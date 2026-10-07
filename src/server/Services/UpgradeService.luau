--!strict
-- Purchases. The client only names the upgrade; price, level caps, tier
-- requirements and the balance are all checked here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Upgrades = require(Shared.Config.Upgrades)
local Economy = require(Shared.Economy)
local Net = require(Shared.Net)

local Core = script.Parent.Parent.Core
local Types = require(Core.Types)
local Sessions = require(Core.Sessions)
local Remotes = require(Core.Remotes)
local PlotService = require(script.Parent.PlotService)
local EconomyService = require(script.Parent.EconomyService)
local CharacterService = require(script.Parent.CharacterService)
local TutorialService = require(script.Parent.TutorialService)

type Session = Types.Session

local UpgradeService = {}

function UpgradeService.purchase(session: Session, upgradeId: string): (boolean, string?)
	local def = Upgrades.get(upgradeId)
	if not def then
		return false, "invalid"
	end
	local upgrades = session.data.upgrades
	local blocker = Economy.upgradeBlocker(upgradeId, upgrades)
	if blocker then
		return false, blocker
	end
	local level = (upgrades :: any)[upgradeId] :: number
	local cost = Economy.upgradeCost(upgradeId, level)
	if cost == nil then
		return false, "max"
	end
	if not EconomyService.spend(session, cost) then
		return false, "notEnough"
	end
	local newLevel = level + 1;
	(upgrades :: any)[upgradeId] = newLevel

	local plot = PlotService.of(session)
	if def.effect == "pedestals" then
		if plot then
			PlotService.refreshPedestals(plot)
			Remotes.fx("PedestalUnlock", { plot = plot.index, slot = Economy.unlockedPedestals(upgrades) })
		end
	elseif def.effect == "tier" then
		if plot then
			local tier = Economy.tier(upgrades)
			PlotService.setTier(plot, tier)
			Remotes.fx("TierUp", { plot = plot.index, tier = tier, userId = session.userId })
			Remotes.notify(session.player, "n.tierUp", { tier = tier }, "rare")
		end
		EconomyService.recompute(session)
	elseif def.effect == "essenceMultiplier" then
		EconomyService.recompute(session)
	elseif def.effect == "walkSpeed" then
		CharacterService.refreshSpeed(session)
	end

	Remotes.fxTo(session.player, "Purchase", { id = upgradeId, level = newLevel })
	TutorialService.progress(session, "purchase")
	-- upgrades changed (Essence spent is hot and rides along)
	Sessions.markCold(session)
	return true, nil
end

function UpgradeService.start()
	Remotes.onInvoke(Net.Functions.Purchase, { rate = 4, burst = 6 }, function(player: Player, upgradeId: any)
		if type(upgradeId) ~= "string" or #upgradeId > 32 then
			return false, "invalid"
		end
		local session = Sessions.ready(player)
		if not session then
			return false, "loading"
		end
		Sessions.touch(session)
		return UpgradeService.purchase(session, upgradeId)
	end)
end

return UpgradeService
