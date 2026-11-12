-- Central tuning for the whole game. Read by both the server and the client.
local Config = {}

Config.GAME_NAME = "BlockCraft"
Config.MC_VERSION = "1.21.1" -- combat rules (attack cooldown, crits, armor, enchantments) follow this version

-- World ------------------------------------------------------------------------------------------
Config.BLOCK_SIZE = 3 -- studs per block
Config.WORLD_RADIUS = 128 -- the world spans [-R, R) blocks on X and Z (256 x 256)
Config.WORLD_HEIGHT = 64
Config.SEED = nil :: number? -- set a number for the same world every server, nil for a fresh one
Config.GRAVITY = 96 -- studs/s^2; 32 blocks/s^2 like Minecraft (Roblox's default 196 feels far too heavy)
Config.JUMP_HEIGHT = 3.9 -- studs; about 1.25 blocks

-- Protected spawn square (in blocks) centred on (0, 0). Players spawn here.
Config.SPAWN = { radius = 14, floorY = 28 }

-- Floating PvP arena, built outside the world border so it can only be reached by /warp pvp.
-- Players arrive on a safe spawn platform `spawnHeight` blocks above the floor and jump down to fight.
Config.ARENA = {
	centerX = Config.WORLD_RADIUS + 70,
	centerZ = 0,
	floorY = 40,
	radius = 26,
	wallHeight = 7,
	spawnHeight = 10,
	spawnRadius = 4,
}

-- Rules ------------------------------------------------------------------------------------------
Config.WILDERNESS_PVP = true -- PvP outside spawn and the arena
Config.COMBAT_TAG_SECONDS = 15
Config.TELEPORT_WARMUP = 3 -- seconds to stand still before /spawn, /rtp and /warp teleport you
Config.RTP_COOLDOWN = 30
Config.RESPAWN_TIMEOUT = 60 -- auto-respawn if the player never presses "Respawn"
Config.RESPAWN_AT_PVP_WARP = true -- dying in the PvP warp respawns you on its spawn platform
Config.BLOCKY_AVATARS = true -- square heads and no body-shape packages, for a blockier look

-- Player -----------------------------------------------------------------------------------------
Config.MAX_HEALTH = 20 -- 10 hearts
Config.REGEN_INTERVAL = 4 -- seconds per half heart of natural regeneration
Config.BLOCK_REACH = 4.5 -- blocks
Config.ATTACK_REACH = 3 -- blocks
Config.WALK_SPEED = 13 -- 4.3 blocks/s
Config.SPRINT_SPEED = 17 -- 5.6 blocks/s
Config.SNEAK_SPEED = 4
Config.KNOCKBACK_HORIZONTAL = 16
Config.KNOCKBACK_SPRINT_BONUS = 14 -- extra horizontal knockback for a fully charged sprint hit
Config.KNOCKBACK_VERTICAL = 20
Config.ITEM_DESPAWN = 300 -- dropped items vanish after 5 minutes
Config.DAY_LENGTH = 1200 -- seconds for a full day/night cycle (20 minutes)

-- Kits -------------------------------------------------------------------------------------------
-- Shown in the /kits menu in this order. `icon` is an item id, `cooldown` is in seconds.
Config.KIT_ORDER = { "starter", "diamond", "builder" }
Config.Kits = {
	starter = {
		displayName = "Starter",
		icon = "iron_chestplate",
		cooldown = 5 * 60,
		items = {
			{ id = "iron_helmet", count = 1 },
			{ id = "iron_chestplate", count = 1 },
			{ id = "iron_leggings", count = 1 },
			{ id = "iron_boots", count = 1 },
			{ id = "iron_sword", count = 1 },
			{ id = "oak_planks", count = 32 },
		},
	},
	diamond = {
		displayName = "Diamond",
		icon = "diamond_chestplate",
		cooldown = 5 * 60 * 60,
		items = {
			{ id = "diamond_helmet", count = 1, ench = { protection = 3 } },
			{ id = "diamond_chestplate", count = 1, ench = { protection = 3 } },
			{ id = "diamond_leggings", count = 1, ench = { protection = 3 } },
			{ id = "diamond_boots", count = 1, ench = { protection = 3 } },
			{ id = "diamond_sword", count = 1, ench = { sharpness = 4, fire_aspect = 1 } },
		},
	},
	builder = {
		displayName = "Builder",
		icon = "oak_planks",
		cooldown = 10 * 60,
		items = {
			{ id = "oak_planks", count = 64 },
			{ id = "cobblestone", count = 64 },
			{ id = "stone_bricks", count = 32 },
			{ id = "glowstone", count = 16 },
		},
	},
}

-- PvP bot ----------------------------------------------------------------------------------------
Config.BOT = {
	enabled = true,
	name = "PvP Bot",
	kit = "diamond", -- the bot wears and wields this kit
	respawnSeconds = 15,
	ignoreUnarmored = true, -- never starts a fight with a player wearing no armor (it still fights back)
	retaliateSeconds = 8, -- how long it stays on whoever hit it last
	reactionTime = 0.12, -- seconds between getting in reach and swinging
	critChance = 0.85, -- how often it jumps to land a falling (critical) hit
	goldenApples = 1, -- times per life it backs off to heal 4 hearts when low
	loot = { { id = "diamond", count = 2 } }, -- dropped when it dies
}

-- Assets -----------------------------------------------------------------------------------------
-- Block and item art is generated in code as original 16x16 pixel art (src/shared/PixelArt.luau).
-- To use your own uploaded images instead, map a texture key to an asset id here, e.g.
--   Config.Textures = { grass_top = "rbxassetid://123", stone = "rbxassetid://456" }
-- Texture keys are listed in PixelArt.BLOCK_KEYS. Minecraft's own textures and sounds are
-- Mojang/Microsoft property and must not be uploaded.
Config.Textures = {} :: { [string]: string }

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
