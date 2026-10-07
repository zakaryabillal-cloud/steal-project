--!strict
-- Reads the (replicated) game state and turns it into music conditions.
-- Read-only and cheap: sampled every Settings.SenseInterval, never per frame.
--
--   Boss   : LocalPlayer attributes "MusicBoss" (boss id) + "MusicBossPhase"
--            (number). Reserved for the boss service (phase 6), which sets
--            them server-side while the player takes part in a fight.
--   Chase  : the player carries a stolen relic (thief), one of the player's
--            relics is out of their Sanctuary (victim: carried or dropped
--            while stolen), or a stolen Legendary+ relic is carried within
--            NearbyChaseRadius (bystander). "intense" when Legendary+.
--   Event  : workspace attribute "EventId" (server EventService).
--   Rift   : horizontal distance to the Rift, with enter/exit hysteresis.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Music = require(Shared.Config.Music)
local Rarities = require(Shared.Config.Rarities)
local Layout = require(Shared.Layout)

local MusicSensors = {}
MusicSensors.__index = MusicSensors

export type MusicSensors = typeof(setmetatable({} :: {
	player: Player,
	inRift: boolean,
}, MusicSensors))

function MusicSensors.new(player: Player?): MusicSensors
	return setmetatable({
		player = player or Players.LocalPlayer,
		inRift = false,
	}, MusicSensors)
end

local function attrNumber(instance: Instance, name: string): number
	local value = instance:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

local function attrString(instance: Instance, name: string): string
	local value = instance:GetAttribute(name)
	return if type(value) == "string" then value else ""
end

local function rootPosition(player: Player): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

function MusicSensors.sense(self: MusicSensors): { [string]: { [string]: any } }
	local settings = Music.Settings
	local signals: { [string]: { [string]: any } } = {}
	local player = self.player
	local userId = player.UserId
	local root = rootPosition(player)

	-- Boss (future): set by the server while the player is in a boss fight.
	local boss = attrString(player, "MusicBoss")
	if boss ~= "" then
		signals.Boss = { boss = boss, phase = math.max(1, attrNumber(player, "MusicBossPhase")) }
	end

	-- Chase.
	local chase, intense = false, false
	local folder = workspace:FindFirstChild("Relics")
	if folder then
		for _, anchor in folder:GetChildren() do
			local stolenFrom = attrNumber(anchor, "StolenFrom")
			if stolenFrom == 0 or anchor:GetAttribute("Vanish") ~= nil then
				continue
			end
			local state = attrString(anchor, "State")
			local carrier = attrNumber(anchor, "CarrierId")
			local rarity = attrString(anchor, "Rarity")
			local high = rarity ~= "" and Rarities.isAtLeast(rarity, settings.IntenseRarity)
			if carrier == userId or (stolenFrom == userId and (state == "Carried" or state == "Dropped")) then
				chase = true
				intense = intense or high
			elseif state == "Carried" and root and anchor:IsA("BasePart") and rarity ~= "" and Rarities.isAtLeast(rarity, settings.NearbyChaseRarity) then
				local offset = anchor.Position - root
				if offset.Magnitude <= settings.NearbyChaseRadius then
					chase = true
					intense = true
				end
			end
		end
	end
	if chase then
		signals.Chase = { intense = intense }
	end

	-- World event.
	local event = attrString(workspace, "EventId")
	if event ~= "" then
		signals.Event = { event = event }
	end

	-- Rift proximity with hysteresis.
	if root then
		local core = Layout.RiftCore
		local distance = Vector3.new(root.X - core.X, 0, root.Z - core.Z).Magnitude
		if self.inRift then
			if distance > settings.RiftExitRadius then
				self.inRift = false
			end
		elseif distance < settings.RiftEnterRadius then
			self.inRift = true
		end
	end
	if self.inRift then
		signals.Rift = {}
	end
	return signals
end

return MusicSensors
