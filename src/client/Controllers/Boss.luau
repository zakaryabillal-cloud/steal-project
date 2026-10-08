--!strict
-- Client side of boss expeditions (V2 phase 6): what the local player can
-- read about the portal and the arena (replicated attributes), the Strike
-- input (left click, E, gamepad X, the big touch button) with a local
-- cooldown, and the join / ready / leave requests.
--
-- The server decides everything (range, damage, cooldown, hits, rewards):
-- Strike carries no payload at all, a refused strike only undoes the local
-- swing feedback.
--
-- Phase 6.5: the swing uses the equipped boss weapon (cooldown, style) and a
-- 3-hit combo; the local character animates at once (Punch), the server's
-- answer (BossStruck) corrects the combo step; other fighters' swings come
-- from "BossSwing".

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Locale = require(Shared.Locale)
local Bosses = require(Shared.Config.Bosses)
local Weapons = require(Shared.Config.Weapons)
local Signal = require(Shared.Util.Signal)

local ClientNet = require(script.Parent.Parent.ClientNet)
local Store = require(script.Parent.Store)
local Punch = require(script.Parent.Punch)

local Boss = {}

-- (payload) a strike of ours landed (server confirmed).
Boss.struck = Signal.new()
-- (reason) a strike was refused (range, air, shield...).
Boss.denied = Signal.new()
-- () the local player swung (immediate feedback, before the server answers).
Boss.swung = Signal.new()
-- () the portal prompt asked for the boss card.
Boss.menuRequested = Signal.new()
-- (player, weaponDef, payload) another fighter swung.
Boss.otherSwung = Signal.new()

Boss.StrikeKeys = table.freeze({
	keyboard = Enum.KeyCode.E,
	gamepad = Enum.KeyCode.ButtonX,
})

local localPlayer = Players.LocalPlayer
local readyAt = 0
local initialized = false
-- Predicted combo step (corrected by the server) and its time.
local comboStep = 0
local comboAt = 0

local function attrString(instance: Instance?, name: string): string
	local value = if instance then instance:GetAttribute(name) else nil
	return if type(value) == "string" then value else ""
end

local function attrNumber(instance: Instance?, name: string): number
	local value = if instance then instance:GetAttribute(name) else nil
	return if type(value) == "number" then value else 0
end
Boss.attrNumber = attrNumber
Boss.attrString = attrString

function Boss.now(): number
	return workspace:GetServerTimeNow()
end

-- The arena model while an expedition exists (replicated from the server).
function Boss.arena(): Model?
	return workspace:FindFirstChild("BossArena") :: Model?
end

function Boss.anchor(): BasePart?
	local arena = Boss.arena()
	local anchor = arena and arena:FindFirstChild("Boss")
	return if anchor and anchor:IsA("BasePart") then anchor else nil
end

function Boss.plateau(): Instance?
	local world = workspace:FindFirstChild("World")
	local landmarks = world and world:FindFirstChild("Landmarks")
	return landmarks and landmarks:FindFirstChild("BossPlateau")
end

-- Is the local player inside the current expedition (waiting or fighting)?
function Boss.inFight(): boolean
	local fightId = localPlayer:GetAttribute("BossFight")
	return type(fightId) == "string" and fightId ~= ""
end

function Boss.hearts(): number
	return attrNumber(localPlayer, "BossHearts")
end

-- "Open" | "Intro" | "Fight" | "Victory" | "Defeat" | "" (no arena)
function Boss.fightState(): string
	return attrString(Boss.arena(), "State")
end

export type PortalView = {
	state: string, -- Dormant | Open | Fight
	boss: string,
	opensAt: number,
	closesAt: number,
	count: number,
}

function Boss.portal(): PortalView
	local plateau = Boss.plateau()
	local state = attrString(plateau, "PortalState")
	return {
		state = if state == "" then "Dormant" else state,
		boss = attrString(plateau, "PortalBoss"),
		opensAt = attrNumber(plateau, "PortalOpensAt"),
		closesAt = attrNumber(plateau, "PortalClosesAt"),
		count = attrNumber(plateau, "PortalCount"),
	}
end

-- Boss definition shown on the portal (current or next opening).
function Boss.portalBoss(): Bosses.BossDef
	return Bosses.get(Boss.portal().boss) or Bosses.list[1]
end

-- The boss after that one (rotation preview, phase 7A).
function Boss.portalNextBoss(): Bosses.BossDef?
	return Bosses.get(attrString(Boss.plateau(), "PortalNextBoss"))
end

-- Boss of the current arena (nil without one).
function Boss.arenaBoss(): Bosses.BossDef?
	return Bosses.get(attrString(Boss.arena(), "BossId"))
end

-- Per-boss text with a generic fallback: "boss.<id>.<key>" or "boss.<key>".
function Boss.text(bossId: string?, key: string, args: { [string]: any }?): string
	local own = "boss." .. tostring(bossId) .. "." .. key
	if bossId and Locale.has(own) then
		return Locale.t(own, args)
	end
	return Locale.t("boss." .. key, args)
end

-- Distance from the local character to the portal (math.huge without one).
function Boss.portalDistance(): number
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local plateau = Boss.plateau()
	local prompt = plateau and plateau:FindFirstChild("PortalPrompt")
	if not root or not root:IsA("BasePart") or not prompt or not prompt:IsA("BasePart") then
		return math.huge
	end
	local offset = root.Position - prompt.Position
	return Vector3.new(offset.X, 0, offset.Z).Magnitude
end

function Boss.join(): (boolean, string?)
	return ClientNet.invoke(Net.Functions.BossJoin)
end

function Boss.ready()
	ClientNet.fire(Net.Events.BossReady)
end

function Boss.leave()
	ClientNet.fire(Net.Events.BossLeave)
end

-- Equipped boss weapon (from the synced inventory; the server re-checks).
function Boss.weapon(): Weapons.WeaponDef
	local inventory = Store.state.weapons
	local def = Weapons.get(inventory and inventory.equipped)
	if def and inventory.owned[def.id] then
		return def
	end
	return Weapons.get(Weapons.Starter) :: Weapons.WeaponDef
end

-- Local cooldown fraction (0 = ready .. 1 = just used), display only.
function Boss.cooldownFraction(): number
	local remaining = readyAt - os.clock()
	if remaining <= 0 then
		return 0
	end
	return math.clamp(remaining / Boss.weapon().cooldown, 0, 1)
end

-- Current combo step for the HUD pips (0 when the combo timed out).
function Boss.comboStep(): number
	if os.clock() - comboAt > Weapons.ComboWindow then
		return 0
	end
	return comboStep
end

function Boss.canStrike(): boolean
	return Boss.inFight() and Boss.fightState() == "Fight" and Boss.hearts() > 0
end

-- Asks the server for a strike. Returns false when nothing was sent.
function Boss.strike(): boolean
	if not Boss.canStrike() or os.clock() < readyAt then
		return false
	end
	local weapon = Boss.weapon()
	readyAt = os.clock() + weapon.cooldown
	local step = if os.clock() - comboAt > Weapons.ComboWindow or comboStep >= #weapon.combo then 1 else comboStep + 1
	comboStep, comboAt = step, os.clock()
	ClientNet.fire(Net.Events.BossStrike)
	local character = localPlayer.Character
	if character then
		Punch.play(character, weapon.style, step, step == #weapon.combo, weapon.cooldown)
	end
	Boss.swung:Fire(weapon, step)
	return true
end

function Boss.init()
	if initialized then
		return
	end
	initialized = true
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not Boss.canStrike() then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Boss.StrikeKeys.keyboard or input.KeyCode == Boss.StrikeKeys.gamepad then
			Boss.strike()
		end
	end)
	ClientNet.on("BossStruck", function(payload)
		if type(payload.combo) == "number" then
			comboStep, comboAt = payload.combo, os.clock()
		end
		Boss.struck:Fire(payload)
	end)
	-- Another fighter's swing: animate their character here.
	ClientNet.on("BossSwing", function(payload)
		local player = Players:GetPlayerByUserId(tonumber(payload.userId) or 0)
		local def = Weapons.get(payload.weapon)
		if player and player ~= localPlayer and player.Character and def then
			Punch.play(player.Character, def.style, tonumber(payload.combo) or 1, payload.finisher == true, def.cooldown)
			Boss.otherSwung:Fire(player, def, payload)
		end
	end)
	ClientNet.on("BossStrikeDenied", function(payload)
		if payload.reason ~= "cooldown" then
			readyAt = 0
			comboStep = 0
		end
		Boss.denied:Fire(payload.reason)
	end)
	ClientNet.on("BossMenu", function()
		Boss.menuRequested:Fire()
	end)
end

return Boss
