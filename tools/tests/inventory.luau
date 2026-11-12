-- Tests for the shared inventory rules. Run from the repository root with the standalone Luau CLI:
--   luau tools/tests/inventory.luau
local Logic = require("../../src/shared/InventoryLogic")

Logic.defs = {
	dirt = { maxStack = 64, kind = "block" },
	sand = { maxStack = 64, kind = "block" },
	sandstone = { maxStack = 64, kind = "block" },
	oak_log = { maxStack = 64, kind = "block" },
	oak_planks = { maxStack = 64, kind = "block" },
	sword = { maxStack = 1, kind = "sword" },
	helmet = { maxStack = 1, kind = "armor", slot = "head" },
	boots = { maxStack = 1, kind = "armor", slot = "feet" },
}

local passed = 0
local function check(condition: boolean, message: string)
	if not condition then
		error("FAILED: " .. message, 2)
	end
	passed += 1
end

local function stack(id: string, count: number?, ench: { [string]: number }?): Logic.Stack
	return { id = id, count = count or 1, ench = ench }
end

local function count(state: Logic.State, ref: any): number
	local found = Logic.get(state, ref)
	return if found then found.count else 0
end

local function total(state: Logic.State, id: string): number
	local sum = 0
	for _, s in Logic.clear(Logic.decode(Logic.encode(state))) do
		if s.id == id then
			sum += s.count
		end
	end
	return sum
end

-- Left click: pick up, put down, merge, swap.
do
	local s = Logic.newState()
	s.slots[1] = stack("dirt", 40)
	s.slots[2] = stack("dirt", 40)
	s.slots[3] = stack("sword")
	Logic.click(s, 1, "left", false)
	check(s.cursor ~= nil and s.cursor.count == 40 and s.slots[1] == nil, "left click picks up the whole stack")
	Logic.click(s, 2, "left", false)
	check(count(s, 2) == 64 and s.cursor ~= nil and s.cursor.count == 16, "left click merges up to the stack limit")
	Logic.click(s, 3, "left", false)
	check(count(s, 3) == 16 and s.cursor ~= nil and s.cursor.id == "sword", "left click swaps different items")
	Logic.click(s, 20, "left", false)
	check(s.cursor == nil and count(s, 20) == 1, "left click puts the stack into an empty slot")
	check(total(s, "dirt") == 80, "no dirt created or lost")
end

-- Right click: take half, place one.
do
	local s = Logic.newState()
	s.slots[1] = stack("dirt", 7)
	Logic.click(s, 1, "right", false)
	check(s.cursor ~= nil and s.cursor.count == 4 and count(s, 1) == 3, "right click takes the larger half")
	Logic.click(s, 2, "right", false)
	Logic.click(s, 2, "right", false)
	check(count(s, 2) == 2 and s.cursor ~= nil and s.cursor.count == 2, "right click places one at a time")
	Logic.click(s, 1, "right", false)
	check(count(s, 1) == 4 and s.cursor ~= nil and s.cursor.count == 1, "right click adds one to a matching stack")
	Logic.click(s, 1, "right", false)
	check(s.cursor == nil and count(s, 1) == 5, "placing the last item empties the cursor")
end

-- Armor slots only take their own piece.
do
	local s = Logic.newState()
	s.slots[1] = stack("helmet")
	s.slots[2] = stack("dirt", 5)
	Logic.click(s, 2, "left", false)
	Logic.click(s, "head", "left", false)
	check(s.armor.head == nil and s.cursor ~= nil, "dirt cannot go in the helmet slot")
	Logic.click(s, 2, "left", false)
	Logic.click(s, 1, "left", false)
	Logic.click(s, "feet", "left", false)
	check(s.armor.feet == nil, "a helmet cannot go in the boots slot")
	Logic.click(s, "head", "left", false)
	check(s.armor.head ~= nil and s.cursor == nil, "a helmet goes in the helmet slot")
end

-- Shift-click.
do
	local s = Logic.newState()
	s.slots[1] = stack("helmet")
	s.slots[2] = stack("dirt", 10)
	s.slots[12] = stack("dirt", 60)
	s.slots[15] = stack("boots", 1, { protection = 3 })
	Logic.click(s, 1, "left", true)
	check(s.armor.head ~= nil and s.slots[1] == nil, "shift-click equips armor")
	Logic.click(s, 2, "left", true)
	check(s.slots[2] == nil and count(s, 12) == 64 and count(s, 10) == 6, "shift-click from the hotbar tops up then fills")
	Logic.click(s, 15, "left", true)
	check(s.armor.feet ~= nil and s.armor.feet.ench ~= nil and s.armor.feet.ench.protection == 3, "enchantments survive equipping")
	Logic.click(s, "head", "left", true)
	check(s.armor.head == nil and total(s, "helmet") == 1, "shift-click unequips armor")
	Logic.click(s, 12, "right", true)
	check(s.slots[12] == nil and count(s, 1) == 64, "shift-click from the inventory goes to the hotbar")
end

-- Shift-click with a full destination leaves the remainder.
do
	local s = Logic.newState()
	for i = 10, 36 do
		s.slots[i] = stack("sand", 64)
	end
	s.slots[10].count = 60
	s.slots[1] = stack("sand", 10)
	Logic.click(s, 1, "left", true)
	check(count(s, 10) == 64 and count(s, 1) == 6, "shift-click moves only what fits")
end

-- Number keys.
do
	local s = Logic.newState()
	s.slots[20] = stack("dirt", 3)
	s.slots[4] = stack("sword")
	Logic.swap(s, 20, 4)
	check(count(s, 4) == 3 and s.slots[20] ~= nil and s.slots[20].id == "sword", "number key swaps with the hotbar slot")
	s.armor.head = stack("helmet")
	Logic.swap(s, "head", 4)
	check(s.armor.head ~= nil and s.armor.head.id == "helmet", "number key cannot put dirt in an armor slot")
	Logic.swap(s, "head", 9)
	check(s.armor.head == nil and s.slots[9] ~= nil, "number key moves armor to an empty hotbar slot")
end

-- Crafting.
do
	local s = Logic.newState()
	check(Logic.result(s) == nil, "an empty grid makes nothing")
	s.craft[3] = stack("oak_log", 2)
	local planks = Logic.result(s)
	check(planks ~= nil and planks.id == "oak_planks" and planks.count == 4, "one log makes four planks")
	Logic.click(s, "result", "left", false)
	Logic.click(s, "result", "left", false)
	check(s.cursor ~= nil and s.cursor.count == 8 and s.craft[3] == nil, "taking the result uses up the ingredients")
	Logic.click(s, "result", "left", false)
	check(s.cursor ~= nil and s.cursor.count == 8, "an empty grid gives nothing more")
	Logic.click(s, "craft1", "left", false)
	check(Logic.result(s) == nil and s.cursor == nil, "planks alone are not a recipe")

	for i = 1, 4 do
		s.craft[i] = stack("sand", 3)
	end
	local sandstone = Logic.result(s)
	check(sandstone ~= nil and sandstone.id == "sandstone" and sandstone.count == 1, "four sand make sandstone")
	Logic.click(s, "result", "left", true)
	check(total(s, "sandstone") == 3 and Logic.result(s) == nil, "shift-click crafts until the grid is empty")
	s.craft[1], s.craft[2] = stack("sand"), stack("dirt")
	check(Logic.result(s) == nil, "mixed ingredients make nothing")
	local held = stack("dirt")
	s.cursor = held
	Logic.click(s, "result", "left", false)
	check(s.cursor == held, "nothing can be put into the result slot")
end

-- Result does not merge past the stack limit.
do
	local s = Logic.newState()
	s.craft[1] = stack("oak_log", 5)
	s.cursor = stack("oak_planks", 62)
	Logic.click(s, "result", "left", false)
	check(s.cursor ~= nil and s.cursor.count == 62 and count(s, "craft1") == 5, "result is not taken when it would overflow the cursor")
end

-- Pickup, offhand, drops, closing.
do
	local s = Logic.newState()
	s.slots[5] = stack("dirt", 60)
	check(Logic.add(s, stack("dirt", 10)) == 0 and count(s, 5) == 64 and count(s, 1) == 6, "pickup tops up stacks first")
	check(Logic.add(s, stack("sword", 1, { sharpness = 4 })) == 0 and s.slots[2] ~= nil and s.slots[2].ench ~= nil, "enchanted items never merge")
	check(Logic.equipOrAdd(s, stack("helmet")) == 0 and s.armor.head ~= nil, "kit armor is worn when the slot is empty")
	check(Logic.equipOrAdd(s, stack("helmet")) == 0 and s.slots[3] ~= nil, "a second helmet goes to the inventory")

	Logic.swapOffhand(s, 5)
	check(s.offhand ~= nil and s.offhand.count == 64 and s.slots[5] == nil, "F moves the held stack to the offhand")
	Logic.swapOffhand(s, 2)
	check(s.offhand ~= nil and s.offhand.id == "sword" and count(s, 2) == 64, "F swaps the held stack with the offhand")

	local dropped = Logic.takeFrom(s, 1, 1)
	check(dropped ~= nil and dropped.count == 1 and count(s, 1) == 5, "Q drops one")
	dropped = Logic.takeFrom(s, 1, 64)
	check(dropped ~= nil and dropped.count == 5 and s.slots[1] == nil, "Ctrl+Q drops the stack")
	check(Logic.takeFrom(s, "result", 1) == nil, "the result slot cannot be dropped from")

	Logic.click(s, 2, "left", false)
	local one = Logic.dropCursor(s, false)
	check(one ~= nil and one.count == 1 and s.cursor ~= nil and s.cursor.count == 63, "right-click outside throws one")
	s.craft[2] = stack("oak_log", 2)
	check(#Logic.close(s) == 0 and s.cursor == nil and s.craft[2] == nil, "closing returns the cursor and grid to the inventory")
	check(total(s, "dirt") == 63 and total(s, "oak_log") == 2, "closing loses nothing")
end

-- Closing with a full inventory hands back the overflow.
do
	local s = Logic.newState()
	for i = 1, 36 do
		s.slots[i] = stack("sword")
	end
	s.cursor = stack("dirt", 5)
	local leftovers = Logic.close(s)
	check(#leftovers == 1 and leftovers[1].count == 5, "overflow is returned when the inventory is full")
end

-- Encoding survives a round trip, and bad references are ignored.
do
	local s = Logic.newState()
	s.slots[36] = stack("dirt", 2)
	s.armor.feet = stack("boots", 1, { protection = 3 })
	s.offhand = stack("sword")
	s.craft[4] = stack("sand", 9)
	s.cursor = stack("oak_log", 1)
	local copy = Logic.decode(Logic.encode(s))
	check(count(copy, 36) == 2 and copy.armor.feet.ench.protection == 3 and copy.offhand.id == "sword", "encode/decode keeps slots, armor and offhand")
	check(count(copy, "craft4") == 9 and copy.cursor.id == "oak_log", "encode/decode keeps the grid and cursor")
	copy.slots[36].count = 1
	check(count(s, 36) == 2, "decoded state is independent of the original")

	for _, bad in { 0, 37, 1.5, "body", "craft5", true, {} } :: { any } do
		Logic.click(s, bad, "left", false)
		Logic.swap(s, bad, 1)
		check(Logic.takeFrom(s, bad, 1) == nil, "invalid slot references do nothing")
	end
	Logic.swap(s, 36, 10)
	check(count(s, 36) == 2, "only hotbar indexes are accepted for number keys")
	check(#Logic.clear(s) == 5 and next(s.slots) == nil and s.cursor == nil, "clear removes everything")
end

print(`inventory: {passed} checks passed`)
