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
Building.init()
Commands.init()
Kits.init()
Bot.init()

Inventory.onChanged(function(player)
	Visuals.refresh(player)
end)

-- Inventory remotes --------------------------------------------------------------------------------

Remotes.SelectSlot.OnServerEvent:Connect(function(player, index)
	if RateLimit.allow(player, "select", 30) and type(index) == "number" then
		Inventory.select(player, index)
	end
end)

Remotes.MoveSlot.OnServerEvent:Connect(function(player, from, to)
	if RateLimit.allow(player, "move", 20) then
		Inventory.move(player, from, to)
	end
end)

Remotes.QuickMove.OnServerEvent:Connect(function(player, ref)
	if RateLimit.allow(player, "quickMove", 20) then
		Inventory.quickMove(player, ref)
	end
end)

Remotes.DropItem.OnServerEvent:Connect(function(player, wholeStack)
	if not RateLimit.allow(player, "drop", 10) then
		return
	end
	local root = Combat.rootOf(player)
	if not root then
		return
	end
	local stack = Inventory.takeSelected(player, if wholeStack == true then 64 else 1)
	if stack then
		local look = root.CFrame.LookVector
		Drops.spawn(stack, root.Position + look * 2 + Vector3.new(0, 1, 0), look * 14 + Vector3.new(0, 8, 0), 2)
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
