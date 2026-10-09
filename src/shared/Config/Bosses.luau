--!strict
-- Boss catalogue and expedition rules (V2 phase 6). Shared by the server
-- (authority: portal, fight, damage, loot) and the client (portal card,
-- exact loot probabilities, boss HUD, Codex). Formulas live here as pure
-- functions so both sides always agree.
--
-- To add a boss (phase 7+): one entry in `list` (stats, phases, attacks,
-- loot, arena theme), a behaviour module Server/Bosses/<Id>.luau (attack
-- planner), a model Client/Boss/<Id>Model.luau registered in
-- Client/Boss/BossModels, its attack drawings + sounds in Client/Boss/<Id>FX
-- (registered in BossFX), an arena theme in Server/World/ArenaBuilder,
-- "boss.<id>.*" strings and Boss.<Id>.<phase> music slots in Config/Music.
-- Everything else (portal + rotation, arena walls, hearts, strikes, weapons,
-- abilities, rewards, Codex, trophies, HUD) is shared.
--
-- Rotation (phase 7A): the portal cycles through `list` in order (opening n
-- = list[(n - 1) % #list + 1]); the board and the card show the next boss
-- and the one after it. Studio: /rh boss open <id>, /rh boss next <id>.
-- Phase 7B: Void Warden -> Forgeheart -> Tempest Seraph -> Void Warden...
--
-- Power: the Power RECORD gates / recommends the expedition; the CURRENT
-- Power only adds a small capped bonus to strikes against bosses. Nothing
-- here is ever read by PvP code (theft, abilities, protections).

local Relics = require(script.Parent.Relics)
local Cosmetics = require(script.Parent.Cosmetics)
local Materials = require(script.Parent.Materials)

local Bosses = {}

-- Portal on the Boss Plateau ------------------------------------------------
Bosses.Portal = table.freeze({
	-- Seconds after server start before the first opening.
	FirstOpenDelay = 240,
	-- Seconds between two openings (start to start).
	Interval = 600,
	-- The portal stays open (joinable) this long.
	OpenDuration = 60,
	-- Joining requires standing this close to the portal ring (studs).
	JoinRadius = 34,
	-- Everyone in the waiting room pressed "Ready": the fight starts after this.
	ReadyCountdown = 3,
	-- Seconds the boss of the next opening is announced before it opens.
	AnnounceBefore = 30,
})

-- Arena: a floating platform far away from the island (nothing outside can
-- reach it: no PvP interference), dressed by the boss's theme (the Void
-- Warden's janitor closet, Forgeheart's volcanic forge). Built when the
-- portal opens and destroyed after every expedition.
Bosses.Arena = table.freeze({
	Center = Vector3.new(0, 420, 1600),
	-- Walkable floor radius (studs); invisible walls stand just outside.
	Radius = 58,
	WallHeight = 34,
	-- Players arrive on this ring (studs from the centre), on the -Z side.
	SpawnRadius = 44,
	-- Leaving these bounds is not possible normally (walls): it means an
	-- exploit or a physics glitch.
	BoundsMargin = 14,
	BoundsHeight = 70,
	-- Further than this from the centre = teleport exploit: the player is
	-- removed from the expedition (no reward).
	ExploitDistance = 220,
	-- Static part budget of the arena (checked by the tests).
	PartBudget = 200,
})

-- Combat rules shared by every boss ------------------------------------------
Bosses.Combat = table.freeze({
	-- Fight length limit (3 min 30).
	Duration = 210,
	-- Entrance show before the first attack (boss invulnerable).
	Intro = 4,
	-- Victory / defeat show before everyone is sent back.
	Outro = 7,
	-- Every attack is announced at least this long before it can hurt.
	MinTelegraph = 0.8,
	-- Big attacks (specials) at least this long.
	BigTelegraph = 1.2,
	-- Player hearts per fight and invulnerability after a hit.
	Hearts = 4,
	HitInvulnerability = 1.5,
	-- Knockback applied by a hit (studs/s) and the short stun that comes with it.
	Knockback = 46,
	KnockStun = 0.35,
	-- Phase change: the boss is untouchable for this long (reaction show).
	PhaseShow = 2.2,
	-- Removed from the fight when inactive this long (no strike, no move).
	AfkSeconds = 35,
	-- Standing height of a character root above the floor, and how far above
	-- that a root must be to clear a ground wave (a normal jump is ~7.6).
	RootHeight = 3,
	JumpClear = 2.2,
	-- Telegraphs: yellow while the boss prepares, RED this long before the
	-- server applies the damage (clients flash and tick at that moment).
	DangerLead = 0.35,
})

-- Every ability works in the arena (phase 6.5), with effects adapted to the
-- boss. Abilities never touch another fighter nor cross the expedition
-- border (Core/Expeditions); the boss RESISTS every push, stun, root and
-- slow (control abilities get an alternative effect instead).
Bosses.Abilities = table.freeze({
	dash = table.freeze({ kind = "movement" }),
	-- Destination must stay inside the arena walls.
	blink = table.freeze({ kind = "movement" }),
	-- Only the 4 floating bubble anchors of the arena (see ArenaGrapple).
	grapple = table.freeze({ kind = "movement" }),
	-- No push / stun on the boss: a heavy "BOING" hit instead, and it
	-- washes the sticky goo off the caster.
	pulse = table.freeze({ kind = "control", damage = 25 }),
	-- No slow on the boss: "chilled", he takes more damage for a while.
	frost_wave = table.freeze({ kind = "control", damage = 10, chill = 0.15, chillDuration = 4 }),
	-- The boss walking / landing on an armed rune sets it off: "ZAP!".
	rune_trap = table.freeze({ kind = "control", damage = 40 }),
	-- Blocks the next boss hit while it is up (consumed).
	shield = table.freeze({ kind = "defence" }),
	-- Spectral Phase: boss attacks pass through you.
	phase = table.freeze({ kind = "defence" }),
	-- The boss aims his puddles, bunnies and hops at decoys too.
	decoy = table.freeze({ kind = "defence" }),
})

-- Floating bubble anchors for the Grapple inside the arena (index 101+).
Bosses.ArenaGrapple = table.freeze({
	FirstIndex = 101,
	Radius = 40,
	Height = 15,
	Angles = table.freeze({ 45, 135, 225, 315 }),
})

-- "Strike" (Frappe): the only way to damage a boss. Arena only.
Bosses.Strike = table.freeze({
	Damage = 10,
	-- Server cooldown between two strikes (client shows the same).
	Cooldown = 0.4,
	-- Reach from the boss body surface (studs, horizontal) and height tolerance.
	Reach = 10,
	Height = 14,
	-- Dizzy boss (after its special): damage multiplier.
	DizzyMultiplier = 1.5,
	-- Current Power bonus: linear up to this Power, capped. 0.25 = +25 %.
	PowerForCap = 1500,
	PowerBonusCap = 0.25,
})

-- Eligibility for rewards: a participant must have dealt at least this share
-- of an equal split of the boss Health (anti-AFK / anti-leech), and still be
-- in the server, not removed for inactivity or exploit, not abandoned.
Bosses.Eligibility = table.freeze({
	MinShare = 0.2,
})

-- Trophy pedestals in every Sanctuary (boss relics only, never stealable).
-- Socle k unlocks at Power record >= Unlocks[k].
Bosses.Trophies = table.freeze({
	Unlocks = table.freeze({ 0, 400, 900 }),
})

-- Types ------------------------------------------------------------------------

export type LootEntry = {
	-- Reward key (also used by the Codex): "essence", "void_shard", ...
	id: string,
	kind: string, -- "essence" | "material" | "relic" | "cosmetic"
	-- Material / relic / cosmetic id (kind ~= "essence").
	ref: string?,
	-- Exact probability for every eligible participant (independent rolls).
	chance: number,
	-- Amount range (materials).
	min: number?,
	max: number?,
	-- Essence: minutes of the player's own production, with a floor.
	minutes: number?,
	floor: number?,
	-- Rare rewards are counted in the Codex.
	rare: boolean?,
	-- Duplicate compensation (owned cosmetic, max-level trophy).
	fallback: { material: string, amount: number }?,
}

export type AttackDef = {
	id: string,
	-- Seconds between the warning and the first possible damage.
	telegraph: number,
	-- Big special (needs Combat.BigTelegraph).
	big: boolean?,
	-- Free tuning read by the boss module (radius, speed, counts...).
	tuning: { [string]: number },
}

export type PhaseDef = {
	-- Phase starts when Health fraction <= `from` (phase 1: 1).
	from: number,
	-- Attack pool (weighted by order of appearance: no repeat twice in a row).
	attacks: { string },
	-- Seconds of breathing room between two attacks.
	gap: number,
	-- Special attack id thrown on entering the phase and every `specialEvery` attacks.
	special: string?,
	specialEvery: number?,
	-- Expression shown during the phase (client).
	mood: string,
}

-- Safe pad of the arena (phase 7A): polar position around the arena centre.
export type PadDef = {
	deg: number,
	r: number,
}

-- Calm lane of a wind sweep (phase 7B, Tempest Seraph's Sky Gust): a strip
-- parallel to the wind direction, `offset` studs to the side of the arena
-- centre (signed, along the sweep's `side` vector), `width` studs wide.
export type Lane = {
	offset: number,
	width: number,
}

export type BossDef = {
	id: string,
	-- Server/Bosses/<module>.luau
	module: string,
	-- Arena look (Server/World/ArenaBuilder): "closet" | "volcano" | "sky".
	theme: string,
	-- Optional safe pads drawn in the arena (Forgeheart's eruption, the
	-- Tempest Seraph's cloud shelters).
	pads: { PadDef }?,
	padRadius: number?,
	-- Rank I, II, III... (Codex order) and difficulty stars (1..5).
	rank: number,
	difficulty: number,
	color: Color3,
	accent: Color3,
	-- Expedition gate (Power RECORD) and recommendation (current Power).
	minPowerRecord: number,
	recommendedPower: number,
	-- Health = baseHealth * (1 + healthPerExtra * (participants - 1)).
	baseHealth: number,
	healthPerExtra: number,
	-- Body half-size (studs) used for strike reach.
	radius: number,
	-- Body centre height above the floor.
	height: number,
	phases: { PhaseDef },
	attacks: { [string]: AttackDef },
	loot: { LootEntry },
	-- Exclusive relic / cosmetic (also present in `loot`).
	relic: string,
	cosmetic: string,
}

-- Catalogue ----------------------------------------------------------------------

local list: { BossDef } = {
	{
		-- The grumpy janitor of the Rift: a big purple jelly cube with a cap,
		-- huge eyes and a giant broom. He hates mess (and you are the mess).
		id = "VoidWarden",
		module = "VoidWarden",
		theme = "closet",
		rank = 1,
		difficulty = 2,
		color = Color3.fromRGB(176, 110, 255),
		accent = Color3.fromRGB(255, 214, 72),
		minPowerRecord = 25,
		recommendedPower = 150,
		baseHealth = 1500,
		healthPerExtra = 0.7,
		radius = 7,
		height = 7,
		phases = {
			{ from = 1, attacks = { "broom_wave", "goo_puddles", "dust_bunnies", "belly_flop" }, gap = 1.6, mood = "grumpy" },
			{ from = 0.6, attacks = { "broom_wave", "dust_bunnies", "goo_puddles", "belly_flop" }, gap = 1.3, special = "big_cleanup", specialEvery = 4, mood = "angry" },
			{ from = 0.25, attacks = { "broom_wave", "goo_puddles", "dust_bunnies", "belly_flop" }, gap = 1.0, special = "big_cleanup", specialEvery = 3, mood = "furious" },
		},
		attacks = {
			-- Spin of the broom: a ring of dust rolls out from the boss. JUMP over it.
			broom_wave = { id = "broom_wave", telegraph = 1.2, tuning = { speed = 30, band = 3, speedPerPhase = 4 } },
			-- Sticky goo puddles: circles fill yellow -> red, then SPLAT. Step out.
			goo_puddles = { id = "goo_puddles", telegraph = 1.2, tuning = { count = 3, extraPerPhase = 1, radius = 6, linger = 4, slow = 0.45 } },
			-- Dust bunnies lobbed in an arc: landing marks show where. Move away.
			dust_bunnies = { id = "dust_bunnies", telegraph = 1.1, tuning = { count = 4, extraPerPhase = 1, radius = 4.5, spread = 9 } },
			-- Belly flop: a shadow grows where the boss will land.
			belly_flop = { id = "belly_flop", telegraph = 1.0, tuning = { radius = 9, height = 26 } },
			-- Special "Grand Ménage": 3 quarters of the arena get mopped. Find the
			-- sparkling safe quarter! Leaves the boss dizzy (bonus damage).
			big_cleanup = { id = "big_cleanup", telegraph = 2.0, big = true, tuning = { dizzy = 3.5, innerSafe = 0 } },
		},
		loot = {
			{ id = "essence", kind = "essence", chance = 1, minutes = 5, floor = 250 },
			{ id = "void_shard", kind = "material", ref = "void_shard", chance = 1, min = 3, max = 6 },
			{ id = "void_catalyst", kind = "material", ref = "void_catalyst", chance = 0.15, min = 1, max = 1, rare = true },
			{ id = "void_duster", kind = "relic", ref = "void_duster", chance = 0.08, rare = true, fallback = { material = "void_shard", amount = 8 } },
			{ id = "trail_bubbles", kind = "cosmetic", ref = "trail_bubbles", chance = 0.05, rare = true, fallback = { material = "void_shard", amount = 5 } },
		},
		relic = "void_duster",
		cosmetic = "trail_bubbles",
	},
	{
		-- FORGEHEART (phase 7A): a huge cartoon lava golem made of round
		-- boulders, glowing lava cracks and a burning heart. Big googly eyes,
		-- a goofy mouth, massive arms. Strong, clumsy, hot-headed and funny.
		id = "Forgeheart",
		module = "Forgeheart",
		theme = "volcano",
		-- Six cooled-rock pads around the centre: during the Final Eruption
		-- every other one stays safe (always one within reach).
		pads = {
			{ deg = 0, r = 26 }, { deg = 60, r = 26 }, { deg = 120, r = 26 },
			{ deg = 180, r = 26 }, { deg = 240, r = 26 }, { deg = 300, r = 26 },
		},
		padRadius = 8,
		rank = 2,
		difficulty = 3,
		color = Color3.fromRGB(255, 120, 50),
		accent = Color3.fromRGB(255, 214, 72),
		minPowerRecord = 120,
		recommendedPower = 400,
		baseHealth = 2200,
		healthPerExtra = 0.75,
		radius = 8,
		height = 9,
		phases = {
			{ from = 1, attacks = { "volcanic_hammer", "lava_blobs", "burning_floor", "meteor_shower" }, gap = 1.4, mood = "grumpy" },
			{ from = 0.6, attacks = { "volcanic_hammer", "meteor_shower", "lava_blobs", "burning_floor" }, gap = 1.15, special = "final_eruption", specialEvery = 4, mood = "angry" },
			{ from = 0.3, attacks = { "volcanic_hammer", "lava_blobs", "meteor_shower", "burning_floor" }, gap = 0.95, special = "final_eruption", specialEvery = 3, mood = "furious" },
		},
		attacks = {
			-- "Marteau volcanique": he slams the ground in front of him (or all
			-- around him when nobody is close). Phase 3: a shockwave ring
			-- rolls out of the impact (JUMP).
			volcanic_hammer = { id = "volcanic_hammer", telegraph = 1.3, tuning = { radius = 11, reach = 14, maxDistance = 30, poundRadius = 15, waveSpeed = 34, band = 3, waveReach = 42 } },
			-- "Boulettes de lave": lobbed lava balls land on marked circles and
			-- leave a burning puddle for a moment.
			lava_blobs = { id = "lava_blobs", telegraph = 1.3, tuning = { count = 4, extraPerPhase = 1, radius = 5, spread = 8, linger = 2.4 } },
			-- "Sol brûlant": cracks glow yellow, then the floor there burns
			-- red for a few seconds. Stay off the red.
			burning_floor = { id = "burning_floor", telegraph = 1.5, tuning = { count = 3, extraPerPhase = 1, radius = 8, duration = 3 } },
			-- "Pluie de météores": meteors fall one after another on marked
			-- circles (every mark is visible from the start).
			meteor_shower = { id = "meteor_shower", telegraph = 1.2, tuning = { count = 5, extraPerPhase = 2, radius = 4.5, interval = 0.4 } },
			-- Special "Éruption finale" (phase 2+): he jumps to the centre and
			-- the whole floor erupts except every other cooled-rock pad (green
			-- beacons). Phase 3: a second eruption on the other pads. He ends up
			-- out of breath (dizzy, bonus damage).
			final_eruption = { id = "final_eruption", telegraph = 3.0, big = true, tuning = { second = 2.3, dizzy = 3.2 } },
		},
		loot = {
			{ id = "essence", kind = "essence", chance = 1, minutes = 7, floor = 500 },
			{ id = "magma_shard", kind = "material", ref = "magma_shard", chance = 1, min = 3, max = 6 },
			{ id = "ember_core", kind = "material", ref = "ember_core", chance = 0.15, min = 1, max = 1, rare = true },
			{ id = "ember_anvil", kind = "relic", ref = "ember_anvil", chance = 0.08, rare = true, fallback = { material = "magma_shard", amount = 8 } },
			{ id = "trail_magma", kind = "cosmetic", ref = "trail_magma", chance = 0.05, rare = true, fallback = { material = "magma_shard", amount = 5 } },
		},
		relic = "ember_anvil",
		cosmetic = "trail_magma",
	},
	{
		-- TEMPEST SERAPH (phase 7B): a cartoon thunder-cloud diva. A puffy
		-- cloud body, big expressive eyes, a golden crown worn crooked, tiny
		-- flapping wings and yellow zig-zag bolts. Smug, dramatic, very loud,
		-- never scary. Floats above the floor and pops into a drizzle at the end.
		id = "TempestSeraph",
		module = "TempestSeraph",
		theme = "sky",
		-- Six cloud shelters around the centre: during the MEGA-STORM every
		-- other one is lit (always one within reach).
		pads = {
			{ deg = 30, r = 27 }, { deg = 90, r = 27 }, { deg = 150, r = 27 },
			{ deg = 210, r = 27 }, { deg = 270, r = 27 }, { deg = 330, r = 27 },
		},
		padRadius = 8,
		rank = 3,
		difficulty = 4,
		color = Color3.fromRGB(110, 180, 255),
		accent = Color3.fromRGB(255, 226, 70),
		minPowerRecord = 300,
		recommendedPower = 900,
		baseHealth = 3000,
		healthPerExtra = 0.8,
		radius = 8,
		height = 11,
		phases = {
			{ from = 1, attacks = { "targeted_bolt", "dancing_tornadoes", "sky_gust", "chain_lightning" }, gap = 1.3, mood = "grumpy" },
			{ from = 0.65, attacks = { "targeted_bolt", "sky_gust", "dancing_tornadoes", "chain_lightning" }, gap = 1.05, special = "mega_storm", specialEvery = 4, mood = "angry" },
			{ from = 0.3, attacks = { "chain_lightning", "targeted_bolt", "sky_gust", "dancing_tornadoes" }, gap = 0.85, special = "mega_storm", specialEvery = 3, mood = "furious" },
		},
		attacks = {
			-- "Éclair ciblé": a reticle FOLLOWS a fighter for `track` s, then
			-- LOCKS (stops) and the bolt strikes 0.6 s later. Step out after the
			-- lock. Phase 1: 1 (+1 per extra fighter, max +2); phase 2+: one per
			-- fighter; phase 3: `extraPerPhase` more volley(s) 0.5 s later.
			targeted_bolt = { id = "targeted_bolt", telegraph = 1.6, tuning = { radius = 5.5, track = 1.0, extraPerPhase = 1, volleyGap = 0.5 } },
			-- "Tornades dansantes": every tornado path is drawn from the warning;
			-- they appear at the impact time and dance along it, slower than you
			-- walk. Too tall to jump over.
			dancing_tornadoes = { id = "dancing_tornadoes", telegraph = 1.4, tuning = { radius = 4.5, speed = 14, count = 2, extraPerPhase = 1, minDuration = 2.5, height = 18 } },
			-- "Rafale céleste": a wind front sweeps the whole arena; only the
			-- three green calm lanes are safe (jumping does not help).
			sky_gust = { id = "sky_gust", telegraph = 1.5, tuning = { speed = 22, speedPhase3 = 28, band = 4, laneWidth = 14, laneSpacing = 32, jitter = 3, startBeyond = 6 } },
			-- "Chaîne électrique": nodes under the fighters (then free spots)
			-- linked by arcs; every node and every arc zaps. Spread out!
			chain_lightning = { id = "chain_lightning", telegraph = 1.4, tuning = { count = 3, extraPerPhase = 1, radius = 4.5, width = 3 } },
			-- Special "MÉGA-TEMPÊTE" (phase 2+): he rises to the centre and the
			-- whole arena is struck except every other cloud shelter (lit).
			-- Phase 3: two more strikes alternating the lit shelters. Then he
			-- is dazed (dizzy, bonus damage).
			mega_storm = { id = "mega_storm", telegraph = 3.2, big = true, tuning = { second = 2.4, dizzy = 3 } },
		},
		loot = {
			{ id = "essence", kind = "essence", chance = 1, minutes = 9, floor = 900 },
			{ id = "storm_shard", kind = "material", ref = "storm_shard", chance = 1, min = 3, max = 6 },
			{ id = "thunder_core", kind = "material", ref = "thunder_core", chance = 0.15, min = 1, max = 1, rare = true },
			{ id = "zigzag_crown", kind = "relic", ref = "zigzag_crown", chance = 0.08, rare = true, fallback = { material = "storm_shard", amount = 8 } },
			{ id = "aura_thunder", kind = "cosmetic", ref = "aura_thunder", chance = 0.05, rare = true, fallback = { material = "storm_shard", amount = 5 } },
		},
		relic = "zigzag_crown",
		cosmetic = "aura_thunder",
	},
}

-- Arena themes built by Server/World/ArenaBuilder.
local THEMES = { closet = true, volcano = true, sky = true }

-- Validation (fails at load time, caught by every test run) -----------------------
local byId: { [string]: BossDef } = {}
for _, def in list do
	assert(byId[def.id] == nil, "duplicate boss " .. def.id)
	assert(def.difficulty >= 1 and def.difficulty <= 5, "boss " .. def.id .. " difficulty out of range")
	assert(def.minPowerRecord <= def.recommendedPower, "boss " .. def.id .. " gate above its recommendation")
	assert(#def.phases >= 1 and def.phases[1].from == 1, "boss " .. def.id .. " phase 1 must start at full Health")
	for index = 2, #def.phases do
		assert(def.phases[index].from < def.phases[index - 1].from, "boss " .. def.id .. " phases must go down")
	end
	for attackId, attack in def.attacks do
		assert(attack.id == attackId, "boss " .. def.id .. " attack id mismatch " .. attackId)
		local minimum = if attack.big then Bosses.Combat.BigTelegraph else Bosses.Combat.MinTelegraph
		assert(attack.telegraph >= minimum, "boss " .. def.id .. " attack " .. attackId .. " telegraph too short")
	end
	for _, phase in def.phases do
		for _, attackId in phase.attacks do
			assert(def.attacks[attackId], "boss " .. def.id .. " phase uses unknown attack " .. attackId)
		end
		if phase.special then
			assert(def.attacks[phase.special] and def.attacks[phase.special].big, "boss " .. def.id .. " special must be a big attack")
		end
	end
	local seen: { [string]: boolean } = {}
	for _, entry in def.loot do
		assert(not seen[entry.id], "boss " .. def.id .. " duplicate loot " .. entry.id)
		seen[entry.id] = true
		assert(entry.chance > 0 and entry.chance <= 1, "boss " .. def.id .. " loot chance out of range " .. entry.id)
		if entry.kind == "material" then
			assert(entry.ref and entry.min and entry.max and entry.min >= 1 and entry.max >= entry.min, "boss " .. def.id .. " bad material loot " .. entry.id)
			assert(Materials.get(entry.ref), "boss " .. def.id .. " drops an unknown material " .. tostring(entry.ref))
		elseif entry.kind == "essence" then
			assert(entry.minutes and entry.minutes > 0, "boss " .. def.id .. " essence loot needs minutes")
		else
			assert(entry.kind == "relic" or entry.kind == "cosmetic", "boss " .. def.id .. " unknown loot kind " .. entry.kind)
			assert(entry.ref and entry.fallback, "boss " .. def.id .. " exclusive loot needs a duplicate fallback " .. entry.id)
			assert(Materials.get(entry.fallback.material), "boss " .. def.id .. " fallback uses an unknown material")
			if entry.kind == "relic" then
				local relic = Relics.get(entry.ref :: string)
				assert(relic and relic.bossOnly == def.id, "boss " .. def.id .. " relic loot must be its own boss relic")
			else
				local cosmetic = Cosmetics.get(entry.ref)
				assert(cosmetic and cosmetic.unlock.kind == "boss" and cosmetic.unlock.boss == def.id, "boss " .. def.id .. " cosmetic loot must be its own boss cosmetic")
			end
		end
	end
	assert(Relics.get(def.relic) and Cosmetics.get(def.cosmetic), "boss " .. def.id .. " exclusive relic / cosmetic missing")
	assert(THEMES[def.theme] == true, "boss " .. def.id .. " unknown arena theme " .. tostring(def.theme))
	if def.pads then
		assert(def.padRadius and def.padRadius > 0, "boss " .. def.id .. " pads need a radius")
		for _, pad in def.pads do
			assert(pad.r + (def.padRadius :: number) < Bosses.Arena.Radius, "boss " .. def.id .. " pad outside the arena")
		end
	end
	byId[def.id] = def
end

Bosses.list = list
Bosses.byId = byId

function Bosses.get(id: any): BossDef?
	if type(id) ~= "string" then
		return nil
	end
	return byId[id]
end

-- The boss of the n-th opening of a server (rotation in `list` order).
function Bosses.forOpening(index: number): BossDef
	return list[((math.max(1, math.floor(index)) - 1) % #list) + 1]
end

-- Floor positions of a boss's safe pads (empty when it has none).
function Bosses.arenaPads(def: BossDef): { Vector3 }
	local out = {}
	local c = Bosses.Arena.Center
	local pads: { PadDef } = def.pads or {}
	for _, pad in pads do
		local a = math.rad(pad.deg)
		table.insert(out, Vector3.new(c.X + math.cos(a) * pad.r, c.Y, c.Z + math.sin(a) * pad.r))
	end
	return out
end

-- Formulas (pure) ----------------------------------------------------------------

-- Phase 7B shared geometry (server shapes and client drawings use the SAME
-- formulas, so what is drawn is exactly what hurts). All distances are flat
-- (XZ plane).

-- Length of a polyline.
function Bosses.pathLength(points: { Vector3 }): number
	local total = 0
	for i = 2, #points do
		total += (points[i] - points[i - 1]).Magnitude
	end
	return total
end

-- Position on a polyline at time `t`: it moves at constant speed (by arc
-- length) from points[1] at `startAt` to points[#points] at `endAt`, and is
-- clamped to the ends outside that window (tornadoes, path shapes).
function Bosses.pathPosition(points: { Vector3 }, startAt: number, endAt: number, t: number): Vector3
	local count = #points
	if count == 0 then
		return Vector3.zero
	end
	local total = Bosses.pathLength(points)
	if count == 1 or total <= 0 or endAt <= startAt then
		return if t >= endAt then points[count] else points[1]
	end
	local remaining = math.clamp((t - startAt) / (endAt - startAt), 0, 1) * total
	for i = 2, count do
		local a, b = points[i - 1], points[i]
		local segment = (b - a).Magnitude
		if remaining <= segment then
			return if segment > 0 then a:Lerp(b, remaining / segment) else b
		end
		remaining -= segment
	end
	return points[count]
end

-- Flat distance from `p` to the segment [a, b] (chain lightning arcs).
function Bosses.segmentDistance(p: Vector3, a: Vector3, b: Vector3): number
	local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local ap = Vector3.new(p.X - a.X, 0, p.Z - a.Z)
	local lengthSq = ab:Dot(ab)
	if lengthSq <= 1e-9 then
		return ap.Magnitude
	end
	local k = math.clamp(ap:Dot(ab) / lengthSq, 0, 1)
	return (ap - ab * k).Magnitude
end

-- Is a sweep's `lateral` offset (signed distance along the sweep's side
-- vector) inside one of its calm lanes?
function Bosses.inCalmLane(lateral: number, lanes: { Lane }): boolean
	for _, lane in lanes do
		if math.abs(lateral - lane.offset) <= lane.width / 2 then
			return true
		end
	end
	return false
end

-- Side vector of a sweep direction (lanes are measured along it):
-- side = (-dir.Z, 0, dir.X).
function Bosses.sweepSide(dir: Vector3): Vector3
	return Vector3.new(-dir.Z, 0, dir.X)
end

-- Signed position of a sweep's wind front along its direction at time `t`
-- (it is at `start` when `t` = `at`, then moves forward at `speed`).
function Bosses.sweepFront(start: number, speed: number, at: number, t: number): number
	return start + (t - at) * speed
end

function Bosses.maxHealth(def: BossDef, participants: number): number
	local n = math.max(1, math.floor(participants))
	return math.floor(def.baseHealth * (1 + def.healthPerExtra * (n - 1)) + 0.5)
end

-- Strike bonus from the CURRENT Power (0 .. PowerBonusCap).
function Bosses.powerBonus(power: number): number
	local s = Bosses.Strike
	if type(power) ~= "number" or power ~= power or power <= 0 then
		return 0
	end
	return math.clamp(power / s.PowerForCap, 0, 1) * s.PowerBonusCap
end

-- Damage of one hit: `base` (weapon) x multipliers (combo, dizzy, chill,
-- team buff) x the capped current-Power bonus, rounded to 0.1.
function Bosses.hitDamage(base: number, power: number, multiplier: number): number
	local damage = base * multiplier * (1 + Bosses.powerBonus(power))
	return math.floor(damage * 10 + 0.5) / 10
end

function Bosses.strikeDamage(power: number, dizzy: boolean): number
	local s = Bosses.Strike
	local damage = s.Damage * (1 + Bosses.powerBonus(power))
	if dizzy then
		damage *= s.DizzyMultiplier
	end
	return math.floor(damage * 10 + 0.5) / 10
end

-- Damage a participant must deal to be eligible for rewards.
function Bosses.eligibleDamage(maxHealth: number, participants: number): number
	return Bosses.Eligibility.MinShare * maxHealth / math.max(1, participants)
end

-- Essence reward: `minutes` of the player's production (per second rate).
function Bosses.essenceReward(entry: LootEntry, ratePerSecond: number): number
	local rate = if type(ratePerSecond) == "number" and ratePerSecond == ratePerSecond then math.max(0, ratePerSecond) else 0
	local amount = rate * 60 * (entry.minutes or 0)
	return math.floor(math.clamp(math.max(amount, entry.floor or 0), 0, 1e13))
end

-- Phase index for a Health fraction (1 = full Health).
function Bosses.phaseAt(def: BossDef, fraction: number): number
	local phase = 1
	for index, entry in def.phases do
		if fraction <= entry.from then
			phase = index
		end
	end
	return phase
end

-- Can a Power record enter this boss's expedition?
function Bosses.canEnter(def: BossDef, powerRecord: number): boolean
	return powerRecord >= def.minPowerRecord
end

-- Grapple anchors of the arena: { index, position } (index >= FirstIndex).
function Bosses.arenaGrapplePoints(): { { index: number, position: Vector3 } }
	local g = Bosses.ArenaGrapple
	local c = Bosses.Arena.Center
	local points = {}
	for k, deg in g.Angles do
		local a = math.rad(deg)
		table.insert(points, { index = g.FirstIndex + k - 1, position = Vector3.new(c.X + math.cos(a) * g.Radius, c.Y + g.Height, c.Z + math.sin(a) * g.Radius) })
	end
	return points
end

function Bosses.arenaGrapplePoint(index: number): Vector3?
	for _, point in Bosses.arenaGrapplePoints() do
		if point.index == index then
			return point.position
		end
	end
	return nil
end

-- Trophy pedestals unlocked for a Power record (1..#Unlocks).
function Bosses.trophySlots(powerRecord: number): number
	local count = 0
	for _, threshold in Bosses.Trophies.Unlocks do
		if powerRecord >= threshold then
			count += 1
		end
	end
	return count
end

-- Percentage text with every significant digit kept ("8 %", "12.5 %", "100 %").
function Bosses.percent(chance: number): string
	local value = chance * 100
	if math.abs(value - math.floor(value + 0.5)) < 1e-9 then
		return string.format("%d %%", math.floor(value + 0.5))
	end
	local text = string.format("%.2f", value)
	text = string.gsub(text, "0+$", "") :: string
	text = string.gsub(text, "%.$", "") :: string
	return text .. " %"
end

return Bosses
