local Blocks = require(script.Parent.Blocks)

export type ItemDef = {
	key: string,
	name: string,
	kind: string, -- "block" | "sword" | "armor" | "material"
	maxStack: number,
	color: Color3,
	block: string?,
	damage: number?,
	attackSpeed: number?,
	slot: string?, -- armor slot
	armor: number?,
	toughness: number?,
}

export type Stack = { id: string, count: number, ench: { [string]: number }? }

local Items = {}

local DIAMOND = Color3.fromRGB(77, 219, 205)
local IRON = Color3.fromRGB(216, 216, 216)

local defs: { [string]: ItemDef } = {}

for _, block in Blocks.list do
	defs[block.key] = { key = block.key, name = block.name, kind = "block", maxStack = 64, color = block.color, block = block.key }
end

-- Damage, attack speed, armor and toughness values are Minecraft Java 1.21.1's.
local extra: { ItemDef } = {
	{ key = "coal", name = "Coal", kind = "material", maxStack = 64, color = Color3.fromRGB(30, 30, 30) },
	{ key = "raw_iron", name = "Raw Iron", kind = "material", maxStack = 64, color = Color3.fromRGB(196, 160, 128) },
	{ key = "diamond", name = "Diamond", kind = "material", maxStack = 64, color = DIAMOND },
	{ key = "diamond_sword", name = "Diamond Sword", kind = "sword", maxStack = 1, color = DIAMOND, damage = 7, attackSpeed = 1.6 },
	{ key = "diamond_helmet", name = "Diamond Helmet", kind = "armor", maxStack = 1, color = DIAMOND, slot = "head", armor = 3, toughness = 2 },
	{ key = "diamond_chestplate", name = "Diamond Chestplate", kind = "armor", maxStack = 1, color = DIAMOND, slot = "chest", armor = 8, toughness = 2 },
	{ key = "diamond_leggings", name = "Diamond Leggings", kind = "armor", maxStack = 1, color = DIAMOND, slot = "legs", armor = 6, toughness = 2 },
	{ key = "diamond_boots", name = "Diamond Boots", kind = "armor", maxStack = 1, color = DIAMOND, slot = "feet", armor = 3, toughness = 2 },
	{ key = "iron_sword", name = "Iron Sword", kind = "sword", maxStack = 1, color = IRON, damage = 6, attackSpeed = 1.6 },
	{ key = "iron_helmet", name = "Iron Helmet", kind = "armor", maxStack = 1, color = IRON, slot = "head", armor = 2, toughness = 0 },
	{ key = "iron_chestplate", name = "Iron Chestplate", kind = "armor", maxStack = 1, color = IRON, slot = "chest", armor = 6, toughness = 0 },
	{ key = "iron_leggings", name = "Iron Leggings", kind = "armor", maxStack = 1, color = IRON, slot = "legs", armor = 5, toughness = 0 },
	{ key = "iron_boots", name = "Iron Boots", kind = "armor", maxStack = 1, color = IRON, slot = "feet", armor = 2, toughness = 0 },
}
for _, def in extra do
	defs[def.key] = def
end

Items.defs = defs
Items.ARMOR_SLOTS = { "head", "chest", "legs", "feet" }
Items.SLOT_COUNT = 36 -- 1-9 hotbar, 10-36 main inventory
Items.FIST = { damage = 1, attackSpeed = 4 }

local ENCHANT_NAMES = { protection = "Protection", sharpness = "Sharpness", fire_aspect = "Fire Aspect", unbreaking = "Unbreaking" }
local ENCHANT_ORDER = { "protection", "sharpness", "fire_aspect", "unbreaking" }
local ROMAN = { "I", "II", "III", "IV", "V" }

function Items.get(key: string?): ItemDef?
	if type(key) ~= "string" then
		return nil
	end
	return defs[key]
end

function Items.isArmorSlot(ref: any): boolean
	return ref == "head" or ref == "chest" or ref == "legs" or ref == "feet"
end

-- Stacks merge only when they are the same item with no enchantments.
function Items.canMerge(a: Stack, b: Stack): boolean
	return a.id == b.id and a.ench == nil and b.ench == nil
end

function Items.copy(stack: Stack): Stack
	return { id = stack.id, count = stack.count, ench = if stack.ench then table.clone(stack.ench) else nil }
end

-- Returns the display name and one line per enchantment.
function Items.describe(stack: Stack): (string, { string })
	local def = defs[stack.id]
	local lines = {}
	if stack.ench then
		for _, key in ENCHANT_ORDER do
			local level = stack.ench[key]
			if level then
				table.insert(lines, `{ENCHANT_NAMES[key]} {ROMAN[level] or tostring(level)}`)
			end
		end
	end
	return if def then def.name else stack.id, lines
end

return Items
