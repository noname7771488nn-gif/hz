-- Slash commands via TextChatService. Admin-style commands are registered so they are recognised,
-- but always answer with the permission-denied message.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local Kits = require(script.Parent.Kits)
local Messages = require(script.Parent.Messages)
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
	"/kit [name] - Claim a kit (/kits lists them)",
	"/rtp - Random teleport into the wilderness",
	"/warp pvp (or /pvp) - Go to the PvP arena",
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
	Kits.claim(player, args[1])
end)

register({ "kits" }, function(player)
	Kits.list(player)
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
	Teleport.request(player, Structures.arenaCFrame, "the PvP arena")
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

local function parseArgs(text: string): { string }
	local args = {}
	for word in string.gmatch(text, "%S+") do
		table.insert(args, word)
	end
	table.remove(args, 1)
	return args
end

function Commands.init()
	for alias, handler in handlers do
		local command = Instance.new("TextChatCommand")
		command.Name = "BlockCraft_" .. alias
		command.PrimaryAlias = "/" .. alias
		command.Triggered:Connect(function(textSource, text)
			local player = Players:GetPlayerByUserId(textSource.UserId)
			if not player then
				return
			end
			local ok, err = pcall(handler, player, parseArgs(text))
			if not ok then
				warn(`[BlockCraft] /{alias} failed for {player.Name}:`, err)
				Messages.send(player, "An internal error occurred while attempting to perform this command.", "error")
			end
		end)
		command.Parent = TextChatService
	end

	-- Unknown "/..." messages are never shown in public chat.
	task.spawn(function()
		local channels = TextChatService:WaitForChild("TextChannels", 30)
		local general = channels and channels:WaitForChild("RBXGeneral", 30) :: TextChannel?
		if not general then
			warn("[BlockCraft] RBXGeneral channel not found; unknown commands will be shown in chat")
			return
		end
		general.ShouldDeliverCallback = function(message: TextChatMessage, target: TextSource)
			if string.sub(message.Text, 1, 1) ~= "/" then
				return true
			end
			local source = message.TextSource
			if source and source.UserId == target.UserId then
				local sender = Players:GetPlayerByUserId(source.UserId)
				if sender then
					Messages.send(sender, 'Unknown command. Type "/help" for help.', "error")
				end
			end
			return false
		end
	end)
end

return Commands
