local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local Config = require(script.Parent.Config)

local Sounds = {}

local function make(name: string, volume: number?): Sound?
	local id = Config.Sounds[name]
	if not id or id == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = id
	sound.Volume = volume or 0.5
	sound.RollOffMaxDistance = 60
	return sound
end

-- 3D sound at a position or on an instance. Played from the server, everyone nearby hears it.
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
