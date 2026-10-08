--!nocheck
-- V2 phase 7A ("Forgeheart + boss sound identity") scenarios. Called by
-- tests/run.luau with its helpers, after V2Combat, on the same live server.
--
--   * catalogue: harder than the Void Warden but fair (telegraphs, reachable
--     safe rocks), exact loot, materials, relic, cosmetic, strings, weapons
--     untouched;
--   * every attack planned inside the arena, never hurting before its
--     telegraph, lava shapes that last exactly as long as drawn;
--   * rotation (alternating bosses, next-boss preview, Studio override),
--     the volcanic arena (pads, walls, anchors, budget);
--   * lava and the Final Eruption hurt only where drawn, the safe rocks
--     protect, shield / phase / jump work against lava;
--   * every weapon and the boss-adapted abilities, phases + music state,
--     solo victory with every reward once, saved, never twice;
--   * client: Forgeheart's body, telegraph colours, special banner + red
--     edge, safe-rock arrow, HUD bar, card (loot, theme, next boss), Codex;
--   * audio: candidate ids used only once verified, music per boss, phase
--     intensity without speed change, ducking under critical warnings,
--     priorities / anti-spam, distinct sounds per boss.

local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Enum = roblox.Enum

return function(ctx)
	local scenario, check, advance, waitFor = ctx.scenario, ctx.check, ctx.advance, ctx.waitFor
	local sreq, shared, remote, Engine, Loader, game = ctx.sreq, ctx.shared, ctx.remote, ctx.Engine, ctx.Loader, ctx.game
	local sessionOf, teleport = ctx.sessionOf, ctx.teleport
	local hasNotification, clearLog = ctx.hasNotification, ctx.clearLog
	local alice = ctx.alice()
	local bob = game:GetService("Players"):FindFirstChild("Bob") or ctx.bob()

	local Sessions = sreq("Core.Sessions")
	local DataSchema = sreq("Core.DataSchema")
	local BossService = sreq("Services.BossService")
	local WeaponService = sreq("Services.WeaponService")
	local AbilityService = sreq("Services.AbilityService")
	local StatusService = sreq("Services.StatusService")
	local TrophyService = sreq("Services.TrophyService")
	local Forgeheart = sreq("Bosses.Forgeheart")
	local ArenaBuilder = sreq("World.ArenaBuilder")
	local Bosses = shared("Config.Bosses")
	local Weapons = shared("Config.Weapons")
	local Materials = shared("Config.Materials")
	local Relics = shared("Config.Relics")
	local Cosmetics = shared("Config.Cosmetics")
	local Abilities = shared("Config.Abilities")
	local Music = shared("Config.Music")
	local Sounds = shared("Config.Sounds")
	local GameConfig = shared("Config.GameConfig")
	local WorldFeatures = shared("WorldFeatures")
	local Strings = shared("Locale.Strings")
	local STORE = GameConfig.Data.StoreName .. "/u_"

	local Client = game:GetService("StarterPlayer").StarterPlayerScripts.Client
	local function creq(path)
		local node = Client
		for part in string.gmatch(path, "[^%.]+") do
			node = node:FindFirstChild(part)
		end
		return Loader.require("client", node)
	end

	local DEF = Bosses.get("Forgeheart")
	local VW = Bosses.get("VoidWarden")
	local ARENA = Bosses.Arena
	local FLOOR = ARENA.Center.Y
	local LEAD = Bosses.Combat.DangerLead
	local WALK = 16

	local function now()
		return Engine.workspace:GetServerTimeNow()
	end
	local function root(player)
		return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
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
		BossService.setNextBoss(nil)
		BossService.setNextOpen(now() + 100000)
		advance(0.2)
	end
	local function nearBoss(player, distance, side)
		local f = fight()
		local a = f.anchor.Position
		Engine.moveTo(player, Vector3.new(a.X + (side or 0) * 4, FLOOR + 3, a.Z - (DEF.radius + (distance or 2))))
		sessionOf(player).lastPosition = nil
	end
	local function openForge(players)
		reset()
		local f = BossService.open("Forgeheart")
		for i, player in players do
			sessionOf(player).data.power.peak = math.max(sessionOf(player).data.power.peak, 1000)
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
	local function planView(phase, participants, targets, seed)
		return {
			boss = DEF,
			phase = phase,
			participants = participants,
			center = ARENA.Center,
			floorY = FLOOR,
			radius = ARENA.Radius,
			bossPosition = Vector3.new(ARENA.Center.X, FLOOR + DEF.height, ARENA.Center.Z + 18),
			targets = targets,
			rng = Engine.Random.new(seed or 7),
		}
	end

	--------------------------------------------------------------------------
	scenario("V2 Forgeheart: catalogue, harder but fair, exact loot, weapons untouched", function()
		reset()
		check(DEF ~= nil and DEF.rank == 2 and DEF.theme == "volcano" and VW.theme == "closet", "Forgeheart is rank II with his own volcanic arena")
		check(DEF.difficulty > VW.difficulty and DEF.baseHealth > VW.baseHealth and DEF.minPowerRecord > VW.minPowerRecord and DEF.recommendedPower > VW.recommendedPower, "harder than the Void Warden (difficulty, Health, gate, recommendation)")
		local ids = {}
		for id, attack in DEF.attacks do
			ids[id] = true
			local minimum = if attack.big then Bosses.Combat.BigTelegraph else Bosses.Combat.MinTelegraph
			check(attack.telegraph >= math.max(minimum, 1.2), id .. ": announced " .. attack.telegraph .. " s ahead (>= 1.2 s, more than the minimum)")
			check(attack.telegraph - LEAD >= 0.85, id .. ": at least 0.85 s of yellow before the red")
		end
		check(ids.volcanic_hammer and ids.lava_blobs and ids.burning_floor and ids.meteor_shower and ids.final_eruption, "five original attacks: hammer, lava blobs, burning floor, meteors, final eruption")
		check(#DEF.phases == 3 and DEF.phases[1].special == nil and DEF.phases[2].special == "final_eruption" and DEF.phases[3].special == "final_eruption", "the eruption only in the advanced phases")
		for i = 1, 3 do
			check(DEF.phases[i].gap < VW.phases[i].gap, "phase " .. i .. ": shorter breaks than the Void Warden (" .. DEF.phases[i].gap .. " s)")
		end
		-- Safe rocks: every point of the arena reaches a safe rock in time.
		local pads = Bosses.arenaPads(DEF)
		check(#pads == 6, "six cooled-rock pads")
		local window = DEF.attacks.final_eruption.telegraph - LEAD
		local worst = 0
		for parity = 0, 1 do
			for ring = 0, 5 do
				local r = ARENA.Radius * ring / 5
				for k = 0, 47 do
					local a = k / 48 * math.pi * 2
					local p = Vector3.new(ARENA.Center.X + math.cos(a) * r, FLOOR, ARENA.Center.Z + math.sin(a) * r)
					local best = math.huge
					for index, pad in pads do
						if (index - 1) % 2 == parity then
							best = math.min(best, math.max(0, (p - pad).Magnitude - DEF.padRadius))
						end
					end
					worst = math.max(worst, best)
				end
			end
		end
		check(worst / WALK <= window, string.format("any spot reaches a safe rock walking (%.1f studs = %.2f s <= %.2f s before the red)", worst, worst / WALK, window))
		-- Loot (exact, individual).
		local byId = {}
		for _, entry in DEF.loot do
			byId[entry.id] = entry
		end
		check(byId.essence and byId.essence.chance == 1 and byId.essence.minutes == 7, "Essence: 100 %, 7 min of production")
		check(byId.magma_shard and byId.magma_shard.chance == 1 and byId.magma_shard.min == 3 and byId.magma_shard.max == 6, "volcanic material: Magma Shards 100 %, 3-6")
		check(byId.ember_core and byId.ember_core.chance == 0.15 and byId.ember_core.rare, "rare Forge material: Ember Core 15 %")
		check(byId.ember_anvil and byId.ember_anvil.chance == 0.08 and Relics.get("ember_anvil").bossOnly == "Forgeheart" and Relics.get("ember_anvil").spawnWeight == 0, "exclusive relic Ember Anvil 8 %, never in the Rift")
		check(byId.trail_magma and byId.trail_magma.chance == 0.05 and Cosmetics.get("trail_magma").unlock.kind == "boss" and Cosmetics.get("trail_magma").unlock.boss == "Forgeheart", "exclusive cosmetic Magma Drip 5 %")
		check(Materials.get("magma_shard").source == "Forgeheart" and Materials.get("ember_core").source == "Forgeheart", "materials sourced from Forgeheart (Codex)")
		check(Bosses.maxHealth(DEF, 1) == 2200 and Bosses.maxHealth(DEF, 2) == 3850, "Health scales with participants (+75 % each)")
		-- Strings in both languages.
		local missing = {}
		local keys = { "boss.Forgeheart.name", "boss.Forgeheart.title", "boss.Forgeheart.lore", "boss.Forgeheart.phase.1", "boss.Forgeheart.phase.2", "boss.Forgeheart.phase.3", "boss.Forgeheart.victorySub", "boss.Forgeheart.dizzy", "boss.Forgeheart.safeGo", "boss.special", "boss.next", "boss.music", "mat.magma_shard", "mat.ember_core", "relic.ember_anvil.name", "relic.ember_anvil.lore", "cos.trail_magma" }
		for id in DEF.attacks do
			table.insert(keys, "boss.attack." .. id)
		end
		for _, key in keys do
			if not Strings.en[key] or not Strings.fr[key] then
				table.insert(missing, key)
			end
		end
		check(#missing == 0, "every Forgeheart text in English and French (" .. table.concat(missing, ", ") .. ")")
		-- The six weapons keep their prices (no arbitrary change).
		local prices = { foam_gloves = 0, squeaky_mallet = 25000, bubble_blaster = 120000, star_wand = 400000, giant_plunger = 1500000, rainbow_hammer = 6000000 }
		local same = #Weapons.list == 6
		for _, def in Weapons.list do
			same = same and prices[def.id] == def.price.essence
		end
		check(same, "the six weapons keep their prices")
		check(Weapons.totalWins({ VoidWarden = { wins = 2 }, Forgeheart = { wins = 3 } }) == 5, "Forgeheart victories count for weapon unlocks too")
		-- No asset id in the boss code (sounds live in Config/Sounds).
		for _, path in { "src/server/Bosses/Forgeheart.luau", "src/client/Boss/ForgeheartModel.luau", "src/client/Boss/ForgeheartFX.luau", "src/server/World/ArenaBuilder.luau" } do
			check(string.find(fs.readFile(path), "rbxassetid", 1, true) == nil, path .. ": no asset id")
		end
	end)

	--------------------------------------------------------------------------
	scenario("V2 Forgeheart: every attack planned inside, never before its telegraph", function()
		for _, phase in { 1, 2, 3 } do
			for id, attack in DEF.attacks do
				local plan = Forgeheart.plan(planView(phase, 2, { arenaPoint(12, 0, -3), arenaPoint(-14, 8, -3) }, phase * 10), id, 100)
				local earliest, inside, lasting = math.huge, true, true
				for _, shape in plan.shapes do
					earliest = math.min(earliest, shape.at)
					local flat = (Vector3.new(shape.center.X, 0, shape.center.Z) - Vector3.new(ARENA.Center.X, 0, ARENA.Center.Z)).Magnitude
					inside = inside and flat <= ARENA.Radius + 1
					if shape.kind == "burn" then
						lasting = lasting and shape.untilTime and shape.untilTime > shape.at
					end
				end
				check(inside and lasting, string.format("phase %d %s: shapes inside the arena, lava with an end", phase, id))
				check(plan.hitAt - plan.telegraphAt >= attack.telegraph - 1e-9 and earliest >= plan.hitAt - 1e-9, string.format("phase %d %s: no damage before %.1f s of warning", phase, id, attack.telegraph))
				check(plan.payload ~= nil and plan.action ~= nil, string.format("phase %d %s: clients get what they need to draw it", phase, id))
				if plan.motion then
					check(plan.motion.endAt <= plan.hitAt, string.format("phase %d %s: he lands before anything hurts", phase, id))
				end
			end
		end
		-- Hammer: in front of a close fighter, all around him otherwise.
		local close = Forgeheart.plan(planView(1, 1, { arenaPoint(0, 4, -3) }), "volcanic_hammer", 0)
		local far = Forgeheart.plan(planView(1, 1, { arenaPoint(0, -50, -3) }), "volcanic_hammer", 0)
		check(close.shapes[1].radius == DEF.attacks.volcanic_hammer.tuning.radius and far.shapes[1].radius == DEF.attacks.volcanic_hammer.tuning.poundRadius, "hammer: aimed slam near a fighter, ground pound when nobody is close")
		local p3 = Forgeheart.plan(planView(3, 1, { arenaPoint(0, 4, -3) }), "volcanic_hammer", 0)
		check(#p3.shapes == 2 and p3.shapes[2].kind == "ring" and p3.payload.wave ~= nil, "phase 3 hammer: a shockwave ring to jump over")
		-- Eruption: every other pad, both parities in phase 3.
		local e2 = Forgeheart.plan(planView(2, 2, {}), "final_eruption", 0)
		local e3 = Forgeheart.plan(planView(3, 2, {}), "final_eruption", 0)
		check(#e2.shapes == 1 and #e2.shapes[1].safeSpots == 3 and e2.dizzyFor == DEF.attacks.final_eruption.tuning.dizzy, "eruption: 3 safe rocks, then out of breath")
		local a, b = e3.payload.waves[1].safe, e3.payload.waves[2].safe
		check(#e3.shapes == 2 and a[1] % 2 ~= b[1] % 2 and e3.shapes[2].at > e3.shapes[1].at, "phase 3: a second eruption on the other rocks")
		-- Crowds get more hazards.
		local solo = Forgeheart.plan(planView(1, 1, { arenaPoint(5, 5) }), "meteor_shower", 0)
		local group = Forgeheart.plan(planView(1, 4, { arenaPoint(5, 5) }), "meteor_shower", 0)
		check(#group.shapes > #solo.shapes, "more meteors for bigger groups (" .. #solo.shapes .. " -> " .. #group.shapes .. ")")
	end)

	--------------------------------------------------------------------------
	scenario("V2 Forgeheart: rotation, next-boss preview, Studio override, volcanic arena", function()
		reset()
		check(Bosses.forOpening(1).id == "VoidWarden" and Bosses.forOpening(2).id == "Forgeheart" and Bosses.forOpening(3).id == "VoidWarden", "rotation alternates the bosses")
		local plateau = Engine.workspace.World.Landmarks.BossPlateau
		local first, second = plateau:GetAttribute("PortalBoss"), plateau:GetAttribute("PortalNextBoss")
		check(Bosses.get(first) and Bosses.get(second) and first ~= second, "portal publishes the next boss and the one after (" .. tostring(first) .. " then " .. tostring(second) .. ")")
		check(BossService.setNextBoss("Nope") == false, "unknown boss refused by the override")
		BossService.setNextBoss("Forgeheart")
		check(plateau:GetAttribute("PortalBoss") == "Forgeheart", "Studio override: Forgeheart is next")
		local f = BossService.open()
		check(f and f.boss.id == "Forgeheart", "the portal opens on Forgeheart")
		local arena = Engine.workspace:FindFirstChild("BossArena")
		check(arena and arena:GetAttribute("Theme") == "volcano" and arena:GetAttribute("BossId") == "Forgeheart", "volcanic arena built")
		local parts, lights, emitters, pads, walls, anchors, floor = 0, 0, 0, 0, 0, 0, false
		for _, d in arena:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
				if d.Name == "SafePad" and d:GetAttribute("PadIndex") then
					pads += 1
				elseif d.Name == "Wall" and d.Transparency == 1 and d.CanCollide then
					walls += 1
				elseif d.Name == "Anchor" and d:GetAttribute("GrapplePoint") then
					anchors += 1
				end
				if d:GetAttribute("ArenaFloor") then
					floor = true
				end
			elseif d:IsA("PointLight") then
				lights += 1
			elseif d:IsA("ParticleEmitter") then
				emitters += 1
			end
		end
		check(parts <= ARENA.PartBudget and lights <= 2 and emitters <= 1, string.format("within budget (%d parts, %d lights, %d emitter)", parts, lights, emitters))
		check(pads == 6 and walls == 16 and anchors == 4 and floor, "6 safe pads, 16 invisible walls (anti-escape), 4 grapple rocks, the floor")
		local hurting = 0
		for _, d in arena:GetDescendants() do
			if d:IsA("BasePart") and d.CanTouch then
				hurting += 1
			end
		end
		check(hurting == 0, "no touch-damage part in the decor (no invisible damage)")
		-- Entry gate.
		local sb = sessionOf(bob)
		local peak = sb.data.power.peak
		sb.data.power.peak = DEF.minPowerRecord - 1
		atPortal(bob, 2)
		local ok, reason = BossService.join(bob)
		check(not ok and reason == "power", "Power record below " .. DEF.minPowerRecord .. ": refused")
		sb.data.power.peak = peak
		reset()
		check(Engine.workspace:FindFirstChild("BossArena") == nil, "arena destroyed afterwards")
	end)

	--------------------------------------------------------------------------
	scenario("V2 Forgeheart: lava hurts only where drawn, safe rocks protect", function()
		local sa, sb = sessionOf(alice), sessionOf(bob)
		local f = openForge({ alice, bob })
		startNow()
		check(alice:GetAttribute("MusicBoss") == "Forgeheart" and alice:GetAttribute("MusicBossPhase") == 1, "Forgeheart music state set at the start of the fight")
		local pa, pb = BossService.participant(alice), BossService.participant(bob)
		-- Burning floor under Bob, Alice 20 studs away.
		Engine.moveTo(alice, arenaPoint(20, -20))
		Engine.moveTo(bob, arenaPoint(-20, -20))
		sa.lastPosition, sb.lastPosition = nil, nil
		local spot = Vector3.new(root(bob).Position.X, FLOOR, root(bob).Position.Z)
		table.insert(f.shapes, { kind = "burn", at = now() + 0.2, untilTime = now() + 3, center = spot, radius = 8, resolved = {} })
		advance(0.1)
		check(pb.hearts == Bosses.Combat.Hearts, "nothing before the lava starts")
		advance(0.3)
		check(pb.hearts == Bosses.Combat.Hearts - 1 and pa.hearts == Bosses.Combat.Hearts, "only the fighter standing in the lava burns")
		advance(Bosses.Combat.HitInvulnerability + 0.2)
		check(pb.hearts == Bosses.Combat.Hearts - 2, "staying in it keeps hurting (one heart per invulnerability window)")
		Engine.moveTo(bob, spot + Vector3.new(0, 13, 0))
		sb.lastPosition = nil
		advance(Bosses.Combat.HitInvulnerability + 0.2)
		check(pb.hearts == Bosses.Combat.Hearts - 2, "jumping over the lava is safe")
		Engine.moveTo(bob, spot + Vector3.new(0, 3, 0))
		sb.lastPosition = nil
		advance(2)
		check(pb.hearts == Bosses.Combat.Hearts - 2, "once cooled, the floor is harmless")
		pb.hearts = Bosses.Combat.Hearts
		bob:SetAttribute("BossHearts", pb.hearts)
		advance(1)
		-- Shield blocks a lava hit.
		local give = function(s, id)
			local def = Abilities.get(id)
			s.data.abilities.unlocked[id] = true
			s.data.abilities.loadout[Abilities.slotIndex(def.slot)] = id
			Sessions.setCooldown(s, id, 0)
		end
		give(sb, "shield")
		AbilityService.use(bob, "shield", nil)
		clearLog(bob)
		table.insert(f.shapes, { kind = "burn", at = now() + 0.05, untilTime = now() + 0.5, center = spot, radius = 8, resolved = {} })
		advance(0.2)
		check(pb.hearts == Bosses.Combat.Hearts and #fxList(bob, "BossBlock") == 1, "the shield blocks the lava (BLOCKED!)")
		advance(2)
		-- Final Eruption: Alice on a safe rock, Bob not.
		local pads = Bosses.arenaPads(DEF)
		Engine.moveTo(alice, pads[1] + Vector3.new(2, 3, 0))
		Engine.moveTo(bob, pads[2] + Vector3.new(0, 3, 0))
		sa.lastPosition, sb.lastPosition = nil, nil
		pa.dodgeFxAt, pb.hearts = 0, Bosses.Combat.Hearts
		clearLog(alice)
		local center = Vector3.new(ARENA.Center.X, FLOOR, ARENA.Center.Z)
		table.insert(f.shapes, { kind = "outside", at = now() + 0.1, center = center, radius = ARENA.Radius + 10, safeSpots = { pads[1], pads[3], pads[5] }, safeRadius = DEF.padRadius, resolved = {} })
		advance(0.3)
		local dodge = lastFx(alice, "BossDodge")
		check(pa.hearts == Bosses.Combat.Hearts and dodge and dodge.kind == "safe", "on a green rock: safe (\"À L'ABRI !\")")
		check(pb.hearts == Bosses.Combat.Hearts - 1, "off the green rocks: the eruption hits")
		reset()
	end)

	--------------------------------------------------------------------------
	scenario("V2 Forgeheart: every weapon, boss-adapted abilities, phases, solo victory, rewards once", function()
		local sa = sessionOf(alice)
		local savedWeapons = deepCopy(sa.data.weapons)
		local savedLoadout = table.clone(sa.data.abilities.loadout)
		local f = openForge({ alice })
		startNow()
		check(f.maxHp == Bosses.maxHealth(DEF, 1), "solo Health " .. f.maxHp)
		-- Every weapon hits him with the server formula.
		local allGood = true
		for _, def in Weapons.list do
			sa.data.weapons.owned[def.id] = true
			sa.data.weapons.equipped = def.id
			local p = BossService.participant(alice)
			p.combo, p.lastHitAt = 0, 0
			advance(1.3)
			local hp = f.hp
			nearBoss(alice, math.min(3, def.reach - 1))
			local ok = BossService.strike(alice)
			allGood = allGood and ok and math.abs((hp - f.hp) - Bosses.hitDamage(def.damage, sa.power, def.combo[1])) < 1e-6
		end
		check(allGood, "the six weapons hit Forgeheart (weapon x combo x Power bonus)")
		local held = alice.Character:FindFirstChild("BossWeapon")
		check(held ~= nil, "weapon held in the volcanic arena")
		-- Pulse: no push, BOING damage.
		local harmonyBackup = sa.harmonyRelics
		sa.harmonyRelics = {}
		local def = Abilities.get("pulse")
		sa.data.abilities.unlocked.pulse = true
		sa.data.abilities.loadout[Abilities.slotIndex(def.slot)] = "pulse"
		Sessions.setCooldown(sa, "pulse", 0)
		local before, hp = f.anchor.Position, f.hp
		nearBoss(alice, 3)
		AbilityService.use(alice, "pulse", nil)
		advance(0.1)
		check(math.abs((hp - f.hp) - Bosses.Abilities.pulse.damage) < 1e-6 and (f.anchor.Position - before).Magnitude < 1e-3, "Pulse: damage, never a push (he resists)")
		sa.harmonyRelics = harmonyBackup
		-- Phase 2 opens with the Final Eruption.
		clearLog(alice)
		BossService.devSetHealth(0.55)
		advance(0.1)
		check(f.phase == 2 and alice:GetAttribute("MusicBossPhase") == 2, "phase 2 + music phase")
		f.nextAttackAt = 0
		advance(Bosses.Combat.PhaseShow + 0.3)
		check(f.plan and f.plan.id == "final_eruption" and f.motion ~= nil, "phase 2 opens with the Final Eruption (he jumps to the centre)")
		local payload = lastFx(alice, "BossAttack")
		check(payload and payload.attack == "final_eruption" and #payload.data.waves == 1 and payload.motion ~= nil, "eruption sent with its safe rocks and his arc")
		calm()
		BossService.devSetHealth(0.25)
		advance(0.1)
		check(f.phase == 3 and f.anchor:GetAttribute("Mood") == "furious", "phase 3: meltdown")
		advance(Bosses.Combat.PhaseShow + 0.1)
		calm()
		-- Victory with every drop forced (relic on a free pedestal).
		local record = deepCopy(sa.data.bosses.Forgeheart or DataSchema.newBossRecord())
		local magma = sa.data.materials.magma_shard or 0
		sa.data.cosmetics.owned.trail_magma = nil
		local existing = TrophyService.find(sa, "ember_anvil")
		local p = BossService.participant(alice)
		p.damage = math.max(p.damage, Bosses.eligibleDamage(f.maxHp, 1) + 1)
		forceDrops(0)
		BossService.devSetHealth(0.001)
		clearLog(alice)
		advance(0.1)
		nearBoss(alice, 3)
		local ok = BossService.strike(alice)
		advance(0.2)
		check(ok and f.state == "Victory", "Forgeheart defeated")
		local ended = lastFx(alice, "BossEnd")
		check(ended and ended.boss == "Forgeheart" and ended.outcome == "rewarded" and #ended.rewards == #DEF.loot, "every reward line (" .. (ended and #ended.rewards or 0) .. ")")
		check((sa.data.materials.magma_shard or 0) >= magma + DEF.loot[2].max and (sa.data.materials.ember_core or 0) >= 1, "volcanic materials stored")
		check(sa.data.cosmetics.owned.trail_magma == true, "Magma Drip unlocked")
		local trophy = TrophyService.find(sa, "ember_anvil")
		check(trophy ~= nil and (existing == nil or trophy.level >= existing.level), "Ember Anvil on a trophy pedestal (never stealable)")
		local codex = sa.data.bosses.Forgeheart
		check(codex and codex.wins == record.wins + 1 and codex.discovered and codex.rare.ember_anvil ~= nil, "Codex: Forgeheart discovered, +1 victory, rare find")
		check(alice:GetAttribute("MusicBoss") == nil, "boss music released at the victory")
		local again, why = BossService.debugReward(alice)
		check(again == nil and why == "already", "never paid twice")
		advance(1)
		local saved = Engine.dataStoreData[STORE .. alice.UserId]
		check(saved and saved.bosses.Forgeheart and saved.bosses.Forgeheart.wins == codex.wins and saved.materials.magma_shard == sa.data.materials.magma_shard, "rewards saved right away")
		-- Saves keep Forgeheart's data and sanitise it.
		local clean = DataSchema.normalize(DataSchema.serialize(sa.data))
		check(clean.bosses.Forgeheart.wins == codex.wins and clean.materials.ember_core == sa.data.materials.ember_core, "round trip keeps the Forgeheart Codex and materials")
		local tampered = DataSchema.serialize(sa.data)
		tampered.bosses.Forgeheart.wins = 9999
		tampered.materials.magma_shard = -5
		table.insert(tampered.relics, { uid = "fake1", id = "ember_anvil", level = 1, slot = 3 })
		local fixed = DataSchema.normalize(tampered)
		local onPedestal = false
		for _, relic in fixed.relics do
			onPedestal = onPedestal or relic.id == "ember_anvil"
		end
		check(fixed.bosses.Forgeheart.wins <= fixed.bosses.Forgeheart.attempts and (fixed.materials.magma_shard == nil or fixed.materials.magma_shard >= 0) and not onPedestal, "forged Codex / materials / relic on a normal pedestal are sanitised")
		advance(Bosses.Combat.Outro + 0.5)
		sa.data.weapons = savedWeapons
		sa.data.abilities.loadout = savedLoadout
		Sessions.markCold(sa)
		reset()
	end)

	--------------------------------------------------------------------------
	scenario("V2 Forgeheart: client body, telegraphs, special banner, safe arrow, HUD, card, Codex", function()
		local BossFX = creq("Controllers.BossFX")
		local BossHud = creq("UI.Screens.BossHud")
		local Audio = creq("Controllers.Audio")
		local Settings = creq("Controllers.Settings")
		local ForgeheartModel = creq("Boss.ForgeheartModel")
		local BossRig = creq("Boss.BossRig")
		-- The model on its own: native parts, deflates when defeated.
		local holder = Engine.Instance.new("Folder")
		holder.Parent = Engine.workspace
		local rig = ForgeheartModel.build(1, holder)
		local count, neon, assets = 0, 0, 0
		for _, entry in rig.parts do
			count += 1
			if entry.part.Material == Enum.Material.Neon then
				neon += 1
			end
		end
		check(count >= 30 and neon >= 6 and rig.byName.Heart and rig.byName.FistL and rig.byName.EyeWhiteR and rig.byName.MouthGlow, string.format("Forgeheart body: %d native parts, %d glowing lava parts, heart, fists, eyes, mouth", count, neon))
		local pose = BossRig.defaultPose("grumpy")
		ForgeheartModel.pose(rig, CFrame.new(0, 0, 0), pose, 0.1)
		local wide = rig.byName.Body.part.Size.X
		pose.deflate = 1
		ForgeheartModel.pose(rig, CFrame.new(0, 0, 0), pose, 0.1)
		check(rig.byName.Body.part.Size.X < wide * 0.6, "defeat: he deflates like a sad balloon")
		pose.deflate, pose.broom = 0, 1
		ForgeheartModel.pose(rig, CFrame.new(0, 0, 0), pose, 0.1)
		check(rig.byName.FistR.part.Position.Y > rig.byName.Head.part.Position.Y - 2, "slam wind-up: fists raised to the head")
		ForgeheartModel.destroy(rig)
		holder:Destroy()
		local _ = assets
		-- Live fight, Low quality.
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
		local f = openForge({ alice })
		startNow()
		advance(0.3)
		local bossId = BossFX.debugBoss()
		check(bossId == "Forgeheart" and BossFX.debugState().rig, "client builds Forgeheart's body (not the Void Warden's)")
		check(table.find(played, "FHAppear") ~= nil, "his entrance has its own sound")
		local function colors()
			local yellow, red, lava, total = 0, 0, 0, 0
			for _, d in Engine.workspace.ClientBoss:GetDescendants() do
				if d:IsA("BasePart") and d.Name == "Disc" then
					total += 1
					local c = d.Color
					if d.Transparency < 0.95 then
						if c.R > 0.9 and c.G > 0.75 and c.B < 0.4 then
							yellow += 1
						elseif c.R > 0.9 and c.G < 0.6 then
							red += 1
						end
					end
				end
			end
			return yellow, red, total
		end
		local warnings = {}
		for _, attackId in { "volcanic_hammer", "lava_blobs", "burning_floor", "meteor_shower" } do
			calm()
			table.clear(played)
			clearLog(alice)
			Engine.moveTo(alice, arenaPoint(10, -12))
			sessionOf(alice).lastPosition = nil
			f.nextAttackAt = math.huge
			f.lastAttack = nil
			-- Plan this exact attack through the module and run it like the service does.
			local view = planView(1, 1, { Vector3.new(root(alice).Position.X, FLOOR, root(alice).Position.Z) })
			view.bossPosition = f.anchor.Position
			local plan = Forgeheart.plan(view, attackId, now())
			BossFX.attack({ attack = plan.id, action = plan.action, telegraphAt = plan.telegraphAt, hitAt = plan.hitAt, data = plan.payload, motion = plan.motion })
			advance(0.15)
			local y1, r1, total = colors()
			check(total > 0 and y1 > 0 and r1 == 0, attackId .. ": drawn YELLOW while he prepares, on Low quality (" .. y1 .. " parts)")
			local warn = BossFX.WarnSounds[attackId]
			check(warn and table.find(played, warn) ~= nil, attackId .. ": warning sound " .. tostring(warn))
			warnings[warn or "?"] = true
			local shown, icon = BossFX.bubbleState()
			check(shown and icon ~= "", attackId .. ": \"!\" bubble with its icon")
			advance(math.max(0, plan.hitAt - LEAD / 2 - now()))
			local _, r2 = colors()
			check(r2 > 0, attackId .. ": RED right before the damage")
			if attackId == "burning_floor" or attackId == "lava_blobs" then
				advance(1)
				local _, r3 = colors()
				check(r3 > 0, attackId .. ": the burning lava stays drawn red-orange while it hurts")
			end
			advance(3)
		end
		local distinct = 0
		for _ in warnings do
			distinct += 1
		end
		check(distinct == 4, "four different warning sounds")
		-- Final Eruption: special banner, red edge, green rocks, arrow.
		calm()
		table.clear(played)
		local view = planView(2, 1, {})
		view.bossPosition = f.anchor.Position
		local plan = Forgeheart.plan(view, "final_eruption", now())
		local payload = { attack = plan.id, action = plan.action, telegraphAt = plan.telegraphAt, hitAt = plan.hitAt, data = plan.payload, motion = plan.motion }
		BossFX.attack(payload)
		BossHud.attack(payload, BossFX.AttackColors.final_eruption)
		advance(0.3)
		local hud = alice.PlayerGui:FindFirstChild("RiftHUD")
		local banner, edge, arrow, arrowText = nil, nil, nil, nil
		for _, d in hud:GetDescendants() do
			if d.Name == "AttackBanner" then
				banner = d
			elseif d.Name == "SpecialEdge" then
				edge = d
			elseif d.Name == "SafeArrow" then
				arrow = d
				arrowText = d:FindFirstChild("Text")
			end
		end
		check(banner and banner.Visible and (string.find(banner.Text, Strings.en["boss.special"], 1, true) or string.find(banner.Text, Strings.fr["boss.special"], 1, true)), "\"SPECIAL ATTACK!\" announced with the hint")
		check(edge and edge.Visible, "pulsing red screen edge until the eruption")
		check(table.find(played, "FHEruptionAlarm") ~= nil, "deep alarm before the eruption")
		local beacons = 0
		for _, d in Engine.workspace.ClientBoss:GetDescendants() do
			if d.Name == "SafeBeacon" and d.Transparency < 0.9 then
				beacons += 1
			end
		end
		check(beacons == 3, "three green beacons on the safe rocks (" .. beacons .. ")")
		check(BossFX.safeZone and BossFX.safeZone.spots and #BossFX.safeZone.spots == 3, "the HUD knows the safe rocks")
		check(arrow and arrow.Visible and arrowText and (arrowText.Text == Strings.en["boss.Forgeheart.safeGo"] or arrowText.Text == Strings.fr["boss.Forgeheart.safeGo"]), "arrow: run to a GREEN rock")
		local spot = BossFX.safeZone.spots[1]
		Engine.moveTo(alice, Vector3.new(spot.X, FLOOR + 3, spot.Z))
		advance(0.3)
		check(arrowText.Text == Strings.en["boss.Forgeheart.safeHere"] or arrowText.Text == Strings.fr["boss.Forgeheart.safeHere"], "on the rock: \"safe on the rock!\"")
		advance(math.max(0, plan.hitAt + 0.3 - now()))
		check(table.find(played, "FHEruptionBuild") ~= nil and table.find(played, "FHBigImpact") ~= nil, "pressure build-up then the big KABOOM")
		check(not edge.Visible, "the red edge stops after the hit")
		-- HUD bar follows the boss.
		local name, mood, head = nil, nil, nil
		for _, d in hud:GetDescendants() do
			if d.Name == "BossName" then
				name = d
			elseif d.Name == "Mood" then
				mood = d
			elseif d.Name == "BossHead" and d:FindFirstChild("Lava1") then
				head = d
			end
		end
		check(name and name.Text == Strings.en["boss.Forgeheart.name"], "HUD bar: Forgeheart")
		check(mood and string.sub(mood.Text, 1, 3) == "1/3", "phase indicator 1/3 (" .. tostring(mood and mood.Text) .. ")")
		check(head ~= nil, "HUD bar: Forgeheart's own head")
		Settings.quality = quality
		Audio.play, Audio.playAt = origPlay, origPlayAt
		reset()
		-- Portal card: Forgeheart's loot, theme and the next boss.
		BossService.setNextBoss("Forgeheart")
		advance(0.5)
		local UI = creq("UI")
		local BossPortal = creq("UI.Screens.BossPortal")
		UI.open("BossPortal")
		advance(0.4)
		local rows = BossPortal.debugRows()
		for _, entry in DEF.loot do
			check(rows[entry.id] and string.find(rows[entry.id], Bosses.percent(entry.chance), 1, true) ~= nil, "card: exact chance of " .. entry.id .. " (" .. Bosses.percent(entry.chance) .. ")")
		end
		check(rows.void_shard == nil, "card: only Forgeheart's rewards")
		local modal = alice.PlayerGui:FindFirstChild("RiftModals")
		local music, nextBoss = nil, nil
		for _, d in modal:GetDescendants() do
			if d.Name == "Music" and d:IsA("TextLabel") then
				music = d
			elseif d.Name == "NextBoss" then
				nextBoss = d
			end
		end
		check(music and string.find(music.Text, "Mindwinder (a)", 1, true) ~= nil, "card names his theme: Mindwinder (a)")
		check(nextBoss and nextBoss.Text ~= "", "card previews the next boss (" .. tostring(nextBoss and nextBoss.Text) .. ")")
		UI.close()
		local BossCodex = creq("UI.Screens.BossCodex")
		check(#BossCodex.debugCards() == 2, "Codex: one card per boss")
		local board = nil
		for _, d in Engine.workspace.ClientBoss:GetDescendants() do
			if d.Name == "PortalBoard" then
				board = d
			end
		end
		local nextLine = board and board:FindFirstChild("Next", true)
		check(nextLine and nextLine.Text ~= "", "portal board: countdown + the boss after")
		reset()
	end)

	--------------------------------------------------------------------------
	scenario("V2 Forgeheart: audio identity, verification, music per boss, ducking, priorities", function()
		local AudioCheck = creq("Controllers.AudioCheck")
		local Audio = creq("Controllers.Audio")
		local MusicDirector = creq("Controllers.MusicDirector")
		local BossFX = creq("Controllers.BossFX")
		-- Candidates are only used once verified.
		check(AudioCheck.status("rbxassetid://5048722308") == "unchecked", "headless: no ContentProvider, the ids stay unchecked")
		local _, unverified = Audio.resolve("VWAppear")
		check(unverified == Sounds.VWAppear.fallback, "unverified candidate: the built-in fallback plays")
		AudioCheck.debugProbe(function(id)
			if id == "rbxassetid://1885641628" then
				return false, nil
			elseif id == "rbxassetid://1844669489" then
				return true, 140
			elseif id == "rbxassetid://1838075377" then
				return true, 150
			end
			return true, 2
		end)
		local _, ok = Audio.resolve("VWAppear")
		check(ok == "rbxassetid://5048722308", "verified candidate is used (VWAppear)")
		local _, failed = Audio.resolve("VWBounce")
		check(AudioCheck.status("rbxassetid://1885641628") == "failed" and failed == Sounds.VWBounce.fallback, "unavailable id (deleted / private): fallback + warning")
		check(AudioCheck.status("rbxassetid://1844669489") == "tooLong" and Audio.playLoop("FHLavaAmbience2") == nil, "1844669489 is a long track: refused as a lava ambience (it would fight the boss theme)")
		check(AudioCheck.status("rbxassetid://1838075377") == "ok" and AudioCheck.musicAllowed("rbxassetid://1838075377"), "Forgeheart theme accepted once it loads")
		local logged = false
		for _, line in Engine.log do
			if string.find(line, "1885641628", 1, true) then
				logged = true
			end
		end
		check(logged, "the failing id is named in the Output")
		check(#AudioCheck.report() >= 9, "report lists every configured id (" .. #AudioCheck.report() .. ")")
		-- Music: one theme per boss, intensity without speed change.
		local function enter(bossId)
			reset()
			local f = BossService.open(bossId)
			sessionOf(alice).data.power.peak = math.max(sessionOf(alice).data.power.peak, 1000)
			atPortal(alice, 1)
			BossService.join(alice)
			advance(0.2)
			BossService.devStart()
			advance(0.2)
			advance(Bosses.Combat.Intro + 0.1)
			calm()
			advance(2)
			return f
		end
		enter("VoidWarden")
		local state, key = MusicDirector.current()
		check(state == "Boss" and key == "Boss.VoidWarden.1", "Void Warden fight: Dynamic Swing slot (" .. tostring(key) .. ")")
		local f = enter("Forgeheart")
		state, key = MusicDirector.current()
		check(state == "Boss" and key == "Boss.Forgeheart.1", "Forgeheart fight: Mindwinder slot (" .. tostring(key) .. ")")
		advance(3)
		local info = MusicDirector.debugInfo()
		check(#info.audible == 1 and info.audible[1].key == "Boss.Forgeheart.1", "a single music track audible")
		check(MusicDirector.intensity() == 1, "intensity 1 in phase 1")
		BossService.devSetHealth(0.25)
		advance(1)
		check(f.phase == 3 and MusicDirector.intensity() == 3, "phase 3: brighter mix (intensity 3)")
		local themeSound = nil
		for _, d in game:GetService("SoundService"):GetDescendants() do
			if d.Name == "Music_Boss.Forgeheart.1" then
				themeSound = d
			end
		end
		local eq = themeSound and themeSound:FindFirstChildOfClass("EqualizerSoundEffect")
		check(themeSound and eq and eq.HighGain == Music.BossIntensity[3].high and themeSound.PlaybackSpeed == 1, "EQ layer on the theme, never sped up")
		-- Ducking under a critical warning.
		Audio.play("BossDanger")
		advance(0.3)
		check(Audio.debugMix().duck < 0.7, string.format("music ducked under the danger tick (%.2f)", Audio.debugMix().duck))
		advance(3)
		check(Audio.debugMix().duck > 0.99, "music back to the player's level")
		-- Anti-spam and priorities.
		local origin = Vector3.new(ARENA.Center.X, FLOOR + 2, ARENA.Center.Z)
		local played = 0
		for _ = 1, 30 do
			if Audio.playAt("FHMeteorBoom", origin) then
				played += 1
			end
		end
		check(played == 1, "30 meteor booms in one frame: one sound (minGap)")
		check(Sounds.BossDanger.priority == 1 and Sounds.FHEruptionAlarm.priority == 2 and Sounds.BossWarnCleanup.priority == 2 and Sounds.FHHammerHit.priority == 3 and (Sounds.FHWarnBlobs.priority or 4) == 4 and Sounds.FHLavaAmbience.priority == 5, "priorities: danger > specials > impacts > attacks > ambience")
		-- Each boss has its own sounds (no shared BOOM for every attack).
		local seen, shared = {}, 0
		for _, key in BossFX.WarnSounds do
			if seen[key] then
				shared += 1
			end
			seen[key] = true
		end
		check(shared == 0, "ten attacks, ten different warning sounds")
		local source = fs.readFile("src/client/Controllers/BossFX.luau") .. fs.readFile("src/client/Boss/ForgeheartFX.luau")
		local impacts = 0
		for _, k in { "VWImpact", "VWSweep", "VWGooSplat", "VWDustPouf", "VWCleanupSweep", "FHHammerHit", "FHBlobPop", "FHMeteorBoom", "FHBigImpact", "FHLavaCrackle" } do
			if string.find(source, '"' .. k .. '"', 1, true) then
				impacts += 1
			end
		end
		check(impacts == 10, "ten distinct impact sounds wired (" .. impacts .. "/10)")
		check(BossFX.ActionSounds.VoidWarden.Intro == "VWAppear" and BossFX.ActionSounds.Forgeheart.Defeated == "FHDefeat" and BossFX.ActionSounds.VoidWarden.Defeated == "VWDefeat", "entrances and defeats sound different per boss")
		reset()
		advance(Music.States[1].hold + Music.States[1].fadeOut + 1)
		state = MusicDirector.current()
		check(state ~= "Boss", "boss music stops after the fight (" .. tostring(state) .. ")")
		-- Back to the headless state for the next scenarios.
		AudioCheck.debugProbe(nil)
	end)
end
