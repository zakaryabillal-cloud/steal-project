--!strict
-- Lightweight server-side movement sanity check and activity tracking.
-- Character physics are client-owned on Roblox, so instead of fighting every
-- movement we target the exploit that matters: teleporting with relics.
-- Impossible horizontal speeds drop carried relics; blatant teleports are
-- pulled back. Normal movement (dash, knockback, bounce pads) stays well
-- under the threshold.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local Core = script.Parent.Parent.Core
local Sessions = require(Core.Sessions)
local Scheduler = require(Core.Scheduler)
local CarryService = require(script.Parent.CarryService)

local MovementGuard = {}

local SECURITY = GameConfig.Security

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
				if speed > SECURITY.MaxHorizontalSpeed then
					if #session.carrying > 0 then
						CarryService.dropAll(session, previous)
					end
					if speed > SECURITY.MaxHorizontalSpeed * 2.5 then
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
