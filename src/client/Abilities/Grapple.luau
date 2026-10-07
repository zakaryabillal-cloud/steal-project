--!strict
-- Grapple: needs a target from GrappleTargeting (an anchor in range and in
-- sight). Sends the anchor INDEX only; the server re-checks range and line
-- of sight from its own data. The pull is applied locally (client-owned
-- physics) at the configured speed and stops on arrival (small hop onto the
-- ledge), on timeout, when stunned, or when the server cuts / refuses it.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldFeatures = require(ReplicatedStorage.Shared.WorldFeatures)

local Context = require(script.Parent.Context)
local Controllers = script.Parent.Parent.Controllers
local Store = require(Controllers.Store)
local AbilityFX = require(Controllers.AbilityFX)
local CameraFX = require(Controllers.CameraFX)
local GrappleTargeting = require(Controllers.GrappleTargeting)
local ClientNet = require(script.Parent.Parent.ClientNet)

local Grapple = {}

local localPlayer = Players.LocalPlayer
local pulling: RBXScriptConnection? = nil

local function stop()
	local connection = pulling
	if connection then
		pulling = nil
		connection:Disconnect()
	end
	AbilityFX.cutCable(localPlayer.UserId)
end

function Grapple.isPulling(): boolean
	return pulling ~= nil
end

function Grapple.canUse(_ctx: Context.ClientContext): (boolean, string?)
	if GrappleTargeting.current() == nil then
		return false, "noAnchor"
	end
	return true, nil
end

function Grapple.activate(ctx: Context.ClientContext): any
	local index = GrappleTargeting.current() :: number
	local tuning = ctx.tuning
	local target = WorldFeatures.GrapplePoints[index].position
	local root, humanoid = ctx.root, ctx.humanoid
	local speed = tuning.Speed * (if #Store.state.carrying > 0 then tuning.CarryFactor else 1)
	local distance = (target - root.Position).Magnitude
	local untilTime = os.clock() + distance / speed + tuning.ExtraTime
	stop()
	AbilityFX.cable(localPlayer.UserId, target, untilTime)
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	CameraFX.punch(6)
	pulling = RunService.Heartbeat:Connect(function()
		local stunned = Store.state.status.stunUntil > Store.now() or Store.state.status.rootUntil > Store.now()
		if os.clock() > untilTime or not root.Parent or humanoid.Health <= 0 or stunned then
			stop()
			return
		end
		local offset = target - root.Position
		if offset.Magnitude <= tuning.ArriveDistance then
			local flat = Vector3.new(offset.X, 0, offset.Z)
			local forward = if flat.Magnitude > 0.1 then flat.Unit * 16 else Vector3.zero
			root.AssemblyLinearVelocity = forward + Vector3.new(0, tuning.Hop, 0)
			stop()
			return
		end
		root.AssemblyLinearVelocity = offset.Unit * speed
	end)
	return index
end

function Grapple.denied(_reason: string)
	stop()
end

-- The server cut the cable (hard control, death...).
ClientNet.on("GrappleEnd", function(payload)
	if payload.userId == localPlayer.UserId then
		stop()
	end
end)

return (Grapple :: any) :: Context.ClientModule
