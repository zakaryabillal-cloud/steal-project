--!strict
-- Runtime check of every configured audio asset id (V2 phase 7A).
--
-- Asset ids cannot be validated from the repository: whether an id exists,
-- is public / allowed in THIS experience and has the expected length is
-- only known by a real Roblox client. At start-up this module asks
-- ContentProvider:PreloadAsync for every id of Config/Sounds and
-- Config/Music, waits for the Sound to load and reads its TimeLength:
--
--   ok        loaded, length within the slot's limit  -> the id is used
--   failed    deleted, private, not allowed, timeout  -> fallback + warning
--   tooLong   longer than the slot's `maxLength` (e.g. a music track pasted
--             into a sound effect slot)               -> fallback + warning
--   pending   being checked
--   unchecked no ContentProvider (headless tests)
--
-- Sound effects use their id only when "ok" (the built-in fallback plays
-- meanwhile). Music keeps its id unless the check FAILED (a failing track is
-- then an empty slot: the next music state plays, as before). Studio prints
-- the full report at start-up and on "/rh audio".

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Sounds = require(Shared.Config.Sounds)
local Music = require(Shared.Config.Music)
local Signal = require(Shared.Util.Signal)

local AudioCheck = {}

export type Entry = {
	id: string,
	-- Config keys using this id ("Sounds.VWAppear", "Music.Boss.VoidWarden.1").
	keys: { string },
	kind: string, -- "sound" | "music"
	status: string,
	length: number?,
	maxLength: number?,
	reason: string?,
}

-- (entry) fired when an id's status changes.
AudioCheck.changed = Signal.new()

local entries: { [string]: Entry } = {}
local started = false
-- Tests: synchronous probe replacing ContentProvider (returns status, length).
local probe: ((id: string) -> (boolean, number?))? = nil

local LOAD_TIMEOUT = 8

local function register(id: string, key: string, kind: string, maxLength: number?)
	if id == "" or string.sub(id, 1, 13) ~= "rbxassetid://" then
		return
	end
	local entry = entries[id]
	if not entry then
		entry = { id = id, keys = {}, kind = kind, status = "unchecked", length = nil, maxLength = maxLength, reason = nil }
		entries[id] = entry
	end
	table.insert(entry.keys, key)
	if maxLength and (entry.maxLength == nil or maxLength < (entry.maxLength :: number)) then
		entry.maxLength = maxLength
	end
end

local function collect()
	table.clear(entries)
	for key, def in Sounds do
		register(def.id, "Sounds." .. key, "sound", def.maxLength)
	end
	for key, track in Music.Tracks do
		register(track.id, "Music." .. key, "music", nil)
	end
end

local function settle(entry: Entry, loaded: boolean, length: number?)
	if not loaded then
		entry.status = "failed"
		entry.reason = "could not be loaded (deleted, private or not allowed in this experience)"
	elseif entry.maxLength and length and length > (entry.maxLength :: number) then
		entry.status = "tooLong"
		entry.reason = string.format("is %.1f s long, the slot accepts %.0f s at most (wrong kind of audio?)", length, entry.maxLength :: number)
	else
		entry.status = "ok"
		entry.reason = nil
	end
	entry.length = length
	if entry.status ~= "ok" then
		warn(string.format("[RiftHeist audio] %s (%s) %s: the built-in fallback is used instead.", entry.id, table.concat(entry.keys, ", "), entry.reason or "?"))
	end
	AudioCheck.changed:Fire(entry)
end

-- Real client: preload + wait for the Sound to load + read its length.
local function verify(provider: Instance, entry: Entry)
	local sound = Instance.new("Sound")
	sound.Name = "AudioCheck"
	sound.SoundId = entry.id
	sound.Volume = 0
	local fetched = false
	local ok = pcall(function()
		(provider :: any):PreloadAsync({ sound }, function(_: string, status: Enum.AssetFetchStatus)
			if status == Enum.AssetFetchStatus.Success then
				fetched = true
			end
		end)
	end)
	local loaded = false
	if ok and fetched then
		local deadline = os.clock() + LOAD_TIMEOUT
		while not sound.IsLoaded and os.clock() < deadline do
			task.wait(0.1)
		end
		loaded = sound.IsLoaded and sound.TimeLength > 0
	end
	local length = if loaded then sound.TimeLength else nil
	sound:Destroy()
	settle(entry, loaded, length)
end

-- Starts the checks (once). Safe without ContentProvider (stays unchecked).
function AudioCheck.run()
	if started then
		return
	end
	started = true
	collect()
	local test = probe
	if test then
		for _, entry in entries do
			local loaded, length = test(entry.id)
			settle(entry, loaded, length)
		end
		return
	end
	local ok, provider = pcall(function()
		return game:GetService("ContentProvider")
	end)
	if not ok or not provider then
		return
	end
	for _, entry in entries do
		entry.status = "pending"
		task.spawn(verify, provider, entry)
	end
	if RunService:IsStudio() then
		task.delay(LOAD_TIMEOUT + 2, function()
			AudioCheck.print()
		end)
	end
end

function AudioCheck.status(id: string): string
	local entry = entries[id]
	return if entry then entry.status else "unchecked"
end

-- A sound effect id may be played (verified OK).
function AudioCheck.usable(id: string): boolean
	return id ~= "" and AudioCheck.status(id) == "ok"
end

-- A music id may be played (not known to fail).
function AudioCheck.musicAllowed(id: string): boolean
	if id == "" then
		return false
	end
	local status = AudioCheck.status(id)
	return status ~= "failed" and status ~= "tooLong"
end

-- Every checked id, sorted (report / tests).
function AudioCheck.report(): { Entry }
	local list = {}
	for _, entry in entries do
		table.insert(list, entry)
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	return list
end

function AudioCheck.print()
	print("[RiftHeist audio] asset check (real client only; 'unchecked' = no ContentProvider):")
	for _, entry in AudioCheck.report() do
		local length = if entry.length then string.format("%.1f s", entry.length) else "-"
		print(string.format("  %-28s %-9s %-8s %s", entry.id, entry.status, length, table.concat(entry.keys, ", ")))
	end
end

-- TESTS ONLY: replace the real check with a synchronous probe and re-run.
function AudioCheck.debugProbe(fn: ((id: string) -> (boolean, number?))?)
	probe = fn
	started = false
	AudioCheck.run()
end

return AudioCheck
