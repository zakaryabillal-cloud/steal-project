--!strict
-- Relic catalogue. To add a relic:
--   1. add an entry here (id, rarity, palette, shape),
--   2. add a shape builder with the same `shape` name in Shared/Relics/RelicShapes,
--   3. add its name + lore in Shared/Locale/Strings (en and fr).
-- Order in this list is the RiftDex order.

export type RelicDef = {
	id: string,
	rarity: string,
	shape: string,
	-- Fine-tunes Essence inside a rarity tier (1 = tier baseline).
	rateFactor: number,
	-- Relative weight inside its rarity tier. 0 = never spawns naturally.
	spawnWeight: number,
	-- Only spawns while this event is active (see Config/Events).
	eventOnly: string?,
	-- Boss-exclusive relic (V2 phase 6): never spawns in the Rift, only
	-- dropped by this boss and kept on non-stealable trophy pedestals.
	bossOnly: string?,
	primary: Color3,
	secondary: Color3,
	glow: Color3,
	dexIndex: number,
}

local Relics = {}

local list: { RelicDef } = {
	-- Common ----------------------------------------------------------------
	{
		id = "ember_shard",
		rarity = "Common",
		shape = "EmberShard",
		rateFactor = 1,
		spawnWeight = 1,
		primary = Color3.fromRGB(255, 120, 60),
		secondary = Color3.fromRGB(120, 40, 30),
		glow = Color3.fromRGB(255, 170, 90),
		dexIndex = 0,
	},
	{
		id = "verdant_seed",
		rarity = "Common",
		shape = "VerdantSeed",
		rateFactor = 1,
		spawnWeight = 1,
		primary = Color3.fromRGB(120, 200, 110),
		secondary = Color3.fromRGB(80, 60, 50),
		glow = Color3.fromRGB(190, 255, 150),
		dexIndex = 0,
	},
	{
		id = "tide_pearl",
		rarity = "Common",
		shape = "TidePearl",
		rateFactor = 1.05,
		spawnWeight = 1,
		primary = Color3.fromRGB(230, 245, 255),
		secondary = Color3.fromRGB(70, 150, 210),
		glow = Color3.fromRGB(150, 220, 255),
		dexIndex = 0,
	},
	{
		id = "rune_tablet",
		rarity = "Common",
		shape = "RuneTablet",
		rateFactor = 1.1,
		spawnWeight = 0.9,
		primary = Color3.fromRGB(120, 112, 140),
		secondary = Color3.fromRGB(80, 74, 100),
		glow = Color3.fromRGB(120, 240, 255),
		dexIndex = 0,
	},
	-- Uncommon --------------------------------------------------------------
	{
		id = "frost_lotus",
		rarity = "Uncommon",
		shape = "FrostLotus",
		rateFactor = 1,
		spawnWeight = 1,
		primary = Color3.fromRGB(190, 235, 255),
		secondary = Color3.fromRGB(120, 180, 240),
		glow = Color3.fromRGB(210, 250, 255),
		dexIndex = 0,
	},
	{
		id = "storm_crystal",
		rarity = "Uncommon",
		shape = "StormCrystal",
		rateFactor = 1.05,
		spawnWeight = 1,
		primary = Color3.fromRGB(150, 170, 255),
		secondary = Color3.fromRGB(60, 70, 120),
		glow = Color3.fromRGB(200, 220, 255),
		dexIndex = 0,
	},
	{
		id = "elder_root",
		rarity = "Uncommon",
		shape = "ElderRoot",
		rateFactor = 1.1,
		spawnWeight = 0.9,
		primary = Color3.fromRGB(120, 80, 60),
		secondary = Color3.fromRGB(90, 160, 80),
		glow = Color3.fromRGB(255, 200, 90),
		dexIndex = 0,
	},
	-- Rare ------------------------------------------------------------------
	{
		id = "ocean_orb",
		rarity = "Rare",
		shape = "OceanOrb",
		rateFactor = 1,
		spawnWeight = 1,
		primary = Color3.fromRGB(40, 140, 220),
		secondary = Color3.fromRGB(20, 60, 130),
		glow = Color3.fromRGB(90, 220, 255),
		dexIndex = 0,
	},
	{
		id = "lunar_fragment",
		rarity = "Rare",
		shape = "LunarFragment",
		rateFactor = 1.05,
		spawnWeight = 1,
		primary = Color3.fromRGB(225, 230, 245),
		secondary = Color3.fromRGB(150, 160, 200),
		glow = Color3.fromRGB(200, 215, 255),
		dexIndex = 0,
	},
	{
		id = "magma_heart",
		rarity = "Rare",
		shape = "MagmaHeart",
		rateFactor = 1.1,
		spawnWeight = 0.9,
		primary = Color3.fromRGB(60, 40, 45),
		secondary = Color3.fromRGB(255, 90, 30),
		glow = Color3.fromRGB(255, 140, 50),
		dexIndex = 0,
	},
	-- Epic ------------------------------------------------------------------
	{
		id = "void_cube",
		rarity = "Epic",
		shape = "VoidCube",
		rateFactor = 1,
		spawnWeight = 1,
		primary = Color3.fromRGB(70, 60, 110),
		secondary = Color3.fromRGB(10, 6, 20),
		glow = Color3.fromRGB(170, 110, 255),
		dexIndex = 0,
	},
	{
		id = "sun_fragment",
		rarity = "Epic",
		shape = "SunFragment",
		rateFactor = 1.05,
		spawnWeight = 1,
		primary = Color3.fromRGB(255, 210, 90),
		secondary = Color3.fromRGB(255, 130, 40),
		glow = Color3.fromRGB(255, 230, 140),
		dexIndex = 0,
	},
	{
		id = "chrono_glass",
		rarity = "Epic",
		shape = "ChronoGlass",
		rateFactor = 1.1,
		spawnWeight = 0.9,
		primary = Color3.fromRGB(190, 160, 110),
		secondary = Color3.fromRGB(200, 230, 255),
		glow = Color3.fromRGB(255, 220, 150),
		dexIndex = 0,
	},
	-- Legendary -------------------------------------------------------------
	{
		id = "cosmic_eye",
		rarity = "Legendary",
		shape = "CosmicEye",
		rateFactor = 1,
		spawnWeight = 1,
		primary = Color3.fromRGB(245, 240, 255),
		secondary = Color3.fromRGB(120, 60, 220),
		glow = Color3.fromRGB(190, 120, 255),
		dexIndex = 0,
	},
	{
		id = "astral_astrolabe",
		rarity = "Legendary",
		shape = "Astrolabe",
		rateFactor = 1.1,
		spawnWeight = 1,
		primary = Color3.fromRGB(230, 190, 110),
		secondary = Color3.fromRGB(40, 50, 100),
		glow = Color3.fromRGB(140, 200, 255),
		dexIndex = 0,
	},
	-- Mythic ----------------------------------------------------------------
	{
		id = "prismatic_anomaly",
		rarity = "Mythic",
		shape = "PrismaticAnomaly",
		rateFactor = 1,
		spawnWeight = 1,
		primary = Color3.fromRGB(255, 120, 200),
		secondary = Color3.fromRGB(120, 220, 255),
		glow = Color3.fromRGB(255, 255, 255),
		dexIndex = 0,
	},
	{
		id = "pocket_planet",
		rarity = "Mythic",
		shape = "PocketPlanet",
		rateFactor = 1.1,
		spawnWeight = 1,
		primary = Color3.fromRGB(70, 150, 220),
		secondary = Color3.fromRGB(110, 200, 120),
		glow = Color3.fromRGB(160, 220, 255),
		dexIndex = 0,
	},
	-- Secret ----------------------------------------------------------------
	{
		id = "rift_heart",
		rarity = "Secret",
		shape = "RiftHeart",
		rateFactor = 1,
		spawnWeight = 1,
		primary = Color3.fromRGB(200, 120, 255),
		secondary = Color3.fromRGB(10, 5, 25),
		glow = Color3.fromRGB(240, 210, 255),
		dexIndex = 0,
	},
	{
		id = "eclipse_sigil",
		rarity = "Secret",
		shape = "EclipseSigil",
		rateFactor = 1.15,
		spawnWeight = 0,
		eventOnly = "Eclipse",
		primary = Color3.fromRGB(8, 6, 12),
		secondary = Color3.fromRGB(255, 70, 40),
		glow = Color3.fromRGB(255, 170, 80),
		dexIndex = 0,
	},
	-- Boss relics (V2 phase 6) ----------------------------------------------
	{
		-- The Void Warden's favourite feather duster (he wants it back).
		id = "void_duster",
		rarity = "Legendary",
		shape = "VoidDuster",
		rateFactor = 1.1,
		spawnWeight = 0,
		bossOnly = "VoidWarden",
		primary = Color3.fromRGB(255, 150, 220),
		secondary = Color3.fromRGB(150, 96, 255),
		glow = Color3.fromRGB(255, 220, 120),
		dexIndex = 0,
	},
}

local byId: { [string]: RelicDef } = {}
local byRarity: { [string]: { RelicDef } } = {}
for index, def in list do
	def.dexIndex = index
	assert(byId[def.id] == nil, "Duplicate relic id " .. def.id)
	assert(def.bossOnly == nil or def.spawnWeight == 0, "boss relic " .. def.id .. " must never spawn in the Rift")
	byId[def.id] = def
	local bucket = byRarity[def.rarity]
	if not bucket then
		bucket = {}
		byRarity[def.rarity] = bucket
	end
	table.insert(bucket, def)
end

Relics.list = list
Relics.byId = byId
Relics.byRarity = byRarity
Relics.count = #list

function Relics.get(id: string): RelicDef?
	return byId[id]
end

return Relics
