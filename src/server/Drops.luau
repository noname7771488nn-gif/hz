-- Item entities on the ground: block drops, thrown items and loot from dead players.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Items = require(Shared.Items)
local ItemModels = require(Shared.ItemModels)
local Sounds = require(Shared.Sounds)

local Inventory = require(script.Parent.Inventory)

local Drops = {}

local PICKUP_RADIUS = 5

type DropInfo = { stack: Items.Stack, pickupAt: number, despawnAt: number }

local folder = Instance.new("Folder")
folder.Name = "Drops"
folder.Parent = workspace

local active: { [BasePart]: DropInfo } = {}

function Drops.spawn(stack: Items.Stack, position: Vector3, velocity: Vector3?, pickupDelay: number?): BasePart?
	if not Items.get(stack.id) or stack.count < 1 then
		return nil
	end
	local root = Instance.new("Part")
	root.Name = "Drop"
	root.Size = Vector3.one * 0.8
	root.Transparency = 1
	root.CanQuery = false
	root.CanTouch = false
	root.CustomPhysicalProperties = PhysicalProperties.new(2, 1, 0, 1, 1)
	root.CFrame = CFrame.new(position) * CFrame.Angles(0, math.random() * math.pi * 2, 0)

	local model = ItemModels.build(stack.id, 0.6)
	model:PivotTo(root.CFrame)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = model.PrimaryPart
	weld.Parent = root
	model.Parent = root

	root.Parent = folder
	root:SetNetworkOwner(nil)
	root.AssemblyLinearVelocity = velocity or Vector3.new((math.random() - 0.5) * 6, 10, (math.random() - 0.5) * 6)

	local now = os.clock()
	active[root] = { stack = Items.copy(stack), pickupAt = now + (pickupDelay or 0.5), despawnAt = now + Config.ITEM_DESPAWN }
	return root
end

-- Spills stacks around a point, like a player's inventory on death.
function Drops.scatter(stacks: { Items.Stack }, position: Vector3)
	for _, stack in stacks do
		local angle = math.random() * math.pi * 2
		local speed = 4 + math.random() * 6
		Drops.spawn(stack, position + Vector3.new(0, 1, 0), Vector3.new(math.cos(angle) * speed, 12, math.sin(angle) * speed), 1)
	end
end

local elapsed = 0
RunService.Heartbeat:Connect(function(dt)
	elapsed += dt
	if elapsed < 0.1 then
		return
	end
	elapsed = 0

	local collectors = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if humanoid and root and humanoid.Health > 0 then
			table.insert(collectors, { player = player, position = root.Position })
		end
	end

	local now = os.clock()
	for drop, info in active do
		if not drop.Parent then
			active[drop] = nil
			continue
		end
		if now >= info.despawnAt or drop.Position.Y < -60 then
			drop:Destroy()
			active[drop] = nil
			continue
		end
		if now < info.pickupAt then
			continue
		end
		for _, collector in collectors do
			if (collector.position - drop.Position).Magnitude > PICKUP_RADIUS then
				continue
			end
			local left = Inventory.add(collector.player, info.stack)
			if left < info.stack.count then
				Sounds.play("pickup", collector.position, 0.3)
				if left == 0 then
					drop:Destroy()
					active[drop] = nil
					break
				end
				info.stack.count = left
			end
		end
	end
end)

return Drops
