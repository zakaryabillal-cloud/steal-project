--!strict
-- Rarity tiers. Rarer tiers are not just recoloured: they scale up, get auras,
-- light pillars, orbiters, longer Rift charge-ups and server-wide moments.

export type RarityId = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic" | "Secret"

export type Rarity = {
	id: RarityId,
	order: number,
	-- Relative spawn weight out of 100.
	weight: number,
	-- Base Essence per second for a level 1, non-mutated relic of this tier.
	rate: number,
	color: Color3,
	glow: Color3,
	-- Visual dressing
	scale: number,
	lightRange: number,
	lightBrightness: number,
	particleRate: number,
	aura: boolean,
	pillar: boolean,
	orbiters: number,
	groundRing: boolean,
	-- Gameplay feel
	chargeTime: number,
	stealHold: number,
	carrySpeed: number,
	-- "none" | "nearby" | "server"
	announce: string,
}

local Rarities = {}

local list: { Rarity } = {
	{
		id = "Common",
		order = 1,
		weight = 56,
		rate = 1,
		color = Color3.fromRGB(196, 202, 218),
		glow = Color3.fromRGB(235, 240, 255),
		scale = 1,
		lightRange = 6,
		lightBrightness = 0.8,
		particleRate = 3,
		aura = false,
		pillar = false,
		orbiters = 0,
		groundRing = false,
		chargeTime = 1.1,
		stealHold = 1.2,
		carrySpeed = 0.97,
		announce = "none",
	},
	{
		id = "Uncommon",
		order = 2,
		weight = 25,
		rate = 3,
		color = Color3.fromRGB(104, 230, 140),
		glow = Color3.fromRGB(170, 255, 190),
		scale = 1.05,
		lightRange = 7,
		lightBrightness = 1,
		particleRate = 5,
		aura = false,
		pillar = false,
		orbiters = 0,
		groundRing = false,
		chargeTime = 1.2,
		stealHold = 1.5,
		carrySpeed = 0.95,
		announce = "none",
	},
	{
		id = "Rare",
		order = 3,
		weight = 12,
		rate = 8,
		color = Color3.fromRGB(74, 166, 255),
		glow = Color3.fromRGB(150, 210, 255),
		scale = 1.15,
		lightRange = 9,
		lightBrightness = 1.3,
		particleRate = 8,
		aura = false,
		pillar = false,
		orbiters = 1,
		groundRing = true,
		chargeTime = 1.5,
		stealHold = 2,
		carrySpeed = 0.93,
		announce = "nearby",
	},
	{
		id = "Epic",
		order = 4,
		weight = 5,
		rate = 22,
		color = Color3.fromRGB(184, 96, 255),
		glow = Color3.fromRGB(222, 170, 255),
		scale = 1.3,
		lightRange = 11,
		lightBrightness = 1.6,
		particleRate = 12,
		aura = true,
		pillar = false,
		orbiters = 2,
		groundRing = true,
		chargeTime = 1.9,
		stealHold = 2.5,
		carrySpeed = 0.9,
		announce = "nearby",
	},
	{
		id = "Legendary",
		order = 5,
		weight = 1.6,
		rate = 60,
		color = Color3.fromRGB(255, 186, 56),
		glow = Color3.fromRGB(255, 226, 150),
		scale = 1.5,
		lightRange = 14,
		lightBrightness = 2,
		particleRate = 18,
		aura = true,
		pillar = true,
		orbiters = 3,
		groundRing = true,
		chargeTime = 2.7,
		stealHold = 3,
		carrySpeed = 0.87,
		announce = "server",
	},
	{
		id = "Mythic",
		order = 6,
		weight = 0.36,
		rate = 160,
		color = Color3.fromRGB(255, 72, 132),
		glow = Color3.fromRGB(255, 160, 200),
		scale = 1.7,
		lightRange = 16,
		lightBrightness = 2.4,
		particleRate = 24,
		aura = true,
		pillar = true,
		orbiters = 4,
		groundRing = true,
		chargeTime = 3.4,
		stealHold = 3.5,
		carrySpeed = 0.84,
		announce = "server",
	},
	{
		id = "Secret",
		order = 7,
		weight = 0.04,
		rate = 450,
		color = Color3.fromRGB(235, 235, 255),
		glow = Color3.fromRGB(20, 12, 40),
		scale = 1.9,
		lightRange = 18,
		lightBrightness = 2.8,
		particleRate = 30,
		aura = true,
		pillar = true,
		orbiters = 5,
		groundRing = true,
		chargeTime = 4.2,
		stealHold = 4,
		carrySpeed = 0.8,
		announce = "server",
	},
}

local byId: { [string]: Rarity } = {}
for _, rarity in list do
	byId[rarity.id] = rarity
end

Rarities.list = list
Rarities.byId = byId

function Rarities.get(id: string): Rarity
	local rarity = byId[id]
	assert(rarity, "Unknown rarity " .. tostring(id))
	return rarity
end

function Rarities.isAtLeast(id: string, threshold: string): boolean
	return Rarities.get(id).order >= Rarities.get(threshold).order
end

return Rarities
