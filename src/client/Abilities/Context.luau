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
}

export type ClientModule = {
	-- Local prediction + feedback. Returns the payload sent to the server
	-- (nil when the ability takes none).
	activate: (ctx: ClientContext) -> any,
}

return {}
