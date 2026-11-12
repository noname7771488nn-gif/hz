-- Central tuning for the whole game. Read by both the server and the client.
local Config = {}

Config.GAME_NAME = "BlockCraft"

-- World ------------------------------------------------------------------------------------------
Config.BLOCK_SIZE = 3 -- studs per block; a default avatar is ~1.7 blocks tall, close to Minecraft's 1.8
Config.WORLD_RADIUS = 64 -- the world spans [-R, R) blocks on X and Z
Config.WORLD_HEIGHT = 64
Config.SEED = nil :: number? -- set a number for the same world every server, nil for a fresh one

-- Protected spawn square (in blocks) centred on (0, 0). Players spawn here.
Config.SPAWN = { radius = 12, floorY = 28 }

-- Floating PvP arena, built outside the world border so it can only be reached by /warp pvp.
Config.ARENA = { centerX = Config.WORLD_RADIUS + 56, centerZ = 0, floorY = 40, radius = 15 }

-- Rules ------------------------------------------------------------------------------------------
Config.WILDERNESS_PVP = true -- PvP outside spawn and the arena
Config.COMBAT_TAG_SECONDS = 15
Config.TELEPORT_WARMUP = 3 -- seconds to stand still before /spawn, /rtp and /warp teleport you
Config.RTP_COOLDOWN = 30
Config.RESPAWN_TIMEOUT = 60 -- auto-respawn if the player never presses "Respawn"

-- Player -----------------------------------------------------------------------------------------
Config.MAX_HEALTH = 20 -- 10 hearts
Config.REGEN_INTERVAL = 4 -- seconds per half heart of natural regeneration
Config.BLOCK_REACH = 4.5 -- blocks
Config.ATTACK_REACH = 3 -- blocks
Config.WALK_SPEED = 13
Config.SPRINT_SPEED = 17
Config.SNEAK_SPEED = 4
Config.KNOCKBACK_HORIZONTAL = 26
Config.KNOCKBACK_VERTICAL = 18
Config.ITEM_DESPAWN = 300 -- dropped items vanish after 5 minutes
Config.DAY_LENGTH = 1200 -- seconds for a full day/night cycle (20 minutes)

-- Kits -------------------------------------------------------------------------------------------
Config.KIT_ORDER = { "diamond" }
Config.Kits = {
	diamond = {
		displayName = "Diamond",
		cooldown = 5 * 60 * 60,
		items = {
			{ id = "diamond_helmet", count = 1, ench = { protection = 3 } },
			{ id = "diamond_chestplate", count = 1, ench = { protection = 3 } },
			{ id = "diamond_leggings", count = 1, ench = { protection = 3 } },
			{ id = "diamond_boots", count = 1, ench = { protection = 3 } },
			{ id = "diamond_sword", count = 1, ench = { sharpness = 5, unbreaking = 3 } },
		},
	},
}

-- Assets -----------------------------------------------------------------------------------------
-- Minecraft's own textures and sounds are Mojang/Microsoft property and must not be uploaded.
-- Upload your own (or properly licensed) pixel-art images and put the ids here, e.g.
--   grass = { top = "rbxassetid://123", side = "rbxassetid://456", bottom = "rbxassetid://789" },
--   stone = { all = "rbxassetid://321" },
-- Blocks without an entry use Roblox materials and colours.
Config.Textures = {}

-- Sound ids. The defaults are sounds that ship with the Roblox client; replace them with your own.
Config.Sounds = {
	blockBreak = "rbxasset://sounds/action_jump_land.mp3",
	blockPlace = "rbxasset://sounds/action_jump_land.mp3",
	hit = "rbxasset://sounds/swordslash.wav",
	hurt = "rbxasset://sounds/uuhhh.mp3",
	swing = "rbxasset://sounds/swordlunge.wav",
	pickup = "rbxasset://sounds/electronicpingshort.wav",
	equip = "rbxasset://sounds/unsheath.wav",
	click = "rbxasset://sounds/clickfast.wav",
	kit = "rbxasset://sounds/electronicpingshort.wav",
}

return Config
