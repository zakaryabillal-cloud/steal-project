--!strict
-- Boss weapons (V2 phase 6.5). Used ONLY to hit bosses inside an expedition:
-- nothing in the island's PvP (theft, abilities, protections, Power) reads
-- this file (tests/scenarios/V2Combat.luau scans the sources).
--
-- One weapon equipped at a time; the inventory is saved (schema 6). Weapons
-- are bought with Essence (some also with boss materials) once their unlock
-- condition (boss victories) is met. The server validates every purchase,
-- every equip and computes every hit (Services/WeaponService, BossService).
--
-- Prices come from the real economy (simulated in the phase 6.5 report):
-- a casual player (a relic every ~90 s, thefts, chases) makes ~130 Essence/s
-- at 20 min, ~1 000/s after 1 h, ~2 300/s after 2 h; an active one ~1.5x
-- that. Every Sanctuary upgrade (~0.8 M in total) is bought around the
-- first hour, so weapons become the long-term Essence sink:
--   Squeaky Mallet   25 k   first session (about one upgrade step)
--   Bubble Blaster  120 k   after the first victory
--   Star Wand       400 k   + 10 Void Shards, 2 victories
--   Giant Plunger   1.5 M   + 20 Shards + 1 Catalyst, 5 victories
--   Rainbow Hammer  6 M     + 40 Shards + 2 Catalysts, 10 victories (prestige)
-- Boss materials drop 3-6 Shards per victory and a Catalyst 15 % of the time:
-- the whole collection takes ~20 victories (several sessions, a fight every
-- 10 min), never an endless grind.
--
-- DPS stays bounded (prestige = 1.55x the free gloves) so veterans still
-- have to dodge: the boss is beaten by reading his attacks, not by stats.

local Weapons = {}

export type Special = {
	-- none | heavy | ranged | teamBuff | dizzyBonus | heal
	kind: string,
	-- teamBuff: damage bonus for every fighter; dizzyBonus: multiplier.
	value: number?,
	-- teamBuff duration / heal cooldown (seconds).
	duration: number?,
}

export type Price = {
	essence: number,
	-- materialId -> amount (Config/Materials).
	materials: { [string]: number },
}

export type WeaponDef = {
	id: string,
	order: number,
	-- Common | Rare | Epic | Legendary (display: stars + colour)
	rarity: string,
	-- Animation family: punch | smash | shoot | zap | thrust
	style: string,
	-- Damage of a normal hit, seconds between two hits, reach (studs from
	-- the boss's body), and the 3-hit combo multipliers (hit 3 = finisher).
	damage: number,
	cooldown: number,
	reach: number,
	combo: { number },
	special: Special,
	price: Price,
	-- Boss victories needed before it can be bought (0 = none).
	wins: number,
	-- Free starter weapon (always owned).
	starter: boolean?,
	-- Config/Emoji glyph shown on cards and on the Strike button.
	emoji: string,
	-- Display data for Shared/Weapons/WeaponModels (native parts only).
	visual: { [string]: any },
}

-- Seconds after a hit during which the next hit continues the combo.
Weapons.ComboWindow = 1.1
-- Highest damage-per-second ratio any weapon may reach against the starter.
Weapons.MaxDpsRatio = 1.6

local function c(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function price(essence: number, materials: { [string]: number }?): Price
	return { essence = essence, materials = materials or {} }
end

local list: { WeaponDef } = {
	{
		id = "foam_gloves",
		order = 1,
		rarity = "Common",
		style = "punch",
		damage = 10,
		cooldown = 0.4,
		reach = 10,
		combo = { 1, 1, 1.5 },
		special = { kind = "none" },
		price = price(0),
		wins = 0,
		starter = true,
		emoji = "weapons",
		visual = { kind = "gloves", color = c(255, 84, 96), cuff = c(255, 246, 229) },
	},
	{
		id = "squeaky_mallet",
		order = 2,
		rarity = "Rare",
		style = "smash",
		damage = 17,
		cooldown = 0.62,
		reach = 11,
		combo = { 1, 1, 2 },
		special = { kind = "heavy" },
		price = price(25000),
		wins = 0,
		emoji = "hammer",
		visual = { kind = "mallet", head = c(255, 120, 200), band = c(255, 246, 229), handle = c(255, 205, 50) },
	},
	{
		id = "bubble_blaster",
		order = 3,
		rarity = "Rare",
		style = "shoot",
		damage = 7,
		cooldown = 0.3,
		reach = 28,
		combo = { 1, 1, 1.3 },
		special = { kind = "ranged" },
		price = price(120000),
		wins = 1,
		emoji = "splash",
		visual = { kind = "blaster", body = c(90, 190, 255), tank = c(170, 240, 255), barrel = c(255, 140, 210) },
	},
	{
		id = "star_wand",
		order = 4,
		rarity = "Epic",
		style = "zap",
		damage = 9,
		cooldown = 0.34,
		reach = 18,
		combo = { 1, 1, 1.5 },
		special = { kind = "teamBuff", value = 0.15, duration = 5 },
		price = price(400000, { void_shard = 10 }),
		wins = 2,
		emoji = "star",
		visual = { kind = "wand", stick = c(255, 246, 229), star = c(255, 214, 72) },
	},
	{
		id = "giant_plunger",
		order = 5,
		rarity = "Epic",
		style = "thrust",
		damage = 12,
		cooldown = 0.42,
		reach = 11,
		combo = { 1, 1, 2.1 },
		special = { kind = "dizzyBonus", value = 1.5 },
		price = price(1500000, { void_shard = 20, void_catalyst = 1 }),
		wins = 5,
		emoji = "strong",
		visual = { kind = "plunger", cup = c(255, 70, 90), stick = c(196, 120, 70) },
	},
	{
		id = "rainbow_hammer",
		order = 6,
		rarity = "Legendary",
		style = "smash",
		damage = 14,
		cooldown = 0.46,
		reach = 13,
		combo = { 1, 1.15, 2.3 },
		special = { kind = "heal", duration = 15 },
		price = price(6000000, { void_shard = 40, void_catalyst = 2 }),
		wins = 10,
		emoji = "rainbow",
		visual = { kind = "hammer", colors = { c(255, 84, 96), c(255, 214, 72), c(90, 190, 255) }, handle = c(255, 205, 50) },
	},
}

-- Pure formulas -----------------------------------------------------------------

-- Average damage per second of a full combo loop (no bonus).
function Weapons.dps(def: WeaponDef): number
	local total = 0
	for _, k in def.combo do
		total += k
	end
	return def.damage * (total / #def.combo) / def.cooldown
end

-- Combo step after a hit at `now` (previous step / time). 1..#combo.
function Weapons.nextCombo(def: WeaponDef, previousStep: number, lastHitAt: number, now: number): number
	if now - lastHitAt > Weapons.ComboWindow or previousStep >= #def.combo or previousStep < 1 then
		return 1
	end
	return previousStep + 1
end

-- Validation ------------------------------------------------------------------
local byId: { [string]: WeaponDef } = {}
local starter: WeaponDef? = nil
local VALID_STYLES = { punch = true, smash = true, shoot = true, zap = true, thrust = true }
local VALID_SPECIALS = { none = true, heavy = true, ranged = true, teamBuff = true, dizzyBonus = true, heal = true }
for _, def in list do
	assert(byId[def.id] == nil, "duplicate weapon " .. def.id)
	assert(#def.id <= 32, "weapon id too long " .. def.id)
	assert(VALID_STYLES[def.style], "weapon " .. def.id .. " has an unknown style")
	assert(VALID_SPECIALS[def.special.kind], "weapon " .. def.id .. " has an unknown special")
	assert(def.damage > 0 and def.cooldown >= 0.25 and def.reach > 0 and #def.combo == 3, "weapon " .. def.id .. " stats out of range")
	assert(def.price.essence >= 0 and def.wins >= 0, "weapon " .. def.id .. " price out of range")
	if def.starter then
		assert(starter == nil, "only one starter weapon")
		assert(def.price.essence == 0 and next(def.price.materials) == nil and def.wins == 0, "the starter weapon is free")
		starter = def
	end
	byId[def.id] = def
end
assert(starter, "a starter weapon is required")
for _, def in list do
	assert(Weapons.dps(def) <= Weapons.dps(starter :: WeaponDef) * Weapons.MaxDpsRatio + 1e-6, "weapon " .. def.id .. " is too strong (DPS cap)")
end

Weapons.list = list
Weapons.byId = byId
Weapons.Starter = (starter :: WeaponDef).id

function Weapons.get(id: any): WeaponDef?
	if type(id) ~= "string" then
		return nil
	end
	return byId[id]
end

-- Total boss victories counted for unlocks (every boss of the Codex).
function Weapons.totalWins(codex: { [string]: any }?): number
	local wins = 0
	if type(codex) == "table" then
		for _, record in codex do
			if type(record) == "table" and type(record.wins) == "number" then
				wins += record.wins
			end
		end
	end
	return wins
end

-- Why `def` cannot be bought (nil = it can). Pure: used by the server
-- (authority) and by the shop (display).
--   owned | wins | essence | materials
function Weapons.blocker(def: WeaponDef, owned: { [string]: boolean }, essence: number, materials: { [string]: number }, wins: number): string?
	if owned[def.id] or def.starter then
		return "owned"
	end
	if wins < def.wins then
		return "wins"
	end
	if essence < def.price.essence then
		return "essence"
	end
	for materialId, amount in def.price.materials do
		if (materials[materialId] or 0) < amount then
			return "materials"
		end
	end
	return nil
end

return Weapons
