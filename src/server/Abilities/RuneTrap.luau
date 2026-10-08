--!strict
-- Rune Trap (Control): a glowing rune placed on the ground under the caster
-- (the server finds the ground; the client sends no position). It arms after
-- a short delay, then the first other player (or decoy) stepping on it
-- triggers it: every other player on the rune is slowed (StatusService rules,
-- so never stacked, capped, no stun-lock). One trap per player: placing a new
-- one replaces the old. Visible to everyone (counterplay: walk around it).
--
-- Never placed inside another player's Sanctuary. Removed on the owner's
-- death, respawn, departure, unequip, expiry, and by a sweep that destroys
-- any trap part without a live record.

local Core = script.Parent.Parent.Core
local Types = require(Core.Types)
local Remotes = require(Core.Remotes)
local Sessions = require(Core.Sessions)
local Services = script.Parent.Parent.Services
local StatusService = require(Services.StatusService)
local PlotService = require(Services.PlotService)
local CharacterService = require(Services.CharacterService)
local Common = require(script.Parent.Common)
local Decoy = require(script.Parent.Decoy) :: any

type Session = Types.Session

export type Trap = {
	owner: Session,
	part: Part,
	position: Vector3,
	armedAt: number,
	expiresAt: number,
	tuning: { [string]: any },
	cosmicEye: boolean,
	armed: boolean,
}

local RuneTrap = {}

local traps: { [Session]: Trap } = {}
local sweepAt = 0

local TRAP_COLOR = Color3.fromRGB(205, 130, 255)

-- Where the trap would go for this cast, or (nil, reason).
local function placement(ctx: Types.AbilityContext): (Vector3?, string?)
	local params = Common.params(ctx.session)
	local ground = Common.ground(ctx.root.Position, 3 + ctx.tuning.MaxGroundDrop, params)
	if not ground then
		return nil, "noGround"
	end
	local position = ground.Position
	local plot = PlotService.plotAt(position)
	if plot ~= nil and plot ~= ctx.session.plot then
		return nil, "forbidden"
	end
	if Common.sealedAgainst(ctx.session, position) then
		return nil, "forbidden"
	end
	return position, nil
end

local function destroy(trap: Trap, how: string)
	if traps[trap.owner] == trap then
		traps[trap.owner] = nil
	end
	trap.owner.abilityState.trap = nil
	if trap.part.Parent then
		trap.part:Destroy()
	end
	Remotes.fx("TrapEnd", { userId = trap.owner.userId, position = trap.position, how = how })
end

function RuneTrap.validate(ctx: Types.AbilityContext): (boolean, string?)
	local position, reason = placement(ctx)
	return position ~= nil, reason
end

function RuneTrap.activate(ctx: Types.AbilityContext)
	local session = ctx.session
	local tuning = ctx.tuning
	local position = placement(ctx)
	if not position then
		return
	end
	local previous = traps[session]
	if previous then
		destroy(previous, "replaced")
	end
	local part = Instance.new("Part")
	part.Name = "RuneTrap"
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(0.3, tuning.Size, tuning.Size)
	part.CFrame = CFrame.new(position + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = TRAP_COLOR
	part.Transparency = 0.6
	part:SetAttribute("OwnerId", session.userId)
	part:SetAttribute("ArmedAt", ctx.now + tuning.ArmTime)
	part:SetAttribute("ExpiresAt", ctx.now + tuning.Lifetime)
	part:SetAttribute("Radius", tuning.TriggerRadius)
	part.Parent = Common.folder()
	local trap: Trap = {
		owner = session,
		part = part,
		position = position,
		armedAt = ctx.now + tuning.ArmTime,
		expiresAt = ctx.now + tuning.Lifetime,
		tuning = tuning,
		cosmicEye = ctx.harmonies.cosmic_eye == true,
		armed = false,
	}
	traps[session] = trap
	session.abilityState.trap = true
	Remotes.fx("TrapPlaced", { userId = session.userId, position = position, armedAt = trap.armedAt })
end

local function onRune(trap: Trap, root: BasePart, extra: number): boolean
	local p = root.Position
	local flat = Vector3.new(p.X - trap.position.X, 0, p.Z - trap.position.Z).Magnitude
	local dy = p.Y - trap.position.Y
	return flat <= trap.tuning.TriggerRadius + extra and dy > -1.5 and dy < 7
end

local function trigger(trap: Trap)
	local tuning = trap.tuning
	local victims = {}
	for _, target in Sessions.all() do
		if not Common.canAffect(trap.owner, target) then
			continue
		end
		local root = Common.root(target)
		if root and onRune(trap, root, 1) then
			Common.onControlHit(trap.cosmicEye, target)
			if StatusService.applySlow(target, "trap", tuning.Slow, tuning.SlowDuration) then
				table.insert(victims, target.userId)
			end
		end
	end
	Decoy.popNear(trap.position, tuning.TriggerRadius, trap.owner)
	Remotes.fx("TrapTriggered", { userId = trap.owner.userId, position = trap.position, victims = victims })
	destroy(trap, "triggered")
end

function RuneTrap.tick(now: number)
	for owner, trap in table.clone(traps) do
		if owner.released or not trap.part.Parent or now >= trap.expiresAt then
			destroy(trap, "expired")
			continue
		end
		if now < trap.armedAt then
			continue
		end
		if not trap.armed then
			trap.armed = true
			trap.part.Transparency = 0.25
			trap.part:SetAttribute("Armed", true)
		end
		local fired = false
		for _, target in Sessions.all() do
			if Common.canAffect(owner, target) and not CharacterService.isProtected(target) then
				local root = Common.root(target)
				if root and onRune(trap, root, 0) then
					fired = true
					break
				end
			end
		end
		if not fired then
			-- A decoy running over the rune sets it off (and pops).
			for _, record in Decoy.active() do
				if record.owner ~= owner then
					local at = Decoy.position(record, now)
					local flat = Vector3.new(at.X - trap.position.X, 0, at.Z - trap.position.Z).Magnitude
					if flat <= trap.tuning.TriggerRadius and math.abs(at.Y - trap.position.Y) < 7 then
						fired = true
						break
					end
				end
			end
		end
		if fired then
			trigger(trap)
		end
	end
	-- Sweep: no trap part may exist without a live record.
	if now >= sweepAt then
		sweepAt = now + 1
		local folder = workspace:FindFirstChild("Abilities")
		if folder then
			for _, child in folder:GetChildren() do
				if child.Name == "RuneTrap" then
					local owned = false
					for _, trap in traps do
						if trap.part == child then
							owned = true
							break
						end
					end
					if not owned then
						child:Destroy()
					end
				end
			end
		end
	end
end

function RuneTrap.cleanup(session: Session, reason: string)
	local trap = traps[session]
	if trap then
		destroy(trap, reason)
	end
	session.abilityState.trap = nil
end

-- Tests / debug.
function RuneTrap.of(session: Session): Trap?
	return traps[session]
end

function RuneTrap.count(): number
	local n = 0
	for _ in traps do
		n += 1
	end
	return n
end

return (RuneTrap :: any) :: Types.AbilityModule
