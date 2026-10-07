--!strict
-- Server-side data shapes shared by every service.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Economy = require(ReplicatedStorage.Shared.Economy)
local Status = require(ReplicatedStorage.Shared.Status)

export type SaveRelic = {
	uid: string,
	id: string,
	level: number,
	mutation: string?,
	slot: number,
}

export type DexEntry = {
	count: number,
	mutations: { [string]: boolean },
	first: number,
}

export type Settings = {
	sfx: number,
	music: number,
	quality: string,
	shake: boolean,
	language: string,
}

export type Stats = {
	claimed: number,
	deposits: number,
	stolen: number,
	lost: number,
	recovered: number,
	rareFinds: number,
	essenceCollected: number,
}

-- Schema 2 ------------------------------------------------------------------
export type AbilityData = {
	-- abilityId -> true. Always contains the default abilities.
	unlocked: { [string]: boolean },
	-- One ability id per loadout slot (Config/Abilities.Slots order), "" = empty.
	loadout: { string },
	-- schema 3: harmonies the player switched off (relic id -> true).
	harmonyOff: { [string]: boolean },
}

export type PowerData = {
	-- Highest Power ever reached. Used for unlocks so thefts never re-lock content.
	peak: number,
}

export type SaveData = {
	schema: number,
	essence: number,
	lifetimeEssence: number,
	upgrades: Economy.UpgradeLevels,
	relics: { SaveRelic },
	dex: { [string]: DexEntry },
	coreStored: number,
	lastSeen: number,
	playTime: number,
	stats: Stats,
	tutorial: number,
	tips: { [string]: boolean },
	settings: Settings,
	-- schema 2
	abilities: AbilityData,
	power: PowerData,
}

-- Runtime crowd-control state (never saved). See Shared/Status.
export type StatusState = Status.State

-- Abilities -------------------------------------------------------------------
-- Passed to Server/Abilities/<Module>.activate after AbilityService validated
-- ownership, loadout, character, status and cooldown.
export type AbilityContext = {
	session: Session,
	player: Player,
	root: BasePart,
	abilityId: string,
	now: number,
	-- Sanitised by the module's readPayload (nil when the ability takes none).
	payload: any,
	-- Effective tuning (GameConfig + active harmonies) and cooldown, both
	-- computed on the server from the relics actually displayed.
	tuning: { [string]: any },
	cooldown: number,
	-- Active harmonies of the caster (relic id -> true).
	harmonies: { [string]: boolean },
}

export type AbilityModule = {
	-- Returns the sanitised payload, or nil to reject the request.
	readPayload: ((raw: any) -> any)?,
	-- Optional check run before the cooldown is spent: (false, reason)
	-- rejects the request at no cost (blocked blink, invalid anchor...).
	validate: ((ctx: AbilityContext) -> (boolean, string?))?,
	activate: (ctx: AbilityContext) -> (),
	-- Optional: periodic work (AbilityService runs one shared job).
	tick: ((now: number) -> ())?,
	-- Optional: drop everything the session owns (death, respawn, leave,
	-- unequip, sweep). Must be safe to call at any time, any number of times.
	cleanup: ((session: Session, reason: string) -> ())?,
}

export type StealHold = {
	uid: string,
	startedAt: number,
}

export type Session = {
	player: Player,
	userId: number,
	data: SaveData,
	loaded: boolean,
	canSave: boolean,
	dataStatus: string,
	plot: number?,
	carrying: { string },
	cooldowns: { [string]: number },
	stunnedUntil: number,
	steadyUntil: number,
	spawnProtectedUntil: number,
	teleportGraceUntil: number,
	lastActivity: number,
	lastPosition: Vector3?,
	joinedAt: number,
	stealHold: StealHold?,
	-- thief side: victim userId -> timestamps of successful thefts
	stealLog: { [number]: { number } },
	-- victim side: timestamps this player was robbed
	robbedLog: { number },
	rate: number,
	multiplier: number,
	-- Current Power (derived, recomputed with the Essence rate).
	power: number,
	-- Relic ids with a harmony currently displayed in the Sanctuary
	-- (recomputed with the Essence rate, sent in the hot Sync).
	harmonyRelics: { string },
	status: StatusState,
	-- Runtime state of abilities (pending blink, grapple flight, trap, decoy...).
	-- Never saved; cleared on death, respawn and leave.
	abilityState: { [string]: any },
	-- Studio test unlock (/rh abilities): never saved.
	devAbilities: boolean,
	-- Temporary raise of the movement guard threshold (dash).
	moveAllowance: { speed: number, untilTime: number }?,
	-- Hot state changed (pushed at most every Sync.HotInterval).
	dirty: boolean,
	-- Cold state changed (Dex, upgrades, loadout, settings...).
	coldDirty: boolean,
	-- Last cold snapshot sent, used by the audit to catch unmarked changes.
	lastCold: { [string]: any }?,
	saving: boolean,
	released: boolean,
	lastNotice: { [string]: number },
	leaderstats: Folder?,
}

return {}
