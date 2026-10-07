--!strict
-- Ability catalogue, loadout slots, unlock requirements and relic harmonies.
--
-- A player equips at most one ability per slot (3 slots + the Sanctuary Seal,
-- which is not part of the loadout). Each ability has:
--   * a server module   Server/Abilities/<Module>.luau  (validation + effect)
--   * a client module   Client/Abilities/<Module>.luau  (prediction + feel)
-- To add an ability: add a def here, the two modules, its tuning in
-- GameConfig.Abilities and its strings in Shared/Locale/Strings
-- ("ability.<id>", "ability.<id>.desc", en and fr).
--
-- Unlocks: abilities that are not `default` are bought with Essence once the
-- player's Power RECORD reaches `unlock.power` (a theft never re-locks them).
-- `unlock.materials` is reserved for boss / Forge materials (phase 6+): every
-- launch ability leaves it empty.
--
-- Harmonies: 6 relics change one ability while the relic stands on a pedestal
-- of its owner's Sanctuary (a relic out on a heist does not count). Players
-- can switch each harmony off from the Loadout screen.

local GameConfig = require(script.Parent.GameConfig)
local Relics = require(script.Parent.Relics)

export type SlotDef = {
	id: string,
	-- Ability equipped for new players / when a saved loadout is invalid.
	default: string,
	-- Optional slots may be left empty ("").
	optional: boolean,
	keyboard: Enum.KeyCode,
	gamepad: Enum.KeyCode,
}

export type UnlockDef = {
	-- Power record required.
	power: number,
	essence: number,
	-- Future boss / Forge materials: materialId -> amount (empty at launch).
	materials: { [string]: number },
}

export type AbilityDef = {
	id: string,
	slot: string,
	order: number,
	-- Module name under Server/Abilities and Client/Abilities.
	module: string,
	cooldown: number,
	-- Fraction of the cooldown the server forgives for network latency
	-- (the client still waits the full cooldown).
	lenience: number,
	-- Unlocked for everyone from the start.
	default: boolean,
	-- Rooted players cannot use it (movement abilities).
	needsMovement: boolean,
	-- What the client sends: "none" | "direction" (a unit vector, never a
	-- position) | "anchor" (an index into WorldFeatures.GrapplePoints).
	payload: string,
	icon: string,
	color: Color3,
	-- Design note: how the victim can answer it. Documentation only.
	counterplay: string,
	tuning: { [string]: any },
	unlock: UnlockDef?,
}

export type HarmonyDef = {
	-- Relic id (Config/Relics) that grants the harmony.
	relic: string,
	-- Target: one ability, every ability of a slot, or passive (no ability).
	ability: string?,
	slot: string?,
	passive: boolean,
	-- GameConfig.Harmonies entry.
	key: string,
	-- Values merged over the ability tuning (nil = none).
	tuning: { [string]: any }?,
	-- Cooldown multiplier for the targeted abilities (nil = 1).
	cooldownFactor: number?,
	icon: string,
	counterplay: string,
}

local Abilities = {}

Abilities.Slots = table.freeze({
	{ id = "Mobility", default = "dash", optional = false, keyboard = Enum.KeyCode.Q, gamepad = Enum.KeyCode.ButtonR1 },
	{ id = "Control", default = "pulse", optional = false, keyboard = Enum.KeyCode.F, gamepad = Enum.KeyCode.ButtonL1 },
	{ id = "Utility", default = "", optional = true, keyboard = Enum.KeyCode.R, gamepad = Enum.KeyCode.ButtonR2 },
} :: { SlotDef })

-- The Seal stays outside the loadout.
Abilities.SealKeys = table.freeze({ keyboard = Enum.KeyCode.G, gamepad = Enum.KeyCode.ButtonY })

local A = GameConfig.Abilities
local H = GameConfig.Harmonies

local function unlock(power: number, essence: number): UnlockDef
	return { power = power, essence = essence, materials = {} }
end

local list: { AbilityDef } = {
	-- Mobility -----------------------------------------------------------------
	{
		id = "dash",
		slot = "Mobility",
		order = 1,
		module = "Dash",
		cooldown = A.Dash.Cooldown,
		lenience = 0.1,
		default = true,
		needsMovement = true,
		payload = "none",
		icon = "dash",
		color = Color3.fromRGB(190, 160, 255),
		counterplay = "Short and straight: predictable direction, long enough cooldown to punish a missed dash.",
		tuning = A.Dash,
	},
	{
		id = "blink",
		slot = "Mobility",
		order = 2,
		module = "Blink",
		cooldown = A.Blink.Cooldown,
		lenience = 0.1,
		default = false,
		needsMovement = true,
		payload = "direction",
		icon = "blink",
		color = Color3.fromRGB(170, 120, 255),
		counterplay = "Visible 0.3s wind-up (a stun cancels it), never through walls, half range while carrying.",
		tuning = A.Blink,
		unlock = unlock(110, 2500),
	},
	{
		id = "grapple",
		slot = "Mobility",
		order = 3,
		module = "Grapple",
		cooldown = A.Grapple.Cooldown,
		lenience = 0.1,
		default = false,
		needsMovement = true,
		payload = "anchor",
		icon = "grapple",
		color = Color3.fromRGB(110, 235, 255),
		counterplay = "Only towards the 14 visible anchors, visible cable, any hard control cuts it.",
		tuning = A.Grapple,
		unlock = unlock(320, 20000),
	},
	-- Control ------------------------------------------------------------------
	{
		id = "pulse",
		slot = "Control",
		order = 4,
		module = "Pulse",
		cooldown = A.Pulse.Cooldown,
		lenience = 0,
		default = true,
		needsMovement = false,
		payload = "none",
		icon = "pulse",
		color = Color3.fromRGB(150, 230, 255),
		counterplay = "Short radius, visible wind-up ring; targets become steady (immune) after a hit.",
		tuning = A.Pulse,
	},
	{
		id = "frost_wave",
		slot = "Control",
		order = 5,
		module = "FrostWave",
		cooldown = A.FrostWave.Cooldown,
		lenience = 0,
		default = false,
		needsMovement = false,
		payload = "none",
		icon = "frost",
		color = Color3.fromRGB(140, 210, 255),
		counterplay = "A slow only (no knockback, no drop), blocked by walls, slows never stack.",
		tuning = A.FrostWave,
		unlock = unlock(70, 1000),
	},
	{
		id = "rune_trap",
		slot = "Control",
		order = 6,
		module = "RuneTrap",
		cooldown = A.RuneTrap.Cooldown,
		lenience = 0,
		default = false,
		needsMovement = false,
		payload = "none",
		icon = "trap",
		color = Color3.fromRGB(205, 130, 255),
		counterplay = "Glowing rune visible to everyone, 1s arming, one per player, walk around it.",
		tuning = A.RuneTrap,
		unlock = unlock(170, 6000),
	},
	-- Utility ------------------------------------------------------------------
	{
		id = "shield",
		slot = "Utility",
		order = 7,
		module = "Shield",
		cooldown = A.Shield.Cooldown,
		lenience = 0,
		default = false,
		needsMovement = false,
		payload = "none",
		icon = "shield",
		color = Color3.fromRGB(255, 215, 120),
		counterplay = "2s only, visible bubble, slows still apply and the bearer moves 20% slower: wait it out.",
		tuning = A.Shield,
		unlock = unlock(40, 400),
	},
	{
		id = "decoy",
		slot = "Utility",
		order = 8,
		module = "Decoy",
		cooldown = A.Decoy.Cooldown,
		lenience = 0,
		default = false,
		needsMovement = false,
		payload = "direction",
		icon = "decoy",
		color = Color3.fromRGB(255, 160, 210),
		counterplay = "Runs in a straight line, pops on the first control hit, revealed by the Cosmic Eye.",
		tuning = A.Decoy,
		unlock = unlock(240, 12000),
	},
	{
		id = "phase",
		slot = "Utility",
		order = 9,
		module = "Phase",
		cooldown = A.Phase.Cooldown,
		lenience = 0,
		default = false,
		needsMovement = false,
		payload = "none",
		icon = "phase",
		color = Color3.fromRGB(120, 255, 220),
		counterplay = "1.5s, ghostly and obvious, carried relic stays visible, still hit by control.",
		tuning = A.Phase,
		unlock = unlock(420, 35000),
	},
}

local harmonies: { HarmonyDef } = {
	{
		relic = "storm_crystal",
		ability = "dash",
		passive = false,
		key = "StormTrail",
		tuning = { StormTrail = H.StormTrail },
		icon = "dash",
		counterplay = "The trail is visible and short; a mild slow that never stacks.",
	},
	{
		relic = "void_cube",
		ability = "blink",
		passive = false,
		key = "VoidBlink",
		tuning = { Range = H.VoidBlink.Range, CarryFactor = H.VoidBlink.CarryFactor },
		icon = "blink",
		counterplay = "Same wind-up and wall rules; still shortened while carrying.",
	},
	{
		relic = "magma_heart",
		ability = "pulse",
		passive = false,
		key = "Eruption",
		tuning = {
			Eruption = true,
			Cooldown = H.Eruption.Cooldown,
			Radius = H.Eruption.Radius,
			Knockback = H.Eruption.Knockback,
			Lift = H.Eruption.Lift,
			Stun = H.Eruption.Stun,
			Windup = H.Eruption.Windup,
		},
		icon = "pulse",
		counterplay = "Telegraphed magma ring: step out during the wind-up. Longer cooldown.",
	},
	{
		relic = "frost_lotus",
		ability = "frost_wave",
		passive = false,
		key = "FrostLotus",
		tuning = { Radius = H.FrostLotus.Radius, Slow = H.FrostLotus.Slow, SlowDuration = H.FrostLotus.SlowDuration },
		icon = "frost",
		counterplay = "Still a slow only, capped like every slow.",
	},
	{
		relic = "chrono_glass",
		slot = "Utility",
		passive = false,
		key = "ChronoGlass",
		cooldownFactor = H.ChronoGlass.CooldownFactor,
		icon = "phase",
		counterplay = "-15% only on the Utility slot.",
	},
	{
		relic = "cosmic_eye",
		passive = true,
		key = "CosmicEye",
		icon = "eye",
		counterplay = "Counterplay itself: reveals decoys and phasing players, control ends their phase.",
	},
}

local byId: { [string]: AbilityDef } = {}
local slotIndex: { [string]: number } = {}
local harmonyByRelic: { [string]: HarmonyDef } = {}
for index, slot in Abilities.Slots do
	slotIndex[slot.id] = index
end
for _, def in list do
	assert(byId[def.id] == nil, "duplicate ability " .. def.id)
	assert(slotIndex[def.slot] ~= nil, "ability " .. def.id .. " has unknown slot " .. def.slot)
	assert(def.default or def.unlock ~= nil, "ability " .. def.id .. " needs an unlock requirement")
	assert(def.payload == "none" or def.payload == "direction" or def.payload == "anchor", "ability " .. def.id .. " has an unknown payload kind")
	byId[def.id] = def
end
for _, slot in Abilities.Slots do
	if slot.default ~= "" then
		local def = byId[slot.default]
		assert(def and def.slot == slot.id and def.default, "slot " .. slot.id .. " default must be an unlocked ability of that slot")
	end
end
for _, harmony in harmonies do
	assert(Relics.get(harmony.relic) ~= nil, "harmony on unknown relic " .. harmony.relic)
	assert(harmonyByRelic[harmony.relic] == nil, "duplicate harmony " .. harmony.relic)
	assert(harmony.ability == nil or byId[harmony.ability] ~= nil, "harmony targets unknown ability")
	assert(harmony.slot == nil or slotIndex[harmony.slot] ~= nil, "harmony targets unknown slot")
	assert(H[harmony.key] ~= nil, "harmony " .. harmony.relic .. " has no GameConfig.Harmonies entry")
	harmonyByRelic[harmony.relic] = harmony
end

-- Sanity of the tuning against the crowd-control and movement rules.
do
	local S = GameConfig.Status
	for _, slow: any in { A.FrostWave :: any, A.RuneTrap, H.FrostLotus, H.StormTrail } do
		assert(slow.Slow <= S.MaxSlow and slow.SlowDuration <= S.MaxSlowDuration, "slow above the Status caps")
	end
	assert(A.Shield.SelfSlow <= S.MaxSlow and A.Shield.Duration <= S.MaxBuffDuration, "shield above the Status caps")
	assert(A.Phase.Duration <= S.MaxBuffDuration, "phase above the Status caps")
	assert(A.Pulse.Stun <= S.MaxHardDuration and H.Eruption.Stun <= S.MaxHardDuration, "stun above the hard-control cap")
	assert(A.Grapple.Speed < GameConfig.Security.MaxHorizontalSpeed, "grapple faster than the movement guard allows")
	assert(A.Dash.Speed < GameConfig.Security.MaxHorizontalSpeed, "dash faster than the movement guard allows")
end

Abilities.list = list
Abilities.Harmonies = harmonies

function Abilities.get(id: any): AbilityDef?
	if type(id) ~= "string" then
		return nil
	end
	return byId[id]
end

function Abilities.slotIndex(slotId: string): number?
	return slotIndex[slotId]
end

-- Default loadout, one entry per slot ("" = empty).
function Abilities.defaultLoadout(): { string }
	local loadout = {}
	for index, slot in Abilities.Slots do
		loadout[index] = slot.default
	end
	return loadout
end

function Abilities.defaultUnlocked(): { [string]: boolean }
	local unlocked = {}
	for _, def in list do
		if def.default then
			unlocked[def.id] = true
		end
	end
	return unlocked
end

-- Is `abilityId` a legal choice for slot `index` given the unlocked set?
function Abilities.canEquip(index: number, abilityId: string, unlocked: { [string]: boolean }): boolean
	local slot = Abilities.Slots[index]
	if not slot then
		return false
	end
	if abilityId == "" then
		return slot.optional
	end
	local def = byId[abilityId]
	return def ~= nil and def.slot == slot.id and unlocked[abilityId] == true
end

-- Harmonies -------------------------------------------------------------------

function Abilities.harmony(relicId: any): HarmonyDef?
	if type(relicId) ~= "string" then
		return nil
	end
	return harmonyByRelic[relicId]
end

-- Active harmonies from the relic ids displayed in the Sanctuary, minus the
-- ones switched off. Returns relicId -> true.
function Abilities.activeHarmonies(displayed: { string }, off: { [string]: boolean }?): { [string]: boolean }
	local active = {}
	for _, relicId in displayed do
		if harmonyByRelic[relicId] and not (off and off[relicId]) then
			active[relicId] = true
		end
	end
	return active
end

local function targets(harmony: HarmonyDef, def: AbilityDef): boolean
	return harmony.ability == def.id or harmony.slot == def.slot
end

-- Harmonies (relic ids) currently changing `def`.
function Abilities.harmoniesFor(def: AbilityDef, active: { [string]: boolean }): { string }
	local found = {}
	for _, harmony in harmonies do
		if active[harmony.relic] and targets(harmony, def) then
			table.insert(found, harmony.relic)
		end
	end
	return found
end

-- Effective tuning of `def` with the active harmonies merged in.
function Abilities.tuning(def: AbilityDef, active: { [string]: boolean }?): { [string]: any }
	local merged = table.clone(def.tuning)
	if active then
		for _, harmony in harmonies do
			if active[harmony.relic] and harmony.tuning and targets(harmony, def) then
				for key, value in harmony.tuning do
					merged[key] = value
				end
			end
		end
	end
	return merged
end

-- Effective cooldown of `def` (harmony tuning + cooldown factors).
function Abilities.cooldown(def: AbilityDef, active: { [string]: boolean }?): number
	local tuning = Abilities.tuning(def, active)
	local cooldown = if type(tuning.Cooldown) == "number" then tuning.Cooldown else def.cooldown
	if active then
		for _, harmony in harmonies do
			if active[harmony.relic] and harmony.cooldownFactor and targets(harmony, def) then
				cooldown *= harmony.cooldownFactor
			end
		end
	end
	return cooldown
end

return Abilities
