--!strict
-- Builds the private state snapshot sent to a player's client. Only data the
-- client needs for display; nothing here is ever trusted back.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Types = require(script.Parent.Types)
local Sessions = require(script.Parent.Sessions)

local Snapshot = {}

function Snapshot.build(session: Types.Session): { [string]: any }
	local data = session.data
	local dex = {}
	for relicId, entry in data.dex do
		dex[relicId] = { count = entry.count, mutations = table.clone(entry.mutations) }
	end
	local playTime = Sessions.playTime(session)
	return {
		essence = data.essence,
		lifetimeEssence = data.lifetimeEssence,
		upgrades = table.clone(data.upgrades),
		dex = dex,
		stats = table.clone(data.stats),
		tutorial = data.tutorial,
		tips = table.clone(data.tips),
		settings = table.clone(data.settings),
		plot = session.plot or 0,
		carrying = table.clone(session.carrying),
		cooldowns = table.clone(session.cooldowns),
		rate = session.rate,
		multiplier = session.multiplier,
		noviceUntil = workspace:GetServerTimeNow() + math.max(0, GameConfig.Steal.NoviceSeconds - playTime),
		canSave = session.canSave,
		dataStatus = session.dataStatus,
	}
end

return Snapshot
