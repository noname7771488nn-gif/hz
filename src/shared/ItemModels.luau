-- Builds small 3D models for items. Used for held items, dropped items and inventory icons.
local Blocks = require(script.Parent.Blocks)
local Items = require(script.Parent.Items)

local ItemModels = {}

local HANDLE = Color3.fromRGB(104, 76, 44)

local function newPart(parent: Instance, size: Vector3, color: Color3, cframe: CFrame): Part
	local part = Instance.new("Part")
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.CFrame = cframe
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local ARMOR_SIZES = {
	head = Vector3.new(1, 0.6, 1),
	chest = Vector3.new(1, 1, 0.55),
	legs = Vector3.new(0.9, 1, 0.5),
	feet = Vector3.new(0.9, 0.4, 0.6),
}

-- Returns a Model whose PrimaryPart is the grip point. All parts are unanchored, massless and welded.
function ItemModels.build(key: string, scale: number?): Model
	local s = scale or 1
	local def = Items.get(key)
	local model = Instance.new("Model")
	model.Name = key

	local primary: Part
	if not def then
		primary = newPart(model, Vector3.one * 0.5 * s, Color3.new(1, 0, 1), CFrame.identity)
	elseif def.kind == "block" then
		primary = newPart(model, Vector3.one * s, def.color, CFrame.identity)
		local blockDef = def.block and Blocks.byKey[def.block]
		if blockDef then
			Blocks.applyAppearance(primary, blockDef)
		end
	elseif def.kind == "sword" then
		primary = newPart(model, Vector3.new(0.16, 0.5, 0.16) * s, HANDLE, CFrame.identity)
		newPart(model, Vector3.new(0.2, 0.12, 0.7) * s, def.color:Lerp(Color3.new(0, 0, 0), 0.35), CFrame.new(0, 0.3 * s, 0))
		local blade = newPart(model, Vector3.new(0.12, 1.5, 0.32) * s, def.color, CFrame.new(0, 1.11 * s, 0))
		blade.Reflectance = 0.15
	elseif def.kind == "armor" then
		primary = newPart(model, (ARMOR_SIZES[def.slot or "chest"] or Vector3.one) * s, def.color, CFrame.identity)
		primary.Reflectance = 0.15
	else
		local rotation = if key == "diamond" then CFrame.Angles(0, math.rad(45), math.rad(45)) else CFrame.identity
		primary = newPart(model, Vector3.one * 0.5 * s, def.color, rotation)
	end

	model.PrimaryPart = primary
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and child ~= primary then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = primary
			weld.Part1 = child
			weld.Parent = child
		end
	end
	return model
end

return ItemModels
