--!strict
-- Spectral Phase: the ghost look comes from the server's PhaseUntil
-- attribute (AbilityFX); the collision change is made by the server.

local Context = require(script.Parent.Context)
local Controllers = script.Parent.Parent.Controllers
local CameraFX = require(Controllers.CameraFX)

local Phase = {}

function Phase.activate(_ctx: Context.ClientContext): any
	CameraFX.punch(4)
	return nil
end

return (Phase :: any) :: Context.ClientModule
