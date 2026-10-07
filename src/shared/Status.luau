--!strict
-- Pure crowd-control rules (no instances, no side effects). StatusService on
-- the server applies them; the client only reads the resulting state.
--
-- Rules (GameConfig.Status):
--   * Hard control = stun, root, knockback. A target hit by hard control
--     becomes "steady": immune to further hard control for
--     max(SteadyTime, duration + SteadyGap). This makes stun-locking impossible
--     whatever the number of attackers.
--   * Hard control never lasts more than MaxHardDuration.
--   * Slows never stack: only the strongest active slow applies, capped at
--     MaxSlow. Slows do not grant steady (they never remove control).
--   * A shield blocks hard control only (V2 phase 4: "short protection
--     against hard CC, never invincibility"). Slows still apply.

local GameConfig = require(script.Parent.Config.GameConfig)

local RULES = GameConfig.Status

local Status = {}

export type Slow = { amount: number, untilTime: number }

export type State = {
	-- source -> slow. One entry per source, so re-applying refreshes instead of stacking.
	slows: { [string]: Slow },
	rootUntil: number,
	shieldUntil: number,
	phaseUntil: number,
}

Status.HardKinds = table.freeze({ stun = true, root = true, knockback = true })
Status.BuffKinds = table.freeze({ shield = true, phase = true })

function Status.new(): State
	return {
		slows = {},
		rootUntil = 0,
		shieldUntil = 0,
		phaseUntil = 0,
	}
end

local function finite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

function Status.isShielded(state: State, now: number): boolean
	return now < state.shieldUntil
end

export type HardResult = {
	ok: boolean,
	-- "shield" | "steady" | "invalid"
	reason: string?,
	duration: number,
	steadyUntil: number,
}

-- Decides a hard control application. `steadyUntil` is the target's current
-- immunity end. On success, returns the clamped duration and the new
-- steadyUntil the caller must store.
function Status.resolveHard(state: State, steadyUntil: number, now: number, duration: number): HardResult
	if type(duration) ~= "number" or not finite(duration) or duration < 0 then
		return { ok = false, reason = "invalid", duration = 0, steadyUntil = steadyUntil }
	end
	if Status.isShielded(state, now) then
		return { ok = false, reason = "shield", duration = 0, steadyUntil = steadyUntil }
	end
	if now < steadyUntil then
		return { ok = false, reason = "steady", duration = 0, steadyUntil = steadyUntil }
	end
	local clamped = math.min(duration, RULES.MaxHardDuration)
	local steady = now + math.max(RULES.SteadyTime, clamped + RULES.SteadyGap)
	return { ok = true, reason = nil, duration = clamped, steadyUntil = steady }
end

-- Applies a slow from `source` (a shield does not block slows). Returns (ok, reason).
function Status.applySlow(state: State, now: number, source: string, amount: number, duration: number): (boolean, string?)
	if type(amount) ~= "number" or type(duration) ~= "number" or not finite(amount) or not finite(duration) then
		return false, "invalid"
	end
	if amount <= 0 or duration <= 0 then
		return false, "invalid"
	end
	state.slows[source] = {
		amount = math.min(amount, RULES.MaxSlow),
		untilTime = now + math.min(duration, RULES.MaxSlowDuration),
	}
	return true, nil
end

-- Strongest active slow (0 when none).
function Status.slowAmount(state: State, now: number): number
	local strongest = 0
	for source, slow in state.slows do
		if now >= slow.untilTime then
			state.slows[source] = nil
		elseif slow.amount > strongest then
			strongest = slow.amount
		end
	end
	return math.min(strongest, RULES.MaxSlow)
end

-- Walk speed multiplier from slows.
function Status.speedFactor(state: State, now: number): number
	return 1 - Status.slowAmount(state, now)
end

-- Latest time any slow ends (0 when none).
function Status.slowEnds(state: State, now: number): number
	local latest = 0
	for _, slow in state.slows do
		if slow.untilTime > now and slow.untilTime > latest then
			latest = slow.untilTime
		end
	end
	return latest
end

function Status.isRooted(state: State, now: number): boolean
	return now < state.rootUntil
end

-- Self buffs (shield, phase). Returns (ok, reason).
function Status.applyBuff(state: State, now: number, kind: string, duration: number): (boolean, string?)
	if not Status.BuffKinds[kind] or type(duration) ~= "number" or not finite(duration) or duration <= 0 then
		return false, "invalid"
	end
	local untilTime = now + math.min(duration, RULES.MaxBuffDuration)
	if kind == "shield" then
		state.shieldUntil = math.max(state.shieldUntil, untilTime)
	else
		state.phaseUntil = math.max(state.phaseUntil, untilTime)
	end
	return true, nil
end

-- Ends a self buff early (e.g. the Cosmic Eye ending a Spectral Phase).
function Status.endBuff(state: State, now: number, kind: string): boolean
	if kind == "shield" and state.shieldUntil > now then
		state.shieldUntil = now
		return true
	elseif kind == "phase" and state.phaseUntil > now then
		state.phaseUntil = now
		return true
	end
	return false
end

function Status.isPhased(state: State, now: number): boolean
	return now < state.phaseUntil
end

function Status.clear(state: State)
	table.clear(state.slows)
	state.rootUntil = 0
	state.shieldUntil = 0
	state.phaseUntil = 0
end

return Status
