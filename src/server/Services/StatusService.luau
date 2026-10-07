--!strict
-- Applies crowd control and self buffs with the shared rules in Shared/Status.
-- Every ability that affects another player MUST go through this service:
-- it is the single place that guarantees no stun-lock, no stacking slows and
-- no control on spawn-protected or shielded players.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Status = require(Shared.Status)
local Abilities = require(Shared.Config.Abilities)
local Signal = require(Shared.Util.Signal)

local Core = script.Parent.Parent.Core
local Types = require(Core.Types)
local Sessions = require(Core.Sessions)
local CharacterService = require(script.Parent.CharacterService)

type Session = Types.Session

local StatusService = {}

-- (target, kind) after a hard control landed (grapple cut, wind-ups cancelled).
StatusService.controlled = Signal.new()

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
	StatusService.controlled:Fire(target, kind)
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

-- Slow the caster puts on themselves (Shield's mobility trade-off). Same
-- rules as any slow (strongest wins, capped) but never blocked by protection.
function StatusService.applySelfSlow(session: Session, source: string, amount: number, duration: number): (boolean, string?)
	local ok, reason = Status.applySlow(session.status, now(), source, amount, duration)
	if not ok then
		return false, reason
	end
	CharacterService.refreshSpeed(session)
	refreshLater(session, math.max(0, Status.slowEnds(session.status, now()) - now()))
	Sessions.markDirty(session)
	return true, nil
end

-- Removes one slow source (e.g. the Shield's own slow when it ends early).
function StatusService.clearSlow(session: Session, source: string)
	if session.status.slows[source] then
		session.status.slows[source] = nil
		CharacterService.refreshSpeed(session)
		Sessions.markDirty(session)
	end
end

-- Mirrors shield / phase end times on the character so every client can
-- draw them (server time; 0 = none).
local function publishBuffs(session: Session)
	local character = session.player.Character
	if character then
		local state = session.status
		character:SetAttribute("ShieldUntil", state.shieldUntil)
		character:SetAttribute("PhaseUntil", state.phaseUntil)
	end
end

-- Self buff ("shield" | "phase").
function StatusService.applyBuff(session: Session, kind: string, duration: number): (boolean, string?)
	local ok, reason = Status.applyBuff(session.status, now(), kind, duration)
	if ok then
		publishBuffs(session)
		if kind == "phase" then
			-- Pass through players now, collide again when it ends.
			CharacterService.refreshCollision(session)
			local untilTime = session.status.phaseUntil
			task.delay(math.max(0, untilTime - now()) + 0.05, function()
				if not session.released and now() >= session.status.phaseUntil then
					CharacterService.refreshCollision(session)
				end
			end)
		end
		Sessions.markDirty(session)
	end
	return ok, reason
end

-- Ends a self buff early. Returns true when one was active.
function StatusService.endBuff(session: Session, kind: string): boolean
	local ended = Status.endBuff(session.status, now(), kind)
	if ended then
		publishBuffs(session)
		if kind == "phase" then
			CharacterService.refreshCollision(session)
		end
		Sessions.markDirty(session)
	end
	return ended
end

function StatusService.isPhased(session: Session): boolean
	return Status.isPhased(session.status, now())
end

function StatusService.isShielded(session: Session): boolean
	return Status.isShielded(session.status, now())
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
