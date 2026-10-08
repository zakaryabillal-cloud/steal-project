--!nocheck
-- V2 phase 6 ("First boss: Void Warden") scenarios. Called by tests/run.luau
-- with its helpers; runs on the same live server after the earlier scenarios.
--
--   * catalogue, exact loot table, formulas, telegraph minimums, no invented
--     asset id, boss relic never in the Rift;
--   * schema 5 (Codex, materials, trophies): migration, sanitising, Sync;
--   * portal cycle (announce, open 60 s, close empty, next opening);
--   * entry rules (closed, power record, relics in hand, distance, twice);
--   * Expedition protection + PvP isolation (abilities, steal checks);
--   * waiting room, ready vote, Health scaling with the participants;
--   * Strike: arena only, range, cooldown, spam, forged payloads, airborne,
--     phase shield; telegraphed attacks hitting only those who stay;
--   * hearts, KO, death, abandon, AFK, out of bounds, teleport exploit,
--     intruders, disconnects, timeout;
--   * phases + music attributes, solo and co-op victories, individual
--     rewards, contribution threshold, no double reward, duplicates;
--   * trophy pedestals (never stealable, restored on rejoin), saves;
--   * cleanup after every expedition, MovementGuard compatibility;
--   * client: boss body, telegraphs, HUD, portal card with exact chances,
--     Codex, portal board.

local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

return function(ctx)
	local scenario, check, advance, waitFor = ctx.scenario, ctx.check, ctx.advance, ctx.waitFor
	local sreq, shared, remote, Engine, Loader, game = ctx.sreq, ctx.shared, ctx.remote, ctx.Engine, ctx.Loader, ctx.game
	local sessionOf, teleport, insideOwnPlot, plotCenter = ctx.sessionOf, ctx.teleport, ctx.insideOwnPlot, ctx.plotCenter
	local hasNotification, clearLog = ctx.hasNotification, ctx.clearLog
	local alice, bob = ctx.alice(), ctx.bob()

	local Sessions = sreq("Core.Sessions")
	local Snapshot = sreq("Core.Snapshot")
	local DataSchema = sreq("Core.DataSchema")
	local Rolls = sreq("Core.Rolls")
	local Expeditions = sreq("Core.Expeditions")
	local BossService = sreq("Services.BossService")
	local TrophyService = sreq("Services.TrophyService")
	local StealService = sreq("Services.StealService")
	local PlotService = sreq("Services.PlotService")
	local RelicService = sreq("Services.RelicService")
	local AbilityService = sreq("Services.AbilityService")
	local EconomyService = sreq("Services.EconomyService")
	local Common = sreq("Abilities.Common")
	local VoidWarden = sreq("Bosses.VoidWarden")
	local ArenaBuilder = sreq("World.ArenaBuilder")
	local Bosses = shared("Config.Bosses")
	local Weapons = shared("Config.Weapons")
	local Materials = shared("Config.Materials")
	local Relics = shared("Config.Relics")
	local Cosmetics = shared("Config.Cosmetics")
	local Music = shared("Config.Music")
	local GameConfig = shared("Config.GameConfig")
	local WorldFeatures = shared("WorldFeatures")
	local Layout = shared("Layout")
	local Strings = shared("Locale.Strings")
	local RelicFaces = shared("Relics.RelicFaces")
	local RelicShapes = shared("Relics.RelicShapes")
	local STORE = GameConfig.Data.StoreName .. "/u_"

	local Client = game:GetService("StarterPlayer").StarterPlayerScripts.Client
	local function creq(path)
		local node = Client
		for part in string.gmatch(path, "[^%.]+") do
			node = node:FindFirstChild(part)
		end
		return Loader.require("client", node)
	end

	local Random = Engine.Random
	local DEF = Bosses.get("VoidWarden")
	local ARENA = Bosses.Arena
	local FLOOR = ARENA.Center.Y

	local function now()
		return Engine.workspace:GetServerTimeNow()
	end
	local function root(player)
		return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	end
	local function humanoid(player)
		return player.Character and player.Character:FindFirstChild("Humanoid")
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
	local function fxCount(player, kind)
		local n = 0
		for _, entry in Engine.clientLog[player] or {} do
			if entry.remote == "FX" and entry.args[1] == kind then
				n += 1
			end
		end
		return n
	end
	local function lastFx(player, kind)
		local found = nil
		for _, entry in Engine.clientLog[player] or {} do
			if entry.remote == "FX" and entry.args[1] == kind then
				found = entry.args[2]
			end
		end
		return found
	end
	local function plateauModel()
		return Engine.workspace.World.Landmarks.BossPlateau
	end
	-- Standing on the plateau, 12 studs in front of the portal ring.
	local function atPortal(player, k)
		local spec = WorldFeatures.BossPlateau
		local p = WorldFeatures.polar(spec.deg + ((k or 0) % 5 - 2) * 1.2, spec.portalR - 12, spec.top + 3)
		teleport(player, p)
		advance(0.1)
	end
	local function inArena(player)
		local r = root(player)
		return r ~= nil and ArenaBuilder.inside(r.Position)
	end
	-- Floor point of the arena (offset from the centre), standing height.
	local function arenaPoint(dx, dz, lift)
		return Vector3.new(ARENA.Center.X + dx, FLOOR + 3 + (lift or 0), ARENA.Center.Z + dz)
	end
	local function fight()
		return BossService.state()
	end
	-- No automatic attack (deterministic checks).
	local function calm()
		local f = fight()
		if f then
			f.nextAttackAt = math.huge
			f.plan = nil
			if f.motion then
				-- Land him where the hop was going.
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
	-- Next to the boss (in front), standing on the floor.
	local function nextToBoss(player, side)
		local f = fight()
		local a = f.anchor.Position
		local p = Vector3.new(a.X + (side or 0) * 4, FLOOR + 3, a.Z - 12)
		Engine.moveTo(player, p)
		local s = sessionOf(player)
		s.lastPosition = nil
	end
	local function strikes(player, count)
		local landed = 0
		for _ = 1, count do
			nextToBoss(player)
			local ok = BossService.strike(player)
			if ok then
				landed += 1
			end
			advance(0.41)
			local f = fight()
			if not f or f.state ~= "Fight" then
				break
			end
		end
		return landed
	end
	-- Opens a fresh expedition and puts `players` in the arena.
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
	local function forceDrops(value)
		BossService.setRandom(function()
			return {
				NextNumber = function()
					return value
				end,
				NextInteger = function(_, a, b)
					return if value < 0.5 then b else a
				end,
			}
		end)
	end

	local cleo, dino = nil, nil
	local function newPlayer(name, id)
		local player = Engine.addPlayer(name, id)
		waitFor(function()
			local s = sessionOf(player)
			return s ~= nil and s.loaded and player.Character ~= nil
		end, 6)
		local s = sessionOf(player)
		s.data.power.peak = math.max(s.data.power.peak, 200)
		s.data.playTime = GameConfig.Steal.NoviceSeconds + 10
		return player
	end

	--------------------------------------------------------------------------
	scenario("V2 Bosses: catalogue, exact loot table, formulas, no invented asset", function()
		reset()
		check(#Bosses.list == 1 and DEF ~= nil, "exactly one boss for now: the Void Warden (no Phase 7 boss)")
		check(Bosses.Portal.Interval == 600 and Bosses.Portal.OpenDuration == 60, "portal every 10 min, open 60 s")
		check(Bosses.Combat.Duration == 210, "fight limited to 3:30")
		local kinds, specials = {}, 0
		for id, attack in DEF.attacks do
			local minimum = if attack.big then Bosses.Combat.BigTelegraph else Bosses.Combat.MinTelegraph
			check(attack.telegraph >= minimum and minimum >= 0.8, "attack " .. id .. " telegraphed >= " .. minimum .. " s")
			kinds[id] = true
			if attack.big then
				specials += 1
			end
		end
		check(kinds.broom_wave and kinds.goo_puddles and kinds.dust_bunnies and kinds.belly_flop and kinds.big_cleanup, "ring wave, ground zones, projectiles, hop and the special")
		check(specials == 1 and DEF.phases[1].special == nil and DEF.phases[2].special == "big_cleanup", "the special only from phase 2")
		check(#DEF.phases == 3 and DEF.phases[2].from == 0.6 and DEF.phases[3].from == 0.25, "3 phases (100-60-25 %)")
		-- Loot table.
		local byId = {}
		for _, entry in DEF.loot do
			byId[entry.id] = entry
		end
		check(byId.essence and byId.essence.chance == 1 and byId.essence.minutes == 5, "Essence: 100 %, 5 min of the player's production")
		check(byId.void_shard and byId.void_shard.chance == 1 and byId.void_shard.min == 3 and byId.void_shard.max == 6, "Void Shards: 100 %, 3-6")
		check(byId.void_catalyst and byId.void_catalyst.chance == 0.15 and byId.void_catalyst.rare, "rare catalyst: 15 %")
		check(byId.void_duster and byId.void_duster.chance == 0.08 and Relics.get("void_duster").bossOnly == "VoidWarden", "exclusive relic: 8 %, boss only")
		check(byId.trail_bubbles and byId.trail_bubbles.chance == 0.05 and Cosmetics.get("trail_bubbles").unlock.kind == "boss", "exclusive cosmetic: 5 %, boss source")
		check(Bosses.percent(0.08) == "8 %" and Bosses.percent(1) == "100 %" and Bosses.percent(0.125) == "12.5 %" and Bosses.percent(0.0525) == "5.25 %", "exact percentages shown with every digit")
		check(Materials.get("void_shard") and Materials.get("void_catalyst") and #Materials.PlannedRecipes >= 1, "materials ready for the future Forge")
		-- Formulas.
		check(Bosses.maxHealth(DEF, 1) == 1500 and Bosses.maxHealth(DEF, 2) == 2550 and Bosses.maxHealth(DEF, 4) == 4650, "Health scales with participants (+70 % each)")
		check(Bosses.powerBonus(0) == 0 and math.abs(Bosses.powerBonus(750) - 0.125) < 1e-9 and Bosses.powerBonus(1e9) == Bosses.Strike.PowerBonusCap, "Power bonus linear then capped at +25 %")
		check(Bosses.strikeDamage(0, false) == 10 and Bosses.strikeDamage(1e9, false) == 12.5 and Bosses.strikeDamage(0, true) == 15, "strike damage (Power bonus, dizzy x1.5)")
		check(Bosses.eligibleDamage(1500, 1) == 300 and math.abs(Bosses.eligibleDamage(Bosses.maxHealth(DEF, 4), 4) - 232.5) < 1e-6, "contribution threshold = 20 % of a fair share")
		check(Bosses.phaseAt(DEF, 1) == 1 and Bosses.phaseAt(DEF, 0.6) == 2 and Bosses.phaseAt(DEF, 0.25) == 3 and Bosses.phaseAt(DEF, 0.01) == 3, "phase from Health")
		check(Bosses.trophySlots(0) == 1 and Bosses.trophySlots(400) == 2 and Bosses.trophySlots(900) == 3, "trophy pedestals 1-3 by Power record")
		check(Bosses.canEnter(DEF, 25) and not Bosses.canEnter(DEF, 24) and DEF.recommendedPower == 150, "Power record gate 25, recommended 150")
		check(Bosses.essenceReward(DEF.loot[1], 0) == 250 and Bosses.essenceReward(DEF.loot[1], 10) == 3000, "Essence reward = 5 min of production (floor 250)")
		-- A solo beginner can win in time: strikes needed vs fight length.
		local hits = Bosses.maxHealth(DEF, 1) / Bosses.strikeDamage(0, false)
		check(hits * Bosses.Strike.Cooldown <= Bosses.Combat.Duration * 0.4, string.format("solo beginner: %.0f s of hitting fits in 40 %% of the fight", hits * Bosses.Strike.Cooldown))
		-- The boss relic never comes out of the Rift.
		local rng = Random.new(7)
		local seen = false
		for _ = 1, 4000 do
			if Rolls.relic(rng, "Legendary", nil).id == "void_duster" or Rolls.spawn(rng, "Eclipse").relicId == "void_duster" then
				seen = true
			end
		end
		check(not seen, "4000 Legendary / Eclipse rolls: never the boss relic")
		check(RelicShapes.VoidDuster ~= nil and RelicFaces.get("void_duster") ~= nil, "boss relic has a cartoon shape and a face")
		-- Strings and assets.
		for _, lang in { "en", "fr" } do
			local t = Strings[lang]
			local missing = {}
			for _, key in { "boss.VoidWarden.name", "boss.VoidWarden.title", "boss.VoidWarden.lore", "boss.enter", "boss.strike", "boss.victory", "boss.defeat", "boss.codex.title", "block.expedition", "deny.arena", "n.bossOpen", "relic.void_duster.name", "cos.trail_bubbles", "mat.void_shard", "mat.void_catalyst", "trophy.label", "prompt.boss", "boss.portal.open", "boss.portal.dormant", "boss.portal.fight" } do
				if not t[key] then
					table.insert(missing, key)
				end
			end
			for id in DEF.attacks do
				if not t["boss.attack." .. id] then
					table.insert(missing, "boss.attack." .. id)
				end
			end
			check(#missing == 0, lang .. ": boss strings present (" .. table.concat(missing, ", ") .. ")")
		end
		local invented = {}
		for _, path in { "src/shared/Config/Bosses.luau", "src/shared/Config/Materials.luau", "src/server/Services/BossService.luau", "src/server/World/ArenaBuilder.luau", "src/client/Controllers/BossFX.luau", "src/client/Boss/VoidWardenModel.luau", "src/client/UI/Screens/BossHud.luau", "src/client/UI/Screens/BossPortal.luau", "src/client/UI/Screens/BossCodex.luau" } do
			if string.find(fs.readFile(path), "rbxassetid", 1, true) then
				table.insert(invented, path)
			end
		end
		check(#invented == 0, "no asset id in the boss code (" .. table.concat(invented, ", ") .. ")")
		local silent = true
		for _, key in { "Boss.VoidWarden.1", "Boss.VoidWarden.2", "Boss.VoidWarden.3", "Stinger.BossIntro", "Stinger.BossVictory", "Stinger.BossDefeat" } do
			local track = Music.track(key)
			if not track or track.id ~= "" then
				silent = false
			end
		end
		check(silent, "boss music slots stay empty (fallback, nothing invented)")
		check(Music.track("Explore").id == "rbxassetid://9046476113" and Music.track("Chase").id == "rbxassetid://9046474891", "the phase 3 music ids are untouched")
	end)

	--------------------------------------------------------------------------
	scenario("V2 Bosses: schema 5 migration, sanitising, newer-schema guard, Sync", function()
		-- Phase 6.5 bumped the schema to 6 (weapons): the boss data stays, the
		-- checks follow the current version.
		check(DataSchema.Version >= 5 and GameConfig.Data.SchemaVersion == DataSchema.Version, "schema 5 or later (" .. DataSchema.Version .. ")")
		local phase5 = {
			schema = 4,
			essence = 777,
			lifetimeEssence = 999,
			power = { peak = 321 },
			relics = { { uid = "a1", id = "storm_crystal", level = 2, slot = 1 } },
			cosmetics = { owned = { trail_riftwake = true }, equipped = { trail = "trail_riftwake" } },
			abilities = { unlocked = { dash = true, pulse = true }, loadout = { "dash", "pulse", "" }, harmonyOff = {} },
		}
		local data = DataSchema.normalize(deepCopy(phase5))
		check(data.schema == DataSchema.Version and next(data.bosses) == nil and next(data.materials) == nil and #data.trophies == 0, "phase 5 save -> empty Codex, no material, no trophy")
		check(data.essence == 777 and data.power.peak == 321 and #data.relics == 1 and data.cosmetics.owned.trail_riftwake, "nothing lost from phase 5")
		check(phase5.schema == 4 and phase5.bosses == nil, "the stored record is never mutated")
		local tampered = deepCopy(phase5)
		tampered.schema = 5
		tampered.bosses = {
			VoidWarden = { discovered = "yes", attempts = 3, wins = 9, bestTime = -5, rare = { void_duster = 2, essence = 5, nope = 1 }, lastFight = string.rep("x", 90) },
			FakeBoss = { attempts = 5 },
			[7] = true,
		}
		tampered.materials = { void_shard = 12.7, void_catalyst = -3, gold = 99, [1] = 4 }
		tampered.trophies = {
			{ uid = "t1", id = "void_duster", level = 99, slot = 9 },
			{ uid = "t2", id = "void_duster", level = 1, slot = 2 },
			{ uid = "t3", id = "storm_crystal", level = 1, slot = 2 },
			"garbage",
		}
		table.insert(tampered.relics, { uid = "a2", id = "void_duster", level = 1, slot = 2 })
		local clean = DataSchema.normalize(tampered)
		local vw = clean.bosses.VoidWarden
		check(vw and vw.attempts == 3 and vw.wins == 3 and vw.bestTime == 0 and vw.discovered == true, "wins clamped to attempts, bad best time dropped, attempts imply discovery")
		check(vw.rare.void_duster == 2 and vw.rare.essence == nil and vw.rare.nope == nil and #vw.lastFight <= 40, "only rare loot ids kept; fight id bounded")
		check(clean.bosses.FakeBoss == nil and clean.bosses[7] == nil, "unknown bosses dropped")
		check(clean.materials.void_shard == 12 and clean.materials.void_catalyst == nil and clean.materials.gold == nil and clean.materials[1] == nil, "materials: known ids, whole, never negative")
		check(#clean.trophies == 1 and clean.trophies[1].id == "void_duster" and clean.trophies[1].level == GameConfig.Economy.MaxRelicLevel and clean.trophies[1].slot >= 1 and clean.trophies[1].slot <= 3, "trophies: boss relics only, one per relic, level and slot sanitised")
		local onPedestal = false
		for _, relic in clean.relics do
			if relic.id == "void_duster" then
				onPedestal = true
			end
		end
		check(not onPedestal, "a boss relic can never sit on a normal (stealable) pedestal")
		local round = DataSchema.normalize(DataSchema.serialize(clean))
		check(round.bosses.VoidWarden.wins == 3 and round.materials.void_shard == 12 and #round.trophies == 1 and round.bosses.VoidWarden.lastFight == clean.bosses.VoidWarden.lastFight, "serialize -> normalize round trip is lossless")
		-- Newer schema: never touched.
		local future = { schema = DataSchema.Version + 1, essence = 1, bosses = { NewBoss = {} } }
		Engine.dataStoreData[STORE .. "6363"] = deepCopy(future)
		local player = Engine.addPlayer("FutureBoss", 6363)
		advance(3)
		local s = sessionOf(player)
		check(s and s.dataStatus == "newer" and s.canSave == false, "newer-schema save: temporary data, saving disabled")
		Engine.removePlayer(player)
		advance(2)
		check(Engine.dataStoreData[STORE .. "6363"].schema == DataSchema.Version + 1 and Engine.dataStoreData[STORE .. "6363"].bosses.NewBoss ~= nil, "newer record untouched")
		-- Sync: cold half carries the Codex (without the anti-replay id).
		local sa = sessionOf(alice)
		local cold = Snapshot.cold(sa)
		check(type(cold.bosses) == "table" and type(cold.materials) == "table" and type(cold.trophies) == "table", "Codex, materials and trophies are synced (cold)")
		check(table.find(Snapshot.ColdKeys, "bosses") and table.find(Snapshot.ColdKeys, "materials") and table.find(Snapshot.ColdKeys, "trophies"), "cold keys documented")
		sa.data.bosses.VoidWarden = DataSchema.newBossRecord()
		sa.data.bosses.VoidWarden.lastFight = "secret"
		check(Snapshot.codexView(sa).VoidWarden.lastFight == nil, "the anti-replay fight id never reaches the client")
		sa.data.bosses.VoidWarden = nil
		Sessions.markCold(sa)
		advance(0.3)
	end)

	--------------------------------------------------------------------------
	scenario("V2 Bosses: portal cycle (announce, open 60 s, close empty, next opening)", function()
		reset()
		clearLog(alice)
		local start = now()
		BossService.setNextOpen(start + 31)
		check(plateauModel():GetAttribute("PortalState") == "Dormant" and math.abs(plateauModel():GetAttribute("PortalOpensAt") - (start + 31)) < 0.01, "portal dormant with its countdown")
		advance(2)
		check(hasNotification(alice, "n.bossSoon"), "announced 30 s before")
		check(waitFor(function()
			return fight() ~= nil
		end, 31), "opens on time")
		local f = fight()
		check(f.state == "Open" and plateauModel():GetAttribute("PortalState") == "Open", "portal open")
		check(math.abs(plateauModel():GetAttribute("PortalClosesAt") - (f.openedAt + 60)) < 0.01, "open for 60 s (countdown published)")
		check(math.abs(BossService.nextOpenAt() - (f.openedAt + 600)) < 0.01, "next opening 10 min after this one")
		check(hasNotification(alice, "n.bossOpen"), "everyone told it is open")
		local arena = Engine.workspace:FindFirstChild("BossArena")
		local parts, lights, emitters = 0, 0, 0
		for _, d in arena:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
			elseif d:IsA("PointLight") then
				lights += 1
			elseif d:IsA("ParticleEmitter") then
				emitters += 1
			end
		end
		check(arena ~= nil and parts <= ARENA.PartBudget and lights <= 2 and emitters <= 1, string.format("arena built within budget (%d parts, %d lights, %d emitter)", parts, lights, emitters))
		-- Static world (same rule as the V2 World budget test) + the arena.
		local world = 0
		for _, d in Engine.workspace:GetDescendants() do
			if d:IsA("BasePart") and not d:IsDescendantOf(arena) then
				local node, skip = d.Parent, false
				while node and node ~= Engine.workspace do
					if node.Name == "Relics" or node.Name == "Barrier" or node.Name == "ClientRelics" or node.Name == "ClientBoss" or node.Name == "Abilities" or node:FindFirstChildOfClass("Humanoid") then
						skip = true
						break
					end
					node = node.Parent
				end
				if not skip then
					world += 1
				end
			end
		end
		check(world + parts <= GameConfig.World.PartBudget, string.format("world + arena within the part budget (%d + %d <= %d)", world, parts, GameConfig.World.PartBudget))
		check(arena.Boss and arena.Boss.Transparency == 1 and arena.Boss.CanCollide == false, "the server boss is an invisible anchor (clients draw him)")
		advance(61)
		check(fight() == nil and Engine.workspace:FindFirstChild("BossArena") == nil, "nobody came: the arena is destroyed")
		check(plateauModel():GetAttribute("PortalState") == "Dormant", "portal dormant again")
		reset()
	end)

	--------------------------------------------------------------------------
	scenario("V2 Bosses: entry rules (closed, power record, relics in hand, distance, twice)", function()
		reset()
		local sa = sessionOf(alice)
		sa.data.power.peak = math.max(sa.data.power.peak, 200)
		atPortal(alice)
		local ok, reason = BossService.join(alice)
		check(not ok and reason == "closed", "closed portal refuses")
		BossService.open()
		advance(0.1)
		insideOwnPlot(alice)
		ok, reason = BossService.join(alice)
		check(not ok and reason == "far", "must stand at the portal")
		atPortal(alice)
		local peak = sa.data.power.peak
		sa.data.power.peak = DEF.minPowerRecord - 1
		ok, reason = BossService.join(alice)
		check(not ok and reason == "power", "Power record below the gate refuses")
		sa.data.power.peak = peak
		table.insert(sa.carrying, "fake-uid")
		ok, reason = BossService.join(alice)
		check(not ok and reason == "carrying", "relics in hand: entry refused (nothing lost or duplicated)")
		table.clear(sa.carrying)
		check(not Expeditions.isAway(sa), "refusals change nothing")
		ok, reason = Engine.invokeServer(remote("BossJoin"), alice)
		check(ok == true, "join through the remote (" .. tostring(reason) .. ")")
		advance(0.3)
		check(inArena(alice), "teleported into the arena")
		check(Expeditions.of(sa) == fight().id, "registered as away on the expedition")
		check(alice:GetAttribute("BossFight") == fight().id and alice:GetAttribute("BossHearts") == Bosses.Combat.Hearts, "player attributes for the HUD")
		check(sa.data.bosses.VoidWarden and sa.data.bosses.VoidWarden.discovered == true, "Codex: boss discovered")
		ok, reason = BossService.join(alice)
		check(not ok and reason == "already", "cannot join twice")
		check(plateauModel():GetAttribute("PortalCount") == 1, "portal shows who is inside")
		-- Leaving the waiting room is free (not an attempt).
		BossService.leave(alice)
		advance(0.3)
		check(not inArena(alice) and not Expeditions.isAway(sa) and alice:GetAttribute("BossFight") == nil, "left the waiting room: back on the plateau")
		ok, reason = BossService.join(alice)
		check(ok, "can come back while the portal is open (" .. tostring(reason) .. ")")
		reset()
		check(not Expeditions.isAway(sa) and not inArena(alice), "reset sends everyone back")
	end)

	--------------------------------------------------------------------------
	scenario("V2 Bosses: Expedition protection and PvP isolation", function()
		cleo = newPlayer("Cleo", 8801)
		local sa, sc = sessionOf(alice), sessionOf(cleo)
		-- Alice needs a robbable collection for the check to matter.
		local placed = RelicService.placedBy(alice.UserId)
		check(#placed >= 1, "Alice has relics on display (" .. #placed .. ")")
		openWith({ alice })
		local plot = PlotService.get(sa.plot)
		local kind = PlotService.protection(plot)
		check(kind == "Expedition", "Sanctuary protected while its owner is on the expedition (" .. tostring(kind) .. ")")
		advance(0.5)
		check(plot.model:GetAttribute("Protection") == "Expedition", "protection published for the lock hints")
		local target = placed[1]
		teleport(cleo, target.anchor.Position + Vector3.new(0, -2, 3))
		advance(0.2)
		local allowed, why = StealService.check(sc, target)
		check(not allowed and why == "block.expedition", "a thief is told the owner is fighting a boss (" .. tostring(why) .. ")")
		-- PvP isolation: nothing crosses the expedition border.
		check(not Common.canAffect(sc, sa) and not Common.canAffect(sa, sc), "abilities never cross the expedition border")
		local list = Common.targets(sc, root(alice).Position, 100, false)
		local found = false
		for _, t in list do
			if t.session == sa then
				found = true
			end
		end
		check(not found, "Alice is never an ability target while away")
		-- Phase 6.5: every PvP ability works in the arena again, but only
		-- against the boss (isolation above stays).
		local used, reason = AbilityService.use(alice, "pulse", nil)
		check(reason ~= "arena", "PvP abilities usable inside the arena, boss only (" .. tostring(used) .. " " .. tostring(reason) .. ")")
		local dashOk, dashReason = AbilityService.use(alice, "dash", nil)
		check(dashReason ~= "arena", "movement abilities still allowed in the arena (" .. tostring(dashOk) .. " " .. tostring(dashReason) .. ")")
		-- Protection ends with the expedition.
		BossService.leave(alice)
		advance(0.5)
		check(PlotService.protection(plot) ~= "Expedition", "protection ends when she leaves")
		reset()
	end)

	--------------------------------------------------------------------------
	scenario("V2 Bosses: waiting room, ready vote, Health scaled to the group", function()
		local sa, sb = sessionOf(alice), sessionOf(bob)
		sb.data.power.peak = math.max(sb.data.power.peak, 200)
		local attemptsA = (sa.data.bosses.VoidWarden and sa.data.bosses.VoidWarden.attempts) or 0
		clearLog(alice)
		local f = openWith({ alice, bob })
		check(f.state == "Open" and #f.participants == 2, "two in the waiting room")
		BossService.ready(alice)
		advance(0.2)
		check(f.state == "Open" and f.closesAt > now() + 10, "one ready is not enough")
		Engine.fireServer(remote("BossReady"), bob)
		advance(0.2)
		check(f.closesAt <= now() + Bosses.Portal.ReadyCountdown, "everyone ready: starts in 3 s")
		advance(Bosses.Portal.ReadyCountdown + 0.2)
		check(f.state == "Intro", "the fight begins with the boss entrance")
		check(f.maxHp == Bosses.maxHealth(DEF, 2) and f.hp == f.maxHp, "Health for 2 players: " .. f.maxHp)
		check(sa.data.bosses.VoidWarden.attempts == attemptsA + 1, "Codex: one more attempt")
		check(alice:GetAttribute("MusicBoss") == "VoidWarden" and alice:GetAttribute("MusicBossPhase") == 1, "boss music state set (MusicDirector)")
		check(fxCount(alice, "BossStart") == 1, "start announced to the fighters")
		check(plateauModel():GetAttribute("PortalState") == "Fight", "portal closed during the fight")
		local ok, reason = BossService.join(bob)
		check(not ok and (reason == "fighting" or reason == "already"), "nobody joins a fight in progress")
		local struck, why = BossService.strike(alice)
		check(not struck and why == "notYet", "no strike during the entrance")
		advance(Bosses.Combat.Intro + 0.2)
		check(f.state == "Fight", "fight on")
		reset()
	end)

	--------------------------------------------------------------------------
	scenario("V2 Bosses: Strike is arena-only and server-validated", function()
		local sa = sessionOf(alice)
		dino = newPlayer("Dino", 8802)
		local f = openWith({ alice })
		startNow()
		local struck, why = BossService.strike(dino)
		check(not struck and why == "arena", "Strike does not exist outside the arena")
		Engine.moveTo(alice, arenaPoint(-45, -10))
		sa.lastPosition = nil
		struck, why = BossService.strike(alice)
		check(not struck and why == "range", "too far from the boss")
		local before = f.hp
		nextToBoss(alice)
		struck = BossService.strike(alice)
		check(struck and math.abs((before - f.hp) - Bosses.strikeDamage(sa.power, false)) < 1e-6, "a strike in range deals the server's damage")
		struck, why = BossService.strike(alice)
		check(not struck and why == "cooldown", "cooldown enforced on the server")
		-- Spam + forged payloads through the remote.
		local hpBefore, hitsBefore = f.hp, BossService.participant(alice).hits
		clearLog(alice)
		for _ = 1, 30 do
			Engine.fireServer(remote("BossStrike"), alice, 1e9, "kill", Vector3.new(0, 0, 0))
			advance(0.03)
		end
		local hits = BossService.participant(alice).hits - hitsBefore
		check(hits <= 3, "30 spammed strikes in ~1 s: at most 3 count (" .. hits .. ")")
		-- Phase 6.5: each hit follows the equipped weapon's combo step.
		local expected = 0
		for _, entry in Engine.clientLog[alice] or {} do
			if entry.remote == "FX" and entry.args[1] == "BossStruck" then
				local w = Weapons.get(entry.args[2].weapon)
				expected += Bosses.hitDamage(w.damage, sa.power, w.combo[entry.args[2].combo])
			end
		end
		check(expected > 0 and math.abs((hpBefore - f.hp) - expected) < 1e-6, "forged payloads ignored: damage = server formula")
		-- Untouchable moments.
		advance(0.5)
		f.motion = { from = f.anchor.Position, to = f.anchor.Position, startAt = now() - 0.1, endAt = now() + 5, height = 20 }
		nextToBoss(alice)
		struck, why = BossService.strike(alice)
		check(not struck and why == "air", "cannot hit him mid-hop")
		f.motion = nil
		f.bossInvulnerableUntil = now() + 5
		struck, why = BossService.strike(alice)
		check(not struck and why == "shield", "phase-change show: untouchable")
		f.bossInvulnerableUntil = 0
		-- Power never changes PvP, only this: the bonus is capped.
		check(Bosses.strikeDamage(1e12, false) <= Bosses.Strike.Damage * (1 + Bosses.Strike.PowerBonusCap) + 1e-9, "Power bonus capped (+25 %)")
		reset()
	end)

	--------------------------------------------------------------------------
	scenario("V2 Bosses: every attack is telegraphed, then hits only who stays", function()
		local sa, sb = sessionOf(alice), sessionOf(bob)
		local f = openWith({ alice, bob })
		startNow()
		-- Each planner: shapes never hurt before the telegraph.
		local view = {
			boss = DEF,
			phase = 3,
			participants = 2,
			center = ARENA.Center,
			floorY = FLOOR,
			radius = ARENA.Radius,
			bossPosition = f.anchor.Position,
			targets = { arenaPoint(10, 0, -3), arenaPoint(-10, 5, -3) },
			rng = Random.new(3),
		}
		for id, attack in DEF.attacks do
			local plan = VoidWarden.plan(view, id, 100)
			local earliest = math.huge
			for _, shape in plan.shapes do
				earliest = math.min(earliest, shape.at)
				local inside = (Vector3.new(shape.center.X, 0, shape.center.Z) - Vector3.new(ARENA.Center.X, 0, ARENA.Center.Z)).Magnitude <= ARENA.Radius + 1
				check(inside, id .. ": shape inside the arena")
			end
			local minimum = if attack.big then Bosses.Combat.BigTelegraph else Bosses.Combat.MinTelegraph
			check(plan.hitAt - plan.telegraphAt >= minimum - 1e-9 and earliest >= plan.hitAt - 1e-9, id .. ": no damage before " .. minimum .. " s of warning")
			check(plan.payload ~= nil and plan.action ~= nil, id .. ": clients get what they need to draw it")
		end
		-- Ring: grounded fighter hit, jumping fighter safe.
		local origin = Vector3.new(ARENA.Center.X, FLOOR, ARENA.Center.Z)
		local t = now()
		table.insert(f.shapes, { kind = "ring", at = t + 0.2, center = origin, radius = 70, speed = 30, band = 3, resolved = {} })
		Engine.moveTo(alice, arenaPoint(20, 0))
		Engine.moveTo(bob, arenaPoint(-20, 0, 5))
		sa.lastPosition, sb.lastPosition = nil, nil
		advance(0.5)
		check(BossService.participant(alice).hearts == Bosses.Combat.Hearts and BossService.participant(bob).hearts == Bosses.Combat.Hearts, "nothing happens before the wave arrives")
		advance(0.6)
		check(BossService.participant(alice).hearts == Bosses.Combat.Hearts - 1, "grounded fighter swept by the broom wave")
		check(BossService.participant(bob).hearts == Bosses.Combat.Hearts, "jumping fighter clears it")
		check(fxCount(alice, "BossHit") >= 1 and lastFx(alice, "BossHit").userId == alice.UserId, "hit announced (BONK!)")
		-- Invulnerability after a hit.
		table.insert(f.shapes, { kind = "circle", at = now() + 0.1, center = Vector3.new(root(alice).Position.X, FLOOR, root(alice).Position.Z), radius = 6, resolved = {} })
		advance(0.3)
		check(BossService.participant(alice).hearts == Bosses.Combat.Hearts - 1, "1.5 s of invulnerability after a hit")
		advance(1.5)
		-- Puddles: the one inside is hit, the one who stepped out is not; goo slows.
		Engine.moveTo(bob, arenaPoint(-20, 0))
		sb.lastPosition = nil
		local spot = Vector3.new(root(bob).Position.X, FLOOR, root(bob).Position.Z)
		table.insert(f.shapes, { kind = "circle", at = now() + 0.3, center = spot, radius = 6, resolved = {} })
		table.insert(f.shapes, { kind = "zone", at = now() + 0.3, untilTime = now() + 4, center = spot, radius = 6, slow = 0.45, resolved = {} })
		Engine.moveTo(alice, spot + Vector3.new(14, 3, 0))
		sa.lastPosition = nil
		advance(0.6)
		check(BossService.participant(bob).hearts == Bosses.Combat.Hearts - 1 and BossService.participant(alice).hearts == Bosses.Combat.Hearts - 1, "only the fighter in the puddle is hit")
		check(sb.status.slows and sb.status.slows.goo ~= nil, "sticky goo slows the one standing in it")
		advance(2)
		-- Big Cleanup: the safe quarter is safe.
		table.insert(f.shapes, { kind = "sector", at = now() + 0.2, center = origin, radius = 80, safeAngle = 0, safeWidth = math.pi / 2, resolved = {} })
		Engine.moveTo(alice, arenaPoint(30, 2))
		Engine.moveTo(bob, arenaPoint(-30, 2))
		sa.lastPosition, sb.lastPosition = nil, nil
		advance(0.5)
		check(BossService.participant(alice).hearts == Bosses.Combat.Hearts - 1, "the sparkly quarter is safe")
		check(BossService.participant(bob).hearts == Bosses.Combat.Hearts - 2, "the mopped quarters are not")
		-- The automatic pattern sends one telegraph message per attack.
		clearLog(alice)
		f.nextAttackAt = now()
		advance(0.3)
		local payload = lastFx(alice, "BossAttack")
		check(payload and payload.attack and payload.hitAt - payload.telegraphAt >= Bosses.Combat.MinTelegraph - 1e-9 and payload.data ~= nil, "attack message: kind, telegraph time, impact time, shape data")
		-- Client draws it.
		local BossFX = creq("Controllers.BossFX")
		local BossHud = creq("UI.Screens.BossHud")
		advance(0.2)
		local state = BossFX.debugState()
		check(state.rig and state.visuals > 0, "client: the boss body is built and the telegraph drawn (" .. state.visuals .. " visuals)")
		check(BossHud.debugState().visible and BossHud.debugState().banner ~= "", "client: boss HUD visible with the attack hint")
		reset()
	end)

	--------------------------------------------------------------------------
	scenario("V2 Bosses: hearts, KO, death, wiped party, codex attempt kept", function()
		local sa, sb = sessionOf(alice), sessionOf(bob)
		local winsBefore = (sa.data.bosses.VoidWarden and sa.data.bosses.VoidWarden.wins) or 0
		local f = openWith({ alice, bob })
		startNow()
		clearLog(alice)
		-- Alice loses every heart.
		for _ = 1, Bosses.Combat.Hearts do
			local p = root(alice).Position
			table.insert(f.shapes, { kind = "circle", at = now(), center = Vector3.new(p.X, FLOOR, p.Z), radius = 6, resolved = {} })
			advance(Bosses.Combat.HitInvulnerability + 0.2)
		end
		local pa = BossService.participant(alice)
		check(pa.hearts == 0 and pa.status == "ko", "no heart left: KO")
		check(not Expeditions.isAway(sa), "KO ends the Expedition protection")
		check(fxCount(alice, "BossKO") >= 1, "KO announced (dizzy stars)")
		advance(1.6)
		check(not inArena(alice) and alice:GetAttribute("BossFight") == nil and alice:GetAttribute("MusicBoss") == nil, "sent back to the plateau, attributes cleared")
		check(f.state == "Fight", "the fight goes on for Bob")
		-- Bob dies (reset): counts like a KO.
		humanoid(bob).Health = 0
		advance(0.3)
		check(BossService.participant(bob).status == "dead" and not Expeditions.isAway(sb), "a death leaves the fight cleanly")
		advance(0.2)
		check(f.state == "Defeat" and f.reason == "wiped", "everyone down: defeat")
		local ended = lastFx(alice, "BossEnd")
		check(ended and ended.result == "Defeat" and #ended.rewards == 0, "results sent even after a KO, no reward")
		check(sa.data.bosses.VoidWarden.wins == winsBefore, "no win recorded")
		advance(Bosses.Combat.Outro + 0.5)
		check(fight() == nil and Engine.workspace:FindFirstChild("BossArena") == nil, "arena cleaned after the outro")
		advance(GameConfig.Player.RespawnDelay + 1)
		reset()
	end)

	--------------------------------------------------------------------------
	scenario("V2 Bosses: solo victory, phases, music, rewards once, trophy, save", function()
		local sa = sessionOf(alice)
		local before = deepCopy(sa.data.bosses.VoidWarden or DataSchema.newBossRecord())
		local essenceBefore = sa.data.essence
		local shardsBefore = sa.data.materials.void_shard or 0
		sa.data.cosmetics.owned.trail_bubbles = nil
		for i = #sa.data.trophies, 1, -1 do
			table.remove(sa.data.trophies, i)
		end
		for _, entity in RelicService.trophiesOf(alice.UserId) do
			RelicService.vanish(entity, "Leave")
		end
		local f = openWith({ alice })
		startNow()
		check(f.maxHp == Bosses.maxHealth(DEF, 1), "solo Health: " .. f.maxHp)
		-- Real strikes up to the contribution threshold.
		local landed = strikes(alice, 34)
		local pa = BossService.participant(alice)
		check(landed >= 30 and pa.damage >= Bosses.eligibleDamage(f.maxHp, 1), string.format("%d strikes landed, %.0f damage", landed, pa.damage))
		-- Phase 2: reaction show, music phase, then the special.
		clearLog(alice)
		BossService.devSetHealth(0.59)
		advance(0.1)
		check(f.phase == 2 and alice:GetAttribute("MusicBossPhase") == 2 and f.anchor:GetAttribute("Action") == "PhaseChange", "phase 2: reaction + music phase")
		check(fxCount(alice, "BossPhase") == 1, "phase change announced")
		f.nextAttackAt = 0
		advance(Bosses.Combat.PhaseShow + 0.3)
		check(f.plan and f.plan.id == "big_cleanup", "phase 2 opens with the Grand Ménage special")
		calm()
		BossService.devSetHealth(0.2)
		advance(0.1)
		check(f.phase == 3 and f.anchor:GetAttribute("Mood") == "furious", "phase 3: red as a tomato")
		advance(Bosses.Combat.PhaseShow + 0.1)
		calm()
		-- Final blow with every drop forced.
		forceDrops(0)
		BossService.devSetHealth(0.001)
		clearLog(alice)
		advance(0.1)
		nextToBoss(alice)
		local ok = BossService.strike(alice)
		advance(0.2)
		check(ok and f.state == "Victory", "victory")
		local ended = lastFx(alice, "BossEnd")
		check(ended and ended.result == "Victory" and ended.outcome == "rewarded" and #ended.rewards == #DEF.loot, "results with every reward line (" .. (ended and #ended.rewards or 0) .. ")")
		check(sa.data.essence >= essenceBefore + 250, "Essence reward paid")
		check((sa.data.materials.void_shard or 0) == shardsBefore + DEF.loot[2].max and (sa.data.materials.void_catalyst or 0) >= 1, "Void Shards + catalyst stored for the Forge")
		check(sa.data.cosmetics.owned.trail_bubbles == true, "exclusive cosmetic unlocked")
		local trophy = TrophyService.find(sa, "void_duster")
		check(trophy and trophy.level == 1 and trophy.slot == 1, "exclusive relic on trophy pedestal 1")
		local record = sa.data.bosses.VoidWarden
		check(record.wins == before.wins + 1 and record.bestTime > 0 and record.rare.void_duster == (before.rare.void_duster or 0) + 1 and record.rare.trail_bubbles == (before.rare.trail_bubbles or 0) + 1, "Codex: win, best time, rare finds")
		check(alice:GetAttribute("MusicBoss") == nil, "boss music released (victory stinger slot stays silent)")
		-- Never twice.
		local again, why = BossService.debugReward(alice)
		check(again == nil and why == "already", "the same fight can never pay twice")
		-- The trophy: produces, counts, never stealable.
		local entities = RelicService.trophiesOf(alice.UserId)
		check(#entities == 1 and entities[1].state == "Trophy", "trophy entity in the Sanctuary")
		local anchor = entities[1].anchor
		local prompts = 0
		for _, child in anchor:GetChildren() do
			if child:IsA("ProximityPrompt") then
				prompts += 1
			end
		end
		check(prompts == 0, "no prompt at all on a trophy (no steal, no grab)")
		check((anchor.Position - Layout.trophyPosition(sa.plot, 1)).Magnitude < 0.1, "hovering over its pedestal")
		local thief = sessionOf(bob)
		local allowed, reason = StealService.check(thief, entities[1])
		check(not allowed, "StealService refuses a trophy (" .. tostring(reason) .. ")")
		local socle = PlotService.get(sa.plot).model.Trophies.Trophy1
		check(socle:GetAttribute("State") == "Filled", "pedestal shown and filled")
		EconomyService.recompute(sa)
		local rateWith = sa.rate
		check(rateWith > 0, "trophies produce Essence")
		-- The client got the results card.
		local BossHud = creq("UI.Screens.BossHud")
		check(BossHud.debugState().results, "client: results card shown")
		-- Saved right away.
		advance(1)
		local saved = Engine.dataStoreData[STORE .. alice.UserId]
		check(saved and saved.schema == DataSchema.Version and saved.bosses.VoidWarden.wins == record.wins and saved.materials.void_shard == sa.data.materials.void_shard and #saved.trophies == 1, "rewards saved immediately")
		advance(Bosses.Combat.Outro + 0.5)
		check(fight() == nil, "expedition over")
		-- Duplicates: trophy levels up, owned cosmetic -> shards.
		local shards = sa.data.materials.void_shard
		f = openWith({ alice })
		startNow()
		strikes(alice, 32)
		forceDrops(0)
		BossService.devSetHealth(0.001)
		advance(Bosses.Combat.PhaseShow + 0.1)
		calm()
		nextToBoss(alice)
		BossService.strike(alice)
		advance(0.3)
		check(TrophyService.find(sa, "void_duster").level == 2, "duplicate boss relic: trophy levels up")
		check(sa.data.materials.void_shard == shards + DEF.loot[2].max + 5, "owned cosmetic converted into 5 Void Shards")
		local lines = lastFx(alice, "BossEnd").rewards
		local converted = false
		for _, line in lines do
			if line.kind == "cosmetic" and line.result == "owned" and line.fallback == "void_shard" then
				converted = true
			end
		end
		check(converted, "results explain the conversion")
		reset()
	end)

	--------------------------------------------------------------------------
	scenario("V2 Bosses: co-op victory, individual rewards, contribution threshold", function()
		local sa, sb, sc = sessionOf(alice), sessionOf(bob), sessionOf(cleo)
		sc.data.power.peak = math.max(sc.data.power.peak, 200)
		local f = openWith({ alice, bob, cleo })
		startNow()
		check(f.maxHp == Bosses.maxHealth(DEF, 3), "Health for 3 players")
		local needed = Bosses.eligibleDamage(f.maxHp, 3)
		-- Alice and Bob strike; Cleo only runs around.
		local rounds = math.ceil(needed / Bosses.Strike.Damage) + 2
		for _ = 1, rounds do
			nextToBoss(alice, -1)
			BossService.strike(alice)
			nextToBoss(bob, 1)
			BossService.strike(bob)
			Engine.moveTo(cleo, arenaPoint(math.random(-20, 20), math.random(-20, 20)))
			sc.lastPosition = nil
			advance(0.41)
		end
		check(BossService.participant(alice).damage >= needed and BossService.participant(bob).damage >= needed, "both strikers above the threshold")
		check(BossService.participant(cleo).damage < needed and BossService.participant(cleo).status == "fighting", "Cleo never struck (but moved: not AFK)")
		forceDrops(0.99)
		clearLog(alice)
		BossService.devSetHealth(0.001)
		advance(Bosses.Combat.PhaseShow + 0.1)
		calm()
		nextToBoss(alice)
		BossService.strike(alice)
		advance(0.3)
		check(f.state == "Victory", "co-op victory")
		check(BossService.participant(alice).outcome == "rewarded" and BossService.participant(bob).outcome == "rewarded", "each striker rewarded individually")
		check(BossService.participant(cleo).outcome == "contribution", "no contribution, no reward (anti-leech)")
		local ended = lastFx(alice, "BossEnd")
		check(ended and #ended.rewards == 2, "0.99 roll: only the guaranteed Essence + Shards")
		check(sc.data.bosses.VoidWarden.wins == 0 or sc.data.bosses.VoidWarden.lastFight ~= f.id, "Cleo's Codex has no win from this fight")
		reset()
	end)

	--------------------------------------------------------------------------
	scenario("V2 Bosses: AFK, out of bounds, teleport exploit, intruders, disconnect, timeout", function()
		local sa, sb, sc = sessionOf(alice), sessionOf(bob), sessionOf(cleo)
		local f = openWith({ alice, bob, cleo })
		startNow()
		-- Out of bounds (physics glitch): pulled back, still in.
		Engine.moveTo(bob, arenaPoint(ARENA.Radius + 30, 0))
		sb.lastPosition = nil
		advance(0.2)
		check(inArena(bob) and BossService.participant(bob).status == "fighting" and BossService.participant(bob).pullBacks >= 1, "out of bounds: pulled back inside")
		-- Teleport exploit: removed, no reward.
		Engine.moveTo(cleo, ARENA.Center + Vector3.new(0, 0, 900))
		sc.lastPosition = nil
		advance(0.2)
		check(BossService.participant(cleo).status == "exploit" and not Expeditions.isAway(sc), "teleport out of the arena: removed from the expedition")
		-- Intruder: someone who is not a participant appears in the arena.
		Engine.moveTo(dino, arenaPoint(5, 5))
		sessionOf(dino).lastPosition = nil
		advance(0.7)
		check(not inArena(dino), "intruder ejected to the plateau")
		-- AFK: Alice does nothing for too long.
		Engine.moveTo(alice, arenaPoint(-30, -30))
		sa.lastPosition = nil
		clearLog(alice)
		for _ = 1, math.ceil(Bosses.Combat.AfkSeconds / 2) + 2 do
			Engine.moveTo(bob, arenaPoint(math.random(-20, 20), math.random(-20, 20)))
			sb.lastPosition = nil
			advance(2)
		end
		check(BossService.participant(alice).status == "afk" and hasNotification(alice, "n.bossAfk") and not inArena(alice), "AFK fighter sent back (no reward)")
		check(BossService.participant(bob).status == "fighting", "the active fighter stays")
		-- Disconnect.
		local bobId = bob.UserId
		local attempts = sb.data.bosses.VoidWarden.attempts
		Engine.removePlayer(bob)
		advance(0.5)
		check(f.state == "Defeat" and f.reason == "abandoned", "last fighter disconnected: the fight ends")
		local saved = Engine.dataStoreData[STORE .. bobId]
		check(saved and saved.bosses and saved.bosses.VoidWarden and saved.bosses.VoidWarden.attempts == attempts, "the attempt is saved with Bob's profile")
		advance(Bosses.Combat.Outro + 0.5)
		check(fight() == nil, "arena cleaned")
		bob = Engine.addPlayer("Bob", bobId)
		waitFor(function()
			local s = sessionOf(bob)
			return s ~= nil and s.loaded and bob.Character ~= nil
		end, 6)
		check(sessionOf(bob) and sessionOf(bob).data.bosses.VoidWarden.attempts == attempts, "Bob rejoins with his Codex")
		-- Timeout.
		f = openWith({ alice })
		startNow()
		f.endsAt = now() + 1
		for _ = 1, 3 do
			Engine.moveTo(alice, arenaPoint(math.random(-20, 20), 10))
			sa.lastPosition = nil
			advance(0.5)
		end
		check(f.state == "Defeat" and f.reason == "timeout", "3:30 elapsed: time out")
		reset()
	end)

	--------------------------------------------------------------------------
	scenario("V2 Bosses: trophy pedestals by Power record, restored on rejoin", function()
		local sa = sessionOf(alice)
		local plot = PlotService.get(sa.plot)
		local socles = plot.model.Trophies
		check(#socles:GetChildren() == 3, "3 trophy pedestals per Sanctuary")
		local peak = sa.data.power.peak
		sa.data.power.peak = 0
		TrophyService.refreshSocles(sa.plot, sa)
		check(socles.Trophy1:GetAttribute("State") ~= "Hidden" and socles.Trophy2:GetAttribute("State") == "Hidden" and socles.Trophy3:GetAttribute("State") == "Hidden", "Power record 0: one pedestal")
		sa.data.power.peak = 950
		TrophyService.onPeakRaised(sa)
		check(socles.Trophy2:GetAttribute("State") == "Active" and socles.Trophy3:GetAttribute("State") == "Active", "Power record 950: three pedestals")
		sa.data.power.peak = math.max(peak, 950)
		local result = TrophyService.award(sa, "storm_crystal")
		check(result == "invalid", "only boss relics go on trophy pedestals")
		check(#sa.data.trophies >= 1 and #RelicService.trophiesOf(alice.UserId) == #sa.data.trophies, "one entity per saved trophy")
		-- Leave and rejoin: the trophy leaves with its owner and comes back.
		local sd = sessionOf(dino)
		check(TrophyService.award(sd, "void_duster") == "placed", "Dino gets a trophy")
		local dinoId = dino.UserId
		check(#RelicService.trophiesOf(dinoId) == 1, "Dino's trophy is displayed")
		Engine.removePlayer(dino)
		advance(1.5)
		check(#RelicService.trophiesOf(dinoId) == 0, "trophy leaves with its owner")
		local saved = Engine.dataStoreData[STORE .. dinoId]
		check(saved and #saved.trophies == 1 and saved.trophies[1].id == "void_duster", "trophy saved")
		dino = newPlayer("Dino", dinoId)
		advance(0.5)
		local back = RelicService.trophiesOf(dinoId)
		local sd2 = sessionOf(dino)
		check(#back == 1 and back[1].state == "Trophy" and sd2.plot and (back[1].anchor.Position - Layout.trophyPosition(sd2.plot, 1)).Magnitude < 0.1, "trophy restored on its pedestal after rejoining")
	end)

	--------------------------------------------------------------------------
	scenario("V2 Bosses: MovementGuard compatibility and full cleanup", function()
		local sa = sessionOf(alice)
		local f = openWith({ alice })
		advance(1.5)
		check(inArena(alice), "the 1600-stud trip to the arena is never pulled back by the movement guard")
		startNow()
		local p = root(alice).Position
		table.insert(f.shapes, { kind = "circle", at = now(), center = Vector3.new(p.X, FLOOR, p.Z), radius = 6, resolved = {} })
		advance(1)
		check(BossService.participant(alice).hearts == Bosses.Combat.Hearts - 1 and inArena(alice), "knockback never trips the guard")
		BossService.leave(alice)
		advance(0.5)
		check(BossService.participant(alice).status == "left" and not inArena(alice), "abandon: back on the plateau")
		advance(0.5)
		check(f.state == "Defeat" and f.reason == "abandoned", "everyone left: the fight ends")
		advance(Bosses.Combat.Outro + 0.5)
		check(Engine.workspace:FindFirstChild("BossArena") == nil and Expeditions.count() == 0, "no arena, nobody away")
		for _, player in { alice, bob, cleo, dino } do
			if player and player.Parent then
				check(player:GetAttribute("BossFight") == nil and player:GetAttribute("MusicBoss") == nil, player.Name .. ": no boss attribute left")
			end
		end
		advance(1)
		local BossFX = creq("Controllers.BossFX")
		local state = BossFX.debugState()
		check(not state.rig and state.visuals == 0, "client: boss body and telegraphs destroyed")
		check(state.parts <= 2, "client: no leftover parts (" .. state.parts .. ")")
		local BossHud = creq("UI.Screens.BossHud")
		check(not BossHud.debugState().visible, "client: boss HUD hidden")
		local _ = sa
	end)

	--------------------------------------------------------------------------
	scenario("V2 Bosses: client portal card, exact chances, HUD bar, Codex, board", function()
		reset()
		BossService.setNextOpen(now() + 125)
		advance(0.6)
		local BossPortal = creq("UI.Screens.BossPortal")
		local BossCodex = creq("UI.Screens.BossCodex")
		local UI = creq("UI")
		UI.open("BossPortal")
		advance(0.4)
		local rows = BossPortal.debugRows()
		for _, entry in DEF.loot do
			check(rows[entry.id] and string.find(rows[entry.id], Bosses.percent(entry.chance), 1, true) ~= nil, "card shows the exact chance of " .. entry.id .. " (" .. Bosses.percent(entry.chance) .. ")")
		end
		check(not BossPortal.isEnterEnabled(), "ENTER greyed out while the portal sleeps")
		UI.close()
		-- Prompt -> card.
		local prompt = plateauModel().PortalPrompt.Boss
		check(prompt and prompt:GetAttribute("Action") == "Boss" and prompt.RequiresLineOfSight == false, "portal prompt (keyboard E, gamepad X, touch)")
		clearLog(alice)
		Engine.signal(prompt, "Triggered"):Fire(alice)
		advance(0.2)
		check(fxCount(alice, "BossMenu") == 1, "the prompt opens the boss card")
		check(UI.isOpen("BossPortal"), "client opened the card")
		UI.close()
		-- Open portal at the portal: ENTER lights up.
		BossService.open()
		atPortal(alice)
		advance(0.5)
		UI.open("BossPortal")
		advance(0.4)
		check(BossPortal.isEnterEnabled(), "ENTER enabled at an open portal")
		local ok = BossPortal.enter()
		advance(0.3)
		check(ok and inArena(alice) and not UI.isOpen("BossPortal"), "ENTER joins through the server and closes the card")
		-- HUD bar + Codex.
		local hud = alice.PlayerGui:FindFirstChild("RiftHUD")
		local bar = nil
		for _, d in hud:GetDescendants() do
			if d.Name == "BossBar" then
				bar = d
			end
		end
		check(bar ~= nil and bar.Size.Y.Offset >= 44, "Boss bar with the portal countdown in the HUD (touch-size)")
		local cards = BossCodex.debugCards()
		check(#cards == #Bosses.list and cards[1].name == Strings.en["boss.VoidWarden.name"] or cards[1].name == Strings.fr["boss.VoidWarden.name"], "Codex: discovered boss shown by name")
		check(cards[1].stats ~= "", "Codex: attempts / victories / best time")
		local BossFX = creq("Controllers.BossFX")
		check(BossFX.debugState().board, "client: countdown board above the portal")
		reset()
	end)
end
