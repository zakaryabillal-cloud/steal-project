--!strict
-- Pure economy formulas shared by server (authoritative) and client (display).
-- Nothing here touches instances, so it is unit-tested in tests/.

local Config = script.Parent.Config
local GameConfig = require(Config.GameConfig)
local Rarities = require(Config.Rarities)
local Relics = require(Config.Relics)
local Mutations = require(Config.Mutations)
local Upgrades = require(Config.Upgrades)

local Economy = {}

export type UpgradeLevels = {
	pedestal: number,
	tier: number,
	resonance: number,
	stride: number,
	harness: number,
}

local E = GameConfig.Economy

function Economy.levelMultiplier(level: number): number
	local clamped = math.clamp(math.floor(level), 1, E.MaxRelicLevel)
	return 1 + E.LevelBonus * (clamped - 1)
end

-- Essence/s of a single relic before player-wide multipliers.
function Economy.relicBaseRate(relicId: string, level: number, mutation: string?): number
	local def = Relics.get(relicId)
	if not def then
		return 0
	end
	local rarity = Rarities.get(def.rarity)
	return rarity.rate * def.rateFactor * Economy.levelMultiplier(level) * Mutations.multiplier(mutation)
end

function Economy.resonanceMultiplier(level: number): number
	return 1 + E.ResonancePerLevel * math.max(0, level)
end

function Economy.dexMultiplier(relicsFound: number, mutationsFound: number): number
	return 1 + E.DexBonusPerRelic * relicsFound + E.DexBonusPerMutation * mutationsFound
end

function Economy.playerMultiplier(upgrades: UpgradeLevels, relicsFound: number, mutationsFound: number): number
	return Economy.resonanceMultiplier(upgrades.resonance) * Economy.dexMultiplier(relicsFound, mutationsFound)
end

function Economy.tier(upgrades: UpgradeLevels): number
	return math.clamp(upgrades.tier + 1, 1, #GameConfig.Sanctuary.TierMaxPedestals)
end

function Economy.coreCapacity(tier: number, ratePerSecond: number): number
	local base = E.CoreCapacity[math.clamp(tier, 1, #E.CoreCapacity)]
	return math.max(base, math.floor(ratePerSecond * E.CoreMinSeconds))
end

function Economy.tierMaxPedestals(tier: number): number
	local caps = GameConfig.Sanctuary.TierMaxPedestals
	return caps[math.clamp(tier, 1, #caps)]
end

function Economy.unlockedPedestals(upgrades: UpgradeLevels): number
	local tier = Economy.tier(upgrades)
	return math.min(GameConfig.Sanctuary.StartPedestals + upgrades.pedestal, Economy.tierMaxPedestals(tier))
end

function Economy.walkSpeed(strideLevel: number): number
	return GameConfig.Player.BaseWalkSpeed + GameConfig.Player.StridePerLevel * strideLevel
end

function Economy.carryCapacity(harnessLevel: number): number
	return GameConfig.Carry.BaseCapacity + harnessLevel
end

-- Returns the price of the next level, or nil when maxed.
function Economy.upgradeCost(upgradeId: string, currentLevel: number): number?
	local def = Upgrades.get(upgradeId)
	if not def or currentLevel >= def.maxLevel then
		return nil
	end
	return def.costs[currentLevel + 1]
end

-- Why an upgrade cannot be bought right now (ignoring price). nil = allowed.
function Economy.upgradeBlocker(upgradeId: string, upgrades: UpgradeLevels): string?
	local def = Upgrades.get(upgradeId)
	if not def then
		return "unknown"
	end
	local level = (upgrades :: any)[upgradeId] :: number
	if level >= def.maxLevel then
		return "max"
	end
	if upgradeId == "pedestal" then
		local unlocked = Economy.unlockedPedestals(upgrades)
		if unlocked >= Economy.tierMaxPedestals(Economy.tier(upgrades)) then
			return "needTier"
		end
	end
	return nil
end

function Economy.dissolveValue(relicId: string, level: number, mutation: string?, playerMultiplier: number): number
	return math.floor(Economy.relicBaseRate(relicId, level, mutation) * playerMultiplier * E.DissolveSeconds)
end

function Economy.carrySpeedMultiplier(relicIds: { string }): number
	local multiplier = 1
	for _, id in relicIds do
		local def = Relics.get(id)
		if def then
			multiplier *= Rarities.get(def.rarity).carrySpeed
		end
	end
	return multiplier
end

function Economy.defaultUpgrades(): UpgradeLevels
	return { pedestal = 0, tier = 0, resonance = 0, stride = 0, harness = 0 }
end

return Economy
