--!strict
-- Theft: hold the prompt on another player's displayed relic, then escape
-- with it to your own Sanctuary. Every rule is enforced here:
--   * must physically stand inside the victim's Sanctuary, within reach,
--   * the hold duration is verified server-side (scales with rarity),
--   * victims are alerted the moment a hold begins,
--   * protections: seal, Aegis after a theft, novice playtime, AFK rest,
--     and nobody can be robbed below their last relics,
--   * thief cooldown, carry capacity, free room at home,
--   * anti-harassment limits per thief->victim pair and per victim.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Rarities = require(Shared.Config.Rarities)

local Core = script.Parent.Parent.Core
local Types = require(Core.Types)
local Sessions = require(Core.Sessions)
local Remotes = require(Core.Remotes)
local PlotService = require(script.Parent.PlotService)
local RelicService = require(script.Parent.RelicService)
local EconomyService = require(script.Parent.EconomyService)
local CarryService = require(script.Parent.CarryService)

type Session = Types.Session
type Entity = RelicService.Entity

local StealService = {}

local STEAL = GameConfig.Steal

local function now(): number
	return workspace:GetServerTimeNow()
end

local function prune(list: { number }, window: number): { number }
	local t = now()
	local kept = {}
	for _, stamp in list do
		if t - stamp < window then
			table.insert(kept, stamp)
		end
	end
	return kept
end

-- Returns (ok, reasonKey?, args?)
function StealService.check(thief: Session, entity: Entity): (boolean, string?, { [string]: any }?)
	if not entity.alive or entity.state ~= "Placed" then
		return false, "block.unavailable", nil
	end
	local victim = Sessions.byUserId(entity.ownerId)
	if not victim then
		return false, "block.unavailable", nil
	end
	if victim == thief then
		return false, nil, nil
	end
	if thief.plot == nil then
		return false, "block.noPlot", nil
	end
	local _, _, root = Sessions.character(thief)
	if not root then
		return false, nil, nil
	end
	if now() < thief.stunnedUntil then
		return false, "block.stunned", nil
	end
	if (root.Position - entity.anchor.Position).Magnitude > STEAL.MaxDistance then
		return false, "block.distance", nil
	end
	local plot = PlotService.get(entity.plot)
	if not plot or plot.owner ~= victim then
		return false, "block.unavailable", nil
	end
	if not PlotService.isInside(plot.index, root.Position) then
		return false, "block.inside", nil
	end
	local kind, untilTime = PlotService.protection(plot)
	if kind == "Sealed" then
		return false, "block.sealed", nil
	elseif kind == "Aegis" then
		return false, "block.aegis", { time = (untilTime or now()) - now() }
	elseif kind == "Expedition" then
		return false, "block.expedition", nil
	elseif kind == "Novice" then
		return false, "block.novice", nil
	elseif kind == "Resting" then
		return false, "block.resting", nil
	elseif kind == "LastRelics" then
		return false, "block.lastRelics", nil
	end
	if not Sessions.cooldownReady(thief, "steal") then
		return false, "block.cooldown", { time = (thief.cooldowns.steal or 0) - now() }
	end
	if #thief.carrying >= CarryService.capacity(thief) then
		return false, "block.capacity", nil
	end
	if not CarryService.canAccept(thief, entity) then
		return false, "block.pedestals", nil
	end
	local pairLog = prune(thief.stealLog[victim.userId] or {}, STEAL.PairWindow)
	thief.stealLog[victim.userId] = pairLog
	if #pairLog >= STEAL.PairLimit then
		return false, "block.limit", nil
	end
	victim.robbedLog = prune(victim.robbedLog, STEAL.VictimWindow)
	if #victim.robbedLog >= STEAL.VictimLimit then
		return false, "block.limit", nil
	end
	return true, nil, nil
end

local function reject(session: Session, reason: string?, args: { [string]: any }?)
	if reason and Sessions.allowNotice(session, reason, 2.5) then
		Remotes.notify(session.player, reason, args, "warning")
	end
end

local function clearAttack(entity: Entity, thief: Session)
	local plot = PlotService.get(entity.plot)
	if plot and plot.model:GetAttribute("UnderAttack") == thief.userId then
		plot.model:SetAttribute("UnderAttack", 0)
	end
end

local function onHoldBegan(player: Player, entity: Entity)
	local thief = Sessions.ready(player)
	if not thief then
		return
	end
	Sessions.touch(thief)
	local ok, reason, args = StealService.check(thief, entity)
	if not ok then
		reject(thief, reason, args)
		return
	end
	thief.stealHold = { uid = entity.uid, startedAt = now() }
	local victim = Sessions.byUserId(entity.ownerId)
	local plot = PlotService.get(entity.plot)
	if plot then
		plot.model:SetAttribute("UnderAttack", thief.userId)
	end
	Remotes.fx("StealAttempt", { thiefId = thief.userId, uid = entity.uid, duration = Rarities.get(entity.rarity).stealHold })
	if victim then
		Remotes.notify(victim.player, "n.stealAlert", { thief = player.DisplayName, relic = entity.id }, "danger")
	end
end

local function onHoldEnded(player: Player, entity: Entity)
	local thief = Sessions.ready(player)
	if not thief then
		return
	end
	local hold = thief.stealHold
	if hold and hold.uid == entity.uid then
		-- Keep the hold record briefly: Triggered fires right after HoldEnded.
		task.delay(0.3, function()
			if thief.stealHold == hold then
				thief.stealHold = nil
				Remotes.fx("StealCancel", { thiefId = thief.userId, uid = entity.uid })
				clearAttack(entity, thief)
			end
		end)
	end
end

local function onTriggered(player: Player, entity: Entity)
	local thief = Sessions.ready(player)
	if not thief then
		return
	end
	local hold = thief.stealHold
	if not hold or hold.uid ~= entity.uid then
		return
	end
	local required = Rarities.get(entity.rarity).stealHold
	if now() - hold.startedAt < required * 0.8 then
		return
	end
	local ok, reason, args = StealService.check(thief, entity)
	thief.stealHold = nil
	clearAttack(entity, thief)
	if not ok then
		Remotes.fx("StealCancel", { thiefId = thief.userId, uid = entity.uid })
		reject(thief, reason, args)
		return
	end

	local victim = Sessions.byUserId(entity.ownerId) :: Session
	local plot = PlotService.get(entity.plot) :: PlotService.Plot
	local slot = entity.slot :: number

	entity.returnSlot = slot
	entity.stolenAt = now()
	PlotService.setSlot(plot, slot, nil)
	PlotService.reserve(plot, slot, entity.uid)
	RelicService.toCarried(entity, thief.userId, victim.userId)
	CarryService.attach(thief, entity)

	Sessions.setCooldown(thief, "steal", STEAL.Cooldown)
	local pairLog = thief.stealLog[victim.userId] or {}
	table.insert(pairLog, now())
	thief.stealLog[victim.userId] = pairLog
	table.insert(victim.robbedLog, now())
	PlotService.grantAegis(plot, STEAL.AegisDuration)
	EconomyService.recompute(victim)

	Remotes.fx("Stolen", { uid = entity.uid, thiefId = thief.userId, victimId = victim.userId, relicId = entity.id, rarity = entity.rarity })
	Remotes.notify(victim.player, "n.stolen", { thief = player.DisplayName, relic = entity.id }, "danger")
	task.delay(2, function()
		if victim.player.Parent then
			Remotes.notify(victim.player, "n.aegis", { time = STEAL.AegisDuration }, "info")
		end
	end)
end

function StealService.start()
	RelicService.holdBegan:Connect(function(player: Player, entity: Entity, action: string)
		if action == "Steal" then
			onHoldBegan(player, entity)
		end
	end)
	RelicService.holdEnded:Connect(function(player: Player, entity: Entity, action: string)
		if action == "Steal" then
			onHoldEnded(player, entity)
		end
	end)
	RelicService.promptTriggered:Connect(function(player: Player, entity: Entity, action: string)
		if action == "Steal" then
			onTriggered(player, entity)
		end
	end)
end

return StealService
