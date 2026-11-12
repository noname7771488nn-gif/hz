local Config = require(script.Parent.Config)

export type BlockDef = {
	id: number,
	key: string,
	name: string,
	color: Color3,
	material: Enum.Material,
	hardness: number, -- negative = unbreakable
	drop: (string | boolean)?, -- item key, false for no drop, nil drops itself
	transparent: boolean?, -- neighbours stay visible behind it
	light: Color3?,
}

local Blocks = {}

-- Id 0 is air. Ids are assigned from list order, so only append to keep ids stable.
local list: { any } = {
	{ key = "grass", name = "Grass Block", color = Color3.fromRGB(96, 160, 56), material = Enum.Material.Grass, hardness = 0.6, drop = "dirt" },
	{ key = "dirt", name = "Dirt", color = Color3.fromRGB(134, 96, 67), material = Enum.Material.Ground, hardness = 0.5 },
	{ key = "stone", name = "Stone", color = Color3.fromRGB(125, 125, 125), material = Enum.Material.Slate, hardness = 1.5, drop = "cobblestone" },
	{ key = "cobblestone", name = "Cobblestone", color = Color3.fromRGB(110, 110, 110), material = Enum.Material.Cobblestone, hardness = 2 },
	{ key = "bedrock", name = "Bedrock", color = Color3.fromRGB(55, 55, 55), material = Enum.Material.Basalt, hardness = -1 },
	{ key = "sand", name = "Sand", color = Color3.fromRGB(219, 207, 163), material = Enum.Material.Sand, hardness = 0.5 },
	{ key = "oak_log", name = "Oak Log", color = Color3.fromRGB(102, 81, 50), material = Enum.Material.Wood, hardness = 2 },
	{ key = "oak_leaves", name = "Oak Leaves", color = Color3.fromRGB(58, 122, 36), material = Enum.Material.Grass, hardness = 0.2, drop = false, transparent = true },
	{ key = "oak_planks", name = "Oak Planks", color = Color3.fromRGB(162, 130, 78), material = Enum.Material.WoodPlanks, hardness = 2 },
	{ key = "stone_bricks", name = "Stone Bricks", color = Color3.fromRGB(122, 121, 122), material = Enum.Material.Brick, hardness = 1.5 },
	{ key = "smooth_stone", name = "Smooth Stone", color = Color3.fromRGB(158, 158, 158), material = Enum.Material.Concrete, hardness = 2 },
	{ key = "coal_ore", name = "Coal Ore", color = Color3.fromRGB(88, 88, 88), material = Enum.Material.Slate, hardness = 3, drop = "coal" },
	{ key = "iron_ore", name = "Iron Ore", color = Color3.fromRGB(160, 138, 118), material = Enum.Material.Slate, hardness = 3, drop = "raw_iron" },
	{ key = "diamond_ore", name = "Diamond Ore", color = Color3.fromRGB(100, 170, 170), material = Enum.Material.Slate, hardness = 3, drop = "diamond" },
	{ key = "glowstone", name = "Glowstone", color = Color3.fromRGB(235, 195, 110), material = Enum.Material.Neon, hardness = 0.3, light = Color3.fromRGB(255, 220, 150) },
	{ key = "obsidian", name = "Obsidian", color = Color3.fromRGB(24, 16, 36), material = Enum.Material.Basalt, hardness = 50 },
}

Blocks.list = list :: { BlockDef }
Blocks.byKey = {} :: { [string]: BlockDef }
Blocks.byId = {} :: { [number]: BlockDef }

for i, def in Blocks.list do
	def.id = i
	Blocks.byKey[def.key] = def
	Blocks.byId[i] = def
end

-- Seconds to mine a block by hand.
function Blocks.breakTime(def: BlockDef): number
	if def.hardness < 0 then
		return math.huge
	end
	return math.max(0.05, def.hardness * 1.5)
end

-- Item dropped when the block is mined, or nil.
function Blocks.dropOf(def: BlockDef): string?
	if def.drop == false then
		return nil
	end
	if type(def.drop) == "string" then
		return def.drop
	end
	return def.key
end

local function textureFor(textures, face: Enum.NormalId): string?
	if face == Enum.NormalId.Top and textures.top then
		return textures.top
	elseif face == Enum.NormalId.Bottom and textures.bottom then
		return textures.bottom
	elseif face ~= Enum.NormalId.Top and face ~= Enum.NormalId.Bottom and textures.side then
		return textures.side
	end
	return textures.all
end

-- Styles a cube-shaped part as the given block (used for world blocks, held items, drops and icons).
function Blocks.applyAppearance(part: BasePart, def: BlockDef)
	part.Color = def.color
	part.Material = def.material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	local textures = Config.Textures[def.key]
	if textures then
		for _, face in Enum.NormalId:GetEnumItems() do
			local id = textureFor(textures, face)
			if id and id ~= "" then
				local texture = Instance.new("Texture")
				texture.Texture = id
				texture.Face = face
				texture.StudsPerTileU = part.Size.X
				texture.StudsPerTileV = part.Size.Y
				texture.Parent = part
			end
		end
	end
end

return Blocks
