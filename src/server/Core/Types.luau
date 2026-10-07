--!strict
-- Server-side data shapes shared by every service.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Economy = require(ReplicatedStorage.Shared.Economy)

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
	dirty: boolean,
	saving: boolean,
	released: boolean,
	lastNotice: { [string]: number },
	leaderstats: Folder?,
}

return {}
