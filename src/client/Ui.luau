-- Shared UI building blocks, laid out the way Minecraft lays out its GUI: everything is positioned
-- in "GUI pixels" inside a root frame that is scaled up by a whole number (GUI scale 1-3), so
-- 16x16 sprites always land on whole screen pixels.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Items = require(ReplicatedStorage:WaitForChild("Shared").Items)

local Pixel = require(script.Parent.Pixel)

local Ui = {}

Ui.FONT = Enum.Font.Arcade
Ui.TEXT = 8 -- text height in GUI pixels
Ui.S = 3 -- current GUI scale
Ui.hud = nil :: any -- root frame for the always-on HUD, in GUI pixels
Ui.overlay = nil :: any -- root frame for menus, the crosshair and full-screen effects

local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
Ui.PANEL = rgb(198, 198, 198)
Ui.TITLE = rgb(64, 64, 64)

export type Slot = {
	frame: Frame,
	icon: Frame,
	count: TextLabel,
	hover: Frame?,
	key: string?,
	enchanted: boolean,
	placeholder: GuiObject?,
}

local roots: { { frame: Frame, scale: UIScale } } = {}
local tooltip: TextLabel

function Ui.create(className: string, props: { [string]: any }, children: { Instance }?): any
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

-- A plain coloured rectangle at (x, y) with size (w, h), all in GUI pixels.
function Ui.frame(parent: Instance, x: number, y: number, w: number, h: number, color: Color3?, transparency: number?): Frame
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	frame.Position = UDim2.fromOffset(x, y)
	frame.Size = UDim2.fromOffset(w, h)
	frame.BackgroundColor3 = color or WHITE
	frame.BackgroundTransparency = if color then transparency or 0 else 1
	frame.Parent = parent
	return frame
end

function Ui.escape(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

function Ui.colored(text: string, hex: string): string
	return `<font color="{hex}">{Ui.escape(text)}</font>`
end

local function shade(color: Color3): Color3
	return Color3.new(color.R * 0.25, color.G * 0.25, color.B * 0.25)
end

-- Minecraft-style text: the pixel font with a dark drop shadow one GUI pixel down and right.
-- The returned label is the shadow; the visible text is its child "Main". Change the text with
-- Ui.setText so both stay in step. Pass Shadow = false for plain text (window titles).
function Ui.text(props: { [string]: any }): TextLabel
	local color = props.TextColor3 or WHITE
	local shadow = props.Shadow ~= false
	local text = props.Text or ""
	props.Shadow = nil
	props.Text = ""
	props.Font = props.Font or Ui.FONT
	props.TextSize = props.TextSize or Ui.TEXT
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.BorderSizePixel = 0
	props.TextStrokeTransparency = 1
	props.RichText = true
	props.TextColor3 = if shadow then shade(color) else color
	if shadow and props.Position then
		props.Position += UDim2.fromOffset(1, 1)
	end
	local label = Ui.create("TextLabel", props)
	if shadow then
		Ui.create("TextLabel", {
			Name = "Main",
			Size = UDim2.fromScale(1, 1),
			Position = UDim2.fromOffset(-1, -1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Font = props.Font,
			TextSize = props.TextSize,
			TextColor3 = color,
			TextStrokeTransparency = 1,
			RichText = true,
			TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Center,
			TextYAlignment = props.TextYAlignment or Enum.TextYAlignment.Center,
			TextWrapped = props.TextWrapped == true,
			Parent = label,
		})
	end
	Ui.setText(label, text)
	return label
end

-- Sets the (rich) text, and optionally the colour, of a label made by Ui.text.
function Ui.setText(label: TextLabel, text: string, color: Color3?)
	local main = label:FindFirstChild("Main")
	if main and main:IsA("TextLabel") then
		main.Text = text
		-- The shadow is one flat colour, so it gets the text without its colour tags.
		label.Text = (text:gsub("<[^>]*>", ""))
		if color then
			main.TextColor3 = color
			label.TextColor3 = shade(color)
		end
	else
		label.Text = text
		if color then
			label.TextColor3 = color
		end
	end
end

function Ui.setTextTransparency(label: TextLabel, transparency: number)
	label.TextTransparency = transparency
	local main = label:FindFirstChild("Main")
	if main and main:IsA("TextLabel") then
		main.TextTransparency = transparency
	end
end

-- A light grey Minecraft window: black outline, white highlight on the top and left, dark
-- shadow on the bottom and right. Children are positioned in the window's own GUI pixels.
function Ui.panel(parent: Instance, w: number, h: number): Frame
	local panel = Ui.frame(parent, 0, 0, w, h, rgb(0, 0, 0))
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	Ui.frame(panel, 1, 1, w - 2, h - 2, rgb(85, 85, 85))
	Ui.frame(panel, 1, 1, w - 4, h - 4, WHITE)
	Ui.frame(panel, 3, 3, w - 6, h - 6, Ui.PANEL)
	return panel
end

-- An inventory slot whose 16x16 item area starts at (x, y): dark top-left edge, white
-- bottom-right edge, like Minecraft's.
function Ui.slot(parent: Instance, x: number, y: number, placeholder: string?): Slot
	local frame = Ui.frame(parent, x - 1, y - 1, 18, 18, rgb(55, 55, 55))
	Ui.frame(frame, 1, 1, 17, 17, WHITE)
	Ui.frame(frame, 1, 1, 16, 16, rgb(139, 139, 139))
	local silhouette: GuiObject? = nil
	if placeholder then
		local holder = Ui.frame(frame, 1, 1, 16, 16)
		Pixel.sprite(placeholder).Parent = holder
		silhouette = holder
	end
	local icon = Ui.frame(frame, 1, 1, 16, 16)
	local count = Ui.text({
		Size = UDim2.fromOffset(17, 8),
		Position = UDim2.fromOffset(1, 9),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = frame,
	})
	local hover = Ui.frame(frame, 1, 1, 16, 16, WHITE, 0.5)
	hover.Visible = false
	return { frame = frame, icon = icon, count = count, hover = hover, key = nil, enchanted = false, placeholder = silhouette }
end

-- Just an item icon and its count, with no slot drawn (hotbar and the carried stack).
function Ui.bareSlot(parent: Instance, x: number, y: number): Slot
	local frame = Ui.frame(parent, x, y, 16, 16)
	local icon = Ui.frame(frame, 0, 0, 16, 16)
	local count = Ui.text({
		Size = UDim2.fromOffset(17, 8),
		Position = UDim2.fromOffset(0, 8),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = frame,
	})
	return { frame = frame, icon = icon, count = count, hover = nil, key = nil, enchanted = false, placeholder = nil }
end

function Ui.setSlot(slot: Slot, stack: Items.Stack?)
	local key = stack and stack.id
	local enchanted = stack ~= nil and stack.ench ~= nil
	if slot.key ~= key or slot.enchanted ~= enchanted then
		slot.key = key
		slot.enchanted = enchanted
		Pixel.setIcon(slot.icon, key, enchanted)
	end
	Ui.setText(slot.count, if stack and stack.count > 1 then tostring(stack.count) else "")
	if slot.placeholder then
		slot.placeholder.Visible = stack == nil
	end
end

-- A grey Minecraft button that turns blue-ish with yellow text under the mouse.
function Ui.button(parent: Instance, x: number, y: number, w: number, h: number, text: string): TextButton
	local button = Ui.create("TextButton", {
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = rgb(0, 0, 0),
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Parent = parent,
	})
	Ui.frame(button, 1, 1, w - 2, h - 2, rgb(86, 86, 86))
	Ui.frame(button, 1, 1, w - 3, h - 4, rgb(170, 170, 170))
	local face = Ui.frame(button, 2, 2, w - 4, h - 5, rgb(111, 111, 111))
	local label = Ui.text({ Size = UDim2.fromOffset(w, h - 1), Position = UDim2.fromOffset(0, 0), Text = text, Parent = button })
	button.MouseEnter:Connect(function()
		face.BackgroundColor3 = rgb(126, 136, 191)
		Ui.setText(label, text, rgb(255, 255, 160))
	end)
	button.MouseLeave:Connect(function()
		face.BackgroundColor3 = rgb(111, 111, 111)
		Ui.setText(label, text, WHITE)
	end)
	return button
end

-- Rich-text lines describing a stack: name, then enchantments in grey.
function Ui.describe(stack: Items.Stack): string
	local name, lines = Items.describe(stack)
	local text = Ui.colored(name, if stack.ench then "#55FFFF" else "#FFFFFF")
	for _, line in lines do
		text ..= "\n" .. Ui.colored(line, "#AAAAAA")
	end
	return text
end

-- Mouse position in GUI pixels.
function Ui.mouse(): Vector2
	return UserInputService:GetMouseLocation() / Ui.S
end

-- Whether the mouse is over a GUI object.
function Ui.mouseOver(object: GuiObject): boolean
	local mouse = UserInputService:GetMouseLocation()
	local position, size = object.AbsolutePosition, object.AbsoluteSize
	return mouse.X >= position.X and mouse.X < position.X + size.X and mouse.Y >= position.Y and mouse.Y < position.Y + size.Y
end

function Ui.showTooltip(richText: string)
	Ui.setText(tooltip, richText)
	tooltip.Visible = true
end

function Ui.hideTooltip()
	tooltip.Visible = false
end

local function guiScale(): number
	local camera = workspace.CurrentCamera
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	return math.clamp(math.floor(math.min(size.X / 320, size.Y / 240)), 1, 3)
end

-- Called every frame: follows window resizes and keeps the tooltip beside the mouse.
function Ui.update()
	local scale = guiScale()
	if scale ~= Ui.S then
		Ui.S = scale
		for _, root in roots do
			root.frame.Size = UDim2.fromScale(1 / scale, 1 / scale)
			root.scale.Scale = scale
		end
	end
	if tooltip.Visible then
		local mouse = Ui.mouse()
		tooltip.Position = UDim2.fromOffset(mouse.X + 9, mouse.Y - 13)
	end
end

-- A full-screen root whose contents are in GUI pixels: it is 1/scale of the screen in size
-- and scaled back up, so (0.5, -91) means "91 GUI pixels left of the centre".
local function makeRoot(name: string, displayOrder: number): Frame
	local gui = Ui.create("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = displayOrder,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	local frame = Ui.create("Frame", {
		Name = "Root",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1 / Ui.S, 1 / Ui.S),
		Parent = gui,
	})
	local scale = Ui.create("UIScale", { Scale = Ui.S, Parent = frame })
	table.insert(roots, { frame = frame, scale = scale })
	return frame
end

function Ui.init()
	Ui.S = guiScale()
	Ui.hud = makeRoot("BlockCraftHud", 1)
	Ui.overlay = makeRoot("BlockCraftOverlay", 10)

	tooltip = Ui.text({
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundColor3 = rgb(16, 0, 16),
		BackgroundTransparency = 0.06,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
		ZIndex = 50,
		Parent = Ui.overlay,
	})
	Ui.create("UIPadding", {
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 3),
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 3),
		Parent = tooltip,
	})
	Ui.create("UIStroke", { Color = rgb(60, 0, 150), Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = tooltip })
end

return Ui
