--!strict
-- Remote definitions. The server creates every remote once in
-- ReplicatedStorage.Remotes; clients look them up by name. Using these
-- constants instead of string literals keeps both sides in sync.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

Net.Events = table.freeze({
	-- Server -> client
	Sync = "Sync", -- private player state: hot fields always, cold fields when changed
	Notify = "Notify", -- toast: (key, args, style)
	FX = "FX", -- broadcast visual moment: (kind, payload)
	Knockback = "Knockback", -- (impulse: Vector3, stun: number)
	-- Client -> server
	ClientReady = "ClientReady",
	UseAbility = "UseAbility", -- (abilityId, payload?) equipped abilities; payload = direction or anchor index
	-- V1 aliases of UseAbility("dash") / UseAbility("pulse"), kept for compatibility.
	Dash = "Dash",
	Pulse = "Pulse",
	Seal = "Seal",
	Settings = "Settings",
	DissolveCarried = "DissolveCarried",
	TutorialSeen = "TutorialSeen",
}) :: { [string]: string }

Net.Functions = table.freeze({
	Purchase = "Purchase", -- (upgradeId) -> (ok, reason)
	Dissolve = "Dissolve", -- (relicUid) -> (ok, reason)
	SetLoadout = "SetLoadout", -- (slotIndex, abilityId) -> (ok, reason)
	UnlockAbility = "UnlockAbility", -- (abilityId) -> (ok, reason)
	SetHarmony = "SetHarmony", -- (relicId, enabled) -> (ok, reason)
	EquipCosmetic = "EquipCosmetic", -- (category, cosmeticId | "") -> (ok, reason)
}) :: { [string]: string }

local FOLDER_NAME = "Remotes"

function Net.setupServer(): Folder
	assert(RunService:IsServer(), "Net.setupServer is server-only")
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	for _, name in Net.Events do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
	for _, name in Net.Functions do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = folder
		end
	end
	return folder :: Folder
end

local function folder(): Instance
	return ReplicatedStorage:WaitForChild(FOLDER_NAME)
end

function Net.event(name: string): RemoteEvent
	return folder():WaitForChild(name) :: RemoteEvent
end

function Net.func(name: string): RemoteFunction
	return folder():WaitForChild(name) :: RemoteFunction
end

return Net
