local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local Config = require(script.Parent.Config)

local Sounds = {}

-- Config.Sounds entries are an asset id, or { id = ..., pitch = ..., volume = ... }.
local function make(name: string, volume: number?): Sound?
	local entry = Config.Sounds[name]
	local id = if type(entry) == "table" then entry.id else entry
	if not id or id == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = id
	sound.Volume = volume or (if type(entry) == "table" then entry.volume else nil) or 0.5
	sound.PlaybackSpeed = if type(entry) == "table" then entry.pitch or 1 else 1
	sound.RollOffMaxDistance = 60
	return sound
end

-- 3D sound at a position or on an instance. From the server everyone nearby hears it; from a
-- client only that player does.
function Sounds.play(name: string, where: Vector3 | Instance, volume: number?)
	local sound = make(name, volume)
	if not sound then
		return
	end
	if typeof(where) == "Vector3" then
		local attachment = Instance.new("Attachment")
		attachment.Position = where
		attachment.Parent = workspace.Terrain
		sound.Parent = attachment
		Debris:AddItem(attachment, 4)
	else
		sound.Parent = where
		Debris:AddItem(sound, 4)
	end
	sound:Play()
end

-- Client only: non-positional sound heard by the local player.
function Sounds.playLocal(name: string, volume: number?)
	local sound = make(name, volume)
	if not sound then
		return
	end
	sound.Parent = SoundService
	SoundService:PlayLocalSound(sound)
	Debris:AddItem(sound, 4)
end

return Sounds
