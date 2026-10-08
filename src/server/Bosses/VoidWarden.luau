--!strict
-- VOID WARDEN (rank I): the grumpy janitor of the Rift. A big purple jelly
-- cube with a cap and a giant broom who hates mess (and you are the mess).
--
-- This module only PLANS attacks (positions, timings, shapes); BossService
-- resolves the damage and the clients draw the telegraphs. Every attack is
-- one readable shape with its own colour on the client, and is announced at
-- least Config/Bosses Combat.MinTelegraph seconds before it can hurt
-- (1.2 s for the big special):
--
--   broom_wave    "Coup de balai": a ring of dust rolls out. JUMP over it.
--                 Phase 3: two rings in a row.
--   goo_puddles   "Flaques collantes": circles fill yellow -> red, then
--                 SPLAT; the goo stays a few seconds and slows.
--   dust_bunnies  "Moutons de poussière": lobbed in an arc, landing marks
--                 show where. Move away.
--   belly_flop    Hop: a shadow grows where he lands. He cannot be hit in
--                 the air.
--   big_cleanup   Special (phase 2+) "Grand Ménage": he hops to the centre
--                 and mops three quarters of the arena; one sparkling quarter
--                 is safe. Phase 3: a second sweep, another safe quarter.
--                 He ends up dizzy (bonus damage).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Bosses = require(ReplicatedStorage.Shared.Config.Bosses)
local BossTypes = require(script.Parent.BossTypes)

type Plan = BossTypes.Plan
type Shape = BossTypes.Shape
type FightView = BossTypes.FightView

local VoidWarden = {}

local def = Bosses.get("VoidWarden") :: Bosses.BossDef

local function flat(view: FightView, p: Vector3): Vector3
	return Vector3.new(p.X, view.floorY, p.Z)
end

-- Keeps a floor point at least `margin` studs inside the arena edge.
local function clampInside(view: FightView, p: Vector3, margin: number): Vector3
	local c = view.center
	local offset = Vector3.new(p.X - c.X, 0, p.Z - c.Z)
	local limit = math.max(1, view.radius - margin)
	if offset.Magnitude > limit then
		offset = offset.Unit * limit
	end
	return Vector3.new(c.X + offset.X, view.floorY, c.Z + offset.Z)
end

local function randomPoint(view: FightView, margin: number): Vector3
	local angle = view.rng:NextNumber() * math.pi * 2
	local r = math.sqrt(view.rng:NextNumber()) * math.max(1, view.radius - margin)
	return Vector3.new(view.center.X + math.cos(angle) * r, view.floorY, view.center.Z + math.sin(angle) * r)
end

local function shuffled(view: FightView, list: { Vector3 }): { Vector3 }
	local copy = table.clone(list)
	for i = #copy, 2, -1 do
		local j = view.rng:NextInteger(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

-- Extra hazards for bigger groups (difficulty follows the participants).
local function crowdBonus(view: FightView): number
	return math.min(math.max(view.participants - 1, 0), 3)
end

local function attackDef(id: string): Bosses.AttackDef
	return def.attacks[id]
end

-- Ground ring(s) from the boss: jump over.
local function broomWave(view: FightView, now: number): Plan
	local attack = attackDef("broom_wave")
	local t = attack.tuning
	local origin = flat(view, view.bossPosition)
	local speed = t.speed + t.speedPerPhase * (view.phase - 1)
	local reach = view.radius + 6 + (origin - flat(view, view.center)).Magnitude
	local hitAt = now + attack.telegraph
	local starts = { hitAt }
	if view.phase >= 3 then
		table.insert(starts, hitAt + 1.1)
	end
	local shapes: { Shape } = {}
	for _, startAt in starts do
		table.insert(shapes, { kind = "ring", at = startAt, center = origin, radius = reach, speed = speed, band = t.band })
	end
	return {
		id = attack.id,
		action = "Sweep",
		telegraphAt = now,
		hitAt = hitAt,
		endsAt = starts[#starts] + reach / speed,
		shapes = shapes,
		payload = { origin = origin, starts = starts, speed = speed, band = t.band, maxRadius = reach },
	}
end

-- Sticky puddles under the fighters (and a few random ones).
local function gooPuddles(view: FightView, now: number): Plan
	local attack = attackDef("goo_puddles")
	local t = attack.tuning
	local count = t.count + t.extraPerPhase * (view.phase - 1) + crowdBonus(view)
	local radius = t.radius
	local spots: { Vector3 } = {}
	for _, target in shuffled(view, view.targets) do
		if #spots >= count then
			break
		end
		table.insert(spots, clampInside(view, target, radius + 1))
	end
	local attempts = 0
	while #spots < count and attempts < count * 8 do
		attempts += 1
		local p = randomPoint(view, radius + 1)
		local free = true
		for _, other in spots do
			if (other - p).Magnitude < radius * 1.6 then
				free = false
				break
			end
		end
		if free then
			table.insert(spots, p)
		end
	end
	local hitAt = now + attack.telegraph
	local shapes: { Shape } = {}
	for _, spot in spots do
		table.insert(shapes, { kind = "circle", at = hitAt, center = spot, radius = radius })
		table.insert(shapes, { kind = "zone", at = hitAt, untilTime = hitAt + t.linger, center = spot, radius = radius, slow = t.slow })
	end
	return {
		id = attack.id,
		action = "Splat",
		telegraphAt = now,
		hitAt = hitAt,
		endsAt = hitAt + 0.8,
		shapes = shapes,
		payload = { spots = spots, radius = radius, hitAt = hitAt, untilTime = hitAt + t.linger },
	}
end

-- Lobbed dust bunnies with landing marks.
local function dustBunnies(view: FightView, now: number): Plan
	local attack = attackDef("dust_bunnies")
	local t = attack.tuning
	local count = t.count + t.extraPerPhase * (view.phase - 1) + crowdBonus(view)
	local spots: { Vector3 } = {}
	local targets = shuffled(view, view.targets)
	for i = 1, count do
		local target = targets[((i - 1) % math.max(#targets, 1)) + 1]
		local p: Vector3
		if target and i <= #targets * 2 then
			local angle = view.rng:NextNumber() * math.pi * 2
			local r = if i <= #targets then view.rng:NextNumber() * 2 else t.spread * (0.5 + view.rng:NextNumber() * 0.5)
			p = target + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
		else
			p = randomPoint(view, t.radius + 1)
		end
		table.insert(spots, clampInside(view, p, t.radius))
	end
	local launchAt = now + 0.25
	local lands: { number } = {}
	local shapes: { Shape } = {}
	for i, spot in spots do
		local landAt = now + attack.telegraph + (i - 1) * 0.15
		table.insert(lands, landAt)
		table.insert(shapes, { kind = "circle", at = landAt, center = spot, radius = t.radius })
	end
	return {
		id = attack.id,
		action = "Throw",
		telegraphAt = now,
		hitAt = now + attack.telegraph,
		endsAt = lands[#lands] + 0.5,
		shapes = shapes,
		payload = { from = view.bossPosition + Vector3.new(0, def.height + 2, 0), spots = spots, lands = lands, launchAt = launchAt, radius = t.radius },
	}
end

-- Hop onto a fighter: the shadow grows where he lands.
local function bellyFlop(view: FightView, now: number): Plan
	local attack = attackDef("belly_flop")
	local t = attack.tuning
	local targets = view.targets
	local target = if #targets > 0 then targets[view.rng:NextInteger(1, #targets)] else randomPoint(view, def.radius + 2)
	local landing = clampInside(view, target, def.radius + 2)
	local from = view.bossPosition
	local to = landing + Vector3.new(0, def.height, 0)
	local landAt = now + attack.telegraph
	return {
		id = attack.id,
		action = "Hop",
		telegraphAt = now,
		hitAt = landAt,
		endsAt = landAt + 0.6,
		shapes = { { kind = "circle", at = landAt, center = landing, radius = t.radius } },
		motion = { from = from, to = to, startAt = now + 0.35, endAt = landAt, height = t.height },
		payload = { from = from, to = to, startAt = now + 0.35, landAt = landAt, radius = t.radius, height = t.height },
	}
end

-- Special: mop three quarters of the arena; one quarter sparkles (safe).
local function bigCleanup(view: FightView, now: number): Plan
	local attack = attackDef("big_cleanup")
	local t = attack.tuning
	local center = flat(view, view.center)
	local from = view.bossPosition
	local to = center + Vector3.new(0, def.height, 0)
	local hitAt = now + attack.telegraph
	local first = view.rng:NextInteger(0, 3)
	local sweeps = { { safe = first, at = hitAt } }
	if view.phase >= 3 then
		local second = (first + view.rng:NextInteger(1, 3)) % 4
		table.insert(sweeps, { safe = second, at = hitAt + 1.6 })
	end
	local shapes: { Shape } = {}
	local payloadSweeps = {}
	for _, sweep in sweeps do
		local safeAngle = sweep.safe * math.pi / 2
		table.insert(shapes, { kind = "sector", at = sweep.at, center = center, radius = view.radius + 10, safeAngle = safeAngle, safeWidth = math.pi / 2 })
		table.insert(payloadSweeps, { safeAngle = safeAngle, at = sweep.at })
	end
	local last = sweeps[#sweeps].at
	return {
		id = attack.id,
		action = "Spin",
		telegraphAt = now,
		hitAt = hitAt,
		endsAt = last + 0.3 + t.dizzy,
		shapes = shapes,
		motion = { from = from, to = to, startAt = now + 0.2, endAt = now + 0.8, height = 14 },
		dizzyAt = last + 0.3,
		dizzyFor = t.dizzy,
		payload = { center = center, sweeps = payloadSweeps, safeWidth = math.pi / 2, radius = view.radius, dizzyAt = last + 0.3, dizzyFor = t.dizzy },
	}
end

local PLANNERS: { [string]: (FightView, number) -> Plan } = {
	broom_wave = broomWave,
	goo_puddles = gooPuddles,
	dust_bunnies = dustBunnies,
	belly_flop = bellyFlop,
	big_cleanup = bigCleanup,
}

for attackId in def.attacks do
	assert(PLANNERS[attackId], "VoidWarden has no planner for " .. attackId)
end

function VoidWarden.plan(view: FightView, attackId: string, now: number): Plan
	local planner = PLANNERS[attackId] or broomWave
	return planner(view, now)
end

return VoidWarden
