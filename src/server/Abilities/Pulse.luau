--!strict
-- Pulse (Control): shockwave around the caster. Players hit are knocked back,
-- dazed briefly (hard control through StatusService, so steady immunity and
-- shields prevent stun-locks) and drop every relic they carry, unless they
-- stand inside their own Sanctuary. Decoys caught in it pop.
--
-- Magma Heart harmony -> Eruption: a telegraphed magma ring (wind-up), then a
-- bigger, stronger burst on a longer cooldown. Stepping out of the ring
-- during the wind-up dodges it; a stun on the caster cancels it.
-- Cosmic Eye harmony: players hit lose their Spectral Phase.

local Core = script.Parent.Parent.Core
local Types = require(Core.Types)
local Remotes = require(Core.Remotes)
local Services = script.Parent.Parent.Services
local StatusService = require(Services.StatusService)
local CarryService = require(Services.CarryService)
local PlotService = require(Services.PlotService)
local Common = require(script.Parent.Common)
local Decoy = require(script.Parent.Decoy) :: any

type Session = Types.Session

type Pending = {
	owner: Session,
	origin: Vector3,
	executeAt: number,
	tuning: { [string]: any },
	cosmicEye: boolean,
}

local Pulse = {}

local pending: { Pending } = {}

local function burst(caster: Session, origin: Vector3, tuning: { [string]: any }, cosmicEye: boolean, look: Vector3)
	Decoy.popNear(origin, tuning.Radius, caster)
	-- Boss arena: the boss resists the push (BossService decides the effect).
	Common.bossEffect(caster, "pulse", origin, tuning.Radius)
	for _, target in Common.targets(caster, origin, tuning.Radius, false) do
		local session = target.session
		Common.onControlHit(cosmicEye, session)
		local applied = StatusService.applyControl(session, "stun", tuning.Stun)
		if not applied then
			continue
		end
		local flat = Vector3.new(target.offset.X, 0, target.offset.Z)
		local direction = if flat.Magnitude > 0.1 then flat.Unit else look
		session.teleportGraceUntil = workspace:GetServerTimeNow() + 1.2
		Remotes.knockback(session.player, direction * tuning.Knockback + Vector3.new(0, tuning.Lift, 0), tuning.Stun)
		Remotes.fx("Hit", { userId = session.userId, by = caster.userId })
		if #session.carrying > 0 then
			-- Relics are safe once their carrier is inside their own Sanctuary.
			local safe = session.plot ~= nil and PlotService.isInside(session.plot, target.root.Position)
			if not safe then
				CarryService.dropAll(session, target.root.Position)
				Remotes.notify(session.player, "n.dropped", nil, "danger")
				Remotes.notify(caster.player, "n.knockedDrop", { thief = session.player.DisplayName }, "success")
			end
		end
	end
end

function Pulse.activate(ctx: Types.AbilityContext)
	local session = ctx.session
	local tuning = ctx.tuning
	local origin = ctx.root.Position
	local cosmicEye = ctx.harmonies.cosmic_eye == true
	if tuning.Eruption then
		Pulse.cleanup(session, "replaced")
		table.insert(pending, {
			owner = session,
			origin = origin,
			executeAt = ctx.now + tuning.Windup,
			tuning = tuning,
			cosmicEye = cosmicEye,
		})
		Remotes.fx("EruptionWindup", { userId = session.userId, position = origin, radius = tuning.Radius, at = ctx.now + tuning.Windup })
		return
	end
	Remotes.fx("Pulse", { userId = session.userId, position = origin })
	burst(session, origin, tuning, cosmicEye, ctx.root.CFrame.LookVector)
end

function Pulse.tick(now: number)
	for i = #pending, 1, -1 do
		local item = pending[i]
		if now < item.executeAt then
			continue
		end
		table.remove(pending, i)
		local caster = item.owner
		local root = if caster.released then nil else Common.root(caster)
		if not root or not StatusService.canAct(caster, nil) then
			Remotes.fx("EruptionCancel", { userId = caster.userId })
			continue
		end
		Remotes.fx("Eruption", { userId = caster.userId, position = item.origin, radius = item.tuning.Radius })
		burst(caster, item.origin, item.tuning, item.cosmicEye, root.CFrame.LookVector)
	end
end

function Pulse.cleanup(session: Session, _reason: string)
	for i = #pending, 1, -1 do
		if pending[i].owner == session then
			table.remove(pending, i)
		end
	end
end

-- Tests / debug.
function Pulse.pendingCount(): number
	return #pending
end

return (Pulse :: any) :: Types.AbilityModule
