--!strict
-- Shared types between BossService (generic: portal, arena, hearts, hits,
-- rewards) and the per-boss behaviour modules (Server/Bosses/<Id>.luau).
--
-- A boss module only PLANS attacks: it decides every position and time on
-- the server and returns generic damage shapes. BossService resolves the
-- shapes against the server's view of the fighters, and sends the plan to
-- the clients so they can draw the telegraphs (one message per attack).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Bosses = require(ReplicatedStorage.Shared.Config.Bosses)

-- Damage / effect shapes (all positions on the arena floor):
--   ring    expanding ring from `center` starting at `at`: grounded fighters
--           are hit when its front reaches them (jump over it);
--   circle  disc of `radius` hitting at `at` (step out of it);
--   sector  everyone OUTSIDE the safe sector (`safeAngle` +- safeWidth/2,
--           radians, atan2(z, x) around `center`) is hit at `at`;
--   zone    lingering disc slowing grounded fighters from `at` to `untilTime`;
--   burn    lingering disc HURTING grounded fighters from `at` to
--           `untilTime` (phase 7A: lava; drawn red the whole time, the hit
--           invulnerability limits it to one heart per HitInvulnerability);
--   outside everyone NOT standing on one of the `safeSpots` discs
--           (`safeRadius`) is hit at `at` (phase 7A: Final Eruption).
--
-- Phase 7B (Tempest Seraph):
--   circle  + `track` (userId) / `lockAt` / `key`: a tracked reticle. While
--           t < lockAt the server moves `center` to that fighter's floor
--           position (if they are still fighting); at lockAt it freezes and
--           sends the "BossLock" FX { fight, key, position, userId, at };
--           then it hits at `at` like any circle (+ "step" dodge);
--   path    a disc of `radius` moving along `points` at constant speed (by
--           arc length, Config/Bosses.pathPosition) from `at` to
--           `untilTime`; hurts fighters within `radius`, grounded OR
--           airborne (below `height` studs above the floor);
--   sweep   a straight wind front moving along `dir` (unit, flat): its
--           signed offset from `center` is `start` at `at`, then grows at
--           `speed`. When it passes a fighter (band `band`) the fighter is
--           hit unless inside a calm lane (|lateral - offset| <= width / 2,
--           lateral measured along Config/Bosses.sweepSide(dir)); jumping does
--           not help. Removed once the front is past `radius` + band;
--   chain   at `at`, hits fighters within `radius` of a node of `points` or
--           within `width` / 2 of a segment between two consecutive nodes.
export type Shape = {
	kind: string,
	at: number,
	center: Vector3,
	radius: number,
	untilTime: number?,
	speed: number?,
	band: number?,
	safeAngle: number?,
	safeWidth: number?,
	slow: number?,
	safeSpots: { Vector3 }?,
	safeRadius: number?,
	-- Phase 7B: tracked circle (bolt reticle).
	track: number?,
	lockAt: number?,
	key: string?,
	-- Phase 7B: path (tornado) / chain nodes, tornado height.
	points: { Vector3 }?,
	height: number?,
	-- Phase 7B: sweep (wind front) and chain link width.
	dir: Vector3?,
	start: number?,
	lanes: { Bosses.Lane }?,
	width: number?,
	-- Runtime (BossService): resolved fighters / finished flag / reticle
	-- frozen.
	resolved: { [any]: boolean }?,
	done: boolean?,
	locked: boolean?,
}

-- Server-driven boss movement (hop arc). Untouchable while in the air.
export type Motion = {
	from: Vector3,
	to: Vector3,
	startAt: number,
	endAt: number,
	height: number,
}

export type Plan = {
	id: string,
	-- Boss animation for clients ("Sweep", "Splat", "Throw", "Hop", "Spin";
	-- Forgeheart: "Slam", "Lob", "Stomp", "Roar", "Erupt"; Tempest Seraph:
	-- "Zap", "Twirl", "Blow", "Charge", "Storm").
	action: string,
	telegraphAt: number,
	-- First moment any shape can hurt (>= telegraphAt + attack telegraph).
	hitAt: number,
	-- Attack over: the next one may be planned after the phase gap.
	endsAt: number,
	shapes: { Shape },
	motion: Motion?,
	-- Boss stays dizzy (bonus damage, no attack) after the attack.
	dizzyAt: number?,
	dizzyFor: number?,
	-- Everything the clients need to draw the telegraphs.
	payload: { [string]: any },
}

-- Read-only view of the fight handed to the module.
export type FightView = {
	boss: Bosses.BossDef,
	phase: number,
	participants: number,
	center: Vector3,
	floorY: number,
	radius: number,
	bossPosition: Vector3,
	-- Floor positions of the fighters still standing (then their decoys).
	targets: { Vector3 },
	-- Phase 7B: userId of each entry of `targets` (same order), 0 for a
	-- decoy. Optional (older callers): without it nothing is tracked.
	targetIds: { number }?,
	rng: Random,
}

export type BossModule = {
	-- Plans `attackId` starting now.
	plan: (view: FightView, attackId: string, now: number) -> Plan,
}

return {}
