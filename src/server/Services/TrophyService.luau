--!strict
-- Trophy pedestals (V2 phase 6): boss relics live here, behind the Core of
-- every Sanctuary, and NEVER on a normal pedestal.
--
--   * the save (`data.trophies`) is the truth; entities only mirror it;
--   * a trophy entity has no prompt at all (RelicService "Trophy" state):
--     it cannot be stolen, grabbed, carried or dissolved;
--   * pedestals unlock with the Power RECORD (Config/Bosses Trophies.Unlocks),
--     so a theft can never take one away;
--   * one trophy per boss relic: a duplicate drop levels it up, and at max
--     level the loot entry's fallback (boss materials) is paid instead.
--
-- Trophies produce Essence and count in Power like displayed relics
-- (EconomyService.recompute), which makes the exclusive drop worth it.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Relics = require(Shared.Config.Relics)
local Bosses = require(Shared.Config.Bosses)
local Layout = require(Shared.Layout)

local Core = script.Parent.Parent.Core
local Types = require(Core.Types)
local Sessions = require(Core.Sessions)
local PlotService = require(script.Parent.PlotService)
local RelicService = require(script.Parent.RelicService)

type Session = Types.Session

local TrophyService = {}

local function socleModel(plotIndex: number, slot: number): Model?
	local plot = PlotService.get(plotIndex)
	local folder = plot and plot.model:FindFirstChild("Trophies")
	return if folder then folder:FindFirstChild("Trophy" .. slot) :: Model? else nil
end

local function setSocle(plotIndex: number, slot: number, state: string)
	local model = socleModel(plotIndex, slot)
	if not model or model:GetAttribute("State") == state then
		return
	end
	model:SetAttribute("State", state)
	local visible = state ~= "Hidden"
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			local base = part:GetAttribute("BaseTransparency")
			part.Transparency = if visible then (if type(base) == "number" then base else 0) else 1
			part.CanCollide = visible
		end
	end
end

-- Unlocked pedestal count for this player (Power record).
function TrophyService.unlocked(session: Session): number
	return Bosses.trophySlots(session.data.power.peak)
end

-- Shows the unlocked pedestals of the session's Sanctuary (all hidden when
-- `session` is nil = the plot was released).
function TrophyService.refreshSocles(plotIndex: number, session: Session?)
	local unlocked = if session then TrophyService.unlocked(session) else 0
	local used: { [number]: boolean } = {}
	if session then
		for _, trophy in session.data.trophies do
			used[trophy.slot] = true
		end
	end
	for slot = 1, #Layout.TrophyAngles do
		local state = "Hidden"
		if session and (slot <= unlocked or used[slot]) then
			state = if used[slot] then "Filled" else "Active"
		end
		setSocle(plotIndex, slot, state)
	end
end

local function entityFor(session: Session, uid: string): RelicService.Entity?
	local entity = RelicService.get(uid)
	if entity and entity.state == "Trophy" and entity.ownerId == session.userId then
		return entity
	end
	return nil
end

local function spawnEntity(session: Session, trophy: Types.SaveTrophy): RelicService.Entity?
	local plotIndex = session.plot
	if plotIndex == nil then
		return nil
	end
	local position = Layout.trophyPosition(plotIndex, trophy.slot)
	local entity = RelicService.create({ id = trophy.id, level = trophy.level, uid = trophy.uid }, position)
	trophy.uid = entity.uid
	RelicService.toTrophy(entity, session.userId, plotIndex, trophy.slot, position)
	return entity
end

-- Player loaded / got a Sanctuary: rebuild the trophy entities.
function TrophyService.restore(session: Session)
	local plotIndex = session.plot
	if plotIndex == nil then
		return
	end
	for _, trophy in session.data.trophies do
		if not entityFor(session, trophy.uid) then
			spawnEntity(session, trophy)
		end
	end
	TrophyService.refreshSocles(plotIndex, session)
end

-- Player leaving: their trophies leave with them (still in the save).
function TrophyService.release(session: Session)
	for _, entity in RelicService.trophiesOf(session.userId) do
		RelicService.vanish(entity, "Leave")
	end
	if session.plot then
		TrophyService.refreshSocles(session.plot, nil)
	end
end

function TrophyService.find(session: Session, relicId: string): Types.SaveTrophy?
	for _, trophy in session.data.trophies do
		if trophy.id == relicId then
			return trophy
		end
	end
	return nil
end

local function freeSlot(session: Session): number?
	local used: { [number]: boolean } = {}
	for _, trophy in session.data.trophies do
		used[trophy.slot] = true
	end
	for slot = 1, TrophyService.unlocked(session) do
		if not used[slot] then
			return slot
		end
	end
	return nil
end

-- Awards a boss relic. Returns "placed" | "levelUp" | "full" (max level, or
-- no free pedestal: the caller pays the fallback) | "invalid".
-- Saved immediately in session data (marked cold); the entity follows.
function TrophyService.award(session: Session, relicId: string): (string, Types.SaveTrophy?)
	local def = Relics.get(relicId)
	if not def or def.bossOnly == nil then
		return "invalid", nil
	end
	local existing = TrophyService.find(session, relicId)
	if existing then
		if existing.level >= GameConfig.Economy.MaxRelicLevel then
			return "full", existing
		end
		existing.level += 1
		local entity = entityFor(session, existing.uid)
		if entity then
			RelicService.setLevel(entity, existing.level)
		end
		Sessions.markCold(session)
		return "levelUp", existing
	end
	local slot = freeSlot(session)
	if not slot then
		return "full", nil
	end
	local trophy: Types.SaveTrophy = { uid = HttpService:GenerateGUID(false), id = def.id, level = 1, slot = slot }
	table.insert(session.data.trophies, trophy)
	Sessions.markCold(session)
	spawnEntity(session, trophy)
	if session.plot then
		TrophyService.refreshSocles(session.plot, session)
	end
	return "placed", trophy
end

-- Power record went up (EconomyService.peakRaised): maybe a new pedestal.
function TrophyService.onPeakRaised(session: Session)
	if session.plot then
		TrophyService.refreshSocles(session.plot, session)
	end
end

return TrophyService
