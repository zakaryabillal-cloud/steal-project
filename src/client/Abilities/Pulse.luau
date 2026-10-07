--!strict
-- Pulse: the shockwave plays immediately; the server resolves who is hit.

local Context = require(script.Parent.Context)
local Controllers = script.Parent.Parent.Controllers
local CameraFX = require(Controllers.CameraFX)
local CharacterFX = require(Controllers.CharacterFX)

local Pulse = {}

function Pulse.activate(ctx: Context.ClientContext): any
	CharacterFX.pulse(ctx.root.Position, ctx.player.UserId)
	CameraFX.shake(0.18)
	return nil
end

return (Pulse :: any) :: Context.ClientModule
