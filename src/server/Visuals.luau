-- Server-built visuals everyone can see: worn armor, the held item, name tags and blocky avatars.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
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
		size = Vector3.one * 1.4
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
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
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
	local grip = if hand.Name == "Right Arm" then hand.CFrame * CFrame.new(0, -0.95, -0.15) else hand.CFrame * CFrame.new(0, -0.15, -0.2)
	if def.kind == "block" then
		model:PivotTo(grip * CFrame.new(0, -0.2, -0.3))
	else
		-- Stand the sprite in the character's forward/up plane so a sword points ahead and up.
		model:PivotTo(grip * CFrame.Angles(0, math.rad(90), 0))
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hand
	weld.Part1 = model.PrimaryPart
	weld.Parent = model
	model.Parent = character
end

-- Rebuilds a character's armor shells and held item. Works for players and NPCs.
function Visuals.apply(character: Model, armor: { [string]: string }, heldKey: string?)
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
	if heldKey then
		attachHeldItem(character, heldKey)
	end
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
	Visuals.apply(character, armor, selected and selected.id)
end

-- Minecraft-style name tag with the health underneath.
function Visuals.nameTag(character: Model, name: string, color: Color3?)
	local head = character:WaitForChild("Head", 5)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not head or not humanoid or head:FindFirstChild("NameTag") then
		return
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "NameTag"
	billboard.Size = UDim2.fromScale(7, 1.5)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 1.9, 0)
	billboard.MaxDistance = 90
	billboard.LightInfluence = 0

	local function line(order: number, text: string, textColor: Color3): TextLabel
		local label = Instance.new("TextLabel")
		label.LayoutOrder = order
		label.Size = UDim2.fromScale(1, 0.5)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.Arcade
		label.TextScaled = true
		label.Text = text
		label.TextColor3 = textColor
		label.TextStrokeTransparency = 0.3
		label.Parent = billboard
		return label
	end
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = billboard

	line(1, name, color or Color3.new(1, 1, 1))
	local health = line(2, "", Color3.fromRGB(255, 85, 85))
	local function update()
		health.Text = `{math.ceil(humanoid.Health)} HP`
	end
	humanoid.HealthChanged:Connect(update)
	update()
	billboard.Parent = head
end

-- Square head and no body-shape packages, so avatars read as blocky characters.
function Visuals.blockify(character: Model)
	if not Config.BLOCKY_AVATARS then
		return
	end
	for _, child in character:GetChildren() do
		if child:IsA("CharacterMesh") then
			child:Destroy()
		end
	end
	local head = character:FindFirstChild("Head")
	local mesh = head and head:FindFirstChildOfClass("SpecialMesh")
	if mesh then
		mesh.MeshType = Enum.MeshType.Brick
		mesh.Scale = Vector3.new(0.625, 1.25, 1.25) -- the head part is 2x1x1; this makes a 1.25 cube
	end
end

function Visuals.release(player: Player)
	signatures[player] = nil
end

return Visuals
