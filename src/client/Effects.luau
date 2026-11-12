-- Arm swings, the first-person held item, knockback, the bot's walk animation and clouds.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ItemModels = require(Shared.ItemModels)
local Remotes = require(Shared.Remotes)

local State = require(script.Parent.State)

local Effects = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local SWING_TIME = 0.25

-- Player arm swings ------------------------------------------------------------------------------------
-- Offsets the shoulder joint locally; composes with the walk animation.
local swings: { [Motor6D]: { original: CFrame, started: number, axis: string } } = {}

local function shoulderOf(character: Model): (Motor6D?, string)
	local torso = character:FindFirstChild("Torso")
	local r6 = torso and torso:FindFirstChild("Right Shoulder")
	if r6 and r6:IsA("Motor6D") then
		return r6, "z"
	end
	local arm = character:FindFirstChild("RightUpperArm")
	local r15 = arm and arm:FindFirstChild("RightShoulder")
	if r15 and r15:IsA("Motor6D") then
		return r15, "x"
	end
	return nil, "x"
end

-- Block rigs (the bot) --------------------------------------------------------------------------------
-- Their joints use unrotated frames, so limbs swing about X. Roblox's stock animations don't
-- fit them; this walks their legs and arms from how fast they are moving.
type Rig = { joints: { [string]: Motor6D }, base: { [string]: CFrame }, phase: number, last: Vector3?, speed: number, swungAt: number }
local rigs: { [Model]: Rig } = {}
local RIG_JOINTS = { "Right Shoulder", "Left Shoulder", "Right Hip", "Left Hip" }

local function rigOf(model: Model): Rig?
	local rig = rigs[model]
	if rig then
		return rig
	end
	local torso = model:FindFirstChild("Torso")
	if not torso then
		return nil
	end
	local joints, base = {}, {}
	for _, name in RIG_JOINTS do
		local motor = torso:FindFirstChild(name)
		if not motor or not motor:IsA("Motor6D") then
			return nil -- not fully streamed in yet
		end
		joints[name] = motor
		base[name] = motor.C0
	end
	rig = { joints = joints, base = base, phase = 0, last = nil, speed = 0, swungAt = -1 }
	rigs[model] = rig
	return rig
end

local function animateRigs(dt: number, now: number)
	for model in rigs do
		if not model.Parent then
			rigs[model] = nil
		end
	end
	for _, model in CollectionService:GetTagged("PvPBot") do
		local rig = model:IsA("Model") and rigOf(model)
		local root = model:FindFirstChild("HumanoidRootPart")
		if not rig or not root or not root:IsA("BasePart") then
			continue
		end
		local position = root.Position
		if rig.last and dt > 0 then
			local speed = ((position - rig.last) * Vector3.new(1, 0, 1)).Magnitude / dt
			rig.speed += (speed - rig.speed) * math.min(1, dt * 10)
		end
		rig.last = position
		rig.phase += dt * rig.speed * 0.75
		local stride = math.sin(rig.phase) * math.min(1, rig.speed / Config.WALK_SPEED) * 0.9
		local attack = 0
		local t = (now - rig.swungAt) / SWING_TIME
		if t >= 0 and t < 1 then
			attack = math.sin(t * math.pi) * 1.6
		end
		rig.joints["Right Hip"].C0 = rig.base["Right Hip"] * CFrame.Angles(stride, 0, 0)
		rig.joints["Left Hip"].C0 = rig.base["Left Hip"] * CFrame.Angles(-stride, 0, 0)
		rig.joints["Left Shoulder"].C0 = rig.base["Left Shoulder"] * CFrame.Angles(stride, 0, 0)
		rig.joints["Right Shoulder"].C0 = rig.base["Right Shoulder"] * CFrame.Angles(-stride + attack, 0, 0)
	end
end

function Effects.swing(character: Model?)
	if not character then
		return
	end
	if character:GetAttribute("BlockRig") then
		local rig = rigOf(character)
		if rig then
			rig.swungAt = os.clock()
		end
		return
	end
	local motor, axis = shoulderOf(character)
	if not motor then
		return
	end
	local existing = swings[motor]
	swings[motor] = { original = if existing then existing.original else motor.C0, started = os.clock(), axis = axis }
end

-- First-person viewmodel ------------------------------------------------------------------------------
-- The held item in the bottom-right corner, or a blocky arm when the hand is empty.
local viewmodel: Model? = nil
local viewmodelKey: string? = nil
local viewmodelGrip = CFrame.identity
local viewSwingStarted = -1
local bobTime = 0

local function rebuildViewmodel()
	local stack = State.selectedStack()
	local key = if stack then stack.id else "__hand"
	if key == viewmodelKey and viewmodel then
		return
	end
	viewmodelKey = key
	if viewmodel then
		viewmodel:Destroy()
	end
	local model: Model
	if stack then
		model = ItemModels.build(stack.id, 1.3)
		model.Name = "Viewmodel"
		-- Sprites are turned so the blade runs forward and up, toward the middle of the screen.
		viewmodelGrip = if ItemModels.isSprite(stack.id)
			then CFrame.new(1.25, -1.5, -2.2) * CFrame.Angles(0, math.rad(115), 0) * CFrame.Angles(0, 0, math.rad(-8))
			else CFrame.new(1.5, -1.25, -2.4) * CFrame.Angles(math.rad(8), math.rad(40), 0)
	else
		model = Instance.new("Model")
		model.Name = "Viewmodel"
		local arm = Instance.new("Part")
		arm.Name = "Arm"
		arm.Size = Vector3.new(0.5, 0.5, 1.7)
		arm.Material = Enum.Material.SmoothPlastic
		arm.Color = Color3.fromRGB(198, 150, 108)
		local character = player.Character
		local bodyColors = character and character:FindFirstChildOfClass("BodyColors")
		if bodyColors then
			arm.Color = bodyColors.RightArmColor3
		end
		arm.Parent = model
		model.PrimaryPart = arm
		viewmodelGrip = CFrame.new(1.15, -1.05, -1.7) * CFrame.Angles(math.rad(12), math.rad(-10), 0)
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
		end
	end
	model.Parent = camera
	viewmodel = model
end

local function isFirstPerson(): boolean
	local character = player.Character
	local head = character and character:FindFirstChild("Head") :: BasePart?
	return head ~= nil and (camera.CFrame.Position - head.Position).Magnitude < 1.5
end

function Effects.localSwing()
	viewSwingStarted = os.clock()
	Effects.swing(player.Character)
end

local function updateViewmodel(dt: number, now: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local show = humanoid ~= nil and humanoid.Health > 0 and isFirstPerson()
	if not show then
		if viewmodel then
			viewmodel.Parent = nil
		end
		return
	end
	rebuildViewmodel()
	if not viewmodel or not humanoid then
		return
	end
	viewmodel.Parent = camera

	local moving = humanoid.MoveDirection.Magnitude > 0.1
	if moving then
		bobTime += dt * humanoid.WalkSpeed / 2
	end
	local bob = if moving then CFrame.new(math.sin(bobTime) * 0.05, -math.abs(math.cos(bobTime)) * 0.06, 0) else CFrame.identity
	local swingT = (now - viewSwingStarted) / SWING_TIME
	local swing = CFrame.identity
	if swingT >= 0 and swingT < 1 then
		local s = math.sin(swingT * math.pi)
		swing = CFrame.new(-0.35 * s, -0.1 * s, -0.3 * s) * CFrame.Angles(-0.8 * s, 0.35 * s, 0)
	end
	viewmodel:PivotTo(camera.CFrame * bob * swing * viewmodelGrip)
end

-- Clouds ---------------------------------------------------------------------------------------------
-- Flat blocky clouds drifting over the world, like Minecraft's.
local CLOUD_CELL = 36
local CLOUD_GRID = 28
-- Low enough to sit inside the fog range, so distant clouds fade out instead of popping.
local CLOUD_HEIGHT = Config.WORLD_HEIGHT * Config.BLOCK_SIZE + 40
local cloudFolder: Folder? = nil
local cloudDrift = 0

local function buildClouds()
	local folder = Instance.new("Folder")
	folder.Name = "Clouds"
	local half = CLOUD_GRID / 2
	for z = -half, half - 1 do
		local x = -half
		while x < half do
			if math.noise(x / 5, z / 5, 12.5) > 0.12 then
				-- Merge a row of cloudy cells into one part.
				local run = 0
				while x + run < half and math.noise((x + run) / 5, z / 5, 12.5) > 0.12 do
					run += 1
				end
				local cloud = Instance.new("Part")
				cloud.Anchored = true
				cloud.CanCollide = false
				cloud.CanQuery = false
				cloud.CanTouch = false
				cloud.CastShadow = false
				cloud.Material = Enum.Material.SmoothPlastic
				cloud.Color = Color3.new(1, 1, 1)
				cloud.Transparency = 0.2
				cloud.Size = Vector3.new(run * CLOUD_CELL, 12, CLOUD_CELL)
				cloud:SetAttribute("Offset", Vector3.new((x + run / 2) * CLOUD_CELL, 0, (z + 0.5) * CLOUD_CELL))
				cloud.Parent = folder
				x += run
			else
				x += 1
			end
		end
	end
	folder.Parent = workspace
	cloudFolder = folder
end

local function updateClouds(dt: number)
	if not cloudFolder then
		return
	end
	local span = CLOUD_GRID * CLOUD_CELL
	cloudDrift = (cloudDrift + dt * 3) % span
	-- The cloud sheet follows the camera in whole cells, so it never runs out.
	local focus = camera.CFrame.Position
	local originX = math.floor(focus.X / CLOUD_CELL) * CLOUD_CELL
	local originZ = math.floor(focus.Z / CLOUD_CELL) * CLOUD_CELL
	for _, cloud in cloudFolder:GetChildren() do
		local offset = cloud:GetAttribute("Offset")
		local x = (offset.X + cloudDrift + span / 2) % span - span / 2
		cloud.Position = Vector3.new(originX + x, CLOUD_HEIGHT, originZ + offset.Z)
	end
end

local function update(dt: number)
	local now = os.clock()
	for motor, swing in swings do
		local t = (now - swing.started) / SWING_TIME
		if t >= 1 or not motor.Parent then
			motor.C0 = swing.original
			swings[motor] = nil
		else
			local angle = math.sin(t * math.pi) * 1.4
			motor.C0 = swing.original * (if swing.axis == "z" then CFrame.Angles(0, 0, angle) else CFrame.Angles(angle, 0, 0))
		end
	end
	animateRigs(dt, now)
	updateViewmodel(dt, now)
	updateClouds(dt)
end

function Effects.init()
	Remotes.SwingFx.OnClientEvent:Connect(function(character: Model?)
		if character and character ~= player.Character then
			Effects.swing(character)
		end
	end)
	Remotes.Knockback.OnClientEvent:Connect(function(push: Vector3)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			root.AssemblyLinearVelocity = push
		end
	end)
	State.changed.Event:Connect(rebuildViewmodel)
	State.selectionChanged.Event:Connect(rebuildViewmodel)
	player.CharacterAdded:Connect(function()
		viewmodelKey = nil
	end)
	buildClouds()
	RunService.RenderStepped:Connect(update)
end

return Effects
