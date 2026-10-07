--!strict
-- Ability framework (server authority).
--
--   UseAbility(abilityId, payload?)  client asks to use an equipped ability;
--                                    validated here, effect in Server/Abilities.
--   SetLoadout(slot, abilityId)      RemoteFunction; only inside your own
--                                    Sanctuary, only unlocked abilities of
--                                    that slot.
--   Dash / Pulse                     V1 remotes, kept as aliases of
--                                    UseAbility("dash" / "pulse").
--   Seal                             Sanctuary action, not part of the loadout.
--
-- Cooldowns are stored per ability id (session.cooldowns[id]), so swapping
-- the loadout can never reset a cooldown.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Abilities = require(Shared.Config.Abilities)

local Core = script.Parent.Parent.Core
local Types = require(Core.Types)
local Sessions = require(Core.Sessions)
local Remotes = require(Core.Remotes)
local PlotService = require(script.Parent.PlotService)
local StatusService = require(script.Parent.StatusService)

type Session = Types.Session

local AbilityService = {}

local modules: { [string]: Types.AbilityModule } = {}
for _, def in Abilities.list do
	local moduleScript = script.Parent.Parent.Abilities:FindFirstChild(def.module)
	assert(moduleScript and moduleScript:IsA("ModuleScript"), "missing server ability module " .. def.module)
	modules[def.id] = (require :: any)(moduleScript)
end

local function now(): number
	return workspace:GetServerTimeNow()
end

function AbilityService.isEquipped(session: Session, abilityId: string): boolean
	return table.find(session.data.abilities.loadout, abilityId) ~= nil
end

-- Returns (used, reason?). reason: "invalid" | "notEquipped" | "noCharacter" |
-- "stunned" | "rooted" | "cooldown" | "payload"
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
		return false, "notEquipped"
	end
	local _, _, root = Sessions.character(session)
	if not root then
		return false, "noCharacter"
	end
	local canAct, reason = StatusService.canAct(session, def)
	if not canAct then
		return false, reason
	end
	if not Sessions.cooldownReady(session, def.id) then
		return false, "cooldown"
	end
	local payload: any = nil
	local readPayload = module.readPayload
	if readPayload then
		payload = readPayload(rawPayload)
		if payload == nil then
			return false, "payload"
		end
	end
	Sessions.setCooldown(session, def.id, def.cooldown * (1 - def.lenience))
	Sessions.touch(session)
	module.activate({
		session = session,
		player = player,
		root = root,
		abilityId = def.id,
		now = now(),
		payload = payload,
	})
	return true, nil
end

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
	if not Abilities.canEquip(slotIndex, abilityId, abilities.unlocked) then
		local def = Abilities.get(abilityId)
		if def and def.slot == Abilities.Slots[slotIndex].id and not abilities.unlocked[abilityId] then
			return false, "locked"
		end
		return false, "invalid"
	end
	-- Loadouts are prepared at home, never swapped mid-chase.
	local _, _, root = Sessions.character(session)
	if not root or session.plot == nil or not PlotService.isInside(session.plot, root.Position) then
		return false, "notHome"
	end
	if abilities.loadout[slotIndex] ~= abilityId then
		abilities.loadout[slotIndex] = abilityId
		Sessions.markCold(session)
	end
	Sessions.touch(session)
	return true, nil
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

function AbilityService.start()
	Remotes.on(Net.Events.UseAbility, { rate = 4, burst = 6 }, function(player: Player, abilityId: any, payload: any)
		AbilityService.use(player, abilityId, payload)
	end)
	Remotes.onInvoke(Net.Functions.SetLoadout, { rate = 2, burst = 6 }, AbilityService.setLoadout)
	-- V1 aliases (same limits as V1).
	Remotes.on(Net.Events.Dash, { rate = 2, burst = 3 }, function(player: Player)
		AbilityService.use(player, "dash", nil)
	end)
	Remotes.on(Net.Events.Pulse, { rate = 1, burst = 2 }, function(player: Player)
		AbilityService.use(player, "pulse", nil)
	end)
	Remotes.on(Net.Events.Seal, { rate = 1, burst = 2 }, onSeal)
end

return AbilityService
