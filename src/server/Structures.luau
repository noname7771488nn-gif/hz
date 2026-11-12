-- Spawn hub, the PvP warp (safe spawn platform above an FFA arena), world border and teleport spots.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Zones = require(Shared.Zones)

local World = require(script.Parent.World)

local Structures = {}

local B = Config.BLOCK_SIZE
local SPAWN = Config.SPAWN
local ARENA = Config.ARENA
local ID = World.ID

-- Root part height above the centre of the block a character stands on.
local STAND_OFFSET = B / 2 + 3.1

-- Voxel spawn hub; called during generation before parts are built.
function Structures.writeSpawn()
	local r = SPAWN.radius
	local fy = SPAWN.floorY
	for x = -r, r do
		for z = -r, r do
			for y = fy + 1, World.HEIGHT - 1 do
				World.rawSet(x, y, z, 0)
			end
			local ring = math.max(math.abs(x), math.abs(z))
			local path = math.abs(x) <= 1 or math.abs(z) <= 1
			local floor = ID.stone_bricks
			if ring <= 1 or (not path and (ring == 8 or ring == r)) then
				floor = ID.smooth_stone
			elseif path then
				floor = ID.oak_planks
			elseif (x + z) % 7 == 0 then
				floor = ID.cobblestone
			end
			World.rawSet(x, fy, z, floor)

			-- Low perimeter wall with a gate on each side.
			if ring == r and not path then
				World.rawSet(x, fy + 1, z, ID.stone_bricks)
				if (x + z) % 4 == 0 then
					World.rawSet(x, fy + 2, z, ID.stone_bricks)
				end
			end
		end
	end
	World.rawSet(0, fy, 0, ID.glowstone)

	-- Open pavilion: four pillars carrying a plank ring around the spawn point.
	for _, c in { { 5, 5 }, { -5, 5 }, { 5, -5 }, { -5, -5 } } do
		for y = fy + 1, fy + 4 do
			World.rawSet(c[1], y, c[2], ID.oak_log)
		end
	end
	for x = -6, 6 do
		for z = -6, 6 do
			local ring = math.max(math.abs(x), math.abs(z))
			if ring >= 5 then
				World.rawSet(x, fy + 5, z, if ring == 6 then ID.oak_planks else ID.stone_bricks)
			end
		end
	end
	for _, c in { { 5, 0 }, { -5, 0 }, { 0, 5 }, { 0, -5 } } do
		World.rawSet(c[1], fy + 5, c[2], ID.glowstone)
	end

	-- Lamp posts in the corners.
	for _, c in { { r - 2, r - 2 }, { -r + 2, r - 2 }, { r - 2, -r + 2 }, { -r + 2, -r + 2 } } do
		for y = fy + 1, fy + 3 do
			World.rawSet(c[1], y, c[2], ID.oak_log)
		end
		World.rawSet(c[1], fy + 4, c[2], ID.glowstone)
	end
end

local function hologram(position: Vector3, lines: { { text: string, color: Color3 } })
	local anchor = Instance.new("Part")
	anchor.Name = "Hologram"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = position
	anchor.Parent = workspace

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(26, #lines * 1.5)
	billboard.MaxDistance = 160
	billboard.LightInfluence = 0
	billboard.Parent = anchor

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = billboard

	for i, line in lines do
		local label = Instance.new("TextLabel")
		label.LayoutOrder = i
		label.Size = UDim2.fromScale(1, 1 / #lines)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.Arcade
		label.TextScaled = true
		label.Text = line.text
		label.TextColor3 = line.color
		label.TextStrokeTransparency = 0.4
		label.Parent = billboard
	end
end

local function barrier(position: Vector3, size: Vector3)
	local wall = Instance.new("Part")
	wall.Name = "Barrier"
	wall.Anchored = true
	wall.CanQuery = false
	wall.Transparency = 1
	wall.Size = size
	wall.Position = position
	wall.Parent = workspace
end

-- Four invisible walls around a square, so nobody can be knocked or climb out.
local function fence(center: Vector3, half: number, height: number)
	local span = half * 2 + 4
	barrier(center + Vector3.new(-half - 1, height / 2, 0), Vector3.new(2, height, span))
	barrier(center + Vector3.new(half + 1, height / 2, 0), Vector3.new(2, height, span))
	barrier(center + Vector3.new(0, height / 2, -half - 1), Vector3.new(span, height, 2))
	barrier(center + Vector3.new(0, height / 2, half + 1), Vector3.new(span, height, 2))
end

local GOLD, WHITE, GRAY, RED = Color3.fromRGB(255, 200, 60), Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190), Color3.fromRGB(255, 85, 85)

function Structures.buildDecor()
	local fy = SPAWN.floorY
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn.CanTouch = false
	spawn.Transparency = 1
	spawn.Duration = 0 -- no Roblox force field
	spawn.Neutral = true
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.Position = Vector3.new(0, fy * B + B / 2 + 0.5, 0)
	spawn.Parent = workspace

	hologram(Vector3.new(0, (fy + 3.4) * B, -3 * B), {
		{ text = `Welcome to {Config.GAME_NAME}!`, color = GOLD },
		{ text = "/kits - choose a kit", color = WHITE },
		{ text = "/pvp - PvP warp    /rtp - into the wild", color = WHITE },
		{ text = "Press T to chat, /help for commands", color = GRAY },
	})

	-- World border. The world occupies block centres -R .. R-1, so shift by half a block.
	local half = World.RADIUS * B
	fence(Vector3.new(-B / 2, 0, -B / 2), half, World.HEIGHT * B * 2)
end

-- The PvP warp, built from fixed blocks outside the voxel world so it can never be edited.
function Structures.buildArena()
	local folder = Instance.new("Folder")
	folder.Name = "Arena"

	local cells: { [Vector3]: number } = {}
	local function set(x: number, y: number, z: number, key: string)
		cells[Vector3.new(ARENA.centerX + x, y, ARENA.centerZ + z)] = ID[key]
	end
	local function box(x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, key: string)
		for x = x0, x1 do
			for y = y0, y1 do
				for z = z0, z1 do
					set(x, y, z, key)
				end
			end
		end
	end

	local r = ARENA.radius
	local fy = ARENA.floorY
	local top = fy + ARENA.wallHeight

	-- Floor: worn stone with gravel and cobble patches, ringed by deepslate walls.
	for x = -r, r do
		for z = -r, r do
			local ring = math.max(math.abs(x), math.abs(z))
			local n = math.noise(x / 6, z / 6, 3.3)
			local floor = "stone_bricks"
			if ring == r then
				floor = "deepslate_bricks"
			elseif ring <= 2 or ring % 9 == 0 then
				floor = "smooth_stone"
			elseif n > 0.22 then
				floor = "gravel"
			elseif n < -0.22 then
				floor = "cobblestone"
			end
			set(x, fy, z, floor)
			if ring == r then
				for y = fy + 1, top - 1 do
					set(x, y, z, if y == fy + 3 and (x + z) % 6 == 0 then "glowstone" else "deepslate_bricks")
				end
				set(x, top, z, "obsidian")
			end
		end
	end
	set(0, fy, 0, "glowstone")

	-- Cover: pillars, low walls to jump over and taller corners to fight around.
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			box(sx * 11 - 1, sx * 11, fy + 1, fy + 3, sz * 11 - 1, sz * 11, "cobblestone")
			box(sx * 11 - 1, sx * 11, fy + 4, fy + 4, sz * 11 - 1, sz * 11, "stone_bricks")
			box(sx * 19, sx * 19, fy + 1, fy + 2, math.min(sz * 16, sz * 20), math.max(sz * 16, sz * 20), "oak_planks")
			box(math.min(sx * 16, sx * 19), math.max(sx * 16, sx * 19), fy + 1, fy + 2, sz * 20, sz * 20, "oak_planks")
		end
		box(-4, 4, fy + 1, fy + 1, sx * 16, sx * 16, "stone_bricks")
		box(sx * 16, sx * 16, fy + 1, fy + 1, -4, 4, "stone_bricks")
	end

	-- Safe spawn platform floating above the centre.
	local sr = ARENA.spawnRadius
	local py = fy + ARENA.spawnHeight
	for x = -sr, sr do
		for z = -sr, sr do
			local ring = math.max(math.abs(x), math.abs(z))
			set(x, py, z, if ring == sr then "red_concrete" elseif ring == 0 then "glowstone" else "white_concrete")
		end
	end
	for _, sx in { -sr, sr } do
		for _, sz in { -sr, sr } do
			box(sx, sx, py + 1, py + 2, sz, sz, "oak_log")
			set(sx, py + 3, sz, "glowstone")
		end
	end

	-- Faces under the floor and outside the walls are never seen.
	World.buildStatic(cells, folder, function(cell: Vector3): boolean
		return cell.Y < fy or math.abs(cell.X - ARENA.centerX) > r or math.abs(cell.Z - ARENA.centerZ) > r
	end)
	folder.Parent = workspace

	local center = Vector3.new(ARENA.centerX * B, fy * B, ARENA.centerZ * B)
	fence(center, (r + 0.5) * B, 400)

	hologram(Vector3.new(center.X, (py + 4.5) * B, center.Z), {
		{ text = "PvP Warp", color = RED },
		{ text = "You are safe up here", color = WHITE },
		{ text = "Jump down to fight - no fall damage", color = WHITE },
		{ text = "Kill players to loot their items", color = GRAY },
	})
end

function Structures.spawnCFrame(): CFrame
	local offset = Vector3.new(math.random(-3, 3), 0, math.random(2, 4)) * B
	local position = Vector3.new(0, SPAWN.floorY * B + STAND_OFFSET, 0) + offset
	return CFrame.lookAt(position, Vector3.new(0, position.Y, -30))
end

-- A spot on the PvP warp's safe platform, facing outward over the arena.
function Structures.arenaSpawnCFrame(): CFrame
	local r = ARENA.spawnRadius - 2
	local x, z
	repeat
		x, z = math.random(-r, r), math.random(-r, r)
	until x ~= 0 or z ~= 0
	local y = (ARENA.floorY + ARENA.spawnHeight) * B + STAND_OFFSET
	local position = Vector3.new((ARENA.centerX + x) * B, y, (ARENA.centerZ + z) * B)
	return CFrame.lookAt(position, position + Vector3.new(x, 0, z))
end

-- Where the bot (re)spawns: on the arena floor beside the centre pad.
function Structures.arenaFloorCFrame(): CFrame
	local angle = math.random() * math.pi * 2
	local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * 6 * B
	local center = Vector3.new(ARENA.centerX * B, ARENA.floorY * B + STAND_OFFSET, ARENA.centerZ * B)
	return CFrame.lookAt(center + offset, center)
end

-- Random safe spot on the surface of the wilderness, or nil if none was found.
function Structures.randomWildCFrame(): CFrame?
	local margin = 6
	-- Only land where the terrain's parts already exist.
	local r = math.min(World.RADIUS, World.builtRadius) - margin
	if r <= SPAWN.radius + 12 then
		return nil
	end
	for _ = 1, 60 do
		local x = math.random(-r, r - 1)
		local z = math.random(-r, r - 1)
		if math.max(math.abs(x), math.abs(z)) <= SPAWN.radius + 10 then
			continue
		end
		local y = World.topY(x, z)
		if not y or y + 3 >= World.HEIGHT or Zones.cellZone(x, y, z) ~= "wild" then
			continue
		end
		local top = World.get(x, y, z)
		if top == ID.oak_leaves or top == ID.oak_log or top == ID.birch_leaves or top == ID.birch_log then
			continue
		end
		return CFrame.new(x * B, y * B + STAND_OFFSET, z * B)
	end
	return nil
end

return Structures
