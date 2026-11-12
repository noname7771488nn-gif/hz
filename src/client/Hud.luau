local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Items = require(Shared.Items)
local ItemModels = require(Shared.ItemModels)
local Remotes = require(Shared.Remotes)
local Sounds = require(Shared.Sounds)
local Zones = require(Shared.Zones)

local State = require(script.Parent.State)

local Hud = {}

local player = Players.LocalPlayer

local FONT = Enum.Font.Arcade
local SLOT = 50
local GAP = 4
local PANEL_COLOR = Color3.fromRGB(198, 198, 198)
local SLOT_COLOR = Color3.fromRGB(139, 139, 139)

local CHAT_COLORS = {
	info = "#FFFFFF",
	success = "#55FF55",
	error = "#FF5555",
	death = "#FFAA00",
}

type SlotUi = {
	frame: GuiObject,
	viewport: ViewportFrame,
	count: TextLabel,
	glint: Frame,
	stroke: UIStroke,
	key: string?,
	placeholder: TextLabel?,
}

local hudGui: ScreenGui
local overlayGui: ScreenGui
local hotbar: { SlotUi } = {}
local inventorySlots: { [any]: SlotUi } = {}
local hearts: { Frame } = {}
local armorPips: { Frame } = {}
local armorRow: Frame
local itemNameLabel: TextLabel
local actionLabel: TextLabel
local combatLabel: TextLabel
local zoneLabel: TextLabel
local inventoryRoot: Frame
local tooltip: TextLabel
local deathFrame: Frame
local deathMessage: TextLabel
local hurtFlash: Frame

local inventoryOpen = false
local picked: any = nil
local hovered: any = nil
local actionToken = 0
local nameToken = 0

local function create(className: string, props: { [string]: any }, children: { Instance }?): any
	local instance = Instance.new(className)
	for key, value in props do
		if key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if props.Parent then
		instance.Parent = props.Parent
	end
	return instance
end

local function label(props: { [string]: any }): TextLabel
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Font = props.Font or FONT
	props.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	props.TextStrokeTransparency = props.TextStrokeTransparency or 0.3
	return create("TextLabel", props)
end

-- Item slots -----------------------------------------------------------------------------------------

local function makeSlot(parent: Instance, position: UDim2, button: boolean): SlotUi
	local frame = create(if button then "TextButton" else "Frame", {
		Size = UDim2.fromOffset(SLOT, SLOT),
		Position = position,
		BackgroundColor3 = SLOT_COLOR,
		BackgroundTransparency = if button then 0 else 0.35,
		BorderSizePixel = 0,
		Parent = parent,
	})
	if button then
		frame.Text = ""
		frame.AutoButtonColor = false
	end
	local stroke = create("UIStroke", { Color = Color3.fromRGB(55, 55, 55), Thickness = 2, Parent = frame })
	local viewport = create("ViewportFrame", {
		Size = UDim2.new(1, -8, 1, -8),
		Position = UDim2.fromOffset(4, 4),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(170, 170, 170),
		LightColor = Color3.new(1, 1, 1),
		LightDirection = Vector3.new(-1, -2, -1),
		Parent = frame,
	})
	local glint = create("Frame", {
		Size = UDim2.new(1, -8, 1, -8),
		Position = UDim2.fromOffset(4, 4),
		BackgroundColor3 = Color3.fromRGB(170, 90, 255),
		BackgroundTransparency = 0.8,
		BorderSizePixel = 0,
		Visible = false,
		Parent = frame,
	})
	local count = label({
		Size = UDim2.new(1, -4, 0, 18),
		Position = UDim2.new(0, 0, 1, -18),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 18,
		Text = "",
		ZIndex = 3,
		Parent = frame,
	})
	return { frame = frame, viewport = viewport, count = count, glint = glint, stroke = stroke, key = nil }
end

local function setSlot(ui: SlotUi, stack: Items.Stack?)
	local key = stack and stack.id
	if ui.key ~= key then
		ui.viewport:ClearAllChildren()
		ui.key = key
		if key then
			local def = Items.get(key)
			local model = ItemModels.build(key, 1)
			local direction = Vector3.new(1, 0.8, 1).Unit
			if def and def.kind == "sword" then
				model:PivotTo(CFrame.Angles(math.rad(45), 0, 0))
				direction = Vector3.new(1, 0.1, 0).Unit
			end
			model.Parent = ui.viewport
			local center, size = model:GetBoundingBox()
			local camera = Instance.new("Camera")
			camera.FieldOfView = 30
			local distance = size.Magnitude / 2 / math.tan(math.rad(15)) * 0.85
			camera.CFrame = CFrame.lookAt(center.Position + direction * distance, center.Position)
			camera.Parent = ui.viewport
			ui.viewport.CurrentCamera = camera
		end
	end
	ui.count.Text = if stack and stack.count > 1 then tostring(stack.count) else ""
	ui.glint.Visible = stack ~= nil and stack.ench ~= nil
	if ui.placeholder then
		ui.placeholder.Visible = stack == nil
	end
end

-- Messages -------------------------------------------------------------------------------------------

local generalChannel: TextChannel? = nil

local function escape(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

function Hud.actionBar(text: string, color: Color3?)
	actionToken += 1
	local token = actionToken
	actionLabel.Text = text
	actionLabel.TextColor3 = color or Color3.fromRGB(255, 85, 85)
	actionLabel.TextTransparency = 0
	actionLabel.TextStrokeTransparency = 0.3
	task.delay(2.5, function()
		if token == actionToken then
			actionLabel.Text = ""
		end
	end)
end

function Hud.chat(text: string, kind: string?)
	local color = CHAT_COLORS[kind or "info"] or CHAT_COLORS.info
	if not generalChannel then
		local channels = TextChatService:FindFirstChild("TextChannels")
		generalChannel = channels and channels:FindFirstChild("RBXGeneral") :: TextChannel?
	end
	if generalChannel then
		generalChannel:DisplaySystemMessage(`<font color="{color}">{escape(text)}</font>`)
	else
		Hud.actionBar(text, Color3.fromHex(color))
	end
end

local function showItemName()
	nameToken += 1
	local token = nameToken
	local stack = State.selectedStack()
	if not stack then
		itemNameLabel.Text = ""
		return
	end
	local name = Items.describe(stack)
	itemNameLabel.Text = name
	itemNameLabel.TextColor3 = if stack.ench then Color3.fromRGB(85, 255, 255) else Color3.new(1, 1, 1)
	task.delay(2, function()
		if token == nameToken then
			itemNameLabel.Text = ""
		end
	end)
end

-- Refresh --------------------------------------------------------------------------------------------

local function refreshSlots()
	for i, ui in hotbar do
		setSlot(ui, State.slots[i])
		local selected = i == State.selected
		ui.stroke.Color = if selected then Color3.new(1, 1, 1) else Color3.fromRGB(55, 55, 55)
		ui.stroke.Thickness = if selected then 3 else 2
	end
	for ref, ui in inventorySlots do
		setSlot(ui, State.get(ref))
		ui.stroke.Color = if ref == picked then Color3.fromRGB(255, 220, 60) else Color3.fromRGB(55, 55, 55)
		ui.stroke.Thickness = if ref == picked then 3 else 2
	end
	local points = State.armorPoints()
	armorRow.Visible = points > 0
	for i, pip in armorPips do
		local fill = pip:FindFirstChild("Fill") :: Frame
		fill.Size = UDim2.fromScale(math.clamp(points - (i - 1) * 2, 0, 2) / 2, 1)
	end
end

local function refreshHealth(health: number)
	local value = math.ceil(health)
	for i, heart in hearts do
		local clip = heart:FindFirstChild("Clip") :: Frame
		clip.Size = UDim2.fromScale(math.clamp(value - (i - 1) * 2, 0, 2) / 2, 1)
	end
end

-- Inventory screen -----------------------------------------------------------------------------------

local function showTooltip(ref: any)
	hovered = ref
	local stack = State.get(ref)
	if not stack then
		tooltip.Visible = false
		return
	end
	local name, lines = Items.describe(stack)
	local nameColor = if stack.ench then "#55FFFF" else "#FFFFFF"
	local text = `<font color="{nameColor}">{escape(name)}</font>`
	for _, line in lines do
		text ..= `\n<font color="#AAAAAA">{escape(line)}</font>`
	end
	tooltip.Text = text
	tooltip.Visible = true
end

local function onSlotClicked(ref: any)
	Sounds.playLocal("click", 0.3)
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift) then
		picked = nil
		Remotes.QuickMove:FireServer(ref)
	elseif picked == nil then
		if State.get(ref) then
			picked = ref
		end
	elseif picked == ref then
		picked = nil
	else
		Remotes.MoveSlot:FireServer(picked, ref)
		picked = nil
	end
	refreshSlots()
end

local function addInventorySlot(parent: Instance, ref: any, x: number, y: number, placeholder: string?)
	local ui = makeSlot(parent, UDim2.fromOffset(x, y), true)
	if placeholder then
		ui.placeholder = label({
			Size = UDim2.fromScale(1, 1),
			Text = placeholder,
			TextSize = 12,
			TextColor3 = Color3.fromRGB(90, 90, 90),
			TextStrokeTransparency = 1,
			Parent = ui.frame,
		})
	end
	local button = ui.frame :: TextButton
	button.MouseButton1Click:Connect(function()
		onSlotClicked(ref)
	end)
	button.MouseEnter:Connect(function()
		showTooltip(ref)
	end)
	button.MouseLeave:Connect(function()
		if hovered == ref then
			hovered = nil
			tooltip.Visible = false
		end
	end)
	inventorySlots[ref] = ui
end

function Hud.isInventoryOpen(): boolean
	return inventoryOpen
end

function Hud.setInventoryOpen(open: boolean)
	inventoryOpen = open
	inventoryRoot.Visible = open
	picked = nil
	hovered = nil
	tooltip.Visible = false
	refreshSlots()
end

-- Number keys over a hovered slot swap it with that hotbar slot, as in Minecraft.
function Hud.hotbarSwap(index: number)
	if inventoryOpen and hovered ~= nil and hovered ~= index then
		Remotes.MoveSlot:FireServer(hovered, index)
	end
end

local function buildInventory()
	-- Full-screen modal button frees the mouse while in first person.
	inventoryRoot = create("TextButton", {
		Name = "Inventory",
		Text = "",
		AutoButtonColor = false,
		Modal = true,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Visible = false,
		ZIndex = 5,
		Parent = overlayGui,
	})
	local width = 9 * (SLOT + GAP) - GAP + 24
	local panel = create("Frame", {
		Size = UDim2.fromOffset(width, 342),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = PANEL_COLOR,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = inventoryRoot,
	}, {
		create("UIStroke", { Color = Color3.fromRGB(30, 30, 30), Thickness = 3 }),
	})
	label({
		Size = UDim2.fromOffset(200, 20),
		Position = UDim2.fromOffset(12, 6),
		Text = "Inventory",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 18,
		TextColor3 = Color3.fromRGB(64, 64, 64),
		TextStrokeTransparency = 1,
		Parent = panel,
	})

	for i, slot in Items.ARMOR_SLOTS do
		addInventorySlot(panel, slot, 12 + (i - 1) * (SLOT + GAP), 32, Items.ARMOR_SLOT_NAMES[slot])
	end
	local mainY = 32 + SLOT + 16
	for row = 0, 2 do
		for col = 0, 8 do
			addInventorySlot(panel, 10 + row * 9 + col, 12 + col * (SLOT + GAP), mainY + row * (SLOT + GAP))
		end
	end
	local hotbarY = mainY + 3 * (SLOT + GAP) + 10
	for col = 0, 8 do
		addInventorySlot(panel, col + 1, 12 + col * (SLOT + GAP), hotbarY)
	end

	tooltip = label({
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundColor3 = Color3.fromRGB(20, 4, 30),
		BackgroundTransparency = 0.08,
		RichText = true,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
		ZIndex = 20,
		Parent = overlayGui,
	})
	create("UIPadding", {
		PaddingLeft = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 6),
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
		Parent = tooltip,
	})
	create("UIStroke", { Color = Color3.fromRGB(80, 0, 160), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = tooltip })
end

-- Death screen ---------------------------------------------------------------------------------------

local function buildDeathScreen()
	deathFrame = create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(120, 0, 0),
		BackgroundTransparency = 0.45,
		Visible = false,
		ZIndex = 30,
		Parent = overlayGui,
	})
	label({
		Size = UDim2.new(1, 0, 0, 60),
		Position = UDim2.fromScale(0, 0.28),
		Text = "You died!",
		TextSize = 56,
		ZIndex = 31,
		Parent = deathFrame,
	})
	deathMessage = label({
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromScale(0, 0.4),
		Text = "",
		TextSize = 20,
		ZIndex = 31,
		Parent = deathFrame,
	})
	local respawn = create("TextButton", {
		Size = UDim2.fromOffset(320, 44),
		Position = UDim2.fromScale(0.5, 0.52),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(110, 110, 110),
		BorderSizePixel = 0,
		Font = FONT,
		Text = "Respawn",
		TextSize = 22,
		TextColor3 = Color3.new(1, 1, 1),
		Modal = true,
		ZIndex = 31,
		Parent = deathFrame,
	}, {
		create("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
	})
	respawn.MouseButton1Click:Connect(function()
		Sounds.playLocal("click", 0.4)
		Remotes.Respawn:FireServer()
	end)
end

-- HUD ------------------------------------------------------------------------------------------------

local function buildHud()
	local hotbarWidth = 9 * (SLOT + GAP) - GAP
	local bar = create("Frame", {
		Name = "Hotbar",
		Size = UDim2.fromOffset(hotbarWidth, SLOT),
		Position = UDim2.new(0.5, 0, 1, -12),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Parent = hudGui,
	})
	for i = 1, 9 do
		hotbar[i] = makeSlot(bar, UDim2.fromOffset((i - 1) * (SLOT + GAP), 0), false)
	end

	local heartRow = create("Frame", {
		Size = UDim2.fromOffset(10 * 22, 20),
		Position = UDim2.new(0.5, -hotbarWidth / 2, 1, -12 - SLOT - 8),
		AnchorPoint = Vector2.new(0, 1),
		BackgroundTransparency = 1,
		Parent = hudGui,
	})
	for i = 1, 10 do
		local heart = create("Frame", {
			Size = UDim2.fromOffset(20, 20),
			Position = UDim2.fromOffset((i - 1) * 22, 0),
			BackgroundTransparency = 1,
			Parent = heartRow,
		})
		label({ Size = UDim2.fromScale(1, 1), Text = "♥", Font = Enum.Font.GothamBlack, TextSize = 22, TextColor3 = Color3.fromRGB(40, 40, 40), TextStrokeTransparency = 0.2, Parent = heart })
		local clip = create("Frame", { Name = "Clip", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ClipsDescendants = true, Parent = heart })
		label({ Size = UDim2.fromOffset(20, 20), Text = "♥", Font = Enum.Font.GothamBlack, TextSize = 22, TextColor3 = Color3.fromRGB(230, 30, 30), TextStrokeTransparency = 1, Parent = clip })
		hearts[i] = heart
	end

	armorRow = create("Frame", {
		Size = UDim2.fromOffset(10 * 22, 16),
		Position = UDim2.new(0.5, -hotbarWidth / 2, 1, -12 - SLOT - 32),
		AnchorPoint = Vector2.new(0, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = hudGui,
	})
	for i = 1, 10 do
		local pip = create("Frame", {
			Size = UDim2.fromOffset(14, 14),
			Position = UDim2.fromOffset((i - 1) * 22 + 3, 1),
			BackgroundColor3 = Color3.fromRGB(45, 45, 45),
			BorderSizePixel = 0,
			Parent = armorRow,
		}, {
			create("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1 }),
		})
		create("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(215, 225, 230), BorderSizePixel = 0, Parent = pip })
		armorPips[i] = pip
	end

	itemNameLabel = label({
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.new(0, 0, 1, -12 - SLOT - 58),
		AnchorPoint = Vector2.new(0, 1),
		Text = "",
		TextSize = 20,
		Parent = hudGui,
	})
	actionLabel = label({
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.new(0, 0, 1, -12 - SLOT - 84),
		AnchorPoint = Vector2.new(0, 1),
		Text = "",
		TextSize = 20,
		Parent = hudGui,
	})
	combatLabel = label({
		Size = UDim2.new(1, 0, 0, 26),
		Position = UDim2.fromOffset(0, 12),
		Text = "",
		TextSize = 22,
		TextColor3 = Color3.fromRGB(255, 85, 85),
		Visible = false,
		Parent = hudGui,
	})
	zoneLabel = label({
		Size = UDim2.fromOffset(320, 20),
		Position = UDim2.new(0, 12, 1, -12),
		AnchorPoint = Vector2.new(0, 1),
		Text = "",
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = hudGui,
	})

	-- Crosshair sits on the overlay (no GUI inset) so it matches the locked mouse position.
	for _, size in { UDim2.fromOffset(18, 2), UDim2.fromOffset(2, 18) } do
		create("Frame", {
			Size = size,
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
			Parent = overlayGui,
		})
	end

	hurtFlash = create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(200, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = overlayGui,
	})
end

local function watchCharacter(character: Model)
	deathFrame.Visible = false
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local last = humanoid.Health
	refreshHealth(last)
	humanoid.HealthChanged:Connect(function(health)
		if health < last - 0.01 then
			hurtFlash.BackgroundTransparency = 0.7
			TweenService:Create(hurtFlash, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
		end
		last = health
		refreshHealth(health)
	end)
end

local function updateStatus()
	local remaining = (player:GetAttribute("CombatUntil") or 0) - workspace:GetServerTimeNow()
	if remaining > 0 then
		combatLabel.Visible = true
		combatLabel.Text = `IN COMBAT - {math.ceil(remaining)}s - logging out drops your items!`
	else
		combatLabel.Visible = false
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		local zone = Zones.zoneAt(root.Position)
		local pvp = Zones.pvpAllowedAt(root.Position)
		zoneLabel.Text = `{Zones.DISPLAY[zone]} - {if pvp then "PvP on" else "Safe"}`
		zoneLabel.TextColor3 = if pvp then Color3.fromRGB(255, 120, 120) else Color3.fromRGB(120, 255, 120)
	end

	if tooltip.Visible then
		local mouse = UserInputService:GetMouseLocation()
		tooltip.Position = UDim2.fromOffset(mouse.X + 14, mouse.Y - 10)
	end
end

function Hud.init()
	local playerGui = player:WaitForChild("PlayerGui")
	hudGui = create("ScreenGui", { Name = "BlockCraftHud", ResetOnSpawn = false, IgnoreGuiInset = false, Parent = playerGui })
	overlayGui = create("ScreenGui", { Name = "BlockCraftOverlay", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 10, Parent = playerGui })

	buildHud()
	buildInventory()
	buildDeathScreen()

	State.changed.Event:Connect(function()
		refreshSlots()
		if hovered ~= nil then
			showTooltip(hovered)
		end
	end)
	State.selectionChanged.Event:Connect(function()
		refreshSlots()
		showItemName()
	end)

	Remotes.Notify.OnClientEvent:Connect(function(text: string, kind: string?)
		if kind == "actionbar" then
			Hud.actionBar(text)
		else
			Hud.chat(text, kind)
		end
	end)
	Remotes.Died.OnClientEvent:Connect(function(message: string)
		if inventoryOpen then
			Hud.setInventoryOpen(false)
		end
		deathMessage.Text = message
		deathFrame.Visible = true
	end)

	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)
	RunService.RenderStepped:Connect(updateStatus)
	refreshSlots()
	refreshHealth(Config.MAX_HEALTH)
end

function Hud.isDead(): boolean
	return deathFrame.Visible
end

return Hud
