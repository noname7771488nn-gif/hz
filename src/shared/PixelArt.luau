--!strict
-- Procedurally drawn 16x16 pixel-art textures (blocks, item sprites, HUD icons).
-- Pure Luau and fully deterministic: no Roblox globals and no math.random, so it
-- produces identical pixels in Roblox and under the standalone luau CLI.

local PixelArt = {}

export type Image = { width: number, height: number, pixels: buffer }
export type Run = { x: number, y: number, w: number, r: number, g: number, b: number }

local SIZE = 16

-- Colours are packed as 0xRRGGBB numbers while drawing.
local function rgb(r: number, g: number, b: number): number
	return r * 65536 + g * 256 + b
end

local function newImage(width: number, height: number): Image
	return { width = width, height = height, pixels = buffer.create(width * height * 4) }
end

local function put(image: Image, x: number, y: number, color: number, alpha: number)
	local offset = (y * image.width + x) * 4
	buffer.writeu8(image.pixels, offset, color // 65536)
	buffer.writeu8(image.pixels, offset + 1, color // 256 % 256)
	buffer.writeu8(image.pixels, offset + 2, color % 256)
	buffer.writeu8(image.pixels, offset + 3, alpha)
end

---------------------------------------------------------------------------
-- Noise
---------------------------------------------------------------------------

-- 32-bit multiply done in halves so it stays exact in double precision.
local function mul32(a: number, b: number): number
	local lo = a % 65536
	local hi = (a - lo) / 65536
	return (lo * b + (hi * b % 65536) * 65536) % 4294967296
end

local function hash(x: number, y: number, seed: number): number
	local h = bit32.bxor(x * 73856093 % 4294967296, y * 19349663 % 4294967296, seed * 83492791 % 4294967296)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	h = mul32(h, 0x85EBCA6B)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = mul32(h, 0xC2B2AE35)
	return bit32.bxor(h, bit32.rshift(h, 16))
end

local function rnd(x: number, y: number, seed: number): number
	return hash(x, y, seed) / 4294967296
end

-- Smooth value noise that wraps at the texture edge; cw/ch are the blob size in pixels.
local function vnoise(x: number, y: number, cw: number, ch: number, seed: number): number
	local nx, ny = SIZE // cw, SIZE // ch
	local fx, fy = x / cw, y / ch
	local x0, y0 = math.floor(fx), math.floor(fy)
	local tx, ty = fx - x0, fy - y0
	local x1, y1 = (x0 + 1) % nx, (y0 + 1) % ny
	tx = tx * tx * (3 - 2 * tx)
	ty = ty * ty * (3 - 2 * ty)
	local top = rnd(x0, y0, seed) * (1 - tx) + rnd(x1, y0, seed) * tx
	local bottom = rnd(x0, y1, seed) * (1 - tx) + rnd(x1, y1, seed) * tx
	return top * (1 - ty) + bottom * ty
end

-- Wrapping jittered-grid Voronoi, used for gravel pebbles.
-- Returns the cell id, the gap to the second-nearest cell (small = on a seam),
-- the offset from the cell centre and the distance to it.
local function voronoi(x: number, y: number, grid: number, seed: number): (number, number, number, number, number)
	local best, second = math.huge, math.huge
	local bestId, bestDx, bestDy = 0, 0, 0
	local cell = SIZE / grid
	for gy = 0, grid - 1 do
		for gx = 0, grid - 1 do
			local px = (gx + 0.2 + 0.6 * rnd(gx, gy, seed)) * cell
			local py = (gy + 0.2 + 0.6 * rnd(gx, gy, seed + 1)) * cell
			local dx = (x + 0.5 - px + SIZE / 2) % SIZE - SIZE / 2
			local dy = (y + 0.5 - py + SIZE / 2) % SIZE - SIZE / 2
			-- Blend of euclidean and chebyshev distance gives chunkier, squarer cells.
			local d = 0.5 * math.sqrt(dx * dx + dy * dy) + 0.5 * math.max(math.abs(dx), math.abs(dy))
			if d < best then
				second = best
				best, bestId, bestDx, bestDy = d, gy * grid + gx, dx, dy
			elseif d < second then
				second = d
			end
		end
	end
	return bestId, second - best, bestDx, bestDy, best
end

-- Picks a palette entry from v in [0,1); cuts are the ascending upper bounds.
local function pick(palette: { number }, cuts: { number }, v: number): number
	for i, cut in cuts do
		if v < cut then
			return palette[i]
		end
	end
	return palette[#palette]
end

local function clampIndex(palette: { number }, index: number): number
	return palette[math.clamp(index, 1, #palette)]
end

---------------------------------------------------------------------------
-- Block faces
---------------------------------------------------------------------------

type Painter = (x: number, y: number) -> number

local blocks: { [string]: Painter } = {}

local DIRT = { rgb(92, 64, 43), rgb(117, 83, 56), rgb(134, 96, 67), rgb(149, 108, 76), rgb(168, 126, 91) }
local DIRT_CUTS = { 0.09, 0.33, 0.74, 0.94 }

local function dirt(x: number, y: number): number
	if rnd(x, y, 102) < 0.03 then
		return rgb(140, 134, 126) -- pebble
	end
	return pick(DIRT, DIRT_CUTS, rnd(x, y, 101))
end
blocks.dirt = dirt

local GRASS = { rgb(70, 128, 42), rgb(86, 148, 49), rgb(100, 165, 57), rgb(115, 181, 67), rgb(134, 198, 84) }
local GRASS_CUTS = { 0.1, 0.34, 0.7, 0.92 }

local function grass(x: number, y: number): number
	return pick(GRASS, GRASS_CUTS, rnd(x, y, 111))
end
blocks.grass_top = grass

-- Overhang depth of the turf/snow fringe for a column.
local function fringeDepth(x: number, seed: number): number
	return 2 + math.floor(rnd(x, 0, seed) * 3)
end

blocks.grass_side = function(x, y)
	local depth = fringeDepth(x, 113)
	if y >= depth then
		return dirt(x, y)
	elseif y == depth - 1 then
		return if rnd(x, y, 114) < 0.5 then GRASS[1] else GRASS[2] -- shaded lip
	end
	return grass(x, y)
end

local STONE = { rgb(102, 102, 102), rgb(115, 115, 115), rgb(127, 127, 127), rgb(137, 137, 137), rgb(147, 147, 147) }
local STONE_CUTS = { 0.3, 0.43, 0.6, 0.72 }

local function stone(x: number, y: number): number
	-- Wide, short blobs plus 4px dashes give the horizontal streaks that read as stone.
	local dash = (x + math.floor(rnd(0, y, 123) * SIZE)) % SIZE // 4
	return pick(STONE, STONE_CUTS, vnoise(x, y, 4, 2, 121) * 0.5 + rnd(dash, y, 124) * 0.28 + rnd(x, y, 122) * 0.22)
end
blocks.stone = stone

local function grey(v: number): number
	return rgb(v, v, v)
end

-- Hand-drawn cobble layout: letters are individual stones, '.' is the seam.
local COBBLE_LAYOUT = {
	".AAAA..BBBB.CCC.",
	".AAAAA.BBBB.CCCC",
	".AAAAA.BBBB.CCCC",
	"..AAA..BBBB..CC.",
	"D.......BB....DD",
	"DD.EEEE...FFF.DD",
	"DD.EEEEE.FFFF.DD",
	"DD.EEEEE.FFFF.DD",
	"D...EEE..FFFF..D",
	"..........FF....",
	".GGG..HHHH..III.",
	"GGGG.HHHHHH.III.",
	"GGGG.HHHHHH.III.",
	"GGGG..HHHH..III.",
	".GG....HH...II..",
	"................",
}
local SEAM = string.byte(".")

local function cobbleStone(x: number, y: number): number
	local id = string.byte(COBBLE_LAYOUT[y % SIZE + 1], x % SIZE + 1)
	return id
end

-- Paints a stone layout as lumps lit from the top-left: bright upper/left rims,
-- dark lower/right rims. Each ramp is { shadow, body, light body, highlight }.
local function lumps(stoneAt: Painter, ramps: { { number } }, seams: { number }, seed: number): Painter
	return function(x, y)
		local id = stoneAt(x, y)
		if id == SEAM then
			return if rnd(x, y, seed) < 0.6 then seams[1] else seams[2]
		end
		local ramp = ramps[1 + id % #ramps]
		if stoneAt(x, y - 1) ~= id or stoneAt(x - 1, y) ~= id then
			return ramp[4]
		elseif stoneAt(x, y + 1) ~= id or stoneAt(x + 1, y) ~= id then
			return ramp[1]
		end
		return if rnd(x, y, seed + 1) < 0.6 then ramp[2] else ramp[3]
	end
end

blocks.cobblestone = lumps(cobbleStone, {
	{ grey(92), grey(116), grey(127), grey(152) },
	{ grey(102), grey(128), grey(139), grey(166) },
	{ grey(84), grey(106), grey(117), grey(142) },
}, { grey(54), grey(68) }, 131)

local BEDROCK = { rgb(18, 18, 18), rgb(40, 40, 40), rgb(62, 62, 62), rgb(88, 88, 88), rgb(116, 116, 116) }

blocks.bedrock = function(x, y)
	return pick(BEDROCK, { 0.3, 0.44, 0.58, 0.72 }, vnoise(x, y, 4, 4, 141) * 0.6 + rnd(x, y, 142) * 0.4)
end

local SAND = { rgb(196, 182, 134), rgb(209, 196, 150), rgb(219, 207, 163), rgb(229, 219, 178) }

blocks.sand = function(x, y)
	return pick(SAND, { 0.07, 0.27, 0.8 }, rnd(x, y, 151))
end

local SANDSTONE = { rgb(178, 160, 110), rgb(201, 186, 137), rgb(216, 203, 155), rgb(226, 215, 170), rgb(237, 228, 188) }

blocks.sandstone_top = function(x, y)
	if rnd(x, y, 156) < 0.04 then
		return SANDSTONE[2] -- pit
	end
	return pick(SANDSTONE, { 0, 0.12, 0.62, 0.94 }, vnoise(x, y, 4, 4, 157) * 0.5 + rnd(x, y, 158) * 0.5)
end

-- Vertical wobble of the sandstone strata lines per column.
local STRATA_WAVE = { 0, 0, 1, 1, 1, 0, 0, -1, -1, -1, 0, 0, 1, 1, 0, 0 }

blocks.sandstone_side = function(x, y)
	if y == 0 then
		return SANDSTONE[5]
	elseif y == 15 then
		return SANDSTONE[2]
	elseif y == 3 then
		return if rnd(x, y, 161) < 0.85 then SANDSTONE[1] else SANDSTONE[2]
	elseif y == 4 then
		return SANDSTONE[4]
	end
	local upper = 8 + STRATA_WAVE[x + 1]
	local lower = 12 - STRATA_WAVE[(x + 5) % SIZE + 1]
	if y == upper or y == lower then
		return if rnd(x, y, 162) < 0.8 then SANDSTONE[2] else SANDSTONE[1]
	elseif y == upper + 1 or y == lower + 1 then
		return SANDSTONE[4]
	end
	return pick(SANDSTONE, { 0, 0.1, 0.75, 0.96 }, rnd(x, y, 163))
end

local OAK_BARK = { rgb(50, 38, 22), rgb(70, 54, 32), rgb(88, 69, 42), rgb(103, 82, 50), rgb(120, 96, 60) }
-- Ridge/groove shade per column (index into the bark palette).
local OAK_BARK_COLUMNS = { 3, 4, 2, 1, 3, 4, 5, 3, 1, 2, 4, 3, 2, 1, 4, 5 }

local function barkSide(palette: { number }, columns: { number }, seed: number): Painter
	return function(x, y)
		-- Grooves wander sideways in 4px-tall segments so the bark is not ruler straight.
		local segment = (y + math.floor(rnd(x, 0, seed) * SIZE)) % SIZE // 4
		local wander = rnd(x, segment, seed + 1)
		local column = x
		if wander < 0.22 then
			column = (x + SIZE - 1) % SIZE
		elseif wander > 0.82 then
			column = (x + 1) % SIZE
		end
		local index = columns[column + 1]
		local jitter = rnd(x, y, seed + 2)
		if jitter < 0.1 then
			index -= 1
		elseif jitter > 0.93 then
			index += 1
		end
		return clampIndex(palette, index)
	end
end

local oakBark = barkSide(OAK_BARK, OAK_BARK_COLUMNS, 171)
blocks.oak_log_side = oakBark

local OAK_WOOD = { rgb(132, 104, 60), rgb(154, 123, 74), rgb(172, 139, 86), rgb(188, 154, 99) }
-- Wood shade per square growth ring, from the centre outwards.
local RING_SHADES = { 2, 4, 3, 2, 4, 3 }

local function logTop(bark: Painter, wood: { number }, seed: number): Painter
	return function(x, y)
		local ring = math.floor(math.max(math.abs(x - 7.5), math.abs(y - 7.5)))
		if ring == 7 then
			return bark(x, y)
		elseif ring == 6 then
			return wood[1]
		end
		local index = RING_SHADES[ring + 1]
		if rnd(x, y, seed) < 0.16 then
			index -= 1
		end
		return clampIndex(wood, index)
	end
end

blocks.oak_log_top = logTop(oakBark, OAK_WOOD, 175)

local BIRCH_BARK = { rgb(190, 188, 178), rgb(208, 206, 197), rgb(224, 222, 214), rgb(238, 236, 230) }
local BIRCH_MARK = { rgb(44, 40, 36), rgb(96, 92, 86) }
-- Dark lenticel dashes: x, y, length (wrapping horizontally).
local BIRCH_DASHES = {
	{ 1, 1, 4 }, { 9, 2, 3 }, { 13, 4, 5 }, { 4, 5, 2 }, { 6, 7, 5 },
	{ 0, 9, 2 }, { 11, 10, 4 }, { 3, 12, 3 }, { 8, 13, 2 }, { 14, 15, 4 },
}

local birchMarks: { [number]: number } = {}
for _, dash in BIRCH_DASHES do
	local x0, y0, length = dash[1], dash[2], dash[3]
	for i = 0, length - 1 do
		local soft = length >= 4 and (i == 0 or i == length - 1)
		birchMarks[y0 * SIZE + (x0 + i) % SIZE] = if soft then 2 else 1
	end
	if length >= 4 then
		-- A grey smudge under the long dashes gives them some depth.
		birchMarks[(y0 + 1) % SIZE * SIZE + (x0 + 1) % SIZE] = 2
		birchMarks[(y0 + 1) % SIZE * SIZE + (x0 + 2) % SIZE] = 2
	end
end

local function birchBark(x: number, y: number): number
	local mark = birchMarks[y * SIZE + x]
	if mark then
		return BIRCH_MARK[mark]
	end
	local index = 3 + math.floor(rnd(x // 2, 0, 181) * 2) - 1
	local jitter = rnd(x, y, 182)
	if jitter < 0.14 then
		index -= 1
	elseif jitter > 0.8 then
		index += 1
	end
	return clampIndex(BIRCH_BARK, index)
end
blocks.birch_log_side = birchBark

local BIRCH_WOOD = { rgb(160, 140, 92), rgb(184, 166, 114), rgb(200, 182, 128), rgb(214, 198, 146) }
blocks.birch_log_top = logTop(birchBark, BIRCH_WOOD, 185)

local OAK_LEAVES = { rgb(30, 76, 20), rgb(44, 100, 27), rgb(58, 122, 36), rgb(72, 144, 44), rgb(92, 166, 56) }
local BIRCH_LEAVES = { rgb(62, 96, 34), rgb(86, 124, 46), rgb(108, 148, 58), rgb(128, 168, 70), rgb(152, 188, 90) }

local function leaves(palette: { number }, seed: number): Painter
	return function(x, y)
		-- 2px clumps plus per-pixel grit: dense foliage with dark gaps.
		return pick(palette, { 0.27, 0.42, 0.6, 0.76 }, vnoise(x, y, 2, 2, seed) * 0.55 + rnd(x, y, seed + 1) * 0.45)
	end
end

blocks.oak_leaves = leaves(OAK_LEAVES, 191)
blocks.birch_leaves = leaves(BIRCH_LEAVES, 197)

local PLANKS = { rgb(96, 74, 42), rgb(120, 94, 54), rgb(146, 117, 68), rgb(162, 130, 78), rgb(176, 143, 88), rgb(190, 157, 101) }
-- Column of the butt joint in each of the four boards.
local PLANK_JOINTS = { 6, 13, 2, 9 }

blocks.oak_planks = function(x, y)
	local board, row = y // 4, y % 4
	local joint = PLANK_JOINTS[board + 1]
	if row == 3 then
		return if rnd(x, y, 201) < 0.3 then PLANKS[1] else PLANKS[2] -- seam between boards
	elseif x == joint then
		return PLANKS[2]
	end
	-- Grain runs along the board in short streaks that restart after the joint.
	local streak = (x - joint - 1) % SIZE // 5
	local grain = rnd(streak + board * 4, row, 202)
	local index = 4
	if row == 0 then
		index += 1
	end
	if grain < 0.3 then
		index -= 1
	elseif grain > 0.78 then
		index += 1
	end
	if rnd(x, y, 203) < 0.1 then
		index -= 1
	end
	return PLANKS[math.clamp(index, 3, 6)]
end

-- Running-bond bricks. Palette: mortar, shadow edge, 3 body shades, highlight edge.
local function bricks(palette: { number }, width: number, height: number, seed: number): Painter
	return function(x, y)
		local row = y // height
		local shifted = (x + row % 2 * (width // 2)) % SIZE
		local bx, by = shifted % width, y % height
		if by == height - 1 or bx == width - 1 then
			return palette[1]
		elseif by == 0 or bx == 0 then
			return if rnd(x, y, seed) < 0.2 then palette[5] else palette[6]
		elseif by == height - 2 or bx == width - 2 then
			return palette[2]
		end
		local index = 4
		local tone = rnd(row, shifted // width, seed + 1)
		if tone < 0.3 then
			index = 3
		elseif tone > 0.75 then
			index = 5
		end
		local jitter = rnd(x, y, seed + 2)
		if jitter < 0.18 then
			index -= 1
		elseif jitter > 0.85 then
			index += 1
		end
		return palette[math.clamp(index, 3, 5)]
	end
end

blocks.stone_bricks = bricks(
	{ rgb(70, 70, 70), rgb(98, 98, 98), rgb(113, 113, 113), rgb(123, 123, 123), rgb(133, 133, 133), rgb(152, 152, 152) },
	16, 8, 211
)
blocks.deepslate_bricks = bricks(
	{ rgb(26, 26, 28), rgb(46, 46, 49), rgb(60, 60, 63), rgb(70, 70, 73), rgb(80, 80, 84), rgb(100, 100, 105) },
	8, 8, 215
)

local SMOOTH_STONE = { rgb(124, 124, 124), rgb(151, 151, 151), rgb(160, 160, 160), rgb(168, 168, 168) }

blocks.smooth_stone = function(x, y)
	local ring = math.min(x, y, SIZE - 1 - x, SIZE - 1 - y)
	if ring == 0 then
		return if rnd(x, y, 221) < 0.2 then rgb(134, 134, 134) else SMOOTH_STONE[1]
	end
	return pick(SMOOTH_STONE, { 0, 0.2, 0.8 }, rnd(x, y, 222))
end

-- Ore fleck layout shared by all ores (l = light, m = mid, d = dark); each ore
-- uses a different mirror/transpose of it so they do not look identical.
local ORE_LAYOUT = {
	"................",
	"...lm.....lmm...",
	"..lmmd....mmd...",
	"...md......d....",
	"................",
	".......lm.......",
	"......lmmd...lm.",
	".......mdd...md.",
	".lm.............",
	".mmd.....lm.....",
	"..d.....lmmd....",
	".........mmd....",
	"....lm.......lm.",
	"...lmmd.....mmd.",
	"....dd.......d..",
	"................",
}
local ORE_SHADES = { l = 1, m = 2, d = 3 }

local function oreFleck(x: number, y: number, variant: number): number?
	if variant == 1 then
		x = SIZE - 1 - x
	elseif variant == 2 then
		x, y = y, SIZE - 1 - x
	end
	return ORE_SHADES[string.sub(ORE_LAYOUT[y + 1], x + 1, x + 1)]
end

local function ore(palette: { number }, variant: number): Painter
	return function(x, y)
		local fleck = oreFleck(x, y, variant)
		if fleck then
			return palette[fleck]
		elseif oreFleck(x, (y + SIZE - 1) % SIZE, variant) then
			return STONE[1] -- shadow under the fleck
		end
		return stone(x, y)
	end
end

blocks.coal_ore = ore({ rgb(74, 74, 74), rgb(42, 42, 42), rgb(20, 20, 20) }, 0)
blocks.iron_ore = ore({ rgb(238, 208, 186), rgb(216, 175, 147), rgb(172, 124, 94) }, 1)
blocks.diamond_ore = ore({ rgb(204, 255, 250), rgb(92, 232, 222), rgb(30, 164, 160) }, 2)

-- Glowstone reuses the cobble layout turned on its side, as chunky crystals.
blocks.glowstone = lumps(function(x, y)
	return cobbleStone(y + 5, SIZE - 1 - x)
end, {
	{ rgb(214, 160, 74), rgb(246, 208, 104), rgb(255, 230, 138), rgb(255, 250, 206) },
	{ rgb(202, 148, 66), rgb(240, 198, 96), rgb(252, 222, 128), rgb(255, 244, 186) },
}, { rgb(124, 84, 42), rgb(160, 112, 54) }, 231)

local OBSIDIAN = { rgb(9, 7, 16), rgb(19, 15, 31), rgb(30, 23, 47), rgb(46, 36, 68), rgb(70, 56, 98) }

blocks.obsidian = function(x, y)
	return pick(OBSIDIAN, { 0.3, 0.55, 0.72, 0.8 }, vnoise(x, y, 4, 2, 245) * 0.6 + rnd(x, y, 246) * 0.4)
end

local SNOW = { rgb(214, 228, 238), rgb(231, 240, 245), rgb(244, 249, 250), rgb(255, 255, 255) }

local function snow(x: number, y: number): number
	return pick(SNOW, { 0.05, 0.25, 0.8 }, rnd(x, y, 251))
end
blocks.snow = snow

blocks.snowy_grass_side = function(x, y)
	local depth = fringeDepth(x, 253) + 1
	if y >= depth then
		return dirt(x, y)
	elseif y == depth - 1 then
		return if rnd(x, y, 254) < 0.5 then rgb(196, 213, 228) else SNOW[1] -- shaded lip
	end
	return snow(x, y)
end

-- Pebble tones: grey, light grey and a brownish grey.
local GRAVEL = {
	{ rgb(98, 94, 92), rgb(120, 115, 113), rgb(140, 135, 133) },
	{ rgb(126, 122, 121), rgb(146, 142, 141), rgb(168, 164, 163) },
	{ rgb(104, 92, 84), rgb(124, 110, 101), rgb(143, 129, 119) },
}

blocks.gravel = function(x, y)
	local id, gap, dx, dy = voronoi(x, y, 5, 261)
	if gap < 0.45 then
		return if rnd(x, y, 262) < 0.5 then rgb(70, 66, 65) else rgb(84, 80, 78)
	end
	local tones = GRAVEL[1 + math.floor(rnd(id, 0, 263) * 3)]
	local lit = -(dx + dy)
	if lit > 0.5 then
		return tones[3]
	elseif lit < -0.8 then
		return tones[1]
	end
	return tones[2]
end

local function concrete(palette: { number }, seed: number): Painter
	return function(x, y)
		return pick(palette, { 0.14, 0.86 }, rnd(x, y, seed))
	end
end

blocks.red_concrete = concrete({ rgb(134, 30, 30), rgb(142, 33, 33), rgb(150, 37, 36) }, 271)
blocks.white_concrete = concrete({ rgb(198, 204, 206), rgb(207, 213, 214), rgb(214, 219, 220) }, 275)

---------------------------------------------------------------------------
-- Sprites (hand-pixelled character grids; '.' is transparent)
---------------------------------------------------------------------------

type Palette = { [string]: number }

local sprites: { [string]: () -> Image } = {}

local function drawSprite(rows: { string }, palette: Palette): Image
	local width = #rows[1]
	local image = newImage(width, #rows)
	for y, row in rows do
		for x = 1, width do
			local color = palette[string.sub(row, x, x)]
			if color then
				put(image, x - 1, y - 1, color, 255)
			end
		end
	end
	return image
end

local function sprite(key: string, rows: { string }, palette: Palette)
	sprites[key] = function()
		return drawSprite(rows, palette)
	end
end

-- o outline, l light, b body, d dark; h/k are the wooden handle and its outline.
local DIAMOND: Palette = {
	o = rgb(14, 74, 80), l = rgb(196, 255, 248), b = rgb(84, 226, 210), d = rgb(40, 166, 160),
	h = rgb(138, 100, 54), k = rgb(58, 38, 18),
}
local IRON: Palette = {
	o = rgb(58, 58, 64), l = rgb(252, 252, 252), b = rgb(208, 208, 212), d = rgb(150, 150, 158),
	h = rgb(138, 100, 54), k = rgb(58, 38, 18),
}

local SWORD = {
	".............olb",
	"............olbd",
	"...........olbdo",
	"..........olbdo.",
	".........olbdo..",
	"........olbdo...",
	".......olbdo....",
	"..oo..olbdo.....",
	".oddoolbdo......",
	"..obdlbdo.......",
	"...obddo........",
	"...khbdo........",
	"..khkobdo.......",
	".khk..oo........",
	"obk.............",
	"oo..............",
}

local HELMET = {
	"................",
	"................",
	"....oooooooo....",
	"...ollllbbbbo...",
	"..olbbbbbbbbdo..",
	"..olbbbbbbbbdo..",
	"..obbbbbbbbbdo..",
	"..obdddddddddo..",
	"..obboooooobdo..",
	"..obbo....obdo..",
	"..obdo....obdo..",
	"..oddo....oddo..",
	"..oooo....oooo..",
	"................",
	"................",
	"................",
}

local CHESTPLATE = {
	"................",
	"..oooo....oooo..",
	".ollbbo..obbbdo.",
	"olbbbbboobbbbbdo",
	"olbbbbbbbbbbbbdo",
	"obbdobbbbbbodbdo",
	"obbdolbbbbdodbdo",
	"obdoolbbbbdoobdo",
	"ooo.olbbbbdo.ooo",
	"....olbbbbdo....",
	"....obbbbbdo....",
	"....oddddddo....",
	"....olbbbbdo....",
	"....obbddddo....",
	"....oooooooo....",
	"................",
}

local LEGGINGS = {
	"................",
	"...oooooooooo...",
	"...ollllbbbdo...",
	"...obbbbbbbdo...",
	"...oddddddddo...",
	"...olbbbbbbdo...",
	"...olbboobbdo...",
	"...olbo..obdo...",
	"...olbo..obdo...",
	"...olbo..obdo...",
	"...obbo..obdo...",
	"...obbo..obdo...",
	"...obbo..obdo...",
	"...obdo..oddo...",
	"...oooo..oooo...",
	"................",
}

local BOOTS = {
	"................",
	"................",
	"................",
	"..ooooo..ooooo..",
	"..ollbo..obbdo..",
	"..olbbo..obbdo..",
	"..olbbo..obbdo..",
	"..obbbo..obbdo..",
	"ooobbbo..obbdooo",
	"olbbbbo..obbbbdo",
	"obbbbdo..obbbddo",
	"odddddo..odddddo",
	"ooooooo..ooooooo",
	"................",
	"................",
	"................",
}

local ARMOR_ROWS: { [string]: { string } } = { helmet = HELMET, chestplate = CHESTPLATE, leggings = LEGGINGS, boots = BOOTS }

for _, material in { { name = "diamond", palette = DIAMOND }, { name = "iron", palette = IRON } } do
	sprite(material.name .. "_sword", SWORD, material.palette)
	for piece, rows in ARMOR_ROWS do
		sprite(material.name .. "_" .. piece, rows, material.palette)
	end
end

sprite("coal", {
	"................",
	"................",
	"................",
	"......ooooo.....",
	"....oolbbbboo...",
	"...olbbbbdbbbo..",
	"..olbbbddbbbbdo.",
	"..obbbdbbbblbdo.",
	"..obbdbbbllbddo.",
	"..obbbbbbbbdddo.",
	"...obdbbbdbbdo..",
	"...oddbbbbdddo..",
	"....ooddddooo...",
	"......oooo......",
	"................",
	"................",
}, { o = rgb(6, 6, 8), l = rgb(92, 92, 96), b = rgb(44, 44, 46), d = rgb(24, 24, 26) })

sprite("raw_iron", {
	"................",
	"................",
	".......oooo.....",
	".....oollbbo....",
	"....olllbbbbo...",
	"..ooolbbbbmbdo..",
	".olbbobbbmmbbdo.",
	".olbbbbbmbbbddo.",
	".obbbmbbbbbbdo..",
	".obbmmbbbdbbdo..",
	"..obbbbbddbddo..",
	"..oddbbdddddo...",
	"...oodddddoo....",
	".....ooooo......",
	"................",
	"................",
}, {
	o = rgb(92, 62, 46), l = rgb(244, 220, 202), b = rgb(218, 178, 150), m = rgb(194, 150, 120), d = rgb(160, 114, 86),
})

sprite("diamond", {
	"................",
	"................",
	"................",
	"....oooooooo....",
	"...olwwlbbbdo...",
	"..olwlbbbbbbdo..",
	".ollbbbbbbbbbdo.",
	".obbbbbbbbbbddo.",
	"..obbbbbbbbddo..",
	"...olbbbbbddo...",
	"....obbbbddo....",
	".....obbddo.....",
	"......obdo......",
	".......oo.......",
	"................",
	"................",
}, { o = DIAMOND.o, l = DIAMOND.l, w = rgb(255, 255, 255), b = DIAMOND.b, d = DIAMOND.d })

-- Empty-slot placeholders: each armor piece's fill (without its outline) in one flat grey.
local SLOT_GREY: Palette = { l = rgb(100, 100, 100), b = rgb(100, 100, 100), d = rgb(100, 100, 100) }
sprite("slot_head", HELMET, SLOT_GREY)
sprite("slot_chest", CHESTPLATE, SLOT_GREY)
sprite("slot_legs", LEGGINGS, SLOT_GREY)
sprite("slot_feet", BOOTS, SLOT_GREY)

local HEART = {
	".kk...kk.",
	"krrk.krrk",
	"krwrkrrrk",
	"krrrrrrrk",
	"krrrrrrdk",
	".krrrrdk.",
	"..krrdk..",
	"...kdk...",
	"....k....",
}

local ARMOR = {
	".kkk.kkk.",
	"kllkkklgk",
	"klllllggk",
	"klllllggk",
	"kkllllgkk",
	".kllllgk.",
	".klllggk.",
	".kkgggkk.",
	"...kkk...",
}

-- Full / half / empty HUD icons from one drawing: columns from emptyFrom
-- onwards keep their outline but show the dark empty container instead.
local function hudIcon(key: string, rows: { string }, palette: Palette, emptyFrom: number)
	sprites[key] = function()
		local empty = table.clone(palette)
		for char in palette do
			if char ~= "k" then
				empty[char] = palette.e
			end
		end
		local image = drawSprite(rows, palette)
		local hollow = drawSprite(rows, empty)
		for x = emptyFrom, image.width - 1 do
			for y = 0, image.height - 1 do
				local offset = (y * image.width + x) * 4
				buffer.writeu32(image.pixels, offset, buffer.readu32(hollow.pixels, offset))
			end
		end
		return image
	end
end

local HEART_PALETTE: Palette = {
	k = rgb(0, 0, 0), r = rgb(255, 30, 30), d = rgb(180, 14, 22), w = rgb(255, 255, 255), e = rgb(52, 42, 46),
}
local ARMOR_PALETTE: Palette = {
	k = rgb(12, 12, 14), l = rgb(226, 226, 230), g = rgb(156, 156, 164), e = rgb(52, 52, 58),
}

hudIcon("heart_full", HEART, HEART_PALETTE, 9)
hudIcon("heart_half", HEART, HEART_PALETTE, 5)
hudIcon("heart_empty", HEART, HEART_PALETTE, 0)
hudIcon("armor_full", ARMOR, ARMOR_PALETTE, 9)
hudIcon("armor_half", ARMOR, ARMOR_PALETTE, 5)
hudIcon("armor_empty", ARMOR, ARMOR_PALETTE, 0)

sprite("bot_face", {
	"hhhhhhhh",
	"hhHhhHhh",
	"rrrrrrRr",
	"sbbssbbs",
	"swessews",
	"sssnnsss",
	"stmmmmts",
	"sttttttn",
}, {
	h = rgb(38, 30, 28), H = rgb(66, 52, 46), r = rgb(196, 38, 38), R = rgb(138, 22, 26),
	s = rgb(226, 174, 130), n = rgb(196, 144, 104), b = rgb(52, 36, 28), w = rgb(246, 246, 246),
	e = rgb(34, 110, 62), m = rgb(104, 54, 46), t = rgb(170, 124, 90),
})

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

PixelArt.BLOCK_KEYS = {
	"grass_top", "grass_side", "dirt", "stone", "cobblestone", "bedrock", "sand",
	"sandstone_top", "sandstone_side", "oak_log_side", "oak_log_top", "birch_log_side",
	"birch_log_top", "oak_leaves", "birch_leaves", "oak_planks", "stone_bricks",
	"smooth_stone", "coal_ore", "iron_ore", "diamond_ore", "glowstone", "obsidian",
	"snow", "snowy_grass_side", "gravel", "deepslate_bricks", "red_concrete", "white_concrete",
}

PixelArt.SPRITE_KEYS = {
	"diamond_sword", "iron_sword",
	"diamond_helmet", "diamond_chestplate", "diamond_leggings", "diamond_boots",
	"iron_helmet", "iron_chestplate", "iron_leggings", "iron_boots",
	"coal", "raw_iron", "diamond",
	"heart_full", "heart_half", "heart_empty",
	"armor_full", "armor_half", "armor_empty",
	"slot_head", "slot_chest", "slot_legs", "slot_feet",
	"bot_face",
}

local imageCache: { [string]: Image } = {}
local iconCache: { [string]: Image } = {}
local averageCache: { [string]: { number } } = {}

function PixelArt.get(key: string): Image?
	local cached = imageCache[key]
	if cached then
		return cached
	end
	local image: Image
	local painter = blocks[key]
	local drawer = sprites[key]
	if painter then
		image = newImage(SIZE, SIZE)
		for y = 0, SIZE - 1 do
			for x = 0, SIZE - 1 do
				put(image, x, y, painter(x, y), 255)
			end
		end
	elseif drawer then
		image = drawer()
	else
		return nil
	end
	imageCache[key] = image
	return image
end

-- Magenta/black checker shown for unknown keys in block icons.
local missing: Image? = nil
local function missingImage(): Image
	if missing then
		return missing
	end
	local image = newImage(SIZE, SIZE)
	for y = 0, SIZE - 1 do
		for x = 0, SIZE - 1 do
			put(image, x, y, if (x // 8 + y // 8) % 2 == 0 then rgb(255, 0, 255) else 0, 255)
		end
	end
	missing = image
	return image
end

local function copyShaded(from: Image, tx: number, ty: number, to: Image, x: number, y: number, brightness: number)
	local offset = (ty * from.width + tx) * 4
	local r = math.floor(buffer.readu8(from.pixels, offset) * brightness)
	local g = math.floor(buffer.readu8(from.pixels, offset + 1) * brightness)
	local b = math.floor(buffer.readu8(from.pixels, offset + 2) * brightness)
	put(to, x, y, rgb(r, g, b), 255)
end

function PixelArt.blockIcon(topKey: string, sideKey: string): Image
	local cacheKey = topKey .. "|" .. sideKey
	local cached = iconCache[cacheKey]
	if cached then
		return cached
	end
	local top = PixelArt.get(topKey) or missingImage()
	local side = PixelArt.get(sideKey) or missingImage()
	local icon = newImage(32, 32)
	for py = 0, 31 do
		for px = 0, 31 do
			local cx, cy = px + 0.5, py + 0.5
			-- Top face: a 32x16 rhombus whose axes run down-right and down-left.
			local across, down = (cx - 16) / 16, cy / 8
			local u, v = (down + across) / 2, (down - across) / 2
			if u >= 0 and u < 1 and v >= 0 and v < 1 then
				copyShaded(top, math.floor(u * SIZE), math.floor(v * SIZE), icon, px, py, 1)
			elseif px < 16 then
				local row = cy - (8 + cx / 2)
				if row >= 0 and row < 16 then
					copyShaded(side, px, math.floor(row), icon, px, py, 0.8)
				end
			else
				local row = cy - (16 - (cx - 16) / 2)
				if row >= 0 and row < 16 then
					copyShaded(side, px - 16, math.floor(row), icon, px, py, 0.6)
				end
			end
		end
	end
	iconCache[cacheKey] = icon
	return icon
end

function PixelArt.scaled(image: Image, factor: number): Image
	factor = math.max(1, math.floor(factor))
	local result = newImage(image.width * factor, image.height * factor)
	for y = 0, result.height - 1 do
		local sourceRow = (y // factor) * image.width
		for x = 0, result.width - 1 do
			local pixel = buffer.readu32(image.pixels, (sourceRow + x // factor) * 4)
			buffer.writeu32(result.pixels, (y * result.width + x) * 4, pixel)
		end
	end
	return result
end

function PixelArt.average(key: string): (number, number, number)
	local cached = averageCache[key]
	if cached then
		return cached[1], cached[2], cached[3]
	end
	local image = PixelArt.get(key)
	if not image then
		return 255, 0, 255
	end
	local r, g, b, count = 0, 0, 0, 0
	for offset = 0, image.width * image.height * 4 - 4, 4 do
		if buffer.readu8(image.pixels, offset + 3) >= 128 then
			r += buffer.readu8(image.pixels, offset)
			g += buffer.readu8(image.pixels, offset + 1)
			b += buffer.readu8(image.pixels, offset + 2)
			count += 1
		end
	end
	count = math.max(count, 1)
	local result = { math.round(r / count), math.round(g / count), math.round(b / count) }
	averageCache[key] = result
	return result[1], result[2], result[3]
end

function PixelArt.runs(image: Image): { Run }
	local runs: { Run } = {}
	for y = 0, image.height - 1 do
		local current: Run? = nil
		for x = 0, image.width - 1 do
			local offset = (y * image.width + x) * 4
			if buffer.readu8(image.pixels, offset + 3) >= 128 then
				local r = buffer.readu8(image.pixels, offset)
				local g = buffer.readu8(image.pixels, offset + 1)
				local b = buffer.readu8(image.pixels, offset + 2)
				if current and current.r == r and current.g == g and current.b == b then
					current.w += 1
				else
					local run: Run = { x = x, y = y, w = 1, r = r, g = g, b = b }
					current = run
					table.insert(runs, run)
				end
			else
				current = nil
			end
		end
	end
	return runs
end

return PixelArt
