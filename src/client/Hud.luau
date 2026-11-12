-- The always-on HUD, laid out like Minecraft's: hotbar, hearts, armor, hunger, experience bar,
-- held-item name, crosshair with the attack indicator, sidebar scoreboard and the death screen.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Items = require(Shared.Items)
local Remotes = require(Shared.Remotes)
local Sounds = require(Shared.Sounds)
local Xp = require(Shared.Xp)
local Zones = require(Shared.Zones)

local Pixel = require(script.Parent.Pixel)
local State = require(script.Parent.State)
local Ui = require(script.Parent.Ui)

local Hud = {}

local player = Players.LocalPlayer
local rgb = Color3.fromRGB

-- All positions are GUI pixels inside a 182x80 block that sits on the bottom edge, centred,
-- matching Minecraft's HUD offsets from the bottom of the screen.
local WIDTH, HEIGHT = 182, 80
local HOTBAR_Y = HEIGHT - 22
local XP_Y = HEIGHT - 29
local HEARTS_Y = HEIGHT - 39
local ROW = 10 -- distance between icon rows
local BLINK_SECONDS = 0.6

type Pip = { holder: Frame, baseY: number, sprites: { [string]: GuiObject } }

local bottom: Frame
local hotbar: { Ui.Slot } = {}
local selector: Frame
local offhandFrame: Frame
local offhandSlot: Ui.Slot
local hearts: { Pip } = {}
local absorbs: { Pip } = {}
local armor: { Pip } = {}
local food: { Pip } = {}
local xpFill: Frame
local levelLabel: TextLabel
local itemNameLabel: TextLabel
local actionLabel: TextLabel
local combatLabel: TextLabel
local attackIndicator: Frame
local attackFill: Frame
local sidebar: { [string]: TextLabel } = {}
local deathFrame: Frame
local deathMessage: TextLabel
local deathScore: TextLabel
local hurtFlash: Frame

local actionToken = 0
local nameToken = 0
local slowElapsed = 0
local shakeElapsed = 0
local blinkUntil = 0
local health = Config.MAX_HEALTH

-- A row of ten 9x9 icons, 8 apart. `states` maps a state name to its sprite; the first one
-- listed is drawn at the back. With `fromRight` icon 1 is the rightmost (the hunger bar).
local function pipRow(y: number, states: { { string } }, fromRight: boolean): { Pip }
	local pips = {}
	for i = 1, 10 do
		local x = if fromRight then WIDTH - 9 - (i - 1) * 8 else (i - 1) * 8
		local holder = Ui.frame(bottom, x, y, 9, 9)
		local sprites = {}
		for _, state in states do
			local sprite = Pixel.sprite(state[2])
			sprite.Visible = false
			sprite.Parent = holder
			sprites[state[1]] = sprite
		end
		pips[i] = { holder = holder, baseY = y, sprites = sprites }
	end
	return pips
end

-- `value` counts half icons (20 fills all ten). Icons past the value show `emptyState`, or
-- nothing when it is nil.
local function setPips(pips: { Pip }, value: number, emptyState: string?)
	for i, pip in pips do
		local amount = math.clamp(value - (i - 1) * 2, 0, 2)
		local state = if amount >= 2 then "full" elseif amount >= 1 then "half" else emptyState
		for name, sprite in pip.sprites do
			if name ~= "blink" then
				sprite.Visible = name == state
			end
		end
	end
end

local function moveRow(pips: { Pip }, y: number)
	for _, pip in pips do
		pip.baseY = y
		pip.holder.Position = UDim2.fromOffset(pip.holder.Position.X.Offset, y)
	end
end

function Hud.actionBar(text: string, color: Color3?)
	actionToken += 1
	local token = actionToken
	Ui.setText(actionLabel, Ui.escape(text), color or rgb(255, 85, 85))
	task.delay(2.5, function()
		if token == actionToken then
			Ui.setText(actionLabel, "")
		end
	end)
end

local function showItemName()
	nameToken += 1
	local token = nameToken
	local stack = State.selectedStack()
	if not stack then
		Ui.setText(itemNameLabel, "")
		return
	end
	local name = Items.describe(stack)
	Ui.setText(itemNameLabel, Ui.escape(name), if stack.ench then rgb(85, 255, 255) else Color3.new(1, 1, 1))
	task.delay(2, function()
		if token == nameToken then
			Ui.setText(itemNameLabel, "")
		end
	end)
end

local function refreshSlots()
	for i, slot in hotbar do
		Ui.setSlot(slot, State.inv.slots[i])
	end
	selector.Position = UDim2.fromOffset((State.selected - 1) * 20 - 1, HOTBAR_Y - 1)
	Ui.setSlot(offhandSlot, State.inv.offhand)
	offhandFrame.Visible = State.inv.offhand ~= nil
	setPips(armor, State.armorPoints(), "empty")
	for _, pip in armor do
		pip.holder.Visible = State.armorPoints() > 0
	end
end

-- A hollow rectangle drawn with four strips.
local function outline(parent: Instance, x: number, y: number, w: number, h: number, thickness: number, color: Color3): Frame
	local box = Ui.frame(parent, x, y, w, h)
	Ui.frame(box, 0, 0, w, thickness, color)
	Ui.frame(box, 0, h - thickness, w, thickness, color)
	Ui.frame(box, 0, 0, thickness, h, color)
	Ui.frame(box, w - thickness, 0, thickness, h, color)
	return box
end

local function buildBottom()
	bottom = Ui.create("Frame", {
		Name = "Bottom",
		Size = UDim2.fromOffset(WIDTH, HEIGHT),
		Position = UDim2.new(0.5, -WIDTH / 2, 1, -HEIGHT),
		BackgroundTransparency = 1,
		Parent = Ui.hud,
	})

	-- Hotbar: a dark translucent strip of nine 20x20 cells with grey edges.
	Ui.frame(bottom, 0, HOTBAR_Y, WIDTH, 22, rgb(0, 0, 0), 0.45)
	outline(bottom, 0, HOTBAR_Y, WIDTH, 22, 1, rgb(30, 30, 30))
	for i = 1, 9 do
		outline(bottom, 1 + (i - 1) * 20, HOTBAR_Y + 1, 20, 20, 1, rgb(125, 125, 125))
	end
	selector = outline(bottom, -1, HOTBAR_Y - 1, 24, 24, 1, rgb(30, 30, 30))
	outline(selector, 1, 1, 22, 22, 2, rgb(225, 225, 225))
	for i = 1, 9 do
		hotbar[i] = Ui.bareSlot(bottom, 3 + (i - 1) * 20, HOTBAR_Y + 3)
	end

	offhandFrame = Ui.frame(bottom, -29, HOTBAR_Y, 22, 22, rgb(0, 0, 0), 0.45)
	outline(offhandFrame, 0, 0, 22, 22, 1, rgb(30, 30, 30))
	outline(offhandFrame, 1, 1, 20, 20, 1, rgb(125, 125, 125))
	offhandSlot = Ui.bareSlot(offhandFrame, 3, 3)
	offhandFrame.Visible = false

	-- Experience bar with the level number above it.
	Ui.frame(bottom, 0, XP_Y, WIDTH, 5, rgb(0, 0, 0))
	Ui.frame(bottom, 1, XP_Y + 1, WIDTH - 2, 3, rgb(42, 56, 22))
	xpFill = Ui.frame(bottom, 1, XP_Y + 1, 0, 3, rgb(128, 255, 32))
	levelLabel = Ui.text({
		Size = UDim2.fromOffset(WIDTH, 8),
		Position = UDim2.fromOffset(0, XP_Y - 6),
		TextColor3 = rgb(128, 255, 32),
		Parent = bottom,
	})

	hearts = pipRow(HEARTS_Y, { { "empty", "heart_empty" }, { "half", "heart_half" }, { "full", "heart_full" }, { "blink", "heart_blink" } }, false)
	absorbs = pipRow(HEARTS_Y - ROW, { { "half", "heart_absorb_half" }, { "full", "heart_absorb_full" } }, false)
	armor = pipRow(HEARTS_Y - ROW, { { "empty", "armor_empty" }, { "half", "armor_half" }, { "full", "armor_full" } }, false)
	food = pipRow(HEARTS_Y, { { "empty", "food_empty" }, { "half", "food_half" }, { "full", "food_full" } }, true)

	itemNameLabel = Ui.text({ Size = UDim2.fromOffset(WIDTH, 8), Position = UDim2.fromOffset(0, HEIGHT - 59), Parent = bottom })
	actionLabel = Ui.text({ Size = UDim2.fromOffset(WIDTH * 3, 8), Position = UDim2.fromOffset(-WIDTH, HEIGHT - 72), Parent = bottom })
end

-- Sidebar scoreboard on the right edge, like a Minecraft server's.
local function buildSidebar()
	local rows = {
		{ "kills", "Kills" },
		{ "deaths", "Deaths" },
		{ "streak", "Streak" },
		{ "level", "Level" },
		{ "online", "Online" },
	}
	local width, rowHeight = 92, 9
	local height = (#rows + 3) * rowHeight + 3
	local frame = Ui.create("Frame", {
		Name = "Sidebar",
		Size = UDim2.fromOffset(width, height),
		Position = UDim2.new(1, -width - 1, 0.5, -height / 2),
		BackgroundColor3 = rgb(0, 0, 0),
		BackgroundTransparency = 0.7,
		BorderSizePixel = 0,
		Parent = Ui.hud,
	})
	Ui.frame(frame, 0, 0, width, rowHeight + 1, rgb(0, 0, 0), 0.6)
	Ui.text({
		Size = UDim2.fromOffset(width, 8),
		Position = UDim2.fromOffset(0, 1),
		Text = string.upper(Config.GAME_NAME),
		TextColor3 = rgb(255, 170, 0),
		Parent = frame,
	})
	for i, row in rows do
		local y = 2 + i * rowHeight
		Ui.text({
			Size = UDim2.fromOffset(width - 4, 8),
			Position = UDim2.fromOffset(2, y),
			Text = row[2],
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = frame,
		})
		sidebar[row[1]] = Ui.text({
			Size = UDim2.fromOffset(width - 4, 8),
			Position = UDim2.fromOffset(2, y),
			Text = "0",
			TextColor3 = rgb(255, 85, 85),
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = frame,
		})
	end
	sidebar.zone = Ui.text({
		Size = UDim2.fromOffset(width, 8),
		Position = UDim2.fromOffset(0, 2 + (#rows + 1) * rowHeight),
		Parent = frame,
	})
	sidebar.safety = Ui.text({
		Size = UDim2.fromOffset(width, 8),
		Position = UDim2.fromOffset(0, 2 + (#rows + 2) * rowHeight),
		Parent = frame,
	})
end

local function buildOverlay()
	-- Crosshair: a thin white plus.
	Ui.create("Frame", { Size = UDim2.fromOffset(9, 1), Position = UDim2.new(0.5, -4, 0.5, 0), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = Ui.overlay })
	Ui.create("Frame", { Size = UDim2.fromOffset(1, 9), Position = UDim2.new(0.5, 0, 0.5, -4), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = Ui.overlay })

	-- Attack indicator under the crosshair: fills from the left as the weapon recharges.
	attackIndicator = Ui.create("Frame", {
		Size = UDim2.fromOffset(16, 4),
		Position = UDim2.new(0.5, -8, 0.5, 9),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = Ui.overlay,
	})
	local background = Pixel.sprite("attack_indicator_bg")
	background.Parent = attackIndicator
	attackFill = Ui.create("Frame", { Size = UDim2.fromOffset(0, 4), BackgroundTransparency = 1, ClipsDescendants = true, Parent = attackIndicator })
	local fill = Pixel.sprite("attack_indicator_fill")
	fill.Size = UDim2.fromOffset(16, 4)
	fill.Parent = attackFill

	hurtFlash = Ui.create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = rgb(200, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = Ui.overlay,
	})

	combatLabel = Ui.text({
		Size = UDim2.new(1, 0, 0, 8),
		Position = UDim2.fromOffset(0, 16),
		TextColor3 = rgb(255, 85, 85),
		Visible = false,
		Parent = Ui.hud,
	})

	-- Death screen: red wash, big title, the death message, score and a Respawn button.
	deathFrame = Ui.create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = rgb(110, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 20,
		Parent = Ui.overlay,
	})
	Ui.text({ Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 0.25, 0), Text = "You Died!", TextSize = 16, Parent = deathFrame })
	deathMessage = Ui.text({ Size = UDim2.new(1, 0, 0, 8), Position = UDim2.new(0, 0, 0.25, 26), Parent = deathFrame })
	deathScore = Ui.text({ Size = UDim2.new(1, 0, 0, 8), Position = UDim2.new(0, 0, 0.25, 40), Parent = deathFrame })
	local holder = Ui.create("Frame", { Size = UDim2.fromOffset(200, 20), Position = UDim2.new(0.5, -100, 0.25, 62), BackgroundTransparency = 1, Parent = deathFrame })
	local respawn = Ui.button(holder, 0, 0, 200, 20, "Respawn")
	respawn.Modal = true -- frees the mouse while the camera is locked in first person
	respawn.MouseButton1Click:Connect(function()
		Sounds.playLocal("click", 0.4)
		Remotes.Respawn:FireServer()
	end)
end

local function watchCharacter(character: Model)
	State.dead = false
	deathFrame.Visible = false
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	health = humanoid.Health
	humanoid.HealthChanged:Connect(function(value)
		if value < health - 0.01 then
			blinkUntil = os.clock() + BLINK_SECONDS
			hurtFlash.BackgroundTransparency = 0.75
			TweenService:Create(hurtFlash, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
		end
		health = value
	end)
end

-- Hearts flash a white outline after damage and jitter when health is low.
local function animateHearts(dt: number)
	local now = os.clock()
	local blink = now < blinkUntil and math.floor((blinkUntil - now) / 0.1) % 2 == 1
	shakeElapsed += dt
	local shake = shakeElapsed >= 0.05
	if shake then
		shakeElapsed = 0
	end
	local low = math.ceil(health) <= 4
	for _, pip in hearts do
		pip.sprites.blink.Visible = blink
		if shake then
			local offset = if low then math.random(-1, 1) else 0
			pip.holder.Position = UDim2.fromOffset(pip.holder.Position.X.Offset, pip.baseY + offset)
		end
	end
end

local function attribute(name: string, default: number): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else default
end

-- Called every frame; the slower text updates run a few times a second.
function Hud.update(dt: number)
	local charge = State.charge()
	attackIndicator.Visible = charge < 1 and State.menu == nil and not State.dead
	attackFill.Size = UDim2.fromOffset(math.floor(charge * 16), 4)
	animateHearts(dt)

	slowElapsed += dt
	if slowElapsed < 0.1 then
		return
	end
	slowElapsed = 0

	setPips(hearts, math.ceil(health), "empty")
	setPips(food, attribute("Food", 20), "empty")

	-- Absorption hearts get their own row above the health; armor moves up to make room.
	local absorption = math.ceil(attribute("Absorption", 0))
	setPips(absorbs, absorption, nil)
	moveRow(armor, if absorption > 0 then HEARTS_Y - 2 * ROW else HEARTS_Y - ROW)

	local level, progress = Xp.level(attribute("Xp", 0))
	xpFill.Size = UDim2.fromOffset(math.floor((WIDTH - 2) * progress), 3)
	Ui.setText(levelLabel, if level > 0 then tostring(level) else "")

	local remaining = attribute("CombatUntil", 0) - workspace:GetServerTimeNow()
	combatLabel.Visible = remaining > 0
	if remaining > 0 then
		Ui.setText(combatLabel, `In combat {math.ceil(remaining)}s - logging out drops your items`)
	end

	Ui.setText(sidebar.kills, tostring(attribute("Kills", 0)))
	Ui.setText(sidebar.deaths, tostring(attribute("Deaths", 0)))
	Ui.setText(sidebar.streak, tostring(attribute("Streak", 0)))
	Ui.setText(sidebar.level, tostring(level))
	Ui.setText(sidebar.online, tostring(#Players:GetPlayers()))
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		local pvp = Zones.pvpAllowedAt(root.Position)
		Ui.setText(sidebar.zone, Zones.DISPLAY[Zones.zoneAt(root.Position)], rgb(255, 255, 85))
		Ui.setText(sidebar.safety, if pvp then "PvP on" else "Safe", if pvp then rgb(255, 85, 85) else rgb(85, 255, 85))
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
	Remotes.Died.OnClientEvent:Connect(function(message: string, score: number?)
		State.dead = true
		State.closeMenu()
		Ui.setText(deathMessage, Ui.escape(message))
		Ui.setText(deathScore, `Score: {Ui.colored(tostring(score or 0), "#FFFF55")}`)
		deathFrame.Visible = true
	end)

	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)
	refreshSlots()
end

return Hud
