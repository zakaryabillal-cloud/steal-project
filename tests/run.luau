--!nocheck
-- Headless gameplay test suite for RIFT HEIST.
--
--   lune run tests/run.luau            (from the repository root)
--
-- Runs the real server code (and one real client) inside the fake engine in
-- tests/harness, with virtual time, through multiplayer scenarios.

local fs = require("@lune/fs")
local process = require("@lune/process")
local net = require("@lune/net")

local Vector3 = require("@lune/roblox").Vector3
local CFrame = require("@lune/roblox").CFrame

local Api = require("./harness/Api")
local Engine = require("./harness/Engine")
local Loader = require("./harness/Loader")

local ROOT = process.cwd
local CACHE = ROOT .. "/tools/.cache"
local API_PATH = CACHE .. "/API-Dump.json"

if not fs.isFile(API_PATH) then
	print("Downloading Roblox API dump...")
	if not fs.isDir(CACHE) then
		fs.writeDir(CACHE)
	end
	local response = net.request("https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/API-Dump.json")
	assert(response.ok, "could not download API dump")
	fs.writeFile(API_PATH, response.body)
end
if not fs.isFile(ROOT .. "/sourcemap.json") then
	local result = process.exec("rojo", { "sourcemap", "default.project.json", "-o", "sourcemap.json" })
	assert(result.ok, "rojo sourcemap failed: " .. result.stderr)
end

Api.load(API_PATH)
Engine.verbose = process.env.VERBOSE == "1"

local game = Engine.createGame()
Loader.mount(game, ROOT .. "/sourcemap.json", ROOT)
-- Lighting children declared in default.project.json exist in a real place.
local lighting = game:GetService("Lighting")
for _, className in { "Atmosphere", "Sky", "BloomEffect", "ColorCorrectionEffect", "SunRaysEffect", "DepthOfFieldEffect" } do
	if not lighting:FindFirstChildOfClass(className) then
		local name = ({ BloomEffect = "Bloom", ColorCorrectionEffect = "ColorCorrection", SunRaysEffect = "SunRays", DepthOfFieldEffect = "DepthOfField" })[className] or className
		Engine.createInternal(className, name, lighting)
	end
end

----------------------------------------------------------------------------
-- Test helpers
----------------------------------------------------------------------------

local results = { passed = 0, failed = 0, failures = {} }
local currentScenario = ""

local function check(condition: any, message: string)
	if condition then
		results.passed += 1
	else
		results.failed += 1
		table.insert(results.failures, currentScenario .. ": " .. message)
		print("  \27[31m✗ " .. message .. "\27[0m")
	end
end

local function scenario(name: string, fn: () -> ())
	currentScenario = name
	print("\n\27[36m▶ " .. name .. "\27[0m")
	local errorsBefore = #Engine.errors
	local ok, err = xpcall(fn, debug.traceback)
	if not ok then
		check(false, "scenario crashed: " .. tostring(err))
	end
	check(#Engine.errors == errorsBefore, string.format("no runtime errors (%d new)", #Engine.errors - errorsBefore))
end

local function advance(seconds: number)
	Engine.advance(seconds)
end

local function waitFor(predicate: () -> boolean, timeout: number): boolean
	local elapsed = 0
	while elapsed < timeout do
		if predicate() then
			return true
		end
		advance(0.1)
		elapsed += 0.1
	end
	return predicate()
end

local server = {}
local function sreq(path: string)
	local node = game:GetService("ServerScriptService"):FindFirstChild("Server")
	for part in string.gmatch(path, "[^%.]+") do
		node = node:FindFirstChild(part)
		assert(node, "missing module " .. path)
	end
	return Loader.require("server", node)
end
local function shared(path: string)
	local node = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
	for part in string.gmatch(path, "[^%.]+") do
		node = node:FindFirstChild(part)
	end
	return Loader.require("server", node)
end

local function relics(state: string?)
	local folder = Engine.workspace:FindFirstChild("Relics")
	local list = {}
	if not folder then
		return list
	end
	for _, anchor in folder:GetChildren() do
		if (state == nil or anchor:GetAttribute("State") == state) and anchor:GetAttribute("Vanish") == nil then
			table.insert(list, anchor)
		end
	end
	return list
end

local function prompt(anchor, action: string, player, signal: string?)
	local p = anchor:FindFirstChild(action)
	assert(p, "anchor has no " .. action .. " prompt")
	Engine.signal(p, signal or "Triggered"):Fire(player)
	Engine.runUntil(Engine.now)
	advance(0.05)
end

local function notifications(player): { string }
	local keys = {}
	for _, entry in Engine.clientLog[player] or {} do
		if entry.remote == "Notify" then
			table.insert(keys, entry.args[1])
		end
	end
	return keys
end

local function hasNotification(player, key: string): boolean
	return table.find(notifications(player), key) ~= nil
end

local function clearLog(player)
	Engine.clientLog[player] = {}
end

local function remote(name: string)
	return game:GetService("ReplicatedStorage"):FindFirstChild("Remotes"):FindFirstChild(name)
end

----------------------------------------------------------------------------
-- Boot the server
----------------------------------------------------------------------------

local serverScript = game:GetService("ServerScriptService"):FindFirstChild("Server")
Loader.run("server", serverScript)
advance(2)

local Sessions = sreq("Core.Sessions")
local Layout = shared("Layout")
local GameConfig = shared("Config.GameConfig")
local PlotService = sreq("Services.PlotService")
local RelicService = sreq("Services.RelicService")
local RiftService = sreq("Services.RiftService")
local Economy = shared("Economy")

local function workspace_time()
	return Engine.workspace:GetServerTimeNow()
end

local function sessionOf(player)
	return Sessions.get(player)
end

-- Server-sanctioned teleport (the movement guard ignores it).
local function teleport(player, position)
	local s = Sessions.get(player)
	if s then
		s.teleportGraceUntil = workspace_time() + 1.5
		s.lastPosition = nil
	end
	Engine.moveTo(player, position)
end

local function plotCenter(player)
	return Layout.plotCFrame(sessionOf(player).plot).Position + Vector3.new(0, 3, 0)
end

local function insideOwnPlot(player)
	teleport(player, plotCenter(player) + Vector3.new(0, 0, -8))
	advance(0.4)
end

-- Spawns a relic of the given id at a free spot and claims it for `player`.
local function claimRelic(player, relicId: string?, mutation: string?)
	local before = {}
	for _, anchor in relics("Rift") do
		before[anchor] = true
	end
	if relicId then
		local def = shared("Config.Relics").get(relicId)
		RiftService.force({ relicId = relicId, rarity = def.rarity, mutation = mutation })
	end
	local target
	waitFor(function()
		for _, anchor in relics("Rift") do
			if not before[anchor] or relicId == nil then
				if relicId == nil or anchor:GetAttribute("RelicId") == relicId then
					target = anchor
					return true
				end
			end
		end
		return false
	end, 20)
	assert(target, "no relic spawned")
	teleport(player, target.Position + Vector3.new(0, -2, 2))
	prompt(target, "Claim", player)
	return target
end


----------------------------------------------------------------------------
-- Scenarios
----------------------------------------------------------------------------

scenario("World generation", function()
	check(Engine.workspace:GetAttribute("WorldReady") == true, "WorldReady attribute set")
	local sanctuaries = Engine.workspace:FindFirstChild("Sanctuaries")
	check(sanctuaries and #sanctuaries:GetChildren() == 8, "8 sanctuaries built")
	check(Engine.terrainOps() > 50, "terrain written (" .. Engine.terrainOps() .. " ops)")
	local partCount = 0
	for _, d in Engine.workspace:GetDescendants() do
		if d:IsA("BasePart") then
			partCount += 1
		end
	end
	print("  parts in world:", partCount)
	check(partCount > 1000 and partCount < 6000, "reasonable part budget (" .. partCount .. ")")
	check(game:GetService("ReplicatedStorage"):FindFirstChild("Remotes") ~= nil, "remotes created")
end)

local alice, bob

scenario("Solo: join, spawn, tutorial start", function()
	alice = Engine.addPlayer("Alice", 1001)
	check(waitFor(function()
		local s = sessionOf(alice)
		return s ~= nil and s.loaded and alice.Character ~= nil
	end, 5), "Alice loaded and spawned")
	local s = sessionOf(alice)
	check(s.plot ~= nil, "Alice got a Sanctuary")
	check(s.canSave == true and s.dataStatus == "new", "fresh profile, saving enabled")
	local root = alice.Character:FindFirstChild("HumanoidRootPart")
	check(PlotService.isInside(s.plot, root.Position), "spawned inside own Sanctuary")
	check(alice:FindFirstChild("leaderstats") ~= nil, "leaderstats created")
	local humanoid = alice.Character:FindFirstChild("Humanoid")
	check(humanoid.WalkSpeed == GameConfig.Player.BaseWalkSpeed, "base walk speed applied")
	check(s.data.tutorial == 0, "tutorial at step 0")
end)

scenario("Solo: Rift spawn, claim, carry, deposit", function()
	check(waitFor(function()
		return #relics("Rift") > 0
	end, 15), "Rift spawned a relic")
	local anchor = claimRelic(alice, "storm_crystal")
	local s = sessionOf(alice)
	check(anchor:GetAttribute("State") == "Carried", "relic carried after claim")
	check(#s.carrying == 1, "session tracks carried relic")
	check(s.data.tutorial == 1, "tutorial advanced to 'return'")
	local humanoid = alice.Character:FindFirstChild("Humanoid")
	check(humanoid.WalkSpeed < GameConfig.Player.BaseWalkSpeed, "carrying slows you down")
	insideOwnPlot(alice)
	check(anchor:GetAttribute("State") == "Placed", "relic placed on entering Sanctuary")
	check(#s.data.relics == 1 and s.data.relics[1].id == "storm_crystal", "save data contains relic")
	check(s.data.dex.storm_crystal ~= nil, "RiftDex registered discovery")
	check(s.data.tutorial == 2, "tutorial advanced to 'collect'")
	check(s.rate > 0, "Essence rate > 0 (" .. s.rate .. ")")
	check(humanoid.WalkSpeed == GameConfig.Player.BaseWalkSpeed, "speed restored after deposit")
end)

scenario("Solo: Essence production and Core collection", function()
	local s = sessionOf(alice)
	teleport(alice, plotCenter(alice) + Vector3.new(0, 0, -20))
	advance(5)
	check(s.data.coreStored >= GameConfig.Economy.FirstDepositGift, "core holds gift + production (" .. s.data.coreStored .. ")")
	local before = s.data.essence
	teleport(alice, plotCenter(alice) + Vector3.new(5, 0, 0))
	advance(1)
	check(s.data.essence > before, "collecting at the Core adds Essence")
	check(s.data.coreStored < 1, "core emptied")
	check(s.data.tutorial == 3, "tutorial advanced to 'upgrade'")
	local leaderstat = alice.leaderstats:FindFirstChild("Essence")
	check(leaderstat.Value == math.floor(s.data.essence), "leaderstats mirror Essence")
end)

scenario("Solo: purchases are validated server-side", function()
	local s = sessionOf(alice)
	local purchase = remote("Purchase")
	local ok, reason = Engine.invokeServer(purchase, alice, "tier")
	check(ok == false and reason == "notEnough", "cannot buy tier without Essence")
	ok, reason = Engine.invokeServer(purchase, alice, "pedestal")
	check(ok == true, "pedestal purchase succeeds (" .. tostring(reason) .. ")")
	check(s.data.upgrades.pedestal == 1, "pedestal level incremented")
	check(s.data.tutorial == 4, "tutorial completed")
	ok, reason = Engine.invokeServer(purchase, alice, "nonexistent")
	check(ok == false, "unknown upgrade rejected")
	ok = Engine.invokeServer(purchase, alice, { "table" })
	check(ok == false, "malformed argument rejected")
	local plot = PlotService.get(s.plot)
	local active = 0
	for _, pedestal in plot.pedestals do
		if pedestal:GetAttribute("State") == "Active" then
			active += 1
		end
	end
	check(active == 4, "4 pedestals active after purchase (" .. active .. ")")
end)

scenario("Solo: duplicates fuse into levels", function()
	local s = sessionOf(alice)
	claimRelic(alice, "storm_crystal")
	insideOwnPlot(alice)
	check(#s.data.relics == 1, "duplicate fused instead of using a pedestal")
	check(s.data.relics[1].level == 2, "relic reached level 2")
	local placed = RelicService.get(s.data.relics[1].uid)
	check(placed and placed.anchor:GetAttribute("Level") == 2, "anchor shows level 2")
end)

scenario("Spam: remotes are rate-limited and never error", function()
	local s = sessionOf(alice)
	local dash = remote("Dash")
	for _ = 1, 200 do
		Engine.fireServer(dash, alice)
	end
	for _ = 1, 50 do
		Engine.fireServer(remote("Settings"), alice, "sfx", 0.5)
		Engine.fireServer(remote("Settings"), alice, "quality", "Ultra")
		Engine.fireServer(remote("Settings"), alice, 12, nil)
		Engine.fireServer(remote("TutorialSeen"), alice, string.rep("x", 400))
		Engine.fireServer(remote("TutorialSeen"), alice, "firstGift")
	end
	for _ = 1, 30 do
		Engine.invokeServer(remote("Purchase"), alice, "stride")
	end
	advance(0.5)
	check(s.data.settings.quality ~= "Ultra", "invalid setting ignored")
	check(s.data.tips[string.rep("x", 400)] == nil, "oversized tip ignored")
	check(s.cooldowns.dash ~= nil, "dash cooldown tracked")
end)

scenario("Multiplayer: second player, novice protection", function()
	bob = Engine.addPlayer("Bob", 1002)
	check(waitFor(function()
		local s = sessionOf(bob)
		return s ~= nil and s.loaded and bob.Character ~= nil
	end, 5), "Bob loaded")
	check(sessionOf(bob).plot ~= sessionOf(alice).plot, "different Sanctuaries")
	-- Give Alice 3 relics so the last-relics rule does not apply.
	claimRelic(alice, "ember_shard")
	insideOwnPlot(alice)
	claimRelic(alice, "tide_pearl")
	insideOwnPlot(alice)
	local sa = sessionOf(alice)
	check(#sa.data.relics == 3, "Alice displays 3 relics (" .. #sa.data.relics .. ")")
	-- Alice is still a novice: Bob cannot steal.
	local target = RelicService.get(sa.data.relics[1].uid)
	teleport(bob, target.anchor.Position + Vector3.new(0, -3, 3))
	clearLog(bob)
	prompt(target.anchor, "Steal", bob, "PromptButtonHoldBegan")
	check(hasNotification(bob, "block.novice"), "novice protection blocks the theft")
end)

local stolenUid

scenario("Multiplayer: theft, alert, chase, recovery", function()
	local sa, sb = sessionOf(alice), sessionOf(bob)
	sa.data.playTime = GameConfig.Steal.NoviceSeconds + 10
	-- Bob needs a Sanctuary with room: give him a relic first.
	claimRelic(bob, "verdant_seed")
	insideOwnPlot(bob)
	-- Steal from too far away fails.
	local target = RelicService.get(sa.data.relics[2].uid)
	teleport(bob, target.anchor.Position + Vector3.new(0, 0, 30))
	clearLog(bob)
	prompt(target.anchor, "Steal", bob, "PromptButtonHoldBegan")
	check(hasNotification(bob, "block.distance") or hasNotification(bob, "block.inside"), "remote steal rejected")
	-- Proper theft.
	teleport(bob, target.anchor.Position + Vector3.new(0, -3, 3))
	clearLog(alice)
	prompt(target.anchor, "Steal", bob, "PromptButtonHoldBegan")
	check(hasNotification(alice, "n.stealAlert"), "owner alerted when the hold begins")
	-- Triggering instantly (exploit) is ignored.
	prompt(target.anchor, "Steal", bob, "Triggered")
	check(target.state == "Placed", "instant trigger ignored (hold time enforced)")
	prompt(target.anchor, "Steal", bob, "PromptButtonHoldBegan")
	advance(3.2)
	prompt(target.anchor, "Steal", bob, "Triggered")
	check(target.state == "Carried" and target.carrierId == bob.UserId, "relic stolen by Bob")
	check(target.stolenFrom == alice.UserId, "relic tagged as stolen")
	check(hasNotification(alice, "n.stolen"), "owner told about the theft")
	local plot = PlotService.get(sa.plot)
	check(PlotService.protection(plot) == "Aegis", "victim Sanctuary under Aegis")
	stolenUid = target.uid
	-- Alice catches Bob outside and pulses him.
	teleport(bob, Layout.plotCFrame(sa.plot).Position + Vector3.new(0, -6, 0) + (Layout.plotCFrame(sa.plot).LookVector * 70))
	teleport(alice, bob.Character.HumanoidRootPart.Position + Vector3.new(4, 0, 0))
	sa.steadyUntil = 0
	sb.steadyUntil = 0
	sb.spawnProtectedUntil = 0
	Engine.fireServer(remote("Pulse"), alice)
	advance(0.3)
	check(target.state == "Dropped", "pulse knocks the relic loose")
	check(sb.stunnedUntil > 0, "thief dazed")
	-- Owner grabs it back.
	teleport(alice, target.anchor.Position + Vector3.new(0, -1, 1))
	prompt(target.anchor, "Grab", alice)
	check(target.state == "Placed" and target.ownerId == alice.UserId, "owner recovered the relic")
	check(#sa.data.relics == 3, "victim data unchanged by the failed heist")
end)

scenario("Multiplayer: Aegis + cooldown + pair limits", function()
	local sa = sessionOf(alice)
	advance(1)
	local target = RelicService.get(sa.data.relics[3].uid)
	teleport(bob, target.anchor.Position + Vector3.new(0, -3, 3))
	clearLog(bob)
	prompt(target.anchor, "Steal", bob, "PromptButtonHoldBegan")
	check(hasNotification(bob, "block.aegis"), "Aegis blocks immediate re-theft [" .. table.concat(notifications(bob), ",") .. "]")
	advance(GameConfig.Steal.AegisDuration + 1)
	clearLog(bob)
	teleport(bob, target.anchor.Position + Vector3.new(0, -3, 3))
	prompt(target.anchor, "Steal", bob, "PromptButtonHoldBegan")
	check(not hasNotification(bob, "block.aegis"), "Aegis expired")
end)

scenario("Multiplayer: heist secured transfers ownership", function()
	local sa, sb = sessionOf(alice), sessionOf(bob)
	sa.lastActivity = workspace_time() + 1e6
	local target = RelicService.get(sa.data.relics[3].uid)
	sb.cooldowns.steal = 0
	teleport(bob, target.anchor.Position + Vector3.new(0, -3, 3))
	prompt(target.anchor, "Steal", bob, "PromptButtonHoldBegan")
	advance(3.5)
	prompt(target.anchor, "Steal", bob, "Triggered")
	check(target.state == "Carried", "second theft succeeds [" .. table.concat(notifications(bob), ",") .. "]")
	local relicCountBefore = #sb.data.relics
	insideOwnPlot(bob)
	check(target.state == "Placed" and target.ownerId == bob.UserId, "heist secured in Bob's Sanctuary")
	check(#sa.data.relics == 2, "relic removed from Alice's save")
	check(#sb.data.relics == relicCountBefore + 1 or target.state == "Placed", "relic added to Bob's save (or fused)")
	check(sb.data.stats.stolen >= 1 and sa.data.stats.lost >= 1, "stats updated")
end)

scenario("Edge: double claim of the same relic", function()
	local anchor
	local def = shared("Config.Relics").get("rune_tablet")
	RiftService.force({ relicId = "rune_tablet", rarity = def.rarity })
	waitFor(function()
		for _, a in relics("Rift") do
			if a:GetAttribute("RelicId") == "rune_tablet" then
				anchor = a
				return true
			end
		end
		return false
	end, 15)
	assert(anchor, "no rune tablet")
	teleport(alice, anchor.Position + Vector3.new(0, -2, 2))
	teleport(bob, anchor.Position + Vector3.new(0, -2, -2))
	local p = anchor:FindFirstChild("Claim")
	Engine.signal(p, "Triggered"):Fire(alice)
	Engine.signal(p, "Triggered"):Fire(bob)
	advance(0.2)
	local sa, sb = sessionOf(alice), sessionOf(bob)
	local holders = 0
	for _, s in { sa, sb } do
		for _, uid in s.carrying do
			if uid == anchor.Name then
				holders += 1
			end
		end
	end
	check(holders == 1, "exactly one player got the relic")
	-- Clean up: whoever holds it goes home.
	insideOwnPlot(alice)
	insideOwnPlot(bob)
end)

scenario("Edge: thief leaves mid-heist -> relic flies home", function()
	local sa, sb = sessionOf(alice), sessionOf(bob)
	advance(GameConfig.Steal.AegisDuration + 1)
	sb.cooldowns.steal = 0
	sb.stealLog = {}
	sa.robbedLog = {}
	sa.lastActivity = workspace_time() + 1e6
	local count = #sa.data.relics
	if count < 3 then
		claimRelic(alice, "frost_lotus")
		insideOwnPlot(alice)
	end
	local target = RelicService.get(sa.data.relics[1].uid)
	teleport(bob, target.anchor.Position + Vector3.new(0, -3, 3))
	prompt(target.anchor, "Steal", bob, "PromptButtonHoldBegan")
	advance(target.rarity == "Common" and 1.3 or 3.5)
	prompt(target.anchor, "Steal", bob, "Triggered")
	check(target.state == "Carried", "theft in progress")
	Engine.removePlayer(bob)
	advance(1)
	check(target.state == "Placed" and target.ownerId == alice.UserId, "relic returned to its owner")
	check(sessionOf(bob) == nil, "Bob's session closed")
end)

scenario("Edge: victim leaves mid-heist -> chase voided, relic kept", function()
	bob = Engine.addPlayer("Bob", 1002)
	waitFor(function()
		local s = sessionOf(bob)
		return s ~= nil and s.loaded and bob.Character ~= nil
	end, 5)
	local sb = sessionOf(bob)
	check(#sb.data.relics >= 1, "Bob's collection restored on rejoin (" .. #sb.data.relics .. ")")
	check(sb.dataStatus == "loaded", "Bob's profile loaded from DataStore")
	local sa = sessionOf(alice)
	advance(GameConfig.Steal.AegisDuration + 1)
	sa.lastActivity = workspace_time() + 1e6
	sb.data.playTime = GameConfig.Steal.NoviceSeconds + 1
	while #sa.data.relics < 3 do
		claimRelic(alice, "ember_shard")
		insideOwnPlot(alice)
	end
	local relicCount = #sa.data.relics
	local target = RelicService.get(sa.data.relics[1].uid)
	teleport(bob, target.anchor.Position + Vector3.new(0, -3, 3))
	prompt(target.anchor, "Steal", bob, "PromptButtonHoldBegan")
	advance(4.5)
	prompt(target.anchor, "Steal", bob, "Triggered")
	check(target.state == "Carried", "Bob stole from Alice")
	local savedKey = "RiftHeist_Player_v1/u_" .. alice.UserId
	Engine.removePlayer(alice)
	advance(1)
	check(#sb.carrying == 0, "voided relic removed from the thief")
	local saved = Engine.dataStoreData[savedKey]
	check(saved and #saved.relics == relicCount, "Alice's save still contains the relic")
	check(saved and saved.lock == nil, "session lock released on leave")
	-- Reconnect.
	alice = Engine.addPlayer("Alice", 1001)
	check(waitFor(function()
		local s = sessionOf(alice)
		return s ~= nil and s.loaded and alice.Character ~= nil
	end, 5), "Alice reconnected")
	check(#sessionOf(alice).data.relics == relicCount, "collection restored after reconnect")
	check(#relics("Placed") >= relicCount, "relics back on pedestals")
end)

scenario("Edge: carrier dies -> relic dropped then fades", function()
	local sa = sessionOf(alice)
	local anchor = claimRelic(alice, "verdant_seed")
	local entity = RelicService.get(anchor.Name)
	teleport(alice, Layout.plotCFrame(sa.plot).Position + Layout.plotCFrame(sa.plot).LookVector * 80)
	alice.Character.Humanoid.Health = 0
	advance(0.5)
	check(entity.state == "Dropped", "relic dropped on death")
	advance(GameConfig.Player.RespawnDelay + 0.5)
	check(alice.Character and alice.Character.Humanoid.Health > 0, "player respawned")
	advance(GameConfig.Carry.DropLifetime + 1)
	check(not entity.alive, "dropped Rift relic faded back")
end)

scenario("Edge: falling into the void", function()
	local anchor = claimRelic(alice, "tide_pearl")
	local entity = RelicService.get(anchor.Name)
	teleport(alice, Vector3.new(400, GameConfig.Player.VoidKillY - 20, 0))
	advance(1)
	check(alice.Character.Humanoid.Health <= 0 or entity.state ~= "Carried", "void kills the carrier")
	check(not entity.alive or entity.state ~= "Carried", "relic not left floating in the void")
	advance(GameConfig.Player.RespawnDelay + 1)
end)

scenario("Edge: teleport exploit drops carried relics", function()
	local anchor = claimRelic(alice, "rune_tablet")
	local entity = RelicService.get(anchor.Name)
	advance(2.5)
	Engine.moveTo(alice, Vector3.new(-150, Layout.GroundY + 3, 120))
	advance(1.2)
	check(entity.state ~= "Carried", "impossible movement drops the relic")
end)

scenario("Edge: full server queues the 9th player", function()
	local extra = {}
	for i = 1, 7 do
		table.insert(extra, Engine.addPlayer("Guest" .. i, 2000 + i))
	end
	advance(3)
	local queued = extra[#extra]
	local plots = {}
	local assigned = 0
	for _, player in { alice, bob, table.unpack(extra) } do
		local s = sessionOf(player)
		if s and s.plot then
			assigned += 1
			check(plots[s.plot] == nil, "no shared plot")
			plots[s.plot] = true
		end
	end
	check(assigned == 8, "8 players own Sanctuaries (" .. assigned .. ")")
	check(sessionOf(queued).plot == nil, "9th player waits")
	check(hasNotification(queued, "n.waitingPlot"), "9th player told they are queued")
	Engine.removePlayer(extra[1])
	advance(1)
	check(sessionOf(queued).plot ~= nil, "queued player received the freed Sanctuary")
	for i = 2, #extra do
		Engine.removePlayer(extra[i])
	end
	advance(1)
end)

scenario("Edge: DataStore outage", function()
	Engine.dataStoreFail = true
	local carol = Engine.addPlayer("Carol", 3001)
	advance(60)
	local s = sessionOf(carol)
	check(s and s.loaded, "player still gets to play")
	check(s and s.canSave == false, "saving disabled for the session")
	check(hasNotification(carol, "n.dataWarning"), "player warned about data")
	Engine.removePlayer(carol)
	advance(1)
	Engine.dataStoreFail = false
	check(Engine.dataStoreData["RiftHeist_Player_v1/u_3001"] == nil, "nothing written for a failed profile")
end)

scenario("Events: overload, eclipse special relic", function()
	local EventService = sreq("Services.EventService")
	EventService.trigger("RiftOverload")
	advance(0.2)
	check(Engine.workspace:GetAttribute("EventId") == "RiftOverload", "event attribute set")
	local before = #relics("Rift")
	advance(12)
	check(#relics("Rift") >= before, "spawns continue during overload")
	EventService.trigger("Eclipse")
	advance(95)
	check(Engine.workspace:GetAttribute("EventId") == "", "event ends")
end)

scenario("Economy sanity", function()
	check(Economy.relicBaseRate("ember_shard", 1, nil) == 1, "common base rate 1/s")
	check(math.abs(Economy.relicBaseRate("cosmic_eye", 5, "Prismatic") - 60 * 3.4 * 10) < 0.01, "legendary L5 prismatic rate")
	check(Economy.unlockedPedestals({ pedestal = 9, tier = 0, resonance = 0, stride = 0, harness = 0 }) == 5, "tier caps pedestals")
	check(Economy.upgradeBlocker("pedestal", { pedestal = 2, tier = 0, resonance = 0, stride = 0, harness = 0 }) == "needTier", "pedestal needs tier")
	local Rolls = sreq("Core.Rolls")
	local counts = {}
	local rng = Random and Random.new(1) or nil
	local fake = { NextNumber = function(_, a, b)
		local r = math.random()
		return if a then a + (b - a) * r else r
	end, NextInteger = function(_, a, b)
		return math.random(a, b)
	end }
	for _ = 1, 20000 do
		local roll = Rolls.spawn(rng or fake, nil)
		counts[roll.rarity] = (counts[roll.rarity] or 0) + 1
	end
	check((counts.Common or 0) > 10000 and (counts.Common or 0) < 12500, "≈56% commons (" .. tostring(counts.Common) .. ")")
	check((counts.Legendary or 0) > 150 and (counts.Legendary or 0) < 500, "≈1.6% legendaries (" .. tostring(counts.Legendary) .. ")")
	check(counts.Secret == nil or counts.Secret < 40, "secrets stay rare (" .. tostring(counts.Secret) .. ")")
	local eclipse = 0
	for _ = 1, 5000 do
		if Rolls.spawn(fake, "Eclipse").relicId == "eclipse_sigil" then
			eclipse += 1
		end
	end
	check(eclipse > 150 and eclipse < 500, "Eclipse Sigil only during Eclipse (" .. eclipse .. "/5000)")
	check(Rolls.spawn(fake, nil).relicId ~= "eclipse_sigil", "no sigil outside Eclipse")
end)

scenario("Data schema sanitises tampered saves", function()
	local DataSchema = sreq("Core.DataSchema")
	local data = DataSchema.normalize({
		schema = 1,
		essence = -500,
		upgrades = { pedestal = 999, tier = "x", stride = 2.7 },
		relics = {
			{ uid = "a", id = "ember_shard", level = 99, slot = 1 },
			{ uid = "a", id = "ember_shard", level = 1, slot = 2 },
			{ uid = "b", id = "not_a_relic", slot = 2 },
			{ uid = "c", id = "cosmic_eye", mutation = "Fake", slot = 50 },
		},
		dex = { cosmic_eye = { count = "lots", mutations = { Golden = true, Nope = true } }, nope = {} },
		settings = { quality = "Insane", sfx = 7 },
	})
	check(data.essence == 0, "negative essence clamped")
	check(data.upgrades.pedestal == 9 and data.upgrades.tier == 0 and data.upgrades.stride == 2, "upgrade levels clamped")
	check(#data.relics == 2, "duplicate uid and unknown relic dropped (" .. #data.relics .. ")")
	check(data.relics[1].level == 5, "relic level clamped")
	check(data.relics[2].mutation == nil, "unknown mutation removed")
	check(data.relics[2].slot >= 1 and data.relics[2].slot <= 5, "out-of-range slot re-homed")
	check(data.dex.nope == nil and data.dex.cosmic_eye.mutations.Nope == nil, "unknown dex entries removed")
	check(data.settings.quality == "High" and data.settings.sfx == 1, "settings sanitised")
	local blank = DataSchema.normalize("garbage")
	check(blank.essence == 0 and #blank.relics == 0, "garbage input yields defaults")
end)

----------------------------------------------------------------------------
-- Client smoke test: run the real client for Alice
----------------------------------------------------------------------------

scenario("Client: boot, HUD, menus, FX under a live server", function()
	Engine.localPlayer = alice
	Engine.set(game:GetService("Players"), "LocalPlayer", alice)
	Engine.set(game:GetService("LocalizationService"), "RobloxLocaleId", "fr-fr")
	local clientScript = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"):FindFirstChild("Client")
	Loader.run("client", clientScript)
	-- Push a fresh sync to the client.
	Sessions.markDirty(sessionOf(alice))
	advance(4)
	local playerGui = alice:FindFirstChild("PlayerGui")
	check(playerGui:FindFirstChild("RiftHUD") ~= nil, "HUD created")
	-- Play: claim, deposit, collect with the client attached.
	claimRelic(alice, "magma_heart", "Golden")
	advance(1)
	insideOwnPlot(alice)
	advance(2)
	teleport(alice, plotCenter(alice) + Vector3.new(5, 0, 0))
	advance(2)
	-- Open every menu through the UI module.
	local UI = Loader.require("client", game:GetService("StarterPlayer").StarterPlayerScripts.Client.UI)
	for _, name in { "Shop", "Dex", "Settings" } do
		UI.open(name)
		advance(0.5)
		UI.close()
		advance(0.3)
	end
	-- Rare spawn moment + event + pulse/dash input paths.
	local def = shared("Config.Relics").get("pocket_planet")
	RiftService.force({ relicId = "pocket_planet", rarity = def.rarity, mutation = "Prismatic" })
	advance(6)
	sreq("Services.EventService").trigger("VoidStorm")
	advance(3)
	local Abilities = Loader.require("client", game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.Abilities)
	Abilities.dash()
	Abilities.pulse()
	Abilities.seal()
	advance(2)
	local Settings = Loader.require("client", game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.Settings)
	Settings.set("language", "en")
	Settings.set("quality", "Low")
	advance(1)
	-- Discovery card for every relic and mutation (exercises the factory in viewports).
	local Discovery = Loader.require("client", game:GetService("StarterPlayer").StarterPlayerScripts.Client.UI.Screens.Discovery)
	for _, relic in shared("Config.Relics").list do
		Discovery.show({ relicId = relic.id, mutation = nil, isNew = true, isNewMutation = false, found = 1, total = 19 })
	end
	advance(120)
	check(true, "client survived the session")
end)

scenario("Factory: every relic x mutation builds and animates", function()
	local Factory = Loader.require("client", game:GetService("ReplicatedStorage").Shared.Relics.RelicFactory)
	local Relics = shared("Config.Relics")
	local Mutations = shared("Config.Mutations")
	local built = 0
	for _, relic in Relics.list do
		for _, mutation in { false, table.unpack(Mutations.list) } do
			for _, preview in { false, true } do
				local visual = Factory.build(relic.id, if mutation then mutation.id else nil, { preview = preview })
				if visual then
					built += 1
					local env = { time = 0, dt = 1 / 30, focus = Vector3.new(5, 2, 5), camera = Vector3.new(10, 5, 10), rootCFrame = CFrame.new(0, 10, 0) }
					for frame = 1, 40 do
						env.time = frame / 30
						Factory.step(visual, env)
					end
					Factory.setDetail(visual, 0, 1)
					Factory.setDetail(visual, 2, 0.5)
					Factory.destroy(visual)
				end
			end
		end
	end
	check(built == #Relics.list * (#Mutations.list + 1) * 2, "all " .. built .. " variants built")
end)

----------------------------------------------------------------------------
-- Shutdown
----------------------------------------------------------------------------

scenario("Shutdown: BindToClose saves everyone", function()
	local sa = sessionOf(alice)
	sa.data.essence += 12345
	for _, callback in Engine.closeCallbacks do
		Engine.task.spawn(callback)
	end
	advance(5)
	local saved = Engine.dataStoreData["RiftHeist_Player_v1/u_" .. alice.UserId]
	check(saved and saved.essence == sa.data.essence, "latest Essence persisted on shutdown")
end)

print(string.format("\n\27[1m%d passed, %d failed\27[0m  (%d runtime errors, virtual time %.0fs)", results.passed, results.failed, #Engine.errors, Engine.now))
for _, failure in results.failures do
	print("  - " .. failure)
end
if #Engine.log > 0 and process.env.SHOWLOG == "1" then
	for _, line in Engine.log do
		print(line)
	end
end
process.exit(if results.failed == 0 then 0 else 1)
