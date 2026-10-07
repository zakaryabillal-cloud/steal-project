--!strict
-- Registry of every relic entity in the world. An entity is an invisible
-- anchored "anchor" part in workspace.Relics whose attributes describe the
-- relic (id, level, mutation, state...). Clients render the visual model from
-- those attributes; the server only moves anchors and swaps prompts.
--
-- States:
--   Rift    floating at a Rift spawn spot, claimable
--   Carried following a player (CarrierId), possibly stolen (StolenFrom)
--   Placed  on a Sanctuary pedestal (OwnerId, Plot, Slot)
--   Dropped knocked loose in the world, grabbable for a short time

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Relics = require(Shared.Config.Relics)
local Rarities = require(Shared.Config.Rarities)
local Signal = require(Shared.Util.Signal)

export type Entity = {
	uid: string,
	id: string,
	rarity: string,
	level: number,
	mutation: string?,
	state: string,
	anchor: Part,
	ownerId: number?,
	carrierId: number?,
	stolenFrom: number?,
	stolenAt: number?,
	returnSlot: number?,
	plot: number?,
	slot: number?,
	spot: number?,
	expiresAt: number?,
	alive: boolean,
}

local RelicService = {}

local entities: { [string]: Entity } = {}
local folder: Instance

-- (player, entity, action)
RelicService.promptTriggered = Signal.new()
RelicService.holdBegan = Signal.new()
RelicService.holdEnded = Signal.new()

local PROMPT_DISTANCE = {
	Claim = 11,
	Grab = 11,
	Steal = 9,
	Inspect = 10,
}

function RelicService.init()
	folder = workspace:WaitForChild("Relics")
end

local function newUid(): string
	local guid = string.gsub(HttpService:GenerateGUID(false), "-", "")
	return string.lower(string.sub(guid, 1, 16))
end

local function clearPrompts(entity: Entity)
	for _, child in entity.anchor:GetChildren() do
		if child:IsA("ProximityPrompt") then
			child:Destroy()
		end
	end
end

local function addPrompt(entity: Entity, action: string, hold: number)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = action
	prompt:SetAttribute("Action", action)
	prompt.ActionText = action
	prompt.ObjectText = entity.id
	prompt.HoldDuration = hold
	prompt.MaxActivationDistance = PROMPT_DISTANCE[action] or 10
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.ClickablePrompt = true
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt.Triggered:Connect(function(player: Player)
		if entity.alive then
			RelicService.promptTriggered:Fire(player, entity, action)
		end
	end)
	prompt.PromptButtonHoldBegan:Connect(function(player: Player)
		if entity.alive then
			RelicService.holdBegan:Fire(player, entity, action)
		end
	end)
	prompt.PromptButtonHoldEnded:Connect(function(player: Player)
		if entity.alive then
			RelicService.holdEnded:Fire(player, entity, action)
		end
	end)
	prompt.Parent = entity.anchor
end

local function writeAttributes(entity: Entity)
	local anchor = entity.anchor
	anchor:SetAttribute("State", entity.state)
	anchor:SetAttribute("Level", entity.level)
	anchor:SetAttribute("OwnerId", entity.ownerId or 0)
	anchor:SetAttribute("CarrierId", entity.carrierId or 0)
	anchor:SetAttribute("StolenFrom", entity.stolenFrom or 0)
	anchor:SetAttribute("StolenAt", entity.stolenAt or 0)
	anchor:SetAttribute("Plot", entity.plot or 0)
	anchor:SetAttribute("Slot", entity.slot or 0)
	anchor:SetAttribute("Spot", entity.spot or 0)
	anchor:SetAttribute("ExpiresAt", entity.expiresAt or 0)
end

local function refreshPrompts(entity: Entity)
	clearPrompts(entity)
	local state = entity.state
	if state == "Rift" then
		addPrompt(entity, "Claim", 0)
	elseif state == "Dropped" then
		addPrompt(entity, "Grab", 0.2)
	elseif state == "Placed" then
		addPrompt(entity, "Steal", Rarities.get(entity.rarity).stealHold)
		addPrompt(entity, "Inspect", 0)
	end
end

export type CreateSpec = {
	id: string,
	level: number?,
	mutation: string?,
	uid: string?,
}

function RelicService.create(spec: CreateSpec, position: Vector3): Entity
	local def = Relics.get(spec.id)
	assert(def, "Unknown relic " .. tostring(spec.id))
	local uid = spec.uid or newUid()
	while entities[uid] do
		uid = newUid()
	end

	local anchor = Instance.new("Part")
	anchor.Name = uid
	anchor.Size = Vector3.new(3, 3, 3)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Locked = true
	anchor.CFrame = CFrame.new(position)
	anchor:SetAttribute("Uid", uid)
	anchor:SetAttribute("RelicId", def.id)
	anchor:SetAttribute("Rarity", def.rarity)
	anchor:SetAttribute("Mutation", spec.mutation or "")
	anchor:SetAttribute("SpawnedAt", workspace:GetServerTimeNow())

	local entity: Entity = {
		uid = uid,
		id = def.id,
		rarity = def.rarity,
		level = spec.level or 1,
		mutation = if spec.mutation == "" then nil else spec.mutation,
		state = "None",
		anchor = anchor,
		ownerId = nil,
		carrierId = nil,
		stolenFrom = nil,
		stolenAt = nil,
		returnSlot = nil,
		plot = nil,
		slot = nil,
		spot = nil,
		expiresAt = nil,
		alive = true,
	}
	entities[uid] = entity
	writeAttributes(entity)
	return entity
end

-- Attributes and prompts are written after the anchor is parented so clients
-- always see a complete entity in one ChildAdded.
local function publish(entity: Entity)
	writeAttributes(entity)
	refreshPrompts(entity)
	if entity.anchor.Parent ~= folder then
		entity.anchor.Parent = folder
	end
end

function RelicService.toRift(entity: Entity, spot: number, position: Vector3, expiresAt: number)
	entity.state = "Rift"
	entity.ownerId, entity.carrierId, entity.stolenFrom, entity.stolenAt = nil, nil, nil, nil
	entity.plot, entity.slot, entity.returnSlot = nil, nil, nil
	entity.spot = spot
	entity.expiresAt = expiresAt
	entity.anchor.CFrame = CFrame.new(position)
	publish(entity)
end

function RelicService.toCarried(entity: Entity, carrierId: number, stolenFrom: number?)
	entity.state = "Carried"
	entity.carrierId = carrierId
	entity.stolenFrom = stolenFrom
	if stolenFrom == nil then
		entity.stolenAt = nil
		entity.returnSlot = nil
		entity.ownerId = nil
	end
	entity.plot, entity.slot, entity.spot = nil, nil, nil
	entity.expiresAt = nil
	publish(entity)
end

function RelicService.toPlaced(entity: Entity, ownerId: number, plot: number, slot: number, position: Vector3)
	entity.state = "Placed"
	entity.ownerId = ownerId
	entity.carrierId, entity.stolenFrom, entity.stolenAt, entity.returnSlot = nil, nil, nil, nil
	entity.plot = plot
	entity.slot = slot
	entity.spot = nil
	entity.expiresAt = nil
	entity.anchor.CFrame = CFrame.new(position)
	publish(entity)
end

function RelicService.toDropped(entity: Entity, position: Vector3, expiresAt: number)
	entity.state = "Dropped"
	entity.carrierId = nil
	entity.plot, entity.slot, entity.spot = nil, nil, nil
	entity.expiresAt = expiresAt
	entity.anchor.CFrame = CFrame.new(position)
	publish(entity)
end

function RelicService.setLevel(entity: Entity, level: number)
	entity.level = level
	entity.anchor:SetAttribute("Level", level)
end

function RelicService.moveAnchor(entity: Entity, position: Vector3)
	entity.anchor.CFrame = CFrame.new(position)
end

-- Removes an entity. `reason` is shown by clients as a dissolve animation:
-- "Faded" | "Leave" | "Fused" | "Dissolved" | "Void".
function RelicService.vanish(entity: Entity, reason: string)
	if not entity.alive then
		return
	end
	entity.alive = false
	entities[entity.uid] = nil
	clearPrompts(entity)
	local anchor = entity.anchor
	anchor:SetAttribute("Vanish", reason)
	task.delay(1.2, function()
		anchor:Destroy()
	end)
end

function RelicService.get(uid: string?): Entity?
	if uid == nil then
		return nil
	end
	return entities[uid]
end

function RelicService.all(): { [string]: Entity }
	return entities
end

function RelicService.count(state: string): number
	local n = 0
	for _, entity in entities do
		if entity.state == state then
			n += 1
		end
	end
	return n
end

function RelicService.placedBy(userId: number): { Entity }
	local list = {}
	for _, entity in entities do
		if entity.state == "Placed" and entity.ownerId == userId then
			table.insert(list, entity)
		end
	end
	return list
end

return RelicService
