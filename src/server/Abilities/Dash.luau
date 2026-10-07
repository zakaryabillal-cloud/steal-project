--!strict
-- Dash (Mobility): a short burst. Movement is applied by the client for
-- instant response; the server owns the cooldown (AbilityService), gives the
-- movement guard a short grace window, and broadcasts the trail.

local Core = script.Parent.Parent.Core
local Types = require(Core.Types)
local Remotes = require(Core.Remotes)

local Dash = {}

function Dash.activate(ctx: Types.AbilityContext)
	local session = ctx.session
	session.teleportGraceUntil = math.max(session.teleportGraceUntil, ctx.now + 0.6)
	Remotes.fx("Dash", { userId = session.userId })
end

return (Dash :: any) :: Types.AbilityModule
