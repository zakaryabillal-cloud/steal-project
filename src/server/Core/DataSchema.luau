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
	}
end

-- Ordered migrations: MIGRATIONS[n] upgrades a schema-n table to schema n+1.
-- Add new entries here whenever the schema changes and bump SchemaVersion.
local MIGRATIONS: { [number]: (any) -> any } = {}

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

	local version = num(raw.schema, 1, 1)
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
	}
end

return DataSchema
