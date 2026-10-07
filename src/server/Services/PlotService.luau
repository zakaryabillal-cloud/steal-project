--!strict
-- Owns the 8 Sanctuaries: assignment, pedestal slots, tiers, the seal
-- barrier and the protection state that decides whether a Sanctuary can be
-- robbed. Everything clients need is mirrored as attributes on the model.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Rarities = require(Shared.Config.Rarities)
local Layout = require(Shared.Layout)
local Economy = require(Shared.Economy)
local Signal = require(Shared.Util.Signal)

local Core = script.Parent.Parent.Core
local Types = require(Core.Types)
local Sessions = require(Core.Sessions)
local Remotes = require(Core.Remotes)
local SanctuaryBuilder = require(script.Parent.Parent.World.SanctuaryBuilder)

type Session = Types.Session

export type Plot = {
	index: number,
	model: Model,
	origin: CFrame,
	accent: Color3,
	owner: Session?,
	tier: number,
	-- slot -> relic uid currently displayed
	slots: { [number]: string },
	-- slot -> uid of a stolen relic that may still come home
	reserved: { [number]: string },
	-- slot -> rarity id for pedestal ring colouring
	slotRarity: { [number]: string },
	sealedUntil: number,
	aegisUntil: number,
	pedestals: { [number]: Model },
	walls: { BasePart },
	dome: BasePart,
	spawn: SpawnLocation,
}

local PlotService = {}

local plots: { Plot } = {}
local waiting: { Session } = {}

PlotService.plotFreed = Signal.new()

local function now(): number
	return workspace:GetServerTimeNow()
end

local function resetAttributes(plot: Plot)
	local model = plot.model
	model:SetAttribute("OwnerId", 0)
	model:SetAttribute("OwnerName", "")
	model:SetAttribute("Tier", 1)
	model:SetAttribute("CoreStored", 0)
	model:SetAttribute("CoreCapacity", 0)
	model:SetAttribute("Rate", 0)
	model:SetAttribute("SealedUntil", 0)
	model:SetAttribute("AegisUntil", 0)
	model:SetAttribute("Protection", "")
	model:SetAttribute("ProtectionUntil", 0)
	model:SetAttribute("PlacedCount", 0)
	model:SetAttribute("UnderAttack", 0)
end

function PlotService.init()
	local folder = workspace:WaitForChild("Sanctuaries")
	for index = 1, Layout.PlotCount do
		local model = folder:WaitForChild("Sanctuary" .. index) :: Model
		local pedestals: { [number]: Model } = {}
		local pedestalFolder = model:WaitForChild("Pedestals")
		for slot = 1, #Layout.SlotAngles do
			pedestals[slot] = pedestalFolder:WaitForChild("Pedestal" .. slot) :: Model
		end
		local walls: { BasePart } = {}
		local barrier = model:WaitForChild("Barrier")
		for _, child in barrier:GetChildren() do
			if child:IsA("BasePart") and child.Name == "Wall" then
				table.insert(walls, child)
			end
		end
		local plot: Plot = {
			index = index,
			model = model,
			origin = Layout.plotCFrame(index),
			accent = model:GetAttribute("Accent") :: Color3,
			owner = nil,
			tier = 1,
			slots = {},
			reserved = {},
			slotRarity = {},
			sealedUntil = 0,
			aegisUntil = 0,
			pedestals = pedestals,
			walls = walls,
			dome = barrier:WaitForChild("Dome") :: BasePart,
			spawn = model:WaitForChild("Spawn") :: SpawnLocation,
		}
		plots[index] = plot
		resetAttributes(plot)
	end

	task.spawn(function()
		while true do
			task.wait(0.25)
			PlotService.tick()
		end
	end)
end

function PlotService.get(index: number?): Plot?
	if index == nil then
		return nil
	end
	return plots[index]
end

function PlotService.all(): { Plot }
	return plots
end

function PlotService.of(session: Session): Plot?
	return PlotService.get(session.plot)
end

----------------------------------------------------------------------------
-- Geometry
----------------------------------------------------------------------------

function PlotService.isInside(index: number, position: Vector3): boolean
	local plot = plots[index]
	if not plot then
		return false
	end
	local localPos = plot.origin:PointToObjectSpace(position)
	local horizontal = math.sqrt(localPos.X * localPos.X + localPos.Z * localPos.Z)
	return horizontal <= Layout.PlatformRadius - 0.5 and localPos.Y > -4 and localPos.Y < 40
end

function PlotService.plotAt(position: Vector3): number?
	for index in plots do
		if PlotService.isInside(index, position) then
			return index
		end
	end
	return nil
end

function PlotService.slotPosition(index: number, slot: number): Vector3
	return Layout.relicPosition(index, slot)
end

function PlotService.corePosition(index: number): Vector3
	return plots[index].origin.Position
end

----------------------------------------------------------------------------
-- Pedestals
----------------------------------------------------------------------------

function PlotService.unlockedCount(plot: Plot): number
	local owner = plot.owner
	if not owner then
		return 0
	end
	return Economy.unlockedPedestals(owner.data.upgrades)
end

local function setPedestalState(plot: Plot, slot: number, state: string)
	local pedestal = plot.pedestals[slot]
	if pedestal:GetAttribute("State") == state then
		return
	end
	pedestal:SetAttribute("State", state)
	for _, part in pedestal:GetChildren() do
		if part:IsA("BasePart") then
			local base = (part:GetAttribute("BaseTransparency") :: number?) or 0
			if state == "Active" then
				part.Transparency = base
				part.CanCollide = part.Name ~= "Rune"
			elseif state == "Ghost" then
				part.Transparency = if part.Name == "Ring" then 0.55 else 0.86
				part.CanCollide = false
			else
				part.Transparency = 1
				part.CanCollide = false
			end
		end
	end
end

local function colorRing(plot: Plot, slot: number)
	local ring = plot.pedestals[slot]:FindFirstChild("Ring") :: BasePart?
	if not ring then
		return
	end
	local rarity = plot.slotRarity[slot]
	ring.Color = if rarity then Rarities.get(rarity).color else plot.accent
end

function PlotService.refreshPedestals(plot: Plot)
	local unlocked = PlotService.unlockedCount(plot)
	local tierMax = if plot.owner then Economy.tierMaxPedestals(plot.tier) else 0
	for slot = 1, #Layout.SlotAngles do
		local state = "Hidden"
		if slot <= unlocked then
			state = "Active"
		elseif slot <= tierMax and slot == unlocked + 1 then
			-- Tease the next purchasable pedestal.
			state = "Ghost"
		end
		setPedestalState(plot, slot, state)
		colorRing(plot, slot)
	end
end

function PlotService.freeSlot(plot: Plot): number?
	local unlocked = PlotService.unlockedCount(plot)
	for slot = 1, unlocked do
		if plot.slots[slot] == nil and plot.reserved[slot] == nil then
			return slot
		end
	end
	return nil
end

function PlotService.setSlot(plot: Plot, slot: number, uid: string?, rarity: string?)
	if uid then
		plot.slots[slot] = uid
		plot.slotRarity[slot] = rarity or "Common"
	else
		plot.slots[slot] = nil
		plot.slotRarity[slot] = nil
	end
	colorRing(plot, slot)
	local count = 0
	for _ in plot.slots do
		count += 1
	end
	plot.model:SetAttribute("PlacedCount", count)
end

function PlotService.reserve(plot: Plot, slot: number, uid: string?)
	if uid then
		plot.reserved[slot] = uid
	else
		plot.reserved[slot] = nil
	end
end

function PlotService.placedCount(plot: Plot): number
	local count = 0
	for _ in plot.slots do
		count += 1
	end
	return count
end

----------------------------------------------------------------------------
-- Ownership
----------------------------------------------------------------------------

function PlotService.setTier(plot: Plot, tier: number)
	plot.tier = tier
	SanctuaryBuilder.setTier(plot.model, tier)
	PlotService.refreshPedestals(plot)
end

local function applyOwner(plot: Plot, session: Session)
	plot.owner = session
	session.plot = plot.index
	local model = plot.model
	model:SetAttribute("OwnerId", session.userId)
	model:SetAttribute("OwnerName", session.player.DisplayName)
	session.player.RespawnLocation = plot.spawn
	PlotService.setTier(plot, Economy.tier(session.data.upgrades))
end

-- Returns the plot index, or nil (player is queued until one frees up).
function PlotService.assign(session: Session): number?
	for _, plot in plots do
		if plot.owner == nil then
			applyOwner(plot, session)
			return plot.index
		end
	end
	table.insert(waiting, session)
	return nil
end

function PlotService.release(session: Session)
	local index = table.find(waiting, session)
	if index then
		table.remove(waiting, index)
	end
	local plot = PlotService.get(session.plot)
	if not plot or plot.owner ~= session then
		return
	end
	plot.owner = nil
	table.clear(plot.slots)
	table.clear(plot.reserved)
	table.clear(plot.slotRarity)
	plot.sealedUntil = 0
	plot.aegisUntil = 0
	for _, wall in plot.walls do
		wall.CanCollide = false
		wall.Transparency = 1
	end
	plot.dome.Transparency = 1
	SanctuaryBuilder.setTier(plot.model, 1)
	plot.tier = 1
	resetAttributes(plot)
	PlotService.refreshPedestals(plot)
	session.plot = nil

	-- Hand the plot to the next player in the queue.
	local nextSession = table.remove(waiting, 1)
	while nextSession and (nextSession.released or nextSession.player.Parent == nil) do
		nextSession = table.remove(waiting, 1)
	end
	if nextSession then
		applyOwner(plot, nextSession)
		PlotService.plotFreed:Fire(nextSession, plot.index)
	end
end

----------------------------------------------------------------------------
-- Protection & seal
----------------------------------------------------------------------------

-- Why this Sanctuary cannot be robbed right now, if any.
-- Returns (kind, untilTime?) with kind in Sealed | Aegis | Novice | Resting | LastRelics.
function PlotService.protection(plot: Plot): (string?, number?)
	local owner = plot.owner
	if not owner then
		return "Empty", nil
	end
	local t = now()
	if plot.sealedUntil > t then
		return "Sealed", plot.sealedUntil
	end
	if plot.aegisUntil > t then
		return "Aegis", plot.aegisUntil
	end
	local playTime = Sessions.playTime(owner)
	if playTime < GameConfig.Steal.NoviceSeconds then
		return "Novice", t + (GameConfig.Steal.NoviceSeconds - playTime)
	end
	if t - owner.lastActivity > GameConfig.Steal.AfkSeconds then
		return "Resting", nil
	end
	if PlotService.placedCount(plot) < GameConfig.Steal.MinPlacedToBeRobbed then
		return "LastRelics", nil
	end
	return nil, nil
end

function PlotService.grantAegis(plot: Plot, duration: number)
	plot.aegisUntil = math.max(plot.aegisUntil, now() + duration)
	plot.model:SetAttribute("AegisUntil", plot.aegisUntil)
end

local function setBarrier(plot: Plot, on: boolean)
	for _, wall in plot.walls do
		wall.CanCollide = on
		wall.Transparency = if on then 0.55 else 1
	end
	plot.dome.Transparency = if on then 0.82 else 1
end

-- Moves every non-owner standing inside the Sanctuary out past the gate.
local function ejectIntruders(plot: Plot)
	local owner = plot.owner
	for _, player in Players:GetPlayers() do
		if owner and player == owner.player then
			continue
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if character and root and root:IsA("BasePart") and PlotService.isInside(plot.index, root.Position) then
			local session = Sessions.get(player)
			if session then
				session.teleportGraceUntil = now() + 2
			end
			local lateral = (math.random() - 0.5) * 10
			character:PivotTo(plot.origin * CFrame.new(lateral, -Layout.PlatformHeight + 3.5, -(Layout.PlatformRadius + Layout.RampLength + 6)) * CFrame.Angles(0, math.pi, 0))
		end
	end
end

function PlotService.seal(session: Session): (boolean, string?)
	local plot = PlotService.of(session)
	if not plot then
		return false, "noPlot"
	end
	if not Sessions.cooldownReady(session, "seal") then
		return false, "cooldown"
	end
	local duration = GameConfig.Sanctuary.SealDuration[plot.tier] or GameConfig.Sanctuary.SealDuration[1]
	plot.sealedUntil = now() + duration
	plot.model:SetAttribute("SealedUntil", plot.sealedUntil)
	Sessions.setCooldown(session, "seal", GameConfig.Sanctuary.SealCooldown)
	setBarrier(plot, true)
	ejectIntruders(plot)
	Remotes.fx("Seal", { plot = plot.index, untilTime = plot.sealedUntil })
	return true, nil
end

function PlotService.tick()
	local t = now()
	for _, plot in plots do
		if plot.sealedUntil > 0 and plot.sealedUntil <= t then
			plot.sealedUntil = 0
			plot.model:SetAttribute("SealedUntil", 0)
			setBarrier(plot, false)
			Remotes.fx("Unseal", { plot = plot.index })
		end
		local kind, untilTime = PlotService.protection(plot)
		local model = plot.model
		local label = if kind == "Empty" or kind == nil then "" else kind
		if model:GetAttribute("Protection") ~= label then
			model:SetAttribute("Protection", label)
		end
		local untilValue = untilTime or 0
		local current = model:GetAttribute("ProtectionUntil") :: number?
		if current == nil or math.abs(current - untilValue) > 0.5 then
			model:SetAttribute("ProtectionUntil", untilValue)
		end
	end
end

return PlotService
