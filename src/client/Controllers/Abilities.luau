--!strict
-- Player abilities and movement feel on the client:
--   Dash (Q / R1 / button)  - applied locally for instant response
--   Pulse (F / L1 / button) - local FX immediately, server resolves hits
--   Seal (G / Y / button)   - asks the server to seal your Sanctuary
-- Also applies server knockbacks and handles bounce pads.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)

local ClientNet = require(script.Parent.Parent.ClientNet)
local Store = require(script.Parent.Store)
local Audio = require(script.Parent.Audio)
local CameraFX = require(script.Parent.CameraFX)
local CharacterFX = require(script.Parent.CharacterFX)
local RelicRenderer = require(script.Parent.RelicRenderer)

local Abilities = {}

local localPlayer = Players.LocalPlayer
local DASH = GameConfig.Abilities.Dash
local PULSE = GameConfig.Abilities.Pulse

-- Local prediction of cooldown end (os.clock based).
local readyAt: { [string]: number } = { dash = 0, pulse = 0, seal = 0 }
local durations = { dash = DASH.Cooldown, pulse = PULSE.Cooldown, seal = GameConfig.Sanctuary.SealCooldown }

-- (abilityKey) fired when an ability is used locally.
Abilities.used = Signal.new()

local function rootAndHumanoid(): (BasePart?, Humanoid?)
	local character = localPlayer.Character
	if not character then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil
	end
	return root, humanoid
end

-- Seconds until `key` is ready (max of local prediction and server state).
function Abilities.remaining(key: string): number
	local localRemaining = math.max(0, readyAt[key] - os.clock())
	return math.max(localRemaining, Store.cooldownRemaining(key))
end

function Abilities.duration(key: string): number
	return durations[key] or 1
end

local function stunned(humanoid: Humanoid): boolean
	return humanoid.WalkSpeed <= 0.1
end

function Abilities.dash()
	local root, humanoid = rootAndHumanoid()
	if not root or not humanoid or stunned(humanoid) or Abilities.remaining("dash") > 0 then
		return
	end
	readyAt.dash = os.clock() + DASH.Cooldown
	local move = humanoid.MoveDirection
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
		if os.clock() - start > DASH.Duration or not root.Parent then
			connection:Disconnect()
			return
		end
		local velocity = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(direction.X * DASH.Speed, math.max(velocity.Y, 6), direction.Z * DASH.Speed)
	end)
	CameraFX.punch(9)
	CharacterFX.dash(localPlayer.UserId)
	Audio.play("Dash")
	ClientNet.fire(Net.Events.Dash)
	Abilities.used:Fire("dash")
end

function Abilities.pulse()
	local root, humanoid = rootAndHumanoid()
	if not root or not humanoid or stunned(humanoid) or Abilities.remaining("pulse") > 0 then
		return
	end
	readyAt.pulse = os.clock() + PULSE.Cooldown
	CharacterFX.pulse(root.Position, localPlayer.UserId)
	CameraFX.shake(0.18)
	ClientNet.fire(Net.Events.Pulse)
	Abilities.used:Fire("pulse")
end

function Abilities.seal()
	if Store.state.plot == 0 then
		Audio.play("UiError")
		return
	end
	if Abilities.remaining("seal") > 0 then
		Audio.play("UiError")
		return
	end
	readyAt.seal = os.clock() + 0.5
	ClientNet.fire(Net.Events.Seal)
	Abilities.used:Fire("seal")
end

local KEYS: { [Enum.KeyCode]: () -> () } = {
	[Enum.KeyCode.Q] = Abilities.dash,
	[Enum.KeyCode.F] = Abilities.pulse,
	[Enum.KeyCode.G] = Abilities.seal,
	[Enum.KeyCode.ButtonR1] = Abilities.dash,
	[Enum.KeyCode.ButtonL1] = Abilities.pulse,
	[Enum.KeyCode.ButtonY] = Abilities.seal,
}

local function setupBouncePads()
	local rift = workspace:WaitForChild("World"):WaitForChild("Rift")
	local folder = rift:WaitForChild("BouncePads")
	local pads: { BasePart } = {}
	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute("Launch") ~= nil then
			table.insert(pads, child)
		end
	end
	local cooldown = 0
	RunService.Heartbeat:Connect(function()
		if os.clock() < cooldown then
			return
		end
		local root = rootAndHumanoid()
		if not root then
			return
		end
		for _, pad in pads do
			local offset = root.Position - pad.Position
			if math.abs(offset.Y - 3) < 2.2 and Vector3.new(offset.X, 0, offset.Z).Magnitude < 2.8 then
				local launch = pad:GetAttribute("Launch")
				if typeof(launch) == "Vector3" then
					cooldown = os.clock() + 1
					root.AssemblyLinearVelocity = launch
					Audio.play("Dash", { pitch = 1.3 })
					CameraFX.punch(6)
					RelicRenderer.burst(pad.Position + Vector3.new(0, 0.5, 0), Color3.fromRGB(120, 230, 255), 7, nil)
				end
				break
			end
		end
	end)
end

function Abilities.init()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local action = KEYS[input.KeyCode]
		if action then
			action()
		end
	end)

	ClientNet.onKnockback(function(impulse: Vector3, _stun: number)
		local root, humanoid = rootAndHumanoid()
		if not root or not humanoid then
			return
		end
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		root.AssemblyLinearVelocity = impulse
		CameraFX.shake(0.5)
		CameraFX.punch(-6)
	end)

	task.spawn(setupBouncePads)
end

return Abilities
