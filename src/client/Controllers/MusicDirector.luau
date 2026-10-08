--!strict
-- Dynamic music: Boss > Chase > Event > Rift > Explore.
--
--   MusicSensors  (what is happening)       sampled every SenseInterval
--   MusicState    (which state/slot wins)   priorities, debounce, release
--   MusicPlayer   (how it sounds)           crossfades, resume, stingers
--
-- One Heartbeat connection drives everything. Tracks come from
-- Shared/Config/Music: a slot without an asset id stays silent, and so does
-- a slot whose id failed the runtime check (Controllers/AudioCheck).
--
-- Phase 7A: boss themes are local to the player (2D), start with the fight
-- (MusicBoss attribute set at the Intro), fade out on victory / defeat /
-- exit, and get brighter in later phases (Music.BossIntensity: EQ + level,
-- never faster) instead of switching tracks.

local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Music = require(Shared.Config.Music)
local Signal = require(Shared.Util.Signal)

local MusicFolder = script.Parent.Parent.Music
local MusicState = require(MusicFolder.MusicState)
local MusicPlayer = require(MusicFolder.MusicPlayer)
local MusicSensors = require(MusicFolder.MusicSensors)
local Audio = require(script.Parent.Audio)
local AudioCheck = require(script.Parent.AudioCheck)
local Players = game:GetService("Players")

local MusicDirector = {}

-- (decision) fired whenever the music changes state or track.
MusicDirector.changed = Signal.new()

local machine: MusicState.MusicState? = nil
local player: MusicPlayer.MusicPlayer? = nil
local sensors: MusicSensors.MusicSensors? = nil
local connection: RBXScriptConnection? = nil
local senseTimer = 0
-- Test hook: replaces the configured ids (never used by the game).
local idOverrides: { [string]: string }? = nil

local function resolveId(key: string): string
	if idOverrides then
		return idOverrides[key] or ""
	end
	local def = Music.track(key)
	if not def or not AudioCheck.musicAllowed(def.id) then
		return ""
	end
	return def.id
end

-- Boss phase of the local player's fight (0 = not in a boss fight).
local function bossPhase(): number
	local player = Players.LocalPlayer
	local boss = if player then player:GetAttribute("MusicBoss") else nil
	if type(boss) ~= "string" or boss == "" then
		return 0
	end
	local phase = player:GetAttribute("MusicBossPhase")
	return if type(phase) == "number" then math.clamp(math.floor(phase), 1, #Music.BossIntensity) else 1
end

local function now(): number
	return os.clock()
end

local function evaluate()
	local m, p, s = machine, player, sensors
	if not m or not p or not s then
		return
	end
	local decision = m:update(now(), s:sense(), function(key: string): boolean
		return p:isPlayable(key)
	end)
	if decision then
		p:play(decision.key, decision.fadeIn, decision.fadeOut)
		if decision.stinger then
			p:stinger(decision.stinger)
		end
		MusicDirector.changed:Fire(decision)
	end
	p:setIntensity(if m.current == "Boss" then bossPhase() else 0)
end

local function step(dt: number)
	senseTimer += dt
	if senseTimer >= Music.Settings.SenseInterval then
		senseTimer = 0
		evaluate()
	end
	local p = player
	if p then
		p:step(dt)
	end
end

function MusicDirector.start()
	if connection then
		return
	end
	machine = MusicState.new()
	player = MusicPlayer.new({
		parent = SoundService,
		group = Audio.musicGroup(),
		resolveId = resolveId,
		now = now,
	})
	sensors = MusicSensors.new()
	senseTimer = 0
	connection = RunService.Heartbeat:Connect(step)
	evaluate()
end

-- A track that fails the runtime check stops counting right away.
AudioCheck.changed:Connect(function()
	if connection then
		evaluate()
	end
end)

-- Current boss intensity level of the music (0 = none, 1..3).
function MusicDirector.intensity(): number
	return if player then player.intensity else 0
end

-- Stops the music and releases every Sound and connection.
function MusicDirector.stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	if player then
		player:destroy()
	end
	player, machine, sensors = nil, nil, nil
end

function MusicDirector.isRunning(): boolean
	return connection ~= nil
end

-- One-shot stinger (e.g. "Stinger.BossVictory"). A slot without an asset id
-- stays silent: returns false and nothing is created (existing fallback).
function MusicDirector.stinger(key: string): boolean
	local p = player
	if not p then
		return false
	end
	return p:stinger(key)
end

-- Current music state and slot (slot nil = silent).
function MusicDirector.current(): (string?, string?)
	local m = machine
	if not m then
		return nil, nil
	end
	return m.current, m.currentKey
end

export type DebugInfo = {
	state: string?,
	key: string?,
	audible: { { key: string, volume: number } },
	sounds: number,
	created: number,
	switches: number,
}

function MusicDirector.debugInfo(): DebugInfo
	local m, p = machine, player
	return {
		state = if m then m.current else nil,
		key = if m then m.currentKey else nil,
		audible = if p then p:audible() else {},
		sounds = if p then p:soundCount() else 0,
		created = if p then p.created else 0,
		switches = if m then m.switches else 0,
	}
end

-- TESTS ONLY: pretend these slots have ids (restarts the director).
function MusicDirector.debugSetIds(map: { [string]: string }?)
	idOverrides = map
	if connection then
		MusicDirector.stop()
		MusicDirector.start()
	end
end

return MusicDirector
