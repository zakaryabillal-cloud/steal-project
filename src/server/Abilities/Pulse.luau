--!strict
-- Pulse (Control): shockwave around the caster. Players hit are knocked back,
-- dazed briefly (hard control through StatusService, so steady immunity
-- prevents stun-locks) and drop every relic they carry, unless they stand
-- inside their own Sanctuary.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local Core = script.Parent.Parent.Core
local Types = require(Core.Types)
local Sessions = require(Core.Sessions)
local Remotes = require(Core.Remotes)
local Services = script.Parent.Parent.Services
local StatusService = require(Services.StatusService)
local CarryService = require(Services.CarryService)
local PlotService = require(Services.PlotService)

local PULSE = GameConfig.Abilities.Pulse

local Pulse = {}

function Pulse.activate(ctx: Types.AbilityContext)
	local session = ctx.session
	local origin = ctx.root.Position
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
		local applied = StatusService.applyControl(target, "stun", PULSE.Stun)
		if not applied then
			continue
		end
		local flat = Vector3.new(offset.X, 0, offset.Z)
		local direction = if flat.Magnitude > 0.1 then flat.Unit else ctx.root.CFrame.LookVector
		target.teleportGraceUntil = ctx.now + 1.2
		Remotes.knockback(target.player, direction * PULSE.Knockback + Vector3.new(0, PULSE.Lift, 0), PULSE.Stun)
		Remotes.fx("Hit", { userId = target.userId, by = session.userId })
		if #target.carrying > 0 then
			-- Relics are safe once their carrier is inside their own Sanctuary.
			local safe = target.plot ~= nil and PlotService.isInside(target.plot, targetRoot.Position)
			if not safe then
				CarryService.dropAll(target, targetRoot.Position)
				Remotes.notify(target.player, "n.dropped", nil, "danger")
				Remotes.notify(ctx.player, "n.knockedDrop", { thief = target.player.DisplayName }, "success")
			end
		end
	end
end

return (Pulse :: any) :: Types.AbilityModule
