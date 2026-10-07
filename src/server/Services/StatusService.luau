--!strict
-- Applies crowd control and self buffs with the shared rules in Shared/Status.
-- Every ability that affects another player MUST go through this service:
-- it is the single place that guarantees no stun-lock, no stacking slows and
-- no control on spawn-protected or shielded players.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Status = require(Shared.Status)
local Abilities = require(Shared.Config.Abilities)

local Core = script.Parent.Parent.Core
local Types = require(Core.Types)
local Sessions = require(Core.Sessions)
local CharacterService = require(script.Parent.CharacterService)

type Session = Types.Session

local StatusService = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function refreshLater(session: Session, delay: number)
	task.delay(delay + 0.05, function()
		if not session.released then
			CharacterService.refreshSpeed(session)
			Sessions.markDirty(session)
		end
	end)
end

-- Hard control ("stun" | "root"). Returns (applied, reason?).
-- reason: "protected" | "shield" | "steady" | "invalid"
function StatusService.applyControl(target: Session, kind: string, duration: number): (boolean, string?)
	if kind ~= "stun" and kind ~= "root" then
		return false, "invalid"
	end
	if CharacterService.isProtected(target) then
		return false, "protected"
	end
	local t = now()
	local result = Status.resolveHard(target.status, target.steadyUntil, t, duration)
	if not result.ok then
		return false, result.reason
	end
	target.steadyUntil = result.steadyUntil
	if kind == "stun" then
		CharacterService.stun(target, result.duration)
	else
		target.status.rootUntil = math.max(target.status.rootUntil, t + result.duration)
		CharacterService.refreshSpeed(target)
		refreshLater(target, result.duration)
	end
	Sessions.markDirty(target)
	return true, nil
end

-- Slow from `source` (one slow per source; strongest active slow wins).
function StatusService.applySlow(target: Session, source: string, amount: number, duration: number): (boolean, string?)
	if CharacterService.isProtected(target) then
		return false, "protected"
	end
	local ok, reason = Status.applySlow(target.status, now(), source, amount, duration)
	if not ok then
		return false, reason
	end
	CharacterService.refreshSpeed(target)
	refreshLater(target, math.max(0, Status.slowEnds(target.status, now()) - now()))
	Sessions.markDirty(target)
	return true, nil
end

-- Self buff ("shield" | "phase").
function StatusService.applyBuff(session: Session, kind: string, duration: number): (boolean, string?)
	local ok, reason = Status.applyBuff(session.status, now(), kind, duration)
	if ok then
		Sessions.markDirty(session)
	end
	return ok, reason
end

-- Can `session` use ability `def` right now? Returns (ok, reason?).
function StatusService.canAct(session: Session, def: Abilities.AbilityDef?): (boolean, string?)
	local t = now()
	if t < session.stunnedUntil then
		return false, "stunned"
	end
	if def and def.needsMovement and Status.isRooted(session.status, t) then
		return false, "rooted"
	end
	return true, nil
end

-- Compact view for the owner's hot Sync (display only).
function StatusService.snapshot(session: Session): { [string]: number }
	local t = now()
	local state = session.status
	return {
		stunUntil = if session.stunnedUntil > t then session.stunnedUntil else 0,
		steadyUntil = if session.steadyUntil > t then session.steadyUntil else 0,
		rootUntil = if state.rootUntil > t then state.rootUntil else 0,
		slow = Status.slowAmount(state, t),
		slowUntil = Status.slowEnds(state, t),
		shieldUntil = if state.shieldUntil > t then state.shieldUntil else 0,
		phaseUntil = if state.phaseUntil > t then state.phaseUntil else 0,
	}
end

return StatusService
