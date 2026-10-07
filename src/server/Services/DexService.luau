--!strict
-- RiftDex: records which relics (and mutation variants) a player has secured.
-- Discoveries feed a permanent collection bonus (see Economy.dexMultiplier).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Relics = require(ReplicatedStorage.Shared.Config.Relics)

local Core = script.Parent.Parent.Core
local Types = require(Core.Types)
local Sessions = require(Core.Sessions)

type Session = Types.Session

local DexService = {}

function DexService.counts(session: Session): (number, number)
	local relics, mutations = 0, 0
	for relicId, entry in session.data.dex do
		if Relics.get(relicId) then
			relics += 1
			for _ in entry.mutations do
				mutations += 1
			end
		end
	end
	return relics, mutations
end

-- Returns (isNewRelic, isNewMutation).
function DexService.register(session: Session, relicId: string, mutation: string?): (boolean, boolean)
	local dex = session.data.dex
	local entry = dex[relicId]
	local isNew = entry == nil
	if not entry then
		entry = { count = 0, mutations = {}, first = os.time() }
		dex[relicId] = entry
	end
	entry.count += 1
	local isNewMutation = false
	if mutation and not entry.mutations[mutation] then
		entry.mutations[mutation] = true
		isNewMutation = true
	end
	Sessions.markCold(session)
	local stats = session.leaderstats
	if stats then
		local found = stats:FindFirstChild("RiftDex")
		if found and found:IsA("IntValue") then
			found.Value = DexService.counts(session)
		end
	end
	return isNew, isNewMutation
end

return DexService
