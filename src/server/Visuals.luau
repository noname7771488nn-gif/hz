-- Server-built visuals everyone can see: worn armor and the held item.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared.Items)
local ItemModels = require(Shared.ItemModels)

local Inventory = require(script.Parent.Inventory)

local Visuals = {}

local TAG = "BlockCraftVisual"

-- { part name, fraction of the part's height to cover, "top" | "bottom" | "full" | "head" }
local R6_ARMOR = {
	head = { { "Head", 1, "head" } },
	chest = { { "Torso", 1, "full" }, { "Left Arm", 0.5, "top" }, { "Right Arm", 0.5, "top" } },
	legs = { { "Left Leg", 0.7, "top" }, { "Right Leg", 0.7, "top" } },
	feet = { { "Left Leg", 0.3, "bottom" }, { "Right Leg", 0.3, "bottom" } },
}
local R15_ARMOR = {
	head = { { "Head", 1, "head" } },
	chest = { { "UpperTorso", 1, "full" }, { "LeftUpperArm", 1, "full" }, { "RightUpperArm", 1, "full" } },
	legs = {
		{ "LowerTorso", 1, "full" },
		{ "LeftUpperLeg", 1, "full" },
		{ "RightUpperLeg", 1, "full" },
		{ "LeftLowerLeg", 0.6, "top" },
		{ "RightLowerLeg", 0.6, "top" },
	},
	feet = {
		{ "LeftFoot", 1, "full" },
		{ "RightFoot", 1, "full" },
		{ "LeftLowerLeg", 0.4, "bottom" },
		{ "RightLowerLeg", 0.4, "bottom" },
	},
}

local signatures: { [Player]: string } = {}

local function shell(character: Model, bodyPart: BasePart, fraction: number, anchor: string, color: Color3)
	local size, offset
	if anchor == "head" then
		size = Vector3.one * 1.35
		offset = CFrame.identity
	else
		local height = bodyPart.Size.Y * fraction
		size = Vector3.new(bodyPart.Size.X + 0.16, height + 0.08, bodyPart.Size.Z + 0.16)
		local shift = (bodyPart.Size.Y - height) / 2
		offset = CFrame.new(0, if anchor == "top" then shift elseif anchor == "bottom" then -shift else 0, 0)
	end
	local part = Instance.new("Part")
	part.Name = TAG
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Reflectance = 0.12
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CFrame = bodyPart.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = bodyPart
	weld.Part1 = part
	weld.Parent = part
	part.Parent = character
end

local function attachHeldItem(character: Model, key: string)
	local hand = (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")) :: any
	local def = Items.get(key)
	if not hand or not def then
		return
	end
	local model = ItemModels.build(key, if def.kind == "block" then 0.8 else 1)
	model.Name = TAG
	local grip = if hand.Name == "Right Arm" then hand.CFrame * CFrame.new(0, -1, -0.35) else hand.CFrame * CFrame.new(0, -0.15, -0.3)
	local tilt = if def.kind == "sword" then CFrame.Angles(math.rad(-70), 0, 0) else CFrame.identity
	model:PivotTo(grip * tilt)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hand
	weld.Part1 = model.PrimaryPart
	weld.Parent = model
	model.Parent = character
end

function Visuals.refresh(player: Player, force: boolean?)
	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then
		return
	end
	local selected = Inventory.selected(player)
	local armor = Inventory.armorIds(player)
	local signature = `{selected and selected.id or ""}|{armor.head or ""}|{armor.chest or ""}|{armor.legs or ""}|{armor.feet or ""}`
	if not force and signatures[player] == signature then
		return
	end
	signatures[player] = signature

	for _, child in character:GetChildren() do
		if child.Name == TAG then
			child:Destroy()
		end
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local layout = if humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 then R15_ARMOR else R6_ARMOR
	for slot, key in armor do
		local def = Items.get(key)
		for _, entry in layout[slot] or {} do
			local bodyPart = character:FindFirstChild(entry[1])
			if def and bodyPart and bodyPart:IsA("BasePart") then
				shell(character, bodyPart, entry[2], entry[3], def.color)
			end
		end
	end
	if selected then
		attachHeldItem(character, selected.id)
	end
end

function Visuals.release(player: Player)
	signatures[player] = nil
end

return Visuals
