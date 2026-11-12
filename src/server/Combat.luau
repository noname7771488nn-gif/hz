-- Melee PvP with Minecraft 1.9+ damage rules, combat tagging, fall/void damage, regen and deaths.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Items = require(Shared.Items)
local Zones = require(Shared.Zones)
local Remotes = require(Shared.Remotes)
local Sounds = require(Shared.Sounds)

local Inventory = require(script.Parent.Inventory)
local Drops = require(script.Parent.Drops)
local Messages = require(script.Parent.Messages)
local RateLimit = require(script.Parent.RateLimit)

local Combat = {}

local B = Config.BLOCK_SIZE
local TAG_ATTRIBUTE = "CombatUntil" -- server time when the combat tag ends; read by the client HUD
local INVULNERABLE_SECONDS = 0.5 -- Minecraft's 10 hurt ticks
local REACH_TOLERANCE = 5 -- studs, root-to-root, to absorb latency and hitbox size

type State = {
	lastAttack: number,
	hurtAt: number,
	lastRegen: number,
	lastAttacker: Player?,
	lastAttackerAt: number,
	lastCause: string,
	falling: boolean,
	fallStartY: number,
	lastPosition: Vector3?,
	dead: boolean,
}

local states: { [Player]: State } = {}

local function getState(player: Player): State
	local state = states[player]
	if not state then
		state = {
			lastAttack = 0,
			hurtAt = 0,
			lastRegen = 0,
			lastAttacker = nil,
			lastAttackerAt = 0,
			lastCause = "generic",
			falling = false,
			fallStartY = 0,
			lastPosition = nil,
			dead = false,
		}
		states[player] = state
	end
	return state
end

function Combat.aliveCharacter(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root or humanoid.Health <= 0 then
		return nil, nil, nil
	end
	return character, humanoid, root
end

function Combat.isTagged(player: Player): boolean
	return (player:GetAttribute(TAG_ATTRIBUTE) or 0) > workspace:GetServerTimeNow()
end

function Combat.tagRemaining(player: Player): number
	return math.max(0, (player:GetAttribute(TAG_ATTRIBUTE) or 0) - workspace:GetServerTimeNow())
end

function Combat.tag(player: Player)
	player:SetAttribute(TAG_ATTRIBUTE, workspace:GetServerTimeNow() + Config.COMBAT_TAG_SECONDS)
end

function Combat.resetFall(player: Player)
	getState(player).falling = false
end

function Combat.isDead(player: Player): boolean
	return getState(player).dead
end

-- Minecraft armor formula: armor points reduce damage, toughness resists high hits.
local function reduceByArmor(damage: number, armor: number, toughness: number): number
	local effective = math.clamp(armor - 4 * damage / (toughness + 8), armor / 5, 20)
	return damage * (1 - effective / 25)
end

local function flashRed(character: Model)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.fromRGB(255, 0, 0)
	highlight.FillTransparency = 0.45
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = character
	task.delay(0.3, function()
		highlight:Destroy()
	end)
end

-- cause: "attack" | "fall" | "void"
function Combat.damage(player: Player, amount: number, cause: string, attacker: Player?)
	local character, humanoid, root = Combat.aliveCharacter(player)
	if not character or not humanoid or not root then
		return
	end
	local state = getState(player)
	local armor, toughness, protection = Inventory.armorStats(player)
	if cause == "attack" then
		amount = reduceByArmor(amount, armor, toughness)
	end
	if cause ~= "void" then
		amount *= 1 - math.min(protection, 20) / 25
	end

	state.hurtAt = os.clock()
	state.lastRegen = os.clock()
	state.lastCause = cause
	if attacker then
		state.lastAttacker = attacker
		state.lastAttackerAt = os.clock()
	end
	humanoid.Health = math.max(0, humanoid.Health - amount)
	flashRed(character)
	Sounds.play("hurt", root, 0.5)
end

local function onAttack(attacker: Player, target: any)
	if not RateLimit.allow(attacker, "attack", 12) then
		return
	end
	if typeof(target) ~= "Instance" or not target:IsA("Player") or target == attacker then
		return
	end
	local _, _, attackerRoot = Combat.aliveCharacter(attacker)
	local _, _, targetRoot = Combat.aliveCharacter(target)
	if not attackerRoot or not targetRoot then
		return
	end
	if (attackerRoot.Position - targetRoot.Position).Magnitude > Config.ATTACK_REACH * B + REACH_TOLERANCE then
		return
	end
	if not Zones.pvpAllowedAt(attackerRoot.Position) or not Zones.pvpAllowedAt(targetRoot.Position) then
		Messages.actionBar(attacker, "PvP is disabled here.")
		return
	end

	local state = getState(attacker)
	local victimState = getState(target)
	local now = os.clock()

	local stack = Inventory.selected(attacker)
	local def = stack and Items.get(stack.id)
	local base, speed = Items.FIST.damage, Items.FIST.attackSpeed
	if def and def.kind == "sword" then
		base, speed = def.damage or base, def.attackSpeed or speed
	end
	-- Attack cooldown: spam-clicking does a fraction of the damage, as in 1.9+.
	local charge = math.clamp((now - state.lastAttack) * speed, 0, 1)
	state.lastAttack = now

	if now - victimState.hurtAt < INVULNERABLE_SECONDS then
		return
	end

	local sharpness = if stack and stack.ench then stack.ench.sharpness or 0 else 0
	local damage = base * (0.2 + charge * charge * 0.8)
	if sharpness > 0 then
		damage += (0.5 * sharpness + 0.5) * charge
	end
	local critical = charge > 0.9 and attackerRoot.AssemblyLinearVelocity.Y < -1
	if critical then
		damage *= 1.5
	end

	Combat.tag(attacker)
	Combat.tag(target)
	Combat.damage(target, damage, "attack", attacker)
	Sounds.play("hit", targetRoot, if critical then 0.8 else 0.5)

	local away = (targetRoot.Position - attackerRoot.Position) * Vector3.new(1, 0, 1)
	if away.Magnitude > 0.01 then
		local strength = Config.KNOCKBACK_HORIZONTAL * (if charge > 0.9 then 1 else 0.5)
		Remotes.Knockback:FireClient(target, away.Unit * strength)
	end
end

local function deathMessage(player: Player, state: State): string
	local killer = state.lastAttacker
	if killer and (os.clock() - state.lastAttackerAt > Config.COMBAT_TAG_SECONDS or not killer.Parent) then
		killer = nil
	end
	local name = player.Name
	if state.lastCause == "attack" and killer then
		return `{name} was slain by {killer.Name}`
	elseif state.lastCause == "fall" then
		return if killer then `{name} was doomed to fall by {killer.Name}` else `{name} fell from a high place`
	elseif state.lastCause == "void" then
		return if killer then `{name} was knocked into the void by {killer.Name}` else `{name} fell out of the world`
	end
	return `{name} died`
end

function Combat.dropEverything(player: Player, position: Vector3)
	Drops.scatter(Inventory.clearAll(player), position)
end

local function onDied(player: Player, character: Model, root: BasePart)
	local state = getState(player)
	if state.dead then
		return
	end
	state.dead = true
	local position = state.lastPosition or root.Position
	Combat.dropEverything(player, position)
	player:SetAttribute(TAG_ATTRIBUTE, 0)

	local message = deathMessage(player, state)
	Messages.broadcast(message, "death")
	Remotes.Died:FireClient(player, message)

	task.delay(Config.RESPAWN_TIMEOUT, function()
		if player.Parent and state.dead and player.Character == character then
			pcall(player.LoadCharacterAsync, player)
		end
	end)
end

function Combat.onCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart
	local state = getState(player)
	state.dead = false
	state.falling = false
	state.lastAttacker = nil
	state.lastCause = "generic"
	state.lastPosition = nil

	humanoid.MaxHealth = Config.MAX_HEALTH
	humanoid.Health = Config.MAX_HEALTH
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.Died:Connect(function()
		onDied(player, character, root)
	end)
end

function Combat.respawn(player: Player)
	if not RateLimit.allow(player, "respawn", 1) then
		return
	end
	-- Only dead players may respawn; the first spawn happens after their data has loaded.
	if getState(player).dead then
		pcall(player.LoadCharacterAsync, player)
	end
end

-- Called from PlayerRemoving. Leaving while tagged drops everything where the player stood.
function Combat.handleLeave(player: Player): boolean
	local state = states[player]
	local combatLogged = false
	if state and not state.dead and Combat.isTagged(player) then
		combatLogged = true
		if state.lastPosition then
			Combat.dropEverything(player, state.lastPosition)
		else
			Inventory.clearAll(player)
		end
		Messages.broadcast(`{player.Name} logged out during combat and dropped all their items!`, "death")
	end
	states[player] = nil
	return combatLogged
end

local function step()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local character, humanoid, root = Combat.aliveCharacter(player)
		if not character or not humanoid or not root then
			continue
		end
		local state = getState(player)
		local position = root.Position
		state.lastPosition = position

		if position.Y < -40 then
			state.lastCause = "void"
			humanoid.Health = 0
			continue
		end

		-- Fall damage: one half-heart per block fallen beyond three.
		local vy = root.AssemblyLinearVelocity.Y
		if vy < -3 then
			if not state.falling then
				state.falling = true
				state.fallStartY = position.Y
			end
		elseif state.falling and vy > -1 then
			state.falling = false
			local damage = math.floor((state.fallStartY - position.Y) / B - 3)
			if damage > 0 then
				Combat.damage(player, damage, "fall")
			end
		end

		if humanoid.Health < humanoid.MaxHealth and now - state.lastRegen >= Config.REGEN_INTERVAL then
			state.lastRegen = now
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + 1)
		end
	end
end

function Combat.init()
	Remotes.Attack.OnServerEvent:Connect(onAttack)
	Remotes.Respawn.OnServerEvent:Connect(Combat.respawn)
	Remotes.Swing.OnServerEvent:Connect(function(player)
		if RateLimit.allow(player, "swing", 12) then
			Remotes.SwingFx:FireAllClients(player)
		end
	end)
	RunService.Heartbeat:Connect(step)
end

return Combat
