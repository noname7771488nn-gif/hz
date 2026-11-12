-- Slash commands, sent by the client's chat box. Admin-style commands are recognised but always
-- answer with the permission-denied message.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local Kits = require(script.Parent.Kits)
local Messages = require(script.Parent.Messages)
local RateLimit = require(script.Parent.RateLimit)
local Structures = require(script.Parent.Structures)
local Teleport = require(script.Parent.Teleport)

local Commands = {}

local PERMISSION_DENIED =
	"I'm sorry, but you do not have permission to perform this command. Please contact the server administrators if you believe that this is in error."

local ADMIN_COMMANDS = {
	"gm0", "gm1", "gm2", "gm3", "gmc", "gms", "gma", "gmsp", "gamemode",
	"give", "i", "item", "tp", "tphere", "tpall", "teleport", "time", "weather", "kill",
	"op", "deop", "ban", "unban", "kick", "mute", "fly", "heal", "feed", "god", "vanish", "v",
	"clear", "effect", "enchant", "summon", "setblock", "fill", "difficulty", "gamerule",
	"xp", "experience", "speed", "stop", "reload", "whitelist", "sudo", "invsee", "setspawn", "setwarp",
}

local HELP = {
	"--- Commands ---",
	"/spawn - Teleport to spawn",
	"/kits - Open the kits menu (/kit <name> claims one)",
	"/rtp - Random teleport into the wilderness",
	"/warp pvp (or /pvp) - Go to the PvP warp",
	"/stats - Your kills and deaths",
	"/list - Show who is online",
}

local rtpUsedAt: { [number]: number } = {}

local handlers: { [string]: (Player, { string }) -> () } = {}

local function register(aliases: { string }, handler: (Player, { string }) -> ())
	for _, alias in aliases do
		handlers[alias] = handler
	end
end

register({ "help", "?" }, function(player)
	for _, line in HELP do
		Messages.send(player, line, "info")
	end
end)

register({ "spawn" }, function(player)
	Teleport.request(player, Structures.spawnCFrame, "spawn")
end)

register({ "kit" }, function(player, args)
	if args[1] then
		Kits.claim(player, args[1])
	else
		Kits.sendInfo(player, true)
	end
end)

register({ "kits" }, function(player)
	Kits.sendInfo(player, true)
end)

register({ "rtp", "wild", "randomtp" }, function(player)
	local last = rtpUsedAt[player.UserId]
	if last and os.clock() - last < Config.RTP_COOLDOWN then
		Messages.send(player, `You must wait {math.ceil(Config.RTP_COOLDOWN - (os.clock() - last))}s before using /rtp again.`, "error")
		return
	end
	Teleport.request(player, Structures.randomWildCFrame, "a random location", function()
		rtpUsedAt[player.UserId] = os.clock()
	end)
end)

local function warpToArena(player: Player)
	Teleport.request(player, Structures.arenaSpawnCFrame, "the PvP warp")
end

register({ "pvp" }, warpToArena)

register({ "warp", "warps" }, function(player, args)
	local name = args[1] and string.lower(args[1])
	if not name then
		Messages.send(player, "Warps: pvp", "info")
	elseif name == "pvp" then
		warpToArena(player)
	else
		Messages.send(player, `Warp '{name}' does not exist.`, "error")
	end
end)

register({ "stats" }, function(player)
	local kills, deaths = player:GetAttribute("Kills") or 0, player:GetAttribute("Deaths") or 0
	Messages.send(player, `Kills: {kills}  Deaths: {deaths}  Streak: {player:GetAttribute("Streak") or 0}`, "info")
end)

register({ "list", "online" }, function(player)
	local names = {}
	for _, other in Players:GetPlayers() do
		table.insert(names, other.Name)
	end
	Messages.send(player, `There are {#names} of a max of {Players.MaxPlayers} players online: {table.concat(names, ", ")}`, "info")
end)

for _, name in ADMIN_COMMANDS do
	handlers[name] = function(player)
		Messages.send(player, PERMISSION_DENIED, "error")
	end
end

local function run(player: Player, text: string)
	local words = {}
	for word in string.gmatch(text, "%S+") do
		table.insert(words, word)
	end
	local name = string.lower(string.sub(table.remove(words, 1) or "", 2))
	local handler = handlers[name]
	if not handler then
		Messages.send(player, 'Unknown command. Type "/help" for help.', "error")
		return
	end
	local ok, err = pcall(handler, player, words)
	if not ok then
		warn(`[BlockCraft] /{name} failed for {player.Name}:`, err)
		Messages.send(player, "An internal error occurred while attempting to perform this command.", "error")
	end
end

function Commands.init()
	Remotes.Command.OnServerEvent:Connect(function(player, text)
		if type(text) ~= "string" or #text > 200 or string.sub(text, 1, 1) ~= "/" then
			return
		end
		if RateLimit.allow(player, "command", 4) then
			run(player, text)
		end
	end)
end

return Commands
