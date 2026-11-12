-- The kits menu (/kits): a chest-style window with one slot per kit. Hover for the contents and
-- cooldown, click to claim.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Items = require(Shared.Items)
local Remotes = require(Shared.Remotes)
local Sounds = require(Shared.Sounds)

local State = require(script.Parent.State)
local Ui = require(script.Parent.Ui)

local KitsUi = {}

local root: TextButton
local panel: Frame
local slots: { [string]: Ui.Slot } = {}
local readyAt: { [string]: number } = {}
local hovered: string? = nil
local elapsed = 0

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

local function remaining(name: string): number
	return math.max(0, (readyAt[name] or 0) - workspace:GetServerTimeNow())
end

local function tooltipFor(name: string): string
	local kit = Config.Kits[name]
	local text = Ui.colored(kit.displayName .. " Kit", "#FFAA00")
	for _, item in kit.items do
		local stack = { id = item.id, count = item.count, ench = item.ench }
		local itemName, enchants = Items.describe(stack)
		local line = if item.count > 1 then `{item.count}x {itemName}` else itemName
		if #enchants > 0 then
			line ..= ` ({table.concat(enchants, ", ")})`
		end
		text ..= "\n" .. Ui.colored(line, "#AAAAAA")
	end
	text ..= "\n" .. Ui.colored(`Cooldown: {formatDuration(kit.cooldown)}`, "#5555FF")
	local left = remaining(name)
	if left > 0 then
		text ..= "\n" .. Ui.colored(`Available in {formatDuration(left)}`, "#FF5555")
	else
		text ..= "\n" .. Ui.colored("Click to claim!", "#55FF55")
	end
	return text
end

local function refresh()
	for name, slot in slots do
		local kit = Config.Kits[name]
		local ready = remaining(name) <= 0
		-- Kits that include enchanted gear get the enchanted tint on their icon.
		local enchanted = false
		for _, item in kit.items do
			enchanted = enchanted or item.ench ~= nil
		end
		Ui.setSlot(slot, { id = kit.icon, count = 1, ench = if enchanted then {} else nil })
		slot.frame.BackgroundColor3 = if ready then Ui.SLOT_COLOR else Color3.fromRGB(110, 70, 70)
		slot.stroke.Color = if ready then Color3.fromRGB(60, 160, 60) else Color3.fromRGB(55, 55, 55)
	end
	if hovered then
		Ui.showTooltip(tooltipFor(hovered))
	end
end

function KitsUi.open()
	if State.dead then
		return
	end
	State.openMenu("kits")
	local scale = panel:FindFirstChild("Scale") :: UIScale
	scale.Scale = Ui.scale()
	root.Visible = true
	refresh()
end

-- Keeps cooldown text ticking while the menu is open.
function KitsUi.update(dt: number)
	if State.menu ~= "kits" then
		return
	end
	elapsed += dt
	if elapsed >= 0.5 then
		elapsed = 0
		refresh()
	end
end

function KitsUi.init()
	root = Ui.modal("Kits")
	local S = Ui.SLOT
	local rows = math.max(1, math.ceil(#Config.KIT_ORDER / 9))
	panel = Ui.window(root, "Kits", 9 * S + 24, rows * S + 86)
	Ui.label({
		Size = UDim2.new(1, -24, 0, 20),
		Position = UDim2.new(0, 12, 1, -30),
		Text = "Hover a kit to see what's inside. Click to claim.",
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Ui.TITLE_COLOR,
		TextStrokeTransparency = 1,
		Parent = panel,
	})

	for i = 1, rows * 9 do
		local name = Config.KIT_ORDER[i]
		local slot = Ui.slot(panel, UDim2.fromOffset(12 + ((i - 1) % 9) * S, 38 + ((i - 1) // 9) * S), "panel")
		if name then
			slots[name] = slot
			local button = slot.frame :: TextButton
			button.MouseButton1Click:Connect(function()
				Sounds.playLocal("click", 0.3)
				Remotes.ClaimKit:FireServer(name)
			end)
			button.MouseEnter:Connect(function()
				hovered = name
				refresh()
			end)
			button.MouseLeave:Connect(function()
				if hovered == name then
					hovered = nil
					Ui.hideTooltip()
				end
			end)
		end
	end

	State.registerMenu("kits", function()
		root.Visible = false
		hovered = nil
		Ui.hideTooltip()
	end)
	Remotes.KitInfo.OnClientEvent:Connect(function(times: { [string]: number }, open: boolean)
		readyAt = times
		if open then
			KitsUi.open()
		elseif State.menu == "kits" then
			refresh()
		end
	end)
end

return KitsUi
