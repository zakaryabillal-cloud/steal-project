--!strict
-- Essence production, the Sanctuary Core storage and collection, spending,
-- and offline earnings. All amounts are computed here on the server; clients
-- only ever receive results.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Economy = require(Shared.Economy)

local Core = script.Parent.Parent.Core
local Types = require(Core.Types)
local Sessions = require(Core.Sessions)
local Remotes = require(Core.Remotes)
local PlotService = require(script.Parent.PlotService)
local RelicService = require(script.Parent.RelicService)
local DexService = require(script.Parent.DexService)
local TutorialService = require(script.Parent.TutorialService)

type Session = Types.Session

local EconomyService = {}

local lastCollect: { [Session]: number } = {}

function EconomyService.capacity(session: Session): number
	return Economy.coreCapacity(Economy.tier(session.data.upgrades), session.rate)
end

local function publishCore(session: Session)
	local plot = PlotService.of(session)
	if not plot then
		return
	end
	local model = plot.model
	model:SetAttribute("CoreStored", math.floor(session.data.coreStored))
	model:SetAttribute("CoreCapacity", EconomyService.capacity(session))
	model:SetAttribute("Rate", session.rate)
end

function EconomyService.recompute(session: Session)
	local relicsFound, mutationsFound = DexService.counts(session)
	local multiplier = Economy.playerMultiplier(session.data.upgrades, relicsFound, mutationsFound)
	local total = 0
	for _, entity in RelicService.placedBy(session.userId) do
		total += Economy.relicBaseRate(entity.id, entity.level, entity.mutation)
	end
	session.multiplier = multiplier
	session.rate = total * multiplier
	publishCore(session)
	Sessions.markDirty(session)
end

local function updateLeaderstat(session: Session)
	local stats = session.leaderstats
	if stats then
		local value = stats:FindFirstChild("Essence")
		if value and value:IsA("IntValue") then
			value.Value = math.floor(session.data.essence)
		end
	end
end

function EconomyService.addEssence(session: Session, amount: number)
	local gain = math.floor(math.max(0, amount))
	if gain <= 0 then
		return
	end
	session.data.essence += gain
	session.data.lifetimeEssence += gain
	updateLeaderstat(session)
	Sessions.markDirty(session)
end

function EconomyService.spend(session: Session, amount: number): boolean
	if amount < 0 or session.data.essence < amount then
		return false
	end
	session.data.essence -= amount
	updateLeaderstat(session)
	Sessions.markDirty(session)
	return true
end

function EconomyService.addToCore(session: Session, amount: number)
	local capacity = EconomyService.capacity(session)
	session.data.coreStored = math.min(capacity, session.data.coreStored + amount)
	publishCore(session)
end

function EconomyService.applyOffline(session: Session)
	local lastSeen = session.data.lastSeen
	if lastSeen <= 0 or session.rate <= 0 then
		return
	end
	local elapsed = math.clamp(os.time() - lastSeen, 0, GameConfig.Economy.OfflineMaxSeconds)
	local gained = session.rate * elapsed * GameConfig.Economy.OfflineRate
	local before = session.data.coreStored
	EconomyService.addToCore(session, gained)
	local actual = math.floor(session.data.coreStored - before)
	if actual >= 1 then
		Remotes.notify(session.player, "n.offline", { amount = actual }, "success")
	end
end

local function collect(session: Session, root: BasePart)
	local stored = math.floor(session.data.coreStored)
	if stored < 1 then
		return
	end
	local t = os.clock()
	if t - (lastCollect[session] or 0) < 0.4 then
		return
	end
	lastCollect[session] = t
	session.data.coreStored -= stored
	EconomyService.addEssence(session, stored)
	session.data.stats.essenceCollected += stored
	publishCore(session)
	Remotes.fxTo(session.player, "Collect", { amount = stored, plot = session.plot })
	Remotes.fx("CoreBurst", { plot = session.plot })
	TutorialService.progress(session, "collect")
	Sessions.touch(session)
end

local function productionTick()
	for _, session in Sessions.all() do
		if session.plot == nil then
			continue
		end
		local capacity = EconomyService.capacity(session)
		local before = session.data.coreStored
		session.data.coreStored = math.min(capacity, before + session.rate)
		if before < capacity and session.data.coreStored >= capacity and session.rate > 0 then
			if Sessions.allowNotice(session, "coreFull", 90) then
				Remotes.notify(session.player, "n.coreFull", nil, "warning")
			end
		end
		publishCore(session)
	end
end

local function collectTick()
	local radius = GameConfig.Sanctuary.CollectRadius
	for _, session in Sessions.all() do
		local index = session.plot
		if index == nil then
			continue
		end
		local _, _, root = Sessions.character(session)
		if not root then
			continue
		end
		local core = PlotService.corePosition(index)
		local offset = root.Position - core
		if math.abs(offset.Y) < 9 and Vector3.new(offset.X, 0, offset.Z).Magnitude <= radius then
			collect(session, root)
		end
	end
end

function EconomyService.forget(session: Session)
	lastCollect[session] = nil
end

function EconomyService.start()
	task.spawn(function()
		while true do
			task.wait(1)
			productionTick()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.2)
			collectTick()
		end
	end)
end

return EconomyService
