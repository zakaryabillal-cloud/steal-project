--!strict
-- Weighted random rolls for Rift spawns. Pure functions taking an RNG so they
-- can be tested deterministically. Boss relics (bossOnly) never come out of
-- the Rift: they are only dropped by their boss (BossService).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Rarities = require(Shared.Config.Rarities)
local Relics = require(Shared.Config.Relics)
local Mutations = require(Shared.Config.Mutations)
local Events = require(Shared.Config.Events)

local Rolls = {}

export type Roll = {
	relicId: string,
	rarity: string,
	mutation: string?,
}

function Rolls.rarity(rng: Random, boosts: { [string]: number }?): string
	local total = 0
	for _, rarity in Rarities.list do
		total += rarity.weight * ((boosts and boosts[rarity.id]) or 1)
	end
	local pick = rng:NextNumber() * total
	for _, rarity in Rarities.list do
		pick -= rarity.weight * ((boosts and boosts[rarity.id]) or 1)
		if pick <= 0 then
			return rarity.id
		end
	end
	return Rarities.list[1].id
end

function Rolls.relic(rng: Random, rarityId: string, eventId: string?): Relics.RelicDef
	local pool: { Relics.RelicDef } = Relics.byRarity[rarityId] or {}
	local function spawnable(def: Relics.RelicDef): boolean
		return def.bossOnly == nil and def.spawnWeight > 0 and (def.eventOnly == nil or def.eventOnly == eventId)
	end
	local total = 0
	for _, def in pool do
		if spawnable(def) then
			total += def.spawnWeight
		end
	end
	if total <= 0 then
		-- Tier has nothing spawnable right now: fall back one tier down.
		local order = Rarities.get(rarityId).order
		local lower = Rarities.list[math.max(1, order - 1)]
		if lower.id == rarityId then
			return Relics.list[1]
		end
		return Rolls.relic(rng, lower.id, eventId)
	end
	local pick = rng:NextNumber() * total
	local last: Relics.RelicDef? = nil
	for _, def in pool do
		if spawnable(def) then
			last = def
			pick -= def.spawnWeight
			if pick <= 0 then
				return def
			end
		end
	end
	return last or pool[1]
end

function Rolls.mutation(rng: Random, boosts: { [string]: number }?): string?
	-- Rarest first so common mutations never mask rare ones.
	for i = #Mutations.list, 1, -1 do
		local mutation = Mutations.list[i]
		local chance = mutation.chance * ((boosts and boosts[mutation.id]) or 1)
		if rng:NextNumber() < chance then
			return mutation.id
		end
	end
	return nil
end

function Rolls.spawn(rng: Random, eventId: string?): Roll
	local event = Events.get(eventId)
	if event and event.specialRelic and event.specialChance and rng:NextNumber() < event.specialChance then
		local def = Relics.get(event.specialRelic)
		if def then
			return { relicId = def.id, rarity = def.rarity, mutation = Rolls.mutation(rng, event.mutationBoost) }
		end
	end
	local rarity = Rolls.rarity(rng, event and event.rarityBoost)
	local def = Rolls.relic(rng, rarity, eventId)
	return {
		relicId = def.id,
		rarity = def.rarity,
		mutation = Rolls.mutation(rng, event and event.mutationBoost),
	}
end

return Rolls
