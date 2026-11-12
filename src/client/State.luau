-- Client-side game state: a predicted copy of the local player's inventory (the server stays
-- authoritative), the selected hotbar slot, the attack cooldown and which menu is open.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Items = require(Shared.Items)
local Logic = require(Shared.InventoryLogic)
local Remotes = require(Shared.Remotes)

local player = Players.LocalPlayer

local State = {
	inv = Logic.newState(),
	selected = 1,
	received = false,
	sentSeq = 0, -- number of the last inventory action sent to the server
	menu = nil :: string?, -- "inventory" | "kits" | "chat" | nil
	dead = false,
	sprinting = false,
	lastSwingAt = 0, -- when the attack cooldown last restarted
	changed = Instance.new("BindableEvent"),
	selectionChanged = Instance.new("BindableEvent"),
}

local closers: { [string]: () -> () } = {}

function State.selectedStack(): Items.Stack?
	return State.inv.slots[State.selected]
end

function State.get(ref: any): Items.Stack?
	return Logic.get(State.inv, ref)
end

function State.resetCooldown()
	State.lastSwingAt = os.clock()
end

-- Attack strength from 0 to 1: how far the held weapon has recharged since the last swing.
function State.charge(): number
	return math.clamp((os.clock() - State.lastSwingAt) * Items.attackSpeed(State.selectedStack()), 0, 1)
end

function State.select(index: number)
	index = ((index - 1) % 9) + 1
	if index == State.selected then
		return
	end
	State.selected = index
	State.resetCooldown()
	Remotes.SelectSlot:FireServer(index)
	State.selectionChanged:Fire()
end

function State.armorPoints(): number
	local total = 0
	for _, stack in State.inv.armor do
		local def = Items.get(stack.id)
		total += if def then def.armor or 0 else 0
	end
	return total
end

-- The item the player would eat on right-click (held item first, then offhand), or nil.
function State.edible(): string?
	local food = (player:GetAttribute("Food") or 20) :: number
	local function ok(stack: Items.Stack?): boolean
		local def = stack and Items.get(stack.id)
		return def ~= nil and def.food ~= nil and (food < 20 or def.alwaysEdible == true)
	end
	local held, offhand = State.selectedStack(), State.inv.offhand
	if held and ok(held) then
		return held.id
	elseif offhand and ok(offhand) then
		return offhand.id
	end
	return nil
end

function State.canSprint(): boolean
	return ((player:GetAttribute("Food") or 20) :: number) >= Config.SPRINT_MIN_FOOD and player:GetAttribute("Eating") == nil
end

-- Performs an inventory action: applies it locally right away, then tells the server.
--   click(ref, "left" | "right", shift)   swap(ref, hotbarIndex)   offhand(hotbarIndex)
--   dropCursor(whole)   dropSlot(ref, whole)   dropSelected(whole, hotbarIndex)   close()
function State.act(action: string, a: any, b: any, c: any)
	-- Nothing to act on until the server has sent the inventory once.
	if not State.received then
		return
	end
	local inv = State.inv
	if action == "click" then
		Logic.click(inv, a, b, c == true)
	elseif action == "swap" then
		Logic.swap(inv, a, b)
	elseif action == "offhand" then
		Logic.swapOffhand(inv, a)
	elseif action == "dropCursor" then
		Logic.dropCursor(inv, a == true)
	elseif action == "dropSlot" then
		Logic.takeFrom(inv, a, if b == true then 64 else 1)
	elseif action == "dropSelected" then
		Logic.takeFrom(inv, b, if a == true then 64 else 1)
	elseif action == "close" then
		Logic.close(inv)
	end
	State.sentSeq += 1
	Remotes.InvAction:FireServer(State.sentSeq, action, a, b, c)
	State.changed:Fire()
end

-- Menus are exclusive: opening one closes whichever was open.
function State.registerMenu(name: string, close: () -> ())
	closers[name] = close
end

function State.closeMenu()
	local name = State.menu
	if name then
		State.menu = nil
		closers[name]()
	end
end

function State.openMenu(name: string)
	if State.menu ~= name then
		State.closeMenu()
		State.menu = name
	end
end

Remotes.Inventory.OnClientEvent:Connect(function(payload)
	-- A sync from before our latest click would undo what the player just did; the server
	-- sends another one once it has processed that click.
	if type(payload.seq) == "number" and payload.seq < State.sentSeq then
		return
	end
	State.inv = Logic.decode(payload)
	-- The server's selection only matters on first sync; afterwards the client leads so fast
	-- scrolling never snaps back.
	if not State.received then
		State.received = true
		if type(payload.selected) == "number" then
			State.selected = payload.selected
		end
	end
	State.changed:Fire()
end)

return State
