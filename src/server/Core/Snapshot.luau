--!strict
-- Builds the private state sent to a player's client. Only data the client
-- needs for display; nothing here is ever trusted back.
--
-- The state is split in two (one Sync remote, merged by the client Store):
--   HOT  : small, changes constantly (Essence ticks, cooldowns, carrying,
--          status, Power). Sent whenever marked dirty, at most every
--          GameConfig.Sync.HotInterval.
--   COLD : larger, changes rarely (RiftDex, upgrades, stats, tutorial,
--          settings, loadout, Power record). Only included when marked with
--          Sessions.markCold. A periodic audit compares it with the last cold
--          payload sent and pushes it if a change was ever left unmarked
--          (counted in Snapshot.unmarkedColdChanges so tests catch it).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Types = require(script.Parent.Types)
local Sessions = require(script.Parent.Sessions)

local Snapshot = {}

-- Number of cold changes detected by the audit instead of an explicit mark.
Snapshot.unmarkedColdChanges = 0

-- Keys of each half (documentation + tests).
Snapshot.HotKeys = table.freeze({
	"essence", "lifetimeEssence", "plot", "carrying", "cooldowns", "rate", "multiplier", "noviceUntil", "power", "status",
	"harmonies",
})
Snapshot.ColdKeys = table.freeze({
	"upgrades", "dex", "stats", "tutorial", "tips", "settings", "canSave", "dataStatus", "loadout", "unlocked", "powerPeak",
	"harmonyOff", "cosmetics", "bosses", "materials", "trophies",
})

-- Status snapshot provider, injected by StatusService's owner (avoids a
-- Core -> Services dependency).
local statusProvider: ((Types.Session) -> { [string]: number })? = nil

function Snapshot.setStatusProvider(provider: (Types.Session) -> { [string]: number })
	statusProvider = provider
end

function Snapshot.hot(session: Types.Session): { [string]: any }
	local data = session.data
	local playTime = Sessions.playTime(session)
	return {
		essence = data.essence,
		lifetimeEssence = data.lifetimeEssence,
		plot = session.plot or 0,
		carrying = table.clone(session.carrying),
		cooldowns = table.clone(session.cooldowns),
		rate = session.rate,
		multiplier = session.multiplier,
		noviceUntil = workspace:GetServerTimeNow() + math.max(0, GameConfig.Steal.NoviceSeconds - playTime),
		power = session.power,
		status = if statusProvider then statusProvider(session) else {},
		-- Harmony relics displayed right now (they leave with a theft).
		harmonies = table.clone(session.harmonyRelics),
	}
end

-- Unlocked abilities as the client sees them (Studio test unlock included).
local allAbilities: { string } = {}
for _, def in require(ReplicatedStorage.Shared.Config.Abilities).list do
	table.insert(allAbilities, def.id)
end
function Snapshot.unlockedView(session: Types.Session): { [string]: boolean }
	local view = table.clone(session.data.abilities.unlocked)
	if session.devAbilities then
		for _, id in allAbilities do
			view[id] = true
		end
	end
	return view
end

-- Cosmetics as the client sees them (Studio test unlock included).
local allCosmetics: { string } = {}
for _, def in require(ReplicatedStorage.Shared.Config.Cosmetics).list do
	table.insert(allCosmetics, def.id)
end
function Snapshot.cosmeticsView(session: Types.Session): { [string]: any }
	local owned = table.clone(session.data.cosmetics.owned)
	if session.devCosmetics then
		for _, id in allCosmetics do
			owned[id] = true
		end
	end
	return { owned = owned, equipped = table.clone(session.data.cosmetics.equipped) }
end

-- Boss Codex as the client sees it (the anti-replay fight id stays private).
function Snapshot.codexView(session: Types.Session): { [string]: any }
	local view = {}
	for bossId, record in session.data.bosses do
		view[bossId] = {
			discovered = record.discovered,
			attempts = record.attempts,
			wins = record.wins,
			bestTime = record.bestTime,
			rare = table.clone(record.rare),
		}
	end
	return view
end

function Snapshot.trophiesView(session: Types.Session): { any }
	local view = {}
	for _, trophy in session.data.trophies do
		table.insert(view, { id = trophy.id, level = trophy.level, slot = trophy.slot })
	end
	return view
end

function Snapshot.cold(session: Types.Session): { [string]: any }
	local data = session.data
	local dex = {}
	for relicId, entry in data.dex do
		dex[relicId] = { count = entry.count, mutations = table.clone(entry.mutations) }
	end
	return {
		upgrades = table.clone(data.upgrades),
		dex = dex,
		stats = table.clone(data.stats),
		tutorial = data.tutorial,
		tips = table.clone(data.tips),
		settings = table.clone(data.settings),
		canSave = session.canSave,
		dataStatus = session.dataStatus,
		loadout = table.clone(data.abilities.loadout),
		unlocked = Snapshot.unlockedView(session),
		powerPeak = data.power.peak,
		harmonyOff = table.clone(data.abilities.harmonyOff),
		cosmetics = Snapshot.cosmeticsView(session),
		bosses = Snapshot.codexView(session),
		materials = table.clone(data.materials),
		trophies = Snapshot.trophiesView(session),
	}
end

-- Full state (hot + cold); used for the first Sync and by tests.
function Snapshot.build(session: Types.Session): { [string]: any }
	local payload = Snapshot.hot(session)
	for key, value in Snapshot.cold(session) do
		payload[key] = value
	end
	return payload
end

local function deepEqual(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for key, value in a do
		if not deepEqual(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end
Snapshot.deepEqual = deepEqual

-- Returns the payload to send now, or nil when nothing changed.
function Snapshot.next(session: Types.Session): { [string]: any }?
	if not session.dirty and not session.coldDirty then
		return nil
	end
	local payload = Snapshot.hot(session)
	if session.coldDirty or session.lastCold == nil then
		local cold = Snapshot.cold(session)
		for key, value in cold do
			payload[key] = value
		end
		session.lastCold = cold
	end
	session.dirty = false
	session.coldDirty = false
	return payload
end

-- Audit: re-checks the cold state; marks it dirty if it drifted unmarked.
function Snapshot.audit(session: Types.Session)
	local last = session.lastCold
	if last == nil or session.coldDirty then
		return
	end
	if not deepEqual(Snapshot.cold(session), last) then
		Snapshot.unmarkedColdChanges += 1
		Sessions.markCold(session)
	end
end

return Snapshot
