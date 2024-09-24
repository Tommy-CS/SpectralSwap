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
	end

	if mainBody and mainBody:FindFirstChildOfClass("Humanoid") then
		local humanoid = mainBody.Humanoid
		animationTracks.mainBodyUp = loadAnimation(humanoid, mainBodyUpAnimationId)
		animationTracks.mainBodyThrowPuck = loadAnimation(humanoid, throwPuckAnimationId)
		animationTracks.mainBodyEquipPuck = loadAnimation(humanoid, equipPuckAnimationId)
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

local function stopAnimation(animationName)
	local track = animationTracks[animationName]
	if track and track.IsPlaying then
		track:Stop()
	else
		warn("Animation track not found or not playing for: " .. animationName)
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

-- Variables
local trajectoryParts = {}  -- Store trajectory parts like cylinders
local trajectorySpheres = {}  -- Store trajectory spheres

-- Function to clear trajectory points
local function clearTrajectoryPoints()
	for _, sphere in ipairs(trajectorySpheres) do
		sphere:Destroy()
	end
	trajectorySpheres = {}

	for _, part in ipairs(trajectoryParts) do
		part:Destroy()
	end
	trajectoryParts = {}
end

-- Function to interpolate between points for smooth trajectory visualization
local function interpolatePoints(points, factor)
	local newPoints = {}

	for i = 1, #points - 1 do
		local startPoint = points[i]
		local endPoint = points[i + 1]
		table.insert(newPoints, startPoint)

		-- Linear interpolation between points
		for j = 1, factor do
			local t = j / factor
			local interpolatedPoint = startPoint:Lerp(endPoint, t)
			table.insert(newPoints, interpolatedPoint)
		end
	end

	table.insert(newPoints, points[#points])
	return newPoints
end

-- Function to create a cylinder between two points
local function createCylinderBetweenPoints(startPoint, endPoint)
	local distance = (endPoint - startPoint).Magnitude
	local midpoint = (startPoint + endPoint) / 2

	local cylinder = Instance.new("Part")
	cylinder.Shape = Enum.PartType.Cylinder
	cylinder.Size = Vector3.new(0.3, distance, 0.3) -- Adjust the size to fit your visual style
	cylinder.Anchored = true
	cylinder.CanCollide = false
	cylinder.CFrame = CFrame.new(midpoint, endPoint) * CFrame.Angles(math.pi / 2, 0, 0)
	cylinder.BrickColor = BrickColor.new("Bright blue")
	cylinder.Material = Enum.Material.Neon
	cylinder.Transparency = 0.7 -- Adjust transparency for visual clarity
	cylinder.Parent = workspace

	return cylinder
end

-- Function to calculate trajectory points based on initial position and velocity
local function calculateTrajectoryPoints(startPos, velocity, timeStep, maxTime, direction)
	local points = {}
	local currentPos = startPos
	local currentVelocity = direction * velocity
	local gravity = Vector3.new(0, -workspace.Gravity, 0)

	local bounces = 0
	local maxBounces = 1  -- Limit to 1 bounce for simplicity

	for t = 0, maxTime, timeStep do
		-- Apply gravity to velocity
		currentVelocity = currentVelocity + gravity * timeStep

		-- Calculate next position
		local nextPos = currentPos + currentVelocity * timeStep

		-- Check for wall collisions using raycasting
		local ray = Ray.new(currentPos, nextPos - currentPos)
		local hit, hitPos, hitNormal = workspace:FindPartOnRayWithWhitelist(ray, {workspace.TestAssets})

		if hit and hit:IsA("BasePart") and bounces < maxBounces then
			if hit:FindFirstChild("isValidWallZone") and hit.isValidWallZone.Value then
				-- Reflect velocity if a valid wall zone is hit
				currentVelocity = currentVelocity - 2 * currentVelocity:Dot(hitNormal) * hitNormal
				currentPos = hitPos + hitNormal * 0.05  -- Small offset to prevent sticking
				bounces = bounces + 1
			else
				-- Stop if an invalid zone is hit
				break
			end
		else
			currentPos = nextPos
		end

		-- Stop if the ground or an invalid zone is hit
		if currentPos.Y <= 0 then
			break
		end

		-- Add calculated point to the trajectory
		table.insert(points, currentPos)
	end

	return interpolatePoints(points, 5)  -- Adjust interpolation factor as needed
end

-- Function to create a trajectory guide using points and connecting cylinders
local function createTrajectoryGuide(points)
	-- Clear any previously drawn parts
	clearTrajectoryPoints()

	-- Create cylinders and fewer spheres
	local sphereInterval = 5  -- Set how many points to skip before placing a sphere

	for i = 1, #points - 1 do
		local startPoint = points[i]
		local endPoint = points[i + 1]

		-- Create a sphere at every sphereInterval point
		if i % sphereInterval == 0 then
			local sphere = Instance.new("Part")
			sphere.Shape = Enum.PartType.Ball
			sphere.Size = Vector3.new(0.5, 0.5, 0.5)  -- Larger spheres for visibility
			sphere.Position = startPoint
			sphere.Anchored = true
			sphere.CanCollide = false
			sphere.Material = Enum.Material.Neon
			sphere.Transparency = 0.5
			sphere.BrickColor = BrickColor.new("Bright blue")
			sphere.Parent = workspace
			table.insert(trajectorySpheres, sphere)
		end

		-- Create a cylinder connecting the points
		local cylinder = createCylinderBetweenPoints(startPoint, endPoint)
		table.insert(trajectoryParts, cylinder)
	end
end

-- Function to update trajectory based on puck and mouse position
local function updateTrajectory()
	-- Clear trajectory if puck isn't equipped
	clearTrajectoryPoints()

	if Puck and Puck:IsA("Part") and puckEquipped then
		-- Dynamically check for Head or Torso in the mainBody
		local headOrTorso = mainBody:FindFirstChild("Head") or mainBody:FindFirstChild("UpperTorso") or mainBody:FindFirstChild("Torso")
		if headOrTorso then
			-- Offset to adjust the start of the trajectory
			local offset = headOrTorso.CFrame.RightVector  -- Adjust to suit positioning
			local throwStartPos = headOrTorso.Position + headOrTorso.CFrame.LookVector * 1.5 + offset
			local mousePos = mouse.Hit.p
			local direction = (mousePos - throwStartPos).unit
			local initialVelocity = math.min((mousePos - throwStartPos).magnitude * 10, maxThrowDistance)

			-- Calculate the trajectory points
			local trajectoryPoints = calculateTrajectoryPoints(throwStartPos, initialVelocity, 0.05, 2, direction)

			-- Create visual trajectory guide
			createTrajectoryGuide(trajectoryPoints)
		else
			warn("Head or Torso part not found in mainBody.")
		end
	end
end

-- Update trajectory in real-time when mouse moves or puck is equipped
UIS.InputChanged:Connect(function(input)
	if puckEquipped and input.UserInputType == Enum.UserInputType.MouseMovement then
		updateTrajectory()
	end
end)

-- Call updateTrajectory manually to initialize
if puckEquipped then
	updateTrajectory()
end

-- Function to equip the puck in the player's hand
local updateTrajectoryConnection = nil

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

		local margin = 1  -- Allowable margin around the zone

		-- Check if the puck's position is within the valid zone's bounds
		if (position.X >= zonePos.X - zoneSize.X - margin) and (position.X <= zonePos.X + zoneSize.X + margin) and
			(position.Y >= zonePos.Y - zoneSize.Y - margin) and (position.Y <= zonePos.Y + zoneSize.Y + margin) and
			(position.Z >= zonePos.Z - zoneSize.Z - margin) and (position.Z <= zonePos.Z + zoneSize.Z + margin) then

			-- Raycast downward to detect the top of the zone
			local origin = position + Vector3.new(0, 5, 0)  -- Start slightly above the position
			local direction = Vector3.new(0, -1000, 0)  -- Cast downwards

			local raycastParams = RaycastParams.new()
			raycastParams.FilterDescendantsInstances = {zone}
			raycastParams.FilterType = Enum.RaycastFilterType.Whitelist

			local result = workspace:Raycast(origin, direction, raycastParams)
			local groundPosition
			if result then
				groundPosition = result.Position  -- Position where the ray hit the valid zone
			else
				groundPosition = position  -- Use the input position if no hit detected
			end

			-- Calculate the adjusted position for the spectre body to stand on top of the valid zone
			local adjustedPosition
			if spectreBody and spectreBody.PrimaryPart then
				local humanoid = spectreBody:FindFirstChildOfClass("Humanoid")
				if humanoid then
					adjustedPosition = groundPosition + Vector3.new(0, humanoid.HipHeight + zone.Size.Y / 2, 0)
				else
					adjustedPosition = groundPosition + Vector3.new(0, zone.Size.Y / 2, 0)
				end
			else
				adjustedPosition = groundPosition + Vector3.new(0, zone.Size.Y / 2, 0)
			end

			return true, adjustedPosition
		end
	end

	-- Return false if no valid zone is detected
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
		canSwitch = false  -- Prevent switching during throw

		-- Play the throwing animation
		playAnimation("mainBodyThrowPuck")
		stopAnimation("mainBodyEquipPuck")

		-- Remove the weld from the puck
		local weld = Puck:FindFirstChild("PuckWeld")
		if weld then
			weld:Destroy()
		end

		-- Position the puck in front of the player
		local throwStartPos = mainBody.Head.Position + mainBody.Head.CFrame.LookVector * 3
		Puck.CFrame = CFrame.new(throwStartPos)

		local targetPosition = mouse.Hit.p
		local direction = (targetPosition - throwStartPos).unit

		-- Ensure the throw doesn't exceed the maximum distance
		local throwVelocity = direction * maxThrowDistance
		Puck.Velocity = throwVelocity
		Puck.Anchored = false

		throwPuckRemote:FireServer(Puck)

		-- Disconnect previous touch event
		if touchedConnection then
			touchedConnection:Disconnect()
			touchedConnection = nil
		end

		touchedConnection = Puck.Touched:Connect(function(hit)
			if hit:IsA("Terrain") or hit:IsA("BasePart") then
				local isWallZone = hit:FindFirstChild("isValidWallZone") and hit.isValidWallZone.Value
				if isWallZone then
					-- Reflect the puck's velocity on a valid wall zone
					local hitNormal = hit.CFrame:VectorToWorldSpace(Vector3.new(0, 0, -1)).unit
					local reflectedVelocity = Puck.Velocity - 2 * Puck.Velocity:Dot(hitNormal) * hitNormal
					Puck.Velocity = reflectedVelocity
					Puck.Anchored = false
				else
					-- Stop the puck in invalid zones
					Puck.Velocity = Vector3.new(0, 0, 0)
					Puck.Anchored = true

					-- Check if the puck is in a valid zone
					local isValid, adjustedPosition = isValidZone(Puck.Position)
					if isValid then
						if not spectreBody.PrimaryPart then
							spectreBody.PrimaryPart = spectreBody:FindFirstChild("HumanoidRootPart")
						end
						spectreBody:SetPrimaryPartCFrame(CFrame.new(adjustedPosition))

						-- Play the spectre down animation
						playAnimation("spectreDown")
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
		-- Equip the puck
		playAnimation("mainBodyEquipPuck")  -- Play the equip animation

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
			-- Stop the animation if equipping fails
			stopAnimation("mainBodyEquipPuck")
		end
	else
		-- Unequip the puck
		clearTrajectoryPoints()
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

		-- Stop the equip animation when unequipping
		stopAnimation("mainBodyEquipPuck")
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