--!nocheck
-- V2 phase 3 ("Dynamic audio") scenarios.
--   * MusicState (pure): priorities, debounce, release, anti-flapping,
--     return to the previous state, silent slots, boss phases.
--   * MusicPlayer (real harness Sounds): crossfades, never more than two
--     audible tracks, resume, cache limit, stingers, cleanup, no-id silence.
--   * MusicDirector live in the client (alice): Rift zone, chase as victim /
--     thief / bystander, events, boss attribute, shipped config (5 ids).

local Vector3 = require("@lune/roblox").Vector3

return function(ctx)
	local scenario, check, advance = ctx.scenario, ctx.check, ctx.advance
	local sreq, shared, Engine, Loader, game = ctx.sreq, ctx.shared, ctx.Engine, ctx.Loader, ctx.game
	local alice, bob = ctx.alice(), ctx.bob()

	local Client = game:GetService("StarterPlayer").StarterPlayerScripts.Client
	local function creq(path)
		local node = Client
		for part in string.gmatch(path, "[^%.]+") do
			node = node:FindFirstChild(part)
		end
		return Loader.require("client", node)
	end
	local Music = shared("Config.Music")
	local Sounds = shared("Config.Sounds")
	local MusicState = creq("Music.MusicState")
	local MusicPlayer = creq("Music.MusicPlayer")
	local MusicDirector = creq("Controllers.MusicDirector")
	local SoundService = game:GetService("SoundService")

	local ALL = function()
		return true
	end
	local function only(list)
		local set = {}
		for _, key in list do
			set[key] = true
		end
		return function(key)
			return set[key] == true
		end
	end
	-- The only slots the shipped config fills (patch on top of phase 3).
	local CONFIGURED = {
		Explore = "rbxassetid://9046476113",
		Rift = "rbxassetid://9042760875",
		Chase = "rbxassetid://9046474891",
		ChaseIntense = "rbxassetid://1842546506",
		["Stinger.ChaseStart"] = "rbxassetid://9044615289",
	}
	local function testIds()
		local map = {}
		for key in Music.Tracks do
			map[key] = "test://" .. key -- harness-only placeholder, never shipped
		end
		return map
	end

	--------------------------------------------------------------------------
	scenario("V2 Audio: shipped config (5 configured slots, the rest stays empty)", function()
		local unexpected, undocumented = {}, {}
		for key, track in Music.Tracks do
			local expected = CONFIGURED[key]
			if expected then
				check(track.id == expected, "configured slot " .. key .. " = " .. expected .. " (got " .. tostring(track.id) .. ")")
				check(string.match(track.id, "^rbxassetid://%d+$") ~= nil, "slot " .. key .. " holds a well-formed rbxassetid")
			elseif track.id ~= "" then
				table.insert(unexpected, key)
			end
			if track.mood == "" or track.context == "" or (track.kind ~= "Loop" and track.kind ~= "OneShot") then
				table.insert(undocumented, key)
			end
		end
		local configured = 0
		for key in CONFIGURED do
			check(Music.Tracks[key] ~= nil, "configured key is a real music slot: " .. key)
			configured += 1
		end
		check(configured == 5, "exactly 5 slots configured")
		check(#unexpected == 0, "every other music slot stays empty (" .. table.concat(unexpected, ", ") .. ")")
		check(#undocumented == 0, "every music slot is documented (" .. table.concat(undocumented, ", ") .. ")")
		check(Music.Tracks["Stinger.ChaseStart"].kind == "OneShot", "chase stinger slot is a one-shot")
		check(Music.Tracks.Explore.kind == "Loop" and Music.Tracks.Rift.kind == "Loop" and Music.Tracks.Chase.kind == "Loop" and Music.Tracks.ChaseIntense.kind == "Loop", "configured main slots are loops")
		local sfxIds = {}
		for key, def in Sounds do
			if def.id ~= "" then
				table.insert(sfxIds, key)
			end
		end
		check(#sfxIds == 0, "no SFX asset id invented either")
		check(Sounds.Music == nil, "music moved out of the SFX registry")
		for _, state in Music.States do
			for _, key in Music.candidates(state.id, { boss = "VoidWarden", phase = 3, event = "VoidStorm", intense = true }) do
				if Music.Tracks[key] == nil then
					check(false, "candidate slot exists: " .. key)
				end
			end
		end
		check(Music.Tracks["Boss.VoidWarden.3"] and Music.Tracks["Event.Starfall"] and Music.Tracks["Event.CelestialTide"], "slots prepared for future bosses and events")
	end)

	--------------------------------------------------------------------------
	scenario("V2 Audio: priorities, debounce, release and return", function()
		local m = MusicState.new()
		local d = m:update(0, {}, ALL)
		check(d and d.state == "Explore" and d.key == "Explore", "starts on Explore")
		-- Rift: needs 1.5 s inside before switching.
		local rift = { Rift = {} }
		check(m:update(1, table.clone(rift), ALL) == nil, "Rift not instant (debounce)")
		check(m:update(2, table.clone(rift), ALL) == nil, "still debouncing at 1 s")
		d = m:update(2.6, table.clone(rift), ALL)
		check(d and d.state == "Rift" and d.key == "Rift", "Rift after 1.5 s in the zone")
		-- Chase preempts (higher priority) right after its short debounce.
		local both = function()
			return { Rift = {}, Chase = { intense = false } }
		end
		check(m:update(3, both(), ALL) == nil, "chase debounce")
		d = m:update(3.3, both(), ALL)
		check(d and d.state == "Chase" and d.stinger == "Stinger.ChaseStart", "Chase takes over immediately (with stinger)")
		-- Boss preempts the chase, then a phase change swaps the track at once.
		local boss = function(phase)
			return { Rift = {}, Chase = { intense = false }, Boss = { boss = "VoidWarden", phase = phase } }
		end
		d = m:update(4, boss(1), ALL)
		check(d and d.state == "Boss" and d.key == "Boss.VoidWarden.1", "Boss wins over Chase")
		d = m:update(4.2, boss(2), ALL)
		check(d and d.kind == "track" and d.key == "Boss.VoidWarden.2", "boss phase 2 switches track immediately")
		-- Boss ends at 6 s: held 1.5 s, then back to the chase that is still running.
		check(m:update(6, boss(2), ALL) == nil, "boss fight continues")
		check(m:update(6.2, both(), ALL) == nil, "boss music held after the fight ends")
		check(m:update(7.4, both(), ALL) == nil, "...for its release time")
		d = m:update(7.6, both(), ALL)
		check(d and d.state == "Chase", "returns to the previous state (Chase)")
		-- Chase ends: held 6 s, then back down to the Rift.
		check(m:update(8, table.clone(rift), ALL) == nil, "chase released slowly")
		check(m:update(13.5, table.clone(rift), ALL) == nil, "chase music kept 6 s after the end")
		d = m:update(14.1, table.clone(rift), ALL)
		check(d and d.state == "Rift", "then back to the Rift music")
		-- Leaving the Rift: released after 3 s.
		check(m:update(15, {}, ALL) == nil, "Rift held a moment after leaving")
		d = m:update(18.2, {}, ALL)
		check(d and d.state == "Explore", "back to Explore")
	end)

	--------------------------------------------------------------------------
	scenario("V2 Audio: rapid condition changes do not flap the music", function()
		-- Rift edge: in/out every 0.5 s never reaches the 1.5 s debounce.
		local m = MusicState.new()
		m:update(0, {}, ALL)
		local t = 0
		while t < 20 do
			t += 0.25
			local inside = math.floor(t / 0.5) % 2 == 0
			m:update(t, if inside then { Rift = {} } else {}, ALL)
		end
		check(m.switches == 1 and m.current == "Explore", "no switch while dithering on the Rift edge (" .. m.switches .. ")")
		-- Chase flickering on/off every 0.6 s: one switch in, held throughout.
		m = MusicState.new()
		m:update(0, {}, ALL)
		t = 0
		while t < 20 do
			t += 0.25
			local on = math.floor(t / 0.6) % 2 == 0
			m:update(t, if on then { Chase = {} } else {}, ALL)
		end
		check(m.current == "Chase" and m.switches == 2, "flickering chase: one switch in, no ping-pong (" .. m.switches .. ")")
		-- Many states appearing in quick succession: each downgrade waits.
		m = MusicState.new()
		m:update(0, {}, ALL)
		m:update(1, { Event = { event = "VoidStorm" } }, ALL)
		m:update(1.6, { Event = { event = "VoidStorm" } }, ALL) -- Event
		local before = m.switches
		m:update(2, {}, ALL) -- event ends (held 2 s)
		m:update(4.2, {}, ALL) -- released, but < MinSwitchInterval since 1.6? no: 2.6 s
		check(m.current == "Explore" and m.switches == before + 1, "release honours hold + minimum interval")
		local downgradeTimes = {}
		for _, h in m.history do
			table.insert(downgradeTimes, h.at)
		end
		local okGap = true
		for i = 2, #downgradeTimes do
			if downgradeTimes[i] - downgradeTimes[i - 1] < 0.29 then
				okGap = false
			end
		end
		check(okGap, "never two changes within the same instant")
	end)

	--------------------------------------------------------------------------
	scenario("V2 Audio: silent slots and fallbacks", function()
		local m = MusicState.new()
		local d = m:update(0, {}, only({}))
		check(d and d.state == "Explore" and d.key == nil, "no ids at all: silence, no error")
		m = MusicState.new()
		m:update(0, {}, only({ "Explore" }))
		m:update(1, { Chase = {} }, only({ "Explore" }))
		m:update(2, { Chase = {} }, only({ "Explore" }))
		check(m.current == "Explore" and m.currentKey == "Explore", "missing chase music: exploration keeps playing")
		m = MusicState.new()
		m:update(0, { Chase = { intense = true } }, only({ "Explore", "Chase" }))
		d = m:update(0.4, { Chase = { intense = true } }, only({ "Explore", "Chase" }))
		check(d and d.key == "Chase", "ChaseIntense empty -> Chase")
		m = MusicState.new()
		m:update(0, { Event = { event = "VoidStorm" } }, only({ "Event.Default" }))
		d = m:update(0.6, { Event = { event = "VoidStorm" } }, only({ "Event.Default" }))
		check(d and d.key == "Event.Default", "event without its own track -> Event.Default")
		m = MusicState.new()
		d = m:update(0, { Boss = { boss = "Forgeheart", phase = 2 } }, only({ "Boss.Forgeheart.1" }))
		check(d and d.key == "Boss.Forgeheart.1", "boss phase 2 empty -> phase 1 of the same boss")
		m = MusicState.new()
		d = m:update(0, { Boss = { boss = "Unknown", phase = 2 } }, only({ "Boss.Default.2", "Boss.Default.1" }))
		check(d and d.key == "Boss.Default.2", "unknown boss -> Boss.Default")
		-- With the shipped config: the still-empty Event/Boss slots fall through
		-- to whatever configured music is below them.
		local shipped = function(key)
			return Music.Tracks[key] ~= nil and Music.Tracks[key].id ~= ""
		end
		m = MusicState.new()
		m:update(0, {}, shipped)
		m:update(5, { Event = { event = "VoidStorm" } }, shipped)
		m:update(6, { Event = { event = "VoidStorm" } }, shipped)
		check(m.current == "Explore" and m.currentKey == "Explore", "shipped: event without music -> exploration keeps playing")
		m:update(7, { Event = { event = "VoidStorm" }, Rift = {} }, shipped)
		m:update(9, { Event = { event = "VoidStorm" }, Rift = {} }, shipped)
		check(m.current == "Rift" and m.currentKey == "Rift", "shipped: empty event slot falls through to Rift")
		m:update(12, { Boss = { boss = "VoidWarden", phase = 2 }, Rift = {} }, shipped)
		check(m.current == "Rift", "shipped: boss without music -> Rift keeps playing")
		d = m:update(13, { Boss = { boss = "VoidWarden", phase = 2 }, Chase = { intense = true }, Rift = {} }, shipped)
		m:update(13.5, { Boss = { boss = "VoidWarden", phase = 2 }, Chase = { intense = true }, Rift = {} }, shipped)
		check(m.current == "Chase" and m.currentKey == "ChaseIntense", "shipped: intense chase plays ChaseIntense (" .. tostring(m.currentKey) .. ")")
		check(shipped("Stinger.ChaseStart") and not shipped("Stinger.BossIntro"), "shipped: chase stinger set, boss stinger still empty")
	end)

	--------------------------------------------------------------------------
	scenario("V2 Audio: crossfades, two tracks max, resume, cleanup", function()
		local clock = 0
		local ids = testIds()
		-- The live director now plays the shipped Explore track in the same
		-- SoundService: only count the Sounds this test creates.
		local before = {}
		for _, d in SoundService:GetChildren() do
			before[d] = true
		end
		local player = MusicPlayer.new({
			parent = SoundService,
			resolveId = function(key)
				return ids[key] or ""
			end,
			now = function()
				return clock
			end,
		})
		local maxAudible = 0
		local function run(seconds)
			local steps = math.floor(seconds / 0.05 + 0.5)
			for _ = 1, steps do
				clock += 0.05
				Engine.advance(0.05)
				player:step(0.05)
				maxAudible = math.max(maxAudible, #player:audible())
			end
		end
		player:play("Explore", 1, 1)
		run(1.2)
		local audible = player:audible()
		check(#audible == 1 and audible[1].key == "Explore", "one track playing")
		check(math.abs(audible[1].volume - Music.Tracks.Explore.volume) < 0.01, "track at its configured volume")
		local exploreSound = player.channels[1].sound
		player:play("Chase", 1, 1)
		run(0.5)
		local mid = player:audible()
		check(#mid == 2, "crossfade: both tracks audible during the fade")
		-- Equal power: no loudness dip in the middle of the fade.
		local power = 0
		for _, a in mid do
			local base = Music.Tracks[a.key].volume
			power += (a.volume / base) ^ 2
		end
		check(power > 0.9 and power < 1.1, string.format("equal-power crossfade: constant loudness (%.2f)", power))
		run(3)
		audible = player:audible()
		check(#audible == 1 and audible[1].key == "Chase", "after the fade only the new track remains")
		-- Going back to Explore resumes the same Sound where it was paused.
		player:play("Explore", 1, 1)
		run(1.2)
		check(player:leading() == "Explore" and player.channels[#player.channels].sound == exploreSound, "returning track resumes the same Sound (no restart)")
		check(Engine.soundPosition(exploreSound) > 3, string.format("playback position kept (%.1f s)", Engine.soundPosition(exploreSound)))
		run(1.5)
		-- Rapid requests: never more than two audible tracks.
		player:play("Rift", 1, 1)
		run(0.1)
		player:play("Event.Default", 1, 1)
		run(0.1)
		player:play("Boss.Default.1", 1, 1)
		run(0.1)
		player:play("Explore", 1, 1)
		run(2)
		check(maxAudible <= 2, "never more than two music tracks audible (max " .. maxAudible .. ")")
		check(player:soundCount() <= 1 + Music.Settings.MaxCachedTracks, "paused-track cache is bounded (" .. player:soundCount() .. ")")
		-- Stinger: plays once, throttled, then cleaned up.
		check(player:stinger("Stinger.ChaseStart") == true, "stinger plays")
		check(player:stinger("Stinger.ChaseStart") == false, "stinger throttled")
		run(1)
		check(#player.stingers == 0, "finished stinger destroyed")
		-- Fading to silence parks every track.
		player:play(nil, 1, 1)
		run(1.5)
		check(#player:audible() == 0, "fade to silence")
		player:destroy()
		local leftovers = 0
		for _, d in SoundService:GetChildren() do
			if string.sub(d.Name, 1, 6) == "Music_" and d.Parent ~= nil and not before[d] then
				leftovers += 1
			end
		end
		check(player:soundCount() == 0 and leftovers == 0, "destroy releases every Sound (" .. leftovers .. " left)")
		-- No ids: nothing is ever created.
		local silent = MusicPlayer.new({
			parent = SoundService,
			resolveId = function()
				return ""
			end,
			now = function()
				return clock
			end,
		})
		silent:play("Explore", 1, 1)
		silent:stinger("Stinger.BossIntro")
		check(silent.created == 0 and #silent:audible() == 0, "empty slots create no Sound at all")
		silent:destroy()
	end)

	--------------------------------------------------------------------------
	scenario("V2 Audio: live director (Rift zone, chases, events, boss)", function()
		check(MusicDirector.isRunning(), "MusicDirector started with the client")
		local info = MusicDirector.debugInfo()
		local exploreSound = nil
		for _, d in SoundService:GetChildren() do
			if d.Name == "Music_Explore" then
				exploreSound = d
			end
		end
		check(info.state == "Explore" and info.key == "Explore", "shipped config: exploration music selected (" .. tostring(info.key) .. ")")
		check(#info.audible == 1 and info.audible[1].key == "Explore", "shipped config: exactly one audible music track (" .. #info.audible .. ")")
		check(exploreSound ~= nil and exploreSound.SoundId == CONFIGURED.Explore and exploreSound.Looped, "Explore Sound uses the configured id and loops")

		MusicDirector.debugSetIds(testIds())
		local RelicService = sreq("Services.RelicService")
		local EventService = sreq("Services.EventService")
		local Layout = shared("Layout")
		local maxAudible = 0
		local function wait(seconds)
			local t = 0
			while t < seconds do
				advance(0.1)
				t += 0.1
				maxAudible = math.max(maxAudible, #MusicDirector.debugInfo().audible)
			end
		end
		local function state()
			local s, k = MusicDirector.current()
			return s, k
		end
		local far = Layout.plotCFrame(1).Position + Vector3.new(0, 3, -30)
		ctx.teleport(alice, far)
		Engine.workspace:SetAttribute("EventId", "")
		wait(4)
		local s, k = state()
		check(s == "Explore" and k == "Explore", "exploring: Explore (" .. tostring(s) .. ")")
		check(#MusicDirector.debugInfo().audible == 1, "exactly one main music audible")

		-- Rift zone.
		ctx.teleport(alice, Vector3.new(0, Layout.BasinY + 3, -30))
		wait(1)
		check(state() == "Explore", "not instantly switched on entering the Rift zone")
		wait(2)
		check(state() == "Rift", "Rift music inside the zone")
		ctx.teleport(alice, Vector3.new(0, Layout.GroundY + 3, -80))
		wait(1.5)
		check(state() == "Rift", "hysteresis: still Rift between enter and exit radius")
		ctx.teleport(alice, far)
		wait(5)
		check(state() == "Explore", "leaving the zone returns to Explore")

		-- Victim: one of alice's relics is carried away.
		local victimRelic = RelicService.create({ id = "storm_crystal" }, far + Vector3.new(80, 0, 0))
		RelicService.toCarried(victimRelic, bob.UserId, alice.UserId)
		wait(1)
		s, k = state()
		check(s == "Chase" and k == "Chase", "victim of a theft: chase music (" .. tostring(s) .. ")")
		-- An event starts during the chase: the chase keeps priority.
		EventService.trigger("VoidStorm")
		wait(1)
		check(state() == "Chase", "chase outranks a world event")
		-- Boss attribute (future boss service) outranks everything.
		alice:SetAttribute("MusicBoss", "VoidWarden")
		alice:SetAttribute("MusicBossPhase", 2)
		wait(0.6)
		s, k = state()
		check(s == "Boss" and k == "Boss.VoidWarden.2", "boss fight music wins (" .. tostring(k) .. ")")
		alice:SetAttribute("MusicBoss", nil)
		alice:SetAttribute("MusicBossPhase", nil)
		wait(2.5)
		check(state() == "Chase", "after the boss, back to the ongoing chase")
		-- Chase ends: relic recovered.
		RelicService.vanish(victimRelic, "Returned")
		wait(3)
		check(state() == "Chase", "chase music lingers after the theft ends")
		wait(5)
		s, k = state()
		check(s == "Event" and k == "Event.VoidStorm", "then back to the running event (" .. tostring(k) .. ")")
		Engine.workspace:SetAttribute("EventId", "")
		wait(6)
		check(state() == "Explore", "event over: Explore")

		-- Thief: alice carries a relic stolen from someone else (Legendary = intense).
		local loot = RelicService.create({ id = "cosmic_eye" }, far)
		RelicService.toCarried(loot, alice.UserId, 4242)
		wait(1)
		s, k = state()
		check(s == "Chase" and k == "ChaseIntense", "thief with a Legendary: intense chase (" .. tostring(k) .. ")")
		RelicService.vanish(loot, "Faded")
		wait(9)
		check(state() == "Explore", "thief chase over")

		-- Bystander: a stolen Legendary+ relic carried nearby.
		local passing = RelicService.create({ id = "pocket_planet" }, far + Vector3.new(20, 0, 0))
		RelicService.toCarried(passing, bob.UserId, 4242)
		local commonPassing = RelicService.create({ id = "ember_shard" }, far + Vector3.new(15, 0, 0))
		RelicService.toCarried(commonPassing, bob.UserId, 4242)
		wait(1)
		s, k = state()
		check(s == "Chase" and k == "ChaseIntense", "stolen Mythic carried nearby: chase for bystanders")
		RelicService.moveAnchor(passing, far + Vector3.new(200, 0, 0))
		wait(9)
		check(state() == "Explore", "it went away: no chase for a nearby stolen Common, back to Explore")
		RelicService.vanish(passing, "Faded")
		RelicService.vanish(commonPassing, "Faded")
		wait(1)

		check(maxAudible <= 2, "never more than two music tracks audible during the whole session (max " .. maxAudible .. ")")
		check(MusicDirector.debugInfo().sounds <= 1 + Music.Settings.MaxCachedTracks + 1, "bounded number of music Sounds")

		-- Cleanup: stop releases everything; restart restores the shipped config.
		MusicDirector.stop()
		local leftovers = 0
		for _, d in SoundService:GetChildren() do
			if string.sub(d.Name, 1, 6) == "Music_" then
				leftovers += 1
			end
		end
		check(not MusicDirector.isRunning() and leftovers == 0, "stop() disconnects and destroys every music Sound")
		MusicDirector.debugSetIds(nil)
		MusicDirector.start()
		wait(1)
		info = MusicDirector.debugInfo()
		check(MusicDirector.isRunning() and info.key == "Explore" and info.created == 1 and #info.audible == 1, "restarted with the shipped config (Explore only)")
	end)
end
