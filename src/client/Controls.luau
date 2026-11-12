-- Keyboard controls and camera: 1-9/scroll hotbar, E inventory, T or / chat, Q drop,
-- F5 perspective, Ctrl or double-tap W to sprint, Shift to sneak.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local State = require(script.Parent.State)
local Chat = require(script.Parent.Chat)
local InventoryUi = require(script.Parent.InventoryUi)

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
	local key = input.KeyCode
	if key == Enum.KeyCode.Escape and State.menu then
		State.closeMenu()
		return
	end
	if processed then
		return
	end

	local number = NUMBER_KEYS[key]
	if State.menu then
		-- A menu is open: only its own keys work.
		if State.menu == "inventory" then
			if key == Enum.KeyCode.E then
				State.closeMenu()
			elseif number then
				InventoryUi.hotbarSwap(number)
			end
		elseif State.menu == "kits" and key == Enum.KeyCode.E then
			State.closeMenu()
		end
		return
	end

	if number then
		State.select(number)
	elseif key == Enum.KeyCode.E then
		InventoryUi.toggle()
	elseif key == Enum.KeyCode.T then
		Chat.open("")
	elseif key == Enum.KeyCode.Slash then
		Chat.open("/")
	elseif key == Enum.KeyCode.Q then
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
	local sneaking = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and State.menu == nil
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
		if processed or State.menu then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			State.select(State.selected + (if input.Position.Z > 0 then -1 else 1))
		end
	end)
	RunService.RenderStepped:Connect(update)
end

return Controls
