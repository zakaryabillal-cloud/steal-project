--!strict
-- Crafting materials (V2 phase 6). Earned from bosses only, stored in the
-- player's save (`materials`), never stolen, never sold.
--
-- The Forge (a later phase) will turn them into guaranteed boss relics and
-- upgrades. Nothing consumes them yet except the material requirements that
-- abilities may declare (Config/Abilities `unlock.materials`, none today).
-- The planned recipes are documented here so the economy stays coherent:
--   Forge.Recipes (planned): 30 void_shard -> 1 guaranteed void_duster;
--                            1 void_catalyst + 10 void_shard -> +1 level on a boss relic.

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
}

local byId: { [string]: MaterialDef } = {}
for _, def in list do
	assert(byId[def.id] == nil, "duplicate material " .. def.id)
	byId[def.id] = def
end

Materials.list = list
Materials.byId = byId

-- Planned Forge recipes (documentation + tests; no Forge logic yet).
Materials.PlannedRecipes = table.freeze({
	{ output = "relic:void_duster", inputs = { void_shard = 30 } },
	{ output = "level:boss_relic", inputs = { void_catalyst = 1, void_shard = 10 } },
})

function Materials.get(id: any): MaterialDef?
	if type(id) ~= "string" then
		return nil
	end
	return byId[id]
end

return Materials
