--!strict
-- Grapple (Mobility): pull yourself to one of the prepared grapple anchors
-- (WorldFeatures.GrapplePoints, built in phase 2). Nothing else can be
-- grappled.
--
-- The client names an anchor INDEX; the server takes the anchor's position
-- from WorldFeatures (never from the client or a workspace part) and checks
-- range and line of sight from the character's head. The pull itself is
-- applied by the client (client-owned physics) at Speed studs/s, which is
-- below the movement guard threshold: the guard keeps watching the whole
-- flight, nothing is switched off. Any hard control on the grappler cuts the
-- cable (StatusService.controlled).
--
-- Boss arena (phase 6.5): only the 4 floating bubble anchors of the arena
-- (Config/Bosses.ArenaGrapple, indices 101+) can be grappled there, and
-- they cannot be grappled from anywhere else.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WorldFeatures = require(ReplicatedStorage.Shared.WorldFeatures)
local Bosses = require(ReplicatedStorage.Shared.Config.Bosses)

local Core = script.Parent.Parent.Core
local Types = require(Core.Types)
local Remotes = require(Core.Remotes)
local Expeditions = require(Core.Expeditions)
local Services = script.Parent.Parent.Services
local StatusService = require(Services.StatusService)
local Common = require(script.Parent.Common)

type Session = Types.Session

export type Flight = {
	anchor: number,
	from: Vector3,
	to: Vector3,
	startAt: number,
	endAt: number,
	speed: number,
}

local Grapple = {}

local flying: { [Session]: Flight } = {}

function Grapple.readPayload(raw: any): any
	if type(raw) ~= "number" or raw ~= math.floor(raw) or Grapple.anchorPosition(raw) == nil then
		return nil
	end
	return { anchor = raw }
end

-- Anchor position (server truth) or nil.
function Grapple.anchorPosition(index: number): Vector3?
	if index >= Bosses.ArenaGrapple.FirstIndex then
		return Bosses.arenaGrapplePoint(index)
	end
	local spec = WorldFeatures.GrapplePoints[index]
	return if spec then spec.position else nil
end

-- Can `session` (root) grapple anchor `index`? Returns (ok, reason).
function Grapple.check(session: Session, root: BasePart, index: number, tuning: { [string]: any }): (boolean, string?)
	local target = Grapple.anchorPosition(index)
	if not target then
		return false, "noAnchor"
	end
	-- Arena anchors only from inside the arena, world anchors only outside.
	if Expeditions.isAway(session) ~= (index >= Bosses.ArenaGrapple.FirstIndex) then
		return false, "noAnchor"
	end
	local head = root.Position + Vector3.new(0, 1.5, 0)
	local distance = (target - head).Magnitude
	if distance > tuning.Range + tuning.RangeLenience or distance < tuning.MinDistance then
		return false, "range"
	end
	-- Line of sight, stopping just short of the anchor itself.
	local direction = (target - head).Unit
	if not Common.clear(head, target - direction * 1.2, Common.params(session)) then
		return false, "los"
	end
	return true, nil
end

function Grapple.validate(ctx: Types.AbilityContext): (boolean, string?)
	return Grapple.check(ctx.session, ctx.root, ctx.payload.anchor, ctx.tuning)
end

local function finish(session: Session, reason: string)
	if flying[session] then
		flying[session] = nil
		Remotes.fx("GrappleEnd", { userId = session.userId, reason = reason })
	end
	session.abilityState.grapple = nil
end

function Grapple.activate(ctx: Types.AbilityContext)
	local session = ctx.session
	local tuning = ctx.tuning
	local index = ctx.payload.anchor
	local target = Grapple.anchorPosition(index) :: Vector3
	local speed = tuning.Speed * (if Common.isCarrying(session) then tuning.CarryFactor else 1)
	local distance = (target - ctx.root.Position).Magnitude
	local flight: Flight = {
		anchor = index,
		from = ctx.root.Position,
		to = target,
		startAt = ctx.now,
		endAt = ctx.now + distance / speed + tuning.ExtraTime,
		speed = speed,
	}
	flying[session] = flight
	session.abilityState.grapple = index
	Remotes.fx("Grapple", { userId = session.userId, anchor = index, position = target, speed = speed, untilTime = flight.endAt })
end

function Grapple.tick(now: number)
	for session, flight in table.clone(flying) do
		if session.released or now >= flight.endAt or Common.root(session) == nil then
			flying[session] = nil
			session.abilityState.grapple = nil
		end
	end
end

function Grapple.cleanup(session: Session, reason: string)
	finish(session, reason)
end

-- Tests / debug.
function Grapple.flightOf(session: Session): Flight?
	return flying[session]
end

-- Hard control cuts the cable.
StatusService.controlled:Connect(function(target: Session)
	finish(target, "cut")
end)

return (Grapple :: any) :: Types.AbilityModule
