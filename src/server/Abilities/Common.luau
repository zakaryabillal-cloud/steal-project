--!strict
-- Shared server helpers for ability modules: world raycasts, ground and line
-- of sight checks, target selection, sanitising client directions, and the
-- harmonies that react to a control hit (Cosmic Eye).
--
-- Every geometry question an ability asks is answered here, on the server,
-- from the server's own view of the world: a client never supplies a
-- position, only (at most) a direction or an anchor index.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Layout = require(Shared.Layout)
local Abilities = require(Shared.Config.Abilities)

local Core = script.Parent.Parent.Core
local Types = require(Core.Types)
local Sessions = require(Core.Sessions)
local Services = script.Parent.Parent.Services
local PlotService = require(Services.PlotService)
local StatusService = require(Services.StatusService)
local CharacterService = require(Services.CharacterService)

type Session = Types.Session

local Common = {}

-- Folder holding server-side ability objects (rune traps).
function Common.folder(): Folder
	local folder = workspace:FindFirstChild("Abilities")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Abilities"
		folder.Parent = workspace
	end
	return folder :: Folder
end

-- Raycast parameters for gameplay geometry: characters, relic anchors,
-- ability objects and grapple anchors never block; non-colliding parts and
-- water never block; the caster's own collision group is respected (their
-- own Sanctuary barrier never blocks them).
function Common.params(session: Session?): RaycastParams
	local filter: { Instance } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(filter, player.Character)
		end
	end
	for _, name in { "Relics", "Abilities" } do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(filter, folder)
		end
	end
	local world = workspace:FindFirstChild("World")
	local anchors = world and world:FindFirstChild("GrapplePoints")
	if anchors then
		table.insert(filter, anchors)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = filter
	params.IgnoreWater = true
	params.RespectCanCollide = true
	params.CollisionGroup = if session then CharacterService.groupFor(session) else "Default"
	return params
end

function Common.cast(origin: Vector3, vector: Vector3, params: RaycastParams): RaycastResult?
	if vector.Magnitude < 1e-4 then
		return nil
	end
	return workspace:Raycast(origin, vector, params)
end

-- True when nothing blocks the straight segment a -> b.
function Common.clear(a: Vector3, b: Vector3, params: RaycastParams): boolean
	return Common.cast(a, b - a, params) == nil
end

-- Ground under `position` within `maxDrop` studs (searching from 1 stud above).
function Common.ground(position: Vector3, maxDrop: number, params: RaycastParams): RaycastResult?
	local result = Common.cast(position + Vector3.new(0, 1, 0), Vector3.new(0, -(maxDrop + 1), 0), params)
	if result and result.Normal.Y > 0.35 then
		return result
	end
	return nil
end

function Common.flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function finite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

-- Client direction payload -> horizontal unit vector, or nil when unusable.
-- Whatever the client sends (even a far "destination") is only ever used as
-- a direction: the server computes every position itself.
function Common.readDirection(raw: any): Vector3?
	if typeof(raw) ~= "Vector3" then
		return nil
	end
	local v = raw :: Vector3
	if not finite(v.X) or not finite(v.Y) or not finite(v.Z) then
		return nil
	end
	local flat = Common.flat(v)
	local length = flat.Magnitude
	if length < 1e-3 or not finite(length) then
		return nil
	end
	return flat / length
end

-- Horizontal facing of a root part.
function Common.facing(root: BasePart): Vector3
	local look = Common.flat(root.CFrame.LookVector)
	return if look.Magnitude > 1e-3 then look.Unit else Vector3.new(0, 0, -1)
end

function Common.isCarrying(session: Session): boolean
	return #session.carrying > 0
end

-- Is `position` inside (or right against) a Sealed Sanctuary that is not
-- `session`'s? Seal barriers are not queryable, so abilities that move a
-- player check this explicitly: no blinking into a sealed Sanctuary.
function Common.sealedAgainst(session: Session, position: Vector3): boolean
	local t = workspace:GetServerTimeNow()
	for _, plot in PlotService.all() do
		if plot.sealedUntil > t and plot.owner ~= session then
			local rel = plot.origin:PointToObjectSpace(position)
			local horizontal = math.sqrt(rel.X * rel.X + rel.Z * rel.Z)
			if horizontal <= Layout.PlatformRadius + 2.5 and rel.Y > -8 and rel.Y < Layout.PlatformRadius + 6 then
				return true
			end
		end
	end
	return false
end

-- Root of the session's live character.
function Common.root(session: Session): BasePart?
	local _, _, root = Sessions.character(session)
	return root
end

-- Unobstructed line from a to b (chest heights), ignoring characters.
function Common.lineOfSight(a: Vector3, b: Vector3, params: RaycastParams): boolean
	return Common.clear(a, b, params)
end

export type Target = { session: Session, root: BasePart, offset: Vector3 }

-- Other live players within `radius` of `origin` (optionally in sight).
function Common.targets(caster: Session, origin: Vector3, radius: number, needSight: boolean): { Target }
	local list: { Target } = {}
	local params = if needSight then Common.params(caster) else nil
	for _, target in Sessions.all() do
		if target == caster then
			continue
		end
		local root = Common.root(target)
		if not root then
			continue
		end
		local offset = root.Position - origin
		if offset.Magnitude > radius then
			continue
		end
		if params and not Common.lineOfSight(origin, root.Position, params) then
			continue
		end
		table.insert(list, { session = target, root = root, offset = offset })
	end
	return list
end

-- Is the harmony of `relicId` active for `session` (relic displayed, not switched off)?
function Common.hasHarmony(session: Session, relicId: string): boolean
	return Abilities.activeHarmonies(session.harmonyRelics, session.data.abilities.harmonyOff)[relicId] == true
end

-- A control effect from `caster` reached `target`: Cosmic Eye holders end a
-- Spectral Phase (their counterplay). `cosmicEye` = caster has the harmony.
function Common.onControlHit(cosmicEye: boolean, target: Session)
	if cosmicEye and StatusService.isPhased(target) then
		StatusService.endBuff(target, "phase")
	end
end

return Common
