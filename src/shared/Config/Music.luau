--!strict
-- MUSIC REGISTRY — every music track and musical stinger of Rift Heist.
--
-- HOW TO ADD YOUR MUSIC
--   1. Upload the audio to Roblox (Creator Hub > Audio) or use audio you are
--      licensed to use in your experience.
--   2. Paste its id in the ASSET_IDS block just below, e.g.
--          Explore = "rbxassetid://123456789",
--      (what each slot should sound like is described in Music.Tracks).
--   3. That's it: the MusicDirector picks it up automatically. A slot whose id
--      is "" is SILENT (no Sound is even created). No id is ever invented here.
--
-- Only ONE main music track is audible at a time: when the state changes the
-- old track fades out while the new one fades in (equal-power crossfade).
-- States, by priority (highest wins):
--     Boss  >  Chase  >  Event  >  Rift (near the Rift)  >  Explore
-- If the winning state has no audio for its slot, the next state down plays
-- instead (Settings.FallThroughWhenSilent), so a missing track never cuts the
-- music the player already had.
--
-- Field guide for each slot:
--   id       filled from ASSET_IDS above ("" = silent)
--   kind     "Loop" (seamless loop, main music) or "OneShot" (stinger)
--   volume   0..1 mix level of this track (the player's Music slider applies on top)
--   mood     the atmosphere the track should convey
--   tempo    recommended tempo
--   length   recommended duration / loop length
--   context  when the game plays it

export type TrackDef = {
	id: string,
	kind: string,
	volume: number,
	mood: string,
	tempo: string,
	length: string,
	context: string,
}

export type StateDef = {
	id: string,
	priority: number,
	-- Condition must hold this long before the state takes over (debounce).
	enterDelay: number,
	-- State is kept this long after its condition ends (natural release).
	hold: number,
	-- Crossfade time when this state's track comes in / goes out.
	fadeIn: number,
	fadeOut: number,
	-- Optional one-shot stinger played when the state starts (if it has an id).
	stinger: string?,
}

local Music = {}

-- ═══════════════════════════════════════════════════════════════════════
--  ASSET_IDS — PASTE YOUR "rbxassetid://..." HERE ("" = silent)
-- ═══════════════════════════════════════════════════════════════════════
local ASSET_IDS: { [string]: string } = {
	-- World
	Explore = "rbxassetid://9046476113",
	Rift = "rbxassetid://9042760875",
	-- Chase
	Chase = "rbxassetid://9046474891",
	ChaseIntense = "rbxassetid://1842546506",
	-- World events
	["Event.Default"] = "",
	["Event.RiftOverload"] = "",
	["Event.VoidStorm"] = "",
	["Event.GoldenSurge"] = "",
	["Event.Eclipse"] = "",
	["Event.CelestialTide"] = "",
	["Event.Starfall"] = "",
	-- Bosses (phase 6)
	["Boss.Default.1"] = "",
	["Boss.Default.2"] = "",
	["Boss.VoidWarden.1"] = "",
	["Boss.VoidWarden.2"] = "",
	["Boss.VoidWarden.3"] = "",
	["Boss.Forgeheart.1"] = "",
	["Boss.Forgeheart.2"] = "",
	["Boss.TempestSeraph.1"] = "",
	["Boss.TempestSeraph.2"] = "",
	["Boss.EclipseOracle.1"] = "",
	["Boss.EclipseOracle.2"] = "",
	-- Stingers (one-shots)
	["Stinger.ChaseStart"] = "rbxassetid://9044615289",
	["Stinger.BossIntro"] = "",
	["Stinger.BossVictory"] = "",
	["Stinger.BossDefeat"] = "",
}

local function loop(volume: number, mood: string, tempo: string, length: string, context: string): TrackDef
	return { id = "", kind = "Loop", volume = volume, mood = mood, tempo = tempo, length = length, context = context }
end

local function oneShot(volume: number, mood: string, length: string, context: string): TrackDef
	return { id = "", kind = "OneShot", volume = volume, mood = mood, tempo = "-", length = length, context = context }
end

Music.Tracks = {
	--------------------------------------------------------------------------
	-- Exploration & world
	--------------------------------------------------------------------------
	Explore = loop(0.5,
		"Main theme. Calm, dreamy cosmic fantasy: soft synth pads, celesta/harp arpeggios, light percussion. Curious, never sleepy.",
		"80-100 BPM", "2-4 min seamless loop",
		"Default music anywhere on the island when nothing more important is happening."),
	Rift = loop(0.55,
		"Near THE RIFT: mysterious and magnetic. Deeper drones, shimmering choir 'aahs', reversed textures, a slow pulse that hints at power.",
		"70-90 BPM (or free-time)", "1.5-3 min seamless loop",
		"Player within ~70 studs of the Rift (leaves past ~88 studs)."),

	--------------------------------------------------------------------------
	-- Chase
	--------------------------------------------------------------------------
	Chase = loop(0.6,
		"Heist/chase: urgent and playful. Driving drums, staccato strings/synth bass, rising tension. Fun, not horror.",
		"130-150 BPM", "1-2 min seamless loop",
		"Local player is carrying a stolen relic (thief), one of their relics is being carried away (victim)."),
	ChaseIntense = loop(0.65,
		"High-stakes version of the chase for Legendary+ relics: bigger percussion, brass/choir hits, epic but still playful.",
		"140-160 BPM", "1-2 min seamless loop",
		"Chase involving a Legendary, Mythic or Secret relic, or a stolen Legendary+ relic carried near the player. Falls back to Chase when empty."),

	--------------------------------------------------------------------------
	-- World events (one slot per event; Event.Default is the fallback)
	--------------------------------------------------------------------------
	["Event.Default"] = loop(0.55,
		"Generic world-event music: energetic, magical, 'something is happening'.",
		"110-130 BPM", "1.5-2 min seamless loop",
		"Any world event whose own slot is empty."),
	["Event.RiftOverload"] = loop(0.6,
		"Electric surge: arpeggiated synths, crackling energy, euphoric build.",
		"120-135 BPM", "60 s+ loop (event lasts 60 s)",
		"RIFT OVERLOAD event (relics spawn much faster)."),
	["Event.VoidStorm"] = loop(0.6,
		"Dark storm: heavy low strings, wind textures, ominous choir, thunder hits.",
		"90-110 BPM", "75 s+ loop (event lasts 75 s)",
		"VOID STORM event."),
	["Event.GoldenSurge"] = loop(0.6,
		"Golden fortune: bright brass and bells, triumphant and treasure-hunt-like.",
		"110-125 BPM", "75 s+ loop (event lasts 75 s)",
		"GOLDEN SURGE event."),
	["Event.Eclipse"] = loop(0.6,
		"Eclipse: eerie and sacred, low drones, sparse bells, slow tension.",
		"60-80 BPM", "90 s+ loop (event lasts 90 s)",
		"ECLIPSE event."),
	-- Prepared for the V2 events (phase 7): silent until both the event and its music exist.
	["Event.CelestialTide"] = loop(0.6,
		"Celestial tide: flowing, oceanic, wide reverb, rising swells.",
		"90-110 BPM", "60-90 s loop",
		"Future CELESTIAL TIDE event (the river rises)."),
	["Event.Starfall"] = loop(0.6,
		"Starfall: countdown tension then rush, racing arpeggios.",
		"130-150 BPM", "60 s loop",
		"Future STARFALL event (meteor race)."),

	--------------------------------------------------------------------------
	-- Bosses (phase 6): Boss.<BossId>.<phase>. Phase 1 is the fallback for
	-- later phases of the same boss; Boss.Default.<phase> for unknown bosses.
	--------------------------------------------------------------------------
	["Boss.Default.1"] = loop(0.7, "Generic boss fight: epic, rhythmic, readable (telegraphs must stay audible).", "120-140 BPM", "1.5-3 min loop", "Any boss without its own music."),
	["Boss.Default.2"] = loop(0.72, "Generic boss, final phase: more intense layer of Boss.Default.1.", "same as phase 1", "1.5-3 min loop", "Any boss in its last phase."),
	["Boss.VoidWarden.1"] = loop(0.7, "VOID WARDEN: dark, heavy, pulsating void synths and taiko.", "110-125 BPM", "2-3 min loop", "Void Warden, phase 1 (100-50 % HP)."),
	["Boss.VoidWarden.2"] = loop(0.72, "VOID WARDEN collapsing arena: faster, distorted, alarm-like.", "125-140 BPM", "1.5-2 min loop", "Void Warden, phase 2 (50-20 % HP, platforms fall)."),
	["Boss.VoidWarden.3"] = loop(0.75, "VOID WARDEN enraged: maximum intensity.", "140+ BPM", "1-2 min loop", "Void Warden, enrage (< 20 % HP)."),
	["Boss.Forgeheart.1"] = loop(0.7, "FORGEHEART: industrial, anvils, slow heavy groove, brass.", "90-105 BPM", "2-3 min loop", "Forgeheart, phase 1."),
	["Boss.Forgeheart.2"] = loop(0.72, "FORGEHEART with rising lava: urgent percussion, choir.", "110-125 BPM", "1.5-2 min loop", "Forgeheart, phase 2 (lava rises)."),
	["Boss.TempestSeraph.1"] = loop(0.7, "TEMPEST SERAPH: airy, fast strings, wind, soaring melody.", "140-160 BPM", "2-3 min loop", "Tempest Seraph, phase 1."),
	["Boss.TempestSeraph.2"] = loop(0.72, "TEMPEST SERAPH grounded fight: thunderous drums, triumphant.", "150-170 BPM", "1.5-2 min loop", "Tempest Seraph, phase 2."),
	["Boss.EclipseOracle.1"] = loop(0.7, "ECLIPSE ORACLE (secret): mystical, ritual chants, odd meter.", "90-120 BPM", "2-3 min loop", "Secret Eclipse boss, phase 1."),
	["Boss.EclipseOracle.2"] = loop(0.72, "ECLIPSE ORACLE revealed: overwhelming, dissonant choir.", "120-140 BPM", "1.5-2 min loop", "Secret Eclipse boss, phase 2."),

	--------------------------------------------------------------------------
	-- Musical stingers (one-shots, played over the transition)
	--------------------------------------------------------------------------
	["Stinger.ChaseStart"] = oneShot(0.6, "Short heist hit: 'dun-dun!' with a riser.", "1-2 s", "A chase begins."),
	["Stinger.BossIntro"] = oneShot(0.7, "Boss reveal: big impact + choir swell.", "3-5 s", "A boss fight begins."),
	["Stinger.BossVictory"] = oneShot(0.7, "Victory fanfare.", "4-6 s", "Boss defeated (phase 6)."),
	["Stinger.BossDefeat"] = oneShot(0.6, "Defeat sting, soft and not punishing.", "2-4 s", "Party wiped / time out (phase 6)."),
} :: { [string]: TrackDef }

-- Apply ASSET_IDS (every slot must appear in both tables).
for key, id in ASSET_IDS do
	local track = Music.Tracks[key]
	assert(track, "ASSET_IDS has an unknown music slot: " .. key)
	track.id = id
end
for key in Music.Tracks do
	assert(ASSET_IDS[key] ~= nil, "music slot missing from ASSET_IDS: " .. key)
end

-- Music states in priority order (highest first).
Music.States = {
	{ id = "Boss", priority = 5, enterDelay = 0, hold = 1.5, fadeIn = 1.2, fadeOut = 2.5, stinger = "Stinger.BossIntro" },
	{ id = "Chase", priority = 4, enterDelay = 0.3, hold = 6, fadeIn = 0.8, fadeOut = 3, stinger = "Stinger.ChaseStart" },
	{ id = "Event", priority = 3, enterDelay = 0.5, hold = 2, fadeIn = 2.5, fadeOut = 3 },
	{ id = "Rift", priority = 2, enterDelay = 1.5, hold = 3, fadeIn = 3, fadeOut = 3 },
	{ id = "Explore", priority = 1, enterDelay = 0, hold = 0, fadeIn = 3, fadeOut = 3 },
} :: { StateDef }

Music.Settings = {
	-- How often the world is sampled (seconds). Fades update every frame.
	SenseInterval = 0.25,
	-- Minimum time between two changes toward a LOWER priority state.
	-- (A higher-priority state always takes over immediately.)
	MinSwitchInterval = 2.5,
	-- Minimum time between two track changes inside the same state
	-- (e.g. Chase -> ChaseIntense); boss phase changes are immediate.
	MinTrackChangeInterval = 1,
	-- When the winning state has no audio, play the next state down.
	FallThroughWhenSilent = true,
	-- A paused track resumes where it left off if it returns within this window.
	ResumeWindow = 90,
	-- At most this many paused tracks are kept for resuming (memory).
	MaxCachedTracks = 3,
	-- Same stinger never repeats faster than this.
	StingerCooldown = 10,
	-- Rift zone with hysteresis (horizontal distance to the Rift).
	RiftEnterRadius = 70,
	RiftExitRadius = 88,
	-- A stolen relic of at least this rarity carried within this radius
	-- triggers the chase music for bystanders too.
	NearbyChaseRadius = 70,
	NearbyChaseRarity = "Legendary",
	IntenseRarity = "Legendary",
}

-- Known boss ids (phase 6 will add their gameplay). Used to document slots.
Music.Bosses = { "VoidWarden", "Forgeheart", "TempestSeraph", "EclipseOracle" }

function Music.track(key: string): TrackDef?
	return Music.Tracks[key]
end

function Music.state(id: string): StateDef?
	for _, def in Music.States do
		if def.id == id then
			return def
		end
	end
	return nil
end

-- Ordered candidate slots for a state; the first one with an id plays.
function Music.candidates(stateId: string, params: { [string]: any }?): { string }
	local p: { [string]: any } = params or {}
	if stateId == "Boss" then
		local boss = tostring(p.boss or "Default")
		local phase = math.max(1, math.floor(tonumber(p.phase) or 1))
		local list = {}
		for k = phase, 1, -1 do
			table.insert(list, string.format("Boss.%s.%d", boss, k))
		end
		for k = math.min(phase, 2), 1, -1 do
			table.insert(list, string.format("Boss.Default.%d", k))
		end
		return list
	elseif stateId == "Chase" then
		return if p.intense then { "ChaseIntense", "Chase" } else { "Chase" }
	elseif stateId == "Event" then
		return { "Event." .. tostring(p.event or "Default"), "Event.Default" }
	elseif stateId == "Rift" then
		return { "Rift" }
	end
	return { "Explore" }
end

return Music
