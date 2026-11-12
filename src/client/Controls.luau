-- Keyboard controls and camera: 1-9/scroll hotbar, E inventory, Q drop, F5 perspective,
-- Ctrl or double-tap W to sprint, Shift to sneak.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local State = require(script.Parent.State)
local Hud = require(script.Parent.Hud)

local Controls = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local NUMBER_KEYS = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.Eight] = 8,
	[Enum.KeyCode.Nine] = 9,
}

local NORMAL_FOV = 70
local SPRINT_FOV = 80

local firstPerson = true
local sprinting = false
local lastForwardTap = 0

local function applyCamera()
	if firstPerson then
		player.CameraMode = Enum.CameraMode.LockFirstPerson
	else
		player.CameraMode = Enum.CameraMode.Classic
		player.CameraMaxZoomDistance = 12
		player.CameraMinZoomDistance = 12
	end
end

local function setCoreGui()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	end)
	-- No reset button: resetting would be a way to escape combat. SetCore can fail until the core
	-- scripts are ready, so retry for a while.
	task.spawn(function()
		for _ = 1, 30 do
			if pcall(StarterGui.SetCore, StarterGui, "ResetButtonCallback", false) then
				return
			end
			task.wait(1)
		end
	end)
end

local function onInput(input: InputObject, processed: boolean)
	if processed then
		return
	end
	local key = input.KeyCode
	local number = NUMBER_KEYS[key]
	if number then
		if Hud.isInventoryOpen() then
			Hud.hotbarSwap(number)
		else
			State.select(number)
		end
	elseif key == Enum.KeyCode.E then
		if not Hud.isDead() then
			Hud.setInventoryOpen(not Hud.isInventoryOpen())
		end
	elseif key == Enum.KeyCode.Escape and Hud.isInventoryOpen() then
		Hud.setInventoryOpen(false)
	elseif key == Enum.KeyCode.Q and not Hud.isInventoryOpen() then
		Remotes.DropItem:FireServer(UserInputService:IsKeyDown(Enum.KeyCode.LeftControl))
	elseif key == Enum.KeyCode.F5 then
		firstPerson = not firstPerson
		applyCamera()
	elseif key == Enum.KeyCode.LeftControl then
		sprinting = true
	elseif key == Enum.KeyCode.W then
		if os.clock() - lastForwardTap < 0.3 then
			sprinting = true
		end
		lastForwardTap = os.clock()
	end
end

local function update(dt: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local sneaking = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and not UserInputService:GetFocusedTextBox()
	if humanoid.MoveDirection.Magnitude < 0.1 or sneaking then
		sprinting = false
	end
	humanoid.WalkSpeed = if sneaking then Config.SNEAK_SPEED elseif sprinting then Config.SPRINT_SPEED else Config.WALK_SPEED
	local targetFov = if sprinting then SPRINT_FOV else NORMAL_FOV
	camera.FieldOfView += (targetFov - camera.FieldOfView) * math.min(1, dt * 10)
end

function Controls.init()
	setCoreGui()
	applyCamera()
	UserInputService.InputBegan:Connect(onInput)
	UserInputService.InputChanged:Connect(function(input, processed)
		if processed or Hud.isInventoryOpen() then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			State.select(State.selected + (if input.Position.Z > 0 then -1 else 1))
		end
	end)
	RunService.RenderStepped:Connect(update)
end

return Controls
