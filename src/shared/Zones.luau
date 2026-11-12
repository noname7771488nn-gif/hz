-- Spawn and the PvP arena are protected: no block breaking or placing.
-- Spawn is a safe zone; the arena always allows PvP; the wilderness follows Config.WILDERNESS_PVP.
local Config = require(script.Parent.Config)

local Zones = {}

local B = Config.BLOCK_SIZE
local SPAWN = Config.SPAWN
local ARENA = Config.ARENA

Zones.DISPLAY = {
	spawn = "Spawn",
	arena = "PvP Arena",
	wild = "Wilderness",
}

-- Zone of a block column, in block coordinates.
function Zones.cellZone(x: number, z: number): string
	if math.abs(x) <= SPAWN.radius and math.abs(z) <= SPAWN.radius then
		return "spawn"
	end
	if math.abs(x - ARENA.centerX) <= ARENA.radius + 1 and math.abs(z - ARENA.centerZ) <= ARENA.radius + 1 then
		return "arena"
	end
	return "wild"
end

function Zones.zoneAt(position: Vector3): string
	return Zones.cellZone(math.round(position.X / B), math.round(position.Z / B))
end

function Zones.isProtected(x: number, _y: number, z: number): boolean
	return Zones.cellZone(x, z) ~= "wild"
end

function Zones.pvpAllowedAt(position: Vector3): boolean
	local zone = Zones.zoneAt(position)
	if zone == "spawn" then
		return false
	elseif zone == "arena" then
		return true
	end
	return Config.WILDERNESS_PVP
end

return Zones
