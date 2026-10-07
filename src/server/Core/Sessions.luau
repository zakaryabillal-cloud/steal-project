--!strict
-- Registry of connected players and their runtime state. Services never keep
-- their own per-player tables keyed by Player; they hang state off Session.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Status = require(ReplicatedStorage.Shared.Status)
local Types = require(script.Parent.Types)

type Session = Types.Session

local Sessions = {}

local byPlayer: { [Player]: Session } = {}
local byUserId: { [number]: Session } = {}

Sessions.added = Signal.new()
Sessions.removing = Signal.new()

function Sessions.create(player: Player, data: Types.SaveData): Session
	local now = workspace:GetServerTimeNow()
	local session: Session = {
		player = player,
		userId = player.UserId,
		data = data,
		loaded = false,
		canSave = false,
		dataStatus = "pending",
		plot = nil,
		carrying = {},
		cooldowns = {},
		stunnedUntil = 0,
		steadyUntil = 0,
		spawnProtectedUntil = 0,
		teleportGraceUntil = 0,
		lastActivity = now,
		lastPosition = nil,
		joinedAt = now,
		stealHold = nil,
		stealLog = {},
		robbedLog = {},
		rate = 0,
		multiplier = 1,
		power = 0,
		status = Status.new(),
		dirty = true,
		coldDirty = true,
		lastCold = nil,
		saving = false,
		released = false,
		lastNotice = {},
		leaderstats = nil,
	}
	byPlayer[player] = session
	byUserId[player.UserId] = session
	return session
end

function Sessions.get(player: Player): Session?
	return byPlayer[player]
end

-- Only returns sessions whose data finished loading.
function Sessions.ready(player: Player): Session?
	local session = byPlayer[player]
	if session and session.loaded and not session.released then
		return session
	end
	return nil
end

function Sessions.byUserId(userId: number?): Session?
	if userId == nil then
		return nil
	end
	local session = byUserId[userId]
	if session and session.loaded and not session.released then
		return session
	end
	return nil
end

function Sessions.all(): { Session }
	local list = {}
	for _, session in byPlayer do
		if session.loaded and not session.released then
			table.insert(list, session)
		end
	end
	return list
end

function Sessions.remove(player: Player)
	local session = byPlayer[player]
	if session then
		byPlayer[player] = nil
		if byUserId[session.userId] == session then
			byUserId[session.userId] = nil
		end
	end
end

-- Hot state changed (Essence, carrying, cooldowns, status, Power...).
function Sessions.markDirty(session: Session)
	session.dirty = true
end

-- Cold state changed (Dex, upgrades, loadout, settings, tutorial, stats...).
-- Cold state is only sent when marked (plus a periodic audit, see Snapshot).
function Sessions.markCold(session: Session)
	session.coldDirty = true
	session.dirty = true
end

function Sessions.touch(session: Session)
	session.lastActivity = workspace:GetServerTimeNow()
end

function Sessions.character(session: Session): (Model?, Humanoid?, BasePart?)
	local character = session.player.Character
	if not character then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, humanoid, root
end

function Sessions.rootPosition(session: Session): Vector3?
	local _, _, root = Sessions.character(session)
	return if root then root.Position else nil
end

-- Server time at which an ability/action is ready again.
function Sessions.cooldownReady(session: Session, key: string): boolean
	return workspace:GetServerTimeNow() >= (session.cooldowns[key] or 0)
end

function Sessions.setCooldown(session: Session, key: string, seconds: number)
	session.cooldowns[key] = workspace:GetServerTimeNow() + seconds
	session.dirty = true
end

-- Throttles a repeated notice so the same message isn't spammed.
function Sessions.allowNotice(session: Session, key: string, interval: number): boolean
	local now = os.clock()
	local last = session.lastNotice[key]
	if last and now - last < interval then
		return false
	end
	session.lastNotice[key] = now
	return true
end

function Sessions.playTime(session: Session): number
	return session.data.playTime + (workspace:GetServerTimeNow() - session.joinedAt)
end

return Sessions
