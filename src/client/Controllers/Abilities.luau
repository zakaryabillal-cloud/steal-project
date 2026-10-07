--!strict
-- Player abilities and movement feel on the client.
--
-- Loadout-driven: each slot of Config/Abilities.Slots (Mobility Q/R1,
-- Control F/L1, Utility R/R2) uses whatever ability the server says is
-- equipped (Store.state.loadout). Client modules in Client/Abilities only
-- predict and play feedback; the server validates everything.
--   Seal (G / Y / button) is a Sanctuary action, outside the loadout.
-- Also applies server knockbacks and handles bounce pads.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local AbilityConfig = require(Shared.Config.Abilities)
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)

local ClientNet = require(script.Parent.Parent.ClientNet)
local Store = require(script.Parent.Store)
local Audio = require(script.Parent.Audio)
local CameraFX = require(script.Parent.CameraFX)
local RelicRenderer = require(script.Parent.RelicRenderer)
local AbilityModules = script.Parent.Parent.Abilities
local Context = require(AbilityModules.Context)

local Abilities = {}

local localPlayer = Players.LocalPlayer

local modules: { [string]: Context.ClientModule } = {}
for _, def in AbilityConfig.list do
	local moduleScript = AbilityModules:FindFirstChild(def.module)
	assert(moduleScript and moduleScript:IsA("ModuleScript"), "missing client ability module " .. def.module)
	modules[def.id] = (require :: any)(moduleScript)
end

-- Local prediction of cooldown end (os.clock based), keyed by ability id or "seal".
local readyAt: { [string]: number } = { seal = 0 }

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

-- Seconds until `key` (ability id or "seal") is ready (max of local prediction and server state).
function Abilities.remaining(key: string): number
	local localRemaining = math.max(0, (readyAt[key] or 0) - os.clock())
	return math.max(localRemaining, Store.cooldownRemaining(key))
end

function Abilities.duration(key: string): number
	if key == "seal" then
		return GameConfig.Sanctuary.SealCooldown
	end
	local def = AbilityConfig.get(key)
	return if def then def.cooldown else 1
end

-- Ability id equipped in slot `index` ("" when empty).
function Abilities.slotAbility(index: number): string
	return Store.state.loadout[index] or ""
end

function Abilities.isEquipped(abilityId: string): boolean
	return table.find(Store.state.loadout, abilityId) ~= nil
end

local function stunned(humanoid: Humanoid): boolean
	return humanoid.WalkSpeed <= 0.1 or Store.state.status.stunUntil > Store.now()
end

-- Uses an equipped ability. Returns true when the request was sent.
function Abilities.use(abilityId: string): boolean
	local def = AbilityConfig.get(abilityId)
	local module = modules[abilityId]
	if not def or not module or not Abilities.isEquipped(abilityId) then
		return false
	end
	local root, humanoid = rootAndHumanoid()
	if not root or not humanoid or stunned(humanoid) or Abilities.remaining(abilityId) > 0 then
		return false
	end
	if def.needsMovement and Store.state.status.rootUntil > Store.now() then
		return false
	end
	readyAt[abilityId] = os.clock() + def.cooldown
	local payload = module.activate({ player = localPlayer, root = root, humanoid = humanoid, def = def })
	ClientNet.fire(Net.Events.UseAbility, abilityId, payload)
	Abilities.used:Fire(abilityId)
	return true
end

function Abilities.useSlot(index: number): boolean
	local abilityId = Abilities.slotAbility(index)
	if abilityId == "" then
		return false
	end
	return Abilities.use(abilityId)
end

-- V1 entry points (HUD, tests).
function Abilities.dash()
	Abilities.use("dash")
end

function Abilities.pulse()
	Abilities.use("pulse")
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
	[Enum.KeyCode.G] = Abilities.seal,
	[Enum.KeyCode.ButtonY] = Abilities.seal,
}
for index, slot in AbilityConfig.Slots do
	local function action()
		Abilities.useSlot(index)
	end
	KEYS[slot.keyboard] = action
	KEYS[slot.gamepad] = action
end

-- Bounce pads live in "BouncePads" folders anywhere under workspace.World
-- (Rift islands, Sky Route, High Ledge); each pad carries a Launch velocity.
local function setupBouncePads()
	local world = workspace:WaitForChild("World")
	while workspace:GetAttribute("WorldReady") ~= true do
		task.wait(0.2)
	end
	local pads: { BasePart } = {}
	for _, descendant in world:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute("Launch") ~= nil then
			table.insert(pads, descendant)
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
