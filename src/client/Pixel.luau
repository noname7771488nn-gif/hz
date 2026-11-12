-- Turns the generated pixel art (Shared.PixelArt) into things Roblox can draw:
--   * block-face textures for the world, held blocks and NPC faces, via EditableImage
--   * item and HUD sprites built from UI frames, which need no special permissions
-- EditableImage needs "Allow Mesh / Image APIs" switched on for a published game. Without it the
-- world falls back to flat block colours and block icons to coloured squares.
local AssetService = game:GetService("AssetService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Blocks = require(Shared.Blocks)
local Items = require(Shared.Items)
local PixelArt = require(Shared.PixelArt)

local Pixel = {}

local WORLD_TEXTURE_SIZE = 128 -- upscaled so bilinear filtering keeps the pixels crisp
local ENCHANT_TINT = Color3.fromRGB(190, 120, 255)

local available: boolean? = nil -- nil until the first attempt
local contents: { [string]: Content | false } = {}
Pixel.images = {} -- EditableImages must stay referenced while displayed

local function makeContent(image: PixelArt.Image, minimumSize: number): Content?
	if available == false then
		return nil
	end
	local factor = math.max(1, math.ceil(minimumSize / image.width))
	local scaled = if factor > 1 then PixelArt.scaled(image, factor) else image
	local size = Vector2.new(scaled.width, scaled.height)
	local ok, result = pcall(function()
		local editable = AssetService:CreateEditableImage({ Size = size })
		if editable then
			editable:WritePixelsBuffer(Vector2.zero, size, scaled.pixels)
		end
		return editable
	end)
	if not ok or not result then
		if available == nil then
			available = false
			warn(
				"[BlockCraft] Pixel textures are unavailable, using flat colours instead. "
					.. 'Enable "Allow Mesh / Image APIs" in Game Settings > Security. Reason:',
				result
			)
		end
		return nil
	end
	available = true
	table.insert(Pixel.images, result)
	return Content.fromObject(result)
end

local function cached(cacheKey: string, build: () -> Content?): Content?
	local existing = contents[cacheKey]
	if existing == nil then
		existing = build() or false
		contents[cacheKey] = existing
	end
	return existing or nil
end

-- Content for a block-face (or other world) texture key.
function Pixel.texture(key: string): Content?
	return cached("t:" .. key, function()
		local image = PixelArt.get(key)
		return image and makeContent(image, WORLD_TEXTURE_SIZE)
	end)
end

local function blockIcon(def: Blocks.BlockDef): Content?
	local top, side = Blocks.textureKey(def, 3), Blocks.textureKey(def, 1)
	return cached(`i:{top}|{side}`, function()
		return makeContent(PixelArt.blockIcon(top, side), 1)
	end)
end

local function applyTexture(instance: Instance)
	if instance:IsA("Decal") and not Config.Textures[instance.Name] then
		local content = Pixel.texture(instance.Name)
		if content then
			instance.TextureContent = content
		end
	end
end

local function watchFolder(folder: Instance)
	folder.DescendantAdded:Connect(applyTexture)
	for _, descendant in folder:GetDescendants() do
		applyTexture(descendant)
	end
end

-- Sprites --------------------------------------------------------------------------------------------

local spriteTemplates: { [string]: Frame } = {}

-- A frame that draws the sprite `key` out of one child frame per run of pixels. Size it to a
-- multiple of the sprite's size in pixels so the runs land on whole pixels.
function Pixel.sprite(key: string): Frame
	local template = spriteTemplates[key]
	if not template then
		template = Instance.new("Frame")
		template.BackgroundTransparency = 1
		template.BorderSizePixel = 0
		template.Size = UDim2.fromScale(1, 1)
		local image = PixelArt.get(key)
		if image then
			for _, run in PixelArt.runs(image) do
				local frame = Instance.new("Frame")
				frame.BorderSizePixel = 0
				frame.BackgroundColor3 = Color3.fromRGB(run.r, run.g, run.b)
				frame.Position = UDim2.fromScale(run.x / image.width, run.y / image.height)
				frame.Size = UDim2.fromScale(run.w / image.width, 1 / image.height)
				frame.Parent = template
			end
		end
		spriteTemplates[key] = template
	end
	return template:Clone()
end

-- Shows the icon for an item inside `holder`, replacing any previous icon. nil clears it.
function Pixel.setIcon(holder: GuiObject, itemKey: string?, enchanted: boolean?)
	local previous = holder:FindFirstChild("Icon")
	if previous then
		previous:Destroy()
	end
	local def = Items.get(itemKey)
	if not itemKey or not def then
		return
	end

	local icon: GuiObject
	local blockDef = def.block and Blocks.byKey[def.block]
	if blockDef then
		local content = blockIcon(blockDef)
		if content then
			local image = Instance.new("ImageLabel")
			image.BackgroundTransparency = 1
			image.ImageContent = content
			image.ResampleMode = Enum.ResamplerMode.Pixelated
			image.Size = UDim2.fromScale(1, 1)
			icon = image
		else
			-- No image available: a simple three-tone cube in the block's colour.
			local cube = Instance.new("Frame")
			cube.BackgroundTransparency = 1
			cube.Size = UDim2.fromScale(1, 1)
			local faces = {
				{ 2, 2, 12, 5, blockDef.color:Lerp(Color3.new(1, 1, 1), 0.25) },
				{ 2, 7, 6, 7, blockDef.color:Lerp(Color3.new(0, 0, 0), 0.15) },
				{ 8, 7, 6, 7, blockDef.color:Lerp(Color3.new(0, 0, 0), 0.4) },
			}
			for _, face in faces :: { any } do
				local frame = Instance.new("Frame")
				frame.BorderSizePixel = 0
				frame.BackgroundColor3 = face[5]
				frame.Position = UDim2.fromScale(face[1] / 16, face[2] / 16)
				frame.Size = UDim2.fromScale(face[3] / 16, face[4] / 16)
				frame.Parent = cube
			end
			icon = cube
		end
	else
		icon = Pixel.sprite(itemKey)
		if enchanted then
			for _, pixel in icon:GetChildren() do
				if pixel:IsA("Frame") then
					pixel.BackgroundColor3 = pixel.BackgroundColor3:Lerp(ENCHANT_TINT, 0.3)
				end
			end
		end
	end
	icon.Name = "Icon"
	icon.Parent = holder
end

function Pixel.init()
	task.spawn(function()
		watchFolder(workspace:WaitForChild("Blocks"))
	end)
	task.spawn(function()
		watchFolder(workspace:WaitForChild("Arena"))
	end)
	CollectionService:GetInstanceAddedSignal(Blocks.PIXEL_TAG):Connect(applyTexture)
	for _, instance in CollectionService:GetTagged(Blocks.PIXEL_TAG) do
		applyTexture(instance)
	end
end

return Pixel
