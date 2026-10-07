--!strict
-- Shield: the bubble is drawn from the server's ShieldUntil attribute (see
-- AbilityFX), so every player sees exactly what the server applied.

local Context = require(script.Parent.Context)
local Controllers = script.Parent.Parent.Controllers
local CameraFX = require(Controllers.CameraFX)

local Shield = {}

function Shield.activate(_ctx: Context.ClientContext): any
	CameraFX.punch(-3)
	return nil
end

return (Shield :: any) :: Context.ClientModule
