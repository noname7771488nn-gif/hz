-- Melee combat using the system Minecraft introduced in 1.9: attack cooldown, critical hits,
-- sprint knockback, sweep attacks, armor/toughness/Protection, Sharpness, Fire Aspect, absorption
-- and hit invulnerability. Works on "entities" so players and the PvP bot share the same rules.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Items = require(Shared.Items)
local Zones = require(Shared.Zones)
local Remotes = require(Shared.Remotes)
local Sounds = require(Shared.Sounds)
local Xp = require(Shared.Xp)

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
local SWEEP_DAMAGE = 1
local SWEEP_RADIUS = 1.7 * B -- how close to the main target a bystander must be
local SWEEP_REACH = 3 * B + 2
local BOT_REGEN_INTERVAL = 4

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
	lastAttack: number, -- when the attack cooldown last reset
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
	absorption: number, -- extra golden hearts, used up before health
	exhaustion: number, -- hunger cost of fighting; consumed by Survival
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
		absorption = 0,
		exhaustion = 0,
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

-- Any arm swing or change of held item restarts the attack cooldown.
function Combat.resetCooldown(player: Player)
	local entity = byPlayer[player]
	if entity then
		entity.lastAttack = os.clock()
	end
end

function Combat.setAbsorption(entity: Entity, amount: number)
	entity.absorption = math.max(0, amount)
	if entity.player then
		entity.player:SetAttribute("Absorption", entity.absorption)
	end
end

function Combat.heal(entity: Entity, amount: number)
	local humanoid = Combat.alive(entity)
	if humanoid then
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount)
	end
end

function Combat.addXp(player: Player, amount: number)
	player:SetAttribute("Xp", math.max(0, (player:GetAttribute("Xp") or 0) + amount))
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

-- cause: "attack" | "fall" | "fire" | "starve" | "void"
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
	if cause ~= "void" and cause ~= "starve" then
		-- Each Protection level is 4%, capped at 80%.
		amount *= 1 - math.min(protection, 20) / 25
	end

	if victim.absorption > 0 then
		local absorbed = math.min(victim.absorption, amount)
		amount -= absorbed
		Combat.setAbsorption(victim, victim.absorption - absorbed)
	end

	victim.lastRegen = os.clock()
	victim.lastCause = cause
	victim.exhaustion += 0.1
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

local function push(victim: Entity, from: Vector3, strength: number)
	local root = victim.root
	if not root then
		return
	end
	local away = (root.Position - from) * Vector3.new(1, 0, 1)
	if away.Magnitude > 0.01 then
		local horizontal = away.Unit * strength
		victim.knockback(Vector3.new(horizontal.X, Config.KNOCKBACK_VERTICAL, horizontal.Z))
	end
end

-- A sweep hits everyone standing next to the main target for a little damage.
local function sweepAround(attacker: Entity, victim: Entity, attackerRoot: BasePart, victimRoot: BasePart)
	local now = os.clock()
	for _, other in entities do
		if other == attacker or other == victim then
			continue
		end
		local _, otherRoot = Combat.alive(other)
		if not otherRoot or now - other.hurtAt < INVULNERABLE_SECONDS or not Zones.pvpAllowedAt(otherRoot.Position) then
			continue
		end
		local offset = otherRoot.Position - victimRoot.Position
		local near = (offset * Vector3.new(1, 0, 1)).Magnitude <= SWEEP_RADIUS and math.abs(offset.Y) <= B
		if near and (otherRoot.Position - attackerRoot.Position).Magnitude <= SWEEP_REACH then
			tag(other)
			Combat.damage(other, SWEEP_DAMAGE, "attack", attacker)
			push(other, attackerRoot.Position, Config.KNOCKBACK_HORIZONTAL)
		end
	end
end

-- One melee hit from `attacker` on `victim`. `sprintHint` overrides sprint detection (used by the
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
	local isSword = def ~= nil and def.kind == "sword"
	local base = if def and isSword then def.damage or Items.FIST.damage else Items.FIST.damage
	-- Attack cooldown: swinging before the weapon recharges does a fraction of the damage.
	local charge = math.clamp((now - attacker.lastAttack) * Items.attackSpeed(stack), 0, 1)
	attacker.lastAttack = now
	attacker.exhaustion += 0.1

	if now - victim.hurtAt < INVULNERABLE_SECONDS then
		return false
	end

	local velocity = attackerRoot.AssemblyLinearVelocity
	local speed = (velocity * Vector3.new(1, 0, 1)).Magnitude
	local strong = charge > 0.9
	local sprinting = sprintHint
	if sprinting == nil then
		sprinting = speed > (Config.WALK_SPEED + Config.SPRINT_SPEED) / 2
	end
	local onGround = math.abs(velocity.Y) < 1
	-- Critical: fully charged, falling, not sprinting. Knockback hit: fully charged while
	-- sprinting. Sweep: fully charged sword hit while standing or walking on the ground.
	local critical = strong and velocity.Y < -1 and not sprinting
	local knockbackHit = strong and sprinting
	local sweep = strong and isSword and not critical and not knockbackHit and onGround and speed <= Config.WALK_SPEED + 1

	local damage = base * (0.2 + charge * charge * 0.8)
	if critical then
		damage *= 1.5
	end
	local ench = stack and stack.ench
	local sharpness = if ench then ench.sharpness or 0 else 0
	if sharpness > 0 then
		damage += (0.5 * sharpness + 0.5) * charge
	end

	tag(attacker)
	tag(victim)
	Combat.damage(victim, damage, "attack", attacker)
	if ench and ench.fire_aspect then
		ignite(victim, FIRE_SECONDS_PER_LEVEL * ench.fire_aspect, attacker)
	end
	push(victim, attackerRoot.Position, Config.KNOCKBACK_HORIZONTAL + (if knockbackHit then Config.KNOCKBACK_SPRINT_BONUS else 0))
	if sweep then
		sweepAround(attacker, victim, attackerRoot, victimRoot)
	end

	local kind = if critical then "crit" elseif knockbackHit then "knockback" elseif sweep then "sweep" elseif strong then "strong" else "weak"
	Remotes.HitFx:FireAllClients(victim.model, kind, sharpness > 0, attacker.model)
	return true
end

local function onAttack(player: Player, target: any)
	if not RateLimit.allow(player, "attack", 12) then
		return
	end
	local attacker = byPlayer[player]
	if not attacker or not attacker.model then
		return
	end
	Remotes.SwingFx:FireAllClients(attacker.model)
	local victim = if typeof(target) == "Instance" and target:IsA("Model") then byModel[target] else nil
	local _, attackerRoot = Combat.alive(attacker)
	local _, victimRoot = Combat.alive(victim)
	if not victim or not attackerRoot or not victimRoot then
		attacker.lastAttack = os.clock()
		return
	end
	if (attackerRoot.Position - victimRoot.Position).Magnitude > Config.ATTACK_REACH * B + REACH_TOLERANCE then
		attacker.lastAttack = os.clock()
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
	elseif cause == "starve" then
		return if killer then `{name} starved to death while fighting {killer.name}` else `{name} starved to death`
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
	Combat.setAbsorption(entity, 0)
	local killer = recentKiller(entity)
	local position = entity.lastPosition or (entity.root and entity.root.Position) or Vector3.zero

	local player = entity.player
	if player then
		entity.respawnAtArena = Zones.zoneAt(position) == "arena" or Zones.zoneAt(position) == "pvpspawn"
		Drops.scatter(Inventory.clearAll(player), position)
		local level = Xp.level(player:GetAttribute("Xp") or 0)
		player:SetAttribute(TAG_ATTRIBUTE, 0)
		player:SetAttribute("Deaths", (player:GetAttribute("Deaths") or 0) + 1)
		player:SetAttribute("Streak", 0)

		local message = deathMessage(entity, killer)
		Messages.broadcast(message, "death")
		Remotes.Died:FireClient(player, message, player:GetAttribute("Xp") or 0)
		-- Experience is lost on death; part of it goes to the killer.
		player:SetAttribute("Xp", 0)

		local killerPlayer = killer and killer.player
		if killerPlayer then
			local streak = (killerPlayer:GetAttribute("Streak") or 0) + 1
			killerPlayer:SetAttribute("Kills", (killerPlayer:GetAttribute("Kills") or 0) + 1)
			killerPlayer:SetAttribute("Streak", streak)
			Combat.addXp(killerPlayer, math.clamp(level * 7, 10, 100))
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
	entity.exhaustion = 0
	entity.lastRegen = os.clock()
	Combat.setAbsorption(entity, 0)

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
		knockback = function(velocity: Vector3)
			-- Players own their character's physics, so the push is applied on their client.
			Remotes.Knockback:FireClient(player, velocity)
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

		-- Players regenerate through the hunger system (Survival); the bot just heals slowly.
		if entity.isBot and humanoid.Health > 0 and humanoid.Health < humanoid.MaxHealth and now - entity.lastRegen >= BOT_REGEN_INTERVAL then
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
			Combat.resetCooldown(player)
			Remotes.SwingFx:FireAllClients(player.Character)
		end
	end)
	RunService.Heartbeat:Connect(step)
end

return Combat
