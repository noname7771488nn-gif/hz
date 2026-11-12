local Blocks = require(script.Parent.Blocks)
local InventoryLogic = require(script.Parent.InventoryLogic)

export type ItemDef = {
	key: string,
	name: string,
	kind: string, -- "block" | "sword" | "armor" | "food" | "material"
	maxStack: number,
	color: Color3,
	block: string?,
	damage: number?,
	attackSpeed: number?,
	slot: string?, -- armor slot
	armor: number?,
	toughness: number?,
	food: number?, -- hunger points restored
	saturation: number?,
	alwaysEdible: boolean?, -- can be eaten on a full hunger bar
	goldenApple: boolean?, -- grants Regeneration II and Absorption
}

export type Stack = InventoryLogic.Stack

local Items = {}

local DIAMOND = Color3.fromRGB(77, 219, 205)
local IRON = Color3.fromRGB(216, 216, 216)

local defs: { [string]: ItemDef } = {}

for _, block in Blocks.list do
	defs[block.key] = { key = block.key, name = block.name, kind = "block", maxStack = 64, color = block.color, block = block.key }
end

-- Damage, attack speed, armor, toughness and food values are Minecraft Java's (1.9 and later).
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
	{ key = "cooked_beef", name = "Steak", kind = "food", maxStack = 64, color = Color3.fromRGB(133, 73, 45), food = 8, saturation = 12.8 },
	{
		key = "golden_apple",
		name = "Golden Apple",
		kind = "food",
		maxStack = 64,
		color = Color3.fromRGB(234, 200, 60),
		food = 4,
		saturation = 9.6,
		alwaysEdible = true,
		goldenApple = true,
	},
}
for _, def in extra do
	defs[def.key] = def
end

Items.defs = defs
-- The shared inventory rules look items up here.
InventoryLogic.defs = defs

Items.ARMOR_SLOTS = { "head", "chest", "legs", "feet" }
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

-- Attacks per second of a held stack (bare hands and non-weapons recharge almost instantly).
function Items.attackSpeed(stack: Stack?): number
	local def = stack and defs[stack.id]
	if def and def.kind == "sword" then
		return def.attackSpeed or Items.FIST.attackSpeed
	end
	return Items.FIST.attackSpeed
end

function Items.copy(stack: Stack): Stack
	return InventoryLogic.copy(stack)
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
