--!strict
-- Cosmetics (V2 phase 5), server authority. Purely visual: nothing here (or
-- anywhere) reads a cosmetic to change gameplay.
--
--   EquipCosmetic(category, cosmeticId)  RemoteFunction; "" unequips. The id
--                                        must exist, belong to that category
--                                        and be OWNED by the player.
--
-- Ownership lives in the save (data.cosmetics.owned, schema 4). Automatic
-- unlocks (starter, Power record, stats, RiftDex, Sanctuary tier, play time)
-- are checked from data the game already tracks; future sources (boss,
-- event, daily, premium) are granted only by their own service through
-- CosmeticService.grant (phases 6-10: nothing grants them yet).
--
-- Replication: the equipped id of each category is published as a player
-- attribute ("Cos_<category>", "" = none) and the Sanctuary theme as the
-- Sanctuary model attribute "Theme". Every client renders from those.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Cosmetics = require(Shared.Config.Cosmetics)
local Economy = require(Shared.Economy)
local Signal = require(Shared.Util.Signal)

local Core = script.Parent.Parent.Core
local Types = require(Core.Types)
local Sessions = require(Core.Sessions)
local Remotes = require(Core.Remotes)
local Scheduler = require(Core.Scheduler)
local PlotService = require(script.Parent.PlotService)
local DexService = require(script.Parent.DexService)
local EconomyService = require(script.Parent.EconomyService)

type Session = Types.Session

local CosmeticService = {}

-- (session, cosmeticId) when a cosmetic is granted.
CosmeticService.unlocked = Signal.new()

-- Owned set used for equipping (the Studio test unlock is never saved).
function CosmeticService.ownedSet(session: Session): { [string]: boolean }
	if not session.devCosmetics then
		return session.data.cosmetics.owned
	end
	local all = table.clone(session.data.cosmetics.owned)
	for _, def in Cosmetics.list do
		all[def.id] = true
	end
	return all
end

function CosmeticService.owns(session: Session, cosmeticId: string): boolean
	return CosmeticService.ownedSet(session)[cosmeticId] == true
end

-- What automatic unlocks are measured against.
function CosmeticService.progress(session: Session): Cosmetics.Progress
	local data = session.data
	local found = DexService.counts(session)
	return {
		powerPeak = data.power.peak,
		stats = data.stats :: any,
		dexFound = found,
		tier = Economy.tier(data.upgrades),
		playTime = Sessions.playTime(session),
	}
end

-- Publishes what every client needs to draw this player's cosmetics.
function CosmeticService.publish(session: Session)
	local equipped = session.data.cosmetics.equipped
	local player = session.player
	for _, category in Cosmetics.Categories do
		local id = equipped[category.id] or ""
		if player:GetAttribute(category.attribute) ~= id then
			player:SetAttribute(category.attribute, id)
		end
	end
	local plot = PlotService.of(session)
	if plot and plot.owner == session then
		local theme = equipped.sanctuary or ""
		if plot.model:GetAttribute("Theme") ~= theme then
			plot.model:SetAttribute("Theme", theme)
		end
	end
end

local function grantInternal(session: Session, def: Cosmetics.CosmeticDef, notify: boolean)
	session.data.cosmetics.owned[def.id] = true
	Sessions.markCold(session)
	CosmeticService.unlocked:Fire(session, def.id)
	if notify then
		Remotes.notify(session.player, "n.cosmeticUnlocked", { cosmetic = def.id }, "rare")
	end
end

-- Grants every automatic unlock now met. Returns the new ids.
function CosmeticService.evaluate(session: Session, notify: boolean?): { string }
	local granted: { string } = {}
	local owned = session.data.cosmetics.owned
	local progress: Cosmetics.Progress? = nil
	for _, def in Cosmetics.list do
		if owned[def.id] or not Cosmetics.UnlockKinds[def.unlock.kind].auto then
			continue
		end
		progress = progress or CosmeticService.progress(session)
		if Cosmetics.isMet(def, progress :: Cosmetics.Progress) then
			table.insert(granted, def.id)
		end
	end
	local loud = notify ~= false and #granted <= 3
	for _, id in granted do
		grantInternal(session, Cosmetics.get(id) :: Cosmetics.CosmeticDef, loud)
	end
	if notify ~= false and #granted > 3 then
		Remotes.notify(session.player, "n.cosmeticsUnlocked", { amount = #granted }, "rare")
	end
	return granted
end

-- Future sources (boss / event / daily / premium): called by their services
-- only, never from a client. The source must match the cosmetic's own.
-- Returns (granted, reason?). reason: "invalid" | "source" | "owned"
function CosmeticService.grant(session: Session, cosmeticId: any, source: any): (boolean, string?)
	local def = Cosmetics.get(cosmeticId)
	if not def then
		return false, "invalid"
	end
	local kind = Cosmetics.UnlockKinds[def.unlock.kind]
	if type(source) ~= "string" or source ~= def.unlock.kind or kind.auto then
		return false, "source"
	end
	if session.data.cosmetics.owned[def.id] then
		return false, "owned"
	end
	grantInternal(session, def, true)
	return true, nil
end

-- Returns (ok, reason?). reason: "invalid" | "category" | "locked"
function CosmeticService.equip(player: Player, categoryId: any, cosmeticId: any): (boolean, string?)
	local session = Sessions.ready(player)
	if not session then
		return false, "invalid"
	end
	local category = Cosmetics.category(categoryId)
	if not category or type(cosmeticId) ~= "string" or #cosmeticId > 32 then
		return false, "invalid"
	end
	local equipped = session.data.cosmetics.equipped
	if cosmeticId == "" then
		if equipped[category.id] ~= nil then
			equipped[category.id] = nil
			Sessions.markCold(session)
			CosmeticService.publish(session)
		end
		return true, nil
	end
	local def = Cosmetics.get(cosmeticId)
	if not def then
		return false, "invalid"
	end
	if def.category ~= category.id then
		return false, "category"
	end
	if not CosmeticService.owns(session, def.id) then
		return false, "locked"
	end
	if equipped[category.id] ~= def.id then
		equipped[category.id] = def.id
		Sessions.markCold(session)
		CosmeticService.publish(session)
	end
	return true, nil
end

-- Studio test unlock (DevCommands /rh cosmetics): session only.
function CosmeticService.setDevUnlock(session: Session, enabled: boolean)
	session.devCosmetics = enabled
	if not enabled then
		local owned = session.data.cosmetics.owned
		for category, id in table.clone(session.data.cosmetics.equipped) do
			if not owned[id] then
				session.data.cosmetics.equipped[category] = nil
			end
		end
		CosmeticService.publish(session)
	end
	Sessions.markCold(session)
end

-- Studio: back to the starters only (to test the unlocks again).
function CosmeticService.reset(session: Session)
	session.data.cosmetics.owned = Cosmetics.starters()
	table.clear(session.data.cosmetics.equipped)
	Sessions.markCold(session)
	CosmeticService.publish(session)
end

-- Player loaded (or got a Sanctuary): catch up on unlocks, publish.
function CosmeticService.onReady(session: Session)
	CosmeticService.evaluate(session, true)
	CosmeticService.publish(session)
end

function CosmeticService.start()
	Remotes.onInvoke(Net.Functions.EquipCosmetic, { rate = 4, burst = 8 }, CosmeticService.equip)
	EconomyService.peakRaised:Connect(function(session: Session)
		CosmeticService.evaluate(session, true)
	end)
	-- Stats, RiftDex, tier and play time grow in many places: one cheap
	-- periodic check instead of hooks everywhere.
	Scheduler.every("Cosmetics.unlocks", 2, function()
		for _, session in Sessions.all() do
			CosmeticService.evaluate(session, true)
		end
	end)
end

return CosmeticService
