-- Voxel world. Block ids live in a flat buffer; only blocks touching air get a Part, and only
-- their visible faces get a texture, so a 256x256 world stays around a hundred thousand parts.
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
local masks = buffer.create(W * W * H) -- visible-face bitmask of each block that has a part
local heights = buffer.create(W * W) -- terrain height per column, a hint for the initial build
local parts: { [number]: BasePart } = {}
local folder: Folder? = nil

-- Same order as Blocks.FACES.
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
World.builtRadius = 0 -- columns within this distance of the centre have their parts

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

local function occludes(x: number, y: number, z: number): boolean
	if y < 0 then
		return true
	elseif y >= H then
		return false
	elseif x < -R or x >= R or z < -R or z >= R then
		-- Treat beyond the border as solid so the world's outer walls aren't built.
		return true
	end
	return buffer.readu8(data, index(x, y, z)) ~= 0
end

local function faceMask(x: number, y: number, z: number): number
	local mask = 0
	for face, d in NEIGHBORS do
		if not occludes(x + d[1], y + d[2], z + d[3]) then
			mask += bit32.lshift(1, face - 1)
		end
	end
	return mask
end

local partTemplates: { [number]: Part } = {}

local function createPart(id: number, x: number, y: number, z: number, mask: number, parent: Instance): BasePart
	local def = Blocks.byId[id]
	local template = partTemplates[id]
	if not template then
		template = Instance.new("Part")
		template.Name = def.key
		template.Anchored = true
		template.Size = Vector3.one * B
		template.CastShadow = false
		Blocks.applyAppearance(template, def, 0)
		if def.light then
			local light = Instance.new("PointLight")
			light.Color = def.light
			light.Range = 20
			light.Brightness = 1.2
			light.Parent = template
		end
		partTemplates[id] = template
	end
	local part = template:Clone()
	part.CFrame = CFrame.new(x * B, y * B, z * B)
	Blocks.addFaces(part, def, mask)
	part.Parent = parent
	return part
end

local function refresh(x: number, y: number, z: number)
	if not inBounds(x, y, z) then
		return
	end
	local i = index(x, y, z)
	local id = buffer.readu8(data, i)
	local existing = parts[i]
	local mask = if id ~= 0 then faceMask(x, y, z) else 0
	if existing and (mask == 0 or existing.Name ~= Blocks.byId[id].key or buffer.readu8(masks, i) ~= mask) then
		existing:Destroy()
		parts[i] = nil
		existing = nil
	end
	if mask ~= 0 and not existing then
		parts[i] = createPart(id, x, y, z, mask, folder :: Folder)
		buffer.writeu8(masks, i, mask)
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

-- Builds face-culled parts for a fixed structure that lives outside the voxel world (the arena).
-- `cells` maps block coordinates to block ids; `hidden` marks empty cells that can never be seen.
function World.buildStatic(cells: { [Vector3]: number }, parent: Instance, hidden: ((Vector3) -> boolean)?)
	for position, id in cells do
		local mask = 0
		for face, d in NEIGHBORS do
			local neighbor = position + Vector3.new(d[1], d[2], d[3])
			if not cells[neighbor] and not (hidden and hidden(neighbor)) then
				mask += bit32.lshift(1, face - 1)
			end
		end
		if mask ~= 0 then
			createPart(id, position.X, position.Y, position.Z, mask, parent)
		end
	end
end

-- Terrain -----------------------------------------------------------------------------------------

local ID = {}
for key, def in Blocks.byKey do
	ID[key] = def.id
end
World.ID = ID

local function heightAt(x: number, z: number): number
	return buffer.readu8(heights, (z + R) * W + (x + R))
end

local function generateTerrain(rng: Random, seed: number)
	local floorY = Config.SPAWN.floorY
	local flatRadius = Config.SPAWN.radius + 4
	local blendWidth = 12
	local sandLevel = floorY - 9
	local biomes = {}

	for x = -R, R - 1 do
		for z = -R, R - 1 do
			-- math.noise mostly stays within +-0.5, so this gives roughly +-16 blocks of relief.
			local n = math.noise(x / 96, z / 96, seed) * 22
				+ math.noise(x / 40, z / 40, seed + 17.3) * 10
				+ math.noise(x / 14, z / 14, seed + 31.7) * 4
			local h = floorY - 1 + n
			local dist = math.max(math.abs(x), math.abs(z))
			local nearSpawn = dist < flatRadius + blendWidth
			if dist <= flatRadius then
				h = floorY
			elseif nearSpawn then
				local t = (dist - flatRadius) / blendWidth
				h = floorY + (h - floorY) * t
			end
			h = math.clamp(math.floor(h + 0.5), 6, H - 16)
			buffer.writeu8(heights, (z + R) * W + (x + R), h)

			local climate = math.noise(x / 110, z / 110, seed + 91.1)
			local biome = "plains"
			if h <= sandLevel then
				biome = "beach"
			elseif not nearSpawn and climate > 0.26 then
				biome = "desert"
			elseif not nearSpawn and (climate < -0.3 or h >= floorY + 12) then
				biome = "snow"
			end
			biomes[x * 4096 + z] = biome

			local surface, filler = ID.grass, ID.dirt
			if biome == "beach" or biome == "desert" then
				surface, filler = ID.sand, ID.sand
			elseif biome == "snow" then
				surface = ID.snowy_grass
			elseif not nearSpawn and math.noise(x / 9, z / 9, seed + 5.5) > 0.44 then
				surface = ID.gravel
			end

			World.rawSet(x, 0, z, ID.bedrock)
			for y = 1, h do
				local id
				if y == h then
					id = surface
				elseif y >= h - 3 then
					id = filler
				elseif biome == "desert" and y >= h - 6 then
					id = ID.sandstone
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

	-- Trees: forests where the density noise is high, scattered elsewhere, none in sand.
	local trees = {}
	for x = -R + 3, R - 4 do
		for z = -R + 3, R - 4 do
			local biome = biomes[x * 4096 + z]
			if biome ~= "plains" and biome ~= "snow" then
				continue
			end
			local h = heightAt(x, z)
			local ground = World.get(x, h, z)
			if math.max(math.abs(x), math.abs(z)) <= flatRadius + 3 or (ground ~= ID.grass and ground ~= ID.snowy_grass) then
				continue
			end
			local density = 0.003 + math.max(0, math.noise(x / 50, z / 50, seed + 200)) * 0.04
			if rng:NextNumber() > density then
				continue
			end
			local crowded = false
			for i = #trees, math.max(1, #trees - 40), -1 do
				local t = trees[i]
				if math.abs(t[1] - x) < 4 and math.abs(t[2] - z) < 4 then
					crowded = true
					break
				end
			end
			if crowded then
				continue
			end
			table.insert(trees, { x, z })

			local birch = biome == "plains" and rng:NextNumber() < 0.3
			local log, leaves = if birch then ID.birch_log else ID.oak_log, if birch then ID.birch_leaves else ID.oak_leaves
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
							World.rawSet(x + dx, ly, z + dz, leaves)
						end
					end
				end
			end
			for y = h + 1, top do
				World.rawSet(x, y, z, log)
			end
		end
	end
end

local created = 0

local function buildColumn(x: number, z: number)
	-- Nothing below the lowest neighbouring surface can be exposed (terrain has no caves).
	local low = heightAt(x, z)
	for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local nx, nz = x + d[1], z + d[2]
		if nx >= -R and nx < R and nz >= -R and nz < R then
			low = math.min(low, heightAt(nx, nz))
		end
	end
	for y = math.max(0, low), H - 1 do
		local i = index(x, y, z)
		local id = buffer.readu8(data, i)
		if id ~= 0 and not parts[i] then
			local mask = faceMask(x, y, z)
			if mask ~= 0 then
				parts[i] = createPart(id, x, y, z, mask, folder :: Folder)
				buffer.writeu8(masks, i, mask)
				created += 1
			end
		end
	end
end

-- Builds the square ring of columns at Chebyshev distance `r` from the centre.
local function buildRing(r: number)
	local edges: { number } = if r == 0 then { 0 } else { -r, r }
	for x = -r, r do
		for _, z in edges do
			if x >= -R and x < R and z >= -R and z < R then
				buildColumn(x, z)
			end
		end
	end
	for z = -r + 1, r - 1 do
		for _, x in { -r, r } do
			if x >= -R and x < R and z >= -R and z < R then
				buildColumn(x, z)
			end
		end
	end
end

-- Fills the voxel data, lets `decorate` write structures, builds the spawn area's parts immediately
-- and grows the rest of the world outward in the background.
function World.generate(decorate: () -> ())
	local seed = Config.SEED or math.random(1, 1_000_000)
	local rng = Random.new(seed)

	local f = Instance.new("Folder")
	f.Name = "Blocks"
	f.Parent = workspace
	folder = f

	generateTerrain(rng, (seed % 10_000) / 7.3)
	decorate()

	local near = Config.SPAWN.radius + 10
	for r = 0, near do
		buildRing(r)
	end
	World.builtRadius = near

	task.spawn(function()
		local lastYield = created
		for r = near + 1, R do
			buildRing(r)
			World.builtRadius = r
			if created - lastYield >= 1200 then
				lastYield = created
				task.wait()
			end
		end
	end)
end

return World
