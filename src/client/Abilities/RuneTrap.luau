--!strict
-- Rune Trap: no prediction (the rune is a server part everyone sees). The
-- server places it on the ground under the player.

local Context = require(script.Parent.Context)

local RuneTrap = {}

function RuneTrap.activate(_ctx: Context.ClientContext): any
	return nil
end

return (RuneTrap :: any) :: Context.ClientModule
