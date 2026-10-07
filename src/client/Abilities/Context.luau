--!strict
-- Shared types for client ability modules (Client/Abilities/<Module>.luau).
-- A client module only predicts and plays feedback; the server decides.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Abilities = require(ReplicatedStorage.Shared.Config.Abilities)

export type ClientContext = {
	player: Player,
	root: BasePart,
	humanoid: Humanoid,
	def: Abilities.AbilityDef,
	-- Effective tuning / cooldown with the player's active harmonies (display
	-- and prediction only: the server recomputes both).
	tuning: { [string]: any },
	harmonies: { [string]: boolean },
}

export type ClientModule = {
	-- Optional: can the ability be used right now? (false, reasonKey) skips the
	-- request entirely (e.g. no grapple anchor in sight).
	canUse: ((ctx: ClientContext) -> (boolean, string?))?,
	-- Local prediction + feedback. Returns the payload sent to the server
	-- (nil when the ability takes none). Never a position: at most a
	-- direction or an anchor index.
	activate: (ctx: ClientContext) -> any,
	-- Optional: the server refused the request (undo the prediction).
	denied: ((reason: string) -> ())?,
}

-- Horizontal direction the player means: movement input first, then the
-- camera, then the character's facing.
local function intentDirection(root: BasePart, humanoid: Humanoid): Vector3
	local move = humanoid.MoveDirection
	if move.Magnitude > 0.1 then
		return Vector3.new(move.X, 0, move.Z).Unit
	end
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	return if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
end

return {
	intentDirection = intentDirection,
}
