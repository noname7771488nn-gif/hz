local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local Server = script.Parent
local World = require(Server.World)
local Structures = require(Server.Structures)
local Data = require(Server.Data)
local Inventory = require(Server.Inventory)
local Drops = require(Server.Drops)
local Combat = require(Server.Combat)
local Survival = require(Server.Survival)
local Building = require(Server.Building)
local Commands = require(Server.Commands)
local Kits = require(Server.Kits)
local Bot = require(Server.Bot)
local Visuals = require(Server.Visuals)
local Messages = require(Server.Messages)
local RateLimit = require(Server.RateLimit)

Players.CharacterAutoLoads = false
workspace.Gravity = Config.GRAVITY

World.generate(Structures.writeSpawn)
Structures.buildDecor()
Structures.buildArena()

Combat.init()
Survival.init()
Building.init()
Commands.init()
Kits.init()
Bot.init()

Inventory.onChanged(function(player)
	Visuals.refresh(player)
end)

-- Inventory remotes --------------------------------------------------------------------------------

Remotes.SelectSlot.OnServerEvent:Connect(function(player, index)
	if RateLimit.allow(player, "select", 30) and Inventory.select(player, index) then
		-- Switching items restarts the attack cooldown.
		Combat.resetCooldown(player)
	end
end)

Remotes.InvAction.OnServerEvent:Connect(function(player, seq, action, a, b, c)
	if type(action) ~= "string" or not RateLimit.allow(player, "inventory", 40) then
		Inventory.reject(player, seq)
		return
	end
	local drops = Inventory.action(player, seq, action, a, b, c)
	if #drops == 0 then
		return
	end
	-- Thrown items fly out in front of the player.
	local root = Combat.rootOf(player)
	local entity = Combat.ofPlayer(player)
	local origin = if root then root.Position else entity and entity.lastPosition
	if not origin then
		return
	end
	local look = if root then root.CFrame.LookVector else Vector3.zAxis
	for _, stack in drops do
		Drops.spawn(stack, origin + look * 2 + Vector3.new(0, 1, 0), look * 14 + Vector3.new(0, 8, 0), 2)
	end
end)

-- Players ------------------------------------------------------------------------------------------

local function onCharacterAdded(player: Player, character: Model)
	local entity = Combat.ofPlayer(player)
	if not entity then
		return
	end
	local toArena = Config.RESPAWN_AT_PVP_WARP and entity.respawnAtArena
	entity.respawnAtArena = false
	Combat.bind(entity, character)
	Survival.reset(player)
	Visuals.blockify(character)
	Visuals.nameTag(character, player.Name)
	Visuals.refresh(player, true)

	if toArena then
		-- Died in the PvP warp: come back on its spawn platform instead of the main hub.
		local target = Structures.arenaSpawnCFrame()
		pcall(function()
			player:RequestStreamAroundAsync(target.Position, 3)
		end)
		task.wait(0.1) -- let the engine finish placing the character at the default spawn first
		if player.Character == character and character.Parent then
			character:PivotTo(target)
			Combat.resetFall(player)
		end
	end
end

local function onPlayerAdded(player: Player)
	local profile = Data.load(player)
	if not player.Parent then
		Data.release(player)
		return
	end
	Inventory.load(player, profile.inventory)
	Combat.addPlayer(player)
	player:SetAttribute("Kills", profile.kills)
	player:SetAttribute("Deaths", profile.deaths)
	player:SetAttribute("Xp", profile.xp)
	player:SetAttribute("Streak", 0)

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	player.CharacterAppearanceLoaded:Connect(function(character)
		Visuals.blockify(character)
		Visuals.refresh(player, true)
	end)

	pcall(player.LoadCharacterAsync, player)
	Kits.sendInfo(player, false)
	Messages.broadcast(`{player.Name} joined the game`, "join")
	Messages.send(player, `Welcome to {Config.GAME_NAME}! Type /help for commands.`, "success")
	if not profile.loaded then
		Messages.send(player, "Your data couldn't be loaded, so progress this session won't be saved.", "error")
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	if Data.profiles[player] then
		Messages.broadcast(`{player.Name} left the game`, "join")
	end
	Combat.handleLeave(player)
	Data.save(player, Inventory.serialize(player))
	Inventory.release(player)
	Survival.remove(player)
	Visuals.release(player)
	Data.release(player)
	RateLimit.clear(player)
end)

game:BindToClose(function()
	local pending = 0
	for _, player in Players:GetPlayers() do
		pending += 1
		task.spawn(function()
			Data.save(player, Inventory.serialize(player))
			pending -= 1
		end)
	end
	local started = os.clock()
	while pending > 0 and os.clock() - started < 25 do
		task.wait(0.2)
	end
end)

task.spawn(function()
	while true do
		task.wait(120)
		for _, player in Players:GetPlayers() do
			task.spawn(Data.save, player, Inventory.serialize(player))
		end
	end
end)

-- Day/night cycle starting at 8:00, one full day per Config.DAY_LENGTH seconds. Fog hides the edge
-- of the streamed-in world and follows the sky colour.
local DAY_FOG, NIGHT_FOG = Color3.fromRGB(160, 195, 255), Color3.fromRGB(8, 10, 20)
task.spawn(function()
	local started = os.clock()
	while true do
		local clock = (8 + (os.clock() - started) / Config.DAY_LENGTH * 24) % 24
		Lighting.ClockTime = clock
		-- 1 at midday, 0 at night, blending over the hours around 6:00 and 18:00.
		local daylight = math.clamp(1 - (math.abs(clock - 12) - 5) / 2, 0, 1)
		Lighting.FogColor = NIGHT_FOG:Lerp(DAY_FOG, daylight)
		Lighting.OutdoorAmbient = Color3.fromRGB(70, 75, 95):Lerp(Color3.fromRGB(150, 150, 150), daylight)
		task.wait(1)
	end
end)
