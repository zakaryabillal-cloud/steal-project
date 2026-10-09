--!strict
-- Crafting materials (V2 phase 6). Earned from bosses only, stored in the
-- player's save (`materials`), never stolen, never sold.
--
-- The Forge (a later phase) will turn them into guaranteed boss relics and
-- upgrades. Nothing consumes them yet except the material requirements that
-- abilities may declare (Config/Abilities `unlock.materials`, none today).
-- The planned recipes are documented here so the economy stays coherent:
--   Forge.Recipes (planned): 30 void_shard -> 1 guaranteed void_duster;
--                            1 void_catalyst + 10 void_shard -> +1 level on a boss relic;
--                            30 magma_shard -> 1 guaranteed ember_anvil (phase 7A);
--                            1 ember_core + 10 magma_shard -> +1 level on a boss relic;
--                            30 storm_shard -> 1 guaranteed zigzag_crown (phase 7B);
--                            1 thunder_core + 10 storm_shard -> +1 level on a boss relic.

export type MaterialDef = {
	id: string,
	-- Display order (inventory, Codex).
	order: number,
	rarity: string,
	color: Color3,
	-- Config/Emoji glyph name.
	emoji: string,
	-- Boss that drops it (Codex).
	source: string,
	-- Sanity bound used when loading saves.
	max: number,
}

local Materials = {}

local list: { MaterialDef } = {
	{ id = "void_shard", order = 1, rarity = "Rare", color = Color3.fromRGB(190, 120, 255), emoji = "gem", source = "VoidWarden", max = 1e6 },
	{ id = "void_catalyst", order = 2, rarity = "Epic", color = Color3.fromRGB(255, 120, 220), emoji = "swirl", source = "VoidWarden", max = 1e5 },
	-- Phase 7A: Forgeheart's volcanic materials.
	{ id = "magma_shard", order = 3, rarity = "Rare", color = Color3.fromRGB(255, 130, 50), emoji = "fire", source = "Forgeheart", max = 1e6 },
	{ id = "ember_core", order = 4, rarity = "Epic", color = Color3.fromRGB(255, 214, 72), emoji = "volcano", source = "Forgeheart", max = 1e5 },
	-- Phase 7B: the Tempest Seraph's electric materials ("Éclats de foudre"
	-- and the rare "Noyau de tonnerre" for the Forge).
	{ id = "storm_shard", order = 5, rarity = "Rare", color = Color3.fromRGB(255, 226, 70), emoji = "power", source = "TempestSeraph", max = 1e6 },
	{ id = "thunder_core", order = 6, rarity = "Epic", color = Color3.fromRGB(120, 200, 255), emoji = "comet", source = "TempestSeraph", max = 1e5 },
}

local byId: { [string]: MaterialDef } = {}
for _, def in list do
	assert(byId[def.id] == nil, "duplicate material " .. def.id)
	byId[def.id] = def
end

Materials.list = list
Materials.byId = byId

-- Planned Forge recipes (documentation + tests; no Forge logic yet).
export type Recipe = { output: string, inputs: { [string]: number } }

local recipes: { Recipe } = {
	{ output = "relic:void_duster", inputs = { void_shard = 30 } },
	{ output = "level:boss_relic", inputs = { void_catalyst = 1, void_shard = 10 } },
	{ output = "relic:ember_anvil", inputs = { magma_shard = 30 } },
	{ output = "level:boss_relic", inputs = { ember_core = 1, magma_shard = 10 } },
	{ output = "relic:zigzag_crown", inputs = { storm_shard = 30 } },
	{ output = "level:boss_relic", inputs = { thunder_core = 1, storm_shard = 10 } },
}
Materials.PlannedRecipes = table.freeze(recipes)

function Materials.get(id: any): MaterialDef?
	if type(id) ~= "string" then
		return nil
	end
	return byId[id]
end

return Materials
