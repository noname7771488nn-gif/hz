-- Zones:
--   spawn     protected, no PvP (the main hub)
--   pvpspawn  protected, no PvP (the platform you arrive on with /warp pvp)
--   arena     protected, PvP always on (everything in the PvP warp below that platform)
--   wild      editable, PvP follows Config.WILDERNESS_PVP
local Config = require(script.Parent.Config)

local Zones = {}

local B = Config.BLOCK_SIZE
local SPAWN = Config.SPAWN
local ARENA = Config.ARENA

Zones.DISPLAY = {
	spawn = "Spawn",
	pvpspawn = "PvP Spawn",
	arena = "PvP Arena",
	wild = "Wilderness",
}

-- Zone of a block, in block coordinates.
function Zones.cellZone(x: number, y: number, z: number): string
	if math.abs(x) <= SPAWN.radius and math.abs(z) <= SPAWN.radius then
		return "spawn"
	end
	local ax, az = math.abs(x - ARENA.centerX), math.abs(z - ARENA.centerZ)
	if ax <= ARENA.radius + 1 and az <= ARENA.radius + 1 then
		if ax <= ARENA.spawnRadius + 1 and az <= ARENA.spawnRadius + 1 and y >= ARENA.floorY + ARENA.spawnHeight then
			return "pvpspawn"
		end
		return "arena"
	end
	return "wild"
end

function Zones.zoneAt(position: Vector3): string
	return Zones.cellZone(math.round(position.X / B), math.round(position.Y / B), math.round(position.Z / B))
end

function Zones.isProtected(x: number, y: number, z: number): boolean
	return Zones.cellZone(x, y, z) ~= "wild"
end

function Zones.pvpAllowedAt(position: Vector3): boolean
	local zone = Zones.zoneAt(position)
	if zone == "arena" then
		return true
	elseif zone == "wild" then
		return Config.WILDERNESS_PVP
	end
	return false
end

return Zones
