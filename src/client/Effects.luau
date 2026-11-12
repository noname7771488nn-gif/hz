-- Everything you see when fighting: arm swings, the first-person held items (with the weapon
-- dipping and rising as it recharges), hit particles, the sweep arc, hurt camera tilt and
-- knockback. Also the bot's walk animation and the clouds.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Items = require(Shared.Items)
local ItemModels = require(Shared.ItemModels)
local Remotes = require(Shared.Remotes)
local Sounds = require(Shared.Sounds)

local Pixel = require(script.Parent.Pixel)
local State = require(script.Parent.State)

local Effects = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local SWING_TIME = 0.25
local HURT_TILT_TIME = 0.4

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

-- First-person view ------------------------------------------------------------------------------------
-- The held item at the lower right (or a blocky arm when the hand is empty) and the offhand
-- item at the lower left.
type View = { model: Model?, key: string?, grip: CFrame }
local mainView: View = { model = nil, key = nil, grip = CFrame.identity }
local offView: View = { model = nil, key = nil, grip = CFrame.identity }
local viewSwingStarted = -1
local bobTime = 0

local function buildArm(): Model
	local model = Instance.new("Model")
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
	return model
end

-- Rebuilds one hand's view model when the item in it changes. `side` is 1 for the right hand
-- and -1 for the left.
local function rebuildView(view: View, stack: Items.Stack?, side: number, showArm: boolean)
	local key = if stack then stack.id elseif showArm then "__hand" else nil
	if key == view.key then
		return
	end
	view.key = key
	if view.model then
		view.model:Destroy()
		view.model = nil
	end
	if not key then
		return
	end
	local model: Model
	if stack then
		model = ItemModels.build(stack.id, 1.1)
		-- Sprites are turned so the blade runs forward and up, toward the middle of the screen.
		view.grip = if ItemModels.isSprite(stack.id)
			then CFrame.new(1.3 * side, -1.4, -2.1) * CFrame.Angles(0, math.rad(90 + 25 * side), 0) * CFrame.Angles(0, 0, math.rad(-8))
			else CFrame.new(1.5 * side, -1.25, -2.4) * CFrame.Angles(math.rad(8), math.rad(40 * side), 0)
	else
		model = buildArm()
		view.grip = CFrame.new(1.15, -1.05, -1.7) * CFrame.Angles(math.rad(12), math.rad(-10), 0)
	end
	model.Name = "Viewmodel"
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
		end
	end
	view.model = model
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

local function updateViews(dt: number, now: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local show = humanoid ~= nil and humanoid.Health > 0 and isFirstPerson()
	if not show or not humanoid then
		for _, view in { mainView, offView } do
			if view.model then
				view.model.Parent = nil
			end
		end
		return
	end
	local held, offhand = State.selectedStack(), State.inv.offhand
	rebuildView(mainView, held, 1, true)
	rebuildView(offView, offhand, -1, false)

	local moving = humanoid.MoveDirection.Magnitude > 0.1
	if moving then
		bobTime += dt * humanoid.WalkSpeed / 2
	end
	local bob = if moving then CFrame.new(math.sin(bobTime) * 0.05, -math.abs(math.cos(bobTime)) * 0.06, 0) else CFrame.identity

	local swing = CFrame.identity
	local swingT = (now - viewSwingStarted) / SWING_TIME
	if swingT >= 0 and swingT < 1 then
		local s = math.sin(swingT * math.pi)
		swing = CFrame.new(-0.35 * s, -0.1 * s, -0.3 * s) * CFrame.Angles(-0.8 * s, 0.35 * s, 0)
	end
	-- After a swing the weapon drops out of view and rises back as the attack recharges.
	local equip = State.charge() ^ 3
	local dip = CFrame.new(0, -(1 - equip) * 0.9, 0)

	-- Whatever is being eaten is held up to the mouth and shaken.
	local eating = player:GetAttribute("Eating")
	local chew = CFrame.new(0, 0.35 + math.sin(now * 22) * 0.07, 0.2)
	local eatingMain = eating ~= nil and held ~= nil and held.id == eating
	local eatingOff = eating ~= nil and not eatingMain and offhand ~= nil and offhand.id == eating

	if mainView.model then
		local offset = if eatingMain then CFrame.new(-0.9, 0, 0) * chew else dip * swing
		mainView.model:PivotTo(camera.CFrame * bob * offset * mainView.grip)
		mainView.model.Parent = camera
	end
	if offView.model then
		local offset = if eatingOff then CFrame.new(0.9, 0, 0) * chew else CFrame.identity
		offView.model:PivotTo(camera.CFrame * bob * offset * offView.grip)
		offView.model.Parent = camera
	end
end

-- Particles ------------------------------------------------------------------------------------------
-- Small camera-facing pixel sprites that fly out and fall, like Minecraft's particles.
type Particle = { part: Part, gui: BillboardGui, velocity: Vector3, born: number, life: number, size: number, grow: number }
local particles: { Particle } = {}
local MAX_PARTICLES = 80

local function spawnParticle(key: string, position: Vector3, velocity: Vector3, life: number, size: number, grow: number?)
	if #particles >= MAX_PARTICLES then
		return
	end
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.one * 0.2
	part.Position = position
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(size, size)
	gui.LightInfluence = 0
	gui.MaxDistance = 120
	local sprite = Pixel.sprite(key)
	sprite.Parent = gui
	gui.Parent = part
	part.Parent = camera
	table.insert(particles, { part = part, gui = gui, velocity = velocity, born = os.clock(), life = life, size = size, grow = grow or 0 })
end

local function burst(key: string, center: Vector3, count: number)
	for _ = 1, count do
		local direction = Vector3.new(math.random() - 0.5, math.random() * 0.8, math.random() - 0.5)
		spawnParticle(key, center + direction * 2.5, direction * 14 + Vector3.new(0, 4, 0), 0.35 + math.random() * 0.25, 0.9)
	end
end

local function updateParticles(dt: number, now: number)
	for i = #particles, 1, -1 do
		local particle = particles[i]
		local age = now - particle.born
		if age >= particle.life then
			particle.part:Destroy()
			table.remove(particles, i)
		else
			-- Sweep arcs (which grow) hang in place; everything else falls.
			if particle.grow == 0 then
				particle.velocity -= Vector3.new(0, 30 * dt, 0)
			end
			particle.part.Position += particle.velocity * dt
			local scale = particle.size * (1 + particle.grow * age / particle.life)
			particle.gui.Size = UDim2.fromScale(scale * (if particle.grow > 0 then 2 else 1), scale)
		end
	end
end

local HIT_SOUNDS = { crit = "attackCrit", knockback = "attackKnockback", sweep = "attackSweep", strong = "attackStrong", weak = "attackWeak" }

local function onHit(victim: Model?, kind: string, magic: boolean, attacker: Model?)
	local victimRoot = victim and victim:FindFirstChild("HumanoidRootPart")
	if victimRoot and victimRoot:IsA("BasePart") then
		Sounds.play(HIT_SOUNDS[kind] or "attackStrong", victimRoot.Position)
		if kind == "crit" then
			burst("particle_crit", victimRoot.Position, 10)
		end
		if magic then
			burst("particle_magic", victimRoot.Position, 8)
		end
	end
	local attackerRoot = attacker and attacker:FindFirstChild("HumanoidRootPart")
	if kind == "sweep" and attackerRoot and attackerRoot:IsA("BasePart") then
		local position = attackerRoot.Position + attackerRoot.CFrame.LookVector * 4 + Vector3.new(0, 0.8, 0)
		spawnParticle("particle_sweep", position, Vector3.zero, 0.22, 2.2, 0.5)
	end
	-- A sprint hit ends the sprint, so the next one has to be started again.
	if kind == "knockback" and attacker == player.Character then
		State.sprinting = false
	end
end

-- Hurt tilt ------------------------------------------------------------------------------------------
local hurtAt = -1
local hurtSide = 1

local function watchHealth(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local last = humanoid.Health
	humanoid.HealthChanged:Connect(function(health)
		if health < last - 0.01 then
			hurtAt = os.clock()
			hurtSide = if math.random() < 0.5 then -1 else 1
		end
		last = health
	end)
	-- Our own name tag would float in view when looking up in first person.
	local head = character:WaitForChild("Head", 5)
	local tag = head and head:WaitForChild("NameTag", 5)
	if tag and tag:IsA("BillboardGui") then
		tag.Enabled = false
	end
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

-- Runs right after the camera has moved, so first-person items never lag a frame behind it.
local function update(dt: number)
	local now = os.clock()
	local tilt = (now - hurtAt) / HURT_TILT_TIME
	if tilt >= 0 and tilt < 1 then
		camera.CFrame *= CFrame.Angles(0, 0, math.sin((1 - tilt) ^ 2 * math.pi) * math.rad(7) * hurtSide)
	end

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
	updateViews(dt, now)
	updateParticles(dt, now)
	updateClouds(dt)
end

function Effects.init()
	Remotes.SwingFx.OnClientEvent:Connect(function(character: Model?)
		if character and character ~= player.Character then
			Effects.swing(character)
		end
	end)
	Remotes.HitFx.OnClientEvent:Connect(onHit)
	Remotes.Knockback.OnClientEvent:Connect(function(velocity: Vector3)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			root.AssemblyLinearVelocity = velocity
		end
	end)
	player.CharacterAdded:Connect(function(character)
		mainView.key = nil
		watchHealth(character)
	end)
	if player.Character then
		task.spawn(watchHealth, player.Character)
	end
	buildClouds()
	RunService:BindToRenderStep("BlockCraftEffects", Enum.RenderPriority.Camera.Value + 1, update)
end

return Effects
