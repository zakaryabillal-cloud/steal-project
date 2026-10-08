--!strict
-- Blink (Mobility): a short teleport in a direction, after a visible wind-up.
--
-- The client sends a DIRECTION only (a unit vector; garbage falls back to the
-- character's facing). The server computes the destination from the
-- character's current position when the wind-up ends:
--   * three horizontal rays (knees, waist, head) plus two side rays find the
--     first obstacle: the blink stops WallMargin before it, so it can never
--     cross a wall, an obstacle or any colliding geometry;
--   * the destination needs ground at most MaxDrop below (never the void)
--     and Headroom above; otherwise it is walked back towards the caster;
--   * the final straight segment (incl. height change) must be clear;
--   * it never ends inside, or crosses into, someone else's sealed Sanctuary.
-- Shorter than MinDistance = blocked: at cast time the request is rejected
-- at no cost; after the wind-up the cooldown is mostly refunded.
-- A stun or root during the wind-up cancels it (counterplay).
-- Carrying a relic multiplies the range by CarryFactor (Void Cube harmony:
-- longer range and a smaller penalty).
--
-- The move itself is made by the server (PivotTo) and reported to the
-- movement guard, so it is neither flagged nor a hole in the guard.

local Core = script.Parent.Parent.Core
local Types = require(Core.Types)
local Remotes = require(Core.Remotes)
local Sessions = require(Core.Sessions)
local Services = script.Parent.Parent.Services
local StatusService = require(Services.StatusService)
local MovementGuard = require(Services.MovementGuard)
local Common = require(script.Parent.Common)

type Session = Types.Session

type Pending = {
	owner: Session,
	direction: Vector3,
	executeAt: number,
	tuning: { [string]: any },
}

local Blink = {}

local pending: { Pending } = {}

-- Root height above the ground the character stands on.
local ROOT_HEIGHT = 3

function Blink.readPayload(raw: any): any
	return { direction = Common.readDirection(raw) }
end

local function range(session: Session, tuning: { [string]: any }): number
	return tuning.Range * (if Common.isCarrying(session) then tuning.CarryFactor else 1)
end

-- Does the straight path a -> b touch someone else's sealed Sanctuary?
local function pathSealed(session: Session, a: Vector3, b: Vector3): boolean
	local length = (b - a).Magnitude
	local steps = math.max(1, math.ceil(length))
	for k = 0, steps do
		if Common.sealedAgainst(session, a:Lerp(b, k / steps)) then
			return true
		end
	end
	return false
end

-- Destination for `session` blinking along `direction` from `root`, or nil.
function Blink.destination(session: Session, root: BasePart, direction: Vector3, tuning: { [string]: any }): Vector3?
	local params = Common.params(session)
	local origin = root.Position
	local reach = range(session, tuning)
	local side = Vector3.new(-direction.Z, 0, direction.X)
	local probes = {
		origin + Vector3.new(0, -1.6, 0),
		origin,
		origin + Vector3.new(0, 1.4, 0),
		origin + side * 0.9,
		origin - side * 0.9,
	}
	local free = reach
	for _, start in probes do
		local hit = Common.cast(start, direction * (reach + tuning.WallMargin), params)
		if hit then
			free = math.min(free, hit.Distance - tuning.WallMargin)
		end
	end
	local distance = free
	while distance >= tuning.MinDistance do
		local candidate = origin + direction * distance
		local ground = Common.ground(candidate, ROOT_HEIGHT + tuning.MaxDrop, params)
		if ground then
			local stand = Vector3.new(candidate.X, ground.Position.Y + ROOT_HEIGHT, candidate.Z)
			local headroomClear = Common.clear(ground.Position + Vector3.new(0, 0.2, 0), ground.Position + Vector3.new(0, tuning.Headroom, 0), params)
			-- The body travels level, then drops (or rises first, then travels):
			-- both legs of that path must be clear.
			local corner = if stand.Y <= origin.Y then Vector3.new(stand.X, origin.Y, stand.Z) else Vector3.new(origin.X, stand.Y, origin.Z)
			if headroomClear and Common.clear(origin, corner, params) and Common.clear(corner, stand, params) and not pathSealed(session, origin, stand) and Common.allowedSpot(session, stand) then
				return stand
			end
		end
		distance -= tuning.Step
	end
	return nil
end

local function directionOf(ctx: Types.AbilityContext): Vector3
	return ctx.payload.direction or Common.facing(ctx.root)
end

function Blink.validate(ctx: Types.AbilityContext): (boolean, string?)
	if Blink.destination(ctx.session, ctx.root, directionOf(ctx), ctx.tuning) == nil then
		return false, "blocked"
	end
	return true, nil
end

function Blink.activate(ctx: Types.AbilityContext)
	local session = ctx.session
	Blink.cleanup(session, "replaced")
	local direction = directionOf(ctx)
	table.insert(pending, {
		owner = session,
		direction = direction,
		executeAt = ctx.now + ctx.tuning.Windup,
		tuning = ctx.tuning,
	})
	session.abilityState.blink = true
	Remotes.fx("BlinkWindup", { userId = session.userId, direction = direction, at = ctx.now + ctx.tuning.Windup })
end

function Blink.tick(now: number)
	for i = #pending, 1, -1 do
		local item = pending[i]
		if now < item.executeAt then
			continue
		end
		table.remove(pending, i)
		local session = item.owner
		session.abilityState.blink = nil
		local character, _, root = Sessions.character(session)
		if session.released or not character or not root then
			continue
		end
		local canAct = StatusService.canAct(session, { needsMovement = true } :: any)
		if not canAct then
			Remotes.fx("BlinkFail", { userId = session.userId, reason = "interrupted" })
			continue
		end
		local destination = Blink.destination(session, root, item.direction, item.tuning)
		if not destination then
			-- Blocked during the wind-up (someone sealed, a wall appeared...):
			-- most of the cooldown comes back.
			Sessions.setCooldown(session, "blink", 1)
			Remotes.fx("BlinkFail", { userId = session.userId, reason = "blocked" })
			continue
		end
		local from = root.Position
		local facing = root.CFrame - root.CFrame.Position
		character:PivotTo(CFrame.new(destination) * facing)
		MovementGuard.teleported(session, destination)
		Sessions.touch(session)
		Remotes.fx("Blink", { userId = session.userId, from = from, to = destination })
	end
end

function Blink.cleanup(session: Session, _reason: string)
	for i = #pending, 1, -1 do
		if pending[i].owner == session then
			table.remove(pending, i)
		end
	end
	session.abilityState.blink = nil
end

-- Tests / debug.
function Blink.pendingCount(): number
	return #pending
end

return (Blink :: any) :: Types.AbilityModule
