local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Sounds = require(Shared.Sounds)

local Combat = require(script.Parent.Combat)
local Data = require(script.Parent.Data)
local Drops = require(script.Parent.Drops)
local Inventory = require(script.Parent.Inventory)
local Messages = require(script.Parent.Messages)
local RateLimit = require(script.Parent.RateLimit)

local Kits = {}

-- Also kept in memory per UserId so cooldowns survive rejoining even if DataStores are down.
local memory: { [number]: { [string]: number } } = {}

function Kits.formatDuration(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	local h = seconds // 3600
	local m = (seconds % 3600) // 60
	local s = seconds % 60
	if h > 0 then
		return `{h}h {m}m {s}s`
	elseif m > 0 then
		return `{m}m {s}s`
	end
	return `{s}s`
end

local function lastClaim(player: Player, name: string): number
	local profile = Data.profiles[player]
	local saved = if profile then profile.kits[name] or 0 else 0
	local cached = memory[player.UserId] and memory[player.UserId][name] or 0
	return math.max(saved, cached)
end

function Kits.remaining(player: Player, name: string): number
	local kit = Config.Kits[name]
	return math.max(0, lastClaim(player, name) + kit.cooldown - os.time())
end

-- Sends each kit's "ready at" unix time to the client, optionally opening the kits menu.
function Kits.sendInfo(player: Player, open: boolean)
	local readyAt = {}
	for _, name in Config.KIT_ORDER do
		readyAt[name] = lastClaim(player, name) + Config.Kits[name].cooldown
	end
	Remotes.KitInfo:FireClient(player, readyAt, open)
end

function Kits.claim(player: Player, requested: string)
	local name = string.lower(requested)
	local kit = Config.Kits[name]
	if not kit then
		Messages.send(player, `Kit '{name}' does not exist. Use /kits to see available kits.`, "error")
		return
	end
	local root = Combat.rootOf(player)
	if not root then
		return
	end
	local remaining = Kits.remaining(player, name)
	if remaining > 0 then
		Messages.send(player, `You can claim the {kit.displayName} kit again in {Kits.formatDuration(remaining)}.`, "error")
		return
	end

	local now = os.time()
	memory[player.UserId] = memory[player.UserId] or {}
	memory[player.UserId][name] = now
	local profile = Data.profiles[player]
	if profile then
		profile.kits[name] = now
	end

	local overflow = false
	for _, item in kit.items do
		local stack = { id = item.id, count = item.count, ench = if item.ench then table.clone(item.ench) else nil }
		local left = Inventory.equipOrAdd(player, stack)
		if left > 0 then
			stack.count = left
			Drops.spawn(stack, root.Position, nil, 0)
			overflow = true
		end
	end
	Sounds.play("kit", root, 0.5)
	Messages.send(player, `You received the {kit.displayName} kit! Next claim in {Kits.formatDuration(kit.cooldown)}.`, "success")
	if overflow then
		Messages.send(player, "Your inventory was full, so some items were dropped at your feet.", "error")
	end
	Kits.sendInfo(player, false)

	task.spawn(Data.save, player, Inventory.serialize(player))
end

function Kits.init()
	Remotes.ClaimKit.OnServerEvent:Connect(function(player, name)
		if RateLimit.allow(player, "claimKit", 3) and type(name) == "string" and #name <= 32 then
			Kits.claim(player, name)
		end
	end)
end

return Kits
