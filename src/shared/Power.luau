--!strict
-- Pure Power Level formula, shared by the server (authoritative value) and the
-- client (breakdown display). See Config/Power for the coefficients.

local Config = script.Parent.Config
local PowerConfig = require(Config.Power)
local Relics = require(Config.Relics)
local Economy = require(script.Parent.Economy)

local Power = {}

export type RelicLike = { id: string, level: number, mutation: string? }

export type Breakdown = {
	relics: number,
	tier: number,
	dex: number,
	upgrades: number,
	total: number,
}

function Power.relic(relicId: string, level: number, mutation: string?): number
	local def = Relics.get(relicId)
	if not def then
		return 0
	end
	local base = PowerConfig.Rarity[def.rarity] or 0
	local levelFactor = 1 + PowerConfig.PerLevel * (math.clamp(math.floor(level), 1, 99) - 1)
	local mutationFactor = if mutation then PowerConfig.Mutation[mutation] or 1 else 1
	return base * levelFactor * mutationFactor
end

-- `relics` are the relics currently displayed in the Sanctuary.
function Power.breakdown(relics: { RelicLike }, upgrades: Economy.UpgradeLevels, relicsFound: number, mutationsFound: number): Breakdown
	local relicPower = 0
	for _, relic in relics do
		relicPower += Power.relic(relic.id, relic.level, relic.mutation)
	end
	local tier = Economy.tier(upgrades)
	local tierPower = PowerConfig.Tier[tier] or 0
	local dexPower = PowerConfig.PerRelicDiscovered * relicsFound + PowerConfig.PerMutationDiscovered * mutationsFound
	local upgradePower = PowerConfig.PerResonanceLevel * math.max(0, upgrades.resonance)
	local result: Breakdown = {
		relics = math.floor(relicPower + 0.5),
		tier = tierPower,
		dex = dexPower,
		upgrades = upgradePower,
		total = 0,
	}
	result.total = result.relics + result.tier + result.dex + result.upgrades
	return result
end

function Power.total(relics: { RelicLike }, upgrades: Economy.UpgradeLevels, relicsFound: number, mutationsFound: number): number
	return Power.breakdown(relics, upgrades, relicsFound, mutationsFound).total
end

return Power
