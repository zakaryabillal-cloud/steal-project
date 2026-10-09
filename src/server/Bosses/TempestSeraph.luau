--!strict
-- TEMPEST SERAPH (rank III, phase 7B): a cartoon thunder-cloud diva. A
-- puffy cloud with big eyes, a crooked golden crown, tiny wings and yellow
-- zig-zag bolts; smug, dramatic, never scary. Harder than Forgeheart (more
-- Health, shorter breaks, moving hazards) but every danger is drawn first
-- and announced at least 1.4 s before it can hurt (3.2 s for the special):
--
--   targeted_bolt      "Éclair ciblé": a reticle FOLLOWS a fighter, LOCKS
--                      (stops; "BossLock" FX) and the bolt strikes 0.6 s
--                      later. Phase 1: 1 (+1 per extra fighter, max +2);
--                      phase 2+: one per target; phase 3: a second volley.
--   dancing_tornadoes  "Tornades dansantes": every path is drawn from the
--                      warning; the tornadoes appear at the impact time and
--                      dance along it, slower than walking. Too tall to jump.
--   sky_gust           "Rafale céleste": a wind front sweeps the arena along
--                      one of 8 directions; only the 3 calm lanes are safe.
--   chain_lightning    "Chaîne électrique": nodes under the fighters (then
--                      free spots) linked in a chain by arcs; nodes AND arcs
--                      zap. Fighters bunched up share arcs: spread out!
--   mega_storm         Special (phase 2+): she rises to the centre and the
--                      whole arena is struck except every other cloud shelter
--                      (lit). Phase 3: two more strikes alternating the lit
--                      shelters. Then she is dazed (dizzy, bonus damage).
--
-- Like every boss module, it only PLANS: BossService resolves the damage
-- shapes against the server's view (Bosses/BossTypes documents the new
-- tracked circle, path, sweep and chain shapes) and sends the payload to the
-- clients, which draw exactly what the server resolves (same formulas:
-- Config/Bosses pathPosition / sweepFront / sweepSide / segmentDistance).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Bosses = require(ReplicatedStorage.Shared.Config.Bosses)
local BossTypes = require(script.Parent.BossTypes)

type Plan = BossTypes.Plan
type Shape = BossTypes.Shape
type FightView = BossTypes.FightView

local TempestSeraph = {}

local def = Bosses.get("TempestSeraph") :: Bosses.BossDef

-- Bolt reticle keys ("BossLock" FX) are unique on this server.
local serial = 0

local function flat(view: FightView, p: Vector3): Vector3
	return Vector3.new(p.X, view.floorY, p.Z)
end

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

-- A random point at least `spacing` studs from every point of `others`
-- (best effort: the last try is kept when the arena is crowded).
local function freePoint(view: FightView, margin: number, others: { Vector3 }, spacing: number): Vector3
	local p = randomPoint(view, margin)
	for _ = 1, 12 do
		local free = true
		for _, other in others do
			if (Vector3.new(other.X, 0, other.Z) - Vector3.new(p.X, 0, p.Z)).Magnitude < spacing then
				free = false
				break
			end
		end
		if free then
			return p
		end
		p = randomPoint(view, margin)
	end
	return p
end

-- Indices 1..n in a random order.
local function shuffledIndices(view: FightView, n: number): { number }
	local order = {}
	for i = 1, n do
		order[i] = i
	end
	for i = n, 2, -1 do
		local j = view.rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	return order
end

local function crowdBonus(view: FightView): number
	return math.min(math.max(view.participants - 1, 0), 3)
end

local function attackDef(id: string): Bosses.AttackDef
	return def.attacks[id]
end

-- "Éclair ciblé": reticles follow their fighter, lock, then strike.
local function targetedBolt(view: FightView, now: number): Plan
	local attack = attackDef("targeted_bolt")
	local t = attack.tuning
	local hitAt = now + attack.telegraph
	local lockAt = now + t.track
	local ids = view.targetIds
	local order = shuffledIndices(view, #view.targets)
	-- Phase 1: 1 (+1 per extra fighter, max +2); phase 2+: one per target.
	local count = if view.phase >= 2 then #order else math.min(#order, 1 + math.min(crowdBonus(view), 2))
	-- Phase 3: `extraPerPhase` more volley(s) on the same fighters.
	local volleys = 1 + (if view.phase >= 3 then t.extraPerPhase else 0)
	local gap = t.volleyGap or 0.5
	serial += 1
	local shapes: { Shape } = {}
	local bolts = {}
	local function add(center: Vector3, track: number?, volley: number)
		local delay = (volley - 1) * gap
		local key = string.format("ts%d_%d", serial, #bolts + 1)
		local at = hitAt + delay
		local lock = lockAt + delay
		table.insert(shapes, { kind = "circle", at = at, center = center, radius = t.radius, track = track, lockAt = lock, key = key })
		table.insert(bolts, { key = key, center = center, track = track, lockAt = lock, at = at, volley = volley })
	end
	for volley = 1, volleys do
		if count == 0 then
			-- Nobody to aim at (only happens in tests): one bolt somewhere.
			add(randomPoint(view, t.radius + 1), nil, volley)
		end
		for k = 1, count do
			local index = order[k]
			local id = if ids then ids[index] or 0 else 0
			add(clampInside(view, view.targets[index], 0), if id > 0 then id else nil, volley)
		end
	end
	local last = bolts[#bolts].at
	return {
		id = attack.id,
		action = "Zap",
		telegraphAt = now,
		hitAt = hitAt,
		endsAt = last + 0.5,
		shapes = shapes,
		payload = { bolts = bolts, radius = t.radius, track = t.track, hitAt = hitAt, volleys = volleys },
	}
end

-- One step of `step` studs from `from` toward `angle`, kept inside the arena;
-- turns toward the centre when the wall would make the step too short.
local function stepFrom(view: FightView, from: Vector3, angle: number, step: number, margin: number): Vector3
	local p = clampInside(view, from + Vector3.new(math.cos(angle), 0, math.sin(angle)) * step, margin)
	if (p - from).Magnitude < step * 0.5 then
		local inward = Vector3.new(view.center.X - from.X, 0, view.center.Z - from.Z)
		if inward.Magnitude > 1 then
			p = clampInside(view, from + inward.Unit * step, margin)
		end
	end
	return p
end

-- "Tornades dansantes": drawn paths, walked slower than a player walks.
local function dancingTornadoes(view: FightView, now: number): Plan
	local attack = attackDef("dancing_tornadoes")
	local t = attack.tuning
	local count = t.count + t.extraPerPhase * (view.phase - 1) + math.min(crowdBonus(view), 2)
	local margin = t.radius + 2
	local hitAt = now + attack.telegraph
	local targets = view.targets
	local targetOrder = shuffledIndices(view, #targets)
	local starts: { Vector3 } = {}
	local shapes: { Shape } = {}
	local tornadoes = {}
	local lastEnd = hitAt
	for i = 1, count do
		local start = freePoint(view, margin, starts, t.radius * 3)
		table.insert(starts, start)
		local points: { Vector3 } = { start }
		local n = view.rng:NextInteger(3, 4)
		for k = 2, n do
			local from = points[#points]
			local nextPoint: Vector3
			if k == 2 and #targets > 0 then
				-- The dance goes through (near) a fighter: everyone has to move.
				local target = targets[targetOrder[((i - 1) % #targets) + 1]]
				local angle = view.rng:NextNumber() * math.pi * 2
				nextPoint = clampInside(view, target + Vector3.new(math.cos(angle), 0, math.sin(angle)) * view.rng:NextNumber() * 6, margin)
				if (nextPoint - from).Magnitude < 8 then
					nextPoint = stepFrom(view, from, angle, 14, margin)
				end
			else
				nextPoint = stepFrom(view, from, view.rng:NextNumber() * math.pi * 2, 12 + view.rng:NextNumber() * 14, margin)
			end
			table.insert(points, nextPoint)
		end
		local length = Bosses.pathLength(points)
		-- Never faster than `speed` (slower than walking), never shorter than minDuration.
		local duration = math.max(t.minDuration or 2.5, length / t.speed)
		local endAt = hitAt + duration
		lastEnd = math.max(lastEnd, endAt)
		table.insert(shapes, { kind = "path", at = hitAt, untilTime = endAt, center = start, radius = t.radius, points = points, height = t.height })
		table.insert(tornadoes, { points = points, startAt = hitAt, endAt = endAt })
	end
	return {
		id = attack.id,
		action = "Twirl",
		telegraphAt = now,
		hitAt = hitAt,
		endsAt = lastEnd + 0.2,
		shapes = shapes,
		payload = { tornadoes = tornadoes, radius = t.radius, height = t.height, speed = t.speed, hitAt = hitAt },
	}
end

-- "Rafale céleste": a wind front crosses the arena; calm lanes are safe.
local function skyGust(view: FightView, now: number): Plan
	local attack = attackDef("sky_gust")
	local t = attack.tuning
	local speed = if view.phase >= 3 then t.speedPhase3 else t.speed
	local angle = view.rng:NextInteger(0, 7) * math.pi / 4
	local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local side = Bosses.sweepSide(dir)
	local jitter = t.jitter or 3
	local lanes: { Bosses.Lane } = {}
	for k = -1, 1 do
		table.insert(lanes, { offset = k * t.laneSpacing + (view.rng:NextNumber() * 2 - 1) * jitter, width = t.laneWidth })
	end
	local hitAt = now + attack.telegraph
	local radius = view.radius
	-- The front starts just outside the arena edge at hitAt.
	local start = -(radius + (t.startBeyond or 6))
	local endAt = hitAt + (radius + t.band - start) / speed
	local center = flat(view, view.center)
	return {
		id = attack.id,
		action = "Blow",
		telegraphAt = now,
		hitAt = hitAt,
		endsAt = endAt + 0.2,
		shapes = {
			{ kind = "sweep", at = hitAt, untilTime = endAt, center = center, radius = radius, dir = dir, start = start, speed = speed, band = t.band, lanes = lanes },
		},
		payload = { center = center, dir = dir, side = side, start = start, speed = speed, band = t.band, lanes = lanes, radius = radius, hitAt = hitAt, endAt = endAt },
	}
end

-- "Chaîne électrique": nodes under the fighters, then free spots, linked
-- nearest-first into one chain.
local function chainLightning(view: FightView, now: number): Plan
	local attack = attackDef("chain_lightning")
	local t = attack.tuning
	local count = t.count + t.extraPerPhase * (view.phase - 1)
	local margin = t.radius + 1
	local nodes: { Vector3 } = {}
	for _, index in shuffledIndices(view, #view.targets) do
		if #nodes >= count then
			break
		end
		table.insert(nodes, clampInside(view, view.targets[index], margin))
	end
	while #nodes < count do
		table.insert(nodes, freePoint(view, margin, nodes, t.radius * 3))
	end
	-- Nearest-neighbour order: a readable chain instead of a criss-cross.
	local points: { Vector3 } = { table.remove(nodes, 1) :: Vector3 }
	while #nodes > 0 do
		local last = points[#points]
		local best, bestIndex = math.huge, 1
		for index, node in nodes do
			local d = (node - last).Magnitude
			if d < best then
				best, bestIndex = d, index
			end
		end
		table.insert(points, table.remove(nodes, bestIndex) :: Vector3)
	end
	local hitAt = now + attack.telegraph
	return {
		id = attack.id,
		action = "Charge",
		telegraphAt = now,
		hitAt = hitAt,
		endsAt = hitAt + 0.8,
		shapes = { { kind = "chain", at = hitAt, center = points[1], radius = t.radius, width = t.width, points = points } },
		payload = { points = points, radius = t.radius, width = t.width, hitAt = hitAt },
	}
end

-- Special: the whole arena is struck except every other (lit) cloud shelter.
local function megaStorm(view: FightView, now: number): Plan
	local attack = attackDef("mega_storm")
	local t = attack.tuning
	local center = flat(view, view.center)
	local pads = Bosses.arenaPads(def)
	local padRadius = def.padRadius or 8
	local parity = view.rng:NextInteger(0, 1)
	local hitAt = now + attack.telegraph
	local waves = { { parity = parity, at = hitAt } }
	if view.phase >= 3 then
		-- Two more strikes, alternating the lit shelters.
		table.insert(waves, { parity = 1 - parity, at = hitAt + t.second })
		table.insert(waves, { parity = parity, at = hitAt + t.second * 2 })
	end
	local shapes: { Shape } = {}
	local payloadWaves = {}
	for _, wave in waves do
		local safe: { Vector3 } = {}
		local indices: { number } = {}
		for index, pad in pads do
			if (index - 1) % 2 == wave.parity then
				table.insert(safe, pad)
				table.insert(indices, index)
			end
		end
		table.insert(shapes, { kind = "outside", at = wave.at, center = center, radius = view.radius + 10, safeSpots = safe, safeRadius = padRadius })
		table.insert(payloadWaves, { at = wave.at, safe = indices })
	end
	local last = waves[#waves].at
	return {
		id = attack.id,
		action = "Storm",
		telegraphAt = now,
		hitAt = hitAt,
		endsAt = last + 0.4 + t.dizzy,
		shapes = shapes,
		-- She rises (arc) to the arena centre, back at her floating height.
		motion = { from = view.bossPosition, to = center + Vector3.new(0, def.height, 0), startAt = now + 0.25, endAt = now + 1.05, height = 12 },
		dizzyAt = last + 0.4,
		dizzyFor = t.dizzy,
		payload = { center = center, waves = payloadWaves, pads = pads, padRadius = padRadius, dizzyAt = last + 0.4, dizzyFor = t.dizzy },
	}
end

local PLANNERS: { [string]: (FightView, number) -> Plan } = {
	targeted_bolt = targetedBolt,
	dancing_tornadoes = dancingTornadoes,
	sky_gust = skyGust,
	chain_lightning = chainLightning,
	mega_storm = megaStorm,
}

for attackId in def.attacks do
	assert(PLANNERS[attackId], "TempestSeraph has no planner for " .. attackId)
end

function TempestSeraph.plan(view: FightView, attackId: string, now: number): Plan
	local planner = PLANNERS[attackId] or targetedBolt
	return planner(view, now)
end

return TempestSeraph
