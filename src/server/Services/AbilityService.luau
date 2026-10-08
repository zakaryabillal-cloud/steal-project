--!strict
-- Ability framework (server authority).
--
--   UseAbility(abilityId, payload?)  client asks to use an equipped ability;
--                                    validated here, effect in Server/Abilities.
--   SetLoadout(slot, abilityId)      RemoteFunction; only inside your own
--                                    Sanctuary, only unlocked abilities of
--                                    that slot.
--   UnlockAbility(abilityId)         RemoteFunction; Power record + Essence
--                                    (+ future materials), checked here.
--   SetHarmony(relicId, enabled)     RemoteFunction; switch a relic harmony
--                                    on/off, only inside your own Sanctuary.
--   Dash / Pulse                     V1 remotes, kept as aliases of
--                                    UseAbility("dash" / "pulse").
--   Seal                             Sanctuary action, not part of the loadout.
--
-- What the server decides alone: which ability is equipped, cooldowns (per
-- ability id, so swapping the loadout never resets one), ranges, destinations,
-- raycasts, targets, statuses, trap placement, grapple anchors, harmonies
-- (from the relics actually displayed in the caster's Sanctuary) and loadout
-- changes. A client payload is at most a direction or an anchor index.
--
-- Runtime state (pending blink, grapple flight, trap, decoy...) lives in
-- session.abilityState and is cleaned on death, respawn, leave and unequip,
-- plus a periodic sweep for anything orphaned.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Abilities = require(Shared.Config.Abilities)
local Bosses = require(Shared.Config.Bosses)
local Materials = require(Shared.Config.Materials)

local Core = script.Parent.Parent.Core
local Types = require(Core.Types)
local Sessions = require(Core.Sessions)
local Expeditions = require(Core.Expeditions)
local Remotes = require(Core.Remotes)
local Scheduler = require(Core.Scheduler)
local PlotService = require(script.Parent.PlotService)
local StatusService = require(script.Parent.StatusService)
local EconomyService = require(script.Parent.EconomyService)
local CharacterService = require(script.Parent.CharacterService)

type Session = Types.Session

local AbilityService = {}

local AbilityModules = script.Parent.Parent.Abilities
local modules: { [string]: Types.AbilityModule } = {}
local moduleList: { Types.AbilityModule } = {}
for _, def in Abilities.list do
	local moduleScript = AbilityModules:FindFirstChild(def.module)
	assert(moduleScript and moduleScript:IsA("ModuleScript"), "missing server ability module " .. def.module)
	local module = (require :: any)(moduleScript)
	modules[def.id] = module
	table.insert(moduleList, module)
end

-- Reasons worth telling the client about (its prediction must be undone).
local DENIED_FEEDBACK: { [string]: boolean } = {
	stunned = true,
	rooted = true,
	cooldown = true,
	payload = true,
	blocked = true,
	noAnchor = true,
	range = true,
	los = true,
	noGround = true,
	forbidden = true,
	notEquipped = true,
	arena = true,
}

local function now(): number
	return workspace:GetServerTimeNow()
end

function AbilityService.module(abilityId: string): Types.AbilityModule?
	return modules[abilityId]
end

function AbilityService.isEquipped(session: Session, abilityId: string): boolean
	return table.find(session.data.abilities.loadout, abilityId) ~= nil
end

-- Unlocked set used for equipping (the Studio test unlock is never saved).
function AbilityService.unlockedSet(session: Session): { [string]: boolean }
	if not session.devAbilities then
		return session.data.abilities.unlocked
	end
	local all = table.clone(session.data.abilities.unlocked)
	for _, def in Abilities.list do
		all[def.id] = true
	end
	return all
end

function AbilityService.isUnlocked(session: Session, abilityId: string): boolean
	return AbilityService.unlockedSet(session)[abilityId] == true
end

-- Harmonies active for `session` right now (relic id -> true): relics on
-- its own pedestals (never one out on a heist), minus the switched-off ones.
function AbilityService.activeHarmonies(session: Session): { [string]: boolean }
	return Abilities.activeHarmonies(session.harmonyRelics, session.data.abilities.harmonyOff)
end

function AbilityService.hasHarmony(session: Session, relicId: string): boolean
	return AbilityService.activeHarmonies(session)[relicId] == true
end

local function deny(session: Session, abilityId: string, reason: string): (boolean, string?)
	if DENIED_FEEDBACK[reason] and Sessions.allowNotice(session, "deny:" .. abilityId .. reason, 0.25) then
		Remotes.fxTo(session.player, "AbilityDenied", { ability = abilityId, reason = reason })
	end
	return false, reason
end

-- Returns (used, reason?). reason: "invalid" | "notEquipped" | "noCharacter" |
-- "stunned" | "rooted" | "cooldown" | "payload" | a module reason ("blocked",
-- "noAnchor", "range", "los", "noGround", "forbidden").
function AbilityService.use(player: Player, abilityId: any, rawPayload: any): (boolean, string?)
	local session = Sessions.ready(player)
	if not session then
		return false, "invalid"
	end
	local def = Abilities.get(abilityId)
	if not def then
		return false, "invalid"
	end
	local module = modules[def.id]
	if not module or not AbilityService.isEquipped(session, def.id) then
		return deny(session, def.id, "notEquipped")
	end
	local _, _, root = Sessions.character(session)
	if not root then
		return false, "noCharacter"
	end
	-- Boss arena: movement / defence only (no PvP tool between fighters).
	if Expeditions.isAway(session) and not Bosses.Combat.ArenaAbilities[def.id] then
		return deny(session, def.id, "arena")
	end
	local canAct, reason = StatusService.canAct(session, def)
	if not canAct then
		return deny(session, def.id, reason or "stunned")
	end
	if not Sessions.cooldownReady(session, def.id) then
		return deny(session, def.id, "cooldown")
	end
	local payload: any = nil
	local readPayload = module.readPayload
	if readPayload then
		payload = readPayload(rawPayload)
		if payload == nil then
			return deny(session, def.id, "payload")
		end
	end
	local harmonies = AbilityService.activeHarmonies(session)
	local ctx: Types.AbilityContext = {
		session = session,
		player = player,
		root = root,
		abilityId = def.id,
		now = now(),
		payload = payload,
		tuning = Abilities.tuning(def, harmonies),
		cooldown = Abilities.cooldown(def, harmonies),
		harmonies = harmonies,
	}
	local validate = module.validate
	if validate then
		local ok, why = validate(ctx)
		if not ok then
			return deny(session, def.id, why or "blocked")
		end
	end
	Sessions.setCooldown(session, def.id, ctx.cooldown * (1 - def.lenience))
	Sessions.touch(session)
	module.activate(ctx)
	return true, nil
end

-- Drops every runtime effect owned by `session` (all abilities, or one).
function AbilityService.cleanup(session: Session, reason: string, abilityId: string?)
	for id, module in modules do
		if abilityId == nil or abilityId == id then
			local cleanup = module.cleanup
			if cleanup then
				local ok, err = pcall(cleanup :: any, session, reason)
				if not ok then
					warn(string.format("[AbilityService] cleanup %s failed for %s: %s", id, session.player.Name, tostring(err)))
				end
			end
		end
	end
end

-- Player leaving: nothing they created may outlive them.
function AbilityService.release(session: Session)
	AbilityService.cleanup(session, "leave")
	table.clear(session.abilityState)
end

-- Inside the session's own Sanctuary (owned plot, character inside).
local function atHome(session: Session): boolean
	local _, _, root = Sessions.character(session)
	local plot = PlotService.of(session)
	return root ~= nil and plot ~= nil and plot.owner == session and PlotService.isInside(plot.index, root.Position)
end
AbilityService.atHome = atHome

-- Returns (ok, reason?). reason: "invalid" | "notHome" | "locked"
function AbilityService.setLoadout(player: Player, slotIndex: any, abilityId: any): (boolean, string?)
	local session = Sessions.ready(player)
	if not session then
		return false, "invalid"
	end
	if type(slotIndex) ~= "number" or slotIndex ~= math.floor(slotIndex) or Abilities.Slots[slotIndex] == nil then
		return false, "invalid"
	end
	if type(abilityId) ~= "string" or #abilityId > 32 then
		return false, "invalid"
	end
	local abilities = session.data.abilities
	if not Abilities.canEquip(slotIndex, abilityId, AbilityService.unlockedSet(session)) then
		local def = Abilities.get(abilityId)
		if def and def.slot == Abilities.Slots[slotIndex].id and not AbilityService.isUnlocked(session, abilityId) then
			return false, "locked"
		end
		return false, "invalid"
	end
	-- Loadouts are prepared at home, never swapped mid-chase.
	if not atHome(session) then
		return false, "notHome"
	end
	local previous = abilities.loadout[slotIndex]
	if previous ~= abilityId then
		abilities.loadout[slotIndex] = abilityId
		Sessions.markCold(session)
		if previous ~= "" and not AbilityService.isEquipped(session, previous) then
			-- Unequipped: its trap / decoy / pending effect disappears.
			AbilityService.cleanup(session, "unequip", previous)
		end
	end
	Sessions.touch(session)
	return true, nil
end

-- Returns (ok, reason?). reason: "invalid" | "owned" | "power" | "materials" | "notEnough"
function AbilityService.unlock(player: Player, abilityId: any): (boolean, string?)
	local session = Sessions.ready(player)
	if not session then
		return false, "invalid"
	end
	local def = Abilities.get(abilityId)
	if not def then
		return false, "invalid"
	end
	local unlocked = session.data.abilities.unlocked
	if def.default or unlocked[def.id] then
		return false, "owned"
	end
	local requirement = def.unlock
	if not requirement then
		return false, "invalid"
	end
	if session.data.power.peak < requirement.power then
		return false, "power"
	end
	-- Boss materials (phase 6): checked here, spent together with the Essence.
	-- Unknown material ids can never be met.
	local materials = session.data.materials
	for materialId, amount in requirement.materials do
		if amount > 0 and (Materials.get(materialId) == nil or (materials[materialId] or 0) < amount) then
			return false, "materials"
		end
	end
	if not EconomyService.spend(session, requirement.essence) then
		return false, "notEnough"
	end
	for materialId, amount in requirement.materials do
		if amount > 0 then
			materials[materialId] = (materials[materialId] or 0) - amount
		end
	end
	unlocked[def.id] = true
	Sessions.markCold(session)
	Sessions.touch(session)
	Remotes.notify(player, "n.abilityUnlocked", { ability = def.id }, "rare")
	return true, nil
end

-- Returns (ok, reason?). reason: "invalid" | "notHome"
function AbilityService.setHarmony(player: Player, relicId: any, enabled: any): (boolean, string?)
	local session = Sessions.ready(player)
	if not session then
		return false, "invalid"
	end
	if type(relicId) ~= "string" or #relicId > 32 or not Abilities.harmony(relicId) or type(enabled) ~= "boolean" then
		return false, "invalid"
	end
	if not atHome(session) then
		return false, "notHome"
	end
	local off = session.data.abilities.harmonyOff
	local wasOff = off[relicId] == true
	if enabled and wasOff then
		off[relicId] = nil
		Sessions.markCold(session)
	elseif not enabled and not wasOff then
		off[relicId] = true
		Sessions.markCold(session)
	end
	Sessions.touch(session)
	return true, nil
end

-- Studio test unlock (DevCommands): every ability equippable for this session
-- only. Never saved: the saved loadout is re-validated against the real
-- unlocks on the next join.
function AbilityService.setDevUnlock(session: Session, enabled: boolean)
	session.devAbilities = enabled
	if not enabled then
		local unlocked = session.data.abilities.unlocked
		for index, slot in Abilities.Slots do
			local equipped = session.data.abilities.loadout[index]
			if equipped ~= "" and not unlocked[equipped] then
				session.data.abilities.loadout[index] = slot.default
				AbilityService.cleanup(session, "unequip", equipped)
			end
		end
	end
	Sessions.markCold(session)
end

local function onSeal(player: Player)
	local session = Sessions.ready(player)
	if not session then
		return
	end
	Sessions.touch(session)
	local ok, reason = PlotService.seal(session)
	if ok then
		Remotes.notify(player, "n.sealed", nil, "success")
	elseif reason == "cooldown" then
		Remotes.notify(player, "n.sealCooldown", { time = (session.cooldowns.seal or 0) - now() }, "warning")
	end
end

-- Power record crossed an unlock threshold: tell the player once.
local function onPeakRaised(session: Session, previous: number, peak: number)
	for _, def in Abilities.list do
		local requirement = def.unlock
		if requirement and not session.data.abilities.unlocked[def.id] and requirement.power > previous and requirement.power <= peak then
			Remotes.notify(session.player, "n.abilityEligible", { ability = def.id }, "rare")
		end
	end
end

local sweepTimer = 0

function AbilityService.start()
	-- Server-side ability objects (rune traps) live here; create it up front
	-- so clients can watch it from the start.
	local Common = require(AbilityModules.Common) :: any
	Common.folder()
	Remotes.on(Net.Events.UseAbility, { rate = 4, burst = 6 }, function(player: Player, abilityId: any, payload: any)
		AbilityService.use(player, abilityId, payload)
	end)
	Remotes.onInvoke(Net.Functions.SetLoadout, { rate = 2, burst = 6 }, AbilityService.setLoadout)
	Remotes.onInvoke(Net.Functions.UnlockAbility, { rate = 1, burst = 3 }, AbilityService.unlock)
	Remotes.onInvoke(Net.Functions.SetHarmony, { rate = 2, burst = 6 }, AbilityService.setHarmony)
	-- V1 aliases (same limits as V1).
	Remotes.on(Net.Events.Dash, { rate = 2, burst = 3 }, function(player: Player)
		AbilityService.use(player, "dash", nil)
	end)
	Remotes.on(Net.Events.Pulse, { rate = 1, burst = 2 }, function(player: Player)
		AbilityService.use(player, "pulse", nil)
	end)
	Remotes.on(Net.Events.Seal, { rate = 1, burst = 2 }, onSeal)

	CharacterService.died:Connect(function(session: Session)
		AbilityService.cleanup(session, "death")
	end)
	CharacterService.spawned:Connect(function(session: Session)
		AbilityService.cleanup(session, "respawn")
	end)
	EconomyService.peakRaised:Connect(onPeakRaised)

	-- One job for every ability: pending wind-ups, flights, traps, decoys,
	-- trails, reveals; plus a sweep of anything orphaned once per second.
	Scheduler.every("Abilities.tick", 0.1, function(elapsed: number)
		local t = now()
		for _, module in moduleList do
			local tick = module.tick
			if tick then
				tick(t)
			end
		end
		sweepTimer += elapsed
		if sweepTimer >= 1 then
			sweepTimer = 0
			for _, session in Sessions.all() do
				for id, module in modules do
					local cleanup = module.cleanup
					if cleanup and not AbilityService.isEquipped(session, id) then
						cleanup(session, "sweep")
					end
				end
			end
		end
	end)
end

return AbilityService
