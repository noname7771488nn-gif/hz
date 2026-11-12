-- Mining, placing, eating and attacking from the crosshair.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Blocks = require(Shared.Blocks)
local Items = require(Shared.Items)
local Remotes = require(Shared.Remotes)
local Zones = require(Shared.Zones)

local State = require(script.Parent.State)
local Hud = require(script.Parent.Hud)
local Effects = require(script.Parent.Effects)

local Interaction = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local blocksFolder = workspace:WaitForChild("Blocks")
local arenaFolder = workspace:WaitForChild("Arena")
local dropsFolder = workspace:WaitForChild("Drops")

local B = Config.BLOCK_SIZE
local BLOCK_REACH = Config.BLOCK_REACH * B + B / 2
local ATTACK_REACH = Config.ATTACK_REACH * B + 1.5
local PLACE_REPEAT = 0.2 -- 4-tick right-click delay
local SWING_INTERVAL = 0.25 -- arm swings while mining
local MINE_DELAY = 0.25 -- pause between consecutive blocks while holding the button
local PROTECTED_MESSAGE = "Hey! Sorry, but you can't change blocks here."

type Target = { kind: string, part: BasePart?, character: Model?, cell: Vector3?, normal: Vector3? }

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude

local selection = Instance.new("SelectionBox")
selection.Color3 = Color3.new(0, 0, 0)
selection.LineThickness = 0.03
selection.SurfaceColor3 = Color3.new(0, 0, 0)
selection.SurfaceTransparency = 1

local miningCell: Vector3? = nil
local miningProgress = 0
local miningCooldownUntil = 0
local lastSwingSent = 0
local leftDown = false
local rightDown = false
local nextPlaceAt = 0
local nextUseAt = 0
local eatingRequested = false

-- The player or NPC character a part belongs to.
local function characterFromPart(part: Instance): Model?
	local node = part.Parent
	while node and node ~= workspace do
		if node:IsA("Model") and node:FindFirstChildOfClass("Humanoid") then
			return node
		end
		node = node.Parent
	end
	return nil
end

local function eyePosition(): Vector3?
	local character = player.Character
	local head = character and character:FindFirstChild("Head") :: BasePart?
	return head and head.Position
end

local function getTarget(): Target?
	local character = player.Character
	local eye = eyePosition()
	if not character or not eye then
		return nil
	end
	params.FilterDescendantsInstances = { character, dropsFolder, camera }
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local result = workspace:Raycast(ray.Origin, ray.Direction * 60, params)
	if not result then
		return nil
	end
	local distance = (result.Position - eye).Magnitude
	local hit = result.Instance
	local other = characterFromPart(hit)
	if other then
		return if distance <= ATTACK_REACH then { kind = "character", character = other } else nil
	end
	if (hit.Parent == blocksFolder or hit.Parent == arenaFolder) and distance <= BLOCK_REACH then
		local cell = Vector3.new(math.round(hit.Position.X / B), math.round(hit.Position.Y / B), math.round(hit.Position.Z / B))
		local n = result.Normal
		return { kind = "block", part = hit :: BasePart, cell = cell, normal = Vector3.new(math.round(n.X), math.round(n.Y), math.round(n.Z)) }
	end
	return nil
end

local function canAct(): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0 and State.menu == nil and not State.dead
end

-- Swings the arm. A swing at thin air restarts the attack cooldown; swings while mining don't.
local function swing(missed: boolean)
	Effects.localSwing()
	if missed then
		State.resetCooldown()
	end
	if missed or os.clock() - lastSwingSent > 0.1 then
		lastSwingSent = os.clock()
		Remotes.Swing:FireServer(missed)
	end
end

local function stopMining()
	miningCell = nil
	miningProgress = 0
	selection.SurfaceTransparency = 1
end

local function primaryAction()
	local target = getTarget()
	if target and target.kind == "character" then
		-- The server works out the hit's strength from the cooldown, then restarts it.
		Effects.localSwing()
		Remotes.Attack:FireServer(target.character)
		State.resetCooldown()
	elseif not target then
		swing(true)
	end
	-- Blocks are handled by the mining loop while the button is held.
end

local function stopEating()
	if eatingRequested then
		eatingRequested = false
		Remotes.Use:FireServer(false)
	end
end

local function placeBlock()
	local stack = State.selectedStack()
	local def = stack and Items.get(stack.id)
	if not def or def.kind ~= "block" then
		return
	end
	local target = getTarget()
	if not target or target.kind ~= "block" or not target.cell or not target.normal then
		return
	end
	local cell = target.cell + target.normal
	if Zones.isProtected(cell.X, cell.Y, cell.Z) then
		Hud.actionBar(PROTECTED_MESSAGE)
		return
	end
	Effects.localSwing()
	Remotes.PlaceBlock:FireServer(cell.X, cell.Y, cell.Z)
end

-- Holding right-click eats the held food (or the offhand's), otherwise places blocks.
local function useItem(now: number)
	if State.edible() then
		if player:GetAttribute("Eating") == nil and now >= nextUseAt then
			nextUseAt = now + 0.3
			eatingRequested = true
			Remotes.Use:FireServer(true)
		end
	else
		stopEating()
		if now >= nextPlaceAt then
			nextPlaceAt = now + PLACE_REPEAT
			placeBlock()
		end
	end
end

local function update(dt: number)
	if not canAct() then
		selection.Adornee = nil
		stopMining()
		stopEating()
		return
	end
	local now = os.clock()
	local target = getTarget()
	local block = if target and target.kind == "block" then target else nil
	selection.Adornee = if block then block.part else nil

	if leftDown and block and block.cell and block.part and now >= miningCooldownUntil then
		local cell = block.cell
		if miningCell ~= cell then
			if Zones.isProtected(cell.X, cell.Y, cell.Z) then
				Hud.actionBar(PROTECTED_MESSAGE)
				miningCooldownUntil = now + 0.5
				stopMining()
				return
			end
			local def = Blocks.byKey[block.part.Name]
			if not def or def.hardness < 0 then
				stopMining()
				return
			end
			miningCell = cell
			miningProgress = 0
			Remotes.StartBreak:FireServer(cell.X, cell.Y, cell.Z)
		end
		local def = Blocks.byKey[block.part.Name]
		if def then
			miningProgress += dt / Blocks.breakTime(def)
			selection.SurfaceTransparency = 1 - math.min(miningProgress, 1) * 0.65
			if now - lastSwingSent > SWING_INTERVAL then
				swing(false)
			end
			if miningProgress >= 1 then
				Remotes.FinishBreak:FireServer(cell.X, cell.Y, cell.Z)
				stopMining()
				miningCooldownUntil = now + MINE_DELAY
			end
		end
	elseif miningCell then
		stopMining()
	end

	if rightDown then
		useItem(now)
	else
		stopEating()
	end
end

function Interaction.init()
	selection.Parent = player:WaitForChild("PlayerGui")

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not canAct() then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			leftDown = true
			primaryAction()
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			rightDown = true
			nextPlaceAt = 0
			nextUseAt = 0
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			leftDown = false
			stopMining()
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			rightDown = false
		end
	end)
	RunService.RenderStepped:Connect(update)
end

return Interaction
