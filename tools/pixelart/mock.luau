-- Draws a mock-up of the HUD and the inventory screen from the same sprites and the same GUI
-- coordinates the game uses (src/client/Hud.luau, Screens.luau), as a PPM image on stdout.
-- It is a layout preview, not a screenshot: text is not drawn and Roblox is not involved.
--   luau tools/pixelart/mock.luau -a inventory > mock.ppm && python3 tools/pixelart/ppm2png.py mock.ppm mock.png
-- Use "-a hud" for the HUD on its own.
local PixelArt = require("../../src/shared/PixelArt")

local args = { ... }
local showInventory = args[1] ~= "hud"
local S = 3 -- GUI scale
local W, H = 427, 240 -- screen size in GUI pixels (1281x720 on screen)
local canvas = buffer.create(W * S * H * S * 3)

local function plot(px: number, py: number, r: number, g: number, b: number, alpha: number)
	if px < 0 or py < 0 or px >= W * S or py >= H * S then
		return
	end
	local i = (py * W * S + px) * 3
	buffer.writeu8(canvas, i, math.floor(buffer.readu8(canvas, i) * (1 - alpha) + r * alpha))
	buffer.writeu8(canvas, i + 1, math.floor(buffer.readu8(canvas, i + 1) * (1 - alpha) + g * alpha))
	buffer.writeu8(canvas, i + 2, math.floor(buffer.readu8(canvas, i + 2) * (1 - alpha) + b * alpha))
end

-- Filled rectangle in GUI pixels.
local function rect(x: number, y: number, w: number, h: number, r: number, g: number, b: number, alpha: number?)
	for py = math.floor(y * S), math.floor((y + h) * S) - 1 do
		for px = math.floor(x * S), math.floor((x + w) * S) - 1 do
			plot(px, py, r, g, b, alpha or 1)
		end
	end
end

local function outline(x: number, y: number, w: number, h: number, t: number, r: number, g: number, b: number)
	rect(x, y, w, t, r, g, b)
	rect(x, y + h - t, w, t, r, g, b)
	rect(x, y, t, h, r, g, b)
	rect(x + w - t, y, t, h, r, g, b)
end

-- Draws an image into a box of `size` GUI pixels (nearest neighbour).
local function blit(image: PixelArt.Image?, x: number, y: number, width: number, height: number, clip: number?)
	if not image then
		return
	end
	local pw, ph = width * S, height * S
	for py = 0, ph - 1 do
		for px = 0, math.floor(pw * (clip or 1)) - 1 do
			local sx = math.floor(px * image.width / pw)
			local sy = math.floor(py * image.height / ph)
			local i = (sy * image.width + sx) * 4
			local a = buffer.readu8(image.pixels, i + 3)
			if a >= 128 then
				plot(x * S + px, y * S + py, buffer.readu8(image.pixels, i), buffer.readu8(image.pixels, i + 1), buffer.readu8(image.pixels, i + 2), 1)
			end
		end
	end
end

local BLOCK_ICONS = {
	oak_planks = { "oak_planks", "oak_planks" },
	cobblestone = { "cobblestone", "cobblestone" },
	grass = { "grass_top", "grass_side" },
	oak_log = { "oak_log_top", "oak_log_side" },
	glowstone = { "glowstone", "glowstone" },
}

local function item(key: string, x: number, y: number)
	local icon = BLOCK_ICONS[key]
	blit(if icon then PixelArt.blockIcon(icon[1], icon[2]) else PixelArt.get(key), x, y, 16, 16)
end

local function slot(x: number, y: number, key: string?, placeholder: string?)
	rect(x - 1, y - 1, 18, 18, 55, 55, 55)
	rect(x, y, 17, 17, 255, 255, 255)
	rect(x, y, 16, 16, 139, 139, 139)
	if key then
		item(key, x, y)
	elseif placeholder then
		blit(PixelArt.get(placeholder), x, y, 16, 16)
	end
end

-- Backdrop: sky and grass.
rect(0, 0, W, 130, 150, 190, 255)
for x = 0, W, 16 do
	blit(PixelArt.get("grass_top"), x, 130, 16, 16)
	for y = 146, H, 16 do
		blit(PixelArt.get("grass_side"), x, y, 16, 16)
	end
end

-- HUD: 182x80 block on the bottom edge.
local ox, oy = math.floor(W / 2) - 91, H - 80
rect(ox, oy + 58, 182, 22, 0, 0, 0, 0.55)
outline(ox, oy + 58, 182, 22, 1, 30, 30, 30)
for i = 0, 8 do
	outline(ox + 1 + i * 20, oy + 59, 20, 20, 1, 125, 125, 125)
end
local HOTBAR = { "diamond_sword", "golden_apple", "cooked_beef", "oak_planks", "cobblestone" }
for i, key in HOTBAR do
	item(key, ox + 3 + (i - 1) * 20, oy + 61)
end
outline(ox - 1, oy + 57, 24, 24, 1, 30, 30, 30)
outline(ox, oy + 58, 22, 22, 2, 225, 225, 225)
rect(ox, oy + 51, 182, 5, 0, 0, 0)
rect(ox + 1, oy + 52, 180, 3, 42, 56, 22)
rect(ox + 1, oy + 52, 70, 3, 128, 255, 32)
for i = 0, 9 do
	blit(PixelArt.get(if i < 7 then "heart_full" elseif i == 7 then "heart_half" else "heart_empty"), ox + i * 8, oy + 41, 9, 9)
	blit(PixelArt.get(if i < 8 then "armor_full" else "armor_empty"), ox + i * 8, oy + 21, 9, 9)
	blit(PixelArt.get(if i < 6 then "food_full" elseif i == 6 then "food_half" else "food_empty"), ox + 182 - 9 - i * 8, oy + 41, 9, 9)
end
blit(PixelArt.get("heart_absorb_full"), ox, oy + 31, 9, 9)
blit(PixelArt.get("heart_absorb_full"), ox + 8, oy + 31, 9, 9)

-- Crosshair and attack indicator (shown part-way recharged).
rect(W / 2 - 4, H / 2, 9, 1, 255, 255, 255)
rect(W / 2, H / 2 - 4, 1, 9, 255, 255, 255)
blit(PixelArt.get("attack_indicator_bg"), math.floor(W / 2) - 8, math.floor(H / 2) + 9, 16, 4)
blit(PixelArt.get("attack_indicator_fill"), math.floor(W / 2) - 8, math.floor(H / 2) + 9, 16, 4, 0.6)

local function drawInventory()
	-- Inventory window: dimmed screen, then the 176x166 panel centred.
	rect(0, 0, W, H, 0, 0, 0, 0.5)
	local px, py = math.floor(W / 2) - 88, math.floor(H / 2) - 83
	rect(px, py, 176, 166, 0, 0, 0)
	rect(px + 1, py + 1, 174, 164, 85, 85, 85)
	rect(px + 1, py + 1, 172, 162, 255, 255, 255)
	rect(px + 3, py + 3, 170, 160, 198, 198, 198)
	local ARMOR = { "diamond_helmet", "diamond_chestplate", "diamond_leggings", false }
	local PLACEHOLDERS = { "slot_head", "slot_chest", "slot_legs", "slot_feet" }
	for i = 1, 4 do
		slot(px + 8, py + 8 + (i - 1) * 18, ARMOR[i] or nil, PLACEHOLDERS[i])
	end
	rect(px + 25, py + 7, 51, 72, 55, 55, 55)
	rect(px + 26, py + 8, 50, 71, 255, 255, 255)
	rect(px + 26, py + 8, 49, 70, 0, 0, 0)
	slot(px + 77, py + 62, nil, "slot_offhand")
	slot(px + 98, py + 18, "oak_log")
	slot(px + 116, py + 18)
	slot(px + 98, py + 36)
	slot(px + 116, py + 36)
	blit(PixelArt.get("gui_arrow"), px + 135, py + 29, 16, 13)
	slot(px + 154, py + 28, "oak_planks")
	local MAIN = { [1] = "iron_sword", [2] = "iron_boots", [5] = "grass", [10] = "glowstone", [14] = "diamond", [20] = "coal", [27] = "raw_iron" }
	for row = 0, 2 do
		for col = 0, 8 do
			slot(px + 8 + col * 18, py + 84 + row * 18, MAIN[row * 9 + col + 1])
		end
	end
	for col = 0, 8 do
		slot(px + 8 + col * 18, py + 142, HOTBAR[col + 1])
	end
	-- Hovered slot highlight and the stack carried by the mouse.
	rect(px + 8 + 3 * 18, py + 84, 16, 16, 255, 255, 255, 0.5)
	item("diamond_boots", px + 8 + 3 * 18 + 6, py + 84 + 5)
end

if showInventory then
	drawInventory()
end

local out = { "P3", `{W * S} {H * S}`, "255" }
for py2 = 0, H * S - 1 do
	local row = table.create(W * S)
	for px2 = 0, W * S - 1 do
		local i = (py2 * W * S + px2) * 3
		row[px2 + 1] = `{buffer.readu8(canvas, i)} {buffer.readu8(canvas, i + 1)} {buffer.readu8(canvas, i + 2)}`
	end
	table.insert(out, table.concat(row, " "))
end
print(table.concat(out, "\n"))
