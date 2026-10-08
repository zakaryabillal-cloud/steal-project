--!strict
-- Boss weapons (V2 phase 6.5): inventory, purchases, equipping and the
-- weapon held in hand inside the boss arena. Weapons only ever hit bosses
-- (BossService reads WeaponService.weaponOf); no PvP code reads them.
--
--   BuyWeapon(weaponId)    RemoteFunction: unlock condition (boss victories),
--                          Essence + boss materials checked and spent in one
--                          step on the server; never twice.
--   EquipWeapon(weaponId)  RemoteFunction: owned weapons only, not in the
--                          middle of a fight.
--
-- The held weapon is a server-built model (Shared/Weapons/WeaponModels)
-- welded to the hand(s) while the player is in the arena, so every client
-- sees it; it is removed on exit, death and leave.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Weapons = require(Shared.Config.Weapons)
local Materials = require(Shared.Config.Materials)
local WeaponModels = require(Shared.Weapons.WeaponModels)

local Core = script.Parent.Parent.Core
local Types = require(Core.Types)
local Sessions = require(Core.Sessions)
local Remotes = require(Core.Remotes)
local EconomyService = require(script.Parent.EconomyService)

type Session = Types.Session

local WeaponService = {}

-- Set by BossService: is this session fighting right now (no swap mid-fight)?
local fightingCheck: ((Session) -> boolean)? = nil

function WeaponService.setFightingCheck(fn: (Session) -> boolean)
	fightingCheck = fn
end

-- Equipped weapon definition (always a valid, owned one).
function WeaponService.weaponOf(session: Session): Weapons.WeaponDef
	local data = session.data.weapons
	local def = Weapons.get(data.equipped)
	if def and data.owned[def.id] then
		return def
	end
	return Weapons.get(Weapons.Starter) :: Weapons.WeaponDef
end

function WeaponService.owns(session: Session, weaponId: string): boolean
	return session.data.weapons.owned[weaponId] == true
end

-- Returns (ok, reason?). reason: invalid | owned | wins | essence | materials
function WeaponService.buy(player: Player, weaponId: any): (boolean, string?)
	local session = Sessions.ready(player)
	if not session then
		return false, "invalid"
	end
	local def = Weapons.get(weaponId)
	if not def then
		return false, "invalid"
	end
	local data = session.data
	local blocker = Weapons.blocker(def, data.weapons.owned, data.essence, data.materials, Weapons.totalWins(data.bosses))
	if blocker then
		return false, blocker
	end
	-- Everything was checked above: spend all of it, then grant.
	if not EconomyService.spend(session, def.price.essence) then
		return false, "essence"
	end
	for materialId, amount in def.price.materials do
		local material = Materials.get(materialId)
		if material then
			data.materials[materialId] = math.max(0, (data.materials[materialId] or 0) - amount)
		end
	end
	data.weapons.owned[def.id] = true
	Sessions.markCold(session)
	Sessions.touch(session)
	Remotes.notify(player, "n.weaponBought", { weapon = def.id }, "rare")
	Remotes.fxTo(player, "WeaponBought", { weapon = def.id })
	return true, nil
end

-- Returns (ok, reason?). reason: invalid | locked | inFight
function WeaponService.equip(player: Player, weaponId: any): (boolean, string?)
	local session = Sessions.ready(player)
	if not session then
		return false, "invalid"
	end
	local def = Weapons.get(weaponId)
	if not def then
		return false, "invalid"
	end
	if not WeaponService.owns(session, def.id) then
		return false, "locked"
	end
	if fightingCheck and fightingCheck(session) then
		return false, "inFight"
	end
	if session.data.weapons.equipped ~= def.id then
		session.data.weapons.equipped = def.id
		Sessions.markCold(session)
		-- Already in the arena (waiting room): swap the held model.
		if session.player.Character and session.player.Character:FindFirstChild("BossWeapon") then
			WeaponService.attach(session)
		end
	end
	Sessions.touch(session)
	return true, nil
end

----------------------------------------------------------------------------
-- Held weapon (arena only)
----------------------------------------------------------------------------

local function handOf(character: Model, side: string): (BasePart?, CFrame)
	-- R15 hands, then R6 arms (grip at the bottom of the arm), then the root.
	local r15 = character:FindFirstChild(if side == "right" then "RightHand" else "LeftHand")
	if r15 and r15:IsA("BasePart") then
		return r15, CFrame.new(0, -0.15, 0)
	end
	local r6 = character:FindFirstChild(if side == "right" then "Right Arm" else "Left Arm")
	if r6 and r6:IsA("BasePart") then
		return r6, CFrame.new(0, -1, 0)
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root, CFrame.new(if side == "right" then 1.5 else -1.5, -0.5, -0.5)
	end
	return nil, CFrame.identity
end

function WeaponService.detach(session: Session)
	local character = session.player.Character
	local existing = character and character:FindFirstChild("BossWeapon")
	if existing then
		existing:Destroy()
	end
end

-- Welds the equipped weapon to the fighter's hand(s).
function WeaponService.attach(session: Session): Model?
	WeaponService.detach(session)
	local character = session.player.Character
	if not character then
		return nil
	end
	local def = WeaponService.weaponOf(session)
	local built = WeaponModels.build(def)
	built.model.Name = "BossWeapon"
	for _, p in built.pieces do
		local hand, grip = handOf(character, p.hand)
		if not hand then
			p.part:Destroy()
			continue
		end
		p.part.Anchored = false
		p.part.CFrame = hand.CFrame * grip * p.offset
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hand
		weld.Part1 = p.part
		weld.Parent = p.part
	end
	built.model.Parent = character
	return built.model
end

function WeaponService.start()
	Remotes.onInvoke(Net.Functions.BuyWeapon, { rate = 1, burst = 3 }, WeaponService.buy)
	Remotes.onInvoke(Net.Functions.EquipWeapon, { rate = 2, burst = 4 }, WeaponService.equip)
end

return WeaponService
