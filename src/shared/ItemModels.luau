-- Builds 3D models for items: textured cubes for blocks and extruded pixel sprites for everything
-- else, like Minecraft's held and dropped items.
local Blocks = require(script.Parent.Blocks)
local Items = require(script.Parent.Items)
local PixelArt = require(script.Parent.PixelArt)

local ItemModels = {}

-- Sprite pixel the hand holds, for items that aren't gripped at their centre.
local GRIPS = {
	sword = { x = 3.5, y = 12.5 },
}

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

function ItemModels.isSprite(key: string): boolean
	local def = Items.get(key)
	return def ~= nil and def.kind ~= "block"
end

-- Returns a Model whose PrimaryPart is the grip point. Sprites lie in the PrimaryPart's XY plane
-- (+X toward the sprite's right, +Y up). All parts are unanchored, massless and welded.
function ItemModels.build(key: string, scale: number?): Model
	local s = scale or 1
	local def = Items.get(key)
	local model = Instance.new("Model")
	model.Name = key

	local primary: Part
	local image = if def and def.kind ~= "block" then PixelArt.get(key) else nil
	if def and def.kind == "block" then
		primary = newPart(model, Vector3.one * s, def.color, CFrame.identity)
		local blockDef = def.block and Blocks.byKey[def.block]
		if blockDef then
			Blocks.applyAppearance(primary, blockDef, Blocks.ALL_FACES, true)
		end
	elseif def and image then
		local unit = (if def.kind == "sword" then 1.8 else 1.2) * s / image.width
		local grip = GRIPS[def.kind] or { x = image.width / 2, y = image.height / 2 }
		primary = newPart(model, Vector3.one * unit, def.color, CFrame.identity)
		primary.Transparency = 1
		for _, run in PixelArt.runs(image) do
			local x = (run.x + run.w / 2 - grip.x) * unit
			local y = (grip.y - run.y - 0.5) * unit
			newPart(model, Vector3.new(run.w * unit, unit, unit), Color3.fromRGB(run.r, run.g, run.b), CFrame.new(x, y, 0))
		end
	else
		primary = newPart(model, Vector3.one * 0.5 * s, if def then def.color else Color3.new(1, 0, 1), CFrame.identity)
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
