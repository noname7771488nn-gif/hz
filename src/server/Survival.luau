-- Hunger, eating and food effects for players, following Minecraft's rules:
-- sprinting, fighting and healing cost exhaustion; exhaustion drains saturation, then hunger;
-- a full hunger bar heals quickly while saturation lasts, an empty one starves.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Items = require(Shared.Items)
local Remotes = require(Shared.Remotes)
local Sounds = require(Shared.Sounds)

local Combat = require(script.Parent.Combat)
local Inventory = require(script.Parent.Inventory)
local RateLimit = require(script.Parent.RateLimit)

local Survival = {}

local B = Config.BLOCK_SIZE
local MAX_FOOD = 20
local SPRINT_THRESHOLD = (Config.WALK_SPEED + Config.SPRINT_SPEED) / 2
local SPRINT_COST = 0.1 -- exhaustion per block sprinted
local REGEN_II_INTERVAL = 1.25 -- seconds per half heart
local GOLDEN_APPLE = { regenSeconds = 5, absorption = 4, absorptionSeconds = 120 }

type Vitals = {
	food: number,
	saturation: number,
	timer: number, -- seconds since the last natural heal or starvation tick
	eating: { ref: any, id: string, finishAt: number }?,
	regenUntil: number,
	nextRegenAt: number,
	absorbUntil: number,
	lastPosition: Vector3?,
}

local vitals: { [Player]: Vitals } = {}

local function stopEating(player: Player, v: Vitals)
	if v.eating then
		v.eating = nil
		player:SetAttribute("Eating", nil)
	end
end

-- The slot the player would eat from: the held item first, then the offhand.
local function edible(player: Player, v: Vitals): (any, Items.Stack?)
	local held, index = Inventory.selected(player)
	local offhand = Inventory.offhand(player)
	for _, candidate in { { ref = index, stack = held }, { ref = "offhand", stack = offhand } } :: { any } do
		local def = candidate.stack and Items.get(candidate.stack.id)
		if def and def.food and (v.food < MAX_FOOD or def.alwaysEdible) then
			return candidate.ref, candidate.stack
		end
	end
	return nil, nil
end

local function stackAt(player: Player, ref: any): Items.Stack?
	if ref == "offhand" then
		return Inventory.offhand(player)
	end
	local held, index = Inventory.selected(player)
	return if index == ref then held else nil
end

local function finishEating(player: Player, v: Vitals, entity: Combat.Entity, root: BasePart)
	local eating = v.eating
	if not eating then
		return
	end
	stopEating(player, v)
	local def = Items.get(eating.id)
	if not def or not def.food or not Inventory.takeFrom(player, eating.ref, 1) then
		return
	end
	v.food = math.min(MAX_FOOD, v.food + def.food)
	v.saturation = math.min(v.food, v.saturation + (def.saturation or 0))
	player:SetAttribute("Food", v.food)
	if def.goldenApple then
		local now = os.clock()
		v.regenUntil = now + GOLDEN_APPLE.regenSeconds
		v.nextRegenAt = now + REGEN_II_INTERVAL
		v.absorbUntil = now + GOLDEN_APPLE.absorptionSeconds
		Combat.setAbsorption(entity, GOLDEN_APPLE.absorption)
	end
	Sounds.play("burp", root)
end

local function step(dt: number)
	local now = os.clock()
	for player, v in vitals do
		local entity = Combat.ofPlayer(player)
		local humanoid, root = Combat.alive(entity)
		if not entity or not humanoid or not root then
			stopEating(player, v)
			v.lastPosition = nil
			continue
		end

		-- Sprinting makes you hungry.
		local position = root.Position
		if v.lastPosition and dt > 0 then
			local moved = ((position - v.lastPosition) * Vector3.new(1, 0, 1)).Magnitude
			-- Teleports move much further than this in one step and cost nothing.
			if moved / dt > SPRINT_THRESHOLD and moved < 12 then
				entity.exhaustion += moved / B * SPRINT_COST
			end
		end
		v.lastPosition = position

		while entity.exhaustion >= 4 do
			entity.exhaustion -= 4
			if v.saturation > 0 then
				v.saturation = math.max(0, v.saturation - 1)
			elseif v.food > 0 then
				v.food -= 1
				player:SetAttribute("Food", v.food)
			end
		end

		v.timer += dt
		local hurt = humanoid.Health < humanoid.MaxHealth
		if hurt and v.food >= MAX_FOOD and v.saturation > 0 then
			-- Full hunger bar: heal fast, paid for with saturation.
			if v.timer >= 0.5 then
				local spend = math.min(v.saturation, 6)
				Combat.heal(entity, spend / 6)
				entity.exhaustion += spend
				v.timer = 0
			end
		elseif hurt and v.food >= 18 then
			if v.timer >= 4 then
				Combat.heal(entity, 1)
				entity.exhaustion += 6
				v.timer = 0
			end
		elseif v.food <= 0 then
			-- Starving hurts down to half a heart, as on Normal difficulty.
			if v.timer >= 4 then
				if humanoid.Health > 1 then
					Combat.damage(entity, 1, "starve")
				end
				v.timer = 0
			end
		else
			v.timer = 0
		end

		if now < v.regenUntil and now >= v.nextRegenAt then
			v.nextRegenAt += REGEN_II_INTERVAL
			Combat.heal(entity, 1)
		end
		if entity.absorption > 0 and now >= v.absorbUntil then
			Combat.setAbsorption(entity, 0)
		end

		local eating = v.eating
		if eating then
			local stack = stackAt(player, eating.ref)
			if not stack or stack.id ~= eating.id then
				stopEating(player, v)
			elseif now >= eating.finishAt then
				finishEating(player, v, entity, root)
			end
		end
	end
end

local function onUse(player: Player, active: any)
	local v = vitals[player]
	if not v or not RateLimit.allow(player, "use", 10) then
		return
	end
	if active ~= true then
		stopEating(player, v)
		return
	end
	local root = Combat.rootOf(player)
	if v.eating or not root then
		return
	end
	local ref, stack = edible(player, v)
	if stack then
		v.eating = { ref = ref, id = stack.id, finishAt = os.clock() + Config.EAT_SECONDS }
		player:SetAttribute("Eating", stack.id)
		Sounds.play("eat", root)
	end
end

-- Called whenever the player's character spawns: a fresh hunger bar.
function Survival.reset(player: Player)
	vitals[player] = {
		food = MAX_FOOD,
		saturation = 5,
		timer = 0,
		eating = nil,
		regenUntil = 0,
		nextRegenAt = 0,
		absorbUntil = 0,
		lastPosition = nil,
	}
	player:SetAttribute("Food", MAX_FOOD)
	player:SetAttribute("Eating", nil)
end

function Survival.remove(player: Player)
	vitals[player] = nil
end

function Survival.init()
	Remotes.Use.OnServerEvent:Connect(onUse)
	RunService.Heartbeat:Connect(step)
end

return Survival
