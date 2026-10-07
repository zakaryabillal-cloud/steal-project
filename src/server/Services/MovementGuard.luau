--!strict
-- Lightweight server-side movement sanity check and activity tracking.
-- Character physics are client-owned on Roblox, so instead of fighting every
-- movement we target the exploit that matters: teleporting with relics.
-- Impossible horizontal speeds drop carried relics; blatant teleports are
-- pulled back. Normal movement (dash, grapple, knockback, bounce pads) stays
-- under the threshold.
--
-- Abilities never switch the guard off:
--   * MovementGuard.allow raises the threshold for a short time (Dash);
--   * MovementGuard.teleported records a server-made move (Blink) so it is
--     not mistaken for a client teleport.
-- Only server-made moves (spawn, knockback, seal ejection) use the full
-- grace window (session.teleportGraceUntil).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local Core = script.Parent.Parent.Core
local Types = require(Core.Types)
local Sessions = require(Core.Sessions)
local Scheduler = require(Core.Scheduler)
local CarryService = require(script.Parent.CarryService)

local MovementGuard = {}

local SECURITY = GameConfig.Security

-- Raises the speed threshold to `speed` studs/s for `duration` seconds.
function MovementGuard.allow(session: Types.Session, speed: number, duration: number)
	local untilTime = workspace:GetServerTimeNow() + duration
	local current = session.moveAllowance
	if current and current.untilTime > workspace:GetServerTimeNow() then
		session.moveAllowance = { speed = math.max(current.speed, speed), untilTime = math.max(current.untilTime, untilTime) }
	else
		session.moveAllowance = { speed = speed, untilTime = untilTime }
	end
end

-- The server itself moved the character to `position` (e.g. Blink).
function MovementGuard.teleported(session: Types.Session, position: Vector3)
	session.lastPosition = position
end

-- Speed threshold for `session` right now.
function MovementGuard.threshold(session: Types.Session, serverNow: number): number
	local allowance = session.moveAllowance
	if allowance and serverNow < allowance.untilTime then
		return math.max(SECURITY.MaxHorizontalSpeed, allowance.speed)
	end
	return SECURITY.MaxHorizontalSpeed
end

function MovementGuard.start()
	Scheduler.every("Movement.guard", SECURITY.MovementCheckInterval, function(elapsed: number)
		local dt = math.max(elapsed, 0.05)
		local serverNow = workspace:GetServerTimeNow()
		for _, session in Sessions.all() do
			local _, _, root = Sessions.character(session)
			if not root then
				session.lastPosition = nil
				continue
			end
			local position = root.Position
			local previous = session.lastPosition
			if previous and serverNow > session.teleportGraceUntil then
				local flat = Vector3.new(position.X - previous.X, 0, position.Z - previous.Z).Magnitude
				local speed = flat / dt
				local threshold = MovementGuard.threshold(session, serverNow)
				if speed > threshold then
					if #session.carrying > 0 then
						CarryService.dropAll(session, previous)
					end
					if speed > threshold * 2.5 then
						warn(string.format("[MovementGuard] %s moved %.0f studs/s; pulled back", session.player.Name, speed))
						root.CFrame = CFrame.new(previous + Vector3.new(0, 2, 0))
						session.teleportGraceUntil = serverNow + 1
						continue
					end
				end
				if flat > 1.5 then
					session.lastActivity = serverNow
				end
			end
			session.lastPosition = position
		end
	end)
end

return MovementGuard
