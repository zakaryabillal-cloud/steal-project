--!strict
-- Frost Wave: the icy ring plays immediately; the server decides who is
-- slowed (range + line of sight, StatusService rules).

local Context = require(script.Parent.Context)
local Controllers = script.Parent.Parent.Controllers
local AbilityFX = require(Controllers.AbilityFX)

local FrostWave = {}

function FrostWave.activate(ctx: Context.ClientContext): any
	AbilityFX.frostWave(ctx.player.UserId, ctx.root.Position, ctx.tuning.Radius)
	return nil
end

return (FrostWave :: any) :: Context.ClientModule
