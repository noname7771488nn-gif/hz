-- Server-authoritative inventories. The rules live in Shared.InventoryLogic; this module owns
-- each player's state, validates saved data and keeps the client in sync.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared.Items)
local Logic = require(Shared.InventoryLogic)
local Remotes = require(Shared.Remotes)

type Stack = Logic.Stack
-- `seq` is the number of the last client action applied, echoed back so the client can tell
-- which of its predicted clicks a sync already includes.
type Entry = { inv: Logic.State, selected: number, seq: number }

local Inventory = {}

local entries: { [Player]: Entry } = {}
local listeners: { (Player) -> () } = {}

local function validStack(value: any): boolean
	return type(value) == "table"
		and Items.get(value.id) ~= nil
		and type(value.count) == "number"
		and value.count >= 1
		and (value.ench == nil or type(value.ench) == "table")
end

local function sanitize(value: any): Stack
	local def = Items.get(value.id)
	local count = math.clamp(math.floor(value.count), 1, if def then def.maxStack else 64)
	local ench
	if value.ench then
		ench = {}
		for k, v in value.ench do
			if type(k) == "string" and type(v) == "number" then
				ench[k] = v
			end
		end
	end
	return { id = value.id, count = count, ench = ench }
end

function Inventory.sync(player: Player)
	local entry = entries[player]
	if not entry then
		return
	end
	local payload = Logic.encode(entry.inv)
	payload.selected = entry.selected
	payload.seq = entry.seq
	Remotes.Inventory:FireClient(player, payload)
	for _, listener in listeners do
		task.spawn(listener, player)
	end
end

function Inventory.onChanged(listener: (Player) -> ())
	table.insert(listeners, listener)
end

-- Saved form. Anything on the cursor or in the crafting grid counts as back in the inventory.
function Inventory.serialize(player: Player): any
	local entry = entries[player]
	if not entry then
		return nil
	end
	local copy = Logic.decode(Logic.encode(entry.inv))
	Logic.close(copy)
	local encoded = Logic.encode(copy)
	return { slots = encoded.slots, armor = encoded.armor, offhand = encoded.offhand }
end

function Inventory.load(player: Player, saved: any)
	local inv = Logic.newState()
	if type(saved) == "table" then
		if type(saved.slots) == "table" then
			for key, value in saved.slots do
				local i = tonumber(key)
				if i and type(i) == "number" and Logic.validRef(i) and validStack(value) then
					inv.slots[i] = sanitize(value)
				end
			end
		end
		if type(saved.armor) == "table" then
			for slot, value in saved.armor do
				local def = validStack(value) and Items.get(value.id)
				if def and def.kind == "armor" and def.slot == slot then
					inv.armor[slot] = sanitize(value)
				end
			end
		end
		if validStack(saved.offhand) then
			inv.offhand = sanitize(saved.offhand)
		end
	end
	entries[player] = { inv = inv, selected = 1, seq = 0 }
	Inventory.sync(player)
end

function Inventory.release(player: Player)
	entries[player] = nil
end

-- Applies one client inventory action and returns the stacks it threw on the ground.
function Inventory.action(player: Player, seq: any, action: string, a: any, b: any, c: any): { Stack }
	local entry = entries[player]
	local drops: { Stack } = {}
	if not entry then
		return drops
	end
	local inv = entry.inv
	if type(seq) == "number" and seq == seq then
		entry.seq = seq
	end

	if action == "click" then
		if Logic.validRef(a) and (b == "left" or b == "right") then
			Logic.click(inv, a, b, c == true)
		end
	elseif action == "swap" then
		Logic.swap(inv, a, b)
	elseif action == "offhand" then
		Logic.swapOffhand(inv, a)
	elseif action == "close" then
		drops = Logic.close(inv)
	else
		local dropped: Stack? = nil
		if action == "dropCursor" then
			dropped = Logic.dropCursor(inv, a == true)
		elseif action == "dropSlot" then
			dropped = Logic.takeFrom(inv, a, if b == true then 64 else 1)
		elseif action == "dropSelected" and Logic.validHotbar(b) then
			dropped = Logic.takeFrom(inv, b, if a == true then 64 else 1)
		end
		if dropped then
			table.insert(drops, dropped)
		end
	end
	Inventory.sync(player)
	return drops
end

-- Acknowledges an action that was not applied, so the client drops its prediction.
function Inventory.reject(player: Player, seq: any)
	local entry = entries[player]
	if entry and type(seq) == "number" and seq == seq then
		entry.seq = seq
		Inventory.sync(player)
	end
end

-- Adds items (hotbar first, like Minecraft). Returns the amount that didn't fit.
function Inventory.add(player: Player, stack: Stack): number
	local entry = entries[player]
	if not entry then
		return stack.count
	end
	local remaining = Logic.add(entry.inv, stack)
	if remaining ~= stack.count then
		Inventory.sync(player)
	end
	return remaining
end

-- Puts armor straight into an empty armor slot, otherwise behaves like add.
function Inventory.equipOrAdd(player: Player, stack: Stack): number
	local entry = entries[player]
	if not entry then
		return stack.count
	end
	local remaining = Logic.equipOrAdd(entry.inv, stack)
	if remaining ~= stack.count then
		Inventory.sync(player)
	end
	return remaining
end

function Inventory.selected(player: Player): (Stack?, number)
	local entry = entries[player]
	if not entry then
		return nil, 1
	end
	return entry.inv.slots[entry.selected], entry.selected
end

function Inventory.offhand(player: Player): Stack?
	local entry = entries[player]
	return entry and entry.inv.offhand
end

-- Returns true if the selection changed.
function Inventory.select(player: Player, index: any): boolean
	local entry = entries[player]
	if not entry or not Logic.validHotbar(index) or entry.selected == index then
		return false
	end
	entry.selected = index
	for _, listener in listeners do
		task.spawn(listener, player)
	end
	return true
end

-- Removes up to `amount` from a slot (a hotbar index or "offhand") and returns what was removed.
function Inventory.takeFrom(player: Player, ref: any, amount: number): Stack?
	local entry = entries[player]
	local removed = entry and Logic.takeFrom(entry.inv, ref, amount)
	if removed then
		Inventory.sync(player)
	end
	return removed
end

function Inventory.takeSelected(player: Player, amount: number): Stack?
	local entry = entries[player]
	return entry and Inventory.takeFrom(player, entry.selected, amount)
end

-- Empties everything and returns the removed stacks (for death and combat-log drops).
function Inventory.clearAll(player: Player): { Stack }
	local entry = entries[player]
	if not entry then
		return {}
	end
	local removed = Logic.clear(entry.inv)
	Inventory.sync(player)
	return removed
end

-- Armor points, toughness and total Protection levels of what the player is wearing.
function Inventory.armorStats(player: Player): (number, number, number)
	local entry = entries[player]
	if not entry then
		return 0, 0, 0
	end
	local armor, toughness, protection = 0, 0, 0
	for _, stack in entry.inv.armor do
		local def = Items.get(stack.id)
		if def then
			armor += def.armor or 0
			toughness += def.toughness or 0
			protection += if stack.ench then stack.ench.protection or 0 else 0
		end
	end
	return armor, toughness, protection
end

function Inventory.armorIds(player: Player): { [string]: string }
	local ids = {}
	local entry = entries[player]
	if entry then
		for slot, stack in entry.inv.armor do
			ids[slot] = stack.id
		end
	end
	return ids
end

return Inventory
