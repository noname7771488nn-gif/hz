-- Spawn hub, floating PvP arena, world border and teleport destinations.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Blocks = require(Shared.Blocks)
local Zones = require(Shared.Zones)

local World = require(script.Parent.World)

local Structures = {}

local B = Config.BLOCK_SIZE
local SPAWN = Config.SPAWN
local ARENA = Config.ARENA
local ID = World.ID

-- Root part height above the block it stands on.
local STAND_OFFSET = B / 2 + 3.2

local ARENA_PILLARS = { { -7, -7 }, { 7, -7 }, { -7, 7 }, { 7, 7 } }

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
			World.rawSet(x, fy, z, if ring == 4 or ring == 0 then ID.smooth_stone else ID.stone_bricks)

			local gate = math.abs(x) <= 1 or math.abs(z) <= 1
			if ring == r and not gate then
				World.rawSet(x, fy + 1, z, ID.stone_bricks)
			end
		end
	end
	World.rawSet(0, fy, 0, ID.glowstone)

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
	billboard.Size = UDim2.fromScale(24, #lines * 1.6)
	billboard.MaxDistance = 150
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

local function borderWall(position: Vector3, size: Vector3)
	local wall = Instance.new("Part")
	wall.Name = "WorldBorder"
	wall.Anchored = true
	wall.CanQuery = false
	wall.Transparency = 1
	wall.Size = size
	wall.Position = position
	wall.Parent = workspace
end

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

	local gold, white, gray = Color3.fromRGB(255, 200, 60), Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190)
	hologram(Vector3.new(0, (fy + 6) * B, 0), {
		{ text = `Welcome to {Config.GAME_NAME}!`, color = gold },
		{ text = "/kit - claim the Diamond kit", color = white },
		{ text = "/rtp - teleport into the wild", color = white },
		{ text = "/pvp - PvP arena    /help - all commands", color = white },
		{ text = "Spawn is protected", color = gray },
	})

	-- Invisible world border.
	local span = World.RADIUS * 2 * B
	local half = World.RADIUS * B
	local height = World.HEIGHT * B * 2
	borderWall(Vector3.new(-half - B / 2 - 1, height / 2, 0), Vector3.new(2, height, span + 8))
	borderWall(Vector3.new(half - B / 2 + 1, height / 2, 0), Vector3.new(2, height, span + 8))
	borderWall(Vector3.new(0, height / 2, -half - B / 2 - 1), Vector3.new(span + 8, height, 2))
	borderWall(Vector3.new(0, height / 2, half - B / 2 + 1), Vector3.new(span + 8, height, 2))
end

-- Floating arena outside the voxel world. Built from plain parts so it can never be edited.
function Structures.buildArena()
	local model = Instance.new("Model")
	model.Name = "PvPArena"

	local function place(key: string, x: number, y: number, z: number)
		local def = Blocks.byKey[key]
		local part = Instance.new("Part")
		part.Name = key
		part.Anchored = true
		part.Size = Vector3.one * B
		part.CFrame = CFrame.new((ARENA.centerX + x) * B, y * B, (ARENA.centerZ + z) * B)
		Blocks.applyAppearance(part, def)
		if def.light then
			local light = Instance.new("PointLight")
			light.Color = def.light
			light.Range = 20
			light.Parent = part
		end
		part.Parent = model
	end

	local r = ARENA.radius
	local fy = ARENA.floorY
	for x = -r, r do
		for z = -r, r do
			local ring = math.max(math.abs(x), math.abs(z))
			local floor = if ring == r then "obsidian" elseif ring % 5 == 0 then "stone_bricks" else "smooth_stone"
			place(floor, x, fy, z)
			if ring == r then
				for y = fy + 1, fy + 5 do
					place("stone_bricks", x, y, z)
				end
				place("obsidian", x, fy + 6, z)
			end
		end
	end
	for _, p in ARENA_PILLARS do
		for y = fy + 1, fy + 3 do
			place("cobblestone", p[1], y, p[2])
		end
		place("glowstone", p[1], fy + 4, p[2])
	end
	model.Parent = workspace

	hologram(Vector3.new(ARENA.centerX * B, (fy + 9) * B, ARENA.centerZ * B), {
		{ text = "PvP Arena", color = Color3.fromRGB(255, 85, 85) },
		{ text = "Kill players to loot their items", color = Color3.new(1, 1, 1) },
	})
end

function Structures.spawnCFrame(): CFrame
	local offset = Vector3.new(math.random(-3, 3), 0, math.random(2, 5)) * B
	local position = Vector3.new(0, SPAWN.floorY * B + STAND_OFFSET, 0) + offset
	return CFrame.lookAt(position, Vector3.new(0, position.Y, 0))
end

function Structures.arenaCFrame(): CFrame
	local r = ARENA.radius - 2
	local x, z
	repeat
		x, z = math.random(-r, r), math.random(-r, r)
		local blocked = false
		for _, p in ARENA_PILLARS do
			if math.abs(p[1] - x) <= 1 and math.abs(p[2] - z) <= 1 then
				blocked = true
			end
		end
	until not blocked
	local position = Vector3.new((ARENA.centerX + x) * B, ARENA.floorY * B + STAND_OFFSET, (ARENA.centerZ + z) * B)
	return CFrame.lookAt(position, Vector3.new(ARENA.centerX * B, position.Y, ARENA.centerZ * B))
end

-- Random safe spot on the surface of the wilderness, or nil if none was found.
function Structures.randomWildCFrame(): CFrame?
	local margin = 6
	local r = World.RADIUS
	for _ = 1, 60 do
		local x = math.random(-r + margin, r - margin - 1)
		local z = math.random(-r + margin, r - margin - 1)
		if Zones.cellZone(x, z) ~= "wild" or math.max(math.abs(x), math.abs(z)) <= SPAWN.radius + 10 then
			continue
		end
		local y = World.topY(x, z)
		if not y or y + 3 >= World.HEIGHT then
			continue
		end
		local top = World.get(x, y, z)
		if top == ID.oak_leaves or top == ID.oak_log then
			continue
		end
		return CFrame.new(x * B, y * B + STAND_OFFSET, z * B)
	end
	return nil
end

return Structures
