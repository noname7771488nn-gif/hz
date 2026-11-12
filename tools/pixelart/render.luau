--!strict
-- Contact sheet of every PixelArt texture as a plain-text PPM (P3) on stdout.
-- Usage (from the repo root):
--   luau tools/pixelart/render.luau -a [all|blocks|sprites] [scale] [firstBlock] [lastBlock] > sheet.ppm
--   luau tools/pixelart/render.luau -a keys [scale] key1,key2,... > sheet.ppm
--   python3 tools/pixelart/ppm2png.py sheet.ppm sheet.png
-- In keys mode block faces are tiled 3x3 and sprites (any size) are drawn once.

local PixelArt = require("../../src/shared/PixelArt")

type Image = PixelArt.Image

local args = { ... }
local mode: string = args[1] or "all"
local scale: number = tonumber(args[2]) or 6
local firstBlock: number = tonumber(args[3]) or 1
local lastBlock: number = tonumber(args[4]) or #PixelArt.BLOCK_KEYS

local GAP = 8
local ICON_PAIRS = {
	{ "grass_top", "grass_side" },
	{ "oak_log_top", "oak_log_side" },
	{ "birch_log_top", "birch_log_side" },
	{ "stone", "stone" },
	{ "cobblestone", "cobblestone" },
	{ "oak_planks", "oak_planks" },
	{ "diamond_ore", "diamond_ore" },
	{ "sandstone_top", "sandstone_side" },
	{ "snow", "snowy_grass_side" },
	{ "stone_bricks", "stone_bricks" },
	{ "glowstone", "glowstone" },
	{ "oak_leaves", "oak_leaves" },
}

-- Each entry is one cell of the sheet: an image, how often it repeats and its zoom.
type Cell = { image: Image, tiles: number, zoom: number }
local sections: { { Cell } } = {}

if mode == "keys" then
	local cells: { Cell } = {}
	for key in string.gmatch(args[3] or "", "[^,]+") do
		local image = PixelArt.get(key)
		assert(image, "unknown key " .. key)
		local isBlock = table.find(PixelArt.BLOCK_KEYS, key) ~= nil
		table.insert(cells, { image = image, tiles = if isBlock then 3 else 1, zoom = scale })
	end
	table.insert(sections, cells)
elseif mode ~= "sprites" then
	local cells: { Cell } = {}
	for index = firstBlock, lastBlock do
		local image = PixelArt.get(PixelArt.BLOCK_KEYS[index])
		assert(image, "missing block " .. PixelArt.BLOCK_KEYS[index])
		table.insert(cells, { image = image, tiles = 3, zoom = scale })
	end
	table.insert(sections, cells)
end

if mode ~= "blocks" and mode ~= "keys" then
	local icons: { Cell } = {}
	for _, pair in ICON_PAIRS do
		table.insert(icons, { image = PixelArt.blockIcon(pair[1], pair[2]), tiles = 1, zoom = scale })
	end
	table.insert(sections, icons)

	local sprites: { Cell } = {}
	for _, key in PixelArt.SPRITE_KEYS do
		local image = PixelArt.get(key)
		assert(image, "missing sprite " .. key)
		table.insert(sprites, { image = image, tiles = 1, zoom = scale })
	end
	table.insert(sections, sprites)
end

-- Lay the cells out in rows, wrapping so the sheet stays easy to view.
local MAX_WIDTH = 1600
type Placed = { cell: Cell, x: number, y: number }
local placed: { Placed } = {}
local sheetWidth, cursorY = 0, GAP

for _, cells in sections do
	local cursorX, rowHeight = GAP, 0
	for _, cell in cells do
		local w = cell.image.width * cell.tiles * cell.zoom
		local h = cell.image.height * cell.tiles * cell.zoom
		if cursorX + w + GAP > MAX_WIDTH and cursorX > GAP then
			cursorX = GAP
			cursorY += rowHeight + GAP
			rowHeight = 0
		end
		table.insert(placed, { cell = cell, x = cursorX, y = cursorY })
		cursorX += w + GAP
		rowHeight = math.max(rowHeight, h)
		sheetWidth = math.max(sheetWidth, cursorX)
	end
	cursorY += rowHeight + GAP * 2
end

local sheetHeight = cursorY
local canvas = buffer.create(sheetWidth * sheetHeight * 3)
buffer.fill(canvas, 0, 36)

for _, entry in placed do
	local cell = entry.cell
	local image = cell.image
	local zoom = cell.zoom
	local w, h = image.width * cell.tiles * zoom, image.height * cell.tiles * zoom
	for py = 0, h - 1 do
		for px = 0, w - 1 do
			local sx, sy = px // zoom % image.width, py // zoom % image.height
			local source = (sy * image.width + sx) * 4
			local r = buffer.readu8(image.pixels, source)
			local g = buffer.readu8(image.pixels, source + 1)
			local b = buffer.readu8(image.pixels, source + 2)
			if buffer.readu8(image.pixels, source + 3) < 128 then
				-- Mid-grey checker behind transparent pixels.
				local shade = if (px // zoom + py // zoom) % 2 == 0 then 132 else 116
				r, g, b = shade, shade, shade
			end
			local target = ((entry.y + py) * sheetWidth + entry.x + px) * 3
			buffer.writeu8(canvas, target, r)
			buffer.writeu8(canvas, target + 1, g)
			buffer.writeu8(canvas, target + 2, b)
		end
	end
end

print("P3")
print(`{sheetWidth} {sheetHeight}`)
print("255")
local triplets: { [number]: string } = {}
local line = table.create(sheetWidth)
for y = 0, sheetHeight - 1 do
	for x = 0, sheetWidth - 1 do
		local offset = (y * sheetWidth + x) * 3
		local r, g, b = buffer.readu8(canvas, offset), buffer.readu8(canvas, offset + 1), buffer.readu8(canvas, offset + 2)
		local packed = r * 65536 + g * 256 + b
		local text = triplets[packed]
		if not text then
			text = `{r} {g} {b}`
			triplets[packed] = text
		end
		line[x + 1] = text
	end
	print(table.concat(line, " "))
end
