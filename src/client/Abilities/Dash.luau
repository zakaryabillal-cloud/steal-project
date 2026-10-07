--!strict
-- Dash: applied locally for instant response (the character's physics are
-- client-owned); the server validates the cooldown and broadcasts the trail.

local RunService = game:GetService("RunService")

local Context = require(script.Parent.Context)
local Controllers = script.Parent.Parent.Controllers
local Audio = require(Controllers.Audio)
local CameraFX = require(Controllers.CameraFX)
local CharacterFX = require(Controllers.CharacterFX)

local Dash = {}

function Dash.activate(ctx: Context.ClientContext): any
	local tuning = ctx.tuning
	local root = ctx.root
	local move = ctx.humanoid.MoveDirection
	local direction: Vector3
	if move.Magnitude > 0.1 then
		direction = Vector3.new(move.X, 0, move.Z).Unit
	else
		local look = root.CFrame.LookVector
		direction = Vector3.new(look.X, 0, look.Z).Unit
	end
	local start = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		if os.clock() - start > tuning.Duration or not root.Parent then
			connection:Disconnect()
			return
		end
		local velocity = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(direction.X * tuning.Speed, math.max(velocity.Y, 6), direction.Z * tuning.Speed)
	end)
	CameraFX.punch(9)
	CharacterFX.dash(ctx.player.UserId)
	Audio.play("Dash")
	return nil
end

return (Dash :: any) :: Context.ClientModule
