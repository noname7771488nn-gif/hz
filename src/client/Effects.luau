-- Arm swings (everyone's), the first-person held item, knockback and hurt feedback.
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

-- Third-person arm swing by offsetting the shoulder joint; composes with the walk animation.
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

function Effects.swing(character: Model?)
	if not character then
		return
	end
	local motor, axis = shoulderOf(character)
	if not motor then
		return
	end
	local existing = swings[motor]
	swings[motor] = { original = if existing then existing.original else motor.C0, started = os.clock(), axis = axis }
end

-- First-person viewmodel: a blocky arm holding the selected item in the bottom-right corner.
local viewmodel: Model? = nil
local viewmodelKey: string? = nil
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
	local model = Instance.new("Model")
	model.Name = "Viewmodel"
	local arm = Instance.new("Part")
	arm.Name = "Arm"
	arm.Size = Vector3.new(0.45, 0.45, 1.6)
	arm.Anchored = true
	arm.CanCollide = false
	arm.CanQuery = false
	arm.CanTouch = false
	arm.CastShadow = false
	arm.Color = Color3.fromRGB(234, 184, 146)
	local character = player.Character
	local bodyColors = character and character:FindFirstChildOfClass("BodyColors")
	if bodyColors then
		arm.Color = bodyColors.RightArmColor3
	end
	arm.Parent = model
	model.PrimaryPart = arm
	if stack then
		local item = ItemModels.build(stack.id, 0.6)
		item:PivotTo(arm.CFrame * CFrame.new(0, 0.15, -0.95) * CFrame.Angles(math.rad(-60), 0, 0))
		for _, part in item:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
			end
		end
		item.Parent = model
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
	local bob = if moving then CFrame.new(math.sin(bobTime) * 0.04, -math.abs(math.cos(bobTime)) * 0.05, 0) else CFrame.identity
	local swingT = (now - viewSwingStarted) / SWING_TIME
	local swing = CFrame.identity
	if swingT >= 0 and swingT < 1 then
		local s = math.sin(swingT * math.pi)
		swing = CFrame.new(-0.25 * s, 0.15 * s, -0.2 * s) * CFrame.Angles(-0.9 * s, 0.3 * s, 0)
	end
	viewmodel:PivotTo(camera.CFrame * CFrame.new(1.05, -1.0, -1.6) * bob * swing * CFrame.Angles(math.rad(10), math.rad(-8), 0))
end

function Effects.init()
	Remotes.SwingFx.OnClientEvent:Connect(function(other: Player)
		if other ~= player then
			Effects.swing(other.Character)
		end
	end)
	Remotes.Knockback.OnClientEvent:Connect(function(push: Vector3)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			root.AssemblyLinearVelocity = Vector3.new(push.X, Config.KNOCKBACK_VERTICAL, push.Z)
		end
	end)
	State.changed.Event:Connect(rebuildViewmodel)
	State.selectionChanged.Event:Connect(rebuildViewmodel)
	player.CharacterAdded:Connect(function()
		viewmodelKey = nil
	end)
	RunService.RenderStepped:Connect(update)
end

return Effects
