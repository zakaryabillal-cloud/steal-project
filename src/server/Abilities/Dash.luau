--!strict
-- Dash (Mobility): a short burst. Movement is applied by the client for
-- instant response; the server owns the cooldown (AbilityService), raises the
-- movement guard threshold for a moment (never switches it off) and
-- broadcasts the trail.
--
-- Storm Crystal harmony: the dash leaves a static trail (from where the dash
-- started to where the server sees the player a moment later, clamped) that
-- slows other players crossing it (once per trail, StatusService rules).

local Core = script.Parent.Parent.Core
local Types = require(Core.Types)
local Remotes = require(Core.Remotes)
local Sessions = require(Core.Sessions)
local Services = script.Parent.Parent.Services
local StatusService = require(Services.StatusService)
local MovementGuard = require(Services.MovementGuard)
local Common = require(script.Parent.Common)

type Session = Types.Session

type Trail = {
	owner: Session,
	from: Vector3,
	to: Vector3?,
	sampleAt: number,
	untilTime: number,
	tuning: { [string]: any },
	hit: { [Session]: boolean },
	cosmicEye: boolean,
}

local Dash = {}

local trails: { Trail } = {}

function Dash.activate(ctx: Types.AbilityContext)
	local session = ctx.session
	local tuning = ctx.tuning
	MovementGuard.allow(session, tuning.GuardSpeed, tuning.GuardTime)
	Remotes.fx("Dash", { userId = session.userId })
	local storm = tuning.StormTrail
	if storm then
		-- One trail per owner at a time.
		for i = #trails, 1, -1 do
			if trails[i].owner == session then
				table.remove(trails, i)
			end
		end
		table.insert(trails, {
			owner = session,
			from = ctx.root.Position,
			to = nil,
			sampleAt = ctx.now + storm.Sample,
			untilTime = ctx.now + storm.Sample + storm.Duration,
			tuning = storm,
			hit = {},
			cosmicEye = ctx.harmonies.cosmic_eye == true,
		})
	end
end

local function distanceToSegment(p: Vector3, a: Vector3, b: Vector3): number
	local ab = b - a
	local length2 = ab:Dot(ab)
	if length2 < 1e-6 then
		return (p - a).Magnitude
	end
	local t = math.clamp((p - a):Dot(ab) / length2, 0, 1)
	return (p - (a + ab * t)).Magnitude
end

function Dash.tick(now: number)
	for i = #trails, 1, -1 do
		local trail = trails[i]
		if trail.owner.released or now >= trail.untilTime then
			table.remove(trails, i)
			continue
		end
		local tuning = trail.tuning
		if trail.to == nil then
			if now < trail.sampleAt then
				continue
			end
			-- The end is where the server sees the dasher, never further than
			-- MaxLength from the start (a client cannot stretch the trail).
			local root = Common.root(trail.owner)
			if not root then
				table.remove(trails, i)
				continue
			end
			local delta = root.Position - trail.from
			if delta.Magnitude > tuning.MaxLength then
				delta = delta.Unit * tuning.MaxLength
			end
			trail.to = trail.from + delta
			Remotes.fx("StormTrail", { userId = trail.owner.userId, from = trail.from, to = trail.to, untilTime = trail.untilTime })
		end
		local a, b = trail.from, trail.to :: Vector3
		for _, target in Sessions.all() do
			if trail.hit[target] or not Common.canAffect(trail.owner, target) then
				continue
			end
			local root = Common.root(target)
			if not root then
				continue
			end
			local p = root.Position
			local flatA, flatB = Vector3.new(a.X, p.Y, a.Z), Vector3.new(b.X, p.Y, b.Z)
			if distanceToSegment(p, flatA, flatB) <= tuning.HalfWidth and math.abs(p.Y - (a.Y + b.Y) / 2) <= 6 then
				trail.hit[target] = true
				if StatusService.applySlow(target, "storm", tuning.Slow, tuning.SlowDuration) then
					Common.onControlHit(trail.cosmicEye, target)
					Remotes.fx("Slowed", { userId = target.userId, by = trail.owner.userId, kind = "storm" })
				end
			end
		end
	end
end

function Dash.cleanup(session: Session, _reason: string)
	for i = #trails, 1, -1 do
		if trails[i].owner == session then
			table.remove(trails, i)
		end
	end
end

-- Tests / debug.
function Dash.activeTrails(): number
	return #trails
end

return (Dash :: any) :: Types.AbilityModule
