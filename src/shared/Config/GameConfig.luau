--!strict
-- Every gameplay tunable in one place. Economy curves live in Config/Upgrades,
-- Config/Rarities and Config/Mutations; formulas live in Shared/Economy.

local GameConfig = {
	Version = "2.0.0-phase1",

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

	Abilities = {
		Dash = {
			Cooldown = 3.2,
			Speed = 82,
			Duration = 0.18,
		},
		Pulse = {
			Cooldown = 7,
			Radius = 12,
			Knockback = 62,
			Lift = 28,
			Stun = 0.6,
			-- Post-hit immunity (anti stun-lock) is GameConfig.Status.SteadyTime.
		},
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
		-- History: 1 = launch (V1), 2 = abilities loadout + Power record (V2 phase 1).
		SchemaVersion = 2,
		AutosaveInterval = 90,
		MaxRetries = 5,
		-- A session lock older than this is considered abandoned (crashed server).
		LockTimeout = 600,
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
