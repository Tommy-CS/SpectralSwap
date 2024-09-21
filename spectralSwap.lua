-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

-- Remotes
local SpectreMoveRemote = ReplicatedStorage:WaitForChild("SpectreMoveRemote")
local SpectreAnimateRemote = ReplicatedStorage:WaitForChild("SpectreAnimateRemote")
local throwPuckRemote = ReplicatedStorage:WaitForChild("PuckThrown")

-- Variables
local mainBody
local spectreBody
local Puck
local bodiesInitialized = false
local canSwitch = true
local puckEquipped = false
local maxThrowDistance = 110  -- Maximum throw distance

-- Animation variables
local idleAnimationId = "rbxassetid://101891717057483"
local spectreDownAnimationId = "rbxassetid://80179157312038"
local mainBodyUpAnimationId = "rbxassetid://94162609767158"
local equipPuckAnimationId = "rbxassetid://80388347022124"
local throwPuckAnimationId = "rbxassetid://106356331804708"

local animationTracks = {}

----------------------------------------------------------------------------------------------------
-- ANIMATIONS --------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

local function loadAnimation(humanoid, animationId)
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	return humanoid:LoadAnimation(animation)
end

local function initializeAnimations()
	if spectreBody and spectreBody:FindFirstChildOfClass("Humanoid") then
		local humanoid = spectreBody.Humanoid
		animationTracks.spectreIdle = loadAnimation(humanoid, idleAnimationId)
		animationTracks.spectreDown = loadAnimation(humanoid, spectreDownAnimationId)
		animationTracks.spectreEquipPuck = loadAnimation(humanoid, equipPuckAnimationId)
	end

	if mainBody and mainBody:FindFirstChildOfClass("Humanoid") then
		local humanoid = mainBody.Humanoid
		animationTracks.mainBodyUp = loadAnimation(humanoid, mainBodyUpAnimationId)
		animationTracks.mainBodyThrowPuck = loadAnimation(humanoid, throwPuckAnimationId)
	end
end

local function playAnimation(animationName)
	local track = animationTracks[animationName]
	if track then
		track:Play()
	else
		warn("Animation track not found for: " .. animationName)
	end
end

----------------------------------------------------------------------------------------------------
-- BODY SWITCHING ----------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

-- If the player resets, spectre body disappears.
local function resetSpectreBody()
	if spectreBody then
		spectreBody:Destroy()
		spectreBody = nil
	end
end

-- Clean up old spectre bodies in the workspace
local function cleanUpOldSpectres()
	for _, object in pairs(workspace:GetChildren()) do
		if object.Name == "SpectreBodyTemplate" or object.Name == "SpectreBody" then
			object:Destroy()
		end
	end
end

-- Initialize the spectre body
local function initializeSpectreBody()
	cleanUpOldSpectres()

	-- Clone the spectre body
	local spectreBodyTemplate = ReplicatedStorage:WaitForChild("SpectreBodyTemplate")
	spectreBody = spectreBodyTemplate:Clone()
	spectreBody.Parent = workspace

	local humanoidRootPart = spectreBody:WaitForChild("HumanoidRootPart")
	if not humanoidRootPart then
		warn("HumanoidRootPart missing in spectreBody after cloning.")
		return
	end

	spectreBody.PrimaryPart = humanoidRootPart

	-- Hide the display name of the spectre body
	local humanoid = spectreBody:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.DisplayName = ""
	end

	-- Position the spectre body next to the main body
	if mainBody and mainBody:FindFirstChild("HumanoidRootPart") then
		local mainBodyRoot = mainBody.HumanoidRootPart
		local offset = Vector3.new(5, 0, 0)
		spectreBody:SetPrimaryPartCFrame(mainBodyRoot.CFrame + offset)
	else
		warn("mainBody HumanoidRootPart not found.")
	end

	initializeAnimations()
end

-- Swap positions between mainBody and spectreBody
local function swapPositions()
	if bodiesInitialized and mainBody and spectreBody and canSwitch then
		canSwitch = false

		local mainRootPart = mainBody:FindFirstChild("HumanoidRootPart")
		local spectreRootPart = spectreBody:FindFirstChild("HumanoidRootPart")

		if not mainRootPart or not spectreRootPart then
			warn("HumanoidRootPart missing in mainBody or spectreBody.")
			canSwitch = true
			return
		end

		-- Play the "spectre kneeling down" animation before swapping
		playAnimation("spectreDown")

		-- Swap positions
		local mainCFrame = mainRootPart.CFrame
		local spectreCFrame = spectreRootPart.CFrame

		mainRootPart.CFrame = spectreCFrame
		spectreRootPart.CFrame = mainCFrame

		-- Play the "spectre idle" animation after teleportation
		playAnimation("spectreIdle")
		-- Play the "main body getting up" animation after teleporting
		playAnimation("mainBodyUp")

		SpectreMoveRemote:FireServer(spectreCFrame.Position)
		SpectreAnimateRemote:FireServer("Idle")

		mainRootPart.Anchored = false
		spectreRootPart.Anchored = true

		delay(1, function()
			canSwitch = true
		end)
	end
end

----------------------------------------------------------------------------------------------------
-- TRAJECTORY PATH ---------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

local trajectoryParts = {}

local function clearTrajectoryParts()
	for _, part in ipairs(trajectoryParts) do
		part:Destroy()
	end
	trajectoryParts = {}
end

local function createCylinderBetweenPoints(startPoint, endPoint)
	local distance = (endPoint - startPoint).Magnitude
	local midpoint = (startPoint + endPoint) / 2

	local cylinder = Instance.new("Part")
	cylinder.Shape = Enum.PartType.Cylinder
	cylinder.Size = Vector3.new(0.3, distance, 0.3)
	cylinder.Anchored = true
	cylinder.CanCollide = false
	cylinder.Material = Enum.Material.Neon
	cylinder.Transparency = 0.9
	cylinder.CFrame = CFrame.new(midpoint, endPoint) * CFrame.Angles(math.pi / 2, 0, 0)
	cylinder.BrickColor = BrickColor.new("Bright blue")
	cylinder.Parent = workspace

	return cylinder
end

local function interpolatePoints(points, factor)
	local newPoints = {}

	for i = 1, #points - 1 do
		local startPoint = points[i]
		local endPoint = points[i + 1]
		table.insert(newPoints, startPoint)

		for j = 1, factor do
			local t = j / factor
			local interpolatedPoint = startPoint:Lerp(endPoint, t)
			table.insert(newPoints, interpolatedPoint)
		end
	end

	table.insert(newPoints, points[#points])
	return newPoints
end

local function calculateTrajectoryPoints(startPos, velocity, timeStep, maxTime, direction)
	local points = {}
	local currentPos = startPos
	local currentVelocity = direction * velocity
	local gravity = Vector3.new(0, -workspace.Gravity, 0)

	for t = 0, maxTime, timeStep do
		currentVelocity = currentVelocity + gravity * timeStep
		currentPos = currentPos + currentVelocity * timeStep

		-- Check for wall collision
		local ray = Ray.new(currentPos, currentVelocity.unit * timeStep)
		local hit, hitPos, hitNormal = workspace:FindPartOnRayWithWhitelist(ray, {workspace.TestAssets})

		if hit and hit:IsA("BasePart") then
			if hit:FindFirstChild("isValidWallZone") and hit.isValidWallZone.Value then
				-- Reflect the velocity vector
				currentVelocity = currentVelocity - 2 * currentVelocity:Dot(hitNormal) * hitNormal
				currentPos = hitPos + hitNormal * 0.05
			else
				-- Invalid zone hit
				break
			end
		end

		if currentPos.Y <= 0 then
			break
		end

		table.insert(points, currentPos)
	end

	return interpolatePoints(points, 2)
end

local function createTrajectoryGuide(points)
	clearTrajectoryParts()

	local sphereInterval = 7

	for i = 1, #points - 1 do
		local startPoint = points[i]
		local endPoint = points[i + 1]

		if i % sphereInterval == 0 then
			local sphere = Instance.new("Part")
			sphere.Shape = Enum.PartType.Ball
			sphere.Size = Vector3.new(0.5, 0.5, 0.5)
			sphere.Position = startPoint
			sphere.Anchored = true
			sphere.CanCollide = false
			sphere.Material = Enum.Material.Neon
			sphere.Transparency = 0.5
			sphere.BrickColor = BrickColor.new("Bright blue")
			sphere.Parent = workspace
			table.insert(trajectoryParts, sphere)
		end

		local cylinder = createCylinderBetweenPoints(startPoint, endPoint)
		table.insert(trajectoryParts, cylinder)
	end
end

local function updateTrajectory()
	if Puck and Puck:IsA("Part") and puckEquipped then
		if mainBody and mainBody:FindFirstChild("Head") then
			local head = mainBody.Head
			local offset = head.CFrame.RightVector
			local throwStartPos = head.Position + head.CFrame.LookVector * 1.5 + offset
			local mousePos = mouse.Hit.p
			local direction = (mousePos - throwStartPos).unit
			local initialVelocity = math.min((mousePos - throwStartPos).magnitude * 10, maxThrowDistance)

			local trajectoryPoints = calculateTrajectoryPoints(throwStartPos, initialVelocity, 0.05, 2, direction)

			createTrajectoryGuide(trajectoryPoints)
		else
			warn("Head part not found in mainBody")
		end
	else
		clearTrajectoryParts()
	end
end

----------------------------------------------------------------------------------------------------
-- ZONES ------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

local validZones = {}

local function addValidZones()
	local validAssetsFolder = workspace:WaitForChild("TestAssets")
	for _, zone in ipairs(validAssetsFolder:GetChildren()) do
		if zone:IsA("BasePart") and zone:FindFirstChild("isValidZone") and zone.isValidZone.Value then
			table.insert(validZones, zone)
		end
	end
end

local function isValidZone(position)
	for _, zone in ipairs(validZones) do
		local zonePos = zone.Position
		local zoneSize = zone.Size / 2

		local margin = 1

		if (position.X >= zonePos.X - zoneSize.X - margin) and (position.X <= zonePos.X + zoneSize.X + margin) and
			(position.Y >= zonePos.Y - zoneSize.Y - margin) and (position.Y <= zonePos.Y + zoneSize.Y + margin) and
			(position.Z >= zonePos.Z - zoneSize.Z - margin) and (position.Z <= zonePos.Z + zoneSize.Z + margin) then
			local adjustedPosition = Vector3.new(position.X, zonePos.Y + zoneSize.Y + 3, position.Z)
			return true, adjustedPosition
		end
	end

	return false, position
end

----------------------------------------------------------------------------------------------------
-- PUCK -------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

local touchedConnection = nil

-- Reset the puck to its initial position
local function resetPuck()
	if Puck then
		Puck.Position = mainBody.Head.Position
		Puck.Anchored = true
		Puck.CanCollide = true
		Puck.Velocity = Vector3.new(0, 0, 0)
		Puck.RotVelocity = Vector3.new(0, 0, 0)
	end
	puckEquipped = false
end

-- Function to throw the puck
local function throwPuck()
	if bodiesInitialized and puckEquipped and Puck and Puck:IsA("Part") then
		canSwitch = false  -- Prevent swapping during throw

		-- Play the throwing animation
		playAnimation("mainBodyThrowPuck")

		-- Remove the weld
		local weld = Puck:FindFirstChild("PuckWeld")
		if weld then
			weld:Destroy()
		end

		-- Position the puck in front of the player
		local throwStartPos = mainBody.Head.Position + mainBody.Head.CFrame.LookVector * 3
		Puck.CFrame = CFrame.new(throwStartPos)

		local targetPosition = mouse.Hit.p
		local direction = (targetPosition - throwStartPos).unit

		-- Ensure the throw does not exceed the maximum distance
		local throwVelocity = direction * maxThrowDistance
		Puck.Velocity = throwVelocity
		Puck.Anchored = false

		throwPuckRemote:FireServer(Puck)

		if touchedConnection then
			touchedConnection:Disconnect()
			touchedConnection = nil
		end

		touchedConnection = Puck.Touched:Connect(function(hit)
			if hit:IsA("Terrain") or hit:IsA("BasePart") then
				local isWallZone = hit:FindFirstChild("isValidWallZone") and hit.isValidWallZone.Value
				if isWallZone then
					-- Calculate the surface normal
					local hitNormal = hit.CFrame:VectorToWorldSpace(Vector3.new(0, 0, -1)).unit
					-- Reflect the velocity vector
					local reflectedVelocity = Puck.Velocity - 2 * Puck.Velocity:Dot(hitNormal) * hitNormal
					-- Apply the reflected velocity to the puck
					Puck.Velocity = reflectedVelocity
					Puck.Anchored = false
				else
					Puck.Velocity = Vector3.new(0, 0, 0)
					Puck.Anchored = true

					-- Check if in valid zone
					local isValid, adjustedPosition = isValidZone(Puck.Position)
					if isValid then
						if not spectreBody.PrimaryPart then
							spectreBody.PrimaryPart = spectreBody:FindFirstChild("HumanoidRootPart")
						end
						spectreBody:SetPrimaryPartCFrame(CFrame.new(adjustedPosition))
					else
						warn("Invalid placement! Puck must land in the valid zone.")
						resetPuck()
					end

					Puck:Destroy()
					touchedConnection:Disconnect()
					touchedConnection = nil
					canSwitch = true
					clearTrajectoryParts()
				end
			end
		end)

		puckEquipped = false

	else
		warn("Cannot throw puck; Puck is nil or not a valid part.")
	end
end

-- Function to equip the puck in the player's hand
local updateTrajectoryConnection = nil

local function equipPuck()
	if not mainBody then
		warn("mainBody not found or not initialized.")
		return
	end

	puckEquipped = not puckEquipped

	if puckEquipped then
		playAnimation("spectreEquipPuck")
		task.wait(0.5)

		Puck = ReplicatedStorage:WaitForChild("Puck"):Clone()
		Puck.Parent = workspace

		local rightHand = mainBody:FindFirstChild("RightHand") or mainBody:FindFirstChild("Right Arm")
		if rightHand then
			Puck.CFrame = rightHand.CFrame
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = rightHand
			weld.Part1 = Puck
			weld.Name = "PuckWeld"
			weld.Parent = Puck

			Puck.CanCollide = false
			Puck.Anchored = false

			if updateTrajectoryConnection then
				updateTrajectoryConnection:Disconnect()
				updateTrajectoryConnection = nil
			end
			updateTrajectoryConnection = RunService.RenderStepped:Connect(updateTrajectory)
		else
			warn("RightHand or Right Arm not found in mainBody")
			puckEquipped = false
			Puck:Destroy()
			Puck = nil
		end
	else
		clearTrajectoryParts()
		if Puck then
			local weld = Puck:FindFirstChild("PuckWeld")
			if weld then
				weld:Destroy()
			end
			Puck:Destroy()
			Puck = nil
		end

		if updateTrajectoryConnection then
			updateTrajectoryConnection:Disconnect()
			updateTrajectoryConnection = nil
		end
	end
end

----------------------------------------------------------------------------------------------------
-- PLAYER EVENTS ------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

-- Handle when the player's character is added
local function onCharacterAdded(character)
	mainBody = character

	local humanoid = character:WaitForChild("Humanoid")
	if humanoid then
		local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
		if humanoidRootPart then
			initializeSpectreBody()
			bodiesInitialized = true
			addValidZones()
		else
			warn("HumanoidRootPart not found for character:", character.Name)
		end
	else
		warn("Humanoid not found in character:", character.Name)
	end
end

-- Event when the player leaves the game (remove spectre body)
local function onPlayerRemoving()
	if spectreBody then
		spectreBody:Destroy()
		spectreBody = nil
	end
end

-- Set up event listeners
player.CharacterAdded:Connect(onCharacterAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Handle the case where the character already exists
if player.Character then
	onCharacterAdded(player.Character)
end

----------------------------------------------------------------------------------------------------
-- INPUT HANDLING -----------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

-- Event handling for player input
UIS.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.E then
		equipPuck()
	elseif input.KeyCode == Enum.KeyCode.Q then
		swapPositions()
	end
end)

-- Handle mouse button release to throw the puck
UIS.InputEnded:Connect(function(input)
	if puckEquipped and input.UserInputType == Enum.UserInputType.MouseButton1 then
		throwPuck()
	end
end)
