--!strict
-- Server-wide Rift events. State is mirrored on workspace attributes
-- (EventId, EventEndsAt, NextEventAt) so late joiners sync instantly.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Events = require(Shared.Config.Events)

local Remotes = require(script.Parent.Parent.Core.Remotes)
local Scheduler = require(script.Parent.Parent.Core.Scheduler)

local EventService = {}

local current: Events.EventDef? = nil
local endsAt = 0
local rng = Random.new()

local function now(): number
	return workspace:GetServerTimeNow()
end

function EventService.current(): Events.EventDef?
	if current and now() < endsAt then
		return current
	end
	return nil
end

function EventService.currentId(): string?
	local event = EventService.current()
	return if event then event.id else nil
end

local function pick(): Events.EventDef
	local total = 0
	for _, def in Events.list do
		total += def.weight
	end
	local roll = rng:NextNumber() * total
	for _, def in Events.list do
		roll -= def.weight
		if roll <= 0 then
			return def
		end
	end
	return Events.list[1]
end

local function begin(def: Events.EventDef)
	current = def
	endsAt = now() + def.duration
	workspace:SetAttribute("EventId", def.id)
	workspace:SetAttribute("EventEndsAt", endsAt)
	Remotes.fx("EventStart", { id = def.id, endsAt = endsAt })
end

local function finish()
	local def = current
	current = nil
	endsAt = 0
	workspace:SetAttribute("EventId", "")
	workspace:SetAttribute("EventEndsAt", 0)
	if def then
		Remotes.fx("EventEnd", { id = def.id })
	end
end

-- Starts an event immediately (used by the scheduler and Studio dev commands).
function EventService.trigger(id: string?): boolean
	local def = if id then Events.get(id) else pick()
	if not def then
		return false
	end
	if current then
		finish()
	end
	begin(def)
	return true
end

function EventService.start()
	workspace:SetAttribute("EventId", "")
	workspace:SetAttribute("EventEndsAt", 0)
	local nextAt = now() + GameConfig.Events.FirstDelay
	workspace:SetAttribute("NextEventAt", nextAt)
	Scheduler.every("Events.tick", 1, function()
		if current then
			if now() >= endsAt then
				finish()
				nextAt = now() + rng:NextNumber(GameConfig.Events.IntervalMin, GameConfig.Events.IntervalMax)
				workspace:SetAttribute("NextEventAt", nextAt)
			end
		elseif now() >= nextAt then
			begin(pick())
		end
	end)
end

return EventService
