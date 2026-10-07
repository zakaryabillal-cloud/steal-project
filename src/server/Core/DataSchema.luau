--!strict
-- Save-data defaults, migrations and sanitisation. Everything loaded from a
-- DataStore goes through `normalize` so corrupted or tampered fields can never
-- reach gameplay code.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Relics = require(Shared.Config.Relics)
local Mutations = require(Shared.Config.Mutations)
local Upgrades = require(Shared.Config.Upgrades)
local Abilities = require(Shared.Config.Abilities)
local PowerConfig = require(Shared.Config.Power)
local Economy = require(Shared.Economy)
local Layout = require(Shared.Layout)
local Types = require(script.Parent.Types)

type SaveData = Types.SaveData

local DataSchema = {}

DataSchema.Version = GameConfig.Data.SchemaVersion

function DataSchema.default(): SaveData
	return {
		schema = DataSchema.Version,
		essence = 0,
		lifetimeEssence = 0,
		upgrades = Economy.defaultUpgrades(),
		relics = {},
		dex = {},
		coreStored = 0,
		lastSeen = 0,
		playTime = 0,
		stats = {
			claimed = 0,
			deposits = 0,
			stolen = 0,
			lost = 0,
			recovered = 0,
			rareFinds = 0,
			essenceCollected = 0,
		},
		tutorial = 0,
		tips = {},
		settings = {
			sfx = 1,
			music = 0.6,
			quality = "High",
			shake = true,
			language = "",
		},
		abilities = {
			unlocked = Abilities.defaultUnlocked(),
			loadout = Abilities.defaultLoadout(),
		},
		power = {
			peak = 0,
		},
	}
end

-- Ordered migrations: MIGRATIONS[n] upgrades a schema-n table to schema n+1.
-- Add new entries here whenever the schema changes and bump SchemaVersion.
-- Migrations only ADD or reshape fields; they never drop player progress.
-- `normalize` runs afterwards and sanitises every field anyway.
local MIGRATIONS: { [number]: (any) -> any } = {
	-- 1 -> 2 (V2 phase 1): ability loadout + Power record. V1 players start
	-- with the V1 kit (Dash + Pulse) equipped; their Power record is filled in
	-- on the first recompute after joining (see EconomyService.recompute).
	[1] = function(raw: any): any
		if type(raw.abilities) ~= "table" then
			raw.abilities = {
				unlocked = Abilities.defaultUnlocked(),
				loadout = Abilities.defaultLoadout(),
			}
		end
		if type(raw.power) ~= "table" then
			raw.power = { peak = 0 }
		end
		raw.schema = 2
		return raw
	end,
}

-- Schema number stored in a raw DataStore record (1 when missing: launch saves).
function DataSchema.versionOf(raw: any): number
	if type(raw) ~= "table" then
		return DataSchema.Version
	end
	local version = raw.schema
	if type(version) ~= "number" or version ~= version then
		return 1
	end
	return math.floor(version)
end

-- True when a record was written by a NEWER build of the game. Such records
-- must never be normalised (that would drop the fields this build does not
-- know) nor overwritten by this server.
function DataSchema.isNewer(raw: any): boolean
	return type(raw) == "table" and DataSchema.versionOf(raw) > DataSchema.Version
end

local function num(value: any, default: number, min: number?, max: number?): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return default
	end
	local n = value
	if min then
		n = math.max(min, n)
	end
	if max then
		n = math.min(max, n)
	end
	return n
end

local function str(value: any, default: string, maxLength: number): string
	if type(value) ~= "string" then
		return default
	end
	return string.sub(value, 1, maxLength)
end

function DataSchema.normalize(raw: any): SaveData
	local data = DataSchema.default()
	if type(raw) ~= "table" then
		return data
	end

	-- Migrations mutate their input: work on a copy so the caller's record
	-- (e.g. the raw DataStore value) is never altered.
	raw = table.clone(raw)
	local version = math.max(1, DataSchema.versionOf(raw))
	while version < DataSchema.Version do
		local migrate = MIGRATIONS[version]
		if migrate then
			raw = migrate(raw)
		end
		version += 1
	end

	data.essence = math.floor(num(raw.essence, 0, 0, 1e15))
	data.lifetimeEssence = math.floor(num(raw.lifetimeEssence, data.essence, 0, 1e16))
	data.coreStored = math.floor(num(raw.coreStored, 0, 0, 1e15))
	data.lastSeen = num(raw.lastSeen, 0, 0)
	data.playTime = num(raw.playTime, 0, 0)
	data.tutorial = math.floor(num(raw.tutorial, 0, 0, 4))

	if type(raw.upgrades) == "table" then
		for _, def in Upgrades.list do
			(data.upgrades :: any)[def.id] = math.floor(num(raw.upgrades[def.id], 0, 0, def.maxLevel))
		end
	end

	if type(raw.stats) == "table" then
		for key in data.stats :: any do
			(data.stats :: any)[key] = math.floor(num(raw.stats[key], 0, 0))
		end
	end

	if type(raw.tips) == "table" then
		for key, value in raw.tips do
			if type(key) == "string" and value == true and #key <= 32 then
				data.tips[key] = true
			end
		end
	end

	if type(raw.settings) == "table" then
		local s = raw.settings
		data.settings.sfx = num(s.sfx, 1, 0, 1)
		data.settings.music = num(s.music, 0.6, 0, 1)
		local quality = str(s.quality, "High", 8)
		data.settings.quality = if quality == "Low" or quality == "Medium" or quality == "High" then quality else "High"
		data.settings.shake = s.shake ~= false
		local language = str(s.language, "", 4)
		data.settings.language = if language == "en" or language == "fr" then language else ""
	end

	if type(raw.dex) == "table" then
		for relicId, entry in raw.dex do
			if type(relicId) == "string" and Relics.get(relicId) and type(entry) == "table" then
				local mutations = {}
				if type(entry.mutations) == "table" then
					for mutationId, flag in entry.mutations do
						if type(mutationId) == "string" and Mutations.get(mutationId) and flag == true then
							mutations[mutationId] = true
						end
					end
				end
				data.dex[relicId] = {
					count = math.floor(num(entry.count, 1, 1)),
					mutations = mutations,
					first = num(entry.first, 0, 0),
				}
			end
		end
	end

	-- Abilities: defaults are always unlocked; unknown ids are dropped; each
	-- loadout slot must hold an unlocked ability of that slot (else default).
	if type(raw.abilities) == "table" then
		local unlocked = data.abilities.unlocked
		if type(raw.abilities.unlocked) == "table" then
			for abilityId, flag in raw.abilities.unlocked do
				if flag == true and Abilities.get(abilityId) then
					unlocked[abilityId] = true
				end
			end
		end
		if type(raw.abilities.loadout) == "table" then
			for index, slot in Abilities.Slots do
				local chosen = raw.abilities.loadout[index]
				if type(chosen) == "string" and #chosen <= 32 and Abilities.canEquip(index, chosen, unlocked) then
					data.abilities.loadout[index] = chosen
				else
					data.abilities.loadout[index] = slot.default
				end
			end
		end
	end

	if type(raw.power) == "table" then
		data.power.peak = math.floor(num(raw.power.peak, 0, 0, PowerConfig.MaxPeak))
	end

	-- Relics: valid ids only, unique uids, unique slots within unlocked range.
	local unlocked = Economy.unlockedPedestals(data.upgrades)
	local usedSlots: { [number]: boolean } = {}
	local usedUids: { [string]: boolean } = {}
	local overflow = {}
	if type(raw.relics) == "table" then
		for _, entry in raw.relics do
			if type(entry) == "table" and type(entry.id) == "string" and Relics.get(entry.id) then
				local uid = str(entry.uid, "", 64)
				if uid == "" or usedUids[uid] then
					continue
				end
				local mutation = if type(entry.mutation) == "string" and Mutations.get(entry.mutation) then entry.mutation else nil
				local relic: Types.SaveRelic = {
					uid = uid,
					id = entry.id,
					level = math.floor(num(entry.level, 1, 1, GameConfig.Economy.MaxRelicLevel)),
					mutation = mutation,
					slot = math.floor(num(entry.slot, 0, 0, #Layout.SlotAngles)),
				}
				usedUids[uid] = true
				if relic.slot >= 1 and relic.slot <= unlocked and not usedSlots[relic.slot] then
					usedSlots[relic.slot] = true
					table.insert(data.relics, relic)
				else
					table.insert(overflow, relic)
				end
			end
		end
	end
	-- Re-home relics whose slot was invalid; anything beyond capacity is kept
	-- only while there is room (should never happen with consistent saves).
	for _, relic in overflow do
		for slot = 1, unlocked do
			if not usedSlots[slot] then
				usedSlots[slot] = true
				relic.slot = slot
				table.insert(data.relics, relic)
				break
			end
		end
	end

	return data
end

-- Plain table safe to hand to DataStore (no metatables, no instances).
function DataSchema.serialize(data: SaveData): { [string]: any }
	local relics = {}
	for _, relic in data.relics do
		table.insert(relics, {
			uid = relic.uid,
			id = relic.id,
			level = relic.level,
			mutation = relic.mutation,
			slot = relic.slot,
		})
	end
	local dex = {}
	for relicId, entry in data.dex do
		dex[relicId] = { count = entry.count, mutations = table.clone(entry.mutations), first = entry.first }
	end
	return {
		schema = DataSchema.Version,
		essence = data.essence,
		lifetimeEssence = data.lifetimeEssence,
		upgrades = table.clone(data.upgrades),
		relics = relics,
		dex = dex,
		coreStored = data.coreStored,
		lastSeen = data.lastSeen,
		playTime = data.playTime,
		stats = table.clone(data.stats),
		tutorial = data.tutorial,
		tips = table.clone(data.tips),
		settings = table.clone(data.settings),
		abilities = {
			unlocked = table.clone(data.abilities.unlocked),
			loadout = table.clone(data.abilities.loadout),
		},
		power = {
			peak = data.power.peak,
		},
	}
end

return DataSchema
