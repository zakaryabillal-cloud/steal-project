--!strict
-- Decoy (Utility): a fake copy of the caster runs ahead in a straight line,
-- at the caster's current walk speed, showing the relics they carry.
--
-- It has NO gameplay authority: there is no server instance at all. The
-- server keeps a record {origin, direction, length, speed, start, end} and
-- every client draws the copy from the broadcast. It cannot carry, drop,
-- steal, deposit or be stolen from, so nothing (relic, Essence, state) can
-- ever be duplicated through it. The path is computed by the server (stops
-- before walls and ledges).
--
-- Counterplay: any control ability (Pulse, Eruption, Frost Wave, a rune trap)
-- reaching it pops it; the Cosmic Eye harmony reveals it within range and
-- pops it on touch.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local Core = script.Parent.Parent.Core
local Types = require(Core.Types)
local Remotes = require(Core.Remotes)
local Sessions = require(Core.Sessions)
local Services = script.Parent.Parent.Services
local RelicService = require(Services.RelicService)
local Common = require(script.Parent.Common)

type Session = Types.Session

export type Record = {
	id: number,
	owner: Session,
	origin: Vector3,
	direction: Vector3,
	length: number,
	speed: number,
	startAt: number,
	endAt: number,
	-- Sessions it was already revealed to (Cosmic Eye).
	revealed: { [Session]: boolean },
}

local EYE = GameConfig.Harmonies.CosmicEye

local Decoy = {}

local records: { [number]: Record } = {}
local nextId = 0

function Decoy.readPayload(raw: any): any
	-- Optional direction; anything unusable falls back to the facing.
	return { direction = Common.readDirection(raw) }
end

-- Server-side path: straight ahead, stops 2 studs before a wall or where the
-- ground drops more than a step (a decoy never runs off a cliff).
local function pathLength(session: Session, origin: Vector3, direction: Vector3, maxLength: number): number
	local params = Common.params(session)
	local wall = Common.cast(origin, direction * (maxLength + 2), params)
	local length = if wall then math.max(0, wall.Distance - 2) else maxLength
	local step = 2
	local d = step
	local lastY: number? = nil
	while d <= length do
		local ground = Common.ground(origin + direction * d, 7, params)
		if not ground then
			return math.max(0, d - step)
		end
		if lastY and math.abs(ground.Position.Y - lastY) > 3.5 then
			return math.max(0, d - step)
		end
		lastY = ground.Position.Y
		d += step
	end
	return length
end

local function remove(record: Record, how: string, position: Vector3?)
	if records[record.id] ~= record then
		return
	end
	records[record.id] = nil
	if record.owner.abilityState.decoy == record.id then
		record.owner.abilityState.decoy = nil
	end
	Remotes.fx("DecoyEnd", { id = record.id, how = how, position = position })
end

function Decoy.position(record: Record, now: number): Vector3
	local travelled = math.clamp((now - record.startAt) * record.speed, 0, record.length)
	return record.origin + record.direction * travelled
end

function Decoy.activate(ctx: Types.AbilityContext)
	local session = ctx.session
	local tuning = ctx.tuning
	local previous = session.abilityState.decoy
	if previous and records[previous] then
		remove(records[previous], "replaced", nil)
	end
	local _, humanoid = Sessions.character(session)
	local speed = math.max(tuning.MinSpeed, if humanoid then humanoid.WalkSpeed else tuning.MinSpeed)
	local direction = ctx.payload.direction or Common.facing(ctx.root)
	local origin = ctx.root.Position
	local length = pathLength(session, origin, direction, math.min(tuning.MaxLength, speed * tuning.Duration))
	nextId += 1
	local record: Record = {
		id = nextId,
		owner = session,
		origin = origin,
		direction = direction,
		length = length,
		speed = speed,
		startAt = ctx.now,
		endAt = ctx.now + tuning.Duration,
		revealed = {},
	}
	records[record.id] = record
	session.abilityState.decoy = record.id
	-- Visual copy of what the caster carries (display data only).
	local relics = {}
	for _, uid in session.carrying do
		local entity = RelicService.get(uid)
		if entity then
			table.insert(relics, { id = entity.id, rarity = entity.rarity, level = entity.level, mutation = entity.mutation or "", stolenFrom = entity.stolenFrom or 0 })
		end
	end
	Remotes.fx("Decoy", {
		id = record.id,
		userId = session.userId,
		origin = origin,
		direction = direction,
		length = length,
		speed = speed,
		startAt = record.startAt,
		endAt = record.endAt,
		relics = relics,
	})
end

-- Pops every decoy (any owner but `except`) within `radius` of `position`.
-- Returns how many were popped.
function Decoy.popNear(position: Vector3, radius: number, except: Session?): number
	local t = workspace:GetServerTimeNow()
	local count = 0
	for _, record in table.clone(records) do
		if record.owner == except then
			continue
		end
		local at = Decoy.position(record, t)
		if (at - position).Magnitude <= radius + GameConfig.Abilities.Decoy.PopRadius then
			remove(record, "popped", at)
			count += 1
		end
	end
	return count
end

function Decoy.tick(now: number)
	local holders: { { session: Session, root: BasePart } }? = nil
	for _, record in table.clone(records) do
		if record.owner.released or now >= record.endAt then
			remove(record, "expired", Decoy.position(record, now))
			continue
		end
		-- Cosmic Eye: reveal within range, pop on touch.
		if holders == nil then
			holders = {}
			for _, session in Sessions.all() do
				if Common.hasHarmony(session, "cosmic_eye") then
					local root = Common.root(session)
					if root then
						table.insert(holders :: any, { session = session, root = root })
					end
				end
			end
		end
		local at = Decoy.position(record, now)
		for _, holder in holders :: { { session: Session, root: BasePart } } do
			if holder.session == record.owner then
				continue
			end
			local distance = (holder.root.Position - at).Magnitude
			if distance <= EYE.TouchPopRadius then
				remove(record, "popped", at)
				break
			end
			if distance <= EYE.RevealRadius and not record.revealed[holder.session] then
				record.revealed[holder.session] = true
				Remotes.fxTo(holder.session.player, "Reveal", { decoy = record.id })
			end
		end
	end
end

function Decoy.cleanup(session: Session, reason: string)
	local id = session.abilityState.decoy
	if id and records[id] then
		local record = records[id]
		remove(record, reason, Decoy.position(record, workspace:GetServerTimeNow()))
	end
	session.abilityState.decoy = nil
	-- Belt and braces: no record may outlive its owner.
	if reason == "leave" then
		for _, record in table.clone(records) do
			if record.owner == session then
				remove(record, reason, nil)
			end
		end
	end
end

-- Tests / debug.
function Decoy.active(): { Record }
	local list = {}
	for _, record in records do
		table.insert(list, record)
	end
	return list
end

return (Decoy :: any) :: Types.AbilityModule
