--!strict
-- Ability catalogue and loadout slots.
--
-- A player equips at most one ability per slot (3 slots + the Sanctuary Seal,
-- which is not part of the loadout). Each ability has:
--   * a server module   Server/Abilities/<Module>.luau  (validation + effect)
--   * a client module   Client/Abilities/<Module>.luau  (prediction + feel)
-- To add an ability: add a def here, the two modules, and its name/description
-- display name in Shared/Locale/Strings ("ability.<id>", en and fr).
--
-- Numeric tuning for the launch abilities stays in GameConfig.Abilities so the
-- V1 values have a single source of truth.

local GameConfig = require(script.Parent.GameConfig)

export type SlotDef = {
	id: string,
	-- Ability equipped for new players / when a saved loadout is invalid.
	default: string,
	-- Optional slots may be left empty ("").
	optional: boolean,
	keyboard: Enum.KeyCode,
	gamepad: Enum.KeyCode,
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
	icon: string,
	color: Color3,
	-- Design note: how the victim can answer it. Documentation only.
	counterplay: string,
	tuning: { [string]: any },
}

local Abilities = {}

Abilities.Slots = table.freeze({
	{ id = "Mobility", default = "dash", optional = false, keyboard = Enum.KeyCode.Q, gamepad = Enum.KeyCode.ButtonR1 },
	{ id = "Control", default = "pulse", optional = false, keyboard = Enum.KeyCode.F, gamepad = Enum.KeyCode.ButtonL1 },
	{ id = "Utility", default = "", optional = true, keyboard = Enum.KeyCode.R, gamepad = Enum.KeyCode.ButtonR2 },
} :: { SlotDef })

local DASH = GameConfig.Abilities.Dash
local PULSE = GameConfig.Abilities.Pulse

local list: { AbilityDef } = {
	{
		id = "dash",
		slot = "Mobility",
		order = 1,
		module = "Dash",
		cooldown = DASH.Cooldown,
		lenience = 0.1,
		default = true,
		needsMovement = true,
		icon = "dash",
		color = Color3.fromRGB(190, 160, 255),
		counterplay = "Short and straight: predictable direction, long enough cooldown to punish a missed dash.",
		tuning = DASH,
	},
	{
		id = "pulse",
		slot = "Control",
		order = 2,
		module = "Pulse",
		cooldown = PULSE.Cooldown,
		lenience = 0,
		default = true,
		needsMovement = false,
		icon = "pulse",
		color = Color3.fromRGB(150, 230, 255),
		counterplay = "Short radius, visible wind-up ring; targets become steady (immune) after a hit.",
		tuning = PULSE,
	},
}

local byId: { [string]: AbilityDef } = {}
local slotIndex: { [string]: number } = {}
for index, slot in Abilities.Slots do
	slotIndex[slot.id] = index
end
for _, def in list do
	assert(byId[def.id] == nil, "duplicate ability " .. def.id)
	assert(slotIndex[def.slot] ~= nil, "ability " .. def.id .. " has unknown slot " .. def.slot)
	byId[def.id] = def
end
for _, slot in Abilities.Slots do
	if slot.default ~= "" then
		local def = byId[slot.default]
		assert(def and def.slot == slot.id and def.default, "slot " .. slot.id .. " default must be an unlocked ability of that slot")
	end
end

Abilities.list = list

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

return Abilities
