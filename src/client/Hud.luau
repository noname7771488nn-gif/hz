-- The always-on HUD: hotbar, hearts, armor, messages, sidebar scoreboard, crosshair, death screen.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Items = require(Shared.Items)
local Remotes = require(Shared.Remotes)
local Sounds = require(Shared.Sounds)
local Zones = require(Shared.Zones)

local Pixel = require(script.Parent.Pixel)
local State = require(script.Parent.State)
local Ui = require(script.Parent.Ui)

local Hud = {}

local player = Players.LocalPlayer

local HOTBAR_WIDTH = 9 * Ui.SLOT + 6
local BOTTOM_HEIGHT = 216
local PIP = 27 -- hearts and armor icons: 9px sprites at 3x
local PIP_STEP = 24

type Pips = { { empty: GuiObject, half: GuiObject, full: GuiObject } }

local bottom: Frame
local hotbar: { Ui.Slot } = {}
local hearts: Pips = {}
local armorPips: Pips = {}
local armorRow: Frame
local itemNameLabel: TextLabel
local actionLabel: TextLabel
local combatLabel: TextLabel
local sidebarLines: { [string]: TextLabel } = {}
local deathFrame: Frame
local deathMessage: TextLabel
local hurtFlash: Frame

local actionToken = 0
local nameToken = 0
local statusElapsed = 0

local function pipRow(y: number, prefix: string): (Frame, Pips)
	local row = Ui.create("Frame", {
		Size = UDim2.fromOffset(10 * PIP_STEP + 3, PIP),
		Position = UDim2.fromOffset(3, y),
		BackgroundTransparency = 1,
		Parent = bottom,
	})
	local pips: Pips = {}
	for i = 1, 10 do
		local holder = Ui.create("Frame", {
			Size = UDim2.fromOffset(PIP, PIP),
			Position = UDim2.fromOffset((i - 1) * PIP_STEP, 0),
			BackgroundTransparency = 1,
			Parent = row,
		})
		local states = {}
		for _, state in { "empty", "half", "full" } do
			local sprite = Pixel.sprite(`{prefix}_{state}`)
			sprite.Visible = state == "empty"
			sprite.Parent = holder
			states[state] = sprite
		end
		pips[i] = states :: any
	end
	return row, pips
end

-- `value` counts half icons: 20 fills all ten.
local function setPips(pips: Pips, value: number)
	for i, pip in pips do
		local amount = math.clamp(value - (i - 1) * 2, 0, 2)
		pip.empty.Visible = amount == 0
		pip.half.Visible = amount == 1
		pip.full.Visible = amount == 2
	end
end

function Hud.actionBar(text: string, color: Color3?)
	actionToken += 1
	local token = actionToken
	actionLabel.Text = text
	actionLabel.TextColor3 = color or Color3.fromRGB(255, 85, 85)
	task.delay(2.5, function()
		if token == actionToken then
			actionLabel.Text = ""
		end
	end)
end

local function showItemName()
	nameToken += 1
	local token = nameToken
	local stack = State.selectedStack()
	if not stack then
		itemNameLabel.Text = ""
		return
	end
	itemNameLabel.Text = (Items.describe(stack))
	itemNameLabel.TextColor3 = if stack.ench then Color3.fromRGB(85, 255, 255) else Color3.new(1, 1, 1)
	task.delay(2, function()
		if token == nameToken then
			itemNameLabel.Text = ""
		end
	end)
end

local function refreshSlots()
	for i, slot in hotbar do
		Ui.setSlot(slot, State.slots[i])
		local selected = i == State.selected
		slot.stroke.Color = if selected then Color3.new(1, 1, 1) else Color3.fromRGB(120, 120, 120)
		slot.stroke.Thickness = if selected then 5 else 3
		slot.frame.ZIndex = if selected then 2 else 1
	end
	local points = State.armorPoints()
	armorRow.Visible = points > 0
	setPips(armorPips, points)
end

local function buildBottom()
	bottom = Ui.create("Frame", {
		Name = "Bottom",
		Size = UDim2.fromOffset(HOTBAR_WIDTH, BOTTOM_HEIGHT),
		Position = UDim2.new(0.5, 0, 1, -8),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Parent = Ui.hud,
	}, {
		Ui.create("UIScale", { Name = "Scale" }),
	})

	local hotbarY = BOTTOM_HEIGHT - Ui.SLOT
	for i = 1, 9 do
		hotbar[i] = Ui.slot(bottom, UDim2.fromOffset(3 + (i - 1) * Ui.SLOT, hotbarY), "hotbar")
	end
	local heartsY = hotbarY - 9 - PIP
	local _, heartPips = pipRow(heartsY, "heart")
	hearts = heartPips
	armorRow, armorPips = pipRow(heartsY - 3 - PIP, "armor")
	armorRow.Visible = false

	itemNameLabel = Ui.label({
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromOffset(0, heartsY - 3 - PIP - 34),
		Text = "",
		TextSize = 22,
		Parent = bottom,
	})
	actionLabel = Ui.label({
		Size = UDim2.new(3, 0, 0, 24),
		Position = UDim2.new(-1, 0, 0, heartsY - 3 - PIP - 66),
		Text = "",
		TextSize = 22,
		Parent = bottom,
	})
end

local function buildSidebar()
	local sidebar = Ui.create("Frame", {
		Name = "Sidebar",
		Size = UDim2.fromOffset(250, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.new(1, -6, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		Parent = Ui.hud,
	}, {
		Ui.create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }),
		Ui.create("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
		Ui.create("UIScale", { Name = "Scale" }),
	})
	local order = 0
	local function line(name: string, text: string, color: Color3?, centered: boolean?)
		order += 1
		sidebarLines[name] = Ui.label({
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 24),
			Text = text,
			TextSize = 18,
			TextColor3 = color or Color3.new(1, 1, 1),
			TextXAlignment = if centered then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left,
			Parent = sidebar,
		})
	end
	line("title", string.upper(Config.GAME_NAME), Color3.fromRGB(255, 170, 0), true)
	line("version", Config.MC_VERSION .. " PvP", Color3.fromRGB(170, 170, 170), true)
	line("gap1", "")
	line("kills", "")
	line("deaths", "")
	line("streak", "")
	line("gap2", "")
	line("online", "")
	line("zone", "")
	line("gap3", "")
	line("hint", "/kits  /pvp  /rtp", Color3.fromRGB(255, 255, 85), true)
end

local function buildOverlay()
	-- Crosshair.
	for _, size in { UDim2.fromOffset(20, 2), UDim2.fromOffset(2, 20) } do
		Ui.create("Frame", {
			Size = size,
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			Parent = Ui.overlay,
		})
	end

	hurtFlash = Ui.create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(200, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = Ui.overlay,
	})

	combatLabel = Ui.label({
		Size = UDim2.new(1, 0, 0, 28),
		Position = UDim2.fromOffset(0, 48),
		Text = "",
		TextSize = 22,
		TextColor3 = Color3.fromRGB(255, 85, 85),
		Visible = false,
		Parent = Ui.hud,
	})

	deathFrame = Ui.create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(120, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 30,
		Parent = Ui.overlay,
	})
	Ui.label({
		Size = UDim2.new(1, 0, 0, 64),
		Position = UDim2.fromScale(0, 0.28),
		Text = "You Died!",
		TextSize = 60,
		ZIndex = 31,
		Parent = deathFrame,
	})
	deathMessage = Ui.label({
		Size = UDim2.new(1, 0, 0, 26),
		Position = UDim2.fromScale(0, 0.41),
		Text = "",
		TextSize = 22,
		ZIndex = 31,
		Parent = deathFrame,
	})
	local respawn = Ui.create("TextButton", {
		Size = UDim2.fromOffset(360, 48),
		Position = UDim2.fromScale(0.5, 0.52),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(112, 112, 112),
		BorderSizePixel = 0,
		Font = Ui.FONT,
		Text = "Respawn",
		TextSize = 22,
		TextColor3 = Color3.new(1, 1, 1),
		Modal = true,
		ZIndex = 31,
		Parent = deathFrame,
	}, {
		Ui.create("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
	})
	respawn.MouseButton1Click:Connect(function()
		Sounds.playLocal("click", 0.4)
		Remotes.Respawn:FireServer()
	end)
end

local function watchCharacter(character: Model)
	State.dead = false
	deathFrame.Visible = false
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local last = humanoid.Health
	setPips(hearts, math.ceil(last))
	humanoid.HealthChanged:Connect(function(health)
		if health < last - 0.01 then
			hurtFlash.BackgroundTransparency = 0.7
			TweenService:Create(hurtFlash, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
		end
		last = health
		setPips(hearts, math.ceil(health))
	end)
end

-- Called every frame; the slower text updates run a few times a second.
function Hud.update(dt: number)
	Ui.updateTooltip()
	statusElapsed += dt
	if statusElapsed < 0.2 then
		return
	end
	statusElapsed = 0

	local scale = Ui.scale()
	for _, name in { "Bottom", "Sidebar" } do
		local frame = Ui.hud:FindFirstChild(name)
		if frame then
			frame.Scale.Scale = scale
		end
	end

	local remaining = (player:GetAttribute("CombatUntil") or 0) - workspace:GetServerTimeNow()
	combatLabel.Visible = remaining > 0
	if remaining > 0 then
		combatLabel.Text = `IN COMBAT - {math.ceil(remaining)}s - logging out drops your items!`
	end

	sidebarLines.kills.Text = `Kills: {player:GetAttribute("Kills") or 0}`
	sidebarLines.deaths.Text = `Deaths: {player:GetAttribute("Deaths") or 0}`
	sidebarLines.streak.Text = `Streak: {player:GetAttribute("Streak") or 0}`
	sidebarLines.online.Text = `Online: {#Players:GetPlayers()}`
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		local pvp = Zones.pvpAllowedAt(root.Position)
		sidebarLines.zone.Text = Zones.DISPLAY[Zones.zoneAt(root.Position)] .. if pvp then " - PvP" else " - Safe"
		sidebarLines.zone.TextColor3 = if pvp then Color3.fromRGB(255, 85, 85) else Color3.fromRGB(85, 255, 85)
	end
end

function Hud.init()
	buildBottom()
	buildSidebar()
	buildOverlay()

	State.changed.Event:Connect(refreshSlots)
	State.selectionChanged.Event:Connect(function()
		refreshSlots()
		showItemName()
	end)
	Remotes.Died.OnClientEvent:Connect(function(message: string)
		State.dead = true
		State.closeMenu()
		deathMessage.Text = message
		deathFrame.Visible = true
	end)

	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)
	refreshSlots()
	setPips(hearts, Config.MAX_HEALTH)
end

return Hud
