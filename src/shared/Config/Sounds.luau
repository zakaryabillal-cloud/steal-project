--!strict
-- Audio registry. Every gameplay sound goes through a key in this table.
--
--   id       : your uploaded/licensed asset ("rbxassetid://123..."). Leave "" until you have one.
--   fallback : a sound that ships inside every Roblox client (rbxasset://sounds/...),
--              used while `id` is empty so the game is never silent. "" = silent.
--   note     : what the final sound should be. See README "Audio" for the full list.
--
-- Do not invent asset ids: only paste ids you uploaded or that are licensed to you.
--
-- Phase 7A: every `id` is CHECKED by the client when the game starts
-- (Controllers/AudioCheck: ContentProvider:PreloadAsync + Sound.TimeLength).
-- An id is used only once it loaded fine (asset exists, the experience may
-- play it, length within `maxLength`); until then, or if it fails, the
-- built-in `fallback` plays and the Output says which id failed and why.
--
-- Mixing (phase 7A): `priority` 1 = imminent danger, 2 = special attack,
-- 3 = impact / damage, 4 = ordinary attack & feedback (default), 5 =
-- ambience. Priority 1-2 briefly duck the music; when too many sounds play
-- at once the lowest priority gives way. `minGap` = seconds between two
-- plays of the same key (no spam with 8 players).

export type SoundDef = {
	id: string,
	fallback: string,
	volume: number,
	pitch: number,
	-- Random +/- pitch spread applied per play.
	variance: number,
	looped: boolean,
	note: string,
	-- Phase 7A mixing (see the header). nil = 4 / no gap / no length check.
	priority: number?,
	minGap: number?,
	-- An `id` longer than this (seconds) is refused (e.g. a music track
	-- pasted into a short sound effect slot).
	maxLength: number?,
	-- Where the id comes from ("user candidate, to verify in Studio"...).
	source: string?,
}

local SLIDER = "rbxasset://sounds/volume_slider.ogg"
local JUMP = "rbxasset://sounds/action_jump.mp3"
local LAND = "rbxasset://sounds/action_jump_land.mp3"
local BOOM = "rbxasset://sounds/impact_explosion_03.mp3"
local WATER = "rbxasset://sounds/impact_water.mp3"
local WIND = "rbxasset://sounds/action_falling.ogg"

local function def(fallback: string, volume: number, pitch: number, variance: number, note: string, looped: boolean?): SoundDef
	return {
		id = "",
		fallback = fallback,
		volume = volume,
		pitch = pitch,
		variance = variance,
		looped = looped == true,
		note = note,
	}
end

-- A sound with mixing options (phase 7A).
local function mix(sound: SoundDef, priority: number, minGap: number?): SoundDef
	sound.priority = priority
	sound.minGap = minGap
	return sound
end

-- A candidate asset id proposed by the game's creator: used only after the
-- client verified it (Controllers/AudioCheck), the fallback plays otherwise.
local function candidate(sound: SoundDef, id: string, maxLength: number): SoundDef
	sound.id = id
	sound.maxLength = maxLength
	sound.source = "creator candidate (phase 7A brief), verified at runtime"
	return sound
end

local Sounds: { [string]: SoundDef } = {
	-- UI ---------------------------------------------------------------------
	UiHover = def(SLIDER, 0.18, 1.9, 0.05, "Very short soft tick (10-30ms)."),
	UiClick = def(SLIDER, 0.45, 1.2, 0.04, "Crisp UI click, slightly glassy."),
	UiOpen = def(JUMP, 0.22, 1.6, 0, "Soft airy whoosh up, ~200ms."),
	UiClose = def(JUMP, 0.18, 1.25, 0, "Soft whoosh down, ~150ms."),
	UiError = def(SLIDER, 0.4, 0.55, 0, "Muted 'denied' blip, low and short."),
	Notify = def(SLIDER, 0.3, 1.5, 0.03, "Gentle notification chime."),

	-- Rift -------------------------------------------------------------------
	RiftHum = def(WIND, 0.12, 0.32, 0, "Deep looping magical drone for the Rift (3D, seamless loop).", true),
	RiftCharge = def(WIND, 0.35, 0.7, 0, "Rising energy charge-up, 1-4s, gets pitched up by rarity."),
	RelicEmerge = def(JUMP, 0.5, 0.9, 0.06, "Magical 'pop' / burst as a relic is ejected."),
	RareEmerge = def(BOOM, 0.55, 0.55, 0, "Huge cinematic impact + shimmering tail for Legendary+."),

	-- Relics -----------------------------------------------------------------
	Pickup = def(JUMP, 0.45, 1.7, 0.08, "Bright sparkly grab sound."),
	Deposit = def(LAND, 0.7, 0.75, 0.05, "Heavy satisfying 'clunk' of a relic locking into a pedestal."),
	Fuse = def(BOOM, 0.3, 1.6, 0.04, "Crystalline merge/level-up chime."),
	Dissolve = def(WIND, 0.3, 1.6, 0, "Reverse-swell dissolve whoosh."),
	EssenceTick = def(SLIDER, 0.22, 1.4, 0, "Tiny coin-like tick, pitched up per tick."),
	EssenceCollect = def(LAND, 0.4, 1.5, 0.04, "Whoosh + shimmer when absorbing the Core."),

	-- Progression ------------------------------------------------------------
	Purchase = def(BOOM, 0.22, 2.1, 0.04, "Positive purchase stinger."),
	TierUp = def(BOOM, 0.5, 0.8, 0, "Epic build-up + choir hit when the Sanctuary ascends."),
	Discovery = def(BOOM, 0.25, 2.4, 0, "Magical reveal fanfare (1-2s) for a new RiftDex entry."),

	-- Theft ------------------------------------------------------------------
	StealAlert = def(SLIDER, 0.6, 0.5, 0, "Urgent alarm pulse (repeats while a theft is in progress)."),
	StealGrab = def(JUMP, 0.5, 0.65, 0, "Sneaky snatch whoosh."),
	HeistSecured = def(BOOM, 0.45, 0.95, 0, "Triumphant heist stinger."),
	Recovered = def(LAND, 0.55, 1.25, 0, "Relieved 'restore' chime."),
	Seal = def(BOOM, 0.3, 1.8, 0, "Force-field activation hum."),

	-- Combat -----------------------------------------------------------------
	Dash = def(JUMP, 0.45, 0.8, 0.05, "Fast air dash whoosh."),
	Pulse = def(BOOM, 0.4, 1.3, 0.05, "Punchy shockwave thump."),
	Hit = def(LAND, 0.6, 0.6, 0.05, "Impact thud for getting knocked back."),
	Splash = def(WATER, 0.5, 1, 0.08, "Water splash."),

	-- V2 abilities (built-in fallbacks until you upload your own) -------------
	BlinkCharge = def(WIND, 0.35, 2.2, 0, "Short rising shimmer (0.3s) before a Blink."),
	Blink = def(JUMP, 0.5, 1.9, 0.05, "Snappy teleport 'zip' + sparkle."),
	Grapple = def(JUMP, 0.45, 0.6, 0.04, "Hook throw + cable whir."),
	FrostWave = def(WATER, 0.45, 1.6, 0.04, "Icy crackle burst, crystalline."),
	EruptionCharge = def(WIND, 0.4, 0.5, 0, "Low magma rumble building up (0.35s)."),
	Eruption = def(BOOM, 0.55, 0.75, 0.04, "Heavy molten blast."),
	TrapPlace = def(LAND, 0.4, 1.4, 0.04, "Rune stamped into the ground, soft magical thud."),
	TrapTrigger = def(BOOM, 0.4, 1.9, 0.04, "Rune snap + binding chime."),
	Shield = def(BOOM, 0.3, 2.2, 0, "Bright force-field shimmer."),
	Phase = def(WIND, 0.4, 1.8, 0, "Ghostly airy whoosh."),
	Decoy = def(JUMP, 0.35, 1.2, 0.05, "Quick illusion 'pop-in'."),
	DecoyPop = def(SLIDER, 0.45, 0.8, 0.05, "Illusion bursting like a soap bubble."),

	-- World ------------------------------------------------------------------
	EventStart = def(BOOM, 0.4, 0.45, 0, "Deep horn / sky rumble announcing a Rift event."),

	-- V2 phase 6.5: boss fight readability + combat (built-in fallbacks) -----
	-- One distinct warning per attack, played when its telegraph appears.
	BossWarnWave = def(WIND, 0.5, 1.45, 0, "Broom wind-up: rising cartoon whoosh (0.8-1.2s)."),
	BossWarnGoo = def(WATER, 0.45, 1.75, 0.03, "Bubbly 'bloop-bloop' of goo about to splat."),
	BossWarnBunny = def(JUMP, 0.5, 0.6, 0.04, "Springy 'boing' of dust bunnies being thrown."),
	BossWarnFlop = def(WIND, 0.5, 0.35, 0, "Deep falling whistle before a belly flop."),
	BossWarnCleanup = mix(def(SLIDER, 0.6, 0.42, 0, "Silly alarm 'wee-woo' for the Big Cleanup special (siren, then the sweep)."), 2),
	-- The telegraph turns red: danger NOW.
	BossDanger = mix(def(SLIDER, 0.55, 2.2, 0, "Sharp short 'tick!' when a zone turns red."), 1, 0.2),
	BossImpact = mix(def(LAND, 0.6, 0.55, 0.05, "Heavy squishy impact of an attack landing."), 3, 0.08),
	-- Player combat.
	PunchSwing = def(JUMP, 0.35, 2.1, 0.08, "Quick cartoon swoosh of a swing."),
	PunchHit = def(LAND, 0.55, 1.45, 0.08, "Bouncy 'bonk' on the jelly boss."),
	PunchFinisher = def(BOOM, 0.5, 1.25, 0.04, "Big 'KAPOW' of a combo finisher."),
	Squeak = def(SLIDER, 0.4, 2.8, 0.06, "Rubber squeak of the Squeaky Mallet."),
	Dodge = def(JUMP, 0.4, 1.9, 0.04, "Happy 'whoop' when you dodge an attack."),
	HeartLost = mix(def(LAND, 0.55, 0.5, 0, "Soft 'oof' when you lose a heart (never scary)."), 3),
	Block = def(SLIDER, 0.5, 1.6, 0, "Shield 'ding' blocking a boss hit."),
	WeaponBuy = def(BOOM, 0.4, 1.4, 0, "Shiny 'ta-da' for a new boss weapon."),
	PunchHitRock = def(LAND, 0.55, 0.95, 0.08, "Rocky 'clonk' when you hit Forgeheart."),
	BossPhaseUp = mix(def(WIND, 0.45, 0.8, 0, "Rising 'whoosh-up' when a boss enters a new phase (the music gets brighter, never faster)."), 2, 1),

	-- V2 phase 7A: VOID WARDEN identity (bouncy, cartoon, chaotic) -------------
	VWAppear = mix(candidate(def(JUMP, 0.6, 0.55, 0, "Big cartoon BOING when he appears."), "rbxassetid://5048722308", 4), 3, 1),
	VWHop = mix(candidate(def(JUMP, 0.6, 0.7, 0.03, "BOING then SPLAT: belly flop take-off."), "rbxassetid://2772396665", 4), 4, 0.3),
	VWBounce = mix(candidate(def(JUMP, 0.45, 1.3, 0.05, "Small bounce of the jelly body."), "rbxassetid://1885641628", 3), 4, 0.4),
	VWImpact = mix(candidate(def(BOOM, 0.6, 1.1, 0.03, "Comic BOOM of the belly flop landing."), "rbxassetid://2103404398", 4), 3, 0.2),
	VWSweep = mix(def(WIND, 0.55, 1.6, 0.04, "SWOOSH then PAF of the broom (to source: no verified id)."), 4, 0.3),
	VWGooSplat = mix(def(WATER, 0.5, 0.75, 0.06, "BLOUP / slime splat of a sticky puddle (to source)."), 4, 0.1),
	VWDustPouf = mix(def(LAND, 0.45, 1.6, 0.08, "POUF / PLOP of a dust bunny landing (to source)."), 4, 0.1),
	VWCleanupSweep = mix(def(WATER, 0.6, 0.55, 0, "Big mop sweep after the siren (to source)."), 3, 0.5),
	VWDefeat = mix(def(WIND, 0.55, 0.45, 0, "Comic descending trombone 'wah-wah-waah' (to source)."), 3, 2),

	-- V2 phase 7A: FORGEHEART identity (heavy, explosive, volcanic) -----------
	FHLavaAmbience = mix(candidate(def("", 0.3, 1, 0, "Volcanic crackle bed in the forge arena (loop).", true), "rbxassetid://91914091044238", 120), 5),
	-- The creator flagged this id as possibly a MUSIC track: refused automatically
	-- if it is longer than 30 s (a long track would fight with the boss theme).
	FHLavaAmbience2 = mix(candidate(def("", 0.22, 1, 0, "Secondary lava bubbling bed (loop), only if it is a short ambience.", true), "rbxassetid://1844669489", 30), 5),
	FHBigImpact = mix(candidate(def(BOOM, 0.75, 0.8, 0.02, "Huge cartoon explosion: the Final Eruption KABOOM."), "rbxassetid://2103404398", 4), 2, 0.5),
	FHAppear = mix(def(BOOM, 0.6, 0.45, 0, "Ground-shaking stomp + rumble when he wakes up (to source)."), 3, 1),
	FHHammerWindup = mix(def(WIND, 0.55, 0.6, 0, "Low 'WHOOM' while he raises his fists (to source)."), 4, 0.3),
	FHHammerHit = mix(def(LAND, 0.75, 0.42, 0.03, "Deep 'BONK' of the volcanic hammer (to source)."), 3, 0.2),
	FHWarnBlobs = mix(def(WATER, 0.5, 0.6, 0.03, "Lava gurgle before the blobs (to source)."), 4, 0.3),
	FHBlobLaunch = mix(def(JUMP, 0.5, 1.25, 0.06, "'FWIP' of a lava ball thrown (to source)."), 4, 0.15),
	FHBlobPop = mix(def(SLIDER, 0.5, 0.7, 0.08, "'POP' of a lava ball landing (to source)."), 3, 0.08),
	FHWarnFloor = mix(def(WIND, 0.5, 1.9, 0.02, "Rising crackle: the floor is about to burn (to source)."), 4, 0.3),
	FHLavaCrackle = mix(def(WATER, 0.45, 0.45, 0.05, "Crackling lava + bubbles while the floor burns (to source)."), 4, 0.4),
	FHWarnMeteors = mix(def(WIND, 0.55, 0.5, 0, "Sky rumble before the meteor shower (to source)."), 4, 0.5),
	FHMeteorWhistle = mix(def(WIND, 0.4, 2.4, 0.06, "Descending whistle of a falling meteor (to source)."), 4, 0.15),
	FHMeteorBoom = mix(def(BOOM, 0.5, 1.35, 0.06, "Small cartoon explosion of a meteor (to source)."), 3, 0.12),
	FHEruptionAlarm = mix(def(SLIDER, 0.65, 0.32, 0, "Deep alarm before the Final Eruption (to source)."), 2, 1),
	FHEruptionBuild = mix(def(WIND, 0.6, 0.4, 0, "Pressure building up, rising rumble (to source)."), 2, 1),
	FHDizzy = mix(def(SLIDER, 0.5, 0.6, 0, "Rock cracking + cartoon spring 'boyoyoing' (to source)."), 3, 1),
	FHDefeat = mix(def(BOOM, 0.6, 0.6, 0, "Explosion then comic balloon deflating (to source)."), 3, 2),
	AmbientWorld = def("", 0.25, 1, 0, "Looping ambient night bed under the music: wind, soft chimes, distant hum (1-3 min seamless loop).", true),
	-- MUSIC is not here: every music track and stinger is in Config/Music.
}

return Sounds
