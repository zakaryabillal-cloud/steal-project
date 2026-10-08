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
--   zone    lingering disc slowing grounded fighters from `at` to `untilTime`.
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
	-- Runtime (BossService): resolved fighters / finished flag.
	resolved: { [any]: boolean }?,
	done: boolean?,
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
	-- Boss animation for clients ("Sweep", "Splat", "Throw", "Hop", "Spin").
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
	-- Floor positions of the fighters still standing.
	targets: { Vector3 },
	rng: Random,
}

export type BossModule = {
	-- Plans `attackId` starting now.
	plan: (view: FightView, attackId: string, now: number) -> Plan,
}

return {}
