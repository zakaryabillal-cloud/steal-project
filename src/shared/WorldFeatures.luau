--!strict
-- V2 world layout: the outer crown and every point of interest added around
-- the V1 core (Rift basin, meadow, river, ring road, Sanctuaries at r=172).
-- Shared by the world builders (server), clients (future grapple/boss UI)
-- and the tests (route accessibility, budgets).
--
--   Angles are degrees in the XZ plane (0 = +X, 90 = +Z), like Layout.plotAngle.
--   Sanctuaries sit at -90, -45, 0, 45, 90, 135, 180, 225; the ridges between
--   them at 22.5 + 45k. The V2 features use those ridges and the new outer
--   crown (r ~206-276) so the Rift -> Sanctuary trip is NOT longer than in V1.
--
--   Top view (not to scale):
--                      Observatory (112.5, on the High Ledge)
--          Broken Arch (202.5)   Ledge 72..208   Sky Route (157.5)
--      Cave B (247.5)  ·  S8  S7  S6  S5  ·  Cave A (67.5)
--                      ·    RIFT  ·
--      Boss Plateau (292.5)  S1  S2  S3  S4   Ruins (337.5, 67.5, 247.5)

local Layout = require(script.Parent.Layout)

local WorldFeatures = {}

local function polar(deg: number, r: number, y: number): Vector3
	local a = math.rad(deg)
	return Vector3.new(math.cos(a) * r, y, math.sin(a) * r)
end
WorldFeatures.polar = polar

-- Outer crown: rolling upland behind the Sanctuaries with a loop trail.
WorldFeatures.Crown = {
	-- The ground starts rising here (just behind the Sanctuary platforms)...
	riseFrom = 212,
	riseTo = 234,
	-- ...to about this height above GroundY.
	height = 7,
	trailRadius = 240,
	trailHalfWidth = 4.5,
	-- Where the trail bends toward the ledge lip to pass a landmark.
	detours = {
		{ deg = 112.5, halfWidth = 16, r = 233 },
	},
}

-- Trail radius at an angle (degrees), including detours.
function WorldFeatures.trailRadiusAt(deg: number): number
	local crown = WorldFeatures.Crown
	local r = crown.trailRadius
	for _, detour in crown.detours do
		local d = math.abs(((deg - detour.deg + 180) % 360) - 180)
		if d < detour.halfWidth then
			local t = 1 - d / detour.halfWidth
			local w = t * t * (3 - 2 * t)
			r = r + (detour.r - r) * w
		end
	end
	return r
end

-- High Ledge ("corniche haute"): a raised shelf behind Sanctuaries 5-7.
-- Angular ends ramp up gently (they ARE the access ramps); the inner side is a
-- cliff you can only drop from (or bounce/grapple up).
WorldFeatures.Ledge = {
	from = 72,
	to = 208,
	-- Degrees over which each end ramps from the crown up to the top.
	ramp = 18,
	inner = 228,
	outer = 268,
	top = Layout.GroundY + 26,
}

-- Ruined passes on the ridges between Sanctuaries: the ridge is lowered into a
-- walkable saddle full of cover (lateral shortcut between neighbours).
WorldFeatures.RuinPasses = { 67.5, 247.5, 337.5, 22.5 }

-- Caves under the river: Rift meadow -> under the river -> ravine up to a
-- ruined pass. `covered` points are inside the carved tunnel, others are open
-- ravines cut into the heightmap. Floor heights are the walking surface.
export type CavePoint = { deg: number, r: number, floor: number, covered: boolean }
export type Cave = { name: string, points: { CavePoint }, halfWidth: number, height: number }

local function cave(name: string, base: number): Cave
	local g = Layout.GroundY
	return {
		name = name,
		halfWidth = 5,
		-- Clear height inside the tunnel.
		height = 9,
		points = {
			{ deg = base - 37.5, r = 70, floor = g, covered = false },
			{ deg = base - 17, r = 70, floor = g - 11, covered = false },
			{ deg = base - 9, r = 74, floor = g - 17, covered = true },
			{ deg = base - 6, r = 84, floor = g - 24, covered = true },
			{ deg = base - 5.5, r = 95, floor = g - 26, covered = true },
			{ deg = base - 5, r = 108, floor = g - 26, covered = true },
			{ deg = base - 4, r = 120, floor = g - 22, covered = true },
			{ deg = base - 3, r = 128, floor = g - 18, covered = false },
			{ deg = base, r = 162, floor = g + 2, covered = false },
		},
	}
end
WorldFeatures.Caves = { cave("CaveEast", 67.5), cave("CaveWest", 247.5) }

function WorldFeatures.cavePoint(point: CavePoint): Vector3
	return polar(point.deg, point.r, point.floor)
end

-- Sky Route: bounce pad in the meadow -> 4 floating islands joined by narrow
-- rune bridges (no rails: a Pulse here is a fall) -> the High Ledge lip.
export type SkyIsland = { position: Vector3, radius: number }
WorldFeatures.SkyRoute = {
	pad = polar(150, 72, Layout.GroundY),
	islands = {
		{ position = polar(155, 100, 36), radius = 8 },
		{ position = polar(157.5, 132, 41), radius = 7 },
		{ position = polar(160, 165, 47), radius = 7 },
		{ position = polar(157.5, 198, 50), radius = 7.5 },
	} :: { SkyIsland },
	-- Last bridge lands on the ledge lip.
	landing = polar(157.5, 232, Layout.GroundY + 26),
	bridgeWidth = 3,
}

-- Bounce pads from the back alleys up to the High Ledge.
export type Pad = { position: Vector3, target: Vector3 }
WorldFeatures.LedgePads = {
	{ position = polar(100, 216, Layout.GroundY), target = polar(100, 240, Layout.GroundY + 26) },
	{ position = polar(186, 216, Layout.GroundY), target = polar(186, 240, Layout.GroundY + 26) },
} :: { Pad }

-- Landmarks (90 degrees apart around the crown so one is always in view).
WorldFeatures.Observatory = {
	position = polar(112.5, 252, Layout.GroundY + 26),
	-- Viewing balcony (reached by the outer stair) and the roof.
	balconyY = Layout.GroundY + 26 + 30,
	topY = Layout.GroundY + 26 + 64,
}

-- A broken gateway spanning the ledge cliff, over the trail: the inner leg
-- stands in the back alley, the outer foot on the ledge. Angles along the
-- arch run 0 (inner springing) -> 180 (outer springing); the stretch
-- [gapFrom, gapTo] has collapsed.
WorldFeatures.BrokenArch = {
	deg = 202.5,
	inner = 222,
	outer = 258,
	springY = Layout.GroundY + 26,
	gapFrom = 30,
	gapTo = 62,
}

-- Boss plateau: a promontory beyond the island edge with the (dormant) portal.
WorldFeatures.BossPlateau = {
	deg = 292.5,
	neckFrom = 238,
	neckTo = 278,
	neckHalfWidth = 11,
	center = 300,
	radius = 25,
	top = Layout.GroundY + 14,
	-- Portal ring stands at the far end, facing the Rift.
	portalR = 314,
	portalRadius = 15,
}

-- Prepared grapple anchors (the Grapple ability comes in a later phase).
export type GrapplePoint = { name: string, position: Vector3, kind: string }
local LT = Layout.GroundY + 26
WorldFeatures.GrapplePoints = {
	{ name = "LedgeLip90", position = polar(90, 226, LT + 4), kind = "Ledge" },
	{ name = "LedgeLip135", position = polar(135, 226, LT + 4), kind = "Ledge" },
	{ name = "LedgeLip180", position = polar(180, 226, LT + 4), kind = "Ledge" },
	{ name = "ObservatoryBalcony", position = polar(112.5, 236, LT + 32), kind = "Tower" },
	{ name = "ObservatoryRoof", position = polar(112.5, 252, LT + 70), kind = "Tower" },
	-- Broken tip of the long half of the arch (angle gapTo, radius 18).
	{ name = "ArchTip", position = polar(202.5, 240 - 18 * math.cos(math.rad(62)), LT + 18 * math.sin(math.rad(62)) + 3), kind = "Arch" },
	{ name = "SkyIsland2", position = polar(157.5, 132, 41 + 7), kind = "Island" },
	{ name = "SkyIsland4", position = polar(157.5, 198, 50 + 7), kind = "Island" },
	{ name = "BossGate", position = polar(292.5, 280, Layout.GroundY + 14 + 16), kind = "Plateau" },
	{ name = "RuinTowerEast", position = polar(67.5, 186, Layout.GroundY + 24), kind = "Ruin" },
	{ name = "RuinTowerWest", position = polar(247.5, 186, Layout.GroundY + 24), kind = "Ruin" },
	{ name = "RuinTowerNorth", position = polar(337.5, 186, Layout.GroundY + 24), kind = "Ruin" },
	{ name = "RiftIslandEast", position = Layout.FloatingIslands[1] + Vector3.new(0, 9, 0), kind = "Island" },
	{ name = "RiftIslandWest", position = Layout.FloatingIslands[2] + Vector3.new(0, 9, 0), kind = "Island" },
} :: { GrapplePoint }
WorldFeatures.GrappleRange = 45

-- Walkable routes checked by the tests (waypoint polylines on the ground).
-- `mode` = "walk" (continuous) or "hop" (stepping stones / small gaps allowed).
export type Route = { name: string, mode: string, points: { Vector3 } }
-- Waypoints are {deg, r}; consecutive points are joined along the arc
-- (interpolating angle and radius every <= 4 degrees), not by a chord.
local function routeFromAngles(name: string, mode: string, list: { { number } }): Route
	local points = {}
	for i, p in list do
		if i > 1 then
			local q = list[i - 1]
			local span = p[1] - q[1]
			local steps = math.max(1, math.ceil(math.abs(span) / 4))
			for k = 1, steps - 1 do
				local t = k / steps
				table.insert(points, polar(q[1] + span * t, q[2] + (p[2] - q[2]) * t, 0))
			end
		end
		table.insert(points, polar(p[1], p[2], 0))
	end
	return { name = name, mode = mode, points = points }
end

WorldFeatures.Routes = {
	routeFromAngles("Bridge 22.5", "walk", { { 22.5, 30 }, { 22.5, 116 } }),
	routeFromAngles("Bridge 112.5", "walk", { { 112.5, 30 }, { 112.5, 116 } }),
	routeFromAngles("Bridge 202.5", "walk", { { 202.5, 30 }, { 202.5, 116 } }),
	routeFromAngles("Bridge 292.5", "walk", { { 292.5, 30 }, { 292.5, 116 } }),
	routeFromAngles("Ford 67.5", "hop", { { 67.5, 30 }, { 67.5, 116 } }),
	routeFromAngles("Ford 247.5", "hop", { { 247.5, 30 }, { 247.5, 116 } }),
	routeFromAngles("Ring road", "walk", { { 0, 110 }, { 45, 110 }, { 90, 110 }, { 135, 110 }, { 180, 110 }, { 225, 110 }, { 270, 110 }, { 315, 110 }, { 360, 110 } }),
	routeFromAngles("Outer trail (south)", "walk", { { 214, 240 }, { 250, 240 }, { 290, 240 }, { 330, 240 }, { 370, 240 }, { 410, 240 }, { 426, 240 } }),
	routeFromAngles("Ledge trail (east ramp, Observatory, Broken Arch, west ramp)", "walk", { { 48, 240 }, { 72, 240 }, { 98, 238 }, { 112.5, 233 }, { 127, 238 }, { 160, 240 }, { 202.5, 240 }, { 228, 240 } }),
	routeFromAngles("Ruined pass 67.5", "walk", { { 45 + 14, 150 }, { 67.5, 168 }, { 90 - 14, 150 } }),
	routeFromAngles("Ruined pass 247.5", "walk", { { 225 + 14, 150 }, { 247.5, 168 }, { 270 - 14, 150 } }),
	routeFromAngles("Ruined pass 337.5", "walk", { { 315 + 14, 150 }, { 337.5, 168 }, { 360 - 14, 150 } }),
	routeFromAngles("Boss plateau", "walk", { { 292.5, 240 }, { 292.5, 278 }, { 292.5, 300 } }),
	routeFromAngles("Sanctuary 3 back alley to crown", "walk", { { 0, 214 }, { 0, 240 } }),
} :: { Route }

return WorldFeatures
