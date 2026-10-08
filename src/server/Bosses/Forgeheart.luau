--!strict
-- FORGEHEART (rank II, phase 7A): a huge cartoon lava golem. Round
-- boulders, glowing cracks, a burning heart, a goofy mouth; strong, clumsy
-- and hot-headed. Harder than the Void Warden (more Health, shorter breaks,
-- lingering lava) but every danger is drawn first and announced at least
-- 1.2 s before it can hurt (3 s for the special):
--
--   volcanic_hammer  "Marteau volcanique": a slam in front of him (all around
--                    him when nobody is close). Phase 3: a shockwave ring
--                    rolls out of the impact. Step out / JUMP.
--   lava_blobs       "Boulettes de lave": lobbed balls land on marked circles
--                    and leave a burning puddle for a moment.
--   burning_floor    "Sol brûlant": cracks glow yellow, then that floor burns
--                    red for a few seconds (under and around the fighters).
--   meteor_shower    "Pluie de météores": meteors fall one after another on
--                    circles that are all marked from the start.
--   final_eruption   Special (phase 2+): he jumps to the centre and the whole
--                    floor erupts except every other cooled-rock pad (always
--                    one within reach). Phase 3: a second eruption on the
--                    other pads. He ends up out of breath (dizzy).
--
-- Like every boss module, it only PLANS: BossService resolves the damage
-- shapes against the server's view and sends the payload to the clients.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Bosses = require(ReplicatedStorage.Shared.Config.Bosses)
local BossTypes = require(script.Parent.BossTypes)

type Plan = BossTypes.Plan
type Shape = BossTypes.Shape
type FightView = BossTypes.FightView

local Forgeheart = {}

local def = Bosses.get("Forgeheart") :: Bosses.BossDef

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

local function shuffled(view: FightView, list: { Vector3 }): { Vector3 }
	local copy = table.clone(list)
	for i = #copy, 2, -1 do
		local j = view.rng:NextInteger(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

local function crowdBonus(view: FightView): number
	return math.min(math.max(view.participants - 1, 0), 3)
end

local function attackDef(id: string): Bosses.AttackDef
	return def.attacks[id]
end

-- Spots around the targets first, then random free ones (never stacked).
local function spreadSpots(view: FightView, count: number, radius: number, jitter: number): { Vector3 }
	local spots: { Vector3 } = {}
	for _, target in shuffled(view, view.targets) do
		if #spots >= count then
			break
		end
		local angle = view.rng:NextNumber() * math.pi * 2
		local r = view.rng:NextNumber() * jitter
		table.insert(spots, clampInside(view, target + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r), radius + 1))
	end
	local attempts = 0
	while #spots < count and attempts < count * 10 do
		attempts += 1
		local p = randomPoint(view, radius + 1)
		local free = true
		for _, other in spots do
			if (other - p).Magnitude < radius * 1.7 then
				free = false
				break
			end
		end
		if free then
			table.insert(spots, p)
		end
	end
	return spots
end

-- Slam in front of him (toward the nearest fighter) or all around him.
local function volcanicHammer(view: FightView, now: number): Plan
	local attack = attackDef("volcanic_hammer")
	local t = attack.tuning
	local boss = flat(view, view.bossPosition)
	local nearest: Vector3? = nil
	local best = math.huge
	for _, target in view.targets do
		local d = (flat(view, target) - boss).Magnitude
		if d < best then
			best, nearest = d, target
		end
	end
	local center = boss
	local radius = t.poundRadius
	if nearest and best <= t.maxDistance and best > 0.5 then
		local dir = (flat(view, nearest) - boss).Unit
		center = clampInside(view, boss + dir * math.clamp(best, def.radius + 2, t.reach), t.radius)
		radius = t.radius
	end
	local hitAt = now + attack.telegraph
	local shapes: { Shape } = { { kind = "circle", at = hitAt, center = center, radius = radius } }
	local wave = view.phase >= 3
	if wave then
		table.insert(shapes, { kind = "ring", at = hitAt + 0.25, center = center, radius = t.waveReach, speed = t.waveSpeed, band = t.band })
	end
	return {
		id = attack.id,
		action = "Slam",
		telegraphAt = now,
		hitAt = hitAt,
		endsAt = hitAt + (if wave then 1.6 else 0.7),
		shapes = shapes,
		payload = {
			center = center,
			radius = radius,
			hitAt = hitAt,
			wave = if wave then { startAt = hitAt + 0.25, speed = t.waveSpeed, band = t.band, maxRadius = t.waveReach } else nil,
		},
	}
end

-- Lobbed lava balls: marked circles, then a burning puddle for a moment.
local function lavaBlobs(view: FightView, now: number): Plan
	local attack = attackDef("lava_blobs")
	local t = attack.tuning
	local count = t.count + t.extraPerPhase * (view.phase - 1) + crowdBonus(view)
	local spots = spreadSpots(view, count, t.radius, t.spread)
	local launchAt = now + 0.3
	local lands: { number } = {}
	local shapes: { Shape } = {}
	for i, spot in spots do
		local landAt = now + attack.telegraph + (i - 1) * 0.12
		table.insert(lands, landAt)
		table.insert(shapes, { kind = "circle", at = landAt, center = spot, radius = t.radius })
		-- The puddle starts burning a beat after the splash (no double hit).
		table.insert(shapes, { kind = "burn", at = landAt + 0.4, untilTime = landAt + 0.4 + t.linger, center = spot, radius = t.radius * 0.8 })
	end
	return {
		id = attack.id,
		action = "Lob",
		telegraphAt = now,
		hitAt = now + attack.telegraph,
		endsAt = lands[#lands] + 0.6,
		shapes = shapes,
		payload = { from = view.bossPosition + Vector3.new(0, def.height + 4, 0), spots = spots, lands = lands, launchAt = launchAt, radius = t.radius, puddle = t.radius * 0.8, linger = t.linger },
	}
end

-- Cracks under and around the fighters, then burning floor for a while.
local function burningFloor(view: FightView, now: number): Plan
	local attack = attackDef("burning_floor")
	local t = attack.tuning
	local count = t.count + t.extraPerPhase * (view.phase - 1) + math.min(crowdBonus(view), 2)
	local spots = spreadSpots(view, count, t.radius, 6)
	local hitAt = now + attack.telegraph
	local untilTime = hitAt + t.duration
	local shapes: { Shape } = {}
	for _, spot in spots do
		table.insert(shapes, { kind = "burn", at = hitAt, untilTime = untilTime, center = spot, radius = t.radius })
	end
	return {
		id = attack.id,
		action = "Stomp",
		telegraphAt = now,
		hitAt = hitAt,
		-- He can attack again while the floor still burns (pressure, not a wall).
		endsAt = hitAt + 1.2,
		shapes = shapes,
		payload = { spots = spots, radius = t.radius, hitAt = hitAt, untilTime = untilTime },
	}
end

-- Meteors one after another, every circle marked from the start.
local function meteorShower(view: FightView, now: number): Plan
	local attack = attackDef("meteor_shower")
	local t = attack.tuning
	local count = t.count + t.extraPerPhase * (view.phase - 1) + crowdBonus(view)
	local spots = spreadSpots(view, count, t.radius, 7)
	local lands: { number } = {}
	local shapes: { Shape } = {}
	for i, spot in spots do
		local landAt = now + attack.telegraph + (i - 1) * t.interval
		table.insert(lands, landAt)
		table.insert(shapes, { kind = "circle", at = landAt, center = spot, radius = t.radius })
	end
	return {
		id = attack.id,
		action = "Roar",
		telegraphAt = now,
		hitAt = now + attack.telegraph,
		endsAt = lands[#lands] + 0.5,
		shapes = shapes,
		payload = { spots = spots, lands = lands, radius = t.radius },
	}
end

-- Special: the floor erupts except every other cooled-rock pad.
local function finalEruption(view: FightView, now: number): Plan
	local attack = attackDef("final_eruption")
	local t = attack.tuning
	local center = flat(view, view.center)
	local pads = Bosses.arenaPads(def)
	local padRadius = def.padRadius or 8
	local parity = view.rng:NextInteger(0, 1)
	local hitAt = now + attack.telegraph
	local waves = { { parity = parity, at = hitAt } }
	if view.phase >= 3 then
		table.insert(waves, { parity = 1 - parity, at = hitAt + t.second })
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
		action = "Erupt",
		telegraphAt = now,
		hitAt = hitAt,
		endsAt = last + 0.4 + t.dizzy,
		shapes = shapes,
		motion = { from = view.bossPosition, to = center + Vector3.new(0, def.height, 0), startAt = now + 0.25, endAt = now + 0.95, height = 16 },
		dizzyAt = last + 0.4,
		dizzyFor = t.dizzy,
		payload = { center = center, waves = payloadWaves, padRadius = padRadius, dizzyAt = last + 0.4, dizzyFor = t.dizzy },
	}
end

local PLANNERS: { [string]: (FightView, number) -> Plan } = {
	volcanic_hammer = volcanicHammer,
	lava_blobs = lavaBlobs,
	burning_floor = burningFloor,
	meteor_shower = meteorShower,
	final_eruption = finalEruption,
}

for attackId in def.attacks do
	assert(PLANNERS[attackId], "Forgeheart has no planner for " .. attackId)
end

function Forgeheart.plan(view: FightView, attackId: string, now: number): Plan
	local planner = PLANNERS[attackId] or volcanicHammer
	return planner(view, now)
end

return Forgeheart
