--!strict
-- Cosmetic catalogue (V2 phase 5): categories, the starting collection,
-- unlock rules and the performance budgets every effect must respect.
--
-- Cosmetics are PURELY visual. A definition only holds display data
-- (colours, sizes, particle rates, a title text): nothing here is read by any
-- gameplay system (speed, Power, Essence, cooldowns, ranges, theft, bosses,
-- drops, PvP). The asserts at the bottom refuse any other field.
--
-- Rendering is client-side (Client/Controllers/CosmeticRenderer) from what the
-- server publishes: player attributes "Cos_<category>" and the Sanctuary
-- model attribute "Theme". The server only validates ownership (CosmeticService).
--
-- To add a cosmetic: one entry in `list` (id, category, rarity, order, unlock,
-- visual), plus "cos.<id>" (name) in Shared/Locale/Strings (en and fr).
-- Only built-in Roblox textures (rbxasset://) are used: no external asset id.

local Cosmetics = {}

export type Unlock = {
	-- starter | power | stat | dex | tier | playtime  (granted automatically)
	-- boss | event | daily | premium                  (future phases: granted
	--                                                    only by their service)
	kind: string,
	-- Threshold (power, stat, dex, tier, playtime in seconds).
	value: number?,
	-- Save stat for kind = "stat" (data.stats key).
	stat: string?,
	-- Phase 10: MarketplaceService id (0 = not sold). Never read before then.
	productId: number?,
}

export type CosmeticDef = {
	id: string,
	category: string,
	rarity: string,
	order: number,
	unlock: Unlock,
	visual: { [string]: any },
}

export type CategoryDef = {
	id: string,
	order: number,
	-- Player attribute the server publishes the equipped id under.
	attribute: string,
	icon: string,
}

-- Categories (in UI order). Future categories (emotes, banners...) are added
-- here; future SOURCES (boss/event/daily/premium) need no new category.
Cosmetics.Categories = table.freeze({
	{ id = "trail", order = 1, attribute = "Cos_trail", icon = "dash" },
	{ id = "aura", order = 2, attribute = "Cos_aura", icon = "pulse" },
	{ id = "carry", order = 3, attribute = "Cos_carry", icon = "dex" },
	{ id = "sanctuary", order = 4, attribute = "Cos_sanctuary", icon = "seal" },
	{ id = "arrival", order = 5, attribute = "Cos_arrival", icon = "blink" },
	{ id = "secure", order = 6, attribute = "Cos_secure", icon = "essence" },
	{ id = "title", order = 7, attribute = "Cos_title", icon = "power" },
} :: { CategoryDef })

-- Unlock kinds. `auto` ones are checked by CosmeticService from data that
-- already exists; the others are reserved for the services of later phases.
Cosmetics.UnlockKinds = table.freeze({
	starter = { auto = true },
	power = { auto = true },
	stat = { auto = true },
	dex = { auto = true },
	tier = { auto = true },
	playtime = { auto = true },
	boss = { auto = false },
	event = { auto = false },
	daily = { auto = false },
	premium = { auto = false },
} :: { [string]: { auto: boolean } })

-- Save stats an achievement may use (all already counted by the game).
Cosmetics.Stats = table.freeze({ claimed = true, deposits = true, stolen = true, recovered = true, rareFinds = true })

Cosmetics.Rarities = table.freeze({ "Common", "Rare", "Epic", "Legendary" })

-- Performance budgets (client). Every visual is checked against them below.
Cosmetics.Budget = table.freeze({
	-- Effects of OTHER players beyond these distances (studs) are switched off.
	TrailDistance = 160,
	AuraDistance = 90,
	CarryDistance = 120,
	ThemeDistance = 220,
	TitleDistance = 60,
	-- At most this many other players' auras / aura lights at once (nearest first).
	MaxAuras = 8,
	MaxLights = 3,
	-- Per-effect caps.
	MaxRate = 12,
	MaxTrailLifetime = 0.6,
	MaxTrailWidth = 2,
	MaxParticleSize = 1.6,
	MaxBurstParticles = 40,
	-- One-shot effects (arrival / secure) of a player at most this often.
	OneShotCooldown = 1.5,
	-- Seconds a preview (try-on) lasts.
	PreviewSeconds = 5,
	-- The single update loop of the renderer runs this often.
	UpdateInterval = 0.25,
})

local function c(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function unlock(kind: string, value: number?, stat: string?): Unlock
	return { kind = kind, value = value, stat = stat }
end

local list: { CosmeticDef } = {
	-- Trails -------------------------------------------------------------------
	{ id = "trail_stardust", category = "trail", rarity = "Common", order = 1, unlock = unlock("starter"),
		visual = { colors = { c(235, 240, 255), c(170, 190, 255) }, lifetime = 0.35, width = 0.9, light = 0.6 } },
	{ id = "trail_riftwake", category = "trail", rarity = "Rare", order = 2, unlock = unlock("power", 150),
		visual = { colors = { c(150, 230, 255), c(170, 110, 255) }, lifetime = 0.45, width = 1.1, light = 0.9 } },
	{ id = "trail_tempest", category = "trail", rarity = "Epic", order = 3, unlock = unlock("stat", 5, "stolen"),
		visual = { colors = { c(255, 255, 255), c(110, 200, 255) }, lifetime = 0.5, width = 1.2, light = 1 } },
	{ id = "trail_voidwake", category = "trail", rarity = "Legendary", order = 4, unlock = unlock("power", 600),
		visual = { colors = { c(200, 130, 255), c(40, 10, 70) }, lifetime = 0.55, width = 1.4, light = 0.8 } },

	-- Auras --------------------------------------------------------------------
	{ id = "aura_embers", category = "aura", rarity = "Common", order = 1, unlock = unlock("stat", 10, "deposits"),
		visual = { color = c(255, 170, 90), color2 = c(255, 90, 40), rate = 5, size = 0.35, speed = 1.5, texture = "spark" } },
	{ id = "aura_frosthalo", category = "aura", rarity = "Rare", order = 2, unlock = unlock("stat", 3, "recovered"),
		visual = { color = c(200, 240, 255), color2 = c(120, 200, 255), rate = 6, size = 0.4, speed = 1, texture = "sparkle" } },
	{ id = "aura_celestial", category = "aura", rarity = "Epic", order = 3, unlock = unlock("dex", 12),
		visual = { color = c(255, 240, 180), color2 = c(170, 140, 255), rate = 8, size = 0.45, speed = 1.2, texture = "sparkle" } },
	{ id = "aura_eclipse", category = "aura", rarity = "Legendary", order = 4, unlock = unlock("stat", 5, "rareFinds"),
		visual = { color = c(255, 200, 120), color2 = c(60, 20, 90), rate = 10, size = 0.5, speed = 0.8, texture = "glow", light = { range = 8, brightness = 0.6 } } },

	-- Relic carry FX -------------------------------------------------------------
	{ id = "carry_glimmer", category = "carry", rarity = "Common", order = 1, unlock = unlock("starter"),
		visual = { color = c(240, 240, 255), color2 = c(180, 200, 255), rate = 5, size = 0.3, radius = 1.6 } },
	{ id = "carry_orbit", category = "carry", rarity = "Rare", order = 2, unlock = unlock("stat", 25, "claimed"),
		visual = { color = c(140, 230, 255), color2 = c(90, 140, 255), rate = 7, size = 0.35, radius = 2.2 } },
	{ id = "carry_comet", category = "carry", rarity = "Epic", order = 3, unlock = unlock("power", 300),
		visual = { color = c(255, 220, 140), color2 = c(255, 120, 200), rate = 9, size = 0.4, radius = 1.8 } },

	-- Sanctuary themes -------------------------------------------------------------
	{ id = "theme_dawn", category = "sanctuary", rarity = "Common", order = 1, unlock = unlock("starter"),
		visual = { accent = c(255, 196, 120), motes = c(255, 230, 190), rate = 3 } },
	{ id = "theme_nebula", category = "sanctuary", rarity = "Rare", order = 2, unlock = unlock("tier", 2),
		visual = { accent = c(230, 120, 255), motes = c(255, 170, 240), rate = 4 } },
	{ id = "theme_tempest", category = "sanctuary", rarity = "Epic", order = 3, unlock = unlock("tier", 3),
		visual = { accent = c(110, 210, 255), motes = c(220, 250, 255), rate = 5 } },
	{ id = "theme_singularity", category = "sanctuary", rarity = "Legendary", order = 4, unlock = unlock("power", 1000),
		visual = { accent = c(150, 80, 255), motes = c(40, 0, 70), rate = 6 } },

	-- Arrival (spawn) FX -----------------------------------------------------------
	{ id = "arrival_spark", category = "arrival", rarity = "Common", order = 1, unlock = unlock("starter"),
		visual = { color = c(220, 235, 255), color2 = c(150, 200, 255), size = 6, burst = 12, rings = 1 } },
	{ id = "arrival_riftgate", category = "arrival", rarity = "Rare", order = 2, unlock = unlock("power", 80),
		visual = { color = c(170, 120, 255), color2 = c(110, 230, 255), size = 8, burst = 20, rings = 2 } },
	{ id = "arrival_starfall", category = "arrival", rarity = "Epic", order = 3, unlock = unlock("playtime", 2 * 3600),
		visual = { color = c(255, 240, 190), color2 = c(255, 160, 90), size = 9, burst = 28, rings = 2, pillar = true } },

	-- Secure FX (a relic placed / a heist secured) ---------------------------------
	{ id = "secure_chime", category = "secure", rarity = "Common", order = 1, unlock = unlock("starter"),
		visual = { color = c(150, 245, 255), color2 = c(255, 255, 255), size = 5, burst = 10, rings = 1 } },
	{ id = "secure_fireworks", category = "secure", rarity = "Rare", order = 2, unlock = unlock("stat", 25, "deposits"),
		visual = { color = c(255, 200, 90), color2 = c(255, 110, 200), size = 7, burst = 24, rings = 2 } },
	{ id = "secure_supernova", category = "secure", rarity = "Legendary", order = 3, unlock = unlock("stat", 10, "stolen"),
		visual = { color = c(255, 250, 220), color2 = c(170, 90, 255), size = 10, burst = 36, rings = 3, pillar = true } },

	-- Titles ---------------------------------------------------------------------
	{ id = "title_drifter", category = "title", rarity = "Common", order = 1, unlock = unlock("starter"),
		visual = { color = c(205, 210, 230) } },
	{ id = "title_collector", category = "title", rarity = "Rare", order = 2, unlock = unlock("dex", 8),
		visual = { color = c(120, 190, 255) } },
	{ id = "title_heister", category = "title", rarity = "Epic", order = 3, unlock = unlock("stat", 3, "stolen"),
		visual = { color = c(190, 120, 255) } },
	{ id = "title_warden", category = "title", rarity = "Epic", order = 4, unlock = unlock("stat", 5, "recovered"),
		visual = { color = c(140, 240, 200) } },
	{ id = "title_riftborn", category = "title", rarity = "Legendary", order = 5, unlock = unlock("power", 500),
		visual = { color = c(255, 196, 80) } },
}

-- Allowed visual keys per category (display data only).
local VISUAL_KEYS: { [string]: { [string]: boolean } } = {
	trail = { colors = true, lifetime = true, width = true, light = true },
	aura = { color = true, color2 = true, rate = true, size = true, speed = true, texture = true, light = true },
	carry = { color = true, color2 = true, rate = true, size = true, radius = true },
	sanctuary = { accent = true, motes = true, rate = true },
	arrival = { color = true, color2 = true, size = true, burst = true, rings = true, pillar = true },
	secure = { color = true, color2 = true, size = true, burst = true, rings = true, pillar = true },
	title = { color = true },
}

-- Built-in particle textures (rbxasset://, shipped with every client).
Cosmetics.Textures = table.freeze({
	sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	spark = "rbxasset://textures/particles/fire_sparks_main.dds",
	glow = "rbxasset://textures/particles/forcefield_glow_main.dds",
})

local byId: { [string]: CosmeticDef } = {}
local categoryById: { [string]: CategoryDef } = {}
for _, category in Cosmetics.Categories do
	categoryById[category.id] = category
end

local B = Cosmetics.Budget
local lights = 0
for _, def in list do
	assert(byId[def.id] == nil, "duplicate cosmetic " .. def.id)
	assert(#def.id <= 32, "cosmetic id too long " .. def.id)
	assert(categoryById[def.category], "cosmetic " .. def.id .. " has unknown category " .. def.category)
	assert(table.find(Cosmetics.Rarities, def.rarity), "cosmetic " .. def.id .. " has unknown rarity")
	local kind = Cosmetics.UnlockKinds[def.unlock.kind]
	assert(kind, "cosmetic " .. def.id .. " has unknown unlock kind " .. def.unlock.kind)
	if def.unlock.kind == "stat" then
		assert(def.unlock.stat and Cosmetics.Stats[def.unlock.stat], "cosmetic " .. def.id .. " uses an unknown stat")
	end
	if def.unlock.kind ~= "starter" and kind.auto then
		assert(type(def.unlock.value) == "number" and def.unlock.value > 0, "cosmetic " .. def.id .. " needs a threshold")
	end
	-- Purely visual, inside the budgets.
	local allowed = VISUAL_KEYS[def.category]
	for key, value in def.visual do
		assert(allowed[key], "cosmetic " .. def.id .. ": '" .. key .. "' is not a visual field of " .. def.category)
		assert(type(value) ~= "string" or Cosmetics.Textures[value] ~= nil, "cosmetic " .. def.id .. ": only built-in textures")
	end
	local v = def.visual
	if v.rate then
		assert(v.rate <= B.MaxRate, "cosmetic " .. def.id .. " particle rate above budget")
	end
	if v.size and def.category ~= "arrival" and def.category ~= "secure" then
		assert(v.size <= B.MaxParticleSize, "cosmetic " .. def.id .. " particle size above budget")
	end
	if v.burst then
		assert(v.burst <= B.MaxBurstParticles, "cosmetic " .. def.id .. " burst above budget")
	end
	if def.category == "trail" then
		assert(v.lifetime <= B.MaxTrailLifetime and v.width <= B.MaxTrailWidth, "cosmetic " .. def.id .. " trail above budget")
	end
	if v.light then
		assert(def.category ~= "aura" or def.rarity == "Legendary", "only Legendary auras may carry a light")
		if def.category == "aura" then
			lights += 1
		end
	end
	byId[def.id] = def
end
assert(lights <= 2, "too many lit auras in the catalogue")
-- Every category has at least one starter or one automatic unlock to test with.
for _, category in Cosmetics.Categories do
	local any = false
	for _, def in list do
		if def.category == category.id and Cosmetics.UnlockKinds[def.unlock.kind].auto then
			any = true
		end
	end
	assert(any, "category " .. category.id .. " has nothing obtainable")
end

Cosmetics.list = list

function Cosmetics.get(id: any): CosmeticDef?
	if type(id) ~= "string" then
		return nil
	end
	return byId[id]
end

function Cosmetics.category(id: any): CategoryDef?
	if type(id) ~= "string" then
		return nil
	end
	return categoryById[id]
end

-- Ids every player owns from the start.
function Cosmetics.starters(): { [string]: boolean }
	local owned = {}
	for _, def in list do
		if def.unlock.kind == "starter" then
			owned[def.id] = true
		end
	end
	return owned
end

export type Progress = {
	powerPeak: number,
	stats: { [string]: number },
	dexFound: number,
	tier: number,
	playTime: number,
}

-- Is an automatic unlock met by `progress`? (false for future sources)
function Cosmetics.isMet(def: CosmeticDef, progress: Progress): boolean
	local u = def.unlock
	local value = u.value or 0
	if u.kind == "starter" then
		return true
	elseif u.kind == "power" then
		return progress.powerPeak >= value
	elseif u.kind == "stat" then
		return (progress.stats[u.stat :: string] or 0) >= value
	elseif u.kind == "dex" then
		return progress.dexFound >= value
	elseif u.kind == "tier" then
		return progress.tier >= value
	elseif u.kind == "playtime" then
		return progress.playTime >= value
	end
	return false
end

-- Progress fraction (0..1) towards an automatic unlock, for the UI.
function Cosmetics.progress(def: CosmeticDef, progress: Progress): number
	local u = def.unlock
	local value = u.value or 0
	if not Cosmetics.UnlockKinds[u.kind].auto then
		return 0
	end
	if u.kind == "starter" or value <= 0 then
		return 1
	end
	local current = 0
	if u.kind == "power" then
		current = progress.powerPeak
	elseif u.kind == "stat" then
		current = progress.stats[u.stat :: string] or 0
	elseif u.kind == "dex" then
		current = progress.dexFound
	elseif u.kind == "tier" then
		current = progress.tier
	elseif u.kind == "playtime" then
		current = progress.playTime
	end
	return math.clamp(current / value, 0, 1)
end

return Cosmetics
