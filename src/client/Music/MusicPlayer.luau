--!strict
-- Plays the main music track with clean transitions.
--
--   * Equal-power crossfade: the outgoing track fades out while the new one
--     fades in; perceived loudness stays even (no dip, no bump).
--   * Never more than TWO music tracks audible (only during a crossfade); a
--     third request immediately parks the oldest fading track.
--   * Parked tracks are paused, not destroyed, and resume where they left off
--     if they come back within Settings.ResumeWindow (natural return to the
--     previous music). At most Settings.MaxCachedTracks are kept.
--   * Slots without an asset id never create a Sound.
--   * One-shot stingers are throttled and destroyed when finished.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Music = require(ReplicatedStorage.Shared.Config.Music)

local MusicPlayer = {}
MusicPlayer.__index = MusicPlayer

export type Options = {
	parent: Instance,
	group: SoundGroup?,
	-- Asset id for a slot ("" = silent).
	resolveId: (key: string) -> string,
	now: () -> number,
}

type Channel = {
	key: string,
	sound: Sound,
	level: number,
	target: number,
	rate: number,
	base: number,
	startedAt: number,
}

type Parked = { sound: Sound, at: number }

export type MusicPlayer = typeof(setmetatable({} :: {
	options: Options,
	channels: { Channel },
	cache: { [string]: Parked },
	stingers: { Sound },
	stingerAt: { [string]: number },
	created: number,
	destroyed: boolean,
}, MusicPlayer))

function MusicPlayer.new(options: Options): MusicPlayer
	return setmetatable({
		options = options,
		channels = {},
		cache = {},
		stingers = {},
		stingerAt = {},
		created = 0,
		destroyed = false,
	}, MusicPlayer)
end

local function curve(level: number): number
	return math.sin(math.clamp(level, 0, 1) * math.pi / 2)
end

function MusicPlayer.isPlayable(self: MusicPlayer, key: string): boolean
	return Music.track(key) ~= nil and self.options.resolveId(key) ~= ""
end

local function trimCache(self: MusicPlayer)
	local now = self.options.now()
	local entries = {}
	for key, parked in self.cache do
		if now - parked.at > Music.Settings.ResumeWindow then
			parked.sound:Destroy()
			self.cache[key] = nil
		else
			table.insert(entries, { key = key, at = parked.at })
		end
	end
	table.sort(entries, function(a, b)
		return a.at > b.at
	end)
	for i = Music.Settings.MaxCachedTracks + 1, #entries do
		local key = entries[i].key
		self.cache[key].sound:Destroy()
		self.cache[key] = nil
	end
end

local function park(self: MusicPlayer, channel: Channel)
	local index = table.find(self.channels, channel)
	if index then
		table.remove(self.channels, index)
	end
	channel.sound.Volume = 0
	channel.sound:Pause()
	local previous = self.cache[channel.key]
	if previous and previous.sound ~= channel.sound then
		previous.sound:Destroy()
	end
	self.cache[channel.key] = { sound = channel.sound, at = self.options.now() }
	trimCache(self)
end

local function newSound(self: MusicPlayer, key: string, id: string, looped: boolean): Sound
	local sound = Instance.new("Sound")
	sound.Name = "Music_" .. key
	sound.SoundId = id
	sound.Looped = looped
	sound.Volume = 0
	if self.options.group then
		sound.SoundGroup = self.options.group
	end
	sound.Parent = self.options.parent
	self.created += 1
	return sound
end

-- Crossfades to `key` (nil = fade to silence).
function MusicPlayer.play(self: MusicPlayer, key: string?, fadeIn: number, fadeOut: number)
	if self.destroyed then
		return
	end
	for _, channel in self.channels do
		if channel.key ~= key then
			channel.target = 0
			channel.rate = 1 / math.max(fadeOut, 0.05)
		end
	end
	if key == nil or not self:isPlayable(key) then
		return
	end
	local def = Music.track(key) :: Music.TrackDef
	-- Already playing (or fading out): bring it back.
	for _, channel in self.channels do
		if channel.key == key then
			channel.target = 1
			channel.rate = 1 / math.max(fadeIn, 0.05)
			return
		end
	end
	-- Keep at most one other track audible: park the oldest fading ones now.
	while #self.channels >= 2 do
		park(self, self.channels[1])
	end
	local now = self.options.now()
	local sound: Sound
	local parked = self.cache[key]
	if parked and now - parked.at <= Music.Settings.ResumeWindow then
		self.cache[key] = nil
		sound = parked.sound
		sound:Resume()
	else
		if parked then
			parked.sound:Destroy()
			self.cache[key] = nil
		end
		sound = newSound(self, key, self.options.resolveId(key), true)
		sound:Play()
	end
	table.insert(self.channels, {
		key = key,
		sound = sound,
		level = 0,
		target = 1,
		rate = 1 / math.max(fadeIn, 0.05),
		base = def.volume,
		startedAt = now,
	})
end

-- Advances fades (call every frame).
function MusicPlayer.step(self: MusicPlayer, dt: number)
	for i = #self.channels, 1, -1 do
		local channel = self.channels[i]
		if channel.level < channel.target then
			channel.level = math.min(channel.target, channel.level + channel.rate * dt)
		elseif channel.level > channel.target then
			channel.level = math.max(channel.target, channel.level - channel.rate * dt)
		end
		channel.sound.Volume = channel.base * curve(channel.level)
		if channel.level <= 0 and channel.target <= 0 then
			park(self, channel)
		end
	end
end

-- One-shot musical cue (throttled).
function MusicPlayer.stinger(self: MusicPlayer, key: string): boolean
	if self.destroyed or not self:isPlayable(key) then
		return false
	end
	local now = self.options.now()
	if now - (self.stingerAt[key] or -math.huge) < Music.Settings.StingerCooldown then
		return false
	end
	self.stingerAt[key] = now
	local def = Music.track(key) :: Music.TrackDef
	local sound = newSound(self, key, self.options.resolveId(key), false)
	sound.Volume = def.volume
	table.insert(self.stingers, sound)
	sound.Ended:Once(function()
		local index = table.find(self.stingers, sound)
		if index then
			table.remove(self.stingers, index)
		end
		sound:Destroy()
	end)
	sound:Play()
	return true
end

-- Music tracks currently audible (level > 0) — at most 2, during a crossfade.
function MusicPlayer.audible(self: MusicPlayer): { { key: string, volume: number } }
	local list = {}
	for _, channel in self.channels do
		if channel.level > 0 and channel.sound.IsPlaying then
			table.insert(list, { key = channel.key, volume = channel.sound.Volume })
		end
	end
	return list
end

-- The track fading in / at full volume (nil when silent).
function MusicPlayer.leading(self: MusicPlayer): string?
	for i = #self.channels, 1, -1 do
		if self.channels[i].target > 0 then
			return self.channels[i].key
		end
	end
	return nil
end

function MusicPlayer.soundCount(self: MusicPlayer): number
	local count = #self.channels + #self.stingers
	for _ in self.cache do
		count += 1
	end
	return count
end

function MusicPlayer.destroy(self: MusicPlayer)
	self.destroyed = true
	for _, channel in self.channels do
		channel.sound:Destroy()
	end
	for _, parked in self.cache do
		parked.sound:Destroy()
	end
	for _, sound in self.stingers do
		sound:Destroy()
	end
	table.clear(self.channels)
	table.clear(self.cache)
	table.clear(self.stingers)
end

return MusicPlayer
