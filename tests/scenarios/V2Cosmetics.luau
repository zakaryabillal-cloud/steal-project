--!nocheck
-- V2 phase 5 ("Cosmetics") scenarios. Called by tests/run.luau with its
-- helpers; runs on the same live server after the earlier scenarios.
--
--   * catalogue: categories, budgets, purely visual definitions, strings, and
--     a source scan proving no gameplay code reads cosmetics;
--   * schema 4: migration from a phase 4 save, sanitising, newer-schema guard;
--   * server authority: fake / unowned / wrong-category ids, garbage, spam,
--     rapid switching, Studio unlock never saved, future sources;
--   * automatic unlocks (Power record, stats, RiftDex, tier);
--   * no gameplay effect (speed, Power, rate, abilities, carrying, collisions);
--   * client rendering: every category, preview, respawn, death, departure,
--     several equipped players at once (LOD, aura/light budgets, no new loop);
--   * the Cosmetics screen; phase 1-4 systems untouched.

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3

return function(ctx)
	local scenario, check, advance, waitFor = ctx.scenario, ctx.check, ctx.advance, ctx.waitFor
	local sreq, shared, remote, Engine, Loader, game = ctx.sreq, ctx.shared, ctx.remote, ctx.Engine, ctx.Loader, ctx.game
	local sessionOf, teleport, insideOwnPlot = ctx.sessionOf, ctx.teleport, ctx.insideOwnPlot
	local hasNotification, clearLog, claimRelic = ctx.hasNotification, ctx.clearLog, ctx.claimRelic
	local alice, bob = ctx.alice(), ctx.bob()

	local Sessions = sreq("Core.Sessions")
	local Snapshot = sreq("Core.Snapshot")
	local DataSchema = sreq("Core.DataSchema")
	local DataService = sreq("Services.DataService")
	local CosmeticService = sreq("Services.CosmeticService")
	local AbilityService = sreq("Services.AbilityService")
	local EconomyService = sreq("Services.EconomyService")
	local CharacterService = sreq("Services.CharacterService")
	local CarryService = sreq("Services.CarryService")
	local PlotService = sreq("Services.PlotService")
	local Cosmetics = shared("Config.Cosmetics")
	local Abilities = shared("Config.Abilities")
	local GameConfig = shared("Config.GameConfig")
	local Music = shared("Config.Music")
	local Strings = shared("Locale.Strings")
	local B = Cosmetics.Budget

	local Client = game:GetService("StarterPlayer").StarterPlayerScripts.Client
	local function creq(path)
		local node = Client
		for part in string.gmatch(path, "[^%.]+") do
			node = node:FindFirstChild(part)
		end
		return Loader.require("client", node)
	end
	local Renderer = creq("Controllers.CosmeticRenderer")
	local Store = creq("Controllers.Store")

	local STORE = "RiftHeist_Player_v1/u_"
	local sa, sb = sessionOf(alice), sessionOf(bob)
	local unmarkedBefore = Snapshot.unmarkedColdChanges

	local function deepCopy(value)
		if type(value) ~= "table" then
			return value
		end
		local out = {}
		for k, v in value do
			out[k] = deepCopy(v)
		end
		return out
	end
	local function deepEqual(a, b)
		if type(a) ~= "table" or type(b) ~= "table" then
			return a == b
		end
		for k, v in a do
			if not deepEqual(v, b[k]) then
				return false
			end
		end
		for k in b do
			if a[k] == nil then
				return false
			end
		end
		return true
	end
	local function count(t)
		local n = 0
		for _ in t do
			n += 1
		end
		return n
	end
	local function equip(player, category, id)
		return CosmeticService.equip(player, category, id)
	end
	local function root(player)
		return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	end
	local function render()
		Renderer.update()
		Engine.runUntil(Engine.now)
	end
	local function childrenNamed(parent, name)
		local n = 0
		if parent then
			for _, d in parent:GetDescendants() do
				if d.Name == name then
					n += 1
				end
			end
		end
		return n
	end
	local function connectionCount()
		local runService = game:GetService("RunService")
		local total = 0
		for _, name in { "Heartbeat", "RenderStepped", "Stepped" } do
			total += #Engine.signal(runService, name)._connections
		end
		return total
	end
	-- A cosmetic whose condition `session` does not meet (preferably in `category`),
	-- so the periodic unlock check can never grant it during the test.
	local function lockedFor(session, category)
		local progress = CosmeticService.progress(session)
		local fallback = nil
		for _, def in Cosmetics.list do
			if Cosmetics.UnlockKinds[def.unlock.kind].auto and not Cosmetics.isMet(def, progress) then
				if def.category == category then
					return def.id
				end
				fallback = fallback or def.id
			end
		end
		return fallback
	end
	local allIds = {}
	for _, def in Cosmetics.list do
		table.insert(allIds, def.id)
	end

	--------------------------------------------------------------------------
	scenario("V2 Cosmetics: catalogue, budgets, purely visual", function()
		check(#Cosmetics.Categories == 7, "7 categories (trail, aura, carry, sanctuary, arrival, secure, title)")
		local perCategory, starters, auto = {}, 0, 0
		for _, def in Cosmetics.list do
			perCategory[def.category] = (perCategory[def.category] or 0) + 1
			if def.unlock.kind == "starter" then
				starters += 1
			end
			if Cosmetics.UnlockKinds[def.unlock.kind].auto then
				auto += 1
			end
			for _, lang in { "en", "fr" } do
				if Strings[lang]["cos." .. def.id] == nil then
					check(false, "missing name cos." .. def.id .. " (" .. lang .. ")")
				end
			end
			local v = def.visual
			if (v.rate and v.rate > B.MaxRate) or (v.lifetime and v.lifetime > B.MaxTrailLifetime) or (v.burst and v.burst > B.MaxBurstParticles) then
				check(false, def.id .. " above budget")
			end
		end
		for _, category in Cosmetics.Categories do
			if (perCategory[category.id] or 0) < 3 then
				check(false, "category " .. category.id .. " has at least 3 cosmetics")
			end
			for _, lang in { "en", "fr" } do
				if Strings[lang]["cos.cat." .. category.id] == nil then
					check(false, "missing cos.cat." .. category.id)
				end
			end
		end
		-- Phase 6 added exactly one cosmetic: the Void Warden drop (source "boss",
		-- granted only by BossService). Everything else stays automatic.
		local bossDrops = {}
		for _, def in Cosmetics.list do
			if def.unlock.kind == "boss" then
				table.insert(bossDrops, def.id)
			end
		end
		check(#Cosmetics.list == 27, "26 phase 5 cosmetics + 1 boss drop (" .. #Cosmetics.list .. ")")
		check(starters == 6 and auto == #Cosmetics.list - #bossDrops and #bossDrops == 1 and bossDrops[1] == "trail_bubbles", "6 starters; every other cosmetic obtainable now; only real boss content (no fake event/daily/premium)")
		local rarities = {}
		for _, def in Cosmetics.list do
			rarities[def.rarity] = true
		end
		check(rarities.Common and rarities.Rare and rarities.Epic and rarities.Legendary, "Common, Rare, Epic and Legendary looks")
		for _, kind in { "boss", "event", "daily", "premium" } do
			check(Cosmetics.UnlockKinds[kind] and not Cosmetics.UnlockKinds[kind].auto, "future source prepared: " .. kind)
		end
		-- Source scan: cosmetics are read only by the cosmetic code itself.
		local readers, serviceUsers = {}, {}
		local function scan(dir)
			for _, name in fs.readDir(dir) do
				local path = dir .. "/" .. name
				if fs.isDir(path) then
					scan(path)
				elseif string.sub(name, -5) == ".luau" then
					local source = fs.readFile(path)
					if string.find(source, "require%([^)]*Config%.Cosmetics%)") then
						table.insert(readers, (string.gsub(path, "^src/", "")))
					end
					if string.find(source, "require%([^)]*CosmeticService%)") then
						table.insert(serviceUsers, (string.gsub(path, "^src/", "")))
					end
					if string.find(path, "Config/Cosmetics", 1, true) and string.find(source, "rbxassetid", 1, true) then
						check(false, "Config/Cosmetics contains an asset id")
					end
				end
			end
		end
		scan("src")
		table.sort(readers)
		table.sort(serviceUsers)
		local allowedReaders = {
			["client/Controllers/CosmeticRenderer.luau"] = true,
			["client/Controllers/Store.luau"] = true,
			["client/UI/Screens/Cosmetics.luau"] = true,
			["server/Core/DataSchema.luau"] = true,
			["server/Core/Snapshot.luau"] = true,
			["server/Services/CosmeticService.luau"] = true,
		}
		local stray = {}
		for _, path in readers do
			if not allowedReaders[path] then
				table.insert(stray, path)
			end
		end
		check(#stray == 0, "no gameplay module reads cosmetics (" .. table.concat(stray, ", ") .. ")")
		check(table.concat(serviceUsers, ",") == "server/Services/BossService.luau,server/Services/DevCommands.luau,server/init.server.luau", "CosmeticService used only by bootstrap + dev commands + the boss rewards (" .. table.concat(serviceUsers, ",") .. ")")
	end)

	--------------------------------------------------------------------------
	scenario("V2 Cosmetics: schema 4 migration from a phase 4 save, sanitising", function()
		check(GameConfig.Data.SchemaVersion >= 4, "schema 4 or later (phase 6: 5)")
		local phase4 = DataSchema.serialize(DataSchema.normalize({
			schema = 3,
			essence = 4321,
			lifetimeEssence = 9999,
			relics = { { uid = "p4a", id = "magma_heart", level = 3, slot = 1 } },
			abilities = { unlocked = { dash = true, pulse = true, shield = true }, loadout = { "dash", "pulse", "shield" }, harmonyOff = { magma_heart = true } },
			power = { peak = 777 },
			stats = { claimed = 12, deposits = 9, stolen = 1, lost = 2, recovered = 3, rareFinds = 0, essenceCollected = 500 },
		}))
		phase4.schema = 3
		phase4.cosmetics = nil
		local raw = deepCopy(phase4)
		local data = DataSchema.normalize(raw)
		check(deepEqual(raw, phase4), "normalize never mutates the phase 4 record")
		check(data.schema == GameConfig.Data.SchemaVersion, "phase 4 save -> current schema")
		check(data.essence == 4321 and data.lifetimeEssence == 9999 and data.power.peak == 777 and #data.relics == 1 and data.relics[1].level == 3, "Essence, Power record, relics kept")
		check(data.abilities.unlocked.shield and data.abilities.loadout[3] == "shield" and data.abilities.harmonyOff.magma_heart, "abilities, loadout and harmony switches kept")
		check(deepEqual(data.stats, phase4.stats), "stats kept")
		check(deepEqual(data.cosmetics.owned, Cosmetics.starters()) and next(data.cosmetics.equipped) == nil, "starters owned, nothing equipped")
		-- V1 save -> 4 in one go.
		local fixture = serde.decode("json", fs.readFile("tests/fixtures/save_v1.json"))
		local fromV1 = DataSchema.normalize(fixture)
		check(fromV1.schema == GameConfig.Data.SchemaVersion and #fromV1.relics == 5 and deepEqual(fromV1.cosmetics.owned, Cosmetics.starters()), "real V1 save -> schema 4 with the starters")
		-- Tampering.
		local tampered = deepCopy(phase4)
		tampered.schema = 4
		tampered.cosmetics = {
			owned = { trail_voidwake = true, nope = true, aura_eclipse = "yes", [3] = true, title_riftborn = false },
			equipped = { trail = "trail_voidwake", aura = "aura_eclipse", title = "trail_stardust", hax = "trail_voidwake", sanctuary = "theme_singularity", carry = 42 },
		}
		local clean = DataSchema.normalize(tampered)
		check(clean.cosmetics.owned.trail_voidwake == true and clean.cosmetics.owned.nope == nil and clean.cosmetics.owned.aura_eclipse == nil and clean.cosmetics.owned[3] == nil and clean.cosmetics.owned.title_riftborn == nil, "only known ids with `true` are kept")
		check(clean.cosmetics.owned.trail_stardust == true, "starters can never be lost")
		check(clean.cosmetics.equipped.trail == "trail_voidwake", "owned cosmetic stays equipped")
		check(clean.cosmetics.equipped.aura == nil and clean.cosmetics.equipped.sanctuary == nil, "unowned equipped cosmetics removed")
		check(clean.cosmetics.equipped.title == nil and clean.cosmetics.equipped.hax == nil and clean.cosmetics.equipped.carry == nil, "wrong category / unknown category / garbage removed")
		tampered.cosmetics = "everything"
		check(deepEqual(DataSchema.normalize(tampered).cosmetics.owned, Cosmetics.starters()), "wrong type -> starters only")
		local round = DataSchema.normalize(DataSchema.serialize(clean))
		check(deepEqual(round.cosmetics, clean.cosmetics), "serialize -> normalize round trip is lossless")
		check(count(round.cosmetics.owned) <= #Cosmetics.list, "inventory bounded by the catalogue (no duplicates possible: a set)")

		-- A save written by a NEWER build is never touched.
		local future = { schema = GameConfig.Data.SchemaVersion + 1, essence = 55, cosmetics = { owned = { future_trail = true }, equipped = { trail = "future_trail" } }, futureField = 1 }
		Engine.dataStoreData[STORE .. "6161"] = deepCopy(future)
		local player = Engine.addPlayer("FutureCos", 6161)
		advance(3)
		local s = sessionOf(player)
		check(s and s.dataStatus == "newer" and s.canSave == false, "newer cosmetics save: temporary data, saving disabled")
		Engine.removePlayer(player)
		advance(2)
		check(deepEqual(Engine.dataStoreData[STORE .. "6161"], future), "newer record untouched")

		-- A phase 4 player joins: migrated, saved back as schema 4.
		Engine.dataStoreData[STORE .. "6262"] = deepCopy(phase4)
		local vet = Engine.addPlayer("Phase4Vet", 6262)
		advance(3)
		local sv = sessionOf(vet)
		check(sv and sv.canSave and sv.data.cosmetics.owned.trail_stardust and sv.data.abilities.loadout[3] == "shield", "phase 4 player loads with starters and keeps the loadout")
		Engine.removePlayer(vet)
		advance(2)
		local saved = Engine.dataStoreData[STORE .. "6262"]
		check(saved.schema == GameConfig.Data.SchemaVersion and saved.cosmetics and saved.cosmetics.owned.trail_stardust == true and saved.essence == 4321, "saved back as schema 4, nothing lost")
	end)

	--------------------------------------------------------------------------
	scenario("V2 Cosmetics: equip is server-validated (fake, unowned, wrong category, spam)", function()
		CosmeticService.reset(sa)
		advance(0.3)
		local invoke = function(category, id)
			return Engine.invokeServer(remote("EquipCosmetic"), alice, category, id)
		end
		local ok, reason = invoke("trail", "trail_stardust")
		check(ok == true and sa.data.cosmetics.equipped.trail == "trail_stardust", "owned starter equipped through the remote")
		check(alice:GetAttribute("Cos_trail") == "trail_stardust", "published as a player attribute")
		local lockedTrail = lockedFor(sa, "trail")
		local lockedDef = Cosmetics.get(lockedTrail)
		ok, reason = equip(alice, lockedDef.category, lockedTrail)
		check(ok == false and reason == "locked" and sa.data.cosmetics.equipped.trail == "trail_stardust", "unowned cosmetic refused (" .. lockedTrail .. ")")
		ok, reason = equip(alice, "aura", "trail_stardust")
		check(ok == false and reason == "category", "wrong category refused")
		check(equip(alice, "trail", "hax") == false and equip(alice, "hax", "trail_stardust") == false, "fake id / fake category refused")
		check(equip(alice, "trail", string.rep("a", 64)) == false and equip(alice, "trail", 7) == false and equip(alice, { "trail" }, "trail_stardust") == false and equip(alice, nil, nil) == false, "garbage refused")
		check(alice:GetAttribute("Cos_trail") == "trail_stardust" and alice:GetAttribute("Cos_aura") == "", "attributes unchanged by refused requests")
		check(equip(alice, "trail", "") == true and sa.data.cosmetics.equipped.trail == nil and alice:GetAttribute("Cos_trail") == "", "unequip with \"\"")
		-- Client claims ownership in its own Store: the server does not care.
		Store.state.cosmetics = { owned = table.clone(Store.state.cosmetics.owned), equipped = {} }
		Store.state.cosmetics.owned[lockedTrail] = true
		ok = invoke(lockedDef.category, lockedTrail)
		check(ok == false and alice:GetAttribute("Cos_" .. lockedDef.category) == "" and not sa.data.cosmetics.owned[lockedTrail], "a forged client inventory grants nothing")
		-- Spam + rapid switching.
		equip(alice, "title", "title_drifter")
		local rated = 0
		for i = 1, 60 do
			local _, why = invoke("trail", if i % 2 == 0 then "" else "trail_stardust")
			if why == "rate" then
				rated += 1
			end
		end
		check(rated >= 40, "remote spam rate-limited (" .. rated .. ")")
		for i = 1, 41 do
			equip(alice, "trail", if i % 2 == 0 then "" else "trail_stardust")
		end
		check(sa.data.cosmetics.equipped.trail == "trail_stardust" and alice:GetAttribute("Cos_trail") == "trail_stardust", "41 rapid switches: consistent final state")
		advance(0.4)
		check(Store.state.cosmetics.equipped.trail == "trail_stardust" and Store.state.cosmetics.owned[lockedTrail] == nil, "client Store resynced from the server (forged entry gone)")
		check(Snapshot.cold(sa).cosmetics ~= nil and Snapshot.hot(sa).cosmetics == nil, "cosmetics travel in the cold half of the Sync only")
		-- Sanctuary theme published on the Sanctuary.
		equip(alice, "sanctuary", "theme_dawn")
		check(PlotService.get(sa.plot).model:GetAttribute("Theme") == "theme_dawn", "theme published on the Sanctuary model")
		equip(alice, "sanctuary", "")
		check(PlotService.get(sa.plot).model:GetAttribute("Theme") == "", "and removed")
		-- Studio unlock: session only.
		CosmeticService.setDevUnlock(sa, true)
		check(equip(alice, "aura", "aura_eclipse") == true and sa.data.cosmetics.owned.aura_eclipse == nil, "dev unlock: equippable, never written to the inventory")
		local saved = DataSchema.normalize(DataSchema.serialize(sa.data))
		check(saved.cosmetics.equipped.aura == nil, "a saved dev cosmetic is dropped on the next load")
		CosmeticService.setDevUnlock(sa, false)
		check(sa.data.cosmetics.equipped.aura == nil and alice:GetAttribute("Cos_aura") == "", "turning it off unequips what is not owned")
		-- Future sources: only their own service may grant, never for auto unlocks.
		check(CosmeticService.grant(sa, "trail_voidwake", "power") == false and CosmeticService.grant(sa, "trail_voidwake", "premium") == false, "grant refuses automatic cosmetics / mismatched sources")
		check(CosmeticService.grant(sa, "nope", "boss") == false, "grant refuses unknown ids")
		check(remote("GrantCosmetic") == nil and remote("BuyCosmetic") == nil, "no client remote can grant or buy a cosmetic")
	end)

	--------------------------------------------------------------------------
	scenario("V2 Cosmetics: automatic unlocks from existing progress", function()
		CosmeticService.reset(sa)
		local stats = deepCopy(sa.data.stats)
		local peak = sa.data.power.peak
		-- Nothing met: only starters.
		for key in Cosmetics.Stats do
			sa.data.stats[key] = 0
		end
		sa.data.power.peak = 0
		local granted = CosmeticService.evaluate(sa, false)
		local nonStarter = 0
		for id in sa.data.cosmetics.owned do
			if Cosmetics.get(id).unlock.kind ~= "starter" then
				nonStarter += 1
			end
		end
		-- RiftDex / tier / play time may already be met by alice; stats and Power are not.
		for _, id in granted do
			local kind = Cosmetics.get(id).unlock.kind
			if kind == "stat" or kind == "power" then
				check(false, id .. " granted without its condition")
			end
		end
		-- One condition at a time.
		clearLog(alice)
		sa.data.stats.stolen = 3
		granted = CosmeticService.evaluate(sa, true)
		check(table.find(granted, "title_heister") ~= nil and table.find(granted, "trail_tempest") == nil, "3 heists -> Heister title, not yet Tempest Streak (5)")
		check(hasNotification(alice, "n.cosmeticUnlocked"), "unlock notified")
		check(#CosmeticService.evaluate(sa, true) == 0, "never granted twice")
		sa.data.power.peak = 650
		granted = CosmeticService.evaluate(sa, true)
		check(table.find(granted, "trail_voidwake") and table.find(granted, "title_riftborn") and table.find(granted, "arrival_riftgate") and not table.find(granted, "theme_singularity"), "Power record 650 -> its rewards, not the 1000 one")
		-- Ownership survives a drop (theft lowers current Power, never the record or stats).
		sa.data.stats.stolen = 0
		CosmeticService.evaluate(sa, true)
		check(sa.data.cosmetics.owned.title_heister == true, "owned forever once unlocked")
		-- Many at once: one summary notification.
		CosmeticService.reset(sa)
		clearLog(alice)
		sa.data.power.peak = 1e6
		for key in Cosmetics.Stats do
			sa.data.stats[key] = 1000
		end
		granted = CosmeticService.evaluate(sa, true)
		check(#granted >= 15 and hasNotification(alice, "n.cosmeticsUnlocked"), "big catch-up: one summary notification (" .. #granted .. ")")
		-- Restore real progress (the periodic job keeps what was granted).
		sa.data.stats = stats
		sa.data.power.peak = math.max(peak, sa.power)
		Sessions.markCold(sa)
		check(sa.data.cosmetics.owned.secure_supernova == true, "Legendary secure FX now owned")
	end)

	--------------------------------------------------------------------------
	scenario("V2 Cosmetics: no gameplay effect at all", function()
		insideOwnPlot(alice)
		local function snapshot()
			local humanoid = alice.Character:FindFirstChild("Humanoid")
			local dash = Abilities.get("dash")
			return {
				walk = humanoid.WalkSpeed,
				jump = humanoid.JumpHeight,
				power = sa.power,
				rate = sa.rate,
				multiplier = sa.multiplier,
				dashCooldown = Abilities.cooldown(dash, AbilityService.activeHarmonies(sa)),
				dashTuning = Abilities.tuning(dash, AbilityService.activeHarmonies(sa)),
				group = root(alice).CollisionGroup,
				capacity = CarryService.capacity(sa),
				harmonies = table.concat(sa.harmonyRelics, ","),
			}
		end
		CharacterService.refreshSpeed(sa)
		EconomyService.recompute(sa)
		local before = snapshot()
		for _, category in Cosmetics.Categories do
			local best = nil
			for _, def in Cosmetics.list do
				if def.category == category.id and sa.data.cosmetics.owned[def.id] then
					best = def.id
				end
			end
			if best then
				equip(alice, category.id, best)
			end
		end
		check(count(sa.data.cosmetics.equipped) == 7, "one cosmetic equipped in every category")
		CharacterService.refreshSpeed(sa)
		EconomyService.recompute(sa)
		advance(0.5)
		check(deepEqual(snapshot(), before), "speed, jump, Power, Essence rate, abilities, collisions, carry capacity, harmonies: identical")
	end)

	--------------------------------------------------------------------------
	scenario("V2 Cosmetics: client rendering, preview, carry, respawn", function()
		-- Alice wears everything (from the previous scenario).
		advance(0.5)
		render()
		local character = alice.Character
		local counts = Renderer.debugCounts()
		check(childrenNamed(character, "CosmeticTrail") == 1, "trail on alice's character")
		local trail = character:FindFirstChild("HumanoidRootPart"):FindFirstChild("CosmeticTrail")
		check(trail and trail.Lifetime <= B.MaxTrailLifetime and trail.Enabled, "trail within budget, enabled for yourself")
		check(childrenNamed(character, "CosmeticAura") == 1 and childrenNamed(character, "CosmeticCarry") == 1, "aura + carry FX attached")
		local gui = alice.PlayerGui:FindFirstChild("CosmeticFX")
		check(gui and childrenNamed(gui, "Title") == 1, "title nameplate shown")
		check(counts.themed >= 1, "alice's Sanctuary themed")
		-- Theme recolours accent parts, never the barrier.
		local model = PlotService.get(sa.plot).model
		local themeDef = Cosmetics.get(sa.data.cosmetics.equipped.sanctuary)
		local recoloured, barrierTouched = 0, false
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d.Color == themeDef.visual.accent then
				recoloured += 1
				local node = d
				while node and node ~= model do
					if node.Name == "Barrier" then
						barrierTouched = true
					end
					node = node.Parent
				end
			end
		end
		check(recoloured >= 10 and not barrierTouched, "theme recolours " .. recoloured .. " accent parts, never the seal barrier")
		-- Carry FX only while carrying; the title hides so the carry marker stays readable.
		local carry = character:FindFirstChild("HumanoidRootPart"):FindFirstChild("CosmeticCarry"):FindFirstChild("CosmeticParticles")
		check(carry.Enabled == false, "carry FX off when not carrying")
		claimRelic(alice, "ember_shard")
		advance(0.6)
		render()
		check(carry.Enabled == true, "carry FX on while carrying")
		local title = gui:FindFirstChild("CosmeticTitle_" .. alice.UserId)
		check(title and title.Enabled == false, "title hidden while carrying")
		-- Secure FX on deposit.
		local played = {}
		local connection = Renderer.played:Connect(function(kind, userId)
			table.insert(played, kind .. ":" .. userId)
		end)
		insideOwnPlot(alice)
		advance(1)
		render()
		check(table.find(played, "secure:" .. alice.UserId) ~= nil, "secure FX played on the deposit")
		check(carry.Enabled == false and title.Enabled == true, "carry FX off + title back after the deposit")
		-- Respawn: arrival FX, effects rebuilt exactly once.
		alice.Character:FindFirstChild("Humanoid").Health = 0
		advance(GameConfig.Player.RespawnDelay + 0.6)
		render()
		check(alice.Character ~= character, "respawned")
		check(table.find(played, "arrival:" .. alice.UserId) ~= nil, "arrival FX played on respawn")
		check(childrenNamed(alice.Character, "CosmeticTrail") == 1 and childrenNamed(gui, "Title") == 1, "effects rebuilt once on the new character, old title gone")
		-- Rapid switching never leaves duplicates.
		for i = 1, 30 do
			equip(alice, "trail", if i % 2 == 0 then "trail_stardust" else "trail_voidwake")
			render()
		end
		check(childrenNamed(alice.Character, "CosmeticTrail") == 1 and childrenNamed(alice.Character, "CosmeticTrailTop") == 1, "30 switches: one trail, one attachment pair")
		-- Unequip removes everything of that category.
		equip(alice, "aura", "")
		equip(alice, "title", "")
		advance(0.3)
		render()
		check(childrenNamed(alice.Character, "CosmeticAura") == 0 and childrenNamed(gui, "Title") == 0, "unequipped aura + title removed")
		-- Preview (try-on), even locked, local only.
		local locked = nil
		for _, def in Cosmetics.list do
			if def.category == "aura" and not sa.data.cosmetics.owned[def.id] then
				locked = def.id
			end
		end
		local previewId = locked or "aura_embers"
		check(Renderer.preview(previewId) == true, "preview accepted")
		render()
		check(childrenNamed(alice.Character, "CosmeticAura") == 1 and alice:GetAttribute("Cos_aura") == "", "preview shows on your character only (server unchanged)")
		advance(B.PreviewSeconds + 0.5)
		render()
		check(childrenNamed(alice.Character, "CosmeticAura") == 0, "preview ends by itself")
		connection:Disconnect()
	end)

	--------------------------------------------------------------------------
	scenario("V2 Cosmetics: many equipped players (LOD, budgets, one loop, cleanup)", function()
		local loopsBefore = connectionCount()
		-- Earlier scenarios leave the client on Low quality: measure on High.
		local Settings = creq("Controllers.Settings")
		local savedQuality = Settings.quality
		Settings.quality = "High"
		local guests = {}
		for i = 1, 6 do
			local guest = Engine.addPlayer("Glow" .. i, 7100 + i)
			table.insert(guests, guest)
		end
		check(waitFor(function()
			for _, g in guests do
				local s = sessionOf(g)
				if not (s and s.loaded and g.Character) then
					return false
				end
			end
			return true
		end, 8), "6 extra players joined")
		-- The harness camera is static: put it behind alice, like the real follow camera.
		local cameraObject = Engine.workspace.CurrentCamera
		local savedCamera = cameraObject.CFrame
		local base = root(alice).Position
		cameraObject.CFrame = roblox.CFrame.lookAt(base + Vector3.new(0, 8, -14), base)
		for i, guest in guests do
			local s = sessionOf(guest)
			CosmeticService.setDevUnlock(s, true)
			equip(guest, "trail", "trail_voidwake")
			equip(guest, "aura", "aura_eclipse")
			equip(guest, "title", "title_riftborn")
			equip(guest, "carry", "carry_comet")
			-- Four near the camera, two far away.
			local offset = if i <= 4 then Vector3.new(i * 6, 0, 8) else Vector3.new(400 + i * 50, 0, 0)
			teleport(guest, base + offset)
		end
		-- Bob too, near.
		CosmeticService.setDevUnlock(sb, true)
		equip(bob, "aura", "aura_eclipse")
		teleport(bob, base + Vector3.new(-8, 0, 8))
		advance(0.6)
		render()
		local counts = Renderer.debugCounts()
		check(counts.trails >= 6 and counts.auras >= 7, "everyone's effects built (" .. counts.trails .. " trails, " .. counts.auras .. " auras)")
		check(counts.lightsOn <= B.MaxLights, "aura lights capped at " .. B.MaxLights .. " (" .. counts.lightsOn .. ")")
		check(counts.aurasOn <= B.MaxAuras + 1, "auras capped (" .. counts.aurasOn .. ")")
		local far = guests[6]
		local farTrail = root(far):FindFirstChild("CosmeticTrail")
		local farAura = root(far):FindFirstChild("CosmeticAura"):FindFirstChild("CosmeticParticles")
		check(farTrail and not farTrail.Enabled and not farAura.Enabled, "far player's trail and aura switched off (LOD)")
		local nearAura = root(guests[1]):FindFirstChild("CosmeticAura"):FindFirstChild("CosmeticParticles")
		local nearDistance = (root(guests[1]).Position - cameraObject.CFrame.Position).Magnitude
		check(nearAura.Enabled, "near player's aura on (" .. math.floor(nearDistance) .. " studs from the camera)")
		check(connectionCount() == loopsBefore, "no new Heartbeat/RenderStepped connection per player or effect (" .. connectionCount() - loopsBefore .. ")")
		-- Low quality: other players' auras off, yours unaffected.
		Settings.quality = "Low"
		render()
		check(Renderer.debugCounts().aurasOn == 0 and Renderer.debugCounts().lightsOn == 0, "Low quality: other players' auras and lights off")
		Settings.quality = "High"
		render()
		check(Renderer.debugCounts().aurasOn >= 5, "back on High: near auras on again")
		-- Departure with effects active.
		local gui = alice.PlayerGui:FindFirstChild("CosmeticFX")
		local leaving = guests[1]
		local leavingTitle = gui:FindFirstChild("CosmeticTitle_" .. leaving.UserId)
		check(leavingTitle ~= nil, "guest title drawn")
		Engine.removePlayer(leaving)
		advance(0.5)
		render()
		check(gui:FindFirstChild("CosmeticTitle_" .. leaving.UserId) == nil and leavingTitle.Parent == nil, "player left: nameplate destroyed")
		check(Renderer.debugCounts().views == #game:GetService("Players"):GetPlayers(), "no view left for a departed player")
		-- Everyone else leaves too.
		for i = 2, #guests do
			Engine.removePlayer(guests[i])
		end
		advance(1)
		render()
		local strays = 0
		for _, child in gui:GetChildren() do
			local userId = tonumber(string.match(child.Name, "_(%d+)$"))
			if userId and userId > 7100 and userId < 7200 then
				strays += 1
			end
		end
		check(strays == 0, "no leftover cosmetic GUI from departed players")
		CosmeticService.setDevUnlock(sb, false)
		cameraObject.CFrame = savedCamera
		Settings.quality = savedQuality
	end)

	--------------------------------------------------------------------------
	scenario("V2 Cosmetics: Cosmetics screen", function()
		local Screen = creq("UI.Screens.Cosmetics")
		local cards = Screen.cards()
		check(#cards == #Cosmetics.list, "one card per cosmetic (" .. #cards .. ")")
		Screen.select("title")
		advance(0.2)
		local visible, wrong = 0, 0
		for _, card in cards do
			if card.frame.Visible then
				visible += 1
				if card.def.category ~= "title" then
					wrong += 1
				end
			end
		end
		check(visible == 5 and wrong == 0, "category filter (Titles: 5 cards)")
		equip(alice, "title", "title_drifter")
		advance(0.4)
		local byId = {}
		for _, card in cards do
			byId[card.def.id] = card
		end
		check(byId.title_drifter.status.Text == "EQUIPPED" and byId.title_drifter.action.label.Text == "Unequip", "equipped card: EQUIPPED + Unequip")
		-- A locked one.
		CosmeticService.reset(sa)
		advance(0.4)
		Screen.refresh()
		local lockedTitle = byId[lockedFor(sa, "title")]
		check(string.find(lockedTitle.status.Text, "LOCKED", 1, true) ~= nil and not lockedTitle.action.enabled, "locked card: LOCKED, equip disabled (" .. lockedTitle.def.id .. ")")
		check(lockedTitle.hint.Text ~= "" and lockedTitle.hint.Text == Screen.hintText(lockedTitle.def), "locked card says how to unlock it (" .. lockedTitle.hint.Text .. ")")
		local riftborn = Screen.hintText(Cosmetics.get("title_riftborn"))
		check(string.find(riftborn, "500", 1, true) ~= nil, "Power unlock hint names its threshold (" .. riftborn .. ")")
		check(string.find(Screen.hintText(Cosmetics.get("title_collector")), "%", 1, true) ~= nil or sa.data.cosmetics.owned.title_collector, "hint shows progress when measurable (" .. Screen.hintText(Cosmetics.get("title_collector")) .. ")")
		check(byId.title_drifter.status.Text == "OWNED" and byId.title_drifter.action.enabled, "owned card: OWNED, equip enabled")
		local hud = alice.PlayerGui:FindFirstChild("RiftHUD")
		local menuButton = nil
		for _, d in hud:GetDescendants() do
			if d.Name == "Cosmetics" and d.Parent and d.Parent.Name == "Menu" then
				menuButton = d
			end
		end
		check(menuButton ~= nil, "HUD menu has the Style button")
		-- The periodic job grants back what alice's real progress allows.
		advance(2.5)
		check(count(sa.data.cosmetics.owned) > 6, "progress-based cosmetics granted again by the periodic check")
	end)

	--------------------------------------------------------------------------
	scenario("V2 Cosmetics: phases 1-4 untouched", function()
		-- Abilities with cosmetics on.
		equip(alice, "trail", "trail_stardust")
		table.clear(sa.cooldowns)
		sa.stunnedUntil = 0
		local ok = AbilityService.use(alice, "dash")
		check(ok == true and sa.cooldowns.dash ~= nil, "Dash works with a trail equipped")
		-- Music config from phase 3 intact.
		check(Music.track("Explore").id == "rbxassetid://9046476113" and Music.track("Rift").id == "rbxassetid://9042760875" and Music.track("Chase").id == "rbxassetid://9046474891" and Music.track("ChaseIntense").id == "rbxassetid://1842546506" and Music.track("Stinger.ChaseStart").id == "rbxassetid://9044615289", "the 5 phase 3 music ids are intact")
		-- Sync: every cold change marked, nothing unmarked.
		advance(GameConfig.Sync.ColdAuditInterval + 0.5)
		check(Snapshot.unmarkedColdChanges == unmarkedBefore, "every cosmetic change marked the cold Sync (" .. Snapshot.unmarkedColdChanges - unmarkedBefore .. " unmarked)")
		-- Saved for real.
		local result
		Engine.task.spawn(function()
			result = DataService.save(sa, false)
		end)
		advance(1)
		local saved = Engine.dataStoreData[STORE .. alice.UserId]
		check(result ~= false and saved and saved.schema == GameConfig.Data.SchemaVersion and saved.cosmetics and saved.cosmetics.equipped.trail == "trail_stardust", "inventory + equipped persisted (current schema)")
		equip(alice, "trail", "")
		equip(alice, "title", "")
		equip(alice, "sanctuary", "")
	end)
end
