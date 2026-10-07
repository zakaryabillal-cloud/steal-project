--!strict
-- Audio registry. Every gameplay sound goes through a key in this table.
--
--   id       : your uploaded/licensed asset ("rbxassetid://123..."). Leave "" until you have one.
--   fallback : a sound that ships inside every Roblox client (rbxasset://sounds/...),
--              used while `id` is empty so the game is never silent. "" = silent.
--   note     : what the final sound should be. See README "Audio" for the full list.
--
-- Do not invent asset ids: only paste ids you uploaded or that are licensed to you.

export type SoundDef = {
	id: string,
	fallback: string,
	volume: number,
	pitch: number,
	-- Random +/- pitch spread applied per play.
	variance: number,
	looped: boolean,
	note: string,
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

	-- World ------------------------------------------------------------------
	EventStart = def(BOOM, 0.4, 0.45, 0, "Deep horn / sky rumble announcing a Rift event."),
	AmbientWorld = def("", 0.25, 1, 0, "Looping ambient night bed: wind, soft chimes, distant hum.", true),
	Music = def("", 0.18, 1, 0, "Looping calm cosmic-fantasy background track.", true),
}

return Sounds
