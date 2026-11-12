-- Shared UI building blocks: the two ScreenGuis, Minecraft-style text, item slots and the tooltip.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Items = require(ReplicatedStorage:WaitForChild("Shared").Items)

local Pixel = require(script.Parent.Pixel)

local Ui = {}

Ui.hud = nil :: any -- ScreenGui for the always-on HUD
Ui.overlay = nil :: any -- ScreenGui for menus, the crosshair and full-screen effects
Ui.FONT = Enum.Font.Arcade
-- Sizes are multiples of 3 so 16px sprites scale to whole pixels (Minecraft's GUI scale 3).
Ui.SLOT = 60
Ui.ICON = 48
Ui.PANEL_COLOR = Color3.fromRGB(198, 198, 198)
Ui.SLOT_COLOR = Color3.fromRGB(139, 139, 139)
Ui.TITLE_COLOR = Color3.fromRGB(64, 64, 64)

export type Slot = {
	frame: GuiObject,
	icon: Frame,
	count: TextLabel,
	stroke: UIStroke,
	key: string?,
	enchanted: boolean,
	placeholder: GuiObject?,
}

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

-- White pixel-font text with a dark outline.
function Ui.label(props: { [string]: any }): TextLabel
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.BorderSizePixel = 0
	props.Font = props.Font or Ui.FONT
	props.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	props.TextStrokeTransparency = props.TextStrokeTransparency or 0.25
	return Ui.create("TextLabel", props)
end

function Ui.escape(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

function Ui.colored(text: string, hex: string): string
	return `<font color="{hex}">{Ui.escape(text)}</font>`
end

-- An item slot. `style` is "hotbar" (dark, translucent) or "panel" (grey, clickable).
function Ui.slot(parent: Instance, position: UDim2, style: string): Slot
	local panel = style == "panel"
	local frame = Ui.create(if panel then "TextButton" else "Frame", {
		Size = UDim2.fromOffset(Ui.SLOT - 6, Ui.SLOT - 6),
		Position = position + UDim2.fromOffset(3, 3),
		BackgroundColor3 = if panel then Ui.SLOT_COLOR else Color3.fromRGB(20, 20, 20),
		BackgroundTransparency = if panel then 0 else 0.45,
		BorderSizePixel = 0,
		Parent = parent,
	})
	if panel then
		frame.Text = ""
		frame.AutoButtonColor = false
	end
	local stroke = Ui.create("UIStroke", {
		Color = if panel then Color3.fromRGB(55, 55, 55) else Color3.fromRGB(120, 120, 120),
		Thickness = 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = frame,
	})
	local icon = Ui.create("Frame", {
		Size = UDim2.fromOffset(Ui.ICON, Ui.ICON),
		Position = UDim2.fromOffset(3, 3),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	local count = Ui.label({
		Size = UDim2.new(1, -2, 0, 20),
		Position = UDim2.new(0, 0, 1, -20),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 20,
		Text = "",
		ZIndex = 3,
		Parent = frame,
	})
	return { frame = frame, icon = icon, count = count, stroke = stroke, key = nil, enchanted = false }
end

function Ui.setSlot(slot: Slot, stack: Items.Stack?)
	local key = stack and stack.id
	local enchanted = stack ~= nil and stack.ench ~= nil
	if slot.key ~= key or slot.enchanted ~= enchanted then
		slot.key = key
		slot.enchanted = enchanted
		Pixel.setIcon(slot.icon, key, enchanted)
	end
	slot.count.Text = if stack and stack.count > 1 then tostring(stack.count) else ""
	if slot.placeholder then
		slot.placeholder.Visible = stack == nil
	end
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

function Ui.showTooltip(richText: string)
	tooltip.Text = richText
	tooltip.Visible = true
end

function Ui.hideTooltip()
	tooltip.Visible = false
end

-- A full-screen dimmed button. Being Modal, it frees the mouse while the camera is in first person.
function Ui.modal(name: string): TextButton
	return Ui.create("TextButton", {
		Name = name,
		Text = "",
		AutoButtonColor = false,
		Modal = true,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 5,
		Parent = Ui.overlay,
	})
end

-- A Minecraft-style light grey window with a title, centred on screen.
function Ui.window(parent: Instance, title: string, width: number, height: number): Frame
	local panel = Ui.create("Frame", {
		Size = UDim2.fromOffset(width, height),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Ui.PANEL_COLOR,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = parent,
	}, {
		Ui.create("UIStroke", { Color = Color3.fromRGB(20, 20, 20), Thickness = 3 }),
		Ui.create("UIScale", { Name = "Scale" }),
	})
	Ui.label({
		Size = UDim2.fromOffset(width - 24, 24),
		Position = UDim2.fromOffset(12, 8),
		Text = title,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 20,
		TextColor3 = Ui.TITLE_COLOR,
		TextStrokeTransparency = 1,
		Parent = panel,
	})
	return panel
end

-- 1 on tall screens, 2/3 on small ones; both keep sprites on whole pixels.
function Ui.scale(): number
	local camera = workspace.CurrentCamera
	return if camera and camera.ViewportSize.Y < 900 then 2 / 3 else 1
end

function Ui.updateTooltip()
	if tooltip.Visible then
		local mouse = UserInputService:GetMouseLocation()
		tooltip.Position = UDim2.fromOffset(mouse.X + 16, mouse.Y - 12)
	end
end

function Ui.init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	Ui.hud = Ui.create("ScreenGui", { Name = "BlockCraftHud", ResetOnSpawn = false, IgnoreGuiInset = true, Parent = playerGui })
	Ui.overlay = Ui.create("ScreenGui", { Name = "BlockCraftOverlay", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 10, Parent = playerGui })

	tooltip = Ui.label({
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundColor3 = Color3.fromRGB(20, 4, 30),
		BackgroundTransparency = 0.06,
		RichText = true,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
		ZIndex = 50,
		Parent = Ui.overlay,
	})
	Ui.create("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
		Parent = tooltip,
	})
	Ui.create("UIStroke", { Color = Color3.fromRGB(80, 0, 160), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = tooltip })
end

return Ui
