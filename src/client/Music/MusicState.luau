--!strict
-- Pure music state machine (no instances): decides which music state and
-- which track slot should play, given the sensed conditions.
--
--   * Priority: Boss > Chase > Event > Rift > Explore (Config/Music.States).
--   * Debounce: a condition must hold `enterDelay` seconds before its state
--     can win (e.g. walking past the Rift edge does not flip the music).
--   * Release: the current state is kept `hold` seconds after its condition
--     ends, so a chase that pauses for a second does not cut the music.
--   * Anti-flapping: moving DOWN in priority waits at least
--     MinSwitchInterval since the last change; moving UP is immediate.
--   * Silent slots: with FallThroughWhenSilent the highest state that has
--     audio wins, so an empty slot never silences the current music.
--   * Return: when a higher state ends, the next effective state below it
--     (often the previous one) takes over again.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Music = require(ReplicatedStorage.Shared.Config.Music)

local MusicState = {}
MusicState.__index = MusicState

export type Params = { [string]: any }
-- stateId -> params when the condition holds now (absent = not active).
export type Signals = { [string]: Params }

export type Decision = {
	state: string,
	key: string?,
	previous: string?,
	previousKey: string?,
	fadeIn: number,
	fadeOut: number,
	stinger: string?,
	-- "state" (different state) or "track" (same state, different slot)
	kind: string,
}

export type MusicState = typeof(setmetatable({} :: {
	current: string?,
	currentKey: string?,
	changedAt: number,
	trackChangedAt: number,
	active: { [string]: boolean },
	firstSeen: { [string]: number },
	lastSeen: { [string]: number },
	params: { [string]: Params },
	switches: number,
	history: { { at: number, state: string, key: string? } },
}, MusicState))

function MusicState.new(): MusicState
	return setmetatable({
		current = nil,
		currentKey = nil,
		changedAt = -math.huge,
		trackChangedAt = -math.huge,
		active = {},
		firstSeen = {},
		lastSeen = {},
		params = {},
		switches = 0,
		history = {},
	}, MusicState)
end

local function priorityOf(id: string?): number
	if id == nil then
		return 0
	end
	local def = Music.state(id)
	return if def then def.priority else 0
end

-- First playable slot for a state (nil = silent).
local function pickKey(stateId: string, params: Params?, isPlayable: (string) -> boolean): string?
	for _, key in Music.candidates(stateId, params) do
		if isPlayable(key) then
			return key
		end
	end
	return nil
end

-- Tolerance for timing comparisons (sampling is not exact).
local EPSILON = 1e-4

function MusicState.isEffective(self: MusicState, def: Music.StateDef, now: number): boolean
	local id = def.id
	if self.active[id] then
		-- The debounce only applies when ENTERING a state: a condition that
		-- flickers back on while its state is playing keeps it playing.
		return id == self.current or now - (self.firstSeen[id] or now) + EPSILON >= def.enterDelay
	end
	-- Natural release: the current state lingers `hold` seconds.
	local last = self.lastSeen[id]
	return id == self.current and last ~= nil and now - last <= def.hold + EPSILON
end

-- Feeds the latest conditions. Returns a Decision when the music must change.
function MusicState.update(self: MusicState, now: number, signals: Signals, isPlayable: (string) -> boolean): Decision?
	local settings = Music.Settings
	signals.Explore = signals.Explore or {}
	for _, def in Music.States do
		local id = def.id
		local signal = signals[id]
		if signal then
			if not self.active[id] then
				self.firstSeen[id] = now
			end
			self.active[id] = true
			self.lastSeen[id] = now
			self.params[id] = signal
		else
			self.active[id] = false
		end
	end

	-- Highest effective state (with audio, when falling through silent slots).
	local chosen: string = "Explore"
	local chosenKey: string? = nil
	local found = false
	for _, def in Music.States do
		if self:isEffective(def, now) then
			local key = pickKey(def.id, self.params[def.id], isPlayable)
			if key or not settings.FallThroughWhenSilent then
				chosen, chosenKey, found = def.id, key, true
				break
			end
		end
	end
	if not found then
		chosen, chosenKey = "Explore", pickKey("Explore", nil, isPlayable)
	end

	if chosen ~= self.current then
		local up = priorityOf(chosen) > priorityOf(self.current)
		if not up and now - self.changedAt + EPSILON < settings.MinSwitchInterval then
			return nil
		end
		local previous, previousKey = self.current, self.currentKey
		local newDef = Music.state(chosen) :: Music.StateDef
		local oldDef = if previous then Music.state(previous) else nil
		self.current, self.currentKey = chosen, chosenKey
		self.changedAt, self.trackChangedAt = now, now
		self.switches += 1
		table.insert(self.history, { at = now, state = chosen, key = chosenKey })
		if #self.history > 64 then
			table.remove(self.history, 1)
		end
		return {
			state = chosen,
			key = chosenKey,
			previous = previous,
			previousKey = previousKey,
			fadeIn = newDef.fadeIn,
			fadeOut = if oldDef then math.min(oldDef.fadeOut, if up then newDef.fadeIn + 0.5 else oldDef.fadeOut) else 0,
			stinger = if up then newDef.stinger else nil,
			kind = "state",
		}
	elseif chosenKey ~= self.currentKey then
		local immediate = chosen == "Boss"
		if not immediate and now - self.trackChangedAt + EPSILON < settings.MinTrackChangeInterval then
			return nil
		end
		local def = Music.state(chosen) :: Music.StateDef
		local previousKey = self.currentKey
		self.currentKey = chosenKey
		self.trackChangedAt = now
		table.insert(self.history, { at = now, state = chosen, key = chosenKey })
		return {
			state = chosen,
			key = chosenKey,
			previous = chosen,
			previousKey = previousKey,
			fadeIn = math.min(def.fadeIn, 1.5),
			fadeOut = math.min(def.fadeOut, 1.5),
			stinger = nil,
			kind = "track",
		}
	end
	return nil
end

return MusicState
