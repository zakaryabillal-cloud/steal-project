--!strict
-- The Rift spawn loop. Each spawn is a two-step moment:
--   1. "RiftCharge": every client sees the Rift build up (longer and louder
--      for rarer relics; Legendary+ dims the sky server-wide),
--   2. "RelicEmerged": the relic entity appears and clients fly it out of
--      the tear to its spot.
-- Rolls happen here, on the server only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Rarities = require(Shared.Config.Rarities)
local Layout = require(Shared.Layout)

local Core = script.Parent.Parent.Core
local Remotes = require(Core.Remotes)
local Rolls = require(Core.Rolls)
local Scheduler = require(Core.Scheduler)
local RelicService = require(script.Parent.RelicService)
local EventService = require(script.Parent.EventService)

local RiftService = {}

local rng = Random.new()
-- Spots reserved by a charge in progress.
local charging: { [number]: boolean } = {}
local forcedQueue: { Rolls.Roll } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function occupiedSpots(): { [number]: boolean }
	local used: { [number]: boolean } = {}
	for _, entity in RelicService.all() do
		if entity.state == "Rift" and entity.spot then
			used[entity.spot] = true
		end
	end
	for spot in charging do
		used[spot] = true
	end
	return used
end

local function activeCount(): number
	local n = RelicService.count("Rift")
	for _ in charging do
		n += 1
	end
	return n
end

local function chooseSpot(rarity: string): number?
	local used = occupiedSpots()
	if Rarities.isAtLeast(rarity, GameConfig.Rift.ApexRarity) and not used[1] then
		return 1
	end
	local free = {}
	for index, spot in Layout.Spots do
		if index ~= 1 and not used[index] then
			-- Weight the high (island) spots a little lower: they are harder to reach.
			local copies = if spot.kind == "High" then 1 else 2
			for _ = 1, copies do
				table.insert(free, index)
			end
		end
	end
	if #free == 0 then
		return if used[1] then nil else 1
	end
	return free[rng:NextInteger(1, #free)]
end

function RiftService.spawn(roll: Rolls.Roll?)
	local result = roll or Rolls.spawn(rng, EventService.currentId())
	local spot = chooseSpot(result.rarity)
	if not spot then
		return
	end
	local rarity = Rarities.get(result.rarity)
	charging[spot] = true
	local position = Layout.Spots[spot].position
	Remotes.fx("RiftCharge", {
		rarity = result.rarity,
		mutation = result.mutation,
		spot = spot,
		position = position,
		duration = rarity.chargeTime,
	})
	task.delay(rarity.chargeTime, function()
		charging[spot] = nil
		local entity = RelicService.create({ id = result.relicId, mutation = result.mutation, level = 1 }, Layout.RiftCore)
		RelicService.toRift(entity, spot, position, now() + GameConfig.Rift.Lifetime + rarity.order * 5)
		Remotes.fx("RelicEmerged", {
			uid = entity.uid,
			relicId = entity.id,
			rarity = entity.rarity,
			mutation = entity.mutation,
			position = position,
		})
		if rarity.announce == "server" then
			Remotes.notifyAll("n.rareSpawn", { rarity = result.rarity }, "rare")
		end
	end)
end

-- Queue a specific roll for the next spawn (Studio dev commands).
function RiftService.force(roll: Rolls.Roll)
	table.insert(forcedQueue, roll)
end

local function expiryTick()
	local t = now()
	for _, entity in RelicService.all() do
		if entity.state == "Rift" and entity.expiresAt and entity.expiresAt <= t then
			RelicService.vanish(entity, "Faded")
		end
	end
end

function RiftService.start()
	local elapsed = math.huge
	Scheduler.every("Rift.spawn", 0.25, function(dt: number)
		elapsed += dt
		local event = EventService.current()
		local interval = (event and event.spawnInterval) or GameConfig.Rift.SpawnInterval
		local maxActive = (event and event.maxActive) or GameConfig.Rift.MaxActive
		if #forcedQueue > 0 then
			RiftService.spawn(table.remove(forcedQueue, 1))
			elapsed = 0
		elseif elapsed >= interval and activeCount() < maxActive then
			RiftService.spawn(nil)
			elapsed = 0
		end
	end, { delay = GameConfig.Rift.FirstSpawnDelay })
	Scheduler.every("Rift.expiry", 1, expiryTick)
end

return RiftService
