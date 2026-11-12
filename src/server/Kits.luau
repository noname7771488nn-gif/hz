local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Sounds = require(Shared.Sounds)

local Combat = require(script.Parent.Combat)
local Data = require(script.Parent.Data)
local Drops = require(script.Parent.Drops)
local Inventory = require(script.Parent.Inventory)
local Messages = require(script.Parent.Messages)

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

function Kits.list(player: Player)
	Messages.send(player, "Kits:", "info")
	for _, name in Config.KIT_ORDER do
		local kit = Config.Kits[name]
		local remaining = Kits.remaining(player, name)
		local status = if remaining > 0 then `available in {Kits.formatDuration(remaining)}` else "available now"
		Messages.send(player, ` - {name} ({kit.displayName}): {status}`, if remaining > 0 then "error" else "success")
	end
end

-- Claim handler for /kit [name]. With a single kit, /kit on its own claims it.
function Kits.claim(player: Player, requested: string?)
	local name = if requested then string.lower(requested) elseif #Config.KIT_ORDER == 1 then Config.KIT_ORDER[1] else nil
	if not name then
		Kits.list(player)
		return
	end
	local kit = Config.Kits[name]
	if not kit then
		Messages.send(player, `Kit '{name}' does not exist. Use /kits to see available kits.`, "error")
		return
	end
	local character, _, root = Combat.aliveCharacter(player)
	if not character or not root then
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

	task.spawn(Data.save, player, Inventory.serialize(player))
end

return Kits
