local Config = require(script.Parent.Config)

export type BlockDef = {
	id: number,
	key: string,
	name: string,
	color: Color3, -- shown when pixel textures are unavailable
	hardness: number, -- negative = unbreakable
	tex: { all: string?, top: string?, side: string?, bottom: string? },
	drop: (string | boolean)?, -- item key, false for no drop, nil drops itself
	light: Color3?,
}

local Blocks = {}

-- Tag on pixel-textured decals that live outside the world folders (held items, drops, NPCs).
Blocks.PIXEL_TAG = "PixelTex"

-- Face order used for face bitmasks everywhere: +X, -X, +Y, -Y, +Z, -Z.
Blocks.FACES = {
	Enum.NormalId.Right,
	Enum.NormalId.Left,
	Enum.NormalId.Top,
	Enum.NormalId.Bottom,
	Enum.NormalId.Back,
	Enum.NormalId.Front,
}
Blocks.ALL_FACES = 63

local rgb = Color3.fromRGB

-- Id 0 is air. Ids are assigned from list order, so only append to keep ids stable.
local list: { any } = {
	{ key = "grass", name = "Grass Block", color = rgb(104, 164, 62), hardness = 0.6, drop = "dirt", tex = { top = "grass_top", side = "grass_side", bottom = "dirt" } },
	{ key = "dirt", name = "Dirt", color = rgb(134, 96, 67), hardness = 0.5, tex = { all = "dirt" } },
	{ key = "stone", name = "Stone", color = rgb(125, 125, 125), hardness = 1.5, drop = "cobblestone", tex = { all = "stone" } },
	{ key = "cobblestone", name = "Cobblestone", color = rgb(118, 118, 118), hardness = 2, tex = { all = "cobblestone" } },
	{ key = "bedrock", name = "Bedrock", color = rgb(70, 70, 70), hardness = -1, tex = { all = "bedrock" } },
	{ key = "sand", name = "Sand", color = rgb(219, 207, 163), hardness = 0.5, tex = { all = "sand" } },
	{ key = "oak_log", name = "Oak Log", color = rgb(109, 85, 50), hardness = 2, tex = { top = "oak_log_top", bottom = "oak_log_top", side = "oak_log_side" } },
	{ key = "oak_leaves", name = "Oak Leaves", color = rgb(58, 122, 36), hardness = 0.2, drop = false, tex = { all = "oak_leaves" } },
	{ key = "oak_planks", name = "Oak Planks", color = rgb(162, 130, 78), hardness = 2, tex = { all = "oak_planks" } },
	{ key = "stone_bricks", name = "Stone Bricks", color = rgb(122, 121, 122), hardness = 1.5, tex = { all = "stone_bricks" } },
	{ key = "smooth_stone", name = "Smooth Stone", color = rgb(158, 158, 158), hardness = 2, tex = { all = "smooth_stone" } },
	{ key = "coal_ore", name = "Coal Ore", color = rgb(105, 105, 105), hardness = 3, drop = "coal", tex = { all = "coal_ore" } },
	{ key = "iron_ore", name = "Iron Ore", color = rgb(136, 129, 122), hardness = 3, drop = "raw_iron", tex = { all = "iron_ore" } },
	{ key = "diamond_ore", name = "Diamond Ore", color = rgb(121, 141, 140), hardness = 3, drop = "diamond", tex = { all = "diamond_ore" } },
	{ key = "glowstone", name = "Glowstone", color = rgb(204, 160, 86), hardness = 0.3, light = rgb(255, 220, 150), tex = { all = "glowstone" } },
	{ key = "obsidian", name = "Obsidian", color = rgb(24, 16, 36), hardness = 50, tex = { all = "obsidian" } },
	{ key = "sandstone", name = "Sandstone", color = rgb(216, 203, 155), hardness = 0.8, tex = { top = "sandstone_top", bottom = "sandstone_top", side = "sandstone_side" } },
	{ key = "birch_log", name = "Birch Log", color = rgb(216, 215, 210), hardness = 2, tex = { top = "birch_log_top", bottom = "birch_log_top", side = "birch_log_side" } },
	{ key = "birch_leaves", name = "Birch Leaves", color = rgb(110, 150, 70), hardness = 0.2, drop = false, tex = { all = "birch_leaves" } },
	{ key = "snowy_grass", name = "Grass Block", color = rgb(240, 250, 250), hardness = 0.6, drop = "dirt", tex = { top = "snow", side = "snowy_grass_side", bottom = "dirt" } },
	{ key = "snow_block", name = "Snow Block", color = rgb(240, 250, 250), hardness = 0.2, tex = { all = "snow" } },
	{ key = "gravel", name = "Gravel", color = rgb(131, 127, 126), hardness = 0.6, tex = { all = "gravel" } },
	{ key = "deepslate_bricks", name = "Deepslate Bricks", color = rgb(70, 70, 73), hardness = 3.5, tex = { all = "deepslate_bricks" } },
	{ key = "red_concrete", name = "Red Concrete", color = rgb(142, 32, 32), hardness = 1.8, tex = { all = "red_concrete" } },
	{ key = "white_concrete", name = "White Concrete", color = rgb(207, 213, 214), hardness = 1.8, tex = { all = "white_concrete" } },
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

-- Texture key for a face index (see Blocks.FACES).
function Blocks.textureKey(def: BlockDef, face: number): string
	local tex = def.tex
	if face == 3 then
		return tex.top or tex.all or def.key
	elseif face == 4 then
		return tex.bottom or tex.all or def.key
	end
	return tex.side or tex.all or def.key
end

local templates: { [string]: Texture } = {}

-- Adds one Texture per face in `mask`, named after its texture key. The client fills in the pixel
-- art (Pixel module); until then, or if that is unavailable, the part's flat colour shows.
function Blocks.addFaces(part: BasePart, def: BlockDef, mask: number, tagged: boolean?)
	local size = part.Size.X
	for face = 1, 6 do
		if bit32.btest(mask, bit32.lshift(1, face - 1)) then
			local key = Blocks.textureKey(def, face)
			local cacheKey = `{key}|{face}|{size}|{tagged == true}`
			local template = templates[cacheKey]
			if not template then
				template = Instance.new("Texture")
				template.Name = key
				template.Face = Blocks.FACES[face]
				template.StudsPerTileU = size
				template.StudsPerTileV = size
				local override = Config.Textures[key]
				if override then
					template.Texture = override
				end
				if tagged then
					template:AddTag(Blocks.PIXEL_TAG)
				end
				templates[cacheKey] = template
			end
			template:Clone().Parent = part
		end
	end
end

-- Styles a cube-shaped part as the given block.
function Blocks.applyAppearance(part: BasePart, def: BlockDef, mask: number?, tagged: boolean?)
	part.Color = def.color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	Blocks.addFaces(part, def, mask or Blocks.ALL_FACES, tagged)
end

return Blocks
