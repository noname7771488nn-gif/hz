-- Server validation for mining and placing blocks.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Blocks = require(Shared.Blocks)
local Items = require(Shared.Items)
local Zones = require(Shared.Zones)
local Remotes = require(Shared.Remotes)
local Sounds = require(Shared.Sounds)

local World = require(script.Parent.World)
local Inventory = require(script.Parent.Inventory)
local Drops = require(script.Parent.Drops)
local Combat = require(script.Parent.Combat)
local Messages = require(script.Parent.Messages)
local RateLimit = require(script.Parent.RateLimit)

local Building = {}

local B = Config.BLOCK_SIZE
local MAX_REACH = Config.BLOCK_REACH * B + 6 -- studs from the root, with slack for latency
local PROTECTED_MESSAGE = "Hey! Sorry, but you can't change blocks here."
local ORE_XP = { coal_ore = { 0, 2 }, diamond_ore = { 3, 7 } } -- experience range for mining an ore

local breaking: { [Player]: { x: number, y: number, z: number, started: number } } = {}

local function isCell(x: any, y: any, z: any): boolean
	for _, v in { x, y, z } do
		if type(v) ~= "number" or v ~= math.floor(v) or v ~= v then
			return false
		end
	end
	return true
end

local function inReach(player: Player, x: number, y: number, z: number): boolean
	local root = Combat.rootOf(player)
	return root ~= nil and (root.Position - World.toWorld(x, y, z)).Magnitude <= MAX_REACH
end

-- Rough character box (root at the waist) so blocks can't be placed inside players.
local function overlapsPlayer(x: number, y: number, z: number): boolean
	local center = World.toWorld(x, y, z)
	local half = B / 2
	for _, player in Players:GetPlayers() do
		local root = Combat.rootOf(player)
		if root then
			local p = root.Position
			if math.abs(p.X - center.X) < half + 1
				and math.abs(p.Z - center.Z) < half + 1
				and center.Y + half > p.Y - 3
				and center.Y - half < p.Y + 2.6
			then
				return true
			end
		end
	end
	return false
end

local function onStartBreak(player: Player, x: any, y: any, z: any)
	if not RateLimit.allow(player, "startBreak", 20) or not isCell(x, y, z) then
		return
	end
	breaking[player] = { x = x, y = y, z = z, started = os.clock() }
end

local function onFinishBreak(player: Player, x: any, y: any, z: any)
	if not RateLimit.allow(player, "finishBreak", 20) or not isCell(x, y, z) then
		return
	end
	local session = breaking[player]
	breaking[player] = nil
	if not session or session.x ~= x or session.y ~= y or session.z ~= z then
		return
	end
	local id = World.get(x, y, z)
	local def = Blocks.byId[id]
	if not def or def.hardness < 0 or not inReach(player, x, y, z) then
		return
	end
	if Zones.isProtected(x, y, z) then
		Messages.actionBar(player, PROTECTED_MESSAGE)
		return
	end
	-- Allow some latency slack but stop instant-mining.
	if os.clock() - session.started < Blocks.breakTime(def) * 0.75 - 0.15 then
		return
	end

	World.set(x, y, z, 0)
	local position = World.toWorld(x, y, z)
	Sounds.play("blockBreak", position, 0.6)
	local drop = Blocks.dropOf(def)
	if drop and Items.get(drop) then
		Drops.spawn({ id = drop, count = 1 }, position, Vector3.new((math.random() - 0.5) * 4, 8, (math.random() - 0.5) * 4), 0.4)
	end
	local xp = ORE_XP[def.key]
	if xp then
		Combat.addXp(player, math.random(xp[1], xp[2]))
	end
end

local function onPlace(player: Player, x: any, y: any, z: any)
	if not RateLimit.allow(player, "place", 10) or not isCell(x, y, z) then
		return
	end
	local stack = Inventory.selected(player)
	local def = stack and Items.get(stack.id)
	if not def or def.kind ~= "block" or not def.block then
		return
	end
	if not World.inBounds(x, y, z) or World.get(x, y, z) ~= 0 or not inReach(player, x, y, z) then
		return
	end
	if Zones.isProtected(x, y, z) then
		Messages.actionBar(player, PROTECTED_MESSAGE)
		return
	end
	if not World.hasSolidNeighbor(x, y, z) or overlapsPlayer(x, y, z) then
		return
	end
	if not Inventory.takeSelected(player, 1) then
		return
	end
	World.set(x, y, z, Blocks.byKey[def.block].id)
	Sounds.play("blockPlace", World.toWorld(x, y, z), 0.6)
end

function Building.init()
	Remotes.StartBreak.OnServerEvent:Connect(onStartBreak)
	Remotes.FinishBreak.OnServerEvent:Connect(onFinishBreak)
	Remotes.PlaceBlock.OnServerEvent:Connect(onPlace)
	Players.PlayerRemoving:Connect(function(player)
		breaking[player] = nil
	end)
end

return Building
