--!strict
-- Character lifecycle: spawning at the owner's Sanctuary, respawn timing,
-- walk speed (upgrades, carry weight, stuns), collision groups for the seal
-- barrier, and the void kill plane.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Economy = require(Shared.Economy)
local Layout = require(Shared.Layout)
local Signal = require(Shared.Util.Signal)

local Core = script.Parent.Parent.Core
local Types = require(Core.Types)
local Sessions = require(Core.Sessions)
local RelicService = require(script.Parent.RelicService)

type Session = Types.Session

local CharacterService = {}

-- (session, lastPosition: Vector3?)
CharacterService.died = Signal.new()

local function now(): number
	return workspace:GetServerTimeNow()
end

local function groupFor(session: Session): string
	return if session.plot then "Owner" .. session.plot else "Default"
end

function CharacterService.refreshCollision(session: Session)
	local character = session.player.Character
	if not character then
		return
	end
	local group = groupFor(session)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = group
		end
	end
end

function CharacterService.refreshSpeed(session: Session)
	local _, humanoid = Sessions.character(session)
	if not humanoid then
		return
	end
	if now() < session.stunnedUntil then
		humanoid.WalkSpeed = 0
		humanoid.JumpHeight = 0
		return
	end
	local ids = {}
	for _, uid in session.carrying do
		local entity = RelicService.get(uid)
		if entity then
			table.insert(ids, entity.id)
		end
	end
	humanoid.WalkSpeed = Economy.walkSpeed(session.data.upgrades.stride) * Economy.carrySpeedMultiplier(ids)
	humanoid.JumpHeight = GameConfig.Player.JumpHeight
end

function CharacterService.stun(session: Session, duration: number)
	session.stunnedUntil = math.max(session.stunnedUntil, now() + duration)
	session.stealHold = nil
	CharacterService.refreshSpeed(session)
	task.delay(duration + 0.05, function()
		if now() >= session.stunnedUntil then
			CharacterService.refreshSpeed(session)
		end
	end)
end

function CharacterService.spawn(session: Session)
	task.spawn(function()
		if session.player.Parent then
			session.player:LoadCharacterAsync()
		end
	end)
end

function CharacterService.onCharacter(session: Session, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	CharacterService.refreshCollision(session)
	character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = groupFor(session)
		end
	end)
	session.spawnProtectedUntil = now() + GameConfig.Player.SpawnProtection
	session.teleportGraceUntil = now() + 3
	session.stunnedUntil = 0
	session.lastPosition = nil
	CharacterService.refreshSpeed(session)

	if session.plot == nil then
		-- No Sanctuary yet: wait near the Rift instead of inside someone's base.
		task.defer(function()
			if character.Parent then
				character:PivotTo(CFrame.new(0, Layout.GroundY + 4, -Layout.RimRadius - 6))
			end
		end)
	end

	local player = session.player
	humanoid.Died:Connect(function()
		local root = character:FindFirstChild("HumanoidRootPart")
		local position = if root and root:IsA("BasePart") then root.Position else nil
		CharacterService.died:Fire(session, position)
		task.delay(GameConfig.Player.RespawnDelay, function()
			if player.Parent and Sessions.get(player) == session and not session.released then
				player:LoadCharacterAsync()
			end
		end)
	end)
end

function CharacterService.isProtected(session: Session): boolean
	return now() < session.spawnProtectedUntil
end

function CharacterService.start()
	task.spawn(function()
		while true do
			task.wait(0.3)
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 and root.Position.Y < GameConfig.Player.VoidKillY then
					humanoid.Health = 0
				end
			end
		end
	end)
end

return CharacterService
