-- The PvP warp's bot: a blocky NPC that fights by the same 1.21.1 rules as players.
-- It goes for whoever wears the best armor, but turns on anyone who hits it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Blocks = require(Shared.Blocks)
local Items = require(Shared.Items)
local Remotes = require(Shared.Remotes)
local Sounds = require(Shared.Sounds)
local Zones = require(Shared.Zones)

local Combat = require(script.Parent.Combat)
local Drops = require(script.Parent.Drops)
local Messages = require(script.Parent.Messages)
local Structures = require(script.Parent.Structures)
local Visuals = require(script.Parent.Visuals)

local Bot = {}

local B = Config.BLOCK_SIZE
local ARENA = Config.ARENA
local SETTINGS = Config.BOT
local REACH = Config.ATTACK_REACH * B + 0.5 -- root to root, about what a player's crosshair reaches
local HEAL_AT = 7
local HEAL_AMOUNT = 8
local EAT_SECONDS = 1.6

local rng = Random.new()

type Brain = {
	target: Combat.Entity?,
	retargetAt: number,
	strafeDir: number,
	strafeFlipAt: number,
	sprintSince: number?,
	inReachSince: number?,
	lastLandedAt: number,
	critPlan: boolean,
	jumpedAt: number?,
	eatingUntil: number?,
	apples: number,
	wanderTo: Vector3?,
	wanderAt: number,
	stuckAt: number,
	stuckPosition: Vector3,
}

local entity: Combat.Entity
local model: Model? = nil
local root: BasePart? = nil
local align: AlignOrientation? = nil
local brain: Brain

local weapon: Items.Stack? = nil
local armorIds: { [string]: string } = {}
local armor, toughness, protection = 0, 0, 0
local attackSpeed = Items.FIST.attackSpeed

local arenaParams = RaycastParams.new()
arenaParams.FilterType = Enum.RaycastFilterType.Include

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Rig ------------------------------------------------------------------------------------------------

local function limb(parent: Model, name: string, size: Vector3, color: Color3, offset: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = false
	part.CFrame = CFrame.new(offset)
	part.Parent = parent
	return part
end

local function joint(name: string, part0: BasePart, part1: BasePart, c0: CFrame, c1: CFrame)
	local motor = Instance.new("Motor6D")
	motor.Name = name
	motor.Part0 = part0
	motor.Part1 = part1
	motor.C0 = c0
	motor.C1 = c1
	motor.Parent = part0
end

-- A plain-block R6 character. Joints use unrotated frames, so the client animates it itself
-- (Effects module) instead of using Roblox's stock animations.
local function buildRig(): (Model, Humanoid, BasePart)
	local skin = Color3.fromRGB(198, 150, 108)
	local shirt = Color3.fromRGB(46, 52, 64)
	local trousers = Color3.fromRGB(32, 34, 48)

	local rig = Instance.new("Model")
	rig.Name = SETTINGS.name
	local hrp = limb(rig, "HumanoidRootPart", Vector3.new(2, 2, 1), shirt, Vector3.zero)
	hrp.Transparency = 1
	local torso = limb(rig, "Torso", Vector3.new(2, 2, 1), shirt, Vector3.zero)
	local head = limb(rig, "Head", Vector3.new(1.2, 1.2, 1.2), skin, Vector3.new(0, 1.6, 0))
	local rightArm = limb(rig, "Right Arm", Vector3.new(1, 2, 1), skin, Vector3.new(1.5, 0, 0))
	local leftArm = limb(rig, "Left Arm", Vector3.new(1, 2, 1), skin, Vector3.new(-1.5, 0, 0))
	local rightLeg = limb(rig, "Right Leg", Vector3.new(1, 2, 1), trousers, Vector3.new(0.5, -2, 0))
	local leftLeg = limb(rig, "Left Leg", Vector3.new(1, 2, 1), trousers, Vector3.new(-0.5, -2, 0))
	torso.CanCollide = true
	head.CanCollide = true

	joint("RootJoint", hrp, torso, CFrame.identity, CFrame.identity)
	joint("Neck", torso, head, CFrame.new(0, 1, 0), CFrame.new(0, -0.6, 0))
	joint("Right Shoulder", torso, rightArm, CFrame.new(1, 0.5, 0), CFrame.new(-0.5, 0.5, 0))
	joint("Left Shoulder", torso, leftArm, CFrame.new(-1, 0.5, 0), CFrame.new(0.5, 0.5, 0))
	joint("Right Hip", torso, rightLeg, CFrame.new(0.5, -1, 0), CFrame.new(0, 1, 0))
	joint("Left Hip", torso, leftLeg, CFrame.new(-0.5, -1, 0), CFrame.new(0, 1, 0))

	local face = Instance.new("Decal")
	face.Name = "bot_face"
	face.Face = Enum.NormalId.Front
	face:AddTag(Blocks.PIXEL_TAG)
	face.Parent = head

	local hum = Instance.new("Humanoid")
	hum.RigType = Enum.HumanoidRigType.R6
	hum.UseJumpPower = false
	hum.JumpHeight = Config.JUMP_HEIGHT
	hum.WalkSpeed = Config.WALK_SPEED
	hum.AutoRotate = false
	hum.BreakJointsOnDeath = false
	hum.Parent = rig

	rig.PrimaryPart = hrp
	rig:SetAttribute("BlockRig", true)
	rig:AddTag("PvPBot")
	return rig, hum, hrp
end

local function loadGear()
	local kit = Config.Kits[SETTINGS.kit]
	if not kit then
		return
	end
	for _, item in kit.items do
		local def = Items.get(item.id)
		if def and def.kind == "armor" and def.slot then
			armorIds[def.slot] = def.key
			armor += def.armor or 0
			toughness += def.toughness or 0
			protection += if item.ench then item.ench.protection or 0 else 0
		elseif def and def.kind == "sword" then
			weapon = { id = def.key, count = 1, ench = if item.ench then table.clone(item.ench) else nil }
			attackSpeed = def.attackSpeed or attackSpeed
		end
	end
end

-- Targeting ------------------------------------------------------------------------------------------

local function validTarget(candidate: Combat.Entity?): boolean
	local _, candidateRoot = Combat.alive(candidate)
	return candidateRoot ~= nil and Zones.zoneAt(candidateRoot.Position) == "arena"
end

local function armorScore(candidate: Combat.Entity): number
	local points, tough, prot = candidate.armorStats()
	return points + tough * 0.5 + prot
end

local function chooseTarget(now: number, position: Vector3): Combat.Entity?
	-- Whoever hit us last comes first.
	local attacker = entity.lastAttacker
	if attacker and now - entity.lastAttackerAt < SETTINGS.retaliateSeconds and validTarget(attacker) then
		return attacker
	end
	local best: Combat.Entity? = nil
	local bestScore, bestDistance = -1, math.huge
	for _, candidate in Combat.players() do
		if not validTarget(candidate) then
			continue
		end
		local score = armorScore(candidate)
		if score <= 0 and SETTINGS.ignoreUnarmored then
			continue
		end
		local distance = ((candidate.root :: BasePart).Position - position).Magnitude
		if score > bestScore + 0.01 or (math.abs(score - bestScore) <= 0.01 and distance < bestDistance) then
			best, bestScore, bestDistance = candidate, score, distance
		end
	end
	return best
end

-- Movement -------------------------------------------------------------------------------------------

local function blocked(origin: Vector3, direction: Vector3, distance: number): boolean
	return workspace:Raycast(origin, direction * distance, arenaParams) ~= nil
end

-- Turns a wanted direction into one that hops one-block steps and slides around walls.
local function steer(position: Vector3, wanted: Vector3): (Vector3, boolean)
	if wanted.Magnitude < 0.05 then
		return Vector3.zero, false
	end
	local dir = wanted.Unit
	local shin = position - Vector3.new(0, 2, 0)
	local chest = position + Vector3.new(0, 1.5, 0)
	if not blocked(shin, dir, 3.5) then
		return dir, false
	end
	if not blocked(chest, dir, 4.5) then
		return dir, true
	end
	local side = Vector3.new(-dir.Z, 0, dir.X) * brain.strafeDir
	if blocked(shin, side, 3.5) then
		brain.strafeDir = -brain.strafeDir
		side = -side
	end
	return (side + dir * 0.2).Unit, false
end

local function face(direction: Vector3)
	if align and direction.Magnitude > 0.05 then
		align.CFrame = CFrame.lookAt(Vector3.zero, direction)
	end
end

local function drive(hum: Humanoid, position: Vector3, wanted: Vector3, speed: number, now: number)
	local direction, hop = steer(position, wanted)
	hum.WalkSpeed = speed
	hum:Move(direction)
	local grounded = hum.FloorMaterial ~= Enum.Material.Air
	if hop and grounded then
		hum.Jump = true
	end
	-- Unstick: if we wanted to move for a second and went nowhere, hop and change sides.
	if now - brain.stuckAt >= 1 then
		if direction.Magnitude > 0 and (position - brain.stuckPosition).Magnitude < 1 and grounded then
			hum.Jump = true
			brain.strafeDir = -brain.strafeDir
		end
		brain.stuckAt = now
		brain.stuckPosition = position
	end
end

local function wander(hum: Humanoid, position: Vector3, now: number)
	if not brain.wanderTo or now >= brain.wanderAt then
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(3, 9) * B
		brain.wanderTo = Vector3.new(ARENA.centerX * B + math.cos(angle) * distance, position.Y, ARENA.centerZ * B + math.sin(angle) * distance)
		brain.wanderAt = now + rng:NextNumber(3, 6)
	end
	local to = flat((brain.wanderTo :: Vector3) - position)
	if to.Magnitude < 2 then
		hum:Move(Vector3.zero)
		return
	end
	face(to)
	drive(hum, position, to, Config.WALK_SPEED * 0.6, now)
end

-- Fighting -------------------------------------------------------------------------------------------

local function swing(target: Combat.Entity, sprintHit: boolean, now: number)
	local landed = Combat.attack(entity, target, sprintHit)
	if model and root then
		Remotes.SwingFx:FireAllClients(model)
		Sounds.play("swing", root, 0.4)
	end
	if landed then
		brain.lastLandedAt = now
	end
	-- Letting go of sprint after each hit ("W-tapping") makes the next hit a sprint hit again.
	brain.sprintSince = nil
	brain.jumpedAt = nil
	brain.critPlan = rng:NextNumber() < SETTINGS.critChance
end

local function fight(hum: Humanoid, self: BasePart, target: Combat.Entity, now: number)
	local targetRoot = target.root :: BasePart
	local position = self.Position
	local offset = targetRoot.Position - position
	local toTarget = flat(offset)
	local distance = toTarget.Magnitude
	local dir = if distance > 0.05 then toTarget.Unit else self.CFrame.LookVector
	local side = Vector3.new(-dir.Z, 0, dir.X)
	face(dir)

	if now >= brain.strafeFlipAt then
		brain.strafeDir = -brain.strafeDir
		brain.strafeFlipAt = now + rng:NextNumber(0.5, 1.3)
	end

	-- Low on health: back off and heal, once or twice a life.
	if brain.eatingUntil then
		if now < brain.eatingUntil then
			drive(hum, position, -dir + side * (0.7 * brain.strafeDir), Config.SPRINT_SPEED, now)
			return
		end
		brain.eatingUntil = nil
		hum.Health = math.min(hum.MaxHealth, hum.Health + HEAL_AMOUNT)
		Sounds.play("pickup", self, 0.5)
	elseif hum.Health <= HEAL_AT and brain.apples > 0 then
		brain.apples -= 1
		brain.eatingUntil = now + EAT_SECONDS
		return
	end

	local grounded = hum.FloorMaterial ~= Enum.Material.Air
	local vy = self.AssemblyLinearVelocity.Y
	local timeToReady = math.max(0, 1 / attackSpeed - (now - entity.lastAttack))
	if brain.jumpedAt and grounded and now - brain.jumpedAt > 0.8 then
		brain.jumpedAt = nil -- that jump is over; allow another
	end
	local inReach = offset.Magnitude <= REACH
	if inReach then
		brain.inReachSince = brain.inReachSince or now
	else
		brain.inReachSince = nil
	end
	-- Open with a sprint hit for the knockback, then chain critical hits.
	local opener = now - brain.lastLandedAt > 2.5
	local wantCrit = brain.critPlan and not opener

	local wanted: Vector3
	local speed = Config.SPRINT_SPEED
	if distance > REACH + 6 then
		wanted = dir
	elseif timeToReady > 0.3 then
		-- Weapon recharging: circle the target. Stay on them after landing a hit, otherwise
		-- hold just outside their reach so their swings miss.
		local keep = if now - brain.lastLandedAt < 1.2 then REACH + 0.5 else REACH + 2.5
		wanted = dir * (if distance < keep then -1 else 0.3) + side * brain.strafeDir
		speed = Config.WALK_SPEED
	else
		wanted = dir + side * (0.3 * brain.strafeDir)
	end
	if speed == Config.SPRINT_SPEED then
		brain.sprintSince = brain.sprintSince or now
	else
		brain.sprintSince = nil
	end
	drive(hum, position, wanted, speed, now)

	-- Time a jump so the weapon is recharged just as we start to fall onto the target.
	if wantCrit and grounded and not brain.jumpedAt and timeToReady <= 0.3 and distance <= REACH + 4 then
		hum.Jump = true
		brain.jumpedAt = now
	end

	if timeToReady > 0 or not inReach or now - (brain.inReachSince :: number) < SETTINGS.reactionTime then
		return
	end
	if offset.Magnitude > 0.5 and blocked(position, offset.Unit, offset.Magnitude) then
		return -- no line of sight
	end
	local falling = not grounded and vy < -1
	-- If the crit never lines up, swing anyway rather than hold the hit forever.
	local gaveUp = not grounded and brain.jumpedAt ~= nil and now - brain.jumpedAt > 0.7
	if falling or gaveUp then
		swing(target, false, now)
	elseif grounded and not (wantCrit and brain.jumpedAt and now - brain.jumpedAt < 0.2) then
		local sprintHit = brain.sprintSince ~= nil and now - brain.sprintSince > 0.15
		swing(target, sprintHit, now)
	end
end

local function think()
	local hum, self = Combat.alive(entity)
	if not hum or not self then
		return
	end
	local now = os.clock()
	if now >= brain.retargetAt then
		brain.retargetAt = now + 0.4
		brain.target = chooseTarget(now, self.Position)
	end
	local target = brain.target
	if target and validTarget(target) then
		fight(hum, self, target, now)
	else
		brain.target = nil
		brain.sprintSince = nil
		wander(hum, self.Position, now)
	end
end

-- Lifecycle ------------------------------------------------------------------------------------------

local function spawn()
	local rig, _, hrp = buildRig()
	rig:PivotTo(Structures.arenaFloorCFrame())

	local attachment = Instance.new("Attachment")
	attachment.Parent = hrp
	local orientation = Instance.new("AlignOrientation")
	orientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	orientation.Attachment0 = attachment
	orientation.MaxTorque = 1e7
	orientation.Responsiveness = 80
	orientation.CFrame = hrp.CFrame.Rotation
	orientation.Parent = hrp

	rig.Parent = workspace
	-- Keep the bot's physics on the server so no client can move it.
	for _, part in rig:GetChildren() do
		if part:IsA("BasePart") then
			part:SetNetworkOwner(nil)
		end
	end

	model, root, align = rig, hrp, orientation
	brain = {
		target = nil,
		retargetAt = 0,
		strafeDir = if rng:NextNumber() < 0.5 then -1 else 1,
		strafeFlipAt = 0,
		sprintSince = nil,
		inReachSince = nil,
		lastLandedAt = 0,
		critPlan = true,
		jumpedAt = nil,
		eatingUntil = nil,
		apples = SETTINGS.goldenApples,
		wanderTo = nil,
		wanderAt = 0,
		stuckAt = os.clock(),
		stuckPosition = hrp.Position,
	}
	Combat.bind(entity, rig)
	Visuals.apply(rig, armorIds, weapon and weapon.id)
	Visuals.nameTag(rig, SETTINGS.name, Color3.fromRGB(255, 85, 85))
end

local function onDeath(_: Combat.Entity, killer: Combat.Entity?)
	local body = model
	local position = if root then root.Position else nil
	model, root, align = nil, nil, nil

	if position then
		for _, item in SETTINGS.loot do
			Drops.spawn({ id = item.id, count = item.count }, position)
		end
	end
	if killer and killer.player then
		Messages.broadcast(`{killer.name} defeated the {SETTINGS.name}!`, "streak")
	end
	task.delay(1.2, function()
		if body then
			body:Destroy()
		end
	end)
	task.delay(SETTINGS.respawnSeconds, spawn)
end

function Bot.init()
	if not SETTINGS.enabled then
		return
	end
	loadGear()
	arenaParams.FilterDescendantsInstances = { workspace:WaitForChild("Arena") }
	entity = Combat.newEntity({
		name = SETTINGS.name,
		isBot = true,
		armorStats = function()
			return armor, toughness, protection
		end,
		weapon = function()
			return weapon
		end,
		knockback = function(push: Vector3)
			if root then
				root.AssemblyLinearVelocity = push
			end
		end,
		onDeath = onDeath,
	})
	spawn()
	RunService.Heartbeat:Connect(think)
end

return Bot
