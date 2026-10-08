--!strict
-- Essence production, the Sanctuary Core storage and collection, spending,
-- and offline earnings. All amounts are computed here on the server; clients
-- only ever receive results.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local AbilityConfig = require(Shared.Config.Abilities)
local Economy = require(Shared.Economy)
local Power = require(Shared.Power)
local Signal = require(Shared.Util.Signal)

local Core = script.Parent.Parent.Core
local Types = require(Core.Types)
local Sessions = require(Core.Sessions)
local Remotes = require(Core.Remotes)
local Scheduler = require(Core.Scheduler)
local PlotService = require(script.Parent.PlotService)
local RelicService = require(script.Parent.RelicService)
local DexService = require(script.Parent.DexService)
local TutorialService = require(script.Parent.TutorialService)

type Session = Types.Session

local EconomyService = {}

-- (session, previousPeak, newPeak) when the Power record goes up.
EconomyService.peakRaised = Signal.new()

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

local function setLeaderstat(session: Session, name: string, value: number)
	local stats = session.leaderstats
	if stats then
		local stat = stats:FindFirstChild(name)
		if stat and stat:IsA("IntValue") then
			stat.Value = math.floor(value)
		end
	end
end

-- Recomputes everything derived from the displayed collection: Essence rate,
-- multiplier and Power (current + record). Called after every change to
-- placed relics, upgrades or the RiftDex.
function EconomyService.recompute(session: Session)
	local relicsFound, mutationsFound = DexService.counts(session)
	local multiplier = Economy.playerMultiplier(session.data.upgrades, relicsFound, mutationsFound)
	local total = 0
	local placed: { Power.RelicLike } = {}
	local harmonyRelics: { string } = {}
	for _, entity in RelicService.placedBy(session.userId) do
		total += Economy.relicBaseRate(entity.id, entity.level, entity.mutation)
		table.insert(placed, { id = entity.id, level = entity.level, mutation = entity.mutation })
		if AbilityConfig.harmony(entity.id) and not table.find(harmonyRelics, entity.id) then
			table.insert(harmonyRelics, entity.id)
		end
	end
	-- Boss relics on trophy pedestals (phase 6) produce and count in Power
	-- like displayed relics; they can never be stolen.
	for _, entity in RelicService.trophiesOf(session.userId) do
		total += Economy.relicBaseRate(entity.id, entity.level, entity.mutation)
		table.insert(placed, { id = entity.id, level = entity.level, mutation = entity.mutation })
	end
	table.sort(harmonyRelics)
	session.multiplier = multiplier
	session.rate = total * multiplier
	-- Harmonies follow the displayed collection (a relic out on a heist does not count).
	session.harmonyRelics = harmonyRelics

	-- Power only counts relics displayed in the Sanctuary (a relic being
	-- stolen leaves it immediately), so it drops on theft; the record never does.
	-- Without a Sanctuary yet (queued), the collection is not displayed:
	-- keep the previous value rather than flashing 0.
	if session.plot ~= nil then
		session.power = Power.total(placed, session.data.upgrades, relicsFound, mutationsFound)
		if session.power > session.data.power.peak then
			local previous = session.data.power.peak
			session.data.power.peak = session.power
			Sessions.markCold(session)
			EconomyService.peakRaised:Fire(session, previous, session.power)
		end
		setLeaderstat(session, "Power", session.power)
	end
	publishCore(session)
	Sessions.markDirty(session)
end

local function updateLeaderstat(session: Session)
	setLeaderstat(session, "Essence", session.data.essence)
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

-- `immediate` skips the anti-spam throttle (used when production lands while
-- the owner is already standing on the Core, so it never lingers there).
local function collect(session: Session, root: BasePart, immediate: boolean?)
	local stored = math.floor(session.data.coreStored)
	if stored < 1 then
		return
	end
	local t = os.clock()
	if not immediate and t - (lastCollect[session] or 0) < 0.4 then
		return
	end
	lastCollect[session] = t
	session.data.coreStored -= stored
	EconomyService.addEssence(session, stored)
	session.data.stats.essenceCollected += stored
	Sessions.markCold(session)
	publishCore(session)
	Remotes.fxTo(session.player, "Collect", { amount = stored, plot = session.plot })
	Remotes.fx("CoreBurst", { plot = session.plot })
	TutorialService.progress(session, "collect")
	Sessions.touch(session)
end

local function standingOnCore(session: Session): BasePart?
	local index = session.plot
	if index == nil then
		return nil
	end
	local _, _, root = Sessions.character(session)
	if not root then
		return nil
	end
	local offset = root.Position - PlotService.corePosition(index)
	if math.abs(offset.Y) < 9 and Vector3.new(offset.X, 0, offset.Z).Magnitude <= GameConfig.Sanctuary.CollectRadius then
		return root
	end
	return nil
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
		local root = standingOnCore(session)
		if root then
			collect(session, root, true)
		end
	end
end

local function collectTick()
	for _, session in Sessions.all() do
		local root = standingOnCore(session)
		if root then
			collect(session, root)
		end
	end
end

function EconomyService.forget(session: Session)
	lastCollect[session] = nil
end

function EconomyService.start()
	Scheduler.every("Economy.production", 1, productionTick)
	Scheduler.every("Economy.collect", 0.2, collectTick)
end

return EconomyService
