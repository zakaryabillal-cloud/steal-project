--!strict
-- Sound playback through the central registry (Shared/Config/Sounds).
-- 2D sounds are pooled per key; 3D sounds are spawned at world positions.

local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)
local Settings = require(script.Parent.Settings)

local Audio = {}

local sfxGroup: SoundGroup
local musicGroup: SoundGroup
local pools: { [string]: { Sound } } = {}
local rng = Random.new()
local MAX_PER_KEY = 5

local function resolve(key: string): (Sounds.SoundDef?, string)
	local def = Sounds[key]
	if not def then
		return nil, ""
	end
	local id = if def.id ~= "" then def.id else def.fallback
	return def, id
end

function Audio.init()
	sfxGroup = Instance.new("SoundGroup")
	sfxGroup.Name = "RiftSFX"
	sfxGroup.Parent = SoundService
	musicGroup = Instance.new("SoundGroup")
	musicGroup.Name = "RiftMusic"
	musicGroup.Parent = SoundService
	local function refresh()
		sfxGroup.Volume = Settings.sfx
		musicGroup.Volume = Settings.music
	end
	refresh()
	Settings.changed:Connect(refresh)
end

local function configure(sound: Sound, def: Sounds.SoundDef, id: string, pitch: number?, volume: number?)
	sound.SoundId = id
	sound.Volume = def.volume * (volume or 1)
	local variance = if def.variance > 0 then rng:NextNumber(-def.variance, def.variance) else 0
	sound.PlaybackSpeed = math.max(0.05, def.pitch * (pitch or 1) + variance)
	sound.Looped = def.looped
end

export type PlayOptions = { pitch: number?, volume: number? }

function Audio.play(key: string, options: PlayOptions?): Sound?
	local def, id = resolve(key)
	if not def or id == "" then
		return nil
	end
	local pool = pools[key]
	if not pool then
		pool = {}
		pools[key] = pool
	end
	local found: Sound? = nil
	for _, candidate in pool do
		if not candidate.IsPlaying then
			found = candidate
			break
		end
	end
	local s: Sound
	if found then
		s = found
	elseif #pool >= MAX_PER_KEY then
		s = table.remove(pool, 1) :: Sound
		table.insert(pool, s)
	else
		s = Instance.new("Sound")
		s.Name = key
		s.SoundGroup = sfxGroup
		s.Parent = SoundService
		table.insert(pool, s)
	end
	configure(s, def, id, options and options.pitch, options and options.volume)
	s.TimePosition = 0
	s:Play()
	return s
end

-- Positional one-shot at a world point.
function Audio.playAt(key: string, position: Vector3, options: PlayOptions?): Sound?
	local def, id = resolve(key)
	if not def or id == "" then
		return nil
	end
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = workspace.Terrain
	local sound = Instance.new("Sound")
	sound.SoundGroup = sfxGroup
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 12
	sound.RollOffMaxDistance = 160
	configure(sound, def, id, options and options.pitch, options and options.volume)
	sound.Parent = attachment
	sound:Play()
	sound.Ended:Once(function()
		attachment:Destroy()
	end)
	task.delay(8, function()
		if attachment.Parent then
			attachment:Destroy()
		end
	end)
	return sound
end

-- Configures and plays a looping sound already placed in the world (e.g. the Rift hum).
function Audio.loopOn(key: string, sound: Sound)
	local def, id = resolve(key)
	if not def or id == "" then
		return
	end
	configure(sound, def, id, nil, nil)
	sound.Looped = true
	sound.SoundGroup = sfxGroup
	if not sound.IsPlaying then
		sound:Play()
	end
end

-- Background music (only if an asset id is configured).
function Audio.startMusic()
	local def, id = resolve("Music")
	if not def or id == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "Music"
	sound.SoundGroup = musicGroup
	configure(sound, def, id, nil, nil)
	sound.Looped = true
	sound.Parent = SoundService
	sound:Play()
	local ambient, ambientId = resolve("AmbientWorld")
	if ambient and ambientId ~= "" then
		local bed = Instance.new("Sound")
		bed.Name = "Ambient"
		bed.SoundGroup = sfxGroup
		configure(bed, ambient, ambientId, nil, nil)
		bed.Looped = true
		bed.Parent = SoundService
		bed:Play()
	end
end

return Audio
