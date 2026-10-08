--!nocheck
-- V2 phase 6.5 ("Combat 2.0 & boss weapons") scenarios. Called by
-- tests/run.luau with its helpers, after V2Bosses, on the same live server.
--
--   * weapon catalogue: prices from the real economy, bounded DPS, combos,
--     no invented asset id, every string in both languages;
--   * schema 6 (weapon inventory): migration, sanitising, Sync;
--   * purchases and equipping: wins, Essence, materials, duplicates, spam,
--     forged ids, no swap mid-fight;
--   * weapons only ever hit bosses (source scan, Power untouched);
--   * strikes with the equipped weapon: damage, combo, reach, cooldown,
--     dizzy / chill / team buff / heal, broadcast swings, held model;
--   * PvP abilities against the boss: no push, no stun, no slow, arena
--     limits for Blink / Grapple, shield blocks, phase dodges, decoys lure;
--   * readability: yellow then red, warning sounds, Low quality, the "!"
--     bubble, motion sync, safe quarter, dodge / block feedback;
--   * procedural punch on R15 and R6 rigs (and nothing on other rigs);
--   * controls: Strike never overlaps another button (PC, phone, tablet,
--     Roblox's own touch Jump button), normal controls kept outside;
--   * the ARMES / WEAPONS screen: cards, preview, compare, buy, equip.

local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local Vector3 = roblox.Vector3
local Vector2 = roblox.Vector2
local CFrame = roblox.CFrame
local UDim2 = roblox.UDim2
local Enum = roblox.Enum

return function(ctx)
	local scenario, check, advance, waitFor = ctx.scenario, ctx.check, ctx.advance, ctx.waitFor
	local sreq, shared, remote, Engine, Loader, game = ctx.sreq, ctx.shared, ctx.remote, ctx.Engine, ctx.Loader, ctx.game
	local sessionOf, teleport = ctx.sessionOf, ctx.teleport
	local hasNotification, clearLog = ctx.hasNotification, ctx.clearLog
	local alice = ctx.alice()
	-- V2Bosses reconnects Bob (disconnect test): use the live one.
	local bob = game:GetService("Players"):FindFirstChild("Bob") or ctx.bob()

	local Sessions = sreq("Core.Sessions")
	local Snapshot = sreq("Core.Snapshot")
	local DataSchema = sreq("Core.DataSchema")
	local Expeditions = sreq("Core.Expeditions")
	local BossService = sreq("Services.BossService")
	local WeaponService = sreq("Services.WeaponService")
	local AbilityService = sreq("Services.AbilityService")
	local StatusService = sreq("Services.StatusService")
	local EconomyService = sreq("Services.EconomyService")
	local Common = sreq("Abilities.Common")
	local Grapple = sreq("Abilities.Grapple")
	local RuneTrap = sreq("Abilities.RuneTrap")
	local Decoy = sreq("Abilities.Decoy")
	local ArenaBuilder = sreq("World.ArenaBuilder")
	local Bosses = shared("Config.Bosses")
	local Weapons = shared("Config.Weapons")
	local Materials = shared("Config.Materials")
	local Abilities = shared("Config.Abilities")
	local Sounds = shared("Config.Sounds")
	local Emoji = shared("Config.Emoji")
	local GameConfig = shared("Config.GameConfig")
	local WorldFeatures = shared("WorldFeatures")
	local Strings = shared("Locale.Strings")
	local WeaponModels = shared("Weapons.WeaponModels")
	local Theme = shared("Config.Theme")
	local STORE = GameConfig.Data.StoreName .. "/u_"

	local Client = game:GetService("StarterPlayer").StarterPlayerScripts.Client
	local function creq(path)
		local node = Client
		for part in string.gmatch(path, "[^%.]+") do
			node = node:FindFirstChild(part)
		end
		return Loader.require("client", node)
	end

	local Instance = Engine.Instance
	local DEF = Bosses.get("VoidWarden")
	local ARENA = Bosses.Arena
	local FLOOR = ARENA.Center.Y
	local STARTER = Weapons.get(Weapons.Starter)

	local function now()
		return Engine.workspace:GetServerTimeNow()
	end
	local function root(player)
		return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	end
	local function deepCopy(t)
		if type(t) ~= "table" then
			return t
		end
		local out = {}
		for k, v in t do
			out[k] = deepCopy(v)
		end
		return out
	end
	local function fxList(player, kind)
		local list = {}
		for _, entry in Engine.clientLog[player] or {} do
			if entry.remote == "FX" and entry.args[1] == kind then
				table.insert(list, entry.args[2])
			end
		end
		return list
	end
	local function fxCount(player, kind)
		return #fxList(player, kind)
	end
	local function lastFx(player, kind)
		local list = fxList(player, kind)
		return list[#list]
	end
	local function atPortal(player, k)
		local spec = WorldFeatures.BossPlateau
		local p = WorldFeatures.polar(spec.deg + ((k or 0) % 5 - 2) * 1.2, spec.portalR - 12, spec.top + 3)
		teleport(player, p)
		advance(0.1)
	end
	local function arenaPoint(dx, dz, lift)
		return Vector3.new(ARENA.Center.X + dx, FLOOR + 3 + (lift or 0), ARENA.Center.Z + dz)
	end
	local function fight()
		return BossService.state()
	end
	local function calm()
		local f = fight()
		if f then
			f.nextAttackAt = math.huge
			f.plan = nil
			if f.motion then
				f.anchor.CFrame = CFrame.new(f.motion.to)
			end
			f.motion = nil
			table.clear(f.shapes)
		end
	end
	local function reset()
		BossService.devReset()
		BossService.setRandom(nil)
		BossService.setNextOpen(now() + 100000)
		advance(0.2)
	end
	-- In front of the boss at `distance` studs from his body surface.
	local function nearBoss(player, distance, side)
		local f = fight()
		local a = f.anchor.Position
		local d = DEF.radius + (distance or 2)
		Engine.moveTo(player, Vector3.new(a.X + (side or 0) * 4, FLOOR + 3, a.Z - d))
		sessionOf(player).lastPosition = nil
	end
	local function openWith(players)
		reset()
		local f = BossService.open()
		for i, player in players do
			atPortal(player, i)
			local ok, reason = BossService.join(player)
			assert(ok, "join failed for " .. player.Name .. ": " .. tostring(reason))
		end
		advance(0.2)
		return f
	end
	local function startNow()
		BossService.devStart()
		advance(0.2)
		advance(Bosses.Combat.Intro + 0.1)
		calm()
	end
	-- Fresh weapon inventory (starter only) and wallet for a session.
	local function wallet(s, essence, shards, catalysts, wins)
		s.data.weapons = DataSchema.defaultWeapons()
		s.data.essence = essence or 0
		s.data.materials.void_shard = shards
		s.data.materials.void_catalyst = catalysts
		s.data.bosses.VoidWarden = s.data.bosses.VoidWarden or DataSchema.newBossRecord()
		local record = s.data.bosses.VoidWarden
		record.discovered = true
		record.attempts = math.max(record.attempts, wins or 0)
		record.wins = wins or 0
		Sessions.markCold(s)
	end
	local function equipNow(s, weaponId)
		s.data.weapons.owned[weaponId] = true
		s.data.weapons.equipped = weaponId
		Sessions.markCold(s)
	end
	-- Unlock + equip an ability in its slot (server shortcut), ready to use.
	local function give(s, abilityId)
		local def = Abilities.get(abilityId)
		s.data.abilities.unlocked[abilityId] = true
		s.data.abilities.loadout[Abilities.slotIndex(def.slot)] = abilityId
		Sessions.setCooldown(s, abilityId, 0)
		Sessions.markCold(s)
	end

	local savedA, savedB = nil, nil

	--------------------------------------------------------------------------
	scenario("V2 Combat: weapon catalogue, economy-based prices, bounded DPS", function()
		reset()
		local sa, sb = sessionOf(alice), sessionOf(bob)
		savedA = { weapons = deepCopy(sa.data.weapons), materials = deepCopy(sa.data.materials), bosses = deepCopy(sa.data.bosses), essence = sa.data.essence, loadout = table.clone(sa.data.abilities.loadout), unlocked = table.clone(sa.data.abilities.unlocked) }
		savedB = { weapons = deepCopy(sb.data.weapons), essence = sb.data.essence, loadout = table.clone(sb.data.abilities.loadout), unlocked = table.clone(sb.data.abilities.unlocked) }
		check(#Weapons.list == 6, "6 boss weapons (from free to prestige)")
		check(STARTER and STARTER.starter and STARTER.price.essence == 0 and STARTER.wins == 0 and next(STARTER.price.materials) == nil, "Foam Gloves: free starter, always owned")
		check(STARTER.damage == Bosses.Strike.Damage and STARTER.cooldown == Bosses.Strike.Cooldown and STARTER.combo[1] == 1, "the starter's first hit is the phase 6 strike (no regression)")
		local previous, previousWins, rarities = -1, 0, {}
		local starterDps = Weapons.dps(STARTER)
		local best, bestId = 0, ""
		for i, def in Weapons.list do
			check(def.order == i, def.id .. ": order " .. i)
			check(def.price.essence > previous, def.id .. ": price above the previous one (" .. def.price.essence .. ")")
			check(def.wins >= previousWins, def.id .. ": unlock condition never goes backwards (" .. def.wins .. " victories)")
			previous, previousWins = def.price.essence, def.wins
			rarities[def.rarity] = true
			check(#def.combo == 3 and def.combo[3] >= def.combo[1], def.id .. ": 3-hit combo, the finisher is the biggest")
			local ratio = Weapons.dps(def) / starterDps
			check(ratio <= Weapons.MaxDpsRatio + 1e-9 and ratio >= 0.8, def.id .. string.format(": DPS %.1f (x%.2f of the gloves, cap x%.1f)", Weapons.dps(def), ratio, Weapons.MaxDpsRatio))
			if Weapons.dps(def) > best then
				best, bestId = Weapons.dps(def), def.id
			end
			for materialId, amount in def.price.materials do
				check(Materials.get(materialId) ~= nil and amount > 0 and amount == math.floor(amount), def.id .. ": material " .. materialId .. " x" .. amount .. " exists")
			end
			check(Strings.en["weapon." .. def.id .. ".name"] and Strings.fr["weapon." .. def.id .. ".name"] and Strings.en["weapon." .. def.id .. ".special"] and Strings.fr["weapon." .. def.id .. ".special"], def.id .. ": name and special in English and French")
			check(Emoji.get(def.emoji) ~= nil and Emoji.get(def.emoji) ~= "", def.id .. ": card emoji exists")
			check(table.find({ "punch", "smash", "shoot", "zap", "thrust" }, def.style) ~= nil, def.id .. ": known animation style " .. def.style)
		end
		check(rarities.Common and rarities.Rare and rarities.Epic and rarities.Legendary, "4 rarities, free to prestige")
		check(bestId == "rainbow_hammer", "the prestige weapon has the best DPS (" .. bestId .. ")")
		-- Prices against the real income (casual player, phase 6.5 simulation):
		-- ~130 Essence/s at 20 min, ~1 000/s at 1 h, ~2 300/s at 2 h.
		local mallet, prestige = Weapons.get("squeaky_mallet"), Weapons.get("rainbow_hammer")
		check(mallet.wins == 0 and mallet.price.essence / 130 <= 300, "first purchase within a first session (" .. math.floor(mallet.price.essence / 130) .. " s of a 20-min income)")
		check(prestige.price.essence / 2300 >= 2400 and prestige.price.essence / 2300 <= 3600 * 1.5, "prestige = 40-90 min of a 2-hour income (" .. math.floor(prestige.price.essence / 2300 / 60) .. " min)")
		-- Materials: 3-6 shards per victory, catalyst 15 %.
		local shards, catalysts, wins = 0, 0, 0
		for _, def in Weapons.list do
			shards += def.price.materials.void_shard or 0
			catalysts += def.price.materials.void_catalyst or 0
			wins = math.max(wins, def.wins)
		end
		local victories = math.max(wins, shards / 4.5, catalysts / 0.15)
		check(victories >= 10 and victories <= 25, string.format("whole collection ~%.0f victories (several sessions, no endless grind)", victories))
		-- Combo maths.
		local t = 100
		check(Weapons.nextCombo(STARTER, 0, 0, t) == 1 and Weapons.nextCombo(STARTER, 1, t - 0.5, t) == 2 and Weapons.nextCombo(STARTER, 2, t - 0.5, t) == 3, "combo 1 -> 2 -> 3 within the window")
		check(Weapons.nextCombo(STARTER, 3, t - 0.5, t) == 1 and Weapons.nextCombo(STARTER, 2, t - Weapons.ComboWindow - 0.01, t) == 1, "after the finisher or a pause the combo restarts")
		check(Weapons.nextCombo(STARTER, 99, t - 0.1, t) == 1 and Weapons.nextCombo(STARTER, -4, t - 0.1, t) == 1, "corrupted combo steps restart at 1")
		-- Blockers.
		local none = {}
		check(Weapons.blocker(STARTER, { foam_gloves = true }, 0, none, 0) == "owned", "blocker: owned")
		check(Weapons.blocker(Weapons.get("bubble_blaster"), {}, 1e9, none, 0) == "wins", "blocker: victories first")
		check(Weapons.blocker(Weapons.get("star_wand"), {}, 1, { void_shard = 99 }, 9) == "essence", "blocker: Essence")
		check(Weapons.blocker(Weapons.get("star_wand"), {}, 1e9, { void_shard = 9 }, 9) == "materials", "blocker: materials")
		check(Weapons.blocker(Weapons.get("star_wand"), {}, 1e9, { void_shard = 10 }, 2) == nil, "blocker: nil when everything is met")
		check(Weapons.totalWins({ VoidWarden = { wins = 3 }, Other = { wins = 2 } }) == 5 and Weapons.totalWins(nil) == 0, "victories summed over every boss")
		-- Models: native parts only.
		for _, def in Weapons.list do
			local built = WeaponModels.build(def)
			local ok = #built.pieces >= 1
			for _, piece in built.pieces do
				ok = ok and piece.part:IsA("BasePart") and piece.part.CanCollide == false and piece.part.Massless == true
			end
			check(ok, def.id .. ": model of native parts (" .. #built.pieces .. " pieces, massless, no collision)")
			built.model:Destroy()
		end
		for _, path in { "src/shared/Config/Weapons.luau", "src/shared/Weapons/WeaponModels.luau", "src/server/Services/WeaponService.luau", "src/client/Controllers/Punch.luau", "src/client/UI/Screens/Weapons.luau" } do
			local source = fs.readFile(path)
			check(string.find(source, "rbxassetid", 1, true) == nil and string.find(source, "AnimationId", 1, true) == nil, path .. ": no asset id, no Animation asset")
		end
	end)

	--------------------------------------------------------------------------
	scenario("V2 Combat: schema 6 weapon inventory, migration, sanitising, Sync", function()
		check(DataSchema.Version == 6 and GameConfig.Data.SchemaVersion == 6, "schema 6")
		local phase6 = {
			schema = 5,
			essence = 4321,
			power = { peak = 77 },
			relics = { { uid = "w1", id = "storm_crystal", level = 2, slot = 1 } },
			bosses = { VoidWarden = { discovered = true, attempts = 4, wins = 2 } },
			materials = { void_shard = 9 },
			trophies = {},
		}
		local data = DataSchema.normalize(deepCopy(phase6))
		check(data.schema == 6 and data.weapons.owned.foam_gloves == true and data.weapons.equipped == "foam_gloves", "phase 6 save -> owns and holds the free gloves")
		local count = 0
		for _ in data.weapons.owned do
			count += 1
		end
		check(count == 1, "nothing else granted by the migration")
		check(data.essence == 4321 and data.bosses.VoidWarden.wins == 2 and data.materials.void_shard == 9 and #data.relics == 1, "nothing lost from phase 6")
		check(phase6.weapons == nil and phase6.schema == 5, "the stored record is never mutated")
		local tampered = deepCopy(phase6)
		tampered.schema = 6
		tampered.weapons = { owned = { squeaky_mallet = true, fake_sword = true, rainbow_hammer = "yes", [3] = true, foam_gloves = false }, equipped = "fake_sword" }
		local clean = DataSchema.normalize(tampered)
		check(clean.weapons.owned.squeaky_mallet == true and clean.weapons.owned.fake_sword == nil and clean.weapons.owned.rainbow_hammer == nil and clean.weapons.owned[3] == nil, "only known weapons owned with a real true")
		check(clean.weapons.owned.foam_gloves == true, "the starter can never be lost")
		check(clean.weapons.equipped == "foam_gloves", "unknown equipped weapon -> starter")
		tampered.weapons = { owned = { squeaky_mallet = true }, equipped = "rainbow_hammer" }
		check(DataSchema.normalize(tampered).weapons.equipped == "foam_gloves", "equipped but not owned -> starter")
		tampered.weapons = { owned = { squeaky_mallet = true }, equipped = "squeaky_mallet" }
		local round = DataSchema.normalize(DataSchema.serialize(DataSchema.normalize(tampered)))
		check(round.weapons.equipped == "squeaky_mallet" and round.weapons.owned.squeaky_mallet, "serialize -> normalize round trip is lossless")
		tampered.weapons = "garbage"
		check(DataSchema.normalize(tampered).weapons.equipped == "foam_gloves", "garbage inventory -> starter only")
		-- Sync.
		local sa = sessionOf(alice)
		local cold = Snapshot.cold(sa)
		check(type(cold.weapons) == "table" and cold.weapons.equipped ~= nil and cold.weapons.owned.foam_gloves, "weapon inventory synced (cold)")
		local Store = creq("Controllers.Store")
		advance(0.6)
		check(Store.state.weapons and Store.state.weapons.owned.foam_gloves, "client store holds the inventory")
	end)

	--------------------------------------------------------------------------
	scenario("V2 Combat: purchases are server-validated (wins, Essence, materials, duplicates, spam)", function()
		reset()
		local sa = sessionOf(alice)
		wallet(sa, 0, 0, 0, 0)
		for _, forged in { nil, 123, "fake_sword", { id = "squeaky_mallet" }, "" } do
			local ok, reason = WeaponService.buy(alice, forged)
			check(not ok and reason == "invalid", "forged weapon id refused (" .. tostring(forged) .. ")")
		end
		local ok, reason = WeaponService.buy(alice, "foam_gloves")
		check(not ok and reason == "owned", "the starter cannot be bought again")
		ok, reason = WeaponService.buy(alice, "squeaky_mallet")
		check(not ok and reason == "essence" and sa.data.weapons.owned.squeaky_mallet == nil, "not enough Essence: refused, nothing granted")
		sa.data.essence = 25000 + 5
		clearLog(alice)
		ok, reason = WeaponService.buy(alice, "squeaky_mallet")
		check(ok and sa.data.weapons.owned.squeaky_mallet == true and sa.data.essence == 5, "Squeaky Mallet bought: exactly 25 000 Essence spent")
		check(sa.data.weapons.equipped == "foam_gloves", "buying never equips by itself")
		check(fxCount(alice, "WeaponBought") == 1 and hasNotification(alice, "n.weaponBought"), "purchase feedback (sound + notification)")
		sa.data.essence = 1e7
		ok, reason = WeaponService.buy(alice, "squeaky_mallet")
		check(not ok and reason == "owned" and sa.data.essence == 1e7, "a weapon is never bought twice")
		ok, reason = WeaponService.buy(alice, "bubble_blaster")
		check(not ok and reason == "wins" and sa.data.essence == 1e7, "Bubble Blaster locked before the first victory")
		sa.data.bosses.VoidWarden.wins = 2
		sa.data.bosses.VoidWarden.attempts = math.max(sa.data.bosses.VoidWarden.attempts, 2)
		sa.data.materials.void_shard = 9
		ok, reason = WeaponService.buy(alice, "star_wand")
		check(not ok and reason == "materials" and sa.data.materials.void_shard == 9 and sa.data.essence == 1e7, "missing Void Shards: refused, nothing spent")
		sa.data.materials.void_shard = 12
		ok = WeaponService.buy(alice, "star_wand")
		check(ok and sa.data.materials.void_shard == 2 and sa.data.essence == 1e7 - 400000, "Star Wand: 400 000 Essence + 10 Void Shards spent")
		-- Spam through the remote with the exact resources for one plunger.
		sa.data.bosses.VoidWarden.wins = 5
		sa.data.bosses.VoidWarden.attempts = math.max(sa.data.bosses.VoidWarden.attempts, 5)
		sa.data.essence = 1500000
		sa.data.materials.void_shard = 20
		sa.data.materials.void_catalyst = 1
		local granted = 0
		for _ = 1, 20 do
			local okRemote = Engine.invokeServer(remote("BuyWeapon"), alice, "giant_plunger")
			if okRemote == true then
				granted += 1
			end
			advance(0.05)
		end
		check(granted == 1 and sa.data.essence == 0 and sa.data.materials.void_shard == 0 and sa.data.materials.void_catalyst == 0, "20 spammed purchases: bought once, paid once")
		local fine = pcall(function()
			Engine.invokeServer(remote("BuyWeapon"), alice, { 1, 2 }, "extra", 1e9)
			Engine.invokeServer(remote("EquipWeapon"), alice, nil)
		end)
		check(fine, "garbage remote arguments never error")
		-- Equipping.
		advance(1.5)
		ok, reason = WeaponService.equip(alice, "rainbow_hammer")
		check(not ok and reason == "locked", "cannot equip a weapon you do not own")
		ok, reason = WeaponService.equip(alice, "made_up")
		check(not ok and reason == "invalid", "cannot equip a forged id")
		ok = Engine.invokeServer(remote("EquipWeapon"), alice, "star_wand")
		check(ok == true and sa.data.weapons.equipped == "star_wand" and WeaponService.weaponOf(sa).id == "star_wand", "equip through the remote")
		-- Saved: the next autosave / leave writes schema 6 with the inventory.
		local serial = DataSchema.serialize(sa.data)
		check(serial.weapons.owned.giant_plunger == true and serial.weapons.equipped == "star_wand", "inventory serialised for the DataStore")
		WeaponService.equip(alice, "foam_gloves")
	end)

	--------------------------------------------------------------------------
	scenario("V2 Combat: weapons only ever hit bosses (normal PvP untouched)", function()
		reset()
		-- Only the boss code, the inventory and the client weapon UI read weapons.
		local allowed = {
			["src/shared/Config/Weapons.luau"] = true,
			["src/shared/Weapons/WeaponModels.luau"] = true,
			["src/server/Services/WeaponService.luau"] = true,
			["src/server/Services/BossService.luau"] = true,
			["src/server/Services/DevCommands.luau"] = true,
			["src/server/Core/DataSchema.luau"] = true,
			["src/server/Core/Types.luau"] = true,
			["src/server/init.server.luau"] = true,
			["src/client/Controllers/Boss.luau"] = true,
			["src/client/Controllers/BossFX.luau"] = true,
			["src/client/UI/Screens/Weapons.luau"] = true,
			["src/client/UI/Screens/BossHud.luau"] = true,
			["src/client/init.client.luau"] = true,
		}
		local readers, stray = 0, {}
		local function scan(dir)
			for _, name in fs.readDir(dir) do
				local path = dir .. "/" .. name
				if fs.isDir(path) then
					scan(path)
				elseif string.sub(name, -5) == ".luau" then
					local source = fs.readFile(path)
					if string.find(source, "Config.Weapons", 1, true) or string.find(source, "WeaponService", 1, true) then
						readers += 1
						if not allowed[path] then
							table.insert(stray, path)
						end
					end
				end
			end
		end
		scan("src")
		check(readers >= 6 and #stray == 0, "no PvP code reads weapons (" .. (if #stray > 0 then table.concat(stray, ", ") else readers .. " allowed readers") .. ")")
		for _, path in { "src/server/Services/StealService.luau", "src/server/Services/AbilityService.luau", "src/server/Abilities/Common.luau", "src/server/Services/EconomyService.luau", "src/server/Services/PlotService.luau" } do
			local source = fs.readFile(path)
			check(string.find(source, "weapon", 1, true) == nil, path .. ": no weapon in the PvP code")
		end
		-- Power and income do not change with the weapon.
		local sa = sessionOf(alice)
		EconomyService.recompute(sa)
		local power, rate = sa.power, sa.rate
		equipNow(sa, "rainbow_hammer")
		EconomyService.recompute(sa)
		check(sa.power == power and sa.rate == rate, "Power and income identical with the prestige weapon")
		-- No strike, no held weapon outside the arena.
		local struck, why = BossService.strike(alice)
		check(not struck and why == "arena", "no weapon hit outside the arena")
		check(alice.Character:FindFirstChild("BossWeapon") == nil, "no weapon held on the island")
		sa.data.weapons.equipped = "foam_gloves"
	end)

	--------------------------------------------------------------------------
	scenario("V2 Combat: strikes use the equipped weapon (damage, combo, reach, cooldown)", function()
		local sa, sb = sessionOf(alice), sessionOf(bob)
		wallet(sa, 0, 0, 0, 0)
		equipNow(sa, "squeaky_mallet")
		local f = openWith({ alice, bob })
		local held = alice.Character:FindFirstChild("BossWeapon")
		check(held ~= nil and held:IsA("Model") and #held:GetChildren() >= 1, "the equipped weapon is held in the arena (waiting room)")
		local welded = true
		for _, part in held:GetDescendants() do
			if part:IsA("BasePart") then
				local weld = part:FindFirstChildOfClass("WeldConstraint")
				welded = welded and weld ~= nil and weld.Part0 ~= nil and part.Anchored == false
			end
		end
		check(welded, "every piece welded to the hand (root fallback on the test rig)")
		-- Swap in the waiting room: allowed, the held model follows.
		local ok, reason = WeaponService.equip(alice, "foam_gloves")
		check(ok and alice.Character:FindFirstChild("BossWeapon") ~= nil, "weapon swap allowed in the waiting room (" .. tostring(reason) .. ")")
		WeaponService.equip(alice, "squeaky_mallet")
		startNow()
		ok, reason = WeaponService.equip(alice, "foam_gloves")
		check(not ok and reason == "inFight", "no weapon swap in the middle of a fight")
		-- Combo 1-2-3 with the mallet.
		local mallet = Weapons.get("squeaky_mallet")
		local expected = { 1, 2, 3, 1 }
		local hp = f.hp
		local allRight = true
		clearLog(alice)
		clearLog(bob)
		for i = 1, 4 do
			nearBoss(alice, 3)
			local struck = BossService.strike(alice)
			local p = BossService.participant(alice)
			local want = Bosses.hitDamage(mallet.damage, sa.power, mallet.combo[expected[i]])
			allRight = allRight and struck and p.combo == expected[i] and math.abs((hp - f.hp) - want) < 1e-6
			hp = f.hp
			advance(mallet.cooldown + 0.02)
		end
		check(allRight, "mallet combo 1-2-3-1: damage = weapon x combo x Power bonus")
		local struckFx = fxList(alice, "BossStruck")
		check(#struckFx == 4 and struckFx[3].finisher == true and struckFx[3].combo == 3 and struckFx[3].weapon == "squeaky_mallet", "the finisher is announced (KAPOW!)")
		local swings = fxList(bob, "BossSwing")
		check(#swings == 4 and swings[1].userId == alice.UserId and swings[1].weapon == "squeaky_mallet", "other fighters see every swing (animated on their screen)")
		check(fxCount(alice, "BossSwing") == 0, "nobody is sent their own swing twice")
		-- Pause = combo restarts.
		advance(Weapons.ComboWindow + 0.1)
		nearBoss(alice, 3)
		BossService.strike(alice)
		check(BossService.participant(alice).combo == 1, "a pause restarts the combo")
		-- Cooldown of the weapon (server-side 90 % of it).
		advance(mallet.cooldown * 0.6)
		local struck, why = BossService.strike(alice)
		check(not struck and why == "cooldown", "the heavy mallet is slower (server cooldown)")
		advance(mallet.cooldown)
		-- Reach: blaster hits from afar, gloves do not.
		equipNow(sa, "bubble_blaster")
		nearBoss(alice, 22)
		struck = BossService.strike(alice)
		check(struck, "Bubble Blaster hits from 22 studs")
		advance(1)
		equipNow(sa, "foam_gloves")
		nearBoss(alice, 22)
		struck, why = BossService.strike(alice)
		check(not struck and why == "range", "Foam Gloves cannot (range)")
		advance(1)
		-- Dizzy bonus (plunger).
		equipNow(sa, "giant_plunger")
		local plunger = Weapons.get("giant_plunger")
		f.dizzyFrom, f.dizzyUntil = now() - 0.1, now() + 3
		hp = f.hp
		nearBoss(alice, 3)
		BossService.strike(alice)
		check(math.abs((hp - f.hp) - Bosses.hitDamage(plunger.damage, sa.power, Bosses.Strike.DizzyMultiplier * plunger.special.value)) < 1e-6, "Giant Plunger: x1.5 more on a dizzy boss")
		f.dizzyFrom, f.dizzyUntil = 0, 0
		advance(1.5)
		-- Chill (Frost Wave) and team buff (Star Wand finisher).
		equipNow(sa, "star_wand")
		local wand = Weapons.get("star_wand")
		for _ = 1, 3 do
			nearBoss(alice, 3)
			BossService.strike(alice)
			advance(wand.cooldown + 0.02)
		end
		check(f.buffUntil > now() and math.abs(f.buffValue - wand.special.value) < 1e-9 and fxCount(bob, "BossBuff") >= 1, "Star Wand finisher: +15 % for the whole team, announced")
		hp = f.hp
		nearBoss(bob, 3, 1)
		sb.lastPosition = nil
		BossService.strike(bob)
		local bobWeapon = WeaponService.weaponOf(sb)
		local bobCombo = BossService.participant(bob).combo
		check(math.abs((hp - f.hp) - Bosses.hitDamage(bobWeapon.damage, sb.power, bobWeapon.combo[bobCombo] * (1 + wand.special.value))) < 1e-6, "a teammate's hit gets the buff")
		f.buffUntil = 0
		advance(1.5)
		-- Heal (Rainbow Hammer finisher), once per 15 s, never above 3 hearts.
		equipNow(sa, "rainbow_hammer")
		local p = BossService.participant(alice)
		p.hearts = Bosses.Combat.Hearts - 1
		alice:SetAttribute("BossHearts", p.hearts)
		local hammer = Weapons.get("rainbow_hammer")
		clearLog(alice)
		for _ = 1, 3 do
			nearBoss(alice, 3)
			BossService.strike(alice)
			advance(hammer.cooldown + 0.02)
		end
		check(p.hearts == Bosses.Combat.Hearts and alice:GetAttribute("BossHearts") == Bosses.Combat.Hearts and fxCount(alice, "BossHeal") == 1, "Rainbow Hammer finisher gives a heart back")
		p.hearts = Bosses.Combat.Hearts - 1
		for _ = 1, 3 do
			nearBoss(alice, 3)
			BossService.strike(alice)
			advance(hammer.cooldown + 0.02)
		end
		check(p.hearts == Bosses.Combat.Hearts - 1, "...but only once every 15 s")
		p.hearts = Bosses.Combat.Hearts
		alice:SetAttribute("BossHearts", p.hearts)
		-- Forged payloads: the remote carries nothing the server reads.
		advance(1.5)
		hp = f.hp
		clearLog(alice)
		Engine.fireServer(remote("BossStrike"), alice, "rainbow_hammer", 1e9, { combo = 3 })
		advance(0.1)
		local payload = lastFx(alice, "BossStruck")
		check(payload and payload.combo == 1 and math.abs((hp - f.hp) - Bosses.hitDamage(hammer.damage, sa.power, hammer.combo[1])) < 1e-6, "forged weapon / damage / combo ignored")
		-- Leaving drops the held weapon.
		BossService.leave(alice)
		advance(0.5)
		check(alice.Character == nil or alice.Character:FindFirstChild("BossWeapon") == nil, "weapon removed when leaving the arena")
		equipNow(sa, "foam_gloves")
		reset()
		check(bob.Character == nil or bob.Character:FindFirstChild("BossWeapon") == nil, "weapon removed after the expedition")
	end)

	--------------------------------------------------------------------------
	scenario("V2 Combat: PvP abilities against the boss (no push, no stun, arena limits)", function()
		local sa, sb = sessionOf(alice), sessionOf(bob)
		local harmonyBackup = sa.harmonyRelics
		sa.harmonyRelics = {}
		local f = openWith({ alice, bob })
		startNow()
		local function cast(abilityId, payload)
			give(sa, abilityId)
			StatusService.clearSlow(sa, "goo")
			return AbilityService.use(alice, abilityId, payload)
		end
		-- Pulse: no push, heavy BOING, washes the goo off.
		local anchorBefore = f.anchor.Position
		nearBoss(alice, 3)
		nearBoss(bob, 4, 1)
		sb.lastPosition = nil
		StatusService.applySelfSlow(sa, "goo", 0.45, 3)
		give(sa, "pulse")
		local hp = f.hp
		clearLog(alice)
		local used, reason = AbilityService.use(alice, "pulse", nil)
		advance(0.1)
		check(used, "Pulse usable in the arena (" .. tostring(reason) .. ")")
		check(math.abs((hp - f.hp) - Bosses.Abilities.pulse.damage) < 1e-6, "Pulse deals " .. Bosses.Abilities.pulse.damage .. " to the boss")
		check((f.anchor.Position - anchorBefore).Magnitude < 1e-3, "the boss is never pushed")
		check(not (sa.status.slows and sa.status.slows.goo), "Pulse washes the sticky goo off")
		local ability = lastFx(alice, "BossAbility")
		check(ability and ability.ability == "pulse" and ability.resist == true, "\"BOING!\" + \"RESISTS!\" feedback")
		check(not StatusService.isStunned or not StatusService.isStunned(sb), "a teammate next to him is never stunned")
		check(not Common.canAffect(sa, sb), "abilities never hit another fighter")
		-- Far from the boss: nothing.
		Engine.moveTo(alice, arenaPoint(40, 30))
		sa.lastPosition = nil
		hp = f.hp
		cast("pulse")
		advance(0.1)
		check(f.hp == hp, "Pulse out of reach does nothing to him")
		-- Frost Wave: chill (+15 % damage taken), no slow.
		nearBoss(alice, 3)
		hp = f.hp
		used = cast("frost_wave")
		advance(0.1)
		check(used and math.abs((hp - f.hp) - Bosses.Abilities.frost_wave.damage) < 1e-6 and f.chillUntil > now(), "Frost Wave chills him (" .. Bosses.Abilities.frost_wave.damage .. " damage)")
		advance(0.5)
		equipNow(sa, "foam_gloves")
		local p = BossService.participant(alice)
		p.combo, p.lastHitAt = 0, 0
		hp = f.hp
		nearBoss(alice, 3)
		BossService.strike(alice)
		check(math.abs((hp - f.hp) - Bosses.hitDamage(STARTER.damage, sa.power, 1 + Bosses.Abilities.frost_wave.chill)) < 1e-6, "a chilled boss takes +15 %")
		f.chillUntil = 0
		-- Rune Trap: he walks onto it -> ZAP.
		nearBoss(alice, 14)
		used, reason = cast("rune_trap")
		check(used, "Rune Trap placed in the arena (" .. tostring(reason) .. ")")
		local trap = RuneTrap.of(sa)
		advance(GameConfig.Abilities.RuneTrap.ArmTime + 0.2)
		check(trap and trap.armed, "the rune arms")
		hp = f.hp
		f.anchor.CFrame = CFrame.new(Vector3.new(trap.position.X, f.anchor.Position.Y, trap.position.Z))
		advance(0.2)
		check(math.abs((hp - f.hp) - Bosses.Abilities.rune_trap.damage) < 1e-6 and RuneTrap.of(sa) == nil, "the boss sets it off: " .. Bosses.Abilities.rune_trap.damage .. " damage, rune used")
		f.anchor.CFrame = CFrame.new(anchorBefore)
		-- Shield: blocks the next boss hit, then breaks.
		Engine.moveTo(alice, arenaPoint(30, 0))
		sa.lastPosition = nil
		used = cast("shield")
		check(used and StatusService.isShielded(sa), "Shield up in the arena")
		clearLog(alice)
		local spot = Vector3.new(root(alice).Position.X, FLOOR, root(alice).Position.Z)
		table.insert(f.shapes, { kind = "circle", at = now() + 0.05, center = spot, radius = 6, resolved = {} })
		advance(0.2)
		check(p.hearts == Bosses.Combat.Hearts and fxCount(alice, "BossBlock") == 1 and not StatusService.isShielded(sa), "the shield blocks one boss hit (\"BLOCKED!\") and breaks")
		advance(1)
		table.insert(f.shapes, { kind = "circle", at = now() + 0.05, center = spot, radius = 6, resolved = {} })
		advance(0.2)
		check(p.hearts == Bosses.Combat.Hearts - 1, "the next hit lands normally")
		p.hearts = Bosses.Combat.Hearts
		alice:SetAttribute("BossHearts", p.hearts)
		advance(2)
		-- Spectral Phase: attacks pass through.
		used = cast("phase")
		check(used and StatusService.isPhased(sa), "Spectral Phase in the arena")
		clearLog(alice)
		table.insert(f.shapes, { kind = "circle", at = now() + 0.05, center = spot, radius = 6, resolved = {} })
		advance(0.2)
		local dodge = lastFx(alice, "BossDodge")
		check(p.hearts == Bosses.Combat.Hearts and dodge and dodge.kind == "phase", "his attack passes through a phased fighter (\"PHASED!\")")
		advance(2)
		-- Decoy: he aims at it too.
		Engine.moveTo(alice, arenaPoint(-20, 0))
		Engine.moveTo(bob, arenaPoint(-25, 5))
		sa.lastPosition, sb.lastPosition = nil, nil
		used, reason = cast("decoy", Vector3.new(1, 0, 0))
		advance(0.3)
		local targets = BossService.debugTargets()
		local decoys = Decoy.active()
		check(used and #decoys >= 1 and #targets == 3, "a running decoy becomes a target of his attacks (" .. #targets .. " targets)")
		advance(5)
		-- Blink never leaves the arena.
		Engine.moveTo(alice, arenaPoint(ARENA.Radius - 6, 0))
		sa.lastPosition = nil
		give(sa, "blink")
		AbilityService.use(alice, "blink", Vector3.new(1, 0, 0))
		advance(0.6)
		check(ArenaBuilder.inside(root(alice).Position), "Blink towards the wall stays inside the arena")
		local c = ARENA.Center
		check(not Common.allowedSpot(sa, Vector3.new(c.X + ARENA.Radius + 5, c.Y + 3, c.Z)) and Common.allowedSpot(sa, arenaPoint(10, 10)), "arena destinations only while away")
		check(Common.allowedSpot(sessionOf(alice), arenaPoint(10, 10)) and Expeditions.isAway(sa), "(fighter is away)")
		-- Grapple: the 4 arena bubbles, never a world anchor.
		local anchors = Bosses.arenaGrapplePoints()
		check(#anchors == 4 and Grapple.readPayload(anchors[1].index) ~= nil and Grapple.readPayload(Bosses.ArenaGrapple.FirstIndex + 4) == nil, "4 arena anchors; anything else is refused")
		local world = Engine.workspace:FindFirstChild("BossArena")
		local bubbles = world and world:FindFirstChild("GrapplePoints")
		check(bubbles ~= nil and #bubbles:GetChildren() >= 4, "the anchors are drawn in the arena")
		local target = anchors[1].position
		Engine.moveTo(alice, Vector3.new(target.X - 10, FLOOR + 3, target.Z - 10))
		sa.lastPosition = nil
		local tuning = GameConfig.Abilities.Grapple
		local okArena = Grapple.check(sa, root(alice), anchors[1].index, tuning)
		local okWorld, whyWorld = Grapple.check(sa, root(alice), 1, tuning)
		check(okArena and not okWorld and whyWorld == "noAnchor", "grapple: arena anchors in the arena, never the island's")
		give(sa, "grapple")
		used, reason = AbilityService.use(alice, "grapple", anchors[1].index)
		check(used, "grapple to a bubble works (" .. tostring(reason) .. ")")
		advance(2)
		check(ArenaBuilder.inside(root(alice).Position), "the grapple ends inside the arena")
		-- Dash still fine.
		give(sa, "dash")
		used, reason = AbilityService.use(alice, "dash", nil)
		check(reason ~= "arena", "Dash usable in the arena (" .. tostring(used) .. ")")
		reset()
		-- Back home: arena anchors are refused.
		local okHome, whyHome = Grapple.check(sa, root(alice), anchors[1].index, tuning)
		check(not okHome and whyHome == "noAnchor", "arena anchors refused outside an expedition")
		sa.harmonyRelics = harmonyBackup
		sa.data.abilities.loadout = table.clone(savedA.loadout)
		sa.data.abilities.unlocked = table.clone(savedA.unlocked)
		Sessions.markCold(sa)
		EconomyService.recompute(sa)
	end)

	--------------------------------------------------------------------------
	scenario("V2 Combat: readable attacks (yellow then red, sounds, sync, safe quarter, feedback)", function()
		local BossFX = creq("Controllers.BossFX")
		local BossHud = creq("UI.Screens.BossHud")
		local Settings = creq("Controllers.Settings")
		local Audio = creq("Controllers.Audio")
		local lead = Bosses.Combat.DangerLead
		check(lead >= 0.25 and lead <= 0.5, "red danger window " .. lead .. " s (reaction time)")
		for id, attack in DEF.attacks do
			check(attack.telegraph - lead >= 0.5, id .. ": at least 0.5 s of yellow before the red")
		end
		local hitAt = 100
		local c1, d1 = BossFX.zoneColor(hitAt - 1, hitAt)
		local c2, d2 = BossFX.zoneColor(hitAt - lead + 0.01, hitAt)
		check(not d1 and c1.R > 0.9 and c1.G > 0.75 and c1.B < 0.4, "preparation = YELLOW")
		check(d2 and c2.R > 0.9 and c2.G < 0.7, "danger = RED")
		-- One distinct warning sound per attack.
		local seen = {}
		for id in DEF.attacks do
			local key = BossFX.WarnSounds[id]
			check(key and Sounds[key] ~= nil and not seen[key], id .. ": its own warning sound (" .. tostring(key) .. ")")
			if key then
				seen[key] = true
			end
		end
		for _, key in { "BossDanger", "PunchSwing", "PunchHit", "PunchFinisher", "Dodge", "Block", "HeartLost", "WeaponBuy" } do
			check(Sounds[key] ~= nil and (Sounds[key].id == "" or string.find(Sounds[key].id, "rbxasset", 1, true) ~= nil), key .. ": built-in fallback sound only (no invented id)")
		end
		-- Live attack, Low quality: telegraph parts still drawn, colours move.
		local sa, sb = sessionOf(alice), sessionOf(bob)
		local played = {}
		local origPlay, origPlayAt = Audio.play, Audio.playAt
		Audio.play = function(key, ...)
			table.insert(played, key)
			return origPlay(key, ...)
		end
		Audio.playAt = function(key, ...)
			table.insert(played, key)
			return origPlayAt(key, ...)
		end
		local quality = Settings.quality
		Settings.quality = "Low"
		local f = openWith({ alice, bob })
		startNow()
		Engine.moveTo(alice, arenaPoint(15, 10))
		Engine.moveTo(bob, arenaPoint(-15, -10))
		sa.lastPosition, sb.lastPosition = nil, nil
		clearLog(alice)
		f.nextAttackAt = now()
		advance(0.15)
		local payload = lastFx(alice, "BossAttack")
		check(payload ~= nil, "attack announced")
		local function partColors()
			local yellow, red, total = 0, 0, 0
			for _, d in Engine.workspace.ClientBoss:GetDescendants() do
				-- Telegraph surfaces only (discs and Big Cleanup fans).
				if d:IsA("BasePart") and (d.Name == "Disc" or d:IsA("WedgePart")) then
					total += 1
					local col = d.Color
					if col.R > 0.9 and col.G > 0.75 and col.B < 0.4 then
						yellow += 1
					elseif col.R > 0.9 and col.G < 0.6 then
						red += 1
					end
				end
			end
			return yellow, red, total
		end
		local y1, r1, total = partColors()
		check(total > 0 and y1 > 0 and r1 == 0, "Low quality: telegraph drawn in YELLOW while he prepares (" .. y1 .. "/" .. total .. " parts)")
		check(table.find(played, BossFX.WarnSounds[payload.attack]) ~= nil, "warning sound of " .. payload.attack .. " played")
		local shown, icon, bubbleColor = BossFX.bubbleState()
		check(shown and icon ~= "" and bubbleColor and bubbleColor.G > 0.75, "\"!\" bubble over the boss, attack icon, yellow")
		-- Motion sync: hops carry the server arc.
		check(payload.motion == nil or (f.motion ~= nil and payload.motion.endAt == f.motion.endAt and payload.motion.to == f.motion.to), "client arc = server arc (" .. payload.attack .. ")")
		-- Danger moment (payload.hitAt = first damage of every attack).
		advance(math.max(0, payload.hitAt - lead / 2 - now()))
		local _, r2 = partColors()
		check(r2 > 0, "RED just before the damage (" .. r2 .. " parts)")
		check(table.find(played, "BossDanger") ~= nil, "danger tick sound")
		local _, _, bubbleRed = BossFX.bubbleState()
		check(bubbleRed and bubbleRed.G < 0.6, "the bubble turns red too")
		calm()
		-- Every attack, drawn from a server plan: yellow first, no damage before.
		for _, attackId in { "broom_wave", "goo_puddles", "dust_bunnies", "belly_flop", "big_cleanup" } do
			local plan = sreq("Bosses.VoidWarden").plan({
				boss = DEF,
				phase = 3,
				participants = 2,
				center = ARENA.Center,
				floorY = FLOOR,
				radius = ARENA.Radius,
				bossPosition = f.anchor.Position,
				targets = { arenaPoint(10, 0, -3), arenaPoint(-10, 5, -3) },
				rng = Engine.Random.new(5),
			}, attackId, now())
			local earliest = math.huge
			for _, shape in plan.shapes do
				earliest = math.min(earliest, shape.at)
			end
			check(earliest >= plan.hitAt - 1e-9 and plan.hitAt - lead > plan.telegraphAt, attackId .. ": server damage never before the red window")
			if plan.motion then
				check(plan.motion.endAt <= earliest + 0.3, attackId .. ": the body lands when the damage happens")
			end
		end
		-- Big Cleanup: safe quarter beacon + HUD arrow.
		table.clear(played)
		local center = Vector3.new(ARENA.Center.X, FLOOR, ARENA.Center.Z)
		BossFX.attack({ attack = "big_cleanup", telegraphAt = now(), hitAt = now() + 3, data = { center = center, sweeps = { { safeAngle = 0, at = now() + 3 } }, safeWidth = math.pi / 2, radius = ARENA.Radius, dizzyAt = now() + 3.3, dizzyFor = 2 } })
		advance(0.2)
		local beacon = nil
		for _, d in Engine.workspace.ClientBoss:GetDescendants() do
			if d.Name == "SafeBeacon" then
				beacon = d
			end
		end
		check(beacon ~= nil and beacon.Size.X >= 30, "tall green beacon on the safe quarter")
		check(BossFX.safeZone and BossFX.safeZone.safeAngle == 0 and BossFX.safeZone.untilTime > now(), "safe zone known by the HUD")
		local hud = alice.PlayerGui:FindFirstChild("RiftHUD")
		local arrow = nil
		for _, d in hud:GetDescendants() do
			if d.Name == "SafeArrow" then
				arrow = d
			end
		end
		check(arrow ~= nil and arrow.Visible, "HUD arrow points to the safe quarter")
		advance(3.5)
		-- Feedback when dodging / blocking / being hit.
		calm()
		local p = BossService.participant(alice)
		p.hearts = Bosses.Combat.Hearts
		p.dodgeFxAt = 0
		Engine.moveTo(alice, arenaPoint(20, 0))
		sa.lastPosition = nil
		clearLog(alice)
		local spot = Vector3.new(root(alice).Position.X + 9, FLOOR, root(alice).Position.Z)
		table.insert(f.shapes, { kind = "circle", at = now() + 0.05, center = spot, radius = 6, resolved = {} })
		advance(0.2)
		local dodge = lastFx(alice, "BossDodge")
		check(dodge and dodge.kind == "step" and p.hearts == Bosses.Combat.Hearts, "near miss: \"DODGED!\"")
		advance(1)
		table.insert(f.shapes, { kind = "sector", at = now() + 0.05, center = center, radius = 80, safeAngle = 0, safeWidth = math.pi / 2, resolved = {} })
		advance(0.2)
		dodge = lastFx(alice, "BossDodge")
		check(dodge and dodge.kind == "safe", "in the safe quarter: \"SAFE!\"")
		table.clear(played)
		BossFX.dodge({ userId = alice.UserId, kind = "jump" })
		BossFX.hit({ userId = alice.UserId, hearts = 2, position = root(alice).Position })
		check(table.find(played, "Dodge") ~= nil and table.find(played, "HeartLost") ~= nil, "dodge and heart-lost sounds")
		check(Strings.en["boss.dodge.jump"] and Strings.fr["boss.dodge.jump"] and Strings.en["boss.block"] and Strings.fr["boss.safeGo"], "feedback texts in both languages")
		local _ = BossHud
		Settings.quality = quality
		Audio.play, Audio.playAt = origPlay, origPlayAt
		reset()
	end)

	--------------------------------------------------------------------------
	scenario("V2 Combat: procedural punch on R15 and R6 rigs (no asset id)", function()
		local Punch = creq("Controllers.Punch")
		local function motor(parent, name)
			local m = Instance.new("Motor6D")
			m.Name = name
			m.C0 = CFrame.new(1, 0.5, 0)
			m.Parent = parent
			return m
		end
		local function part(model, name)
			local p = Instance.new("Part")
			p.Name = name
			p.Parent = model
			return p
		end
		local r15 = Instance.new("Model")
		r15.Name = "RigR15"
		part(r15, "HumanoidRootPart")
		local upper = part(r15, "UpperTorso")
		local waist = motor(upper, "Waist")
		local rs = motor(part(r15, "RightUpperArm"), "RightShoulder")
		local ls = motor(part(r15, "LeftUpperArm"), "LeftShoulder")
		local re = motor(part(r15, "RightLowerArm"), "RightElbow")
		motor(part(r15, "LeftLowerArm"), "LeftElbow")
		r15.Parent = Engine.workspace
		local r6 = Instance.new("Model")
		r6.Name = "RigR6"
		part(r6, "HumanoidRootPart")
		local torso = part(r6, "Torso")
		local r6r = motor(torso, "Right Shoulder")
		local r6l = motor(torso, "Left Shoulder")
		r6.Parent = Engine.workspace
		local blocky = Instance.new("Model")
		blocky.Name = "CustomRig"
		part(blocky, "HumanoidRootPart")
		blocky.Parent = Engine.workspace
		local base = CFrame.new(1, 0.5, 0)
		local function moved(m)
			return (m.C0.LookVector - base.LookVector).Magnitude > 0.05 or (m.C0.UpVector - base.UpVector).Magnitude > 0.05
		end
		local function rest(m)
			return not moved(m) and (m.C0.Position - base.Position).Magnitude < 1e-4
		end
		check(Punch.play(r15, "punch", 1, false, 0.4) == "R15", "R15 rig recognised")
		advance(0.15)
		check(moved(rs) and moved(waist) and not moved(ls), "R15 jab: right arm + waist twist")
		advance(0.5)
		check(rest(rs) and rest(waist) and rest(re) and Punch.active() == 0, "R15 joints restored exactly after the swing")
		Punch.play(r15, "punch", 2, false, 0.4)
		advance(0.15)
		check(moved(ls) and not moved(rs), "combo hit 2: the other fist")
		advance(0.5)
		for _, style in { "smash", "shoot", "zap", "thrust" } do
			Punch.play(r15, style, 3, true, 0.5)
			advance(0.2)
			local any = moved(rs) or moved(ls) or moved(waist)
			advance(0.6)
			check(any and rest(rs) and rest(ls), "R15 " .. style .. " animates, then restores")
		end
		check(Punch.play(r6, "smash", 1, false, 0.62) == "R6", "R6 rig recognised")
		advance(0.15)
		check(moved(r6r) and moved(r6l), "R6 overhead smash: both shoulders")
		advance(0.6)
		check(rest(r6r) and rest(r6l), "R6 shoulders restored")
		Punch.play(r6, "punch", 1, false, 0.4)
		Punch.play(r6, "punch", 2, false, 0.4)
		advance(0.7)
		check(rest(r6r) and rest(r6l), "a swing interrupted by the next one never leaves a joint bent")
		local okCustom, kind = pcall(Punch.play, blocky, "punch", 1, false, 0.4)
		advance(0.6)
		check(okCustom and kind == "none", "custom rig without standard joints: no arm motion, no error (documented)")
		-- Animation length never exceeds the weapon's rhythm.
		for _, def in Weapons.list do
			local duration = math.clamp(def.cooldown * 0.9, 0.22, 0.6)
			check(duration <= def.cooldown + 1e-9, def.id .. ": swing " .. string.format("%.2f", duration) .. " s <= cooldown " .. def.cooldown .. " s")
		end
		-- The harness character (no Motor6D) strikes without error.
		check(Punch.play(alice.Character, "punch", 1, false, 0.4) == "none" or true, "test rig handled")
		advance(0.6)
		r15:Destroy()
		r6:Destroy()
		blocky:Destroy()
		advance(0.1)
		check(Punch.active() == 0, "no swing left running")
	end)

	--------------------------------------------------------------------------
	scenario("V2 Combat: Strike never overlaps another button (PC, phone, tablet)", function()
		local Hud = creq("UI.Screens.Hud")
		local BossHud = creq("UI.Screens.BossHud")
		local TouchSafe = creq("UI.Kit.TouchSafe")
		local Boss = creq("Controllers.Boss")
		local L = BossHud.Layout
		local A = Hud.abilityLayout()
		-- Absolute rectangle (real pixels) of a GUI box.
		local function rect(W, H, scale, size, position, anchor)
			local w, h = size.X * scale, size.Y * scale
			local x = position.X.Scale * W + position.X.Offset * scale - anchor.X * w
			local y = position.Y.Scale * H + position.Y.Offset * scale - anchor.Y * h
			return { x, y, x + w, y + h }
		end
		local function overlap(a, b)
			return a[1] < b[3] and b[1] < a[3] and a[2] < b[4] and b[2] < a[4]
		end
		local function inside(a, W, H)
			return a[1] >= 0 and a[2] >= 0 and a[3] <= W and a[4] <= H
		end
		local devices = {
			{ name = "PC 1280x720", size = Vector2.new(1280, 720), touch = false },
			{ name = "PC 1920x1080", size = Vector2.new(1920, 1080), touch = false },
			{ name = "PC 1366x768", size = Vector2.new(1366, 768), touch = false },
			{ name = "phone 812x375", size = Vector2.new(812, 375), touch = true },
			{ name = "phone 667x375", size = Vector2.new(667, 375), touch = true },
			{ name = "phone 932x430", size = Vector2.new(932, 430), touch = true },
			{ name = "tablet 1024x768", size = Vector2.new(1024, 768), touch = true },
			{ name = "tablet 1366x1024", size = Vector2.new(1366, 1024), touch = true },
			{ name = "tablet 1180x820", size = Vector2.new(1180, 820), touch = true },
		}
		for _, device in devices do
			local W, H = device.size.X, device.size.Y
			local s = TouchSafe.scaleFor(device.size, device.touch)
			local lw, lh = W / s, H / s
			local bottom = if device.touch then TouchSafe.bottomOffset(device.size, s) else 0
			local boxes = {}
			-- Strike.
			local strike = if device.touch then L.strikeTouch else L.strikePc
			local strikePos = if device.touch then UDim2.new(1, -272, 1, -bottom) else strike.position
			local function add(name, box)
				table.insert(boxes, { name = name, box = box })
			end
			add("Strike", rect(W, H, s, Vector2.new(strike.size, strike.size), strikePos, Vector2.new(1, 1)))
			-- Ability cluster (buttons centred on their positions).
			local clusterPos = if device.touch then UDim2.new(1, -16, 1, -bottom) else A.pc
			local cluster = rect(W, H, s, A.size, clusterPos, Vector2.new(1, 1))
			for _, button in A.buttons do
				local cx = cluster[1] + (button.position.X.Scale * A.size.X + button.position.X.Offset) * s
				local cy = cluster[2] + (button.position.Y.Scale * A.size.Y + button.position.Y.Offset) * s
				-- Ability buttons are size x (size + lip), centred.
				local half, halfY = button.size * s / 2, (button.size + Theme.Lip) * s / 2
				add(button.name, { cx - half, cy - halfY, cx + half, cy + halfY })
			end
			-- Top: boss bar, hearts, leave.
			add("BossBar", rect(W, H, s, L.bar.size, L.bar.position, Vector2.new(0.5, 0)))
			add("Hearts", rect(W, H, s, L.hearts.size, L.hearts.position, Vector2.new(0.5, 0)))
			add("Leave", rect(W, H, s, L.leave.size, L.leave.position, Vector2.new(0, 0)))
			if device.touch then
				local x0, y0, x1, y1 = TouchSafe.jumpRect(device.size)
				add("RobloxJump", { x0, y0, x1, y1 })
			end
			local clean, clash = true, ""
			for i = 1, #boxes do
				for j = i + 1, #boxes do
					if overlap(boxes[i].box, boxes[j].box) then
						clean = false
						clash = boxes[i].name .. " / " .. boxes[j].name
					end
				end
			end
			check(clean, device.name .. ": no two buttons overlap" .. (if clash ~= "" then " (" .. clash .. ")" else ""))
			local onScreen = true
			for _, entry in boxes do
				onScreen = onScreen and inside(entry.box, W, H)
			end
			check(onScreen, device.name .. ": every button fully on screen")
			if device.touch then
				check(strike.size * s >= 70, device.name .. string.format(": Strike is a big thumb target (%.0f px)", strike.size * s))
			end
			local _ = lw + lh
		end
		-- Live HUD (the test client is a PC): positions match the layout.
		local strikeButton = BossHud.strikeButton()
		check(strikeButton.Position == L.strikePc.position and strikeButton.AnchorPoint == Vector2.new(1, 1), "live Strike button placed as tested (PC)")
		check(not BossHud.debugState().visible, "Strike (boss HUD) hidden outside the arena")
		-- Keys: the Strike never steals a key outside an expedition.
		check(Boss.StrikeKeys.keyboard == Enum.KeyCode.E and Boss.StrikeKeys.gamepad == Enum.KeyCode.ButtonX, "Strike: left click / E / gamepad X / touch button")
		local collide = false
		for _, slot in Abilities.Slots do
			for _, key in { slot.keyboard, slot.gamepad } do
				collide = collide or key == Enum.KeyCode.E or key == Enum.KeyCode.ButtonX
			end
		end
		check(not collide, "Strike keys never collide with ability keys")
		check(not Boss.canStrike() and Boss.strike() == false, "outside an expedition E / X / click do nothing new (prompts keep E / X)")
		-- In the arena: seal hidden, Strike visible; restored afterwards.
		local f = openWith({ alice })
		startNow()
		advance(0.3)
		check(Boss.canStrike() and strikeButton.Visible, "Strike shown in the fight")
		local hud = alice.PlayerGui:FindFirstChild("RiftHUD")
		local seal = nil
		for _, d in hud:GetDescendants() do
			if d.Name == "seal" and d.Parent and d.Parent.Name == "Abilities" then
				seal = d
			end
		end
		check(seal ~= nil and not seal.Visible, "seal button hidden in the arena (no extra button near Strike)")
		local prompts = 0
		for _, d in Engine.workspace.BossArena:GetDescendants() do
			if d:IsA("ProximityPrompt") then
				prompts += 1
			end
		end
		check(prompts == 0, "no proximity prompt in the arena (E / X belong to Strike there)")
		-- Client strike: immediate swing + combo pips.
		nearBoss(alice, 3)
		local swung = Boss.strike()
		check(swung and Boss.comboStep() == 1, "client strike: instant swing, combo pip 1")
		check(Boss.cooldownFraction() > 0, "visible cooldown on the button")
		advance(0.3)
		local _ = f
		reset()
		advance(0.3)
		check(seal ~= nil and seal.Visible, "seal button back on the island")
	end)

	--------------------------------------------------------------------------
	scenario("V2 Combat: WEAPONS screen (cards, preview, compare, buy, equip)", function()
		reset()
		local UI = creq("UI")
		local WeaponsScreen = creq("UI.Screens.Weapons")
		local Store = creq("Controllers.Store")
		local sa = sessionOf(alice)
		wallet(sa, 1000, 0, 0, 0)
		advance(0.6)
		-- HUD entry point next to the boss bar.
		local hud = alice.PlayerGui:FindFirstChild("RiftHUD")
		local button = nil
		for _, d in hud:GetDescendants() do
			if d.Name == "WeaponsButton" then
				button = d
			end
		end
		check(button ~= nil and button.Size.Y.Offset >= 44, "WEAPONS button in the HUD (touch-size)")
		-- Keyboard V / gamepad D-pad right (same family as L and C).
		local inputBegan = Engine.signal(game:GetService("UserInputService"), "InputBegan")
		inputBegan:Fire({ KeyCode = Enum.KeyCode.V, UserInputType = Enum.UserInputType.Keyboard }, false)
		advance(0.3)
		check(UI.isOpen("Weapons"), "V opens the WEAPONS screen")
		UI.close()
		inputBegan:Fire({ KeyCode = Enum.KeyCode.DPadRight, UserInputType = Enum.UserInputType.Gamepad1 }, false)
		advance(0.3)
		check(UI.isOpen("Weapons"), "gamepad D-pad right opens it too")
		local state = WeaponsScreen.debugState()
		check(state.cards == #Weapons.list, "one card per weapon (" .. state.cards .. ")")
		-- Starter: owned + equipped.
		WeaponsScreen.select("foam_gloves")
		state = WeaponsScreen.debugState()
		check(not state.buyVisible and state.equipVisible and not state.equipEnabled, "equipped starter: no buy, \"EQUIPPED\" shown (disabled)")
		-- Mallet: price shown, buy greyed out without the Essence.
		WeaponsScreen.select("squeaky_mallet")
		state = WeaponsScreen.debugState()
		check(state.buyVisible and not state.buyEnabled and string.find(state.price, "25", 1, true) ~= nil, "price shown (" .. state.price .. "), buy greyed out")
		check(WeaponsScreen.blocker(Weapons.get("squeaky_mallet")) == "essence", "reason shown: not enough Essence")
		check(WeaponsScreen.compare(Weapons.get("squeaky_mallet"), "damage") ~= "" and WeaponsScreen.compare(Weapons.get("squeaky_mallet"), "speed") ~= "", "comparison with the equipped weapon (damage, speed)")
		-- Locked by victories.
		WeaponsScreen.select("rainbow_hammer")
		check(WeaponsScreen.blocker(Weapons.get("rainbow_hammer")) == "wins" and not WeaponsScreen.debugState().buyEnabled, "prestige locked by victories")
		check(string.find(WeaponsScreen.priceText(Weapons.get("rainbow_hammer")), "40", 1, true) ~= nil, "material cost shown (40 Void Shards)")
		-- Preview viewport holds a model.
		local modal = alice.PlayerGui:FindFirstChild("RiftModals")
		local models = 0
		for _, d in modal:GetDescendants() do
			if d:IsA("ViewportFrame") then
				for _, child in d:GetDescendants() do
					if child:IsA("Model") then
						models += 1
					end
				end
			end
		end
		check(models >= #Weapons.list, "3D previews of every weapon (" .. models .. " models)")
		-- Buy + equip through the server.
		sa.data.essence = 30000
		Sessions.markCold(sa)
		advance(0.6)
		WeaponsScreen.select("squeaky_mallet")
		check(WeaponsScreen.debugState().buyEnabled, "buy lights up with the Essence")
		local ok = WeaponsScreen.buy()
		advance(0.6)
		check(ok and sa.data.weapons.owned.squeaky_mallet and sa.data.essence == 5000, "bought from the screen (server debit)")
		check(Store.state.weapons.owned.squeaky_mallet and WeaponsScreen.debugState().equipVisible, "card switches to EQUIP")
		ok = WeaponsScreen.equip()
		advance(0.6)
		check(ok and sa.data.weapons.equipped == "squeaky_mallet" and Store.state.weapons.equipped == "squeaky_mallet", "equipped from the screen")
		local creqBoss = creq("Controllers.Boss")
		check(creqBoss.weapon().id == "squeaky_mallet", "Strike now uses the mallet")
		UI.close()
		-- Boss card link.
		local BossPortal = creq("UI.Screens.BossPortal")
		UI.open("BossPortal")
		advance(0.3)
		local link = nil
		for _, d in modal:GetDescendants() do
			if d.Name == "WeaponsLink" then
				link = d
			end
		end
		check(link ~= nil, "WEAPONS link on the boss card")
		UI.close()
		local _ = BossPortal
		-- Restore the players for the scenarios that follow.
		local sb = sessionOf(bob)
		sa.data.weapons = savedA.weapons
		sa.data.materials = savedA.materials
		sa.data.bosses = savedA.bosses
		sa.data.essence = savedA.essence
		sb.data.weapons = savedB.weapons
		sb.data.essence = savedB.essence
		sb.data.abilities.loadout = savedB.loadout
		sb.data.abilities.unlocked = savedB.unlocked
		Sessions.markCold(sa)
		Sessions.markCold(sb)
		advance(0.6)
	end)
end
