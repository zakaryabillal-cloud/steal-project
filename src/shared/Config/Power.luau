--!strict
-- Power Level coefficients (formula in Shared/Power).
--
-- Power summarises a player's overall progression. It is NOT a currency: it is
-- never spent, it never affects PvP, and content unlocks use the player's
-- record ("peak") Power so a theft can never re-lock content.
--
-- Rarity weights grow ~x1.7 per tier (Essence grows ~x3) so a single Secret
-- relic does not dwarf a well-built collection.

local Power = {
	Rarity = {
		Common = 10,
		Uncommon = 17,
		Rare = 29,
		Epic = 49,
		Legendary = 84,
		Mythic = 143,
		Secret = 243,
	} :: { [string]: number },

	-- Each relic level above 1 adds this fraction of the relic's base Power.
	PerLevel = 0.3,

	Mutation = {
		Charged = 1.2,
		Golden = 1.3,
		Void = 1.45,
		Corrupted = 1.6,
		Prismatic = 1.8,
	} :: { [string]: number },

	-- Flat bonus per Sanctuary tier (index = tier).
	Tier = { 0, 50, 150, 350, 700 },

	-- RiftDex completion.
	PerRelicDiscovered = 3,
	PerMutationDiscovered = 2,

	-- Resonance (production) upgrade levels.
	PerResonanceLevel = 8,

	-- Sanity bound used when loading saves.
	MaxPeak = 1e7,
}

return Power
