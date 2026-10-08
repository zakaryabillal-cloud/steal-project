--!strict
-- Client-side mirror of the player's private state (pushed by the server's
-- Sync snapshots). Read-only from the client's point of view.
--
-- Each Sync carries the hot fields (Essence, cooldowns, carrying, status,
-- Power) and, only when they changed, the cold fields (Dex, upgrades, loadout,
-- settings...). Payloads are merged into a NEW state table so `changed`
-- listeners can still compare (state, previous).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Signal = require(Shared.Util.Signal)
local Economy = require(Shared.Economy)
local Relics = require(Shared.Config.Relics)
local Abilities = require(Shared.Config.Abilities)
local Cosmetics = require(Shared.Config.Cosmetics)
local ClientNet = require(script.Parent.Parent.ClientNet)

export type State = {
	essence: number,
	lifetimeEssence: number,
	upgrades: Economy.UpgradeLevels,
	dex: { [string]: { count: number, mutations: { [string]: boolean } } },
	stats: { [string]: number },
	tutorial: number,
	tips: { [string]: boolean },
	settings: { sfx: number, music: number, quality: string, shake: boolean, language: string },
	plot: number,
	carrying: { string },
	cooldowns: { [string]: number },
	rate: number,
	multiplier: number,
	noviceUntil: number,
	canSave: boolean,
	dataStatus: string,
	-- V2
	power: number,
	powerPeak: number,
	loadout: { string },
	unlocked: { [string]: boolean },
	status: StatusView,
	-- Harmony relics displayed in the Sanctuary (hot) and the switched-off ones (cold).
	harmonies: { string },
	harmonyOff: { [string]: boolean },
	-- Cosmetics (cold): owned set and equipped id per category.
	cosmetics: { owned: { [string]: boolean }, equipped: { [string]: string } },
	-- Phase 6 (cold): boss Codex, materials, trophy pedestals.
	bosses: { [string]: CodexEntry },
	materials: { [string]: number },
	trophies: { { id: string, level: number, slot: number } },
}

export type CodexEntry = {
	discovered: boolean,
	attempts: number,
	wins: number,
	bestTime: number,
	rare: { [string]: number },
}

export type StatusView = {
	stunUntil: number,
	steadyUntil: number,
	rootUntil: number,
	slow: number,
	slowUntil: number,
	shieldUntil: number,
	phaseUntil: number,
}

local Store = {}

Store.state = {
	essence = 0,
	lifetimeEssence = 0,
	upgrades = Economy.defaultUpgrades(),
	dex = {},
	stats = {},
	tutorial = 0,
	tips = {},
	settings = { sfx = 1, music = 0.6, quality = "High", shake = true, language = "" },
	plot = 0,
	carrying = {},
	cooldowns = {},
	rate = 0,
	multiplier = 1,
	noviceUntil = 0,
	canSave = false,
	dataStatus = "pending",
	power = 0,
	powerPeak = 0,
	loadout = Abilities.defaultLoadout(),
	unlocked = Abilities.defaultUnlocked(),
	status = { stunUntil = 0, steadyUntil = 0, rootUntil = 0, slow = 0, slowUntil = 0, shieldUntil = 0, phaseUntil = 0 },
	harmonies = {},
	harmonyOff = {},
	cosmetics = { owned = Cosmetics.starters(), equipped = {} },
	bosses = {},
	materials = {},
	trophies = {},
} :: State

Store.ready = false
-- (state, previous)
Store.changed = Signal.new()
Store.becameReady = Signal.new()

function Store.init()
	ClientNet.onSync(function(snapshot)
		local previous = Store.state
		local merged = table.clone(previous :: any)
		for key, value in snapshot do
			merged[key] = value
		end
		Store.state = merged :: State
		local first = not Store.ready
		Store.ready = true
		Store.changed:Fire(Store.state, previous)
		if first then
			Store.becameReady:Fire()
		end
	end)
end

function Store.waitReady()
	if not Store.ready then
		Store.becameReady:Wait()
	end
end

function Store.now(): number
	return workspace:GetServerTimeNow()
end

function Store.dexCounts(): (number, number)
	local relics, mutations = 0, 0
	for relicId, entry in Store.state.dex do
		if Relics.get(relicId) then
			relics += 1
			for _ in entry.mutations do
				mutations += 1
			end
		end
	end
	return relics, mutations
end

function Store.plotModel(index: number?): Model?
	local plot = index or Store.state.plot
	if plot == nil or plot == 0 then
		return nil
	end
	local folder = workspace:FindFirstChild("Sanctuaries")
	return if folder then folder:FindFirstChild("Sanctuary" .. plot) :: Model? else nil
end

function Store.cooldownRemaining(key: string): number
	return math.max(0, (Store.state.cooldowns[key] or 0) - Store.now())
end

function Store.carryCapacity(): number
	return Economy.carryCapacity(Store.state.upgrades.harness)
end

function Store.localUserId(): number
	return Players.LocalPlayer.UserId
end

return Store
