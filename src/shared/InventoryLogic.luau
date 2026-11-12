-- Inventory rules: Minecraft's click behaviour, the 2x2 crafting grid and item pickup.
-- Shared by the server, which is authoritative, and the client, which runs the same rules so a
-- click shows its result immediately. Pure Luau with no Roblox APIs, so it also runs under the
-- standalone Luau CLI (tools/tests/inventory.luau).
local Logic = {}

export type Stack = { id: string, count: number, ench: { [string]: number }? }
export type State = {
	slots: { [number]: Stack }, -- 1-9 hotbar, 10-36 main inventory
	armor: { [string]: Stack }, -- head, chest, legs, feet
	offhand: Stack?,
	craft: { [number]: Stack }, -- 2x2 grid, row by row
	cursor: Stack?, -- the stack being carried by the mouse
}
export type Def = { maxStack: number, kind: string, slot: string? }

-- Slot references: 1..36, "head" | "chest" | "legs" | "feet", "offhand", "craft1".."craft4", "result".
Logic.SLOT_COUNT = 36
Logic.defs = {} :: { [string]: Def } -- filled in by Items

local ARMOR: { [string]: boolean } = { head = true, chest = true, legs = true, feet = true }
local CRAFT: { [string]: number } = { craft1 = 1, craft2 = 2, craft3 = 3, craft4 = 4 }

type Recipe = { id: string, count: number }
-- One ingredient anywhere in the grid.
local ONE_INPUT: { [string]: Recipe } = {
	oak_log = { id = "oak_planks", count = 4 },
	birch_log = { id = "birch_planks", count = 4 },
}
-- The same ingredient in all four cells.
local FOUR_INPUT: { [string]: Recipe } = {
	sand = { id = "sandstone", count = 1 },
}

function Logic.newState(): State
	return { slots = {}, armor = {}, offhand = nil, craft = {}, cursor = nil }
end

function Logic.copy(stack: Stack): Stack
	return { id = stack.id, count = stack.count, ench = if stack.ench then table.clone(stack.ench) else nil }
end

function Logic.validRef(ref: any): boolean
	if type(ref) == "number" then
		return ref == math.floor(ref) and ref >= 1 and ref <= Logic.SLOT_COUNT
	end
	return type(ref) == "string" and (ARMOR[ref] == true or CRAFT[ref] ~= nil or ref == "offhand" or ref == "result")
end

function Logic.validHotbar(index: any): boolean
	return type(index) == "number" and index == math.floor(index) and index >= 1 and index <= 9
end

local function maxOf(stack: Stack): number
	local def = Logic.defs[stack.id]
	return if def then def.maxStack else 64
end

-- Stacks merge only when they are the same item with no enchantments.
local function canMerge(a: Stack, b: Stack): boolean
	return a.id == b.id and a.ench == nil and b.ench == nil
end

-- What the crafting grid currently makes, or nil.
function Logic.result(state: State): Stack?
	local id: string? = nil
	local filled = 0
	for i = 1, 4 do
		local stack = state.craft[i]
		if stack then
			if id and stack.id ~= id then
				return nil
			end
			id = stack.id
			filled += 1
		end
	end
	if not id then
		return nil
	end
	local recipe = if filled == 1 then ONE_INPUT[id] elseif filled == 4 then FOUR_INPUT[id] else nil
	if not recipe then
		return nil
	end
	return { id = recipe.id, count = recipe.count }
end

function Logic.get(state: State, ref: any): Stack?
	if type(ref) == "number" then
		return state.slots[ref]
	elseif ARMOR[ref] then
		return state.armor[ref]
	elseif ref == "offhand" then
		return state.offhand
	elseif ref == "result" then
		return Logic.result(state)
	end
	local cell = CRAFT[ref]
	return if cell then state.craft[cell] else nil
end

local function set(state: State, ref: any, stack: Stack?)
	if type(ref) == "number" then
		state.slots[ref] = stack :: any
	elseif ARMOR[ref] then
		state.armor[ref] = stack :: any
	elseif ref == "offhand" then
		state.offhand = stack
	else
		local cell = CRAFT[ref]
		if cell then
			state.craft[cell] = stack :: any
		end
	end
end

-- Whether `stack` may be put into `ref`: armor slots only take their own piece, the result
-- slot takes nothing.
local function accepts(ref: any, stack: Stack): boolean
	if ref == "result" then
		return false
	elseif ARMOR[ref] then
		local def = Logic.defs[stack.id]
		return def ~= nil and def.kind == "armor" and def.slot == ref
	end
	return true
end

-- Moves as much of `stack` as fits into slots first..last (either direction), topping up matching
-- stacks before using empty slots. Leaves what didn't fit in `stack.count` and returns it.
local function insert(state: State, stack: Stack, first: number, last: number): number
	local max = maxOf(stack)
	local step = if last >= first then 1 else -1
	if max > 1 and not stack.ench then
		for i = first, last, step do
			local existing = state.slots[i]
			if existing and canMerge(existing, stack) and existing.count < max then
				local moved = math.min(max - existing.count, stack.count)
				existing.count += moved
				stack.count -= moved
				if stack.count == 0 then
					return 0
				end
			end
		end
	end
	for i = first, last, step do
		if not state.slots[i] then
			local moved = math.min(max, stack.count)
			state.slots[i] = { id = stack.id, count = moved, ench = if stack.ench then table.clone(stack.ench) else nil }
			stack.count -= moved
			if stack.count == 0 then
				return 0
			end
		end
	end
	return stack.count
end

-- How many of `stack` the main inventory could still take.
local function room(state: State, stack: Stack): number
	local max = maxOf(stack)
	local total = 0
	for i = 1, Logic.SLOT_COUNT do
		local existing = state.slots[i]
		if not existing then
			total += max
		elseif canMerge(existing, stack) then
			total += max - existing.count
		end
	end
	return total
end

-- Picks up items (hotbar first). Returns the amount that didn't fit.
function Logic.add(state: State, stack: Stack): number
	return insert(state, Logic.copy(stack), 1, Logic.SLOT_COUNT)
end

-- Puts armor straight into its empty armor slot, otherwise behaves like add.
function Logic.equipOrAdd(state: State, stack: Stack): number
	local def = Logic.defs[stack.id]
	if def and def.kind == "armor" and def.slot and not state.armor[def.slot] then
		state.armor[def.slot] = Logic.copy(stack)
		return 0
	end
	return Logic.add(state, stack)
end

local function consumeIngredients(state: State)
	for i = 1, 4 do
		local stack = state.craft[i]
		if stack then
			stack.count -= 1
			if stack.count <= 0 then
				state.craft[i] = nil
			end
		end
	end
end

local function takeResult(state: State)
	local result = Logic.result(state)
	if not result then
		return
	end
	local cursor = state.cursor
	if not cursor then
		state.cursor = result
	elseif canMerge(cursor, result) and cursor.count + result.count <= maxOf(cursor) then
		cursor.count += result.count
	else
		return
	end
	consumeIngredients(state)
end

-- Shift-click: craft as much as fits, equip armor, or move between the hotbar and the rest.
local function quickMove(state: State, ref: any)
	if ref == "result" then
		for _ = 1, 64 do
			local result = Logic.result(state)
			if not result or room(state, result) < result.count then
				break
			end
			insert(state, result, 1, Logic.SLOT_COUNT)
			consumeIngredients(state)
		end
		return
	end
	local stack = Logic.get(state, ref)
	if not stack then
		return
	end
	local def = Logic.defs[stack.id]
	if type(ref) == "number" and def and def.kind == "armor" and def.slot and not state.armor[def.slot] then
		state.armor[def.slot] = stack
		state.slots[ref] = nil
		return
	end
	local moving = Logic.copy(stack)
	if type(ref) ~= "number" then
		if insert(state, moving, 10, Logic.SLOT_COUNT) > 0 then
			insert(state, moving, 1, 9)
		end
	elseif ref <= 9 then
		insert(state, moving, 10, Logic.SLOT_COUNT)
	else
		insert(state, moving, 1, 9)
	end
	if moving.count <= 0 then
		set(state, ref, nil)
	else
		stack.count = moving.count
	end
end

-- A mouse click on a slot. button is "left" or "right".
function Logic.click(state: State, ref: any, button: string, shift: boolean)
	if not Logic.validRef(ref) then
		return
	end
	if shift then
		quickMove(state, ref)
		return
	end
	if ref == "result" then
		takeResult(state)
		return
	end
	local slot, cursor = Logic.get(state, ref), state.cursor
	if not cursor then
		if not slot then
			return
		end
		if button == "right" and slot.count > 1 then
			-- Take the larger half.
			local taken = math.ceil(slot.count / 2)
			state.cursor = { id = slot.id, count = taken, ench = nil }
			slot.count -= taken
		else
			state.cursor = slot
			set(state, ref, nil)
		end
	elseif not slot then
		if not accepts(ref, cursor) then
			return
		end
		if button == "right" and cursor.count > 1 then
			set(state, ref, { id = cursor.id, count = 1, ench = nil })
			cursor.count -= 1
		else
			set(state, ref, cursor)
			state.cursor = nil
		end
	elseif canMerge(slot, cursor) then
		local space = maxOf(slot) - slot.count
		local moved = math.min(space, if button == "right" then 1 else cursor.count)
		slot.count += moved
		cursor.count -= moved
		if cursor.count <= 0 then
			state.cursor = nil
		end
	elseif accepts(ref, cursor) then
		set(state, ref, cursor)
		state.cursor = slot
	end
end

-- A number key pressed over a slot: swap it with that hotbar slot.
function Logic.swap(state: State, ref: any, hotbar: number)
	if not Logic.validRef(ref) or not Logic.validHotbar(hotbar) or ref == hotbar then
		return
	end
	if ref == "result" then
		local result = Logic.result(state)
		if result and not state.slots[hotbar] then
			state.slots[hotbar] = result
			consumeIngredients(state)
		end
		return
	end
	local here, there = Logic.get(state, ref), state.slots[hotbar]
	if there and not accepts(ref, there) then
		return
	end
	set(state, ref, there)
	state.slots[hotbar] = here :: any
end

function Logic.swapOffhand(state: State, hotbar: number)
	if Logic.validHotbar(hotbar) then
		local held = state.slots[hotbar]
		state.slots[hotbar] = state.offhand :: any
		state.offhand = held
	end
end

-- Removes up to `amount` from a slot (not the result slot) and returns what was removed.
function Logic.takeFrom(state: State, ref: any, amount: number): Stack?
	if not Logic.validRef(ref) or ref == "result" then
		return nil
	end
	local stack = Logic.get(state, ref)
	if not stack or amount < 1 then
		return nil
	end
	local taken = math.min(amount, stack.count)
	local removed = Logic.copy(stack)
	removed.count = taken
	stack.count -= taken
	if stack.count <= 0 then
		set(state, ref, nil)
	end
	return removed
end

-- Clicking outside the window: throw the carried stack (or one item of it).
function Logic.dropCursor(state: State, whole: boolean): Stack?
	local cursor = state.cursor
	if not cursor then
		return nil
	end
	if whole or cursor.count <= 1 then
		state.cursor = nil
		return cursor
	end
	cursor.count -= 1
	return { id = cursor.id, count = 1, ench = nil }
end

-- Closing the screen: the carried stack and the crafting grid go back into the inventory.
-- Returns whatever didn't fit, to be dropped.
function Logic.close(state: State): { Stack }
	local leftovers = {}
	local returning = {}
	if state.cursor then
		table.insert(returning, state.cursor)
		state.cursor = nil
	end
	for i = 1, 4 do
		local stack = state.craft[i]
		if stack then
			table.insert(returning, stack)
			state.craft[i] = nil
		end
	end
	for _, stack in returning do
		if insert(state, stack, 1, Logic.SLOT_COUNT) > 0 then
			table.insert(leftovers, stack)
		end
	end
	return leftovers
end

-- Empties everything and returns the removed stacks (death and combat-log drops).
function Logic.clear(state: State): { Stack }
	local removed = {}
	for _, stack in state.slots do
		table.insert(removed, stack)
	end
	for _, stack in state.armor do
		table.insert(removed, stack)
	end
	for _, stack in state.craft do
		table.insert(removed, stack)
	end
	if state.offhand then
		table.insert(removed, state.offhand)
	end
	if state.cursor then
		table.insert(removed, state.cursor)
	end
	state.slots, state.armor, state.craft = {}, {}, {}
	state.offhand, state.cursor = nil, nil
	return removed
end

-- Remote-safe form: sparse slot lists become string-keyed tables.
function Logic.encode(state: State): { [string]: any }
	local slots, armor, craft = {}, {}, {}
	for i, stack in state.slots do
		slots[tostring(i)] = Logic.copy(stack)
	end
	for slot, stack in state.armor do
		armor[slot] = Logic.copy(stack)
	end
	for i, stack in state.craft do
		craft[tostring(i)] = Logic.copy(stack)
	end
	return {
		slots = slots,
		armor = armor,
		craft = craft,
		offhand = if state.offhand then Logic.copy(state.offhand) else nil,
		cursor = if state.cursor then Logic.copy(state.cursor) else nil,
	}
end

-- Inverse of encode. Trusts its input, so only use it on data from the server or from encode.
function Logic.decode(payload: { [string]: any }): State
	local state = Logic.newState()
	for key, stack in payload.slots or {} do
		local i = tonumber(key)
		if i then
			state.slots[i] = stack
		end
	end
	for slot, stack in payload.armor or {} do
		state.armor[slot] = stack
	end
	for key, stack in payload.craft or {} do
		local i = tonumber(key)
		if i then
			state.craft[i] = stack
		end
	end
	state.offhand = payload.offhand
	state.cursor = payload.cursor
	return state
end

return Logic
