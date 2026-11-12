-- Melee combat following Minecraft Java 1.21.1: attack cooldown, critical and sprint hits,
-- armor/toughness/Protection reduction, Sharpness, Fire Aspect, hit invulnerability, knockback.
-- Works on "entities" so players and the PvP bot share the same rules.
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
local INVULNERABLE_SECONDS = 0.5 -- 10 hurt ticks
local REACH_TOLERANCE = 5 -- studs, root-to-root, to absorb latency and hitbox size
local FIRE_SECONDS_PER_LEVEL = 4

export type Entity = {
	name: string,
	player: Player?,
	isBot: boolean,
	armorStats: () -> (number, number, number), -- armor points, toughness, Protection levels
	weapon: () -> Items.Stack?,
	knockback: (Vector3) -> (),
	onDeath: ((Entity, Entity?) -> ())?,

	model: Model?,
	humanoid: Humanoid?,
	root: BasePart?,
	dead: boolean,
	lastAttack: number,
	hurtAt: number,
	lastRegen: number,
	lastAttacker: Entity?,
	lastAttackerAt: number,
	lastCause: string,
	falling: boolean,
	fallStartY: number,
	fallSafe: boolean,
	lastSafeAt: number,
	lastPosition: Vector3?,
	burningUntil: number,
	nextBurnAt: number,
	burnSource: Entity?,
	respawnAtArena: boolean,
}

local entities: { Entity } = {}
local byModel: { [Model]: Entity } = {}
local byPlayer: { [Player]: Entity } = {}

function Combat.newEntity(props: {
	name: string,
	player: Player?,
	isBot: boolean,
	armorStats: () -> (number, number, number),
	weapon: () -> Items.Stack?,
	knockback: (Vector3) -> (),
	onDeath: ((Entity, Entity?) -> ())?,
}): Entity
	local entity: Entity = {
		name = props.name,
		player = props.player,
		isBot = props.isBot,
		armorStats = props.armorStats,
		weapon = props.weapon,
		knockback = props.knockback,
		onDeath = props.onDeath,
		model = nil,
		humanoid = nil,
		root = nil,
		dead = true,
		lastAttack = 0,
		hurtAt = 0,
		lastRegen = 0,
		lastAttacker = nil,
		lastAttackerAt = 0,
		lastCause = "generic",
		falling = false,
		fallStartY = 0,
		fallSafe = false,
		lastSafeAt = 0,
		lastPosition = nil,
		burningUntil = 0,
		nextBurnAt = 0,
		burnSource = nil,
		respawnAtArena = false,
	}
	table.insert(entities, entity)
	return entity
end

function Combat.removeEntity(entity: Entity)
	if entity.model then
		byModel[entity.model] = nil
	end
	local i = table.find(entities, entity)
	if i then
		table.remove(entities, i)
	end
end

-- Humanoid and root part of a living entity, or nil.
function Combat.alive(entity: Entity?): (Humanoid?, BasePart?)
	if not entity or entity.dead then
		return nil, nil
	end
	local humanoid, root = entity.humanoid, entity.root
	if not humanoid or not root or not root.Parent or humanoid.Health <= 0 then
		return nil, nil
	end
	return humanoid, root
end

function Combat.ofPlayer(player: Player): Entity?
	return byPlayer[player]
end

function Combat.players(): { Entity }
	local list = {}
	for _, entity in byPlayer do
		table.insert(list, entity)
	end
	return list
end

-- Root part of a living player's character, or nil.
function Combat.rootOf(player: Player): BasePart?
	local _, root = Combat.alive(byPlayer[player])
	return root
end

function Combat.isTagged(player: Player): boolean
	return (player:GetAttribute(TAG_ATTRIBUTE) or 0) > workspace:GetServerTimeNow()
end

function Combat.tagRemaining(player: Player): number
	return math.max(0, (player:GetAttribute(TAG_ATTRIBUTE) or 0) - workspace:GetServerTimeNow())
end

local function tag(entity: Entity)
	if entity.player then
		entity.player:SetAttribute(TAG_ATTRIBUTE, workspace:GetServerTimeNow() + Config.COMBAT_TAG_SECONDS)
	end
end

function Combat.resetFall(player: Player)
	local entity = byPlayer[player]
	if entity then
		entity.falling = false
	end
end

local function extinguish(entity: Entity)
	entity.burningUntil = 0
	local fire = entity.root and entity.root:FindFirstChild("Burning")
	if fire then
		fire:Destroy()
	end
end

local function ignite(entity: Entity, seconds: number, source: Entity?)
	local now = os.clock()
	if entity.burningUntil <= now then
		entity.nextBurnAt = now + 1
	end
	entity.burningUntil = math.max(entity.burningUntil, now + seconds)
	entity.burnSource = source
	local root = entity.root
	if root and not root:FindFirstChild("Burning") then
		local fire = Instance.new("Fire")
		fire.Name = "Burning"
		fire.Size = 6
		fire.Heat = 8
		fire.Parent = root
	end
end

-- Armor points reduce damage; toughness resists big hits.
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

-- cause: "attack" | "fall" | "fire" | "void"
function Combat.damage(victim: Entity, amount: number, cause: string, attacker: Entity?)
	local humanoid, root = Combat.alive(victim)
	if not humanoid or not root then
		return
	end
	local armor, toughness, protection = victim.armorStats()
	if cause == "attack" then
		amount = reduceByArmor(amount, armor, toughness)
		victim.hurtAt = os.clock()
	end
	if cause ~= "void" then
		-- Each Protection level is 4%, capped at 80%.
		amount *= 1 - math.min(protection, 20) / 25
	end

	victim.lastRegen = os.clock()
	victim.lastCause = cause
	if attacker then
		victim.lastAttacker = attacker
		victim.lastAttackerAt = os.clock()
	end
	humanoid.Health = math.max(0, humanoid.Health - amount)
	if victim.model then
		flashRed(victim.model)
	end
	Sounds.play("hurt", root, 0.5)
end

-- One melee swing from `attacker` at `victim`. `sprintHint` overrides sprint detection (used by the
-- bot, which knows whether it is sprinting). Returns true if the hit landed.
function Combat.attack(attacker: Entity, victim: Entity, sprintHint: boolean?): boolean
	local _, attackerRoot = Combat.alive(attacker)
	local _, victimRoot = Combat.alive(victim)
	if not attackerRoot or not victimRoot or attacker == victim then
		return false
	end
	if not Zones.pvpAllowedAt(attackerRoot.Position) or not Zones.pvpAllowedAt(victimRoot.Position) then
		if attacker.player then
			Messages.actionBar(attacker.player, "PvP is disabled here.")
		end
		return false
	end

	local now = os.clock()
	local stack = attacker.weapon()
	local def = stack and Items.get(stack.id)
	local base, speed = Items.FIST.damage, Items.FIST.attackSpeed
	if def and def.kind == "sword" then
		base, speed = def.damage or base, def.attackSpeed or speed
	end
	-- Attack cooldown: swinging before the weapon recharges does a fraction of the damage.
	local charge = math.clamp((now - attacker.lastAttack) * speed, 0, 1)
	attacker.lastAttack = now

	if now - victim.hurtAt < INVULNERABLE_SECONDS then
		return false
	end

	local velocity = attackerRoot.AssemblyLinearVelocity
	local strong = charge > 0.9
	local sprinting = sprintHint
	if sprinting == nil then
		sprinting = (velocity * Vector3.new(1, 0, 1)).Magnitude > (Config.WALK_SPEED + Config.SPRINT_SPEED) / 2
	end
	-- Critical hit: fully charged, falling, and not sprinting.
	local critical = strong and velocity.Y < -1 and not sprinting

	local damage = base * (0.2 + charge * charge * 0.8)
	if critical then
		damage *= 1.5
	end
	local ench = stack and stack.ench
	if ench and ench.sharpness then
		damage += (0.5 * ench.sharpness + 0.5) * charge
	end

	tag(attacker)
	tag(victim)
	Combat.damage(victim, damage, "attack", attacker)
	if ench and ench.fire_aspect then
		ignite(victim, FIRE_SECONDS_PER_LEVEL * ench.fire_aspect, attacker)
	end
	Sounds.play("hit", victimRoot, if critical then 0.9 else 0.5)

	local away = (victimRoot.Position - attackerRoot.Position) * Vector3.new(1, 0, 1)
	if away.Magnitude > 0.01 then
		local strength = Config.KNOCKBACK_HORIZONTAL
		if strong and sprinting then
			strength += Config.KNOCKBACK_SPRINT_BONUS
		end
		local push = away.Unit * strength
		victim.knockback(Vector3.new(push.X, Config.KNOCKBACK_VERTICAL, push.Z))
	end
	return true
end

local function onAttack(player: Player, target: any)
	if not RateLimit.allow(player, "attack", 12) then
		return
	end
	local attacker = byPlayer[player]
	local victim = if typeof(target) == "Instance" and target:IsA("Model") then byModel[target] else nil
	if not attacker or not victim then
		return
	end
	local _, attackerRoot = Combat.alive(attacker)
	local _, victimRoot = Combat.alive(victim)
	if not attackerRoot or not victimRoot then
		return
	end
	if (attackerRoot.Position - victimRoot.Position).Magnitude > Config.ATTACK_REACH * B + REACH_TOLERANCE then
		return
	end
	Combat.attack(attacker, victim)
end

local function recentKiller(entity: Entity): Entity?
	local killer = entity.lastAttacker
	if not killer or os.clock() - entity.lastAttackerAt > Config.COMBAT_TAG_SECONDS then
		return nil
	end
	if killer.player and not killer.player.Parent then
		return nil
	end
	return killer
end

local function deathMessage(entity: Entity, killer: Entity?): string
	local name = entity.name
	local cause = entity.lastCause
	if cause == "attack" and killer then
		return `{name} was slain by {killer.name}`
	elseif cause == "fall" then
		return if killer then `{name} was doomed to fall by {killer.name}` else `{name} fell from a high place`
	elseif cause == "fire" then
		return if killer then `{name} was burned to a crisp while fighting {killer.name}` else `{name} burned to death`
	elseif cause == "void" then
		return if killer then `{name} was knocked into the void by {killer.name}` else `{name} fell out of the world`
	end
	return `{name} died`
end

local function onDied(entity: Entity, model: Model)
	if entity.dead or entity.model ~= model then
		return
	end
	entity.dead = true
	extinguish(entity)
	local killer = recentKiller(entity)
	local position = entity.lastPosition or (entity.root and entity.root.Position) or Vector3.zero

	local player = entity.player
	if player then
		entity.respawnAtArena = Zones.zoneAt(position) == "arena" or Zones.zoneAt(position) == "pvpspawn"
		Drops.scatter(Inventory.clearAll(player), position)
		player:SetAttribute(TAG_ATTRIBUTE, 0)
		player:SetAttribute("Deaths", (player:GetAttribute("Deaths") or 0) + 1)
		player:SetAttribute("Streak", 0)

		local message = deathMessage(entity, killer)
		Messages.broadcast(message, "death")
		Remotes.Died:FireClient(player, message)

		local killerPlayer = killer and killer.player
		if killerPlayer then
			local streak = (killerPlayer:GetAttribute("Streak") or 0) + 1
			killerPlayer:SetAttribute("Kills", (killerPlayer:GetAttribute("Kills") or 0) + 1)
			killerPlayer:SetAttribute("Streak", streak)
			if streak % 5 == 0 then
				Messages.broadcast(`{killerPlayer.Name} is on a {streak} kill streak!`, "streak")
			end
		end

		task.delay(Config.RESPAWN_TIMEOUT, function()
			if player.Parent and entity.dead and entity.model == model then
				pcall(player.LoadCharacterAsync, player)
			end
		end)
	end

	if entity.onDeath then
		entity.onDeath(entity, killer)
	end
end

-- Attaches an entity to a freshly spawned character model.
function Combat.bind(entity: Entity, model: Model)
	local humanoid = model:WaitForChild("Humanoid") :: Humanoid
	local root = model:WaitForChild("HumanoidRootPart") :: BasePart
	if entity.model then
		byModel[entity.model] = nil
	end
	byModel[model] = entity
	entity.model = model
	entity.humanoid = humanoid
	entity.root = root
	entity.dead = false
	entity.falling = false
	entity.lastAttacker = nil
	entity.lastCause = "generic"
	entity.lastPosition = nil
	entity.burningUntil = 0
	entity.lastRegen = os.clock()

	humanoid.MaxHealth = Config.MAX_HEALTH
	humanoid.Health = Config.MAX_HEALTH
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.Died:Connect(function()
		onDied(entity, model)
	end)
	model.Destroying:Connect(function()
		byModel[model] = nil
	end)
end

function Combat.addPlayer(player: Player): Entity
	local entity = Combat.newEntity({
		name = player.Name,
		player = player,
		isBot = false,
		armorStats = function()
			return Inventory.armorStats(player)
		end,
		weapon = function()
			return (Inventory.selected(player))
		end,
		knockback = function(push: Vector3)
			-- Players own their character's physics, so the push is applied on their client.
			Remotes.Knockback:FireClient(player, push)
		end,
	})
	byPlayer[player] = entity
	return entity
end

local function respawn(player: Player)
	if not RateLimit.allow(player, "respawn", 1) then
		return
	end
	-- Only dead players may respawn; the first spawn happens after their data has loaded.
	local entity = byPlayer[player]
	if entity and entity.dead and entity.model then
		pcall(player.LoadCharacterAsync, player)
	end
end

-- Called from PlayerRemoving. Leaving while tagged drops everything where the player stood.
function Combat.handleLeave(player: Player)
	local entity = byPlayer[player]
	if not entity then
		return
	end
	if not entity.dead and Combat.isTagged(player) then
		local stacks = Inventory.clearAll(player)
		if entity.lastPosition then
			Drops.scatter(stacks, entity.lastPosition)
		end
		Messages.broadcast(`{player.Name} logged out during combat and dropped all their items!`, "death")
	end
	byPlayer[player] = nil
	Combat.removeEntity(entity)
end

local function step()
	local now = os.clock()
	for _, entity in entities do
		local humanoid, root = Combat.alive(entity)
		if not humanoid or not root then
			continue
		end
		local position = root.Position
		entity.lastPosition = position

		if position.Y < -40 then
			entity.lastCause = "void"
			humanoid.Health = 0
			continue
		end

		if Zones.zoneAt(position) == "pvpspawn" then
			entity.lastSafeAt = now
		end

		-- Fall damage: one half-heart per block fallen beyond three. Dropping off the PvP warp's
		-- spawn platform is free.
		local vy = root.AssemblyLinearVelocity.Y
		if vy < -3 then
			if not entity.falling then
				entity.falling = true
				entity.fallStartY = position.Y
				entity.fallSafe = now - entity.lastSafeAt < 1.5
			end
		elseif entity.falling and vy > -1 then
			entity.falling = false
			local damage = math.floor((entity.fallStartY - position.Y) / B - 3)
			if damage > 0 and not entity.fallSafe then
				Combat.damage(entity, damage, "fall")
			end
		end

		if entity.burningUntil > 0 then
			if now >= entity.burningUntil then
				extinguish(entity)
			elseif now >= entity.nextBurnAt then
				entity.nextBurnAt += 1
				Combat.damage(entity, 1, "fire", entity.burnSource)
			end
		end

		if humanoid.Health > 0 and humanoid.Health < humanoid.MaxHealth and now - entity.lastRegen >= Config.REGEN_INTERVAL then
			entity.lastRegen = now
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + 1)
		end
	end
end

function Combat.init()
	Remotes.Attack.OnServerEvent:Connect(onAttack)
	Remotes.Respawn.OnServerEvent:Connect(respawn)
	Remotes.Swing.OnServerEvent:Connect(function(player)
		if RateLimit.allow(player, "swing", 12) and player.Character then
			Remotes.SwingFx:FireAllClients(player.Character)
		end
	end)
	RunService.Heartbeat:Connect(step)
end

return Combat
