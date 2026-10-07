--!strict
-- Blink: plays the wind-up immediately and sends the intended DIRECTION
-- (movement input, else facing). The server computes the destination, checks
-- walls, ground and sealed Sanctuaries, and moves the character itself.

local Context = require(script.Parent.Context)
local Controllers = script.Parent.Parent.Controllers
local AbilityFX = require(Controllers.AbilityFX)

local Blink = {}

function Blink.activate(ctx: Context.ClientContext): any
	AbilityFX.blinkWindup(ctx.player.UserId, ctx.tuning.Windup)
	return Context.intentDirection(ctx.root, ctx.humanoid)
end

return (Blink :: any) :: Context.ClientModule
