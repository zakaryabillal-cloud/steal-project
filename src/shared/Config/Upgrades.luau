--!strict
-- Sanctuary upgrades. Costs are explicit tables so the economy is easy to read
-- and tune; `costs[n]` is the price to go from level n-1 to level n.

export type UpgradeDef = {
	id: string,
	order: number,
	maxLevel: number,
	costs: { number },
	-- Short machine-readable effect key, interpreted by Shared/Economy.
	effect: string,
}

local Upgrades = {}

local list: { UpgradeDef } = {
	{
		-- Each level unlocks one more pedestal (starting from GameConfig.Sanctuary.StartPedestals).
		id = "pedestal",
		order = 1,
		maxLevel = 9,
		costs = { 40, 120, 350, 900, 2200, 5000, 11000, 24000, 50000 },
		effect = "pedestals",
	},
	{
		-- Sanctuary tier (level 0 = tier 1 "Outpost"). Visually rebuilds the base.
		id = "tier",
		order = 2,
		maxLevel = 4,
		costs = { 600, 4000, 30000, 200000 },
		effect = "tier",
	},
	{
		id = "resonance",
		order = 3,
		maxLevel = 8,
		costs = { 300, 780, 2000, 5300, 13700, 35700, 92800, 241000 },
		effect = "essenceMultiplier",
	},
	{
		id = "stride",
		order = 4,
		maxLevel = 5,
		costs = { 150, 600, 2500, 9000, 30000 },
		effect = "walkSpeed",
	},
	{
		id = "harness",
		order = 5,
		maxLevel = 2,
		costs = { 2500, 40000 },
		effect = "carryCapacity",
	},
}

local byId: { [string]: UpgradeDef } = {}
for _, def in list do
	assert(#def.costs == def.maxLevel, "Upgrade " .. def.id .. " cost table does not match maxLevel")
	byId[def.id] = def
end

Upgrades.list = list
Upgrades.byId = byId

function Upgrades.get(id: string): UpgradeDef?
	return byId[id]
end

return Upgrades
