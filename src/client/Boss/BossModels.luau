--!strict
-- Boss id -> body model module (V2 phases 7A-7B). Every model has the same
-- interface (BossRig.ModelModule): BossFX, the portal card and the Codex
-- build whichever boss the server announces. Add a boss = add one line.

local BossRig = require(script.Parent.BossRig)
local VoidWardenModel = require(script.Parent.VoidWardenModel)
local ForgeheartModel = require(script.Parent.ForgeheartModel)
local TempestSeraphModel = require(script.Parent.TempestSeraphModel)

local BossModels = {}

local models: { [string]: BossRig.ModelModule } = {
	VoidWarden = VoidWardenModel :: any,
	Forgeheart = ForgeheartModel :: any,
	TempestSeraph = TempestSeraphModel :: any,
}

-- Model of a boss (the Void Warden's for an unknown id).
function BossModels.get(bossId: string?): BossRig.ModelModule
	return models[bossId or ""] or (VoidWardenModel :: any)
end

function BossModels.has(bossId: string): boolean
	return models[bossId] ~= nil
end

return BossModels
