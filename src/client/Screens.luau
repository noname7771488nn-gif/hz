-- The inventory screen (E) and the kits menu (/kits), built to Minecraft's layout.
-- Clicking works like Minecraft: left click picks up or puts down a stack, right click takes half
-- or places one, Shift-click moves quickly, number keys swap with the hotbar, Q throws an item,
-- and clicking outside the window throws what the mouse is carrying.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Items = require(Shared.Items)
local Remotes = require(Shared.Remotes)
local Sounds = require(Shared.Sounds)

local Pixel = require(script.Parent.Pixel)
local State = require(script.Parent.State)
local Ui = require(script.Parent.Ui)

local Screens = {}

local player = Players.LocalPlayer
local rgb = Color3.fromRGB

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

-- One clickable slot: either an inventory reference or a kit.
type Entry = { slot: Ui.Slot, ref: any, kit: string? }
type Screen = { panel: Frame, entries: { Entry } }

local root: TextButton
local screens: { [string]: Screen } = {}
local current: Screen? = nil
local hovered: Entry? = nil
local carried: Ui.Slot
local preview: ViewportFrame
local previewSignature = ""
local kitReadyAt: { [string]: number } = {}
local kitElapsed = 0

local function addSlot(screen: Screen, ref: any, x: number, y: number, placeholder: string?)
	table.insert(screen.entries, { slot = Ui.slot(screen.panel, x, y, placeholder), ref = ref, kit = nil })
end

-- The 27 inventory slots and the hotbar, as they appear at the bottom of every container.
local function addPlayerSlots(screen: Screen, top: number)
	for row = 0, 2 do
		for col = 0, 8 do
			addSlot(screen, 10 + row * 9 + col, 8 + col * 18, top + row * 18)
		end
	end
	for col = 0, 8 do
		addSlot(screen, col + 1, 8 + col * 18, top + 58)
	end
end

local function title(panel: Frame, text: string, x: number, y: number)
	Ui.text({
		Size = UDim2.fromOffset(100, 8),
		Position = UDim2.fromOffset(x, y),
		Text = text,
		TextColor3 = Ui.TITLE,
		TextXAlignment = Enum.TextXAlignment.Left,
		Shadow = false,
		Parent = panel,
	})
end

-- Kits ------------------------------------------------------------------------------------------------

local function formatDuration(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	local h, m, s = seconds // 3600, (seconds % 3600) // 60, seconds % 60
	if h > 0 then
		return `{h}h {m}m {s}s`
	elseif m > 0 then
		return `{m}m {s}s`
	end
	return `{s}s`
end

local function kitRemaining(name: string): number
	return math.max(0, (kitReadyAt[name] or 0) - workspace:GetServerTimeNow())
end

local function kitTooltip(name: string): string
	local kit = Config.Kits[name]
	local text = Ui.colored(kit.displayName .. " Kit", "#FFAA00")
	for _, item in kit.items do
		local itemName, enchants = Items.describe({ id = item.id, count = item.count, ench = item.ench })
		local line = if item.count > 1 then `{item.count}x {itemName}` else itemName
		text ..= "\n" .. Ui.colored(line, "#FFFFFF")
		for _, enchant in enchants do
			text ..= "\n" .. Ui.colored("  " .. enchant, "#AAAAAA")
		end
	end
	text ..= "\n" .. Ui.colored(`Cooldown: {formatDuration(kit.cooldown)}`, "#5555FF")
	local left = kitRemaining(name)
	if left > 0 then
		text ..= "\n" .. Ui.colored(`Available in {formatDuration(left)}`, "#FF5555")
	else
		text ..= "\n" .. Ui.colored("Click to claim!", "#55FF55")
	end
	return text
end

-- Player preview ----------------------------------------------------------------------------------------

-- Shows a copy of the player's character, with its armor and held item, in the black box.
local function refreshPreview(force: boolean?)
	local inv = State.inv
	local held = State.selectedStack()
	local parts = { if held then held.id else "", if inv.offhand then inv.offhand.id else "" }
	for _, slot in Items.ARMOR_SLOTS do
		table.insert(parts, if inv.armor[slot] then inv.armor[slot].id else "")
	end
	local signature = table.concat(parts, "|")
	if signature == previewSignature and not force then
		return
	end
	previewSignature = signature
	-- The server rebuilds worn armor a moment after the inventory changes.
	task.delay(0.25, function()
		if previewSignature ~= signature then
			return
		end
		preview:ClearAllChildren()
		local character = player.Character
		if not character then
			return
		end
		local archivable = character.Archivable
		character.Archivable = true
		local clone = character:Clone()
		character.Archivable = archivable
		local body = clone and clone:FindFirstChild("HumanoidRootPart")
		if not clone or not body or not body:IsA("BasePart") then
			return
		end
		for _, item in clone:GetDescendants() do
			if item:IsA("BaseScript") or item:IsA("BillboardGui") or item:IsA("Sound") or item:IsA("Fire") then
				item:Destroy()
			elseif item:IsA("BasePart") then
				item.Anchored = true
				-- First person hides the local character; the copy must be visible.
				item.LocalTransparencyModifier = 0
			end
		end
		clone.Parent = preview
		local camera = Instance.new("Camera")
		camera.FieldOfView = 30
		local focus = body.Position - Vector3.new(0, 0.4, 0)
		camera.CFrame = CFrame.lookAt(focus + body.CFrame.LookVector * 12 + body.CFrame.RightVector * 2, focus)
		camera.Parent = preview
		preview.CurrentCamera = camera
	end)
end

-- Refresh --------------------------------------------------------------------------------------------

local function refresh()
	local screen = current
	if not screen then
		return
	end
	for _, entry in screen.entries do
		local kit = entry.kit and Config.Kits[entry.kit]
		if kit and entry.kit then
			-- Kits that include enchanted gear get the enchanted tint on their icon.
			local enchanted = false
			for _, item in kit.items do
				enchanted = enchanted or item.ench ~= nil
			end
			Ui.setSlot(entry.slot, { id = kit.icon, count = 1, ench = if enchanted then {} else nil })
			-- A kit on cooldown has a red slot.
			if entry.slot.back then
				entry.slot.back.BackgroundColor3 = if kitRemaining(entry.kit) > 0 then rgb(165, 85, 85) else rgb(139, 139, 139)
			end
		elseif entry.ref ~= nil then
			Ui.setSlot(entry.slot, State.get(entry.ref))
		end
	end
	Ui.setSlot(carried, State.inv.cursor)
	if screen == screens.inventory then
		refreshPreview()
	end
end

local function updateHover()
	local screen = current
	local found: Entry? = nil
	if screen then
		for _, entry in screen.entries do
			if Ui.mouseOver(entry.slot.frame) then
				found = entry
				break
			end
		end
	end
	if found ~= hovered then
		if hovered and hovered.slot.hover then
			hovered.slot.hover.Visible = false
		end
		hovered = found
		if found and found.slot.hover and (found.kit or found.ref ~= nil) then
			found.slot.hover.Visible = true
		end
	end

	-- Tooltip for the hovered item, unless the mouse is carrying something.
	local text: string? = nil
	if found and not State.inv.cursor then
		if found.kit then
			text = kitTooltip(found.kit)
		elseif found.ref ~= nil then
			local stack = State.get(found.ref)
			text = stack and Ui.describe(stack)
		end
	end
	if text then
		Ui.showTooltip(text)
	else
		Ui.hideTooltip()
	end
end

-- Opening and closing ----------------------------------------------------------------------------------

local function open(name: string)
	if State.dead then
		return
	end
	State.openMenu(name)
	current = screens[name]
	for key, screen in screens do
		screen.panel.Visible = key == name
	end
	root.Visible = true
	previewSignature = ""
	refresh()
end

function Screens.openInventory()
	open("inventory")
end

function Screens.isOpen(): boolean
	return State.menu == "inventory" or State.menu == "kits"
end

local function close()
	-- Whatever the mouse carries or sits in the crafting grid goes back into the inventory.
	State.act("close")
	root.Visible = false
	current = nil
	hovered = nil
	Ui.hideTooltip()
	Ui.setSlot(carried, nil)
end

-- Input --------------------------------------------------------------------------------------------------

local function onInput(input: InputObject)
	local screen = current
	if not screen or not Screens.isOpen() then
		return
	end
	local entry = hovered
	local left = input.UserInputType == Enum.UserInputType.MouseButton1
	local right = input.UserInputType == Enum.UserInputType.MouseButton2
	if left or right then
		if entry and entry.kit then
			if left then
				Sounds.playLocal("click", 0.3)
				Remotes.ClaimKit:FireServer(entry.kit)
			end
		elseif entry and entry.ref ~= nil then
			local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			State.act("click", entry.ref, if left then "left" else "right", shift)
		elseif not Ui.mouseOver(screen.panel) and State.inv.cursor then
			State.act("dropCursor", left)
		end
		return
	end

	local key = input.KeyCode
	local number = NUMBER_KEYS[key]
	-- E closes the screen; Controls handles that along with opening it.
	if entry and entry.ref ~= nil and number then
		State.act("swap", entry.ref, number)
	elseif entry and entry.ref ~= nil and entry.ref ~= "result" and key == Enum.KeyCode.Q then
		State.act("dropSlot", entry.ref, UserInputService:IsKeyDown(Enum.KeyCode.LeftControl))
	end
end

-- Called every frame.
function Screens.update(dt: number)
	if not current then
		return
	end
	updateHover()
	local mouse = Ui.mouse()
	carried.frame.Position = UDim2.fromOffset(mouse.X - 8, mouse.Y - 8)
	if current == screens.kits then
		-- Keep the cooldown colours ticking.
		kitElapsed += dt
		if kitElapsed >= 0.5 then
			kitElapsed = 0
			refresh()
		end
	end
end

-- Construction -------------------------------------------------------------------------------------------

-- Minecraft's survival inventory: armor column, player preview, offhand, 2x2 crafting.
local function buildInventory(): Screen
	local panel = Ui.panel(root, 176, 166)
	local screen: Screen = { panel = panel, entries = {} }

	for i, slot in Items.ARMOR_SLOTS do
		addSlot(screen, slot, 8, 8 + (i - 1) * 18, "slot_" .. slot)
	end
	Ui.frame(panel, 25, 7, 51, 72, rgb(55, 55, 55))
	Ui.frame(panel, 26, 8, 50, 71, Color3.new(1, 1, 1))
	preview = Ui.create("ViewportFrame", {
		Position = UDim2.fromOffset(26, 8),
		Size = UDim2.fromOffset(49, 70),
		BackgroundColor3 = rgb(0, 0, 0),
		BorderSizePixel = 0,
		Ambient = rgb(200, 200, 200),
		LightColor = Color3.new(1, 1, 1),
		LightDirection = Vector3.new(-1, -2, -1),
		Parent = panel,
	})
	addSlot(screen, "offhand", 77, 62, "slot_offhand")

	title(panel, "Crafting", 97, 8)
	addSlot(screen, "craft1", 98, 18)
	addSlot(screen, "craft2", 116, 18)
	addSlot(screen, "craft3", 98, 36)
	addSlot(screen, "craft4", 116, 36)
	local arrow = Ui.frame(panel, 135, 29, 16, 13)
	Pixel.sprite("gui_arrow").Parent = arrow
	addSlot(screen, "result", 154, 28)

	addPlayerSlots(screen, 84)
	return screen
end

-- A chest-style window: rows of kits on top, the player's inventory below.
local function buildKits(): Screen
	local rows = math.max(1, math.ceil(#Config.KIT_ORDER / 9))
	local panel = Ui.panel(root, 176, 114 + rows * 18)
	local screen: Screen = { panel = panel, entries = {} }

	title(panel, "Kits", 8, 6)
	for i = 1, rows * 9 do
		local slot = Ui.slot(panel, 8 + ((i - 1) % 9) * 18, 18 + ((i - 1) // 9) * 18)
		table.insert(screen.entries, { slot = slot, ref = nil, kit = Config.KIT_ORDER[i] })
	end
	title(panel, "Inventory", 8, rows * 18 + 20)
	addPlayerSlots(screen, rows * 18 + 31)
	return screen
end

function Screens.init()
	-- A full-screen dimmed button. Being Modal, it frees the mouse while the camera is locked
	-- in first person.
	root = Ui.create("TextButton", {
		Name = "Screen",
		Text = "",
		AutoButtonColor = false,
		Modal = true,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 5,
		Parent = Ui.overlay,
	})
	screens.inventory = buildInventory()
	screens.kits = buildKits()

	carried = Ui.bareSlot(Ui.overlay, 0, 0)
	carried.frame.ZIndex = 40

	State.registerMenu("inventory", close)
	State.registerMenu("kits", close)
	State.changed.Event:Connect(refresh)
	State.selectionChanged.Event:Connect(refresh)
	UserInputService.InputBegan:Connect(onInput)

	Remotes.KitInfo.OnClientEvent:Connect(function(times: { [string]: number }, openMenu: boolean)
		kitReadyAt = times
		if openMenu then
			open("kits")
		else
			refresh()
		end
	end)
end

return Screens
