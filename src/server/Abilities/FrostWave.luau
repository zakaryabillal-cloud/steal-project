--!strict
-- Frost Wave (Control): a cold ring around the caster that SLOWS every other
-- player in range and in sight (walls block it). No knockback, no relic drop:
-- it helps a chaser catch up, the drop still needs a Pulse. Slows go through
-- StatusService: they never stack (strongest wins) and are capped.
--
-- Frost Lotus harmony: bigger radius, stronger and longer slow (still capped).
-- Cosmic Eye harmony: players hit lose their Spectral Phase.

local Core = script.Parent.Parent.Core
local Types = require(Core.Types)
local Remotes = require(Core.Remotes)
local Services = script.Parent.Parent.Services
local StatusService = require(Services.StatusService)
local Common = require(script.Parent.Common)
local Decoy = require(script.Parent.Decoy) :: any

local FrostWave = {}

function FrostWave.activate(ctx: Types.AbilityContext)
	local session = ctx.session
	local tuning = ctx.tuning
	local origin = ctx.root.Position
	local cosmicEye = ctx.harmonies.cosmic_eye == true
	Remotes.fx("FrostWave", { userId = session.userId, position = origin, radius = tuning.Radius, lotus = ctx.harmonies.frost_lotus == true })
	Decoy.popNear(origin, tuning.Radius, session)
	for _, target in Common.targets(session, origin, tuning.Radius, true) do
		Common.onControlHit(cosmicEye, target.session)
		if StatusService.applySlow(target.session, "frost", tuning.Slow, tuning.SlowDuration) then
			Remotes.fx("Slowed", { userId = target.session.userId, by = session.userId, kind = "frost" })
		end
	end
end

return (FrostWave :: any) :: Types.AbilityModule
