--!strict
-- Who is away on a boss expedition right now (V2 phase 6).
--
-- BossService is the only writer. Everyone else only asks questions:
--   * PvP isolation: abilities never affect anyone across the expedition
--     border (Expeditions.canAffect), so nothing outside reaches the arena and
--     nothing inside the arena reaches another fighter;
--   * "Expedition" Sanctuary protection while the owner participates
--     (PlotService.protection);
--   * the arena only allows movement / defence abilities (AbilityService).
--
-- An entry exists from the moment a player is teleported into the arena
-- until they leave it (exit, KO, death, disconnect, end of the fight).

local Types = require(script.Parent.Types)

type Session = Types.Session

local Expeditions = {}

local current: { [Session]: string } = {}

function Expeditions.join(session: Session, expeditionId: string)
	current[session] = expeditionId
end

function Expeditions.leave(session: Session)
	current[session] = nil
end

-- Expedition id of the session, or nil when it is on the island.
function Expeditions.of(session: Session): string?
	return current[session]
end

function Expeditions.isAway(session: Session): boolean
	return current[session] ~= nil
end

-- May an effect from `caster` (ability, trap, trail...) touch `target`?
-- Only between two players on the island: never into, out of or inside an
-- expedition (fighters cannot hinder each other either).
function Expeditions.canAffect(caster: Session, target: Session): boolean
	return current[caster] == nil and current[target] == nil
end

function Expeditions.members(expeditionId: string): { Session }
	local list = {}
	for session, id in current do
		if id == expeditionId then
			table.insert(list, session)
		end
	end
	return list
end

function Expeditions.count(): number
	local n = 0
	for _ in current do
		n += 1
	end
	return n
end

-- Test / shutdown helper.
function Expeditions.clear()
	table.clear(current)
end

return Expeditions
