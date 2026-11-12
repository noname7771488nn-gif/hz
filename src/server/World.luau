-- Voxel world. Block ids live in a flat buffer; only blocks touching air get a Part,
-- so a 128x128 world costs tens of thousands of parts instead of over a million.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Blocks = require(Shared.Blocks)

local World = {}

local B = Config.BLOCK_SIZE
local R = Config.WORLD_RADIUS
local W = R * 2
local H = Config.WORLD_HEIGHT

local data = buffer.create(W * W * H)
local parts: { [number]: BasePart } = {}
local folder: Folder? = nil

local NEIGHBORS = {
	{ 1, 0, 0 },
	{ -1, 0, 0 },
	{ 0, 1, 0 },
	{ 0, -1, 0 },
	{ 0, 0, 1 },
	{ 0, 0, -1 },
}

World.HEIGHT = H
World.RADIUS = R

local function inBounds(x: number, y: number, z: number): boolean
	return x >= -R and x < R and z >= -R and z < R and y >= 0 and y < H
end
World.inBounds = inBounds

local function index(x: number, y: number, z: number): number
	return (y * W + (z + R)) * W + (x + R)
end

function World.get(x: number, y: number, z: number): number
	if not inBounds(x, y, z) then
		return 0
	end
	return buffer.readu8(data, index(x, y, z))
end

-- Writes without touching parts; only for generation before parts are built.
function World.rawSet(x: number, y: number, z: number, id: number)
	if inBounds(x, y, z) then
		buffer.writeu8(data, index(x, y, z), id)
	end
end

function World.toWorld(x: number, y: number, z: number): Vector3
	return Vector3.new(x * B, y * B, z * B)
end

function World.toGrid(position: Vector3): (number, number, number)
	return math.round(position.X / B), math.round(position.Y / B), math.round(position.Z / B)
end

local function occludes(x: number, y: number, z: number): boolean
	if y < 0 then
		return true
	elseif y >= H then
		return false
	elseif x < -R or x >= R or z < -R or z >= R then
		-- Treat beyond the border as solid so the world's outer walls aren't built.
		return true
	end
	local id = buffer.readu8(data, index(x, y, z))
	if id == 0 then
		return false
	end
	return not Blocks.byId[id].transparent
end

local function exposed(x: number, y: number, z: number): boolean
	for _, d in NEIGHBORS do
		if not occludes(x + d[1], y + d[2], z + d[3]) then
			return true
		end
	end
	return false
end

local function createPart(id: number, x: number, y: number, z: number): BasePart
	local def = Blocks.byId[id]
	local part = Instance.new("Part")
	part.Name = def.key
	part.Anchored = true
	part.Size = Vector3.one * B
	part.CFrame = CFrame.new(x * B, y * B, z * B)
	Blocks.applyAppearance(part, def)
	if def.light then
		local light = Instance.new("PointLight")
		light.Color = def.light
		light.Range = 18
		light.Brightness = 1.2
		light.Parent = part
	end
	part.Parent = folder
	return part
end

local function refresh(x: number, y: number, z: number)
	if not inBounds(x, y, z) then
		return
	end
	local i = index(x, y, z)
	local id = buffer.readu8(data, i)
	local existing = parts[i]
	if id ~= 0 and exposed(x, y, z) then
		if existing and existing.Name ~= Blocks.byId[id].key then
			existing:Destroy()
			existing = nil
		end
		if not existing then
			parts[i] = createPart(id, x, y, z)
		end
	elseif existing then
		existing:Destroy()
		parts[i] = nil
	end
end

-- Sets a block at runtime and updates the parts of it and its neighbours.
function World.set(x: number, y: number, z: number, id: number): boolean
	if not inBounds(x, y, z) then
		return false
	end
	buffer.writeu8(data, index(x, y, z), id)
	refresh(x, y, z)
	for _, d in NEIGHBORS do
		refresh(x + d[1], y + d[2], z + d[3])
	end
	return true
end

function World.hasSolidNeighbor(x: number, y: number, z: number): boolean
	for _, d in NEIGHBORS do
		if World.get(x + d[1], y + d[2], z + d[3]) ~= 0 then
			return true
		end
	end
	return false
end

function World.topY(x: number, z: number): number?
	for y = H - 1, 0, -1 do
		if World.get(x, y, z) ~= 0 then
			return y
		end
	end
	return nil
end

-- Terrain -----------------------------------------------------------------------------------------

local ID = {}
for key, def in Blocks.byKey do
	ID[key] = def.id
end
World.ID = ID

local function generateTerrain(rng: Random, seed: number)
	local floorY = Config.SPAWN.floorY
	local flatRadius = Config.SPAWN.radius + 4
	local blendWidth = 10
	local sandLevel = floorY - 8

	local heights = {}
	for x = -R, R - 1 do
		for z = -R, R - 1 do
			-- math.noise mostly stays within ±0.5, so these give roughly ±12 blocks of relief.
			local n = math.noise(x / 48, z / 48, seed) * 18 + math.noise(x / 17, z / 17, seed + 31.7) * 6
			local h = floorY - 1 + n
			local dist = math.max(math.abs(x), math.abs(z))
			if dist <= flatRadius then
				h = floorY
			elseif dist < flatRadius + blendWidth then
				local t = (dist - flatRadius) / blendWidth
				h = floorY + (h - floorY) * t
			end
			h = math.clamp(math.floor(h + 0.5), 6, H - 14)
			heights[x * 4096 + z] = h

			local surface = if h <= sandLevel then ID.sand else ID.grass
			local filler = if h <= sandLevel then ID.sand else ID.dirt
			World.rawSet(x, 0, z, ID.bedrock)
			for y = 1, h do
				local id
				if y == h then
					id = surface
				elseif y >= h - 3 then
					id = filler
				elseif y <= 2 and rng:NextNumber() < 0.5 then
					id = ID.bedrock
				else
					id = ID.stone
					local roll = rng:NextNumber()
					if y < 14 and roll < 0.004 then
						id = ID.diamond_ore
					elseif y < 40 and roll < 0.014 then
						id = ID.iron_ore
					elseif roll < 0.03 then
						id = ID.coal_ore
					end
				end
				World.rawSet(x, y, z, id)
			end
		end
	end

	-- Oak trees, kept away from spawn and the world edge.
	local trees = {}
	for x = -R + 3, R - 4 do
		for z = -R + 3, R - 4 do
			local h = heights[x * 4096 + z]
			if math.max(math.abs(x), math.abs(z)) <= flatRadius + 3 or World.get(x, h, z) ~= ID.grass then
				continue
			end
			if rng:NextNumber() > 0.014 then
				continue
			end
			local crowded = false
			for _, t in trees do
				if math.abs(t[1] - x) < 4 and math.abs(t[2] - z) < 4 then
					crowded = true
					break
				end
			end
			if crowded then
				continue
			end
			table.insert(trees, { x, z })

			local trunk = rng:NextInteger(4, 6)
			local top = h + trunk
			for ly = top - 2, top + 1 do
				local radius = if ly <= top - 1 then 2 else 1
				for dx = -radius, radius do
					for dz = -radius, radius do
						local corner = math.abs(dx) == radius and math.abs(dz) == radius
						if corner and (ly > top - 1 or rng:NextNumber() < 0.5) then
							continue
						end
						if World.get(x + dx, ly, z + dz) == 0 then
							World.rawSet(x + dx, ly, z + dz, ID.oak_leaves)
						end
					end
				end
			end
			for y = h + 1, top do
				World.rawSet(x, y, z, ID.oak_log)
			end
		end
	end
end

local function buildParts(x0: number, x1: number, z0: number, z1: number, skip: ((number, number) -> boolean)?, yieldEvery: number?)
	local created = 0
	for x = math.max(x0, -R), math.min(x1, R - 1) do
		for z = math.max(z0, -R), math.min(z1, R - 1) do
			if skip and skip(x, z) then
				continue
			end
			for y = 0, H - 1 do
				local i = index(x, y, z)
				local id = buffer.readu8(data, i)
				if id ~= 0 and not parts[i] and exposed(x, y, z) then
					parts[i] = createPart(id, x, y, z)
					created += 1
					if yieldEvery and created % yieldEvery == 0 then
						task.wait()
					end
				end
			end
		end
	end
end

-- Fills the voxel data, lets `decorate` write structures, builds the spawn area's parts immediately
-- and streams in the rest of the world in the background.
function World.generate(decorate: () -> ())
	local seed = Config.SEED or math.random(1, 1_000_000)
	local rng = Random.new(seed)

	local f = Instance.new("Folder")
	f.Name = "Blocks"
	f.Parent = workspace
	folder = f

	generateTerrain(rng, (seed % 10_000) / 7.3)
	decorate()

	local near = Config.SPAWN.radius + 8
	buildParts(-near, near, -near, near, nil, nil)

	task.spawn(function()
		buildParts(-R, R - 1, -R, R - 1, function(x, z)
			return math.abs(x) <= near and math.abs(z) <= near
		end, 1500)
	end)
end

return World
