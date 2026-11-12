-- The inventory screen (E): armor slots, 27 inventory slots and the hotbar. Click a slot then
-- another to move or swap, Shift-click to quick-move, number keys to swap with the hotbar.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared.Items)
local Remotes = require(Shared.Remotes)
local Sounds = require(Shared.Sounds)

local Pixel = require(script.Parent.Pixel)
local State = require(script.Parent.State)
local Ui = require(script.Parent.Ui)

local InventoryUi = {}

local root: TextButton
local panel: Frame
local slots: { [any]: Ui.Slot } = {}
local picked: any = nil
local hovered: any = nil

local function refresh()
	for ref, slot in slots do
		Ui.setSlot(slot, State.get(ref))
		slot.stroke.Color = if ref == picked then Color3.fromRGB(255, 220, 60) else Color3.fromRGB(55, 55, 55)
	end
	if hovered ~= nil then
		local stack = State.get(hovered)
		if stack then
			Ui.showTooltip(Ui.describe(stack))
		else
			Ui.hideTooltip()
		end
	end
end

local function onClicked(ref: any)
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
	refresh()
end

local function addSlot(ref: any, x: number, y: number, placeholder: string?)
	local slot = Ui.slot(panel, UDim2.fromOffset(x, y), "panel")
	if placeholder then
		local silhouette = Pixel.sprite(placeholder)
		silhouette.Parent = slot.icon
		slot.placeholder = silhouette
	end
	local button = slot.frame :: TextButton
	button.MouseButton1Click:Connect(function()
		onClicked(ref)
	end)
	button.MouseEnter:Connect(function()
		hovered = ref
		refresh()
	end)
	button.MouseLeave:Connect(function()
		if hovered == ref then
			hovered = nil
			Ui.hideTooltip()
		end
	end)
	slots[ref] = slot
end

function InventoryUi.isOpen(): boolean
	return State.menu == "inventory"
end

function InventoryUi.open()
	State.openMenu("inventory")
	local scale = panel:FindFirstChild("Scale") :: UIScale
	scale.Scale = Ui.scale()
	root.Visible = true
	refresh()
end

function InventoryUi.toggle()
	if InventoryUi.isOpen() then
		State.closeMenu()
	elseif not State.dead then
		InventoryUi.open()
	end
end

-- Number keys over a hovered slot swap it with that hotbar slot, as in Minecraft.
function InventoryUi.hotbarSwap(index: number)
	if InventoryUi.isOpen() and hovered ~= nil and hovered ~= index then
		Remotes.MoveSlot:FireServer(hovered, index)
	end
end

function InventoryUi.init()
	root = Ui.modal("Inventory")
	local S = Ui.SLOT
	panel = Ui.window(root, "Inventory", 9 * S + 24, 5 * S + 86)

	for i, slot in Items.ARMOR_SLOTS do
		addSlot(slot, 12 + (i - 1) * S, 38, "slot_" .. slot)
	end
	local mainY = 38 + S + 14
	for row = 0, 2 do
		for col = 0, 8 do
			addSlot(10 + row * 9 + col, 12 + col * S, mainY + row * S)
		end
	end
	for col = 0, 8 do
		addSlot(col + 1, 12 + col * S, mainY + 3 * S + 12)
	end

	State.registerMenu("inventory", function()
		root.Visible = false
		picked = nil
		hovered = nil
		Ui.hideTooltip()
	end)
	State.changed.Event:Connect(function()
		if InventoryUi.isOpen() then
			refresh()
		end
	end)
end

return InventoryUi
