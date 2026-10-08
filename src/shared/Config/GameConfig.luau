--!strict
-- Every gameplay tunable in one place. Economy curves live in Config/Upgrades,
-- Config/Rarities and Config/Mutations; formulas live in Shared/Economy.

local GameConfig = {
	Version = "2.0.0-phase6.5",

	Player = {
		BaseWalkSpeed = 20,
		StridePerLevel = 1.6,
		JumpHeight = 7.6,
		RespawnDelay = 3,
		SpawnProtection = 4,
		-- Falling below this Y kills instantly (faster than FallenPartsDestroyHeight).
		VoidKillY = -70,
	},

	Rift = {
		Center = Vector3.new(0, 0, 0),
		SpawnInterval = 5.5,
		MaxActive = 6,
		-- Seconds an unclaimed relic floats at the Rift before fading.
		Lifetime = 75,
		-- Seconds before the first relic of the server.
		FirstSpawnDelay = 3,
		ClaimDistance = 14,
		-- Rarities at or above this always emerge at the central Apex spot.
		ApexRarity = "Legendary",
	},

	Carry = {
		BaseCapacity = 1,
		-- Dropped Rift relics fade back into the Rift after this many seconds.
		DropLifetime = 18,
		-- A dropped stolen relic flies home after this many seconds untouched.
		StolenDropReturn = 12,
		-- Thieves must secure a stolen relic within this window.
		StolenMaxCarry = 100,
		DepositCheckInterval = 0.15,
		GrabDistance = 12,
	},

	Steal = {
		Cooldown = 40,
		MaxDistance = 13,
		-- Victim sanctuary is shielded for this long after a successful theft.
		AegisDuration = 90,
		-- New players cannot be robbed during their first minutes of playtime.
		NoviceSeconds = 8 * 60,
		-- Victims must keep at least this many relics; they cannot be robbed below it.
		MinPlacedToBeRobbed = 3,
		PairLimit = 2,
		PairWindow = 600,
		VictimLimit = 3,
		VictimWindow = 900,
		-- Players without any server-observed activity for this long are "Resting" (protected).
		AfkSeconds = 150,
	},

	-- Ability tuning (catalogue, unlocks and harmonies: Config/Abilities).
	-- Every value is enforced by the server; clients only predict with it.
	Abilities = {
		-- Mobility ------------------------------------------------------------
		Dash = {
			Cooldown = 3.2,
			Speed = 82,
			Duration = 0.18,
			-- Movement guard allowance after a dash (studs/s, seconds) instead
			-- of the V1 blanket grace window.
			GuardSpeed = 160,
			GuardTime = 0.6,
		},
		Blink = {
			Cooldown = 6,
			-- Short teleport, never through geometry (server raycasts).
			Range = 16,
			-- Range multiplier while carrying a relic.
			CarryFactor = 0.5,
			-- Visible wind-up; a stun or root during it cancels the blink.
			Windup = 0.3,
			-- Shorter than this = blocked (no cooldown spent).
			MinDistance = 3,
			-- Distance kept from the wall that stopped the blink.
			WallMargin = 1.8,
			-- Highest drop allowed at the destination (no blinking into the void).
			MaxDrop = 14,
			-- Free space needed above the destination ground.
			Headroom = 5.5,
			-- Step used to walk the destination back from a wall / ledge.
			Step = 1.5,
		},
		Grapple = {
			Cooldown = 9,
			-- Only towards the prepared anchors (WorldFeatures.GrapplePoints).
			Range = 45,
			-- Extra range the server forgives (latency between aim and request).
			RangeLenience = 3,
			MinDistance = 8,
			-- Pull speed (studs/s): below Security.MaxHorizontalSpeed on purpose.
			Speed = 80,
			CarryFactor = 0.8,
			ArriveDistance = 5,
			-- Flight time = distance / speed + ExtraTime.
			ExtraTime = 0.6,
			-- Upward hop on arrival so the player lands on the ledge.
			Hop = 38,
		},
		-- Control -------------------------------------------------------------
		Pulse = {
			Cooldown = 7,
			Radius = 12,
			Knockback = 62,
			Lift = 28,
			Stun = 0.6,
			-- Post-hit immunity (anti stun-lock) is GameConfig.Status.SteadyTime.
		},
		FrostWave = {
			Cooldown = 9,
			Radius = 14,
			-- A slow (never a knockback, never a relic drop).
			Slow = 0.4,
			SlowDuration = 2.5,
		},
		RuneTrap = {
			Cooldown = 12,
			-- Delay before the trap can trigger (visible arming).
			ArmTime = 1,
			TriggerRadius = 4.5,
			Slow = 0.6,
			SlowDuration = 2,
			Lifetime = 45,
			-- The trap is placed on the ground under the caster (no client position).
			MaxGroundDrop = 8,
			-- Visual diameter (studs).
			Size = 9,
		},
		-- Utility -------------------------------------------------------------
		Shield = {
			Cooldown = 16,
			-- Blocks hard control (stun, root, knockback and the relic drop of
			-- Pulse) for this long. Slows still apply; nothing else is blocked.
			Duration = 2,
			-- Mobility trade-off: the bearer is slowed while shielded.
			SelfSlow = 0.2,
		},
		Decoy = {
			Cooldown = 15,
			Duration = 4,
			-- The decoy runs ahead at the owner's current walk speed.
			MaxLength = 60,
			MinSpeed = 10,
			-- Popped by any control ability (or trap) reaching it.
			PopRadius = 3,
		},
		Phase = {
			Cooldown = 14,
			-- Pass through other players (never through walls or the map).
			Duration = 1.5,
		},
	},

	-- Relic harmonies: owning one of these relics on a pedestal of your own
	-- Sanctuary changes one ability (Config/Abilities.Harmonies).
	Harmonies = {
		-- Storm Crystal -> Dash leaves a static trail that briefly slows.
		StormTrail = { Duration = 1.6, HalfWidth = 3, Slow = 0.25, SlowDuration = 1.5, MaxLength = 18, Sample = 0.25 },
		-- Void Cube -> longer Blink, smaller penalty while carrying.
		VoidBlink = { Range = 20, CarryFactor = 0.75 },
		-- Magma Heart -> Pulse becomes Eruption: telegraphed, bigger, slower.
		Eruption = { Cooldown = 10, Radius = 15, Knockback = 78, Lift = 34, Stun = 0.8, Windup = 0.35 },
		-- Frost Lotus -> stronger Frost Wave (still within the slow caps).
		FrostLotus = { Radius = 16, Slow = 0.5, SlowDuration = 3 },
		-- Chrono Glass -> Utility cooldowns x0.85.
		ChronoGlass = { CooldownFactor = 0.85 },
		-- Cosmic Eye -> reveals decoys and phasing players nearby; your
		-- control abilities end their Spectral Phase.
		CosmicEye = { RevealRadius = 45, TouchPopRadius = 4 },
	},

	-- Crowd-control rules enforced by Shared/Status + StatusService.
	Status = {
		-- After any hard control (stun, root, knockback) the target is "steady":
		-- immune to new hard control for max(SteadyTime, duration + SteadyGap).
		SteadyTime = 2.5,
		SteadyGap = 1,
		-- Hard control never lasts longer than this, whatever the source asks.
		MaxHardDuration = 2,
		-- Slows never stack (strongest wins) and are capped.
		MaxSlow = 0.6,
		MaxSlowDuration = 3,
		-- Self buffs (shield, phase) are capped too.
		MaxBuffDuration = 4,
	},

	Sanctuary = {
		Count = 8,
		Radius = 36,
		StartPedestals = 3,
		-- Max pedestals available at each tier (index = tier).
		TierMaxPedestals = { 5, 7, 9, 11, 12 },
		SealDuration = { 20, 24, 28, 32, 36 },
		SealCooldown = 110,
		CollectRadius = 7,
	},

	Economy = {
		-- Core storage cap per tier. Essence stops accumulating when full.
		CoreCapacity = { 600, 3500, 20000, 120000, 700000 },
		-- Core also always holds at least this many seconds of production.
		CoreMinSeconds = 300,
		OfflineRate = 0.5,
		OfflineMaxSeconds = 8 * 3600,
		-- Dissolving a relic refunds this many seconds of its production.
		DissolveSeconds = 40,
		MaxRelicLevel = 5,
		-- Production multiplier added per extra level (level 5 = x3.4).
		LevelBonus = 0.6,
		ResonancePerLevel = 0.15,
		DexBonusPerRelic = 0.02,
		DexBonusPerMutation = 0.01,
		-- Essence placed in the Core the first time a player deposits a relic.
		FirstDepositGift = 40,
	},

	Events = {
		FirstDelay = 150,
		IntervalMin = 240,
		IntervalMax = 360,
	},

	Data = {
		StoreName = "RiftHeist_Player_v1",
		-- Bump together with a MIGRATIONS entry in Server/Core/DataSchema.
		-- History: 1 = launch (V1), 2 = abilities loadout + Power record (V2 phase 1),
		-- 3 = harmony toggles (V2 phase 4), 4 = cosmetics inventory (V2 phase 5),
		-- 5 = boss Codex + materials + trophy pedestals (V2 phase 6),
		-- 6 = boss weapons inventory (V2 phase 6.5).
		SchemaVersion = 6,
		AutosaveInterval = 90,
		MaxRetries = 5,
		-- A session lock older than this is considered abandoned (crashed server).
		LockTimeout = 600,
	},

	-- Static world budgets (checked by the tests; mobile-first).
	World = {
		-- BaseParts in the built world with tier-1 Sanctuaries (excl. relics/characters).
		PartBudget = 4500,
		LightBudget = 130,
		EmitterBudget = 48,
	},

	Sync = {
		-- Hot state (Essence, cooldowns, carrying, status, Power) is pushed at most this often.
		HotInterval = 0.1,
		-- Cold state (Dex, upgrades, loadout, settings...) is pushed only when marked
		-- changed; this audit re-checks it in case a change was never marked.
		ColdAuditInterval = 2,
	},

	Security = {
		-- Horizontal studs/second allowed before the movement guard intervenes.
		MaxHorizontalSpeed = 120,
		MovementCheckInterval = 0.5,
	},
}

return GameConfig
