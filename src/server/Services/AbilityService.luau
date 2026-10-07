--!strict
-- Movement and interaction abilities (validated server-side):
--   Dash  - short burst, applied locally by the client for responsiveness;
--           the server owns the cooldown and broadcasts the trail.
--   Pulse - shockwave: knocks nearby players back, dazes them briefly and
--           makes them drop every relic they carry. Steady immunity after a
--           hit prevents stun-locking.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Net = require(Shared.Net)

local Core = script.Parent.Parent.Core
local Sessions = require(Core.Sessions)
local Remotes = require(Core.Remotes)
local CharacterService = require(script.Parent.CharacterService)
local CarryService = require(script.Parent.CarryService)
local PlotService = require(script.Parent.PlotService)

local AbilityService = {}

local DASH = GameConfig.Abilities.Dash
local PULSE = GameConfig.Abilities.Pulse

local function now(): number
	return workspace:GetServerTimeNow()
end

local function onDash(player: Player)
	local session = Sessions.ready(player)
	if not session then
		return
	end
	local _, _, root = Sessions.character(session)
	if not root or now() < session.stunnedUntil or not Sessions.cooldownReady(session, "dash") then
		return
	end
	Sessions.setCooldown(session, "dash", DASH.Cooldown * 0.9)
	Sessions.touch(session)
	session.teleportGraceUntil = math.max(session.teleportGraceUntil, now() + 0.6)
	Remotes.fx("Dash", { userId = session.userId })
end

local function onPulse(player: Player)
	local session = Sessions.ready(player)
	if not session then
		return
	end
	local _, _, root = Sessions.character(session)
	if not root or now() < session.stunnedUntil or not Sessions.cooldownReady(session, "pulse") then
		return
	end
	Sessions.setCooldown(session, "pulse", PULSE.Cooldown)
	Sessions.touch(session)
	local origin = root.Position
	Remotes.fx("Pulse", { userId = session.userId, position = origin })

	for _, target in Sessions.all() do
		if target == session then
			continue
		end
		local _, _, targetRoot = Sessions.character(target)
		if not targetRoot then
			continue
		end
		local offset = targetRoot.Position - origin
		if offset.Magnitude > PULSE.Radius then
			continue
		end
		if now() < target.steadyUntil or CharacterService.isProtected(target) then
			continue
		end
		local flat = Vector3.new(offset.X, 0, offset.Z)
		local direction = if flat.Magnitude > 0.1 then flat.Unit else root.CFrame.LookVector
		target.steadyUntil = now() + PULSE.SteadyTime
		target.teleportGraceUntil = now() + 1.2
		CharacterService.stun(target, PULSE.Stun)
		Remotes.knockback(target.player, direction * PULSE.Knockback + Vector3.new(0, PULSE.Lift, 0), PULSE.Stun)
		Remotes.fx("Hit", { userId = target.userId, by = session.userId })
		if #target.carrying > 0 then
			-- Relics are safe once their carrier is inside their own Sanctuary.
			local safe = target.plot ~= nil and PlotService.isInside(target.plot, targetRoot.Position)
			if not safe then
				CarryService.dropAll(target, targetRoot.Position)
				Remotes.notify(target.player, "n.dropped", nil, "danger")
				Remotes.notify(player, "n.knockedDrop", { thief = target.player.DisplayName }, "success")
			end
		end
	end
end

local function onSeal(player: Player)
	local session = Sessions.ready(player)
	if not session then
		return
	end
	Sessions.touch(session)
	local ok, reason = PlotService.seal(session)
	if ok then
		Remotes.notify(player, "n.sealed", nil, "success")
	elseif reason == "cooldown" then
		Remotes.notify(player, "n.sealCooldown", { time = (session.cooldowns.seal or 0) - now() }, "warning")
	end
end

function AbilityService.start()
	Remotes.on(Net.Events.Dash, { rate = 2, burst = 3 }, onDash)
	Remotes.on(Net.Events.Pulse, { rate = 1, burst = 2 }, onPulse)
	Remotes.on(Net.Events.Seal, { rate = 1, burst = 2 }, onSeal)
end

return AbilityService
