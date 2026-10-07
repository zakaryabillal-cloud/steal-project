--!nocheck
-- V2 phase 1 ("Foundations") scenarios. Called by tests/run.luau with its
-- helpers; runs after the V1 scenarios, on the same live server.
--
-- tests/fixtures/save_v1.json is a REAL save written by the V1 build
-- (commit b5f885c): a scripted session played on the V1 code (claims,
-- mutations, purchases incl. tier 2, settings, tips, Core production), then
-- dumped from the DataStore after the player left.

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Vector3 = require("@lune/roblox").Vector3

local STORE = "RiftHeist_Player_v1/u_"

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

return function(ctx)
	local scenario, check, advance, waitFor = ctx.scenario, ctx.check, ctx.advance, ctx.waitFor
	local sreq, shared, remote, Engine = ctx.sreq, ctx.shared, ctx.remote, ctx.Engine
	local sessionOf, teleport, insideOwnPlot, plotCenter = ctx.sessionOf, ctx.teleport, ctx.insideOwnPlot, ctx.plotCenter
	local hasNotification, clearLog = ctx.hasNotification, ctx.clearLog
	local alice, bob = ctx.alice(), ctx.bob()

	local DataSchema = sreq("Core.DataSchema")
	local DataService = sreq("Services.DataService")
	local Snapshot = sreq("Core.Snapshot")
	local Scheduler = sreq("Core.Scheduler")
	local StatusService = sreq("Services.StatusService")
	local AbilityService = sreq("Services.AbilityService")
	local EconomyService = sreq("Services.EconomyService")
	local RelicService = sreq("Services.RelicService")
	local CarryService = sreq("Services.CarryService")
	local Economy = shared("Economy")
	local Power = shared("Power")
	local PowerConfig = shared("Config.Power")
	local Status = shared("Status")
	local Abilities = shared("Config.Abilities")
	local GameConfig = shared("Config.GameConfig")
	local Layout = shared("Layout")
	local OUTSIDE = Vector3.new(0, Layout.GroundY + 3, -70)

	local function now()
		return Engine.workspace:GetServerTimeNow()
	end

	-- DataStore calls yield: run them on the engine scheduler.
	local function saveNow(session)
		local result
		Engine.task.spawn(function()
			result = DataService.save(session, false)
		end)
		advance(1)
		return result
	end

	local fixture = serde.decode("json", fs.readFile("tests/fixtures/save_v1.json"))

	--------------------------------------------------------------------------
	scenario("V2 data: unmarked cold-state changes during all V1 scenarios", function()
		-- Every gameplay path exercised so far marked its cold changes explicitly.
		check(Snapshot.unmarkedColdChanges == 0, "no cold change needed the audit (" .. Snapshot.unmarkedColdChanges .. ")")
	end)

	--------------------------------------------------------------------------
	scenario("V2 data: real V1 save migrates to schema 2 without loss", function()
		check(fixture.schema == 1 and #fixture.relics == 5, "fixture is a V1 save with 5 placed relics")
		local raw = deepCopy(fixture)
		local data = DataSchema.normalize(raw)
		check(deepEqual(raw, fixture), "normalize never mutates the stored record")
		check(data.schema == 2, "schema bumped to 2")
		check(data.essence == fixture.essence and data.lifetimeEssence == fixture.lifetimeEssence, "Essence preserved")
		check(data.coreStored == math.floor(fixture.coreStored), "Core preserved (whole Essence, as in V1)")
		check(data.lastSeen == fixture.lastSeen and data.playTime == fixture.playTime, "lastSeen + playTime preserved")
		check(data.tutorial == fixture.tutorial, "tutorial step preserved")
		check(deepEqual(data.upgrades, fixture.upgrades), "upgrades preserved (tier, pedestals, resonance, harness)")
		check(deepEqual(data.stats, fixture.stats), "stats preserved")
		check(deepEqual(data.tips, fixture.tips), "tips preserved")
		check(deepEqual(data.settings, fixture.settings), "settings preserved")
		local relicsOk = #data.relics == #fixture.relics
		for i, relic in fixture.relics do
			local got = data.relics[i]
			relicsOk = relicsOk and got ~= nil and got.uid == relic.uid and got.id == relic.id and got.level == relic.level and got.mutation == relic.mutation and got.slot == relic.slot
		end
		check(relicsOk, "every relic preserved (uid, id, level, mutation, slot)")
		local dexOk = true
		for relicId, entry in fixture.dex do
			local got = data.dex[relicId]
			dexOk = dexOk and got ~= nil and got.count == entry.count and got.first == entry.first and deepEqual(got.mutations, entry.mutations)
		end
		check(dexOk, "RiftDex preserved (counts, mutations, first seen)")
		check(deepEqual(data.abilities.loadout, { "dash", "pulse", "" }), "V1 kit equipped (Dash + Pulse)")
		check(data.abilities.unlocked.dash == true and data.abilities.unlocked.pulse == true, "default abilities unlocked")
		check(data.power.peak == 0, "Power record starts at 0 (filled on join)")
		check(deepEqual(DataSchema.normalize(DataSchema.serialize(data)), data), "serialize -> normalize round-trip is lossless")

		-- Live: the V1 player joins the V2 server.
		Engine.dataStoreData[STORE .. "4242"] = deepCopy(fixture)
		local vet = Engine.addPlayer("Veteran", 4242)
		advance(3)
		local s = sessionOf(vet)
		check(s and s.loaded and s.canSave and s.dataStatus == "loaded", "V1 profile loads on V2 with saving enabled")
		check(#s.data.relics == 5 and #RelicService.placedBy(4242) == 5, "all 5 relics restored on pedestals")
		local expected = Power.total(s.data.relics, s.data.upgrades, 4, 2)
		check(s.power == expected and s.power > 0, "Power computed from the V1 collection (" .. s.power .. ")")
		check(s.data.power.peak == s.power, "Power record initialised")
		check(vet.leaderstats.Power.Value == s.power, "Power leaderstat")
		Engine.removePlayer(vet)
		advance(2)
		local saved = Engine.dataStoreData[STORE .. "4242"]
		check(saved and saved.schema == 2 and saved.lock == nil, "saved back as schema 2, lock released")
		check(saved.essence == fixture.essence and saved.lifetimeEssence == fixture.lifetimeEssence, "Essence intact after a V2 session")
		check(deepEqual(saved.relics, fixture.relics), "relics intact after a V2 session")
		check(deepEqual(saved.upgrades, fixture.upgrades) and deepEqual(saved.dex, fixture.dex), "upgrades + RiftDex intact after a V2 session")
		check(saved.power.peak == expected and deepEqual(saved.abilities.loadout, { "dash", "pulse", "" }), "V2 fields persisted")

		-- Reconnection.
		vet = Engine.addPlayer("Veteran", 4242)
		advance(3)
		s = sessionOf(vet)
		check(s and s.dataStatus == "loaded" and #s.data.relics == 5, "reconnects with the full collection")
		check(s.data.power.peak == expected and s.power == expected, "Power + record survive a reconnection")
		Engine.removePlayer(vet)
		advance(2)
	end)

	--------------------------------------------------------------------------
	scenario("V2 data: a save from a newer schema is never overwritten", function()
		local future = {
			schema = 99,
			essence = 777,
			lifetimeEssence = 900,
			futureField = { nested = { "keep", "me" } },
			relics = { { uid = "f1", id = "ember_shard", level = 1, slot = 1 } },
		}
		Engine.dataStoreData[STORE .. "5151"] = deepCopy(future)
		check(DataSchema.isNewer(future) and not DataSchema.isNewer(fixture), "isNewer detects newer schemas only")
		local player = Engine.addPlayer("Future", 5151)
		advance(3)
		local s = sessionOf(player)
		check(s and s.loaded and s.canSave == false and s.dataStatus == "newer", "plays with temporary data, saving disabled")
		check(hasNotification(player, "n.dataNewer"), "player told to join another server")
		check(s.data.essence == 0, "newer data never normalised into this build")
		EconomyService.addEssence(s, 500)
		check(saveNow(s) == false, "explicit save refused")
		Engine.removePlayer(player)
		advance(2)
		check(deepEqual(Engine.dataStoreData[STORE .. "5151"], future), "newer record untouched (no lock, no downgrade)")

		-- Race: we loaded schema 2, then a newer server took the profile over.
		local racer = Engine.addPlayer("Racer", 5252)
		advance(3)
		local r = sessionOf(racer)
		check(r and r.canSave, "racer loaded normally")
		local newer = { schema = 3, essence = 999, newThing = 1, lock = { job = "harness-job", time = os.time() } }
		Engine.dataStoreData[STORE .. "5252"] = deepCopy(newer)
		r.data.essence = 5
		check(saveNow(r) == false, "save refused once a newer schema owns the record")
		check(deepEqual(Engine.dataStoreData[STORE .. "5252"], newer), "newer record not downgraded")
		check(r.canSave == false, "further saves disabled for the session")
		Engine.removePlayer(racer)
		advance(2)
		check(deepEqual(Engine.dataStoreData[STORE .. "5252"], newer), "leaving does not overwrite it either")
	end)

	--------------------------------------------------------------------------
	scenario("V2 data: tampered V2 fields are sanitised", function()
		local base = deepCopy(fixture)
		base.schema = 2
		base.abilities = { unlocked = { hax = true, dash = false, pulse = "yes" }, loadout = { "pulse", "dash", "dash" } }
		base.power = { peak = -50 }
		local data = DataSchema.normalize(base)
		check(data.abilities.unlocked.hax == nil, "unknown abilities dropped")
		check(data.abilities.unlocked.dash == true and data.abilities.unlocked.pulse == true, "defaults can never be locked")
		check(deepEqual(data.abilities.loadout, { "dash", "pulse", "" }), "abilities in the wrong slot reset to defaults")
		check(data.power.peak == 0, "negative Power record clamped")

		base.power = { peak = 0 / 0 }
		check(DataSchema.normalize(base).power.peak == 0, "NaN Power record rejected")
		base.power = { peak = 1e99 }
		check(DataSchema.normalize(base).power.peak == PowerConfig.MaxPeak, "absurd Power record clamped")
		base.power = "lots"
		base.abilities = "everything"
		local weird = DataSchema.normalize(base)
		check(weird.power.peak == 0 and deepEqual(weird.abilities.loadout, { "dash", "pulse", "" }), "wrong types fall back to defaults")
		base.abilities = { loadout = { string.rep("x", 500), {}, 7 } }
		check(deepEqual(DataSchema.normalize(base).abilities.loadout, { "dash", "pulse", "" }), "garbage loadout entries rejected")

		local v1 = deepCopy(fixture)
		v1.schema = "1"
		check(DataSchema.normalize(v1).schema == 2 and #DataSchema.normalize(v1).relics == 5, "non-numeric schema treated as V1 and migrated")
		v1.schema = nil
		check(#DataSchema.normalize(v1).relics == 5, "missing schema treated as V1")
	end)

	--------------------------------------------------------------------------
	scenario("V2 Power: formula, record, never client-controlled", function()
		check(Power.relic("ember_shard", 1, nil) == 10, "Common L1 = 10")
		check(math.abs(Power.relic("cosmic_eye", 3, "Void") - 84 * 1.6 * 1.45) < 1e-6, "Legendary L3 Void")
		check(Power.relic("nope", 1, nil) == 0, "unknown relic = 0")
		local upgrades = Economy.defaultUpgrades()
		upgrades.tier = 2
		upgrades.resonance = 3
		local b = Power.breakdown({ { id = "ember_shard", level = 1 } }, upgrades, 5, 2)
		check(b.relics == 10 and b.tier == PowerConfig.Tier[3] and b.dex == 5 * 3 + 2 * 2 and b.upgrades == 24, "breakdown parts")
		check(b.total == b.relics + b.tier + b.dex + b.upgrades, "total = sum of parts")

		local s = sessionOf(alice)
		EconomyService.recompute(s)
		local before, peakBefore = s.power, s.data.power.peak
		check(before > 0 and peakBefore >= before, "alice has Power and a record")
		local placed = RelicService.placedBy(alice.UserId)
		check(#placed > 0, "alice has placed relics")
		insideOwnPlot(alice)
		local ok = CarryService.dissolvePlaced(s, placed[1].uid)
		check(ok == true, "dissolving a displayed relic works")
		check(s.power < before, "current Power drops when a relic leaves the Sanctuary")
		check(s.data.power.peak == peakBefore, "Power record never drops")

		Engine.fireServer(remote("Settings"), alice, "power", 1e9)
		Engine.fireServer(remote("Settings"), alice, "peak", 1e9)
		advance(0.3)
		check(s.data.power.peak == peakBefore and s.power < before, "clients cannot write Power")
	end)

	--------------------------------------------------------------------------
	scenario("V2 Status: shared rules", function()
		local state = Status.new()
		local r = Status.resolveHard(state, 0, 100, 0.6)
		check(r.ok and r.duration == 0.6 and r.steadyUntil == 100 + GameConfig.Status.SteadyTime, "stun accepted, steady 2.5s (V1 value)")
		r = Status.resolveHard(state, r.steadyUntil, 101, 0.6)
		check(not r.ok and r.reason == "steady", "second stun inside steady rejected")
		r = Status.resolveHard(state, 0, 100, 30)
		check(r.ok and r.duration == GameConfig.Status.MaxHardDuration and r.steadyUntil == 100 + 3, "hard control capped at 2s, steady extends past it")
		check(not Status.resolveHard(state, 0, 100, 0 / 0).ok, "NaN duration rejected")
		check(not Status.resolveHard(state, 0, 100, -1).ok, "negative duration rejected")
		Status.applySlow(state, 100, "a", 0.3, 2)
		Status.applySlow(state, 100, "b", 0.5, 2)
		check(math.abs(Status.speedFactor(state, 100.5) - 0.5) < 1e-9, "slows do not stack: strongest wins")
		Status.applySlow(state, 100, "c", 0.95, 99)
		check(math.abs(Status.speedFactor(state, 100.5) - (1 - GameConfig.Status.MaxSlow)) < 1e-9, "slow capped at 60%")
		check(Status.slowEnds(state, 100) == 100 + GameConfig.Status.MaxSlowDuration, "slow duration capped")
		check(Status.speedFactor(state, 200) == 1, "slows expire")
		Status.applyBuff(state, 300, "shield", 1)
		check(not Status.resolveHard(state, 0, 300.5, 0.5).ok, "shield blocks hard control")
		check(not Status.applySlow(state, 300.5, "d", 0.3, 1), "shield blocks slows")
		check(not Status.applyBuff(state, 300, "godmode", 5), "unknown buff rejected")
	end)

	--------------------------------------------------------------------------
	scenario("V2 Status: live anti stun-lock, slows, roots, reconnection", function()
		local s = sessionOf(bob)
		teleport(bob, OUTSIDE)
		advance(0.5)
		s.steadyUntil = 0
		s.spawnProtectedUntil = 0
		local humanoid = bob.Character:FindFirstChild("Humanoid")
		local base = humanoid.WalkSpeed

		-- Swarm: control requested every 0.1s for 10s (e.g. many attackers).
		local stunnedSamples, applied = 0, 0
		for _ = 1, 100 do
			if StatusService.applyControl(s, "stun", 0.6) then
				applied += 1
			end
			advance(0.1)
			if now() < s.stunnedUntil then
				stunnedSamples += 1
			end
		end
		check(applied >= 3 and applied <= 5, "only one stun per steady window (" .. applied .. " applied)")
		check(stunnedSamples / 100 <= 0.3, string.format("stunned at most ~24%% of the time (%.0f%%)", stunnedSamples))
		advance(3)
		check(humanoid.WalkSpeed == base, "speed restored after the swarm")

		StatusService.applySlow(s, "frost", 0.3, 2)
		StatusService.applySlow(s, "trap", 0.5, 2)
		check(math.abs(humanoid.WalkSpeed - base * 0.5) < 1e-6, "strongest slow applied (no stacking)")
		advance(2.3)
		check(humanoid.WalkSpeed == base, "speed restored when slows end")

		check(StatusService.applyControl(s, "root", 1) == true, "root applied")
		check(humanoid.WalkSpeed == 0, "rooted players cannot walk")
		local _, reason = AbilityService.use(bob, "dash")
		check(reason == "rooted", "movement abilities blocked while rooted")
		s.cooldowns.pulse = 0
		check(AbilityService.use(bob, "pulse") == true, "non-movement abilities still usable while rooted")
		advance(1.3)
		check(humanoid.WalkSpeed == base, "root expires")

		advance(3)
		StatusService.applyBuff(s, "shield", 1)
		local okShield, why = StatusService.applyControl(s, "stun", 0.6)
		check(not okShield and why == "shield", "shield blocks control")
		advance(1.2)
		s.spawnProtectedUntil = now() + 5
		local okProt, whyProt = StatusService.applyControl(s, "stun", 0.6)
		check(not okProt and whyProt == "protected", "spawn protection blocks control")
		s.spawnProtectedUntil = 0

		-- Leave while stunned and slowed, then come back.
		s.steadyUntil = 0
		StatusService.applyControl(s, "stun", 0.6)
		StatusService.applySlow(s, "frost", 0.4, 3)
		Engine.removePlayer(bob)
		advance(2)
		bob = Engine.addPlayer("Bob", 1002)
		ctx.setBob(bob)
		advance(4)
		local again = sessionOf(bob)
		check(again and again.loaded and again.canSave, "bob reconnects")
		check(again.stunnedUntil == 0 and next(again.status.slows) == nil, "no status carried over a reconnection")
		check(deepEqual(again.data.abilities.loadout, { "dash", "pulse", "" }), "loadout restored")
	end)

	--------------------------------------------------------------------------
	scenario("V2 Abilities: framework, validation, legacy remotes", function()
		local s = sessionOf(alice)
		teleport(alice, plotCenter(alice) + Vector3.new(0, 0, -20))
		advance(0.5)
		s.cooldowns.dash = 0
		s.cooldowns.pulse = 0
		s.steadyUntil = now() + 30 -- keep alice out of other tests' control
		Engine.fireServer(remote("UseAbility"), alice, "dash")
		advance(0.1)
		local dashReady = s.cooldowns.dash
		check(dashReady and math.abs(dashReady - now() - Abilities.get("dash").cooldown * 0.9) < 0.2, "UseAbility(dash) sets the V1 server cooldown")
		local ok, reason = AbilityService.use(alice, "dash")
		check(not ok and reason == "cooldown", "cooldown enforced")

		local keysBefore = 0
		for _ in s.cooldowns do
			keysBefore += 1
		end
		for _, bad in { 123, {}, "blink", string.rep("x", 1000), true } do
			Engine.fireServer(remote("UseAbility"), alice, bad)
		end
		Engine.fireServer(remote("UseAbility"), alice)
		advance(0.5)
		local keysAfter = 0
		for _ in s.cooldowns do
			keysAfter += 1
		end
		check(keysAfter == keysBefore, "garbage ability ids rejected without side effects")

		Engine.fireServer(remote("UseAbility"), alice, "pulse", { cooldown = 0, radius = 1e9 })
		advance(0.1)
		check(math.abs(s.cooldowns.pulse - now() - Abilities.get("pulse").cooldown) < 0.2, "client payload cannot change cooldowns")

		s.cooldowns.dash = 0
		Engine.fireServer(remote("Dash"), alice)
		advance(0.1)
		check(s.cooldowns.dash > now(), "V1 Dash remote still works (alias)")
		s.cooldowns.pulse = 0
		Engine.fireServer(remote("Pulse"), alice)
		advance(0.1)
		check(s.cooldowns.pulse > now(), "V1 Pulse remote still works (alias)")

		s.cooldowns.dash = 0
		s.data.abilities.loadout[1] = ""
		ok, reason = AbilityService.use(alice, "dash")
		check(not ok and reason == "notEquipped", "unequipped abilities cannot be used")
		s.data.abilities.loadout[1] = "dash"

		s.steadyUntil = 0
		StatusService.applyControl(s, "stun", 0.6)
		ok, reason = AbilityService.use(alice, "dash")
		check(not ok and reason == "stunned", "stunned players cannot use abilities")
		advance(1)

		-- Loadout.
		local invoke = function(...)
			return Engine.invokeServer(remote("SetLoadout"), alice, ...)
		end
		teleport(alice, OUTSIDE)
		advance(0.4)
		ok, reason = invoke(1, "dash")
		check(ok == false and reason == "notHome", "loadout only changes at home")
		insideOwnPlot(alice)
		local cooldownBefore = s.cooldowns.dash
		ok = invoke(1, "dash")
		check(ok == true, "equip at home")
		check(s.cooldowns.dash == cooldownBefore, "re-equipping never resets a cooldown")
		check(invoke(3, "") == true, "optional slot can be emptied")
		check(invoke(1, "") == false, "mandatory slot cannot be emptied")
		check(invoke(1, "pulse") == false and invoke(2, "dash") == false, "abilities only fit their own slot")
		check(invoke(4, "dash") == false and invoke(0, "dash") == false and invoke(1.5, "dash") == false, "invalid slot index rejected")
		check(invoke("1", "dash") == false and invoke(1, {}) == false and invoke(1, nil) == false, "malformed arguments rejected")
		check(deepEqual(s.data.abilities.loadout, { "dash", "pulse", "" }), "loadout unchanged by bad requests")
		check(Abilities.canEquip(1, "dash", {}) == false, "locked abilities cannot be equipped")

		-- Spam.
		s.cooldowns.dash = 0
		for _ = 1, 300 do
			Engine.fireServer(remote("UseAbility"), alice, "dash")
		end
		advance(0.5)
		check(s.cooldowns.dash > now() and s.cooldowns.dash - now() < Abilities.get("dash").cooldown, "spam: one dash, no errors")
		s.steadyUntil = 0
	end)

	--------------------------------------------------------------------------
	scenario("V2 Sync: hot fields often, cold fields only when they change", function()
		local s = sessionOf(alice)
		teleport(alice, plotCenter(alice) + Vector3.new(0, 0, -20))
		advance(1)
		clearLog(alice)
		for _ = 1, 6 do
			EconomyService.addEssence(s, 1)
			advance(0.3)
		end
		local hot, withCold = 0, 0
		local lastHot
		for _, entry in Engine.clientLog[alice] or {} do
			if entry.remote == "Sync" then
				hot += 1
				lastHot = entry.args[1]
				if entry.args[1].dex ~= nil then
					withCold += 1
				end
			end
		end
		check(hot >= 5, "hot changes are pushed (" .. hot .. " syncs)")
		check(withCold == 0, "RiftDex/cold state not re-sent with hot changes")
		check(lastHot and lastHot.essence == s.data.essence and lastHot.power == s.power and lastHot.status ~= nil, "hot payload carries Essence, Power, status")
		local hotSize = #serde.encode("json", lastHot)
		local fullSize = #serde.encode("json", Snapshot.build(s))
		check(hotSize < fullSize, string.format("hot payload smaller than full state (%d vs %d bytes)", hotSize, fullSize))

		clearLog(alice)
		Engine.fireServer(remote("Settings"), alice, "music", 0.31)
		advance(0.3)
		local coldSeen = false
		for _, entry in Engine.clientLog[alice] or {} do
			if entry.remote == "Sync" and entry.args[1].settings and entry.args[1].settings.music == 0.31 and entry.args[1].dex then
				coldSeen = true
			end
		end
		check(coldSeen, "cold change pushed with the cold half")

		-- Client Store merges both halves (alice runs the real client).
		local Store = ctx.Loader.require("client", ctx.game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.Store)
		local state = Store.state
		local cold = Snapshot.cold(s)
		check(state.settings.music == 0.31 and deepEqual(state.dex, cold.dex) and deepEqual(state.upgrades, cold.upgrades), "client Store holds the cold state")
		check(state.essence == s.data.essence and state.power == s.power and state.powerPeak == s.data.power.peak, "client Store holds the hot state")
		check(deepEqual(state.loadout, s.data.abilities.loadout), "client Store holds the loadout")

		-- HUD: Power row + one button per equipped slot (+ Seal).
		advance(0.5)
		local hud = alice:FindFirstChild("PlayerGui"):FindFirstChild("RiftHUD")
		local powerLabel, buttons = nil, {}
		for _, d in hud:GetDescendants() do
			if d.Name == "Power" and d.ClassName == "TextLabel" then
				powerLabel = d
			end
			if d.Parent and d.Parent.Name == "Abilities" then
				buttons[d.Name] = true
			end
		end
		check(powerLabel ~= nil and string.find(powerLabel.Text, shared("Util.Format").commas(math.floor(s.power)), 1, true) ~= nil, "HUD shows the current Power (" .. (powerLabel and powerLabel.Text or "?") .. ")")
		check(buttons.dash and buttons.pulse and buttons.seal and not buttons[""], "HUD buttons follow the loadout (Dash, Pulse, Seal; empty Utility hidden)")

		-- Audit catches a change that forgot to mark itself.
		local before = Snapshot.unmarkedColdChanges
		s.data.stats.claimed += 1
		advance(GameConfig.Sync.ColdAuditInterval + 0.5)
		check(Snapshot.unmarkedColdChanges == before + 1, "audit detected the unmarked change")
		check(Store.state.stats.claimed == s.data.stats.claimed, "and pushed it to the client")
		s.data.stats.claimed -= 1
		sreq("Core.Sessions").markCold(s)
		advance(0.3)
	end)

	--------------------------------------------------------------------------
	scenario("V2 Scheduler: single heartbeat, isolated jobs", function()
		local names = {}
		for _, name in Scheduler.names() do
			names[name] = true
		end
		local expected = { "Plot.tick", "Economy.production", "Economy.collect", "Character.voidKill", "Events.tick", "Rift.spawn", "Rift.expiry", "Carry.deposit", "Carry.dropped", "Movement.guard", "Sync.push", "Sync.audit", "Data.autosave" }
		local missing = {}
		for _, name in expected do
			if not names[name] then
				table.insert(missing, name)
			end
		end
		check(#missing == 0, "every former service loop runs on the Scheduler (" .. table.concat(missing, ",") .. ")")

		local productionBefore = Scheduler.stats("Economy.production").runs
		local boomActive = true
		Scheduler.every("Test.boom", 0.5, function()
			if boomActive then
				error("boom")
			end
		end)
		local slowRuns = 0
		Scheduler.every("Test.slow", 0.5, function()
			slowRuns += 1
			Engine.task.wait(2) -- the engine's virtual-time wait (game code gets it as `task`)
		end)
		advance(4)
		local boom = Scheduler.stats("Test.boom")
		check(boom.errors >= 6 and boom.runs == boom.errors, "a failing job keeps being scheduled (" .. boom.errors .. " errors)")
		check(Scheduler.stats("Economy.production").runs >= productionBefore + 3, "other jobs unaffected by the failing one")
		check(slowRuns <= 2, "a yielding job is never re-entered while busy (" .. slowRuns .. " runs)")
		boomActive = false
		local registered = pcall(Scheduler.every, "Test.boom", 1, function() end)
		check(not registered, "duplicate job names rejected")
	end)
end
