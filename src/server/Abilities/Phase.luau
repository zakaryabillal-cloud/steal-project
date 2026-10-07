--!strict
-- Spectral Phase (Utility): for a short time the caster passes through other
-- players (collision group "Phase<i>", see WorldBuilder). Walls, the map and
-- other players' Sanctuary barriers still block. Nothing else changes: the
-- caster can still be hit by control, and a carried relic stays fully
-- visible (only the body turns ghostly on every client).
--
-- Counterplay: short, obvious, and the Cosmic Eye harmony reveals it and
-- ends it with any control ability.

local Core = script.Parent.Parent.Core
local Types = require(Core.Types)
local Remotes = require(Core.Remotes)
local Sessions = require(Core.Sessions)
local Services = script.Parent.Parent.Services
local StatusService = require(Services.StatusService)
local Common = require(script.Parent.Common)
local GameConfig = require(game:GetService("ReplicatedStorage").Shared.Config.GameConfig)

type Session = Types.Session

local EYE = GameConfig.Harmonies.CosmicEye

local Phase = {}

function Phase.activate(ctx: Types.AbilityContext)
	local session = ctx.session
	local tuning = ctx.tuning
	StatusService.applyBuff(session, "phase", tuning.Duration)
	session.abilityState.phaseRevealed = {}
	Remotes.fx("Phase", { userId = session.userId, untilTime = ctx.now + tuning.Duration })
end

-- Cosmic Eye: reveal phasing players within range (once per activation).
function Phase.tick(_now: number)
	local holders: { { session: Session, root: BasePart } } = {}
	local phasing: { { session: Session, root: BasePart } } = {}
	for _, session in Sessions.all() do
		local root = Common.root(session)
		if not root then
			continue
		end
		if StatusService.isPhased(session) then
			table.insert(phasing, { session = session, root = root })
		end
		if Common.hasHarmony(session, "cosmic_eye") then
			table.insert(holders, { session = session, root = root })
		end
	end
	if #phasing == 0 or #holders == 0 then
		return
	end
	for _, target in phasing do
		local revealed = target.session.abilityState.phaseRevealed
		if type(revealed) ~= "table" then
			revealed = {}
			target.session.abilityState.phaseRevealed = revealed
		end
		for _, holder in holders do
			if holder.session ~= target.session and not revealed[holder.session.userId] and (holder.root.Position - target.root.Position).Magnitude <= EYE.RevealRadius then
				revealed[holder.session.userId] = true
				Remotes.fxTo(holder.session.player, "Reveal", { userId = target.session.userId, untilTime = target.session.status.phaseUntil })
			end
		end
	end
end

function Phase.cleanup(session: Session, reason: string)
	if reason == "unequip" or reason == "leave" then
		StatusService.endBuff(session, "phase")
	end
	if reason ~= "sweep" then
		session.abilityState.phaseRevealed = nil
	end
end

return (Phase :: any) :: Types.AbilityModule
