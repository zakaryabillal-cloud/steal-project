--!strict
-- Shield (Utility): a short bubble that blocks HARD control (stun, root,
-- knockback, hence the relic drop of Pulse / Eruption). It is not
-- invincibility: slows (Frost Wave, rune traps, storm trails) still apply,
-- falling into the void still kills, the movement guard still watches, and
-- the bearer is slowed while it lasts (mobility trade-off). Everything goes
-- through StatusService (no parallel system).

local Core = script.Parent.Parent.Core
local Types = require(Core.Types)
local Remotes = require(Core.Remotes)
local Services = script.Parent.Parent.Services
local StatusService = require(Services.StatusService)

local Shield = {}

function Shield.activate(ctx: Types.AbilityContext)
	local session = ctx.session
	local tuning = ctx.tuning
	StatusService.applyBuff(session, "shield", tuning.Duration)
	StatusService.applySelfSlow(session, "self:shield", tuning.SelfSlow, tuning.Duration)
	Remotes.fx("Shield", { userId = session.userId, untilTime = ctx.now + tuning.Duration })
end

function Shield.cleanup(session: Types.Session, reason: string)
	if reason == "unequip" or reason == "leave" then
		StatusService.endBuff(session, "shield")
		StatusService.clearSlow(session, "self:shield")
	end
end

return (Shield :: any) :: Types.AbilityModule
