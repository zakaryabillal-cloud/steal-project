--!strict
-- Sound playback through the central registry (Shared/Config/Sounds).
-- 2D sounds are pooled per key; 3D sounds are spawned at world positions.
-- Music lives in Config/Music and is driven by MusicDirector.
--
-- Phase 7A mixing:
--   * an asset id plays only once AudioCheck verified it (else the built-in
--     fallback);
--   * priorities (Sounds `priority`, 1 = danger .. 5 = ambience): at most
--     MAX_ACTIVE one-shots at once, the least important gives way;
--   * `minGap` per key: no spam when 8 players trigger the same sound;
--   * priority 1-2 sounds (danger tick, special attacks) duck the music to
--     Music.DuckLevel for a moment; the player's volume sliders always apply.

local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)
local Music = require(ReplicatedStorage.Shared.Config.Music)
local Settings = require(script.Parent.Settings)
local AudioCheck = require(script.Parent.AudioCheck)

local Audio = {}

local sfxGroup: SoundGroup
local musicGroup: SoundGroup
local pools: { [string]: { Sound } } = {}
local rng = Random.new()
local MAX_PER_KEY = 5
-- One-shots audible at the same time (all keys).
local MAX_ACTIVE = 14

type Active = { sound: Sound, priority: number, untilClock: number }
local active: { Active } = {}
local lastPlayed: { [string]: number } = {}
local duckLevel = 1
local duckUntil = 0
local duckCurrent = 1

local function resolve(key: string): (Sounds.SoundDef?, string)
	local def = Sounds[key]
	if not def then
		return nil, ""
	end
	local id = if def.id ~= "" and AudioCheck.usable(def.id) then def.id else def.fallback
	return def, id
end
Audio.resolve = resolve

-- Ducks the music to `level` (0..1) for `seconds` (the strongest wins).
function Audio.duck(level: number, seconds: number)
	local t = os.clock()
	if t >= duckUntil then
		duckLevel = level
	else
		duckLevel = math.min(duckLevel, level)
	end
	duckUntil = math.max(duckUntil, t + seconds)
end

-- May `key` play now? (anti-spam gap, concurrency cap by priority, ducking)
local function admit(key: string, def: Sounds.SoundDef): boolean
	local t = os.clock()
	if def.minGap and t - (lastPlayed[key] or -math.huge) < def.minGap then
		return false
	end
	for i = #active, 1, -1 do
		local entry = active[i]
		if t > entry.untilClock or not entry.sound.IsPlaying or entry.sound.Parent == nil then
			table.remove(active, i)
		end
	end
	local priority = def.priority or 4
	if #active >= MAX_ACTIVE then
		local worst, worstIndex = nil :: Active?, 0
		for i, entry in active do
			if worst == nil or entry.priority > (worst :: Active).priority then
				worst, worstIndex = entry, i
			end
		end
		if worst and worst.priority > priority then
			worst.sound:Stop()
			table.remove(active, worstIndex)
		else
			return false
		end
	end
	lastPlayed[key] = t
	if priority <= 2 then
		Audio.duck(Music.DuckLevel, 1.1)
	end
	return true
end

local function track(sound: Sound, def: Sounds.SoundDef)
	if def.looped then
		return
	end
	local length = if sound.TimeLength > 0 then sound.TimeLength / math.max(0.05, sound.PlaybackSpeed) else 3
	table.insert(active, { sound = sound, priority = def.priority or 4, untilClock = os.clock() + math.clamp(length, 0.3, 8) })
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
		musicGroup.Volume = Settings.music * duckCurrent
	end
	refresh()
	Settings.changed:Connect(refresh)
	-- Smooth ducking: down fast, back up gently.
	RunService.Heartbeat:Connect(function(dt: number)
		local target = if os.clock() < duckUntil then duckLevel else 1
		if duckCurrent ~= target then
			local rate = if target < duckCurrent then 6 else 1.6
			if target < duckCurrent then
				duckCurrent = math.max(target, duckCurrent - rate * dt)
			else
				duckCurrent = math.min(target, duckCurrent + rate * dt)
			end
			musicGroup.Volume = Settings.music * duckCurrent
		end
	end)
	AudioCheck.run()
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
	if not def or id == "" or not admit(key, def) then
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
	track(s, def)
	return s
end

-- Positional one-shot at a world point.
function Audio.playAt(key: string, position: Vector3, options: PlayOptions?): Sound?
	local def, id = resolve(key)
	if not def or id == "" or not admit(key, def) then
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
	track(sound, def)
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

-- Looping bed (e.g. the forge's lava crackle) parented to `parent` (2D in
-- SoundService by default). nil when the key has no playable audio (an
-- unverified id with an empty fallback stays silent).
function Audio.playLoop(key: string, parent: Instance?): Sound?
	local def, id = resolve(key)
	if not def or id == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = "Loop_" .. key
	sound.SoundGroup = sfxGroup
	configure(sound, def, id, nil, nil)
	sound.Looped = true
	sound.Parent = parent or SoundService
	sound:Play()
	return sound
end

-- Tests / debug: current music duck factor and audible one-shots.
function Audio.debugMix(): { duck: number, active: number }
	return { duck = duckCurrent, active = #active }
end

-- SoundGroup of the music (volume = the player's Music setting). Music
-- itself is driven by Controllers/MusicDirector (Config/Music).
function Audio.musicGroup(): SoundGroup
	return musicGroup
end

-- Looping ambient bed under the music (only if an asset id is configured).
-- Ambience is a separate layer: it never competes with the main music.
function Audio.startAmbience()
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
