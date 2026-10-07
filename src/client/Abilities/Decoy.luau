--!strict
-- Decoy: sends the intended direction; the server computes the decoy's path
-- and every client draws the copy (AbilityFX).

local Context = require(script.Parent.Context)

local Decoy = {}

function Decoy.activate(ctx: Context.ClientContext): any
	return Context.intentDirection(ctx.root, ctx.humanoid)
end

return (Decoy :: any) :: Context.ClientModule
