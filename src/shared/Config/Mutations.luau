--!strict
-- Mutations roll independently from rarity when a relic emerges. Each one
-- changes the model (materials, colours, extra VFX) and multiplies Essence.

export type Mutation = {
	id: string,
	order: number,
	-- Base chance per spawn (0..1). Events multiply these.
	chance: number,
	multiplier: number,
	color: Color3,
	accent: Color3,
}

local Mutations = {}

local list: { Mutation } = {
	{
		id = "Charged",
		order = 1,
		chance = 0.04,
		multiplier = 2,
		color = Color3.fromRGB(110, 235, 255),
		accent = Color3.fromRGB(230, 255, 255),
	},
	{
		id = "Golden",
		order = 2,
		chance = 0.02,
		multiplier = 3,
		color = Color3.fromRGB(255, 200, 70),
		accent = Color3.fromRGB(255, 244, 190),
	},
	{
		id = "Void",
		order = 3,
		chance = 0.01,
		multiplier = 4,
		color = Color3.fromRGB(130, 60, 255),
		accent = Color3.fromRGB(30, 10, 60),
	},
	{
		id = "Corrupted",
		order = 4,
		chance = 0.005,
		multiplier = 6,
		color = Color3.fromRGB(255, 40, 70),
		accent = Color3.fromRGB(25, 0, 10),
	},
	{
		id = "Prismatic",
		order = 5,
		chance = 0.0015,
		multiplier = 10,
		color = Color3.fromRGB(255, 255, 255),
		accent = Color3.fromRGB(255, 120, 220),
	},
}

local byId: { [string]: Mutation } = {}
for _, mutation in list do
	byId[mutation.id] = mutation
end

Mutations.list = list
Mutations.byId = byId

function Mutations.get(id: string?): Mutation?
	if id == nil or id == "" then
		return nil
	end
	return byId[id]
end

function Mutations.multiplier(id: string?): number
	local mutation = Mutations.get(id)
	return if mutation then mutation.multiplier else 1
end

return Mutations
