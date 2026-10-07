--!strict
-- Pulse: the shockwave plays immediately; the server resolves who is hit.
-- Magma Heart harmony (Eruption): the telegraph ring plays immediately, the
-- burst itself comes from the server when the wind-up ends.

local Context = require(script.Parent.Context)
local Controllers = script.Parent.Parent.Controllers
local CameraFX = require(Controllers.CameraFX)
local CharacterFX = require(Controllers.CharacterFX)
local AbilityFX = require(Controllers.AbilityFX)

local Pulse = {}

function Pulse.activate(ctx: Context.ClientContext): any
	local tuning = ctx.tuning
	if tuning.Eruption then
		AbilityFX.eruptionWindup(ctx.player.UserId, ctx.root.Position, tuning.Radius, tuning.Windup)
		CameraFX.shake(0.1)
		return nil
	end
	CharacterFX.pulse(ctx.root.Position, ctx.player.UserId)
	CameraFX.shake(0.18)
	return nil
end

function Pulse.denied(_reason: string)
	-- Nothing lasting to undo (the ring is a one-shot).
end

return (Pulse :: any) :: Context.ClientModule
