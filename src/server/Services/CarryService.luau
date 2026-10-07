--!strict
-- Physical relic transport: claiming from the Rift, carrying, dropping when
-- hit or killed, depositing (or fusing duplicates) on entering your own
-- Sanctuary, securing stolen relics, returning stolen relics home, and
-- dissolving relics for Essence.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Rarities = require(Shared.Config.Rarities)
local Relics = require(Shared.Config.Relics)
local Economy = require(Shared.Economy)

local Core = script.Parent.Parent.Core
local Types = require(Core.Types)
local Sessions = require(Core.Sessions)
local Remotes = require(Core.Remotes)
local Scheduler = require(Core.Scheduler)
local PlotService = require(script.Parent.PlotService)
local RelicService = require(script.Parent.RelicService)
local EconomyService = require(script.Parent.EconomyService)
local DexService = require(script.Parent.DexService)
local TutorialService = require(script.Parent.TutorialService)
local CharacterService = require(script.Parent.CharacterService)

type Session = Types.Session
type Entity = RelicService.Entity

local CarryService = {}

local CARRY = GameConfig.Carry

local function now(): number
	return workspace:GetServerTimeNow()
end

function CarryService.capacity(session: Session): number
	return Economy.carryCapacity(session.data.upgrades.harness)
end

function CarryService.attach(session: Session, entity: Entity)
	if not table.find(session.carrying, entity.uid) then
		table.insert(session.carrying, entity.uid)
	end
	CharacterService.refreshSpeed(session)
	Sessions.markDirty(session)
end

local function detach(session: Session, uid: string)
	local index = table.find(session.carrying, uid)
	if index then
		table.remove(session.carrying, index)
		CharacterService.refreshSpeed(session)
		Sessions.markDirty(session)
	end
end

local function findSaveRelic(session: Session, uid: string): (Types.SaveRelic?, number?)
	for index, relic in session.data.relics do
		if relic.uid == uid then
			return relic, index
		end
	end
	return nil, nil
end

-- A placed relic of the same kind that can absorb `entity` as a level-up.
local function fuseTarget(session: Session, entity: Entity): Entity?
	local best: Entity? = nil
	for _, placed in RelicService.placedBy(session.userId) do
		if placed.id == entity.id and (placed.mutation or "") == (entity.mutation or "") and placed.level < GameConfig.Economy.MaxRelicLevel then
			if best == nil or placed.level > best.level then
				best = placed
			end
		end
	end
	return best
end

-- Whether `session` has room at home for `entity` (free pedestal or fusion).
function CarryService.canAccept(session: Session, entity: Entity): boolean
	local plot = PlotService.of(session)
	if not plot then
		return false
	end
	return fuseTarget(session, entity) ~= nil or PlotService.freeSlot(plot) ~= nil
end

----------------------------------------------------------------------------
-- Returning stolen relics
----------------------------------------------------------------------------

-- reason: "Recovered" (owner grabbed it back) | "Returned" (timed out / thief left)
function CarryService.returnToOwner(entity: Entity, reason: string)
	if not entity.alive then
		return
	end
	if entity.carrierId then
		local carrier = Sessions.byUserId(entity.carrierId)
		if carrier then
			detach(carrier, entity.uid)
		end
	end
	local victim = Sessions.byUserId(entity.stolenFrom)
	local plot = if victim then PlotService.of(victim) else nil
	local slot = entity.returnSlot
	if not victim or not plot or not slot then
		RelicService.vanish(entity, "Faded")
		return
	end
	PlotService.reserve(plot, slot, nil)
	RelicService.toPlaced(entity, victim.userId, plot.index, slot, PlotService.slotPosition(plot.index, slot))
	PlotService.setSlot(plot, slot, entity.uid, entity.rarity)
	EconomyService.recompute(victim)
	Remotes.fx("ReturnHome", { uid = entity.uid, reason = reason, plot = plot.index })
	if reason == "Recovered" then
		victim.data.stats.recovered += 1
		Sessions.markCold(victim)
		Remotes.notify(victim.player, "n.recovered", { relic = entity.id }, "success")
	else
		Remotes.notify(victim.player, "n.returnedHome", { relic = entity.id }, "success")
	end
end

----------------------------------------------------------------------------
-- Claim / grab
----------------------------------------------------------------------------

function CarryService.claim(player: Player, entity: Entity)
	local session = Sessions.ready(player)
	if not session then
		return
	end
	Sessions.touch(session)
	if not entity.alive or (entity.state ~= "Rift" and entity.state ~= "Dropped") then
		if Sessions.allowNotice(session, "claimTaken", 2) then
			Remotes.notify(player, "n.claimTaken", nil, "warning")
		end
		return
	end
	local _, _, root = Sessions.character(session)
	if not root then
		return
	end
	if now() < session.stunnedUntil then
		return
	end
	if (root.Position - entity.anchor.Position).Magnitude > GameConfig.Rift.ClaimDistance + 2 then
		return
	end

	-- The owner grabbing their own stolen relic sends it straight home.
	if entity.state == "Dropped" and entity.stolenFrom == session.userId then
		CarryService.returnToOwner(entity, "Recovered")
		return
	end

	if #session.carrying >= CarryService.capacity(session) then
		if Sessions.allowNotice(session, "carryFull", 3) then
			Remotes.notify(player, "n.carryFull", nil, "warning")
		end
		return
	end

	local fromRift = entity.state == "Rift"
	RelicService.toCarried(entity, session.userId, entity.stolenFrom)
	CarryService.attach(session, entity)
	if fromRift then
		session.data.stats.claimed += 1
		Sessions.markCold(session)
	end
	Remotes.fx("Pickup", { uid = entity.uid, userId = session.userId, rarity = entity.rarity, fromRift = fromRift })
	TutorialService.progress(session, "claim")

	local rarity = Rarities.get(entity.rarity)
	if fromRift and rarity.announce == "server" then
		Remotes.notifyAll("n.rareClaimed", { player = player.DisplayName, relic = entity.id }, "rare", player)
	end
end

----------------------------------------------------------------------------
-- Dropping
----------------------------------------------------------------------------

function CarryService.drop(session: Session, entity: Entity, position: Vector3?)
	detach(session, entity.uid)
	if position == nil or position.Y < GameConfig.Player.VoidKillY + 20 then
		if entity.stolenFrom then
			CarryService.returnToOwner(entity, "Returned")
		else
			RelicService.vanish(entity, "Faded")
		end
		return
	end
	local lifetime = if entity.stolenFrom then CARRY.StolenDropReturn else CARRY.DropLifetime
	RelicService.toDropped(entity, position, now() + lifetime)
	Remotes.fx("Dropped", { uid = entity.uid, userId = session.userId, position = position })
end

function CarryService.dropAll(session: Session, position: Vector3?)
	local origin = position or Sessions.rootPosition(session) or session.lastPosition
	local carried = table.clone(session.carrying)
	for i, uid in carried do
		local entity = RelicService.get(uid)
		if entity then
			local scattered: Vector3? = nil
			if origin then
				local angle = i * 2.4
				scattered = origin + Vector3.new(math.cos(angle) * 3.5, 0.8, math.sin(angle) * 3.5)
			end
			CarryService.drop(session, entity, scattered)
		else
			detach(session, uid)
		end
	end
end

----------------------------------------------------------------------------
-- Depositing
----------------------------------------------------------------------------

local function deposit(session: Session, entity: Entity, from: Vector3): boolean
	local plot = PlotService.of(session)
	if not plot then
		return false
	end
	local stolenFrom = entity.stolenFrom
	local victim = if stolenFrom then Sessions.byUserId(stolenFrom) else nil
	if stolenFrom and not victim then
		detach(session, entity.uid)
		RelicService.vanish(entity, "Faded")
		return true
	end

	local target = fuseTarget(session, entity)
	local slot = if target then nil else PlotService.freeSlot(plot)
	if not target and not slot then
		if Sessions.allowNotice(session, "pedestalsFull", 12) then
			Remotes.notify(session.player, "n.pedestalsFull", nil, "warning")
		end
		return false
	end

	-- Securing a heist transfers ownership from the victim's save.
	if stolenFrom and victim then
		local victimPlot = PlotService.of(victim)
		if victimPlot and entity.returnSlot then
			PlotService.reserve(victimPlot, entity.returnSlot, nil)
		end
		local _, index = findSaveRelic(victim, entity.uid)
		if index then
			table.remove(victim.data.relics, index)
		end
		victim.data.stats.lost += 1
		session.data.stats.stolen += 1
		Sessions.markCold(victim)
		Sessions.markCold(session)
		EconomyService.recompute(victim)
		Remotes.notify(victim.player, "n.lostRelic", { thief = session.player.DisplayName, relic = entity.id }, "danger")
		Remotes.fx("HeistSecured", { uid = entity.uid, thiefId = session.userId, victimId = victim.userId, relicId = entity.id, rarity = entity.rarity })
	end

	detach(session, entity.uid)
	if target then
		local level = math.min(target.level + 1, GameConfig.Economy.MaxRelicLevel)
		RelicService.setLevel(target, level)
		local saved = findSaveRelic(session, target.uid)
		if saved then
			saved.level = level
		end
		RelicService.vanish(entity, "Fused")
		Remotes.fx("Fuse", { uid = entity.uid, target = target.uid, from = from, level = level, userId = session.userId })
		Remotes.notify(session.player, "n.fused", { relic = entity.id, level = level }, "success")
	else
		local slotIndex = slot :: number
		RelicService.toPlaced(entity, session.userId, plot.index, slotIndex, PlotService.slotPosition(plot.index, slotIndex))
		PlotService.setSlot(plot, slotIndex, entity.uid, entity.rarity)
		table.insert(session.data.relics, {
			uid = entity.uid,
			id = entity.id,
			level = entity.level,
			mutation = entity.mutation,
			slot = slotIndex,
		})
		Remotes.fx("Deposit", { uid = entity.uid, from = from, userId = session.userId, plot = plot.index, slot = slotIndex })
	end

	session.data.stats.deposits += 1
	if Rarities.isAtLeast(entity.rarity, "Legendary") then
		session.data.stats.rareFinds += 1
	end

	local isNew, isNewMutation = DexService.register(session, entity.id, entity.mutation)
	if isNew or isNewMutation then
		local found = DexService.counts(session)
		Remotes.fxTo(session.player, "Discovery", {
			relicId = entity.id,
			mutation = entity.mutation,
			isNew = isNew,
			isNewMutation = isNewMutation,
			found = found,
			total = Relics.count,
		})
	end

	if not session.data.tips.firstGift then
		session.data.tips.firstGift = true
		EconomyService.recompute(session)
		EconomyService.addToCore(session, GameConfig.Economy.FirstDepositGift)
	end
	EconomyService.recompute(session)
	TutorialService.progress(session, "deposit")
	-- stats + Dex changed
	Sessions.markCold(session)
	return true
end

----------------------------------------------------------------------------
-- Dissolving
----------------------------------------------------------------------------

function CarryService.dissolvePlaced(session: Session, uid: string): (boolean, string?)
	local entity = RelicService.get(uid)
	if not entity or entity.state ~= "Placed" or entity.ownerId ~= session.userId then
		return false, "invalid"
	end
	local plot = PlotService.of(session)
	if not plot or entity.plot ~= plot.index or entity.slot == nil then
		return false, "invalid"
	end
	local value = Economy.dissolveValue(entity.id, entity.level, entity.mutation, session.multiplier)
	local _, index = findSaveRelic(session, uid)
	if index then
		table.remove(session.data.relics, index)
	end
	PlotService.setSlot(plot, entity.slot :: number, nil)
	RelicService.vanish(entity, "Dissolved")
	EconomyService.addEssence(session, value)
	EconomyService.recompute(session)
	Remotes.fx("Dissolve", { uid = uid, amount = value, userId = session.userId })
	return true, tostring(value)
end

function CarryService.dissolveCarried(session: Session, uid: string): (boolean, string?)
	local entity = RelicService.get(uid)
	if not entity or entity.state ~= "Carried" or entity.carrierId ~= session.userId or entity.stolenFrom ~= nil then
		return false, "invalid"
	end
	local value = Economy.dissolveValue(entity.id, entity.level, entity.mutation, session.multiplier)
	detach(session, uid)
	RelicService.vanish(entity, "Dissolved")
	EconomyService.addEssence(session, value)
	Remotes.fx("Dissolve", { uid = uid, amount = value, userId = session.userId })
	return true, tostring(value)
end

----------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------

-- Called when a player leaves: nothing they touched may be lost or duplicated.
function CarryService.onLeave(session: Session)
	local position = Sessions.rootPosition(session) or session.lastPosition
	-- 1. Relics they were carrying.
	for _, uid in table.clone(session.carrying) do
		local entity = RelicService.get(uid)
		if entity then
			if entity.stolenFrom then
				CarryService.returnToOwner(entity, "Returned")
			else
				CarryService.drop(session, entity, if position then position + Vector3.new(0, 0.8, 0) else nil)
			end
		end
	end
	table.clear(session.carrying)
	-- 2. Their own relics currently out on a heist: still in their save, so
	--    the chase is voided and the relic leaves with them.
	for _, entity in RelicService.all() do
		if entity.stolenFrom == session.userId then
			if entity.carrierId then
				local carrier = Sessions.byUserId(entity.carrierId)
				if carrier then
					detach(carrier, entity.uid)
					Remotes.notify(carrier.player, "n.ownerLeft", nil, "info")
				end
			end
			RelicService.vanish(entity, "Faded")
		end
	end
	-- 3. Their displayed collection.
	for _, entity in RelicService.placedBy(session.userId) do
		RelicService.vanish(entity, "Leave")
	end
end

local function carryTick()
	local t = now()
	for _, session in Sessions.all() do
		if #session.carrying == 0 then
			continue
		end
		local _, _, root = Sessions.character(session)
		if not root then
			continue
		end
		local position = root.Position
		for _, uid in table.clone(session.carrying) do
			local entity = RelicService.get(uid)
			if not entity then
				detach(session, uid)
				continue
			end
			RelicService.moveAnchor(entity, position + Vector3.new(0, 4, 0))
			if entity.stolenFrom and entity.stolenAt and t - entity.stolenAt > CARRY.StolenMaxCarry then
				CarryService.returnToOwner(entity, "Returned")
			end
		end
		if session.plot and PlotService.isInside(session.plot, position) then
			for _, uid in table.clone(session.carrying) do
				local entity = RelicService.get(uid)
				if entity then
					deposit(session, entity, position)
				end
			end
		end
	end
end

local function droppedTick()
	local t = now()
	for _, entity in RelicService.all() do
		if entity.state == "Dropped" and entity.expiresAt and entity.expiresAt <= t then
			if entity.stolenFrom then
				CarryService.returnToOwner(entity, "Returned")
			else
				RelicService.vanish(entity, "Faded")
			end
		end
	end
end

function CarryService.start()
	RelicService.promptTriggered:Connect(function(player: Player, entity: Entity, action: string)
		if action == "Claim" or action == "Grab" then
			CarryService.claim(player, entity)
		end
	end)
	CharacterService.died:Connect(function(session: Session, position: Vector3?)
		if #session.carrying > 0 then
			CarryService.dropAll(session, position)
		end
	end)
	Scheduler.every("Carry.deposit", CARRY.DepositCheckInterval, carryTick)
	Scheduler.every("Carry.dropped", 1, droppedTick)
end

return CarryService
