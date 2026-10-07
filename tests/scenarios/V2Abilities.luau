--!nocheck
-- V2 phase 4 ("Abilities") scenarios. Called by tests/run.luau with its
-- helpers; runs on the same live server after the earlier scenarios.
--
--   * catalogue, schema v3, unlocks (Power record + Essence, future materials),
--     Studio test unlock, loadout (only at home), harmony switches;
--   * every ability in a test arena built from parts far from the island
--     (walls, ledges, ceilings): normal use, cooldowns, range, obstacles,
--     carrying, control + anti stun-lock, harmonies;
--   * the 14 grapple anchors of the real world (each one reachable);
--   * security: spam, unequipped / unknown abilities, forged payloads,
--     forged harmonies, cooldown bypass attempts, movement guard;
--   * cleanup: death, respawn, disconnect, unequip, orphan sweep;
--   * real two-player chases: theft -> chase -> mobility -> control ->
--     counterplay -> recovery / securing, checked for duplication, lost
--     state, abusive teleports and cooldown bypass.

local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Enum = roblox.Enum

return function(ctx)
	local scenario, check, advance, waitFor = ctx.scenario, ctx.check, ctx.advance, ctx.waitFor
	local sreq, shared, remote, Engine, Loader, game = ctx.sreq, ctx.shared, ctx.remote, ctx.Engine, ctx.Loader, ctx.game
	local sessionOf, teleport, insideOwnPlot, plotCenter = ctx.sessionOf, ctx.teleport, ctx.insideOwnPlot, ctx.plotCenter
	local hasNotification, clearLog, prompt, claimRelic = ctx.hasNotification, ctx.clearLog, ctx.prompt, ctx.claimRelic
	local alice, bob = ctx.alice(), ctx.bob()

	local Sessions = sreq("Core.Sessions")
	local Snapshot = sreq("Core.Snapshot")
	local DataSchema = sreq("Core.DataSchema")
	local AbilityService = sreq("Services.AbilityService")
	local StatusService = sreq("Services.StatusService")
	local MovementGuard = sreq("Services.MovementGuard")
	local CarryService = sreq("Services.CarryService")
	local RelicService = sreq("Services.RelicService")
	local PlotService = sreq("Services.PlotService")
	local EconomyService = sreq("Services.EconomyService")
	local CharacterService = sreq("Services.CharacterService")
	local Common = sreq("Abilities.Common")
	local Blink = sreq("Abilities.Blink")
	local Grapple = sreq("Abilities.Grapple")
	local RuneTrap = sreq("Abilities.RuneTrap")
	local Decoy = sreq("Abilities.Decoy")
	local Dash = sreq("Abilities.Dash")
	local Pulse = sreq("Abilities.Pulse")
	local Abilities = shared("Config.Abilities")
	local GameConfig = shared("Config.GameConfig")
	local WorldFeatures = shared("WorldFeatures")
	local Layout = shared("Layout")
	local Status = shared("Status")
	local Strings = shared("Locale.Strings")
	local A = GameConfig.Abilities
	local H = GameConfig.Harmonies

	local Client = game:GetService("StarterPlayer").StarterPlayerScripts.Client
	local function creq(path)
		local node = Client
		for part in string.gmatch(path, "[^%.]+") do
			node = node:FindFirstChild(part)
		end
		return Loader.require("client", node)
	end

	local function now()
		return Engine.workspace:GetServerTimeNow()
	end
	local function root(player)
		return player.Character:FindFirstChild("HumanoidRootPart")
	end
	local function pos(player)
		return root(player).Position
	end
	local function humanoid(player)
		return player.Character:FindFirstChild("Humanoid")
	end

	-- Clears statuses, immunities and cooldowns (test isolation).
	local function fresh(s)
		table.clear(s.cooldowns)
		s.steadyUntil = 0
		s.stunnedUntil = 0
		s.spawnProtectedUntil = 0
		Status.clear(s.status)
		s.moveAllowance = nil
		CharacterService.refreshSpeed(s)
		CharacterService.refreshCollision(s)
		Sessions.markDirty(s)
	end

	-- Server-side shortcut: unlock + equip (the real paths are tested below).
	local function give(s, abilityId)
		local def = Abilities.get(abilityId)
		s.data.abilities.unlocked[abilityId] = true
		s.data.abilities.loadout[Abilities.slotIndex(def.slot)] = abilityId
		Sessions.markCold(s)
	end

	-- Harmonies come from displayed relics; tests pin them explicitly.
	local function setHarmonies(s, list)
		s.harmonyRelics = list
		table.clear(s.data.abilities.harmonyOff)
		Sessions.markCold(s)
	end
	local function restoreHarmonies(s)
		table.clear(s.data.abilities.harmonyOff)
		Sessions.markCold(s)
		EconomyService.recompute(s)
	end

	local function fxLog(player, kind, from)
		local list = {}
		for i, entry in Engine.clientLog[player] or {} do
			if i > (from or 0) and entry.remote == "FX" and entry.args[1] == kind then
				table.insert(list, entry.args[2])
			end
		end
		return list
	end
	local function logSize(player)
		return #(Engine.clientLog[player] or {})
	end
	local function knockbacks(player, from)
		local n = 0
		for i, entry in Engine.clientLog[player] or {} do
			if i > (from or 0) and entry.remote == "Knockback" then
				n += 1
			end
		end
		return n
	end
	local function slowOf(s)
		return Status.slowAmount(s.status, now())
	end
	local function cooldownLeft(s, id)
		return math.max(0, (s.cooldowns[id] or 0) - now())
	end
	local function near(a, b, tolerance)
		return math.abs(a - b) <= (tolerance or 0.05)
	end

	--------------------------------------------------------------------------
	-- Test arena: a floor of parts far from the island (no terrain there).
	--------------------------------------------------------------------------
	local ARENA = Vector3.new(1600, 300, 0) -- floor top centre
	local arena = Engine.createInternal("Folder", "TestArena", Engine.workspace)
	local function part(name, size, cf, extra)
		local p = Engine.createInternal("Part", name, nil)
		p.Anchored = true
		p.Size = size
		p.CFrame = cf
		if extra then
			for key, value in extra do
				p[key] = value
			end
		end
		p.Parent = arena
		return p
	end
	part("Floor", Vector3.new(160, 2, 160), CFrame.new(ARENA - Vector3.new(0, 1, 0)))
	-- Root position for a character standing on the floor at (x, z).
	local function stand(x, z)
		return ARENA + Vector3.new(x, 3, z)
	end
	-- Teleport (server-sanctioned) and wait for the guard's grace to end.
	local function place(player, position, settle)
		teleport(player, position)
		advance(settle or 0.1)
	end

	local sa, sb = sessionOf(alice), sessionOf(bob)
	-- The phase 1 audit test deliberately left one unmarked change.
	local unmarkedBefore = Snapshot.unmarkedColdChanges
	local savedLoadoutA = table.clone(sa.data.abilities.loadout)
	local savedLoadoutB = table.clone(sb.data.abilities.loadout)

	--------------------------------------------------------------------------
	scenario("V2 Abilities: catalogue, harmonies, strings, modules", function()
		local perSlot = {}
		for _, def in Abilities.list do
			perSlot[def.slot] = (perSlot[def.slot] or 0) + 1
			if not def.default then
				check(def.unlock and def.unlock.power > 0 and def.unlock.essence > 0 and next(def.unlock.materials) == nil, def.id .. ": unlock = Power record + Essence, no material yet")
			end
			for _, lang in { "en", "fr" } do
				for _, suffix in { "", ".desc", ".stats" } do
					if Strings[lang]["ability." .. def.id .. suffix] == nil then
						check(false, "missing string ability." .. def.id .. suffix .. " (" .. lang .. ")")
					end
				end
			end
			check(Client.Abilities:FindFirstChild(def.module) ~= nil and game:GetService("ServerScriptService").Server.Abilities:FindFirstChild(def.module) ~= nil, def.id .. ": server + client modules")
		end
		check(#Abilities.list == 9 and perSlot.Mobility == 3 and perSlot.Control == 3 and perSlot.Utility == 3, "9 abilities, 3 per slot")
		check(Abilities.Slots[1].keyboard == Enum.KeyCode.Q and Abilities.Slots[1].gamepad == Enum.KeyCode.ButtonR1, "Mobility Q / R1")
		check(Abilities.Slots[2].keyboard == Enum.KeyCode.F and Abilities.Slots[2].gamepad == Enum.KeyCode.ButtonL1, "Control F / L1")
		check(Abilities.Slots[3].keyboard == Enum.KeyCode.R and Abilities.Slots[3].gamepad == Enum.KeyCode.ButtonR2, "Utility R / R2")
		check(Abilities.SealKeys.keyboard == Enum.KeyCode.G and Abilities.SealKeys.gamepad == Enum.KeyCode.ButtonY, "Seal G / Y (outside the loadout)")
		local relics = {}
		for _, harmony in Abilities.Harmonies do
			table.insert(relics, harmony.relic)
			for _, lang in { "en", "fr" } do
				if Strings[lang]["harmony." .. harmony.relic] == nil then
					check(false, "missing string harmony." .. harmony.relic .. " (" .. lang .. ")")
				end
			end
		end
		table.sort(relics)
		check(table.concat(relics, ",") == "chrono_glass,cosmic_eye,frost_lotus,magma_heart,storm_crystal,void_cube", "exactly the 6 planned harmony relics")
		-- Effective values.
		local all = { storm_crystal = true, void_cube = true, magma_heart = true, frost_lotus = true, chrono_glass = true, cosmic_eye = true }
		check(Abilities.tuning(Abilities.get("blink"), all).Range == H.VoidBlink.Range, "Void Cube -> Blink range")
		check(Abilities.cooldown(Abilities.get("pulse"), all) == H.Eruption.Cooldown and Abilities.tuning(Abilities.get("pulse"), all).Eruption, "Magma Heart -> Eruption")
		check(near(Abilities.cooldown(Abilities.get("shield"), all), A.Shield.Cooldown * H.ChronoGlass.CooldownFactor, 1e-6), "Chrono Glass -> Utility cooldown x0.85")
		check(Abilities.cooldown(Abilities.get("blink"), all) == A.Blink.Cooldown, "Chrono Glass does not touch other slots")
		check(Abilities.tuning(Abilities.get("frost_wave"), all).Slow == H.FrostLotus.Slow, "Frost Lotus -> stronger Frost Wave")
		check(Abilities.tuning(Abilities.get("dash"), all).StormTrail ~= nil, "Storm Crystal -> Dash trail")
		check(Abilities.tuning(Abilities.get("blink"), {}).Range == A.Blink.Range and Abilities.get("blink").tuning.Range == A.Blink.Range, "tuning merge never mutates the base values")
		check(H.FrostLotus.Slow <= GameConfig.Status.MaxSlow and H.Eruption.Stun <= GameConfig.Status.MaxHardDuration, "harmonies stay inside the anti stun-lock caps")
		check(A.Grapple.Speed < GameConfig.Security.MaxHorizontalSpeed, "grapple speed under the movement guard threshold")
		local active = Abilities.activeHarmonies({ "magma_heart", "ember_shard", "void_cube" }, { void_cube = true })
		check(active.magma_heart and not active.void_cube and not active.ember_shard, "active = displayed harmony relics minus switched off")
	end)

	--------------------------------------------------------------------------
	scenario("V2 Abilities: schema 3 (harmony switches) migrates and sanitises", function()
		local v2 = {
			schema = 2,
			essence = 1234,
			lifetimeEssence = 5000,
			relics = { { uid = "m1", id = "magma_heart", level = 2, slot = 1 } },
			abilities = { unlocked = { dash = true, pulse = true, blink = true }, loadout = { "blink", "pulse", "" } },
			power = { peak = 321 },
		}
		local before = DataSchema.normalize(v2)
		check(v2.schema == 2 and v2.abilities.harmonyOff == nil, "normalize never mutates the stored v2 record")
		check(before.schema == 3 and next(before.abilities.harmonyOff) == nil, "v2 -> v3: every harmony starts enabled")
		check(before.essence == 1234 and before.power.peak == 321 and before.abilities.unlocked.blink and before.abilities.loadout[1] == "blink" and #before.relics == 1, "v2 progression kept (Essence, Power record, unlocks, loadout, relics)")
		local tampered = table.clone(v2)
		tampered.schema = 3
		tampered.abilities = { unlocked = { dash = true, pulse = true }, loadout = { "dash", "pulse", "" }, harmonyOff = { magma_heart = true, ember_shard = true, void_cube = "yes", [5] = true, cosmic_eye = false } }
		local data = DataSchema.normalize(tampered)
		check(data.abilities.harmonyOff.magma_heart == true, "known switch kept")
		check(data.abilities.harmonyOff.ember_shard == nil and data.abilities.harmonyOff.void_cube == nil and data.abilities.harmonyOff[5] == nil and data.abilities.harmonyOff.cosmic_eye == nil, "unknown relics / non-true values dropped")
		local round = DataSchema.normalize(DataSchema.serialize(data))
		check(round.abilities.harmonyOff.magma_heart == true and round.schema == 3, "serialize -> normalize round trip keeps the switches")
		tampered.abilities.harmonyOff = "all"
		check(next(DataSchema.normalize(tampered).abilities.harmonyOff) == nil, "wrong type falls back to all enabled")
		check(Snapshot.ColdKeys and table.find(Snapshot.ColdKeys, "harmonyOff") and table.find(Snapshot.HotKeys, "harmonies"), "Sync: switches cold, displayed harmonies hot")
	end)

	--------------------------------------------------------------------------
	scenario("V2 Abilities: unlocks (Power record + Essence, materials reserved)", function()
		-- Rules through the service; the remote (rate-limited) is exercised once.
		local unlock = function(id)
			return AbilityService.unlock(alice, id)
		end
		-- Eligibility notice when the Power record crosses a threshold.
		sa.data.abilities.unlocked.shield = nil
		sa.data.abilities.unlocked.frost_wave = nil
		Sessions.markCold(sa)
		clearLog(alice)
		sa.data.power.peak = 0
		EconomyService.recompute(sa)
		check(sa.data.power.peak >= Abilities.get("shield").unlock.power, "record restored by the recompute (" .. sa.data.power.peak .. ")")
		check(hasNotification(alice, "n.abilityEligible"), "player told an ability became unlockable")

		local peak = sa.data.power.peak
		sa.data.power.peak = 10
		sa.data.essence = 1e6
		local ok, reason = unlock("shield")
		check(ok == false and reason == "power", "Power record too low -> refused")
		sa.data.power.peak = peak
		sa.data.essence = 10
		ok, reason = unlock("shield")
		check(ok == false and reason == "notEnough" and sa.data.essence == 10, "not enough Essence -> refused, nothing spent")
		sa.data.essence = 5000
		ok, reason = Engine.invokeServer(remote("UnlockAbility"), alice, "shield")
		check(ok == true and sa.data.abilities.unlocked.shield == true, "unlocked through the remote (" .. tostring(reason) .. ")")
		check(sa.data.essence == 5000 - Abilities.get("shield").unlock.essence, "exact Essence cost spent")
		ok, reason = unlock("shield")
		check(ok == false and reason == "owned" and sa.data.essence == 5000 - Abilities.get("shield").unlock.essence, "second unlock refused, nothing spent")
		check(unlock("dash") == false and unlock("nope") == false and unlock(42) == false and unlock({}) == false, "defaults / unknown / garbage refused")
		-- Future boss / Forge materials: a requirement cannot be met yet.
		local materials = Abilities.get("frost_wave").unlock.materials
		materials.void_shard = 3
		sa.data.essence = 1e6
		sa.data.power.peak = math.max(peak, 1000)
		ok, reason = unlock("frost_wave")
		check(ok == false and reason == "materials" and not sa.data.abilities.unlocked.frost_wave, "material requirement blocks the unlock (no materials system yet)")
		table.clear(materials)
		ok = unlock("frost_wave")
		check(ok == true, "unlocks once no material is required")
		advance(0.3)
		local Store = creq("Controllers.Store")
		check(Store.state.unlocked.shield == true and Store.state.unlocked.frost_wave == true, "client Store sees the unlocks (cold sync)")
		-- Unlocking never equips by itself.
		check(not table.find(sa.data.abilities.loadout, "shield"), "unlock does not change the loadout")
	end)

	--------------------------------------------------------------------------
	scenario("V2 Abilities: loadout only at home, every rule checked by the server", function()
		local invoke = function(slot, id)
			return AbilityService.setLoadout(alice, slot, id)
		end
		place(alice, plotCenter(alice) + Vector3.new(0, 0, -60))
		local ok, reason = invoke(3, "shield")
		check(ok == false and reason == "notHome", "away from the Sanctuary -> refused")
		place(alice, plotCenter(bob) + Vector3.new(0, 0, -8))
		ok, reason = invoke(3, "shield")
		check(ok == false and reason == "notHome", "inside someone else's Sanctuary -> refused")
		insideOwnPlot(alice)
		ok = Engine.invokeServer(remote("SetLoadout"), alice, 3, "shield")
		check(ok == true and sa.data.abilities.loadout[3] == "shield", "equipped at home (remote)")
		ok, reason = invoke(1, "grapple")
		check(ok == false and reason == "locked", "locked ability refused")
		check(invoke(2, "shield") == false and invoke(1, "frost_wave") == false, "wrong slot refused")
		check(invoke(2, "") == false and invoke(3, "") == true and invoke(3, "shield") == true, "only Utility may be emptied")
		check(invoke(9, "shield") == false and invoke(0, "dash") == false and invoke(-1, "dash") == false and invoke(1.5, "dash") == false, "invalid slots refused")
		check(invoke("1", "dash") == false and invoke(1, { "dash" }) == false and invoke(nil, nil) == false and invoke(1, string.rep("d", 64)) == false, "garbage refused")
		-- A cooldown survives swapping out and back.
		sa.cooldowns.shield = now() + 10
		invoke(3, "")
		invoke(3, "shield")
		check(cooldownLeft(sa, "shield") > 9, "re-equipping never resets a cooldown")
		advance(0.3)
		local Store = creq("Controllers.Store")
		check(Store.state.loadout[3] == "shield", "client Store has the new loadout")
		-- Client loadout screen.
		local Loadout = creq("UI.Screens.Loadout")
		local cards = Loadout.cards()
		check(#cards == #Abilities.list, "loadout screen: one card per ability (" .. #cards .. ")")
		local byId = {}
		for _, card in cards do
			byId[card.def.id] = card
		end
		advance(0.6)
		check(Loadout.atHome() == true, "client sees it is at home")
		check(byId.shield.action.label.Text == "Remove" and byId.shield.action.enabled, "equipped Utility card offers Remove")
		check(byId.dash.action.label.Text == "Equipped" and not byId.dash.action.enabled, "equipped mandatory card shows Equipped")
		check(byId.grapple.action.label.Text == "Unlock", "locked card offers Unlock (" .. byId.grapple.action.label.Text .. ")")
		check(string.find(byId.grapple.requirement.Text, "320", 1, true) ~= nil, "requirement shown (" .. byId.grapple.requirement.Text .. ")")
		check(byId.frost_wave.action.label.Text == "Equip" and byId.frost_wave.action.enabled, "unlocked card offers Equip at home")
		place(alice, plotCenter(alice) + Vector3.new(0, 0, -60))
		advance(0.7)
		check(Loadout.atHome() == false and not byId.frost_wave.action.enabled and byId.frost_wave.action.label.Text == "At home only", "away: equip disabled with a hint")
	end)

	--------------------------------------------------------------------------
	scenario("V2 Abilities: harmony switches + Studio test unlock", function()
		local set = function(relic, enabled)
			return AbilityService.setHarmony(alice, relic, enabled)
		end
		place(alice, plotCenter(alice) + Vector3.new(0, 0, -60))
		local ok, reason = set("magma_heart", false)
		check(ok == false and reason == "notHome", "switches only at home")
		insideOwnPlot(alice)
		check(set("magma_heart", false) == true and sa.data.abilities.harmonyOff.magma_heart == true, "harmony switched off")
		check(set("magma_heart", true) == true and sa.data.abilities.harmonyOff.magma_heart == nil, "and back on")
		check(set("ember_shard", false) == false and set("magma_heart", "no") == false and set({}, false) == false, "unknown relic / garbage refused")
		advance(1.5)
		check(Engine.invokeServer(remote("SetHarmony"), alice, "void_cube", false) == true, "switch through the remote")
		advance(0.3)
		check(creq("Controllers.Store").state.harmonyOff.void_cube == true, "client Store mirrors the switch")
		set("void_cube", true)
		check(not AbilityService.activeHarmonies(sa).void_cube or table.find(sa.harmonyRelics, "void_cube") ~= nil, "a harmony needs the relic displayed")

		-- Studio test unlock (DevCommands /rh abilities): session only.
		insideOwnPlot(bob)
		check(AbilityService.setLoadout(bob, 1, "grapple") == false, "bob cannot equip a locked grapple")
		AbilityService.setDevUnlock(sb, true)
		check(AbilityService.setLoadout(bob, 1, "grapple") == true, "dev unlock: every ability equippable")
		check(Snapshot.unlockedView(sb).phase == true and sb.data.abilities.unlocked.phase == nil, "dev unlock is never written to the save data")
		local reloaded = DataSchema.normalize(DataSchema.serialize(sb.data))
		check(reloaded.abilities.loadout[1] == "dash", "a saved dev loadout is re-validated on the next join")
		AbilityService.setDevUnlock(sb, false)
		check(sb.data.abilities.loadout[1] == "dash", "turning it off restores a legal loadout")
	end)

	--------------------------------------------------------------------------
	scenario("V2 Abilities: Blink (wind-up, walls, ledges, ceilings, carrying)", function()
		give(sa, "blink")
		setHarmonies(sa, {})
		local function blinkFrom(x, z, direction)
			fresh(sa)
			local start = stand(x, z)
			place(alice, start, 1.6)
			local ok, reason = AbilityService.use(alice, "blink", direction)
			advance(0.45)
			return ok, reason, start, pos(alice)
		end
		-- Open floor.
		fresh(sa)
		place(alice, stand(0, 0), 1.6)
		local start = pos(alice)
		local ok = AbilityService.use(alice, "blink", Vector3.new(1, 0, 0))
		check(ok and Blink.pendingCount() == 1, "blink accepted, wind-up pending")
		advance(0.1)
		check((pos(alice) - start).Magnitude < 0.01, "no movement before the wind-up ends")
		advance(0.35)
		local landed = pos(alice)
		check(near(landed.X - start.X, A.Blink.Range, 0.05) and near(landed.Z, start.Z) and near(landed.Y, ARENA.Y + 3, 0.05), "lands 16 studs ahead, on the floor")
		check((sa.lastPosition - landed).Magnitude < 0.05, "movement guard told about the server move")
		check(near(cooldownLeft(sa, "blink"), A.Blink.Cooldown * 0.9 - 0.45, 0.1), "cooldown set by the server")
		advance(1.2)
		check((pos(alice) - landed).Magnitude < 0.05, "never pulled back by the guard")
		local _, reason = AbilityService.use(alice, "blink", Vector3.new(1, 0, 0))
		check(reason == "cooldown", "cooldown enforced")

		-- Walls: never through, whatever the angle.
		local wall = part("Wall", Vector3.new(1, 14, 40), CFrame.new(ARENA + Vector3.new(8, 7, 0)))
		local through = 0
		for k = -4, 4 do
			local a = math.rad(k * 10)
			local _, _, origin, final = blinkFrom(0, 0, Vector3.new(math.cos(a), 0, math.sin(a)))
			if final.X - ARENA.X >= 7.5 then
				through += 1
			end
			if k == 0 then
				check(final.X - origin.X <= 7.5 - A.Blink.WallMargin + 0.01 and final.X - origin.X >= A.Blink.MinDistance, "stops before the wall (" .. string.format("%.2f", final.X - origin.X) .. ")")
			end
		end
		check(through == 0, "9 angles: never through the wall")
		wall:Destroy()
		local thin = part("ThinWall", Vector3.new(0.2, 14, 40), CFrame.new(ARENA + Vector3.new(6, 7, 0)))
		local _, _, _, final = blinkFrom(0, 0, Vector3.new(1, 0, 0))
		check(final.X - ARENA.X < 5.9, "never through a 0.2-stud wall")
		thin:Destroy()
		local close = part("CloseWall", Vector3.new(1, 14, 40), CFrame.new(ARENA + Vector3.new(2.5, 7, 0)))
		fresh(sa)
		place(alice, stand(0, 0), 1.6)
		local blockedOk, blockedReason = AbilityService.use(alice, "blink", Vector3.new(1, 0, 0))
		check(blockedOk == false and blockedReason == "blocked" and cooldownLeft(sa, "blink") == 0, "wall too close: refused at no cost")
		close:Destroy()
		-- A low pillar (knee height) also stops it.
		local low = part("LowWall", Vector3.new(1, 2, 40), CFrame.new(ARENA + Vector3.new(9, 1, 0)))
		_, _, _, final = blinkFrom(0, 0, Vector3.new(1, 0, 0))
		check(final.X - ARENA.X < 8.5, "a knee-high obstacle stops it too")
		low:Destroy()

		-- The client can only give a direction, never a destination.
		local okFar, _, origin2, final2 = blinkFrom(0, 0, Vector3.new(1e6, 0, 0))
		check(okFar and near((final2 - origin2).Magnitude, A.Blink.Range, 0.1), "huge vector = direction only (16 studs)")
		local okPoint, _, origin3, final3 = blinkFrom(0, 0, ARENA + Vector3.new(60, 0, 0))
		check(okPoint and (final3 - origin3).Magnitude <= A.Blink.Range + 0.01, "a world position is only read as a direction")
		local okNaN, _, origin4, final4 = blinkFrom(0, 0, Vector3.new(0 / 0, 0, 0))
		check(okNaN and near((final4 - origin4).Magnitude, A.Blink.Range, 0.1) and final4.Z < origin4.Z, "NaN direction -> facing (-Z)")
		local okTable, _, origin5, final5 = blinkFrom(0, 0, { destination = ARENA + Vector3.new(0, 0, 70) })
		check(okTable and (final5 - origin5).Magnitude <= A.Blink.Range + 0.01, "a forged table payload changes nothing")

		-- Ledges: never into the void, onto a lower floor only within MaxDrop.
		_, _, _, final = blinkFrom(74, 0, Vector3.new(1, 0, 0))
		check(final.X - ARENA.X <= 80 and near(final.Y, ARENA.Y + 3, 0.05), "at the edge of the void: stays on the floor")
		local ledge = part("Ledge", Vector3.new(20, 2, 30), CFrame.new(ARENA + Vector3.new(94, -11, 0)))
		_, _, _, final = blinkFrom(74, 0, Vector3.new(1, 0, 0))
		check(near(final.X - ARENA.X, 90, 0.05) and near(final.Y, ARENA.Y - 10 + 3, 0.05), "drops onto a ledge 10 studs lower (within MaxDrop)")
		ledge.CFrame = CFrame.new(ARENA + Vector3.new(94, -31, 0))
		_, _, _, final = blinkFrom(74, 0, Vector3.new(1, 0, 0))
		check(final.X - ARENA.X <= 80 and near(final.Y, ARENA.Y + 3, 0.05), "a 30-stud drop is refused (walks back onto the floor)")
		ledge:Destroy()
		-- Low ceiling at the destination.
		local ceiling = part("Ceiling", Vector3.new(8, 1, 30), CFrame.new(ARENA + Vector3.new(16, 5.5, 0)))
		_, _, _, final = blinkFrom(0, 0, Vector3.new(1, 0, 0))
		check(final.X - ARENA.X < 12, "never ends under a ceiling without headroom (" .. string.format("%.1f", final.X - ARENA.X) .. ")")
		ceiling:Destroy()

		-- Interrupted by a stun or a root during the wind-up.
		fresh(sa)
		place(alice, stand(0, 0), 1.6)
		local from = pos(alice)
		local mark = logSize(alice)
		AbilityService.use(alice, "blink", Vector3.new(1, 0, 0))
		StatusService.applyControl(sa, "stun", 0.6)
		advance(0.45)
		check((pos(alice) - from).Magnitude < 0.01 and #fxLog(alice, "BlinkFail", mark) == 1, "stun during the wind-up cancels it")
		fresh(sa)
		mark = logSize(alice)
		AbilityService.use(alice, "blink", Vector3.new(1, 0, 0))
		StatusService.applyControl(sa, "root", 1)
		advance(0.45)
		check((pos(alice) - from).Magnitude < 0.01, "root during the wind-up cancels it")
		local _, rootedReason = AbilityService.use(alice, "blink", Vector3.new(1, 0, 0))
		check(rootedReason == "rooted" or rootedReason == "cooldown", "rooted players cannot blink")

		-- Carrying: half range; Void Cube: longer range, smaller penalty.
		claimRelic(alice, "ember_shard")
		check(#sa.carrying == 1, "alice carries a relic")
		_, _, origin, final = blinkFrom(0, 0, Vector3.new(1, 0, 0))
		check(near((final - origin).Magnitude, A.Blink.Range * A.Blink.CarryFactor, 0.1), "carrying: range x0.5 (8 studs)")
		check(#sa.carrying == 1, "the relic is still carried after the blink")
		setHarmonies(sa, { "void_cube" })
		_, _, origin, final = blinkFrom(0, 0, Vector3.new(1, 0, 0))
		check(near((final - origin).Magnitude, H.VoidBlink.Range * H.VoidBlink.CarryFactor, 0.1), "Void Cube while carrying: 15 studs")
		CarryService.dropAll(sa, nil)
		_, _, origin, final = blinkFrom(0, 0, Vector3.new(1, 0, 0))
		check(near((final - origin).Magnitude, H.VoidBlink.Range, 0.1), "Void Cube: 20 studs")
		setHarmonies(sa, {})

		-- Sealed Sanctuary: no blinking into it.
		local plot = PlotService.get(sb.plot)
		sb.cooldowns.seal = 0
		PlotService.seal(sb)
		local cf = plot.origin
		local outside = (cf * CFrame.new(0, 3, -(Layout.PlatformRadius + 6))).Position
		fresh(sa)
		place(alice, outside, 1.6)
		local inward = -cf.LookVector
		local sealedOk, sealedReason = AbilityService.use(alice, "blink", inward)
		advance(0.45)
		check(sealedOk == false and sealedReason == "blocked", "blink into a sealed Sanctuary refused (" .. tostring(sealedReason) .. ")")
		check(not Common.sealedAgainst(sa, pos(alice)) and not PlotService.isInside(plot.index, pos(alice)), "still outside the sealed Sanctuary")
		plot.sealedUntil = 0
		PlotService.tick()
		fresh(sa)
		local beforeOpen = pos(alice)
		local openOk = AbilityService.use(alice, "blink", inward)
		advance(0.45)
		check(openOk and (pos(alice) - beforeOpen).Magnitude >= A.Blink.MinDistance, "same blink allowed once the Seal is down")
		restoreHarmonies(sa)
	end)

	--------------------------------------------------------------------------
	-- Real grapple anchors: a standing spot with range + line of sight.
	local spots = {}
	local function findSpot(index)
		if spots[index] ~= nil then
			return spots[index] or nil
		end
		local anchor = WorldFeatures.GrapplePoints[index].position
		local params = Common.params(sa)
		for _, radius in { 14, 20, 26, 32, 38 } do
			for k = 0, 23 do
				local a = k / 24 * math.pi * 2
				local xz = anchor + Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius)
				local hit = Engine.workspace:Raycast(Vector3.new(xz.X, anchor.Y + 6, xz.Z), Vector3.new(0, -90, 0), params)
				if hit and hit.Normal.Y > 0.5 then
					local candidate = hit.Position + Vector3.new(0, 3, 0)
					local okCheck = Grapple.check(sa, { Position = candidate }, index, A.Grapple)
					if okCheck and PlotService.plotAt(candidate) == nil then
						spots[index] = candidate
						return candidate
					end
				end
			end
		end
		spots[index] = false
		return nil
	end

	scenario("V2 Abilities: Grapple (anchors only, range, sight, guard, cut by control)", function()
		local missing = {}
		for index, spec in WorldFeatures.GrapplePoints do
			if not findSpot(index) then
				table.insert(missing, spec.name)
			end
		end
		check(#missing == 0, "all 14 prepared anchors can be grappled from somewhere (" .. table.concat(missing, ", ") .. ")")

		give(sa, "grapple")
		setHarmonies(sa, {})
		local index = 1
		for i = 1, #WorldFeatures.GrapplePoints do
			if findSpot(i) then
				index = i
				break
			end
		end
		local spot = findSpot(index)
		local anchor = WorldFeatures.GrapplePoints[index].position
		-- Forged payloads: never an arbitrary target.
		fresh(sa)
		place(alice, spot, 1.6)
		for _, bad in { 0, -1, #WorldFeatures.GrapplePoints + 1, 1.5, "1", { 1 }, 0 / 0, math.huge, Vector3.new(1, 2, 3), nil } do
			local okBad, why = AbilityService.use(alice, "grapple", bad)
			if okBad or why ~= "payload" then
				check(false, "forged anchor " .. tostring(bad) .. " refused as payload (" .. tostring(why) .. ")")
			end
		end
		check(cooldownLeft(sa, "grapple") == 0, "forged anchors cost nothing")
		-- Range: an anchor far away.
		local far = nil
		for i, spec in WorldFeatures.GrapplePoints do
			if (spec.position - spot).Magnitude > A.Grapple.Range + 10 then
				far = i
				break
			end
		end
		local _, farReason = AbilityService.use(alice, "grapple", far)
		check(farReason == "range", "out-of-range anchor refused")
		-- Line of sight: a wall between.
		local mid = (spot + anchor) / 2
		local blocker = part("Blocker", Vector3.new(30, 30, 1), CFrame.lookAt(mid, anchor))
		local _, losReason = AbilityService.use(alice, "grapple", index)
		check(losReason == "los" and cooldownLeft(sa, "grapple") == 0, "anchor behind an obstacle refused at no cost")
		blocker:Destroy()

		-- Valid grapple while carrying; the pull stays under the guard threshold.
		claimRelic(alice, "tide_pearl")
		place(alice, spot, 1.6)
		local mark = logSize(alice)
		local ok = AbilityService.use(alice, "grapple", index)
		check(ok and Grapple.flightOf(sa) ~= nil and #fxLog(alice, "Grapple", mark) == 1, "grapple accepted (flight + cable FX)")
		local flight = Grapple.flightOf(sa)
		check(near(flight.speed, A.Grapple.Speed * A.Grapple.CarryFactor, 1e-6), "carrying: pull speed x0.8")
		check(near(cooldownLeft(sa, "grapple"), A.Grapple.Cooldown * 0.9, 0.1), "cooldown set")
		-- Simulate the client pull (client-owned physics) at the allowed speed.
		local position = pos(alice)
		local steps = 0
		while (anchor - position).Magnitude > A.Grapple.ArriveDistance and steps < 60 do
			local step = math.min(flight.speed * 0.1, (anchor - position).Magnitude)
			position += (anchor - position).Unit * step
			Engine.moveTo(alice, position)
			advance(0.1)
			steps += 1
		end
		check(#sa.carrying == 1, "relic still carried after the whole flight (guard never fired)")
		check((pos(alice) - position).Magnitude < 0.01, "never pulled back")
		advance(1)
		check(Grapple.flightOf(sa) == nil, "flight over")
		-- A teleport disguised as a grapple is still caught.
		fresh(sa)
		place(alice, spot, 1.6)
		AbilityService.use(alice, "grapple", index)
		Engine.moveTo(alice, spot + Vector3.new(300, 0, 0))
		advance(0.6)
		check(#sa.carrying == 0, "teleport during a grapple: relic dropped by the guard")
		check((pos(alice) - (spot + Vector3.new(300, 0, 0))).Magnitude > 50, "and pulled back")
		advance(1)

		-- Hard control cuts the cable.
		fresh(sa)
		place(alice, spot, 1.6)
		mark = logSize(alice)
		AbilityService.use(alice, "grapple", index)
		StatusService.applyControl(sa, "stun", 0.6)
		check(Grapple.flightOf(sa) == nil and #fxLog(alice, "GrappleEnd", mark) == 1, "stun cuts the grapple")

		-- Client: target picking and the real client path.
		local Targeting = creq("Controllers.GrappleTargeting")
		local headPick = Targeting.pick(spot + Vector3.new(0, 1.5, 0), (anchor - spot).Unit)
		check(headPick ~= nil, "client finds an anchor from the spot")
		restoreHarmonies(sa)
	end)

	--------------------------------------------------------------------------
	scenario("V2 Abilities: Frost Wave (slow only, sight, caps, Frost Lotus)", function()
		give(sa, "frost_wave")
		setHarmonies(sa, {})
		local function cast(bobAt)
			fresh(sa)
			fresh(sb)
			place(alice, stand(0, 0), 1.6)
			place(bob, bobAt, 0.1)
			local mark = logSize(bob)
			local ok = AbilityService.use(alice, "frost_wave")
			advance(0.05)
			return ok, mark
		end
		local ok, mark = cast(stand(10, 0))
		check(ok and near(slowOf(sb), A.FrostWave.Slow), "target in range slowed 40%")
		check(sb.stunnedUntil <= now() and knockbacks(bob, mark) == 0, "no stun, no knockback")
		local base = humanoid(bob).WalkSpeed / (1 - A.FrostWave.Slow)
		advance(A.FrostWave.SlowDuration + 0.2)
		check(slowOf(sb) == 0 and near(humanoid(bob).WalkSpeed, base, 0.01), "slow ends after 2.5s, speed restored")
		cast(stand(A.FrostWave.Radius + 2, 0))
		check(slowOf(sb) == 0, "out of range: untouched")
		local wall = part("FrostWall", Vector3.new(1, 12, 20), CFrame.new(ARENA + Vector3.new(5, 6, 0)))
		cast(stand(10, 0))
		check(slowOf(sb) == 0, "behind a wall: untouched")
		wall:Destroy()
		-- Shield blocks hard control only: the slow still lands.
		fresh(sb)
		StatusService.applyBuff(sb, "shield", 2)
		place(alice, stand(0, 0), 0.1)
		place(bob, stand(10, 0), 0.1)
		sa.cooldowns.frost_wave = 0
		AbilityService.use(alice, "frost_wave")
		check(near(slowOf(sb), A.FrostWave.Slow), "a shield does not stop slows")
		-- Slows never stack (strongest wins, capped).
		StatusService.applySlow(sb, "trap", 0.6, 2)
		check(near(slowOf(sb), 0.6), "frost + trap: strongest only (60%)")
		-- Frost Lotus.
		setHarmonies(sa, { "frost_lotus" })
		cast(stand(15, 0))
		check(near(slowOf(sb), H.FrostLotus.Slow) and near(Status.slowEnds(sb.status, now()) - now(), H.FrostLotus.SlowDuration, 0.1), "Frost Lotus: 50% for 3s at 15 studs")
		restoreHarmonies(sa)
		advance(3.2)
	end)

	--------------------------------------------------------------------------
	scenario("V2 Abilities: Pulse / Eruption and the anti stun-lock", function()
		give(sa, "pulse")
		setHarmonies(sa, {})
		fresh(sa)
		fresh(sb)
		place(alice, stand(0, 0), 1.6)
		place(bob, stand(8, 0), 0.1)
		local mark = logSize(bob)
		check(AbilityService.use(alice, "pulse") == true and sb.stunnedUntil > now() and knockbacks(bob, mark) == 1, "Pulse: immediate stun + knockback")
		local steady = sb.steadyUntil
		check(steady - now() >= GameConfig.Status.SteadyTime - 0.05, "target becomes steady (immune)")
		sa.cooldowns.pulse = 0
		AbilityService.use(alice, "pulse")
		check(sb.steadyUntil == steady and knockbacks(bob, mark) == 1, "second Pulse inside the steady window does nothing")
		-- Eruption (Magma Heart): telegraphed, bigger, slower.
		setHarmonies(sa, { "magma_heart" })
		fresh(sa)
		fresh(sb)
		place(bob, stand(14, 0), 0.1)
		mark = logSize(bob)
		AbilityService.use(alice, "pulse")
		check(Pulse.pendingCount() == 1 and sb.stunnedUntil <= now(), "Eruption: wind-up first, nobody hit yet")
		check(#fxLog(bob, "EruptionWindup", mark) == 1, "the telegraph is broadcast")
		advance(H.Eruption.Windup + 0.1)
		check(sb.stunnedUntil > now() and knockbacks(bob, mark) == 1 and near(cooldownLeft(sa, "pulse"), H.Eruption.Cooldown - H.Eruption.Windup - 0.1, 0.15), "Eruption hits at 14 studs (radius 15), cooldown 10s")
		-- Dodge by leaving the ring during the wind-up.
		fresh(sa)
		fresh(sb)
		place(bob, stand(12, 0), 0.1)
		AbilityService.use(alice, "pulse")
		place(bob, stand(24, 0), 0.1)
		advance(H.Eruption.Windup + 0.1)
		check(sb.stunnedUntil <= now(), "stepping out of the ring dodges the Eruption")
		-- Caster stunned during the wind-up: cancelled.
		fresh(sa)
		fresh(sb)
		place(bob, stand(8, 0), 0.1)
		AbilityService.use(alice, "pulse")
		StatusService.applyControl(sa, "stun", 0.6)
		advance(H.Eruption.Windup + 0.1)
		check(sb.stunnedUntil <= now() and Pulse.pendingCount() == 0, "a stun on the caster cancels the Eruption")
		restoreHarmonies(sa)
	end)

	--------------------------------------------------------------------------
	scenario("V2 Abilities: Rune Trap (arming, one per player, counterplay, cleanup)", function()
		give(sa, "rune_trap")
		setHarmonies(sa, {})
		fresh(sa)
		fresh(sb)
		place(alice, stand(0, 0), 1.6)
		place(bob, stand(30, 0), 0.1)
		local ok = AbilityService.use(alice, "rune_trap")
		local trap = RuneTrap.of(sa)
		check(ok and trap ~= nil and near(trap.position.Y, ARENA.Y, 0.05) and near(trap.position.X, ARENA.X, 0.05), "trap placed on the ground under the caster")
		check(trap.part.Parent ~= nil and trap.part.Parent.Name == "Abilities" and not trap.part.CanCollide and not trap.part.CanQuery, "visible, non-colliding server part")
		-- Not armed yet.
		place(bob, stand(0, 0), 0.1)
		check(slowOf(sb) == 0 and RuneTrap.of(sa) ~= nil, "stepping on it before it arms does nothing")
		place(bob, stand(30, 0), 0.1)
		advance(A.RuneTrap.ArmTime + 0.1)
		check(trap.part:GetAttribute("Armed") == true, "armed after 1s")
		-- The owner never triggers it.
		place(alice, stand(0.5, 0), 0.3)
		check(RuneTrap.of(sa) ~= nil, "owner walks over it safely")
		place(alice, stand(-20, 0), 0.1)
		place(bob, stand(1, 1), 0.3)
		check(near(slowOf(sb), A.RuneTrap.Slow) and RuneTrap.of(sa) == nil and trap.part.Parent == nil, "an enemy triggers it: slowed 60%, trap consumed")
		check(sb.stunnedUntil <= now(), "a slow, never a stun")
		-- One per player: a new trap replaces the old one.
		fresh(sa)
		place(alice, stand(0, 0), 0.1)
		AbilityService.use(alice, "rune_trap")
		local first = RuneTrap.of(sa).part
		sa.cooldowns.rune_trap = 0
		place(alice, stand(-30, 0), 0.1)
		AbilityService.use(alice, "rune_trap")
		check(first.Parent == nil and RuneTrap.of(sa).part ~= first and RuneTrap.count() >= 1, "second trap replaces the first")
		local folder = Engine.workspace:FindFirstChild("Abilities")
		local count = 0
		for _, child in folder:GetChildren() do
			if child:GetAttribute("OwnerId") == alice.UserId then
				count += 1
			end
		end
		check(count == 1, "only one trap part per player")
		-- Spam: cooldown + rate limit.
		for _ = 1, 50 do
			Engine.fireServer(remote("UseAbility"), alice, "rune_trap")
		end
		advance(0.5)
		count = 0
		for _, child in folder:GetChildren() do
			if child:GetAttribute("OwnerId") == alice.UserId then
				count += 1
			end
		end
		check(count == 1, "trap spam: still one trap")
		-- No ground (in the air) / someone else's Sanctuary: refused at no cost.
		fresh(sa)
		place(alice, ARENA + Vector3.new(0, 40, 0), 0.05)
		local okAir, airReason = AbilityService.use(alice, "rune_trap")
		check(okAir == false and airReason == "noGround" and cooldownLeft(sa, "rune_trap") == 0, "no ground: refused")
		place(alice, plotCenter(bob) + Vector3.new(0, 0, -8), 0.1)
		local okForeign, foreignReason = AbilityService.use(alice, "rune_trap")
		check(okForeign == false and foreignReason == "forbidden", "never inside someone else's Sanctuary")
		-- A decoy running over an armed rune sets it off (and pops).
		give(sb, "decoy")
		fresh(sa)
		fresh(sb)
		place(alice, stand(0, -40), 0.1)
		AbilityService.use(alice, "rune_trap")
		advance(A.RuneTrap.ArmTime + 0.1)
		place(alice, stand(-50, -40), 0.1)
		place(bob, stand(10, -40), 0.1)
		AbilityService.use(bob, "decoy", Vector3.new(-1, 0, 0))
		advance(1)
		check(RuneTrap.of(sa) == nil and slowOf(sb) == 0, "a decoy baits the rune: trap spent, the real player untouched")
		local baitPopped = true
		for _, record in Decoy.active() do
			if record.owner == sb then
				baitPopped = false
			end
		end
		check(baitPopped, "and the decoy pops on it")
		-- Orphan sweep: a stray trap part disappears.
		local stray = Engine.createInternal("Part", "RuneTrap", folder)
		advance(1.2)
		check(stray.Parent == nil, "orphan trap part swept")
		-- Expiry.
		fresh(sa)
		place(alice, stand(0, 0), 0.1)
		AbilityService.use(alice, "rune_trap")
		local timed = RuneTrap.of(sa).part
		advance(A.RuneTrap.Lifetime + 0.5)
		check(timed.Parent == nil and RuneTrap.of(sa) == nil, "expires after 45s")
		-- Unequip removes it.
		fresh(sa)
		place(alice, stand(0, 0), 0.1)
		AbilityService.use(alice, "rune_trap")
		local equipped = RuneTrap.of(sa).part
		insideOwnPlot(alice)
		AbilityService.setLoadout(alice, 2, "pulse")
		check(equipped.Parent == nil and RuneTrap.of(sa) == nil, "unequipping removes the trap")
		advance(2.2)
		restoreHarmonies(sa)
	end)

	--------------------------------------------------------------------------
	scenario("V2 Abilities: Shield (hard control only, mobility trade-off)", function()
		give(sb, "shield")
		give(sa, "pulse")
		setHarmonies(sb, {})
		setHarmonies(sa, {})
		fresh(sa)
		fresh(sb)
		place(alice, stand(0, 0), 1.6)
		place(bob, stand(8, 0), 0.1)
		claimRelic(bob, "rune_tablet")
		place(bob, stand(8, 0), 0.1)
		local base = humanoid(bob).WalkSpeed
		check(AbilityService.use(bob, "shield") == true and sb.status.shieldUntil > now(), "shield up")
		check(near(humanoid(bob).WalkSpeed, base * (1 - A.Shield.SelfSlow), 0.01), "bearer slowed 20% while shielded")
		check(bob.Character:GetAttribute("ShieldUntil") == sb.status.shieldUntil, "every client can draw the bubble")
		local mark = logSize(bob)
		AbilityService.use(alice, "pulse")
		check(sb.stunnedUntil <= now() and knockbacks(bob, mark) == 0 and #sb.carrying == 1, "Pulse blocked: no stun, no knockback, relic kept")
		check(StatusService.applyControl(sb, "root", 1) == false, "root blocked")
		sa.cooldowns.frost_wave = 0
		give(sa, "frost_wave")
		AbilityService.use(alice, "frost_wave")
		check(slowOf(sb) >= A.FrostWave.Slow, "not invincible: slows still apply")
		advance(A.Shield.Duration + 0.2)
		check(sb.status.shieldUntil <= now(), "shield gone after 2s")
		give(sa, "pulse")
		sa.cooldowns.pulse = 0
		AbilityService.use(alice, "pulse")
		check(sb.stunnedUntil > now() and #sb.carrying == 0, "after the shield, Pulse works again (relic dropped)")
		-- Chrono Glass: Utility cooldown x0.85.
		fresh(sb)
		setHarmonies(sb, { "chrono_glass" })
		AbilityService.use(bob, "shield")
		check(near(cooldownLeft(sb, "shield"), A.Shield.Cooldown * H.ChronoGlass.CooldownFactor, 0.05), "Chrono Glass: 13.6s cooldown")
		restoreHarmonies(sa)
		restoreHarmonies(sb)
		advance(2.5)
	end)

	--------------------------------------------------------------------------
	scenario("V2 Abilities: Decoy (no authority, no duplication, popped by control)", function()
		give(sb, "decoy")
		setHarmonies(sb, {})
		setHarmonies(sa, {})
		fresh(sa)
		fresh(sb)
		place(bob, stand(0, 20), 1.6)
		claimRelic(bob, "verdant_seed")
		place(bob, stand(0, 20), 1.6)
		local relicCount, carriedBefore, essenceBefore = 0, table.clone(sb.carrying), sb.data.essence
		for _ in RelicService.all() do
			relicCount += 1
		end
		local anchorsBefore = #Engine.workspace:FindFirstChild("Relics"):GetChildren()
		local mark = logSize(alice)
		check(AbilityService.use(bob, "decoy", Vector3.new(1, 0, 0)) == true, "decoy cast")
		local fx = fxLog(alice, "Decoy", mark)[1]
		check(fx and near(fx.speed, humanoid(bob).WalkSpeed, 0.01) and near(fx.direction.X, 1) and (fx.origin - stand(0, 20)).Magnitude < 0.1, "decoy runs from the caster, at the caster's speed")
		check(fx and #fx.relics == 1 and fx.relics[1].id == "verdant_seed", "decoy shows a copy of the carried relic")
		local after = 0
		for _ in RelicService.all() do
			after += 1
		end
		check(after == relicCount and #Engine.workspace:FindFirstChild("Relics"):GetChildren() == anchorsBefore, "no relic entity created")
		check(#sb.carrying == #carriedBefore and sb.carrying[1] == carriedBefore[1] and sb.data.essence == essenceBefore, "carrying and Essence unchanged")
		check(#Decoy.active() == 1, "one decoy record")
		-- Client draws it.
		local AbilityFX = creq("Controllers.AbilityFX")
		advance(0.2)
		check(AbilityFX.debugCounts().decoys == 1, "alice's client draws the decoy")
		local clone = Engine.workspace:FindFirstChild("AbilityFX"):FindFirstChild(bob.Name)
		local collides = false
		if clone then
			for _, d in clone:GetDescendants() do
				if d:IsA("BasePart") and (d.CanCollide or d.CanQuery or d.CanTouch) then
					collides = true
				end
			end
		end
		check(clone ~= nil and not collides, "the copy has no physical presence")
		-- Popped by a control ability.
		local record = Decoy.active()[1]
		local at = Decoy.position(record, now())
		give(sa, "pulse")
		place(bob, stand(-60, 60), 0.1)
		place(alice, at + Vector3.new(-6, 0, 0), 0.1)
		mark = logSize(alice)
		AbilityService.use(alice, "pulse")
		check(#Decoy.active() == 0 and #fxLog(alice, "DecoyEnd", mark) == 1, "Pulse pops it")
		advance(0.2)
		check(AbilityFX.debugCounts().decoys == 0, "client copy removed")
		-- Stops before walls; expires after 4s; one per owner.
		local wall = part("DecoyWall", Vector3.new(1, 12, 20), CFrame.new(ARENA + Vector3.new(15, 6, 20)))
		fresh(sb)
		place(bob, stand(0, 20), 0.1)
		AbilityService.use(bob, "decoy", Vector3.new(1, 0, 0))
		record = Decoy.active()[1]
		check(record and record.length <= 14.5 - 1.9, "path stops before the wall (" .. string.format("%.1f", record and record.length or -1) .. ")")
		wall:Destroy()
		sb.cooldowns.decoy = 0
		AbilityService.use(bob, "decoy", Vector3.new(-1, 0, 0))
		check(#Decoy.active() == 1, "a new decoy replaces the old one")
		advance(A.Decoy.Duration + 0.2)
		check(#Decoy.active() == 0, "expires after 4s")
		-- Cosmic Eye: revealed within range, popped on touch.
		setHarmonies(sa, { "cosmic_eye" })
		fresh(sb)
		place(alice, stand(20, 20), 0.1)
		mark = logSize(alice)
		local markBob = logSize(bob)
		AbilityService.use(bob, "decoy", Vector3.new(1, 0, 0))
		advance(0.3)
		check(#fxLog(alice, "Reveal", mark) == 1 and #fxLog(bob, "Reveal", markBob) == 0, "Cosmic Eye holder (only) sees through the decoy")
		advance(1.2)
		check(#Decoy.active() == 0, "the holder in its path pops it on touch")
		CarryService.dropAll(sb, nil)
		restoreHarmonies(sa)
		restoreHarmonies(sb)
	end)

	--------------------------------------------------------------------------
	scenario("V2 Abilities: Spectral Phase (players only, relic visible, Cosmic Eye)", function()
		give(sb, "phase")
		setHarmonies(sb, {})
		setHarmonies(sa, {})
		fresh(sa)
		fresh(sb)
		place(alice, stand(0, 0), 1.6)
		place(bob, stand(10, 0), 0.1)
		check(AbilityService.use(bob, "phase") == true, "phase cast")
		local group = "Phase" .. sb.plot
		local allPhased = true
		for _, d in bob.Character:GetDescendants() do
			if d:IsA("BasePart") and d.CollisionGroup ~= group then
				allPhased = false
			end
		end
		check(allPhased, "character moved to " .. group)
		check(not Engine.groupsCollide(group, "Owner" .. sa.plot) and not Engine.groupsCollide(group, "Wanderer") and not Engine.groupsCollide(group, "Phase" .. sa.plot), "passes through every player group")
		check(Engine.groupsCollide(group, "Default") and Engine.groupsCollide(group, "Barrier" .. sa.plot), "still blocked by the world and other Sanctuaries' barriers")
		check(not Engine.groupsCollide(group, "Barrier" .. sb.plot), "own barrier stays open")
		check(bob.Character:GetAttribute("PhaseUntil") == sb.status.phaseUntil, "every client can draw the ghost")
		advance(A.Phase.Duration + 0.2)
		check(root(bob).CollisionGroup == "Owner" .. sb.plot, "collides with players again after 1.5s")
		-- Cosmic Eye: revealed and ended by control.
		setHarmonies(sa, { "cosmic_eye" })
		give(sa, "frost_wave")
		fresh(sa)
		fresh(sb)
		local mark = logSize(alice)
		AbilityService.use(bob, "phase")
		advance(0.15)
		check(#fxLog(alice, "Reveal", mark) == 1, "Cosmic Eye reveals the phasing player")
		AbilityService.use(alice, "frost_wave")
		check(sb.status.phaseUntil <= now() and root(bob).CollisionGroup == "Owner" .. sb.plot, "Cosmic Eye: control ends the phase")
		-- Without the Eye, control does not end it.
		setHarmonies(sa, {})
		fresh(sa)
		fresh(sb)
		AbilityService.use(bob, "phase")
		AbilityService.use(alice, "frost_wave")
		check(sb.status.phaseUntil > now(), "without the Eye, the phase continues")
		advance(2)
		restoreHarmonies(sa)
		restoreHarmonies(sb)
	end)

	--------------------------------------------------------------------------
	scenario("V2 Abilities: Dash guard allowance + Storm Crystal trail", function()
		give(sa, "dash")
		setHarmonies(sa, {})
		-- The V1 blanket grace is gone: a teleport right after a dash is caught.
		claimRelic(alice, "ember_shard")
		fresh(sa)
		place(alice, stand(0, 0), 1.6)
		AbilityService.use(alice, "dash")
		Engine.moveTo(alice, stand(0, 0) + Vector3.new(400, 0, 0))
		advance(0.6)
		check(#sa.carrying == 0, "teleport hidden behind a dash: relic dropped")
		advance(1)
		-- But a real dash (and a fast step after it) is fine.
		claimRelic(alice, "ember_shard")
		fresh(sa)
		place(alice, stand(0, 0), 1.6)
		AbilityService.use(alice, "dash")
		Engine.moveTo(alice, stand(65, 0))
		advance(0.6)
		check(#sa.carrying == 1, "a dash burst (130 studs/s) is inside the dash allowance: relic kept")
		fresh(sa)
		place(alice, stand(0, 0), 1.6)
		Engine.moveTo(alice, stand(65, 0))
		advance(0.6)
		check(#sa.carrying == 0, "the same burst without a dash is caught (the allowance is what made it legal)")
		-- Storm Crystal: a short static trail that slows once.
		setHarmonies(sa, { "storm_crystal" })
		fresh(sa)
		fresh(sb)
		place(alice, stand(0, -30), 1.6)
		place(bob, stand(30, 30), 0.1)
		local mark = logSize(bob)
		AbilityService.use(alice, "dash")
		Engine.moveTo(alice, stand(14, -30))
		advance(0.35)
		check(Dash.activeTrails() == 1 and #fxLog(bob, "StormTrail", mark) == 1, "trail laid")
		place(bob, stand(7, -29), 0.25)
		check(near(slowOf(sb), H.StormTrail.Slow), "crossing it slows 25%")
		StatusService.applySlow(sb, "storm", 0.01, 0.01)
		place(bob, stand(8, -30), 0.25)
		check(slowOf(sb) <= 0.01 + 1e-6, "once per trail")
		advance(H.StormTrail.Duration)
		check(Dash.activeTrails() == 0, "trail fades")
		-- A forged long dash cannot stretch the trail.
		fresh(sa)
		place(alice, stand(0, -30), 1.6)
		AbilityService.use(alice, "dash")
		Engine.moveTo(alice, stand(70, -30))
		advance(0.35)
		local trail = fxLog(bob, "StormTrail")
		local last = trail[#trail]
		check(last and (last.to - last.from).Magnitude <= H.StormTrail.MaxLength + 0.01, "trail length clamped to 18 studs")
		advance(2)
		restoreHarmonies(sa)
	end)

	--------------------------------------------------------------------------
	scenario("V2 Abilities: forged requests, spam, unequipped abilities, harmonies", function()
		sa.data.abilities.loadout = { "dash", "pulse", "" }
		fresh(sa)
		place(alice, stand(0, 0), 1.6)
		-- Not equipped.
		local mark = logSize(alice)
		for _, id in { "blink", "grapple", "frost_wave", "rune_trap", "shield", "decoy", "phase" } do
			local ok, reason = AbilityService.use(alice, id, Vector3.new(1, 0, 0))
			if ok or reason ~= "notEquipped" then
				check(false, id .. " used while not equipped")
			end
		end
		check(next(sa.cooldowns) == nil and Blink.pendingCount() == 0 and RuneTrap.of(sa) == nil, "nothing happened for unequipped abilities")
		check(#fxLog(alice, "AbilityDenied", mark) >= 1, "client told so it can undo its prediction")
		-- Unknown / forged ability ids and slots.
		for _, bad in { "BLINK", "blink ", "eruption", "seal", 3, true, {}, string.rep("a", 200), nil } do
			Engine.fireServer(remote("UseAbility"), alice, bad, Vector3.new(1, 0, 0))
		end
		advance(0.3)
		check(next(sa.cooldowns) == nil, "forged ids do nothing")
		-- Forged cooldowns / harmonies in the payload.
		setHarmonies(sa, {})
		fresh(sa)
		Engine.fireServer(remote("UseAbility"), alice, "pulse", { cooldown = 0, Cooldown = 0, harmony = "magma_heart", Eruption = true, Radius = 999 })
		advance(0.05)
		check(Pulse.pendingCount() == 0 and near(cooldownLeft(sa, "pulse"), A.Pulse.Cooldown, 0.1), "payload cannot grant Eruption nor change the cooldown")
		local _, reason = AbilityService.use(alice, "pulse")
		check(reason == "cooldown", "cooldown cannot be skipped")
		-- A harmony needs the relic on a pedestal of the caster's own Sanctuary.
		fresh(sa)
		claimRelic(alice, "magma_heart")
		EconomyService.recompute(sa)
		local displayed = {}
		for _, entity in RelicService.placedBy(alice.UserId) do
			if Abilities.harmony(entity.id) and not table.find(displayed, entity.id) then
				table.insert(displayed, entity.id)
			end
		end
		table.sort(displayed)
		check(table.concat(sa.harmonyRelics, ",") == table.concat(displayed, ","), "harmonies = displayed relics only (" .. table.concat(sa.harmonyRelics, ",") .. ")")
		check(#sa.carrying == 1 and (table.find(displayed, "magma_heart") ~= nil) == (table.find(sa.harmonyRelics, "magma_heart") ~= nil), "a carried Magma Heart grants nothing")
		CarryService.dropAll(sa, nil)
		-- Spam every new ability: one activation each.
		local counts = {}
		for _, id in { "blink", "frost_wave", "shield", "decoy", "phase" } do
			give(sa, id)
			fresh(sa)
			setHarmonies(sa, {})
			place(alice, stand(0, 0), 1.6)
			local before = logSize(bob)
			for _ = 1, 200 do
				Engine.fireServer(remote("UseAbility"), alice, id, Vector3.new(1, 0, 0))
			end
			advance(0.6)
			local kind = ({ blink = "BlinkWindup", frost_wave = "FrostWave", shield = "Shield", decoy = "Decoy", phase = "Phase" })[id]
			counts[id] = #fxLog(bob, kind, before)
		end
		check(counts.blink == 1 and counts.frost_wave == 1 and counts.shield == 1 and counts.decoy == 1 and counts.phase == 1, "200 requests each -> exactly one activation each")
		-- Remote functions are rate-limited.
		local rated = 0
		for _ = 1, 30 do
			local _, why = Engine.invokeServer(remote("UnlockAbility"), alice, "phase")
			if why == "rate" then
				rated += 1
			end
		end
		check(rated > 20, "UnlockAbility spam rate-limited")
		rated = 0
		for _ = 1, 30 do
			local _, why = Engine.invokeServer(remote("SetHarmony"), alice, "void_cube", true)
			if why == "rate" then
				rated += 1
			end
		end
		check(rated > 20, "SetHarmony spam rate-limited")
		restoreHarmonies(sa)
		advance(2)
	end)

	--------------------------------------------------------------------------
	scenario("V2 Abilities: death, respawn and disconnect clean everything", function()
		-- Death during a blink wind-up, with a trap and a decoy out.
		give(sa, "blink")
		fresh(sa)
		place(alice, stand(0, 0), 1.6)
		give(sa, "rune_trap")
		AbilityService.use(alice, "rune_trap")
		give(sa, "decoy")
		AbilityService.use(alice, "decoy", Vector3.new(1, 0, 0))
		give(sa, "blink")
		AbilityService.use(alice, "blink", Vector3.new(1, 0, 0))
		check(RuneTrap.of(sa) ~= nil and #Decoy.active() >= 1 and Blink.pendingCount() == 1, "trap + decoy + pending blink")
		local oldCharacter = alice.Character
		humanoid(alice).Health = 0
		advance(0.1)
		check(RuneTrap.of(sa) == nil and Blink.pendingCount() == 0, "death: trap and pending blink removed")
		local decoys = 0
		for _, record in Decoy.active() do
			if record.owner == sa then
				decoys += 1
			end
		end
		check(decoys == 0, "death: decoy removed")
		advance(GameConfig.Player.RespawnDelay + 0.5)
		check(alice.Character ~= oldCharacter and alice.Character ~= nil, "respawned")
		check(alice.Character:GetAttribute("ShieldUntil") == nil and sa.status.phaseUntil == 0, "fresh character, no leftover buff")

		-- Disconnect in the middle of everything.
		local carol = Engine.addPlayer("Carol", 3003)
		check(waitFor(function()
			local s = sessionOf(carol)
			return s ~= nil and s.loaded and carol.Character ~= nil
		end, 6), "Carol joined")
		local sc = sessionOf(carol)
		for _, id in { "rune_trap", "decoy", "shield" } do
			give(sc, id)
		end
		fresh(sc)
		place(carol, stand(-40, 0), 1.6)
		AbilityService.use(carol, "rune_trap")
		AbilityService.use(carol, "decoy", Vector3.new(1, 0, 0))
		AbilityService.use(carol, "shield")
		give(sc, "blink")
		AbilityService.use(carol, "blink", Vector3.new(1, 0, 0))
		local trapPart = RuneTrap.of(sc).part
		Engine.removePlayer(carol)
		advance(1.5)
		local leftovers = 0
		for _, record in Decoy.active() do
			if record.owner == sc then
				leftovers += 1
			end
		end
		check(trapPart.Parent == nil and RuneTrap.of(sc) == nil and leftovers == 0 and Blink.pendingCount() == 0, "disconnect: trap, decoy and pending blink gone")
		local strays = 0
		for _, child in Engine.workspace:FindFirstChild("Abilities"):GetChildren() do
			if child:GetAttribute("OwnerId") == 3003 then
				strays += 1
			end
		end
		check(strays == 0, "no ability object left by a departed player")
		advance(3)
	end)

	--------------------------------------------------------------------------
	-- Two-player chases on the real island.
	--------------------------------------------------------------------------

	-- Relics at stake between alice and bob (displayed, carried, or dropped
	-- after a theft). Rift spawns come and go on their own: not counted.
	local function relicTotal()
		local a, b = alice.UserId, bob.UserId
		local n = 0
		for _, e in RelicService.all() do
			if (e.state == "Placed" and (e.ownerId == a or e.ownerId == b))
				or (e.state == "Carried" and (e.carrierId == a or e.carrierId == b))
				or (e.state == "Dropped" and (e.stolenFrom == a or e.stolenFrom == b))
			then
				n += 1
			end
		end
		return n
	end
	-- Every live relic uid appears once among entities, and in at most one save.
	local function noDuplicates(): (boolean, string)
		local seen = {}
		for _, s in Sessions.all() do
			for _, saved in s.data.relics do
				if seen[saved.uid] then
					return false, "uid " .. saved.uid .. " saved twice"
				end
				seen[saved.uid] = true
			end
		end
		return true, ""
	end
	local RelicsConfig = shared("Config.Relics")
	local function ensurePlaced(player, count)
		local s = sessionOf(player)
		s.data.upgrades.pedestal = math.max(s.data.upgrades.pedestal, 3)
		Sessions.markCold(s)
		PlotService.refreshPedestals(PlotService.get(s.plot))
		local guard = 0
		while #RelicService.placedBy(player.UserId) < count and guard < 6 do
			guard += 1
			local have = {}
			for _, entity in RelicService.placedBy(player.UserId) do
				have[entity.id] = true
			end
			local pick = nil
			for _, def in RelicsConfig.list do
				if not have[def.id] and not Abilities.harmony(def.id) and (def.rarity == "Common" or def.rarity == "Uncommon") then
					pick = def.id
					break
				end
			end
			claimRelic(player, pick)
			insideOwnPlot(player)
		end
		return #RelicService.placedBy(player.UserId) >= count
	end
	-- A relic of alice's that bob does not display (else securing it would
	-- fuse it into bob's copy instead of placing it).
	local function pickTarget()
		local bobHas = {}
		for _, entity in RelicService.placedBy(bob.UserId) do
			bobHas[entity.id] = true
		end
		for _, entity in RelicService.placedBy(alice.UserId) do
			if not bobHas[entity.id] then
				return entity
			end
		end
		return RelicService.placedBy(alice.UserId)[1]
	end
	local function prepareTheft()
		sa.data.playTime = GameConfig.Steal.NoviceSeconds + 100
		sa.lastActivity = now()
		local plot = PlotService.get(sa.plot)
		plot.aegisUntil = 0
		plot.sealedUntil = 0
		sb.cooldowns.steal = 0
		table.clear(sb.stealLog)
		table.clear(sa.robbedLog)
		sb.data.upgrades.pedestal = math.max(sb.data.upgrades.pedestal, 3)
		Sessions.markCold(sb)
		PlotService.refreshPedestals(PlotService.get(sb.plot))
		PlotService.tick()
	end
	local function steal(entity)
		prepareTheft()
		place(bob, entity.anchor.Position + Vector3.new(0, -3, 3), 0.1)
		prompt(entity.anchor, "Steal", bob, "PromptButtonHoldBegan")
		advance(3.5)
		sa.lastActivity = now()
		prompt(entity.anchor, "Steal", bob, "Triggered")
		return entity.state == "Carried" and entity.carrierId == bob.UserId
	end
	-- Moves `player` towards `target` at `speed` studs/s for `seconds`,
	-- tracking the largest jump seen by the movement guard.
	local function run(player, target, speed, seconds)
		local s = sessionOf(player)
		local elapsed = 0
		while elapsed < seconds do
			local p = pos(player)
			local offset = target - p
			local flat = Vector3.new(offset.X, 0, offset.Z)
			if flat.Magnitude < 0.5 then
				break
			end
			local step = math.min(flat.Magnitude, speed * (1 - Status.slowAmount(s.status, now())) * 0.1)
			if now() >= s.stunnedUntil then
				Engine.moveTo(player, p + flat.Unit * step)
			end
			advance(0.1)
			elapsed += 0.1
		end
	end

	scenario("V2 Chase 1: theft -> Blink -> Dash + Pulse -> Shield -> Pulse -> recovery", function()
		check(ensurePlaced(alice, 4), "alice displays 4 relics")
		setHarmonies(sa, {})
		setHarmonies(sb, {})
		give(sb, "blink")
		give(sb, "shield")
		give(sa, "dash")
		give(sa, "pulse")
		fresh(sa)
		fresh(sb)
		local entities, savedA, savedB = relicTotal(), #sa.data.relics, #sb.data.relics
		local target = pickTarget()
		local uid = target.uid
		check(steal(target), "bob steals " .. target.id)
		check(target.stolenFrom == alice.UserId, "tagged as stolen from alice")
		setHarmonies(sa, {})
		-- Bob runs to the gate and blinks out (half range while carrying).
		local plotCf = Layout.plotCFrame(sa.plot)
		local out = plotCf.LookVector
		place(bob, (plotCf * CFrame.new(0, 3, -(Layout.PlatformRadius - 6))).Position, 0.1)
		local before = pos(bob)
		local blinked, why = AbilityService.use(bob, "blink", Vector3.new(out.X, 0, out.Z))
		advance(0.45)
		local jump = (pos(bob) - before).Magnitude
		check(blinked and jump >= A.Blink.MinDistance and jump <= A.Blink.Range * A.Blink.CarryFactor + 0.5, "carrier blink: at most 8 studs (" .. string.format("%.1f", jump) .. ", " .. tostring(why) .. ")")
		check(target.state == "Carried", "relic still carried after the blink")
		local exit = (plotCf * CFrame.new(0, -Layout.PlatformHeight + 3, -(Layout.PlatformRadius + Layout.RampLength + 30))).Position
		run(bob, exit, 18, 1)
		-- Alice dashes in; bob raises his shield; her Pulse is absorbed.
		AbilityService.use(alice, "dash")
		place(alice, pos(bob) + Vector3.new(5, 0, 0), 0.1)
		AbilityService.use(bob, "shield")
		AbilityService.use(alice, "pulse")
		check(target.state == "Carried" and sb.stunnedUntil <= now(), "shield absorbs the Pulse (relic kept)")
		-- The shield slows him: alice keeps up while her Pulse recharges.
		run(bob, exit, 18, A.Shield.Duration + 0.5)
		advance(cooldownLeft(sa, "pulse") + 0.05)
		check(sb.status.shieldUntil <= now() and cooldownLeft(sa, "pulse") == 0, "shield gone, Pulse recharged")
		place(alice, pos(bob) + Vector3.new(5, 0, 0), 0.1)
		local pulsed, pulseWhy = AbilityService.use(alice, "pulse")
		check(target.state == "Dropped" and sb.stunnedUntil > now(), string.format("Pulse knocks the relic loose (used=%s %s, state=%s, steady=%.1f, shield=%.1f, harmonies=%s, carrying=%d)", tostring(pulsed), tostring(pulseWhy), target.state, sb.steadyUntil - now(), sb.status.shieldUntil - now(), table.concat(sa.harmonyRelics, ","), #sb.carrying))
		-- No stun-lock: bob is steady.
		local steady = sb.steadyUntil
		sa.cooldowns.pulse = 0
		AbilityService.use(alice, "pulse")
		check(sb.steadyUntil == steady, "no stun-lock: a second Pulse does nothing")
		-- Alice grabs it: straight back home.
		place(alice, target.anchor.Position + Vector3.new(0, -1, 1), 0.1)
		prompt(target.anchor, "Grab", alice)
		check(target.state == "Placed" and target.ownerId == alice.UserId and target.uid == uid, "recovered: back on alice's pedestal")
		check(relicTotal() == entities and #sa.data.relics == savedA and #sb.data.relics == savedB, "no relic created, lost or duplicated")
		local ok, dup = noDuplicates()
		check(ok, "no uid saved twice " .. dup)
		check(#sb.carrying == 0 and cooldownLeft(sb, "shield") > 0 and cooldownLeft(sb, "steal") > 0, "bob's cooldowns still running (shield, steal)")
		restoreHarmonies(sa)
		restoreHarmonies(sb)
		advance(3)
	end)

	scenario("V2 Chase 2: theft -> Dash -> body-block -> Phase -> Cosmic Eye + Frost Wave -> secured", function()
		check(ensurePlaced(alice, 4), "alice displays 4 relics")
		setHarmonies(sa, { "cosmic_eye" })
		setHarmonies(sb, {})
		give(sb, "dash")
		give(sb, "phase")
		give(sa, "frost_wave")
		fresh(sa)
		fresh(sb)
		local entities = relicTotal()
		local target = pickTarget()
		local uid = target.uid
		local savedA = #sa.data.relics
		check(steal(target), "bob steals " .. target.id)
		setHarmonies(sa, { "cosmic_eye" })
		local plotCf = Layout.plotCFrame(sa.plot)
		local exit = (plotCf * CFrame.new(0, -Layout.PlatformHeight + 3, -(Layout.PlatformRadius + Layout.RampLength + 12))).Position
		AbilityService.use(bob, "dash")
		run(bob, exit, 18, 2)
		-- Alice blocks the way; bob phases through her.
		place(alice, pos(bob) + Vector3.new(0, 0, 0) + (exit - pos(bob)).Unit * 3, 0.1)
		local mark = logSize(alice)
		check(AbilityService.use(bob, "phase") == true, "bob phases")
		check(root(bob).CollisionGroup == "Phase" .. sb.plot and not Engine.groupsCollide(root(bob).CollisionGroup, root(alice).CollisionGroup), "bob and alice no longer collide")
		check(#sb.carrying == 1 and target.state == "Carried", "the relic stays carried and visible")
		advance(0.15)
		check(#fxLog(alice, "Reveal", mark) >= 1, "Cosmic Eye reveals the phase to alice")
		AbilityService.use(alice, "frost_wave")
		check(sb.status.phaseUntil <= now() and slowOf(sb) > 0, "Cosmic Eye + Frost Wave: phase ended, thief slowed")
		check(target.state == "Carried", "a slow never makes him drop")
		-- He still makes it home: the heist is secured once.
		insideOwnPlot(bob)
		advance(0.5)
		check(target.state == "Placed" and target.ownerId == bob.UserId and target.uid == uid, string.format("secured in bob's Sanctuary (state=%s owner=%s carrier=%s bobCarrying=%d bobRelics=%d pedestals=%d)", target.state, tostring(target.ownerId), tostring(target.carrierId), #sb.carrying, #sb.data.relics, PlotService.unlockedCount(PlotService.get(sb.plot))))
		check(#sa.data.relics == savedA - 1, "removed from alice's save exactly once")
		check(relicTotal() == entities, "no relic created or lost")
		local ok, dup = noDuplicates()
		check(ok, "no uid saved twice " .. dup)
		restoreHarmonies(sa)
		restoreHarmonies(sb)
		advance(3)
	end)

	scenario("V2 Chase 3: theft -> Decoy (seen through) -> Grapple -> cut by Pulse -> relic flies home", function()
		check(ensurePlaced(alice, 4), "alice displays 4 relics")
		setHarmonies(sa, { "cosmic_eye" })
		setHarmonies(sb, {})
		give(sb, "grapple")
		give(sb, "decoy")
		give(sa, "pulse")
		fresh(sa)
		fresh(sb)
		local entities, savedA = relicTotal(), #sa.data.relics
		local target = pickTarget()
		check(steal(target), "bob steals " .. target.id)
		setHarmonies(sa, { "cosmic_eye" })
		local index = nil
		for i = 1, #WorldFeatures.GrapplePoints do
			if findSpot(i) then
				index = i
				break
			end
		end
		local spot = findSpot(index)
		local anchor = WorldFeatures.GrapplePoints[index].position
		place(bob, spot, 1.6)
		-- A decoy runs the other way; alice's Cosmic Eye sees through it.
		place(alice, spot + Vector3.new(0, 0, 0) + (spot - anchor).Unit * 12, 0.1)
		local mark = logSize(alice)
		local away = Vector3.new(spot.X - anchor.X, 0, spot.Z - anchor.Z)
		AbilityService.use(bob, "decoy", -away)
		advance(0.2)
		check(#fxLog(alice, "Reveal", mark) >= 1, "the decoy is revealed to alice")
		check(AbilityService.use(bob, "grapple", index) == true, "the thief grapples away")
		local flight = Grapple.flightOf(sb)
		-- Mid-flight, alice Pulses him out of the air.
		local p = pos(bob) + (anchor - pos(bob)).Unit * 6
		Engine.moveTo(bob, p)
		place(alice, p + Vector3.new(4, 0, 0), 0.1)
		AbilityService.use(alice, "pulse")
		check(flight ~= nil and Grapple.flightOf(sb) == nil, "Pulse cuts the grapple")
		check(target.state == "Dropped", "the relic falls")
		check(cooldownLeft(sb, "grapple") > 0 and cooldownLeft(sb, "decoy") > 0, "bob's cooldowns kept (no reset by the cut)")
		-- Nobody picks it up: it flies home on its own.
		advance(GameConfig.Carry.StolenDropReturn + 1.5)
		check(target.state == "Placed" and target.ownerId == alice.UserId, "the relic returned to alice's pedestal")
		check(relicTotal() == entities and #sa.data.relics == savedA, "nothing lost or duplicated")
		local ok, dup = noDuplicates()
		check(ok, "no uid saved twice " .. dup)
		restoreHarmonies(sa)
		restoreHarmonies(sb)
		advance(2)
	end)

	--------------------------------------------------------------------------
	scenario("V2 Abilities: client HUD and controls", function()
		local Store = creq("Controllers.Store")
		local ClientAbilities = creq("Controllers.Abilities")
		sa.data.abilities.unlocked.blink = true
		insideOwnPlot(alice)
		AbilityService.setLoadout(alice, 1, "blink")
		AbilityService.setLoadout(alice, 3, "shield")
		advance(0.5)
		local hud = alice:FindFirstChild("PlayerGui"):FindFirstChild("RiftHUD")
		local buttons = {}
		for _, d in hud:GetDescendants() do
			if d.Parent and d.Parent.Name == "Abilities" then
				buttons[d.Name] = true
			end
		end
		check(buttons.blink and buttons.pulse and buttons.shield and buttons.seal and buttons.LoadoutButton, "HUD buttons follow the loadout + loadout button")
		-- The real client path: Q-slot blink from the client.
		fresh(sa)
		place(alice, stand(0, 0), 1.6)
		local from = pos(alice)
		check(ClientAbilities.useSlot(1) == true, "client sends the slot's ability")
		advance(0.5)
		check(near((pos(alice) - from).Magnitude, A.Blink.Range, 0.2), "server blinked the client 16 studs")
		check(ClientAbilities.remaining("blink") > 0, "client shows the cooldown")
		-- Status chips while shielded.
		AbilityService.use(alice, "shield")
		advance(0.3)
		local chip = nil
		for _, d in hud:GetDescendants() do
			if d.Name == "Status_shield" then
				chip = d
			end
		end
		check(chip ~= nil and chip.Visible, "SHIELD status chip shown")
		check(Store.state.status.shieldUntil > now(), "client knows the shield state")
		advance(2.5)
		check(chip and not chip.Visible, "chip hidden when it ends")
		-- A refused request undoes the client's cooldown prediction.
		advance(A.Blink.Cooldown)
		fresh(sa)
		place(alice, stand(0, 0), 1.6)
		local wall = part("DenyWall", Vector3.new(40, 14, 1), CFrame.new(ARENA + Vector3.new(0, 7, -2.5)))
		check(ClientAbilities.useSlot(1) == true, "client predicts and sends")
		check(ClientAbilities.remaining("blink") > 0, "predicted cooldown shown at once")
		advance(0.3)
		check(ClientAbilities.remaining("blink") == 0 and cooldownLeft(sa, "blink") == 0, "server said blocked: prediction undone, nothing spent")
		wall:Destroy()
		insideOwnPlot(alice)
		AbilityService.setLoadout(alice, 1, "dash")
		AbilityService.setLoadout(alice, 3, "")
	end)

	--------------------------------------------------------------------------
	scenario("V2 Abilities: cleanup and restore", function()
		arena:Destroy()
		advance(1)
		sa.data.abilities.loadout = table.clone(savedLoadoutA)
		sb.data.abilities.loadout = table.clone(savedLoadoutB)
		Sessions.markCold(sa)
		Sessions.markCold(sb)
		restoreHarmonies(sa)
		restoreHarmonies(sb)
		fresh(sa)
		fresh(sb)
		insideOwnPlot(alice)
		insideOwnPlot(bob)
		advance(1)
		check(RuneTrap.count() == 0 and #Decoy.active() == 0 and Blink.pendingCount() == 0 and Pulse.pendingCount() == 0, "no ability state left anywhere")
		check(#Engine.workspace:FindFirstChild("Abilities"):GetChildren() == 0, "no ability object left in the world")
		check(Snapshot.unmarkedColdChanges == unmarkedBefore, "every cold change of phase 4 was marked (" .. Snapshot.unmarkedColdChanges - unmarkedBefore .. " unmarked)")
	end)
end
