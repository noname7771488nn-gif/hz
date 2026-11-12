-- Server-authoritative inventories: 36 slots (1-9 hotbar) plus four armor slots.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared.Items)
local Remotes = require(Shared.Remotes)

type Stack = Items.Stack
type State = { slots: { [number]: Stack }, armor: { [string]: Stack }, selected: number }

local Inventory = {}

local SLOT_COUNT = Items.SLOT_COUNT
local states: { [Player]: State } = {}
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

local function validRef(ref: any): boolean
	if type(ref) == "number" then
		return ref == math.floor(ref) and ref >= 1 and ref <= SLOT_COUNT
	end
	return Items.isArmorSlot(ref)
end

local function getRef(state: State, ref: any): Stack?
	if type(ref) == "number" then
		return state.slots[ref]
	end
	return state.armor[ref]
end

local function setRef(state: State, ref: any, stack: Stack?)
	if type(ref) == "number" then
		state.slots[ref] = stack :: any
	else
		state.armor[ref] = stack :: any
	end
end

-- Whether `stack` may be put in `ref` (armor slots only take matching armor).
local function fits(ref: any, stack: Stack?): boolean
	if stack == nil or type(ref) == "number" then
		return true
	end
	local def = Items.get(stack.id)
	return def ~= nil and def.kind == "armor" and def.slot == ref
end

function Inventory.serialize(player: Player): any
	local state = states[player]
	if not state then
		return nil
	end
	local slots = {}
	for i, stack in state.slots do
		slots[tostring(i)] = Items.copy(stack)
	end
	local armor = {}
	for slot, stack in state.armor do
		armor[slot] = Items.copy(stack)
	end
	return { slots = slots, armor = armor }
end

function Inventory.sync(player: Player)
	local state = states[player]
	if not state then
		return
	end
	local payload = Inventory.serialize(player)
	payload.selected = state.selected
	Remotes.Inventory:FireClient(player, payload)
	for _, listener in listeners do
		task.spawn(listener, player)
	end
end

function Inventory.onChanged(listener: (Player) -> ())
	table.insert(listeners, listener)
end

function Inventory.load(player: Player, saved: any)
	local state: State = { slots = {}, armor = {}, selected = 1 }
	if type(saved) == "table" then
		if type(saved.slots) == "table" then
			for key, value in saved.slots do
				local i = tonumber(key)
				if i and validRef(i) and validStack(value) then
					state.slots[i] = sanitize(value)
				end
			end
		end
		if type(saved.armor) == "table" then
			for slot, value in saved.armor do
				if Items.isArmorSlot(slot) and validStack(value) and fits(slot, value) then
					state.armor[slot] = sanitize(value)
				end
			end
		end
	end
	states[player] = state
	Inventory.sync(player)
end

function Inventory.release(player: Player)
	states[player] = nil
end

-- Merges into existing stacks then fills empty slots within [first, last]. Returns the amount left over.
local function insert(state: State, stack: Stack, first: number, last: number): number
	local def = Items.get(stack.id)
	if not def then
		return stack.count
	end
	local remaining = stack.count
	if def.maxStack > 1 and not stack.ench then
		for i = first, last do
			local existing = state.slots[i]
			if existing and Items.canMerge(existing, stack) and existing.count < def.maxStack then
				local moved = math.min(def.maxStack - existing.count, remaining)
				existing.count += moved
				remaining -= moved
				if remaining == 0 then
					return 0
				end
			end
		end
	end
	for i = first, last do
		if not state.slots[i] then
			local moved = math.min(def.maxStack, remaining)
			state.slots[i] = { id = stack.id, count = moved, ench = if stack.ench then table.clone(stack.ench) else nil }
			remaining -= moved
			if remaining == 0 then
				return 0
			end
		end
	end
	return remaining
end

-- Adds items (hotbar first, like Minecraft). Returns the amount that didn't fit.
function Inventory.add(player: Player, stack: Stack): number
	local state = states[player]
	if not state then
		return stack.count
	end
	local remaining = insert(state, stack, 1, SLOT_COUNT)
	if remaining ~= stack.count then
		Inventory.sync(player)
	end
	return remaining
end

-- Puts armor straight into an empty armor slot, otherwise behaves like add.
function Inventory.equipOrAdd(player: Player, stack: Stack): number
	local state = states[player]
	if not state then
		return stack.count
	end
	local def = Items.get(stack.id)
	if def and def.kind == "armor" and def.slot and not state.armor[def.slot] then
		state.armor[def.slot] = Items.copy(stack)
		Inventory.sync(player)
		return 0
	end
	return Inventory.add(player, stack)
end

function Inventory.selected(player: Player): (Stack?, number)
	local state = states[player]
	if not state then
		return nil, 1
	end
	return state.slots[state.selected], state.selected
end

function Inventory.select(player: Player, index: number)
	local state = states[player]
	if state and validRef(index) and type(index) == "number" and index <= 9 and state.selected ~= index then
		state.selected = index
		for _, listener in listeners do
			task.spawn(listener, player)
		end
	end
end

-- Removes up to `amount` from the selected slot and returns what was removed.
function Inventory.takeSelected(player: Player, amount: number): Stack?
	local state = states[player]
	local stack = state and state.slots[state.selected]
	if not state or not stack then
		return nil
	end
	local taken = math.min(amount, stack.count)
	local removed = Items.copy(stack)
	removed.count = taken
	stack.count -= taken
	if stack.count <= 0 then
		state.slots[state.selected] = nil
	end
	Inventory.sync(player)
	return removed
end

-- Empties everything and returns the removed stacks (for death and combat-log drops).
function Inventory.clearAll(player: Player): { Stack }
	local state = states[player]
	if not state then
		return {}
	end
	local removed = {}
	for _, stack in state.slots do
		table.insert(removed, stack)
	end
	for _, stack in state.armor do
		table.insert(removed, stack)
	end
	state.slots = {}
	state.armor = {}
	Inventory.sync(player)
	return removed
end

function Inventory.armorStats(player: Player): (number, number, number)
	local state = states[player]
	if not state then
		return 0, 0, 0
	end
	local armor, toughness, protection = 0, 0, 0
	for _, slot in Items.ARMOR_SLOTS do
		local stack = state.armor[slot]
		local def = stack and Items.get(stack.id)
		if stack and def then
			armor += def.armor or 0
			toughness += def.toughness or 0
			protection += if stack.ench then stack.ench.protection or 0 else 0
		end
	end
	return armor, toughness, protection
end

function Inventory.armorIds(player: Player): { [string]: string }
	local ids = {}
	local state = states[player]
	if state then
		for slot, stack in state.armor do
			ids[slot] = stack.id
		end
	end
	return ids
end

-- Click-to-move from the inventory screen: merge same items, otherwise swap.
function Inventory.move(player: Player, from: any, to: any)
	local state = states[player]
	if not state or not validRef(from) or not validRef(to) or from == to then
		return
	end
	local a, b = getRef(state, from), getRef(state, to)
	if not a then
		return
	end
	local def = Items.get(a.id)
	if b and def and def.maxStack > 1 and Items.canMerge(a, b) then
		local moved = math.min(def.maxStack - b.count, a.count)
		b.count += moved
		a.count -= moved
		if a.count <= 0 then
			setRef(state, from, nil)
		end
	elseif fits(to, a) and fits(from, b) then
		setRef(state, from, b)
		setRef(state, to, a)
	else
		return
	end
	Inventory.sync(player)
end

-- Shift-click: equip armor, unequip armor, or move between the hotbar and main inventory.
function Inventory.quickMove(player: Player, ref: any)
	local state = states[player]
	if not state or not validRef(ref) then
		return
	end
	local stack = getRef(state, ref)
	if not stack then
		return
	end
	local def = Items.get(stack.id)
	if type(ref) == "string" then
		setRef(state, ref, nil)
		local left = insert(state, stack, 1, SLOT_COUNT)
		if left > 0 then
			setRef(state, ref, stack)
		end
	elseif def and def.kind == "armor" and def.slot and not state.armor[def.slot] then
		state.armor[def.slot] = stack
		state.slots[ref] = nil
	else
		local first, last = if ref <= 9 then 10 else 1, if ref <= 9 then SLOT_COUNT else 9
		state.slots[ref] = nil
		local left = insert(state, stack, first, last)
		if left > 0 then
			stack.count = left
			state.slots[ref] = stack
		end
	end
	Inventory.sync(player)
end

return Inventory
