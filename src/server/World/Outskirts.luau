--!strict
-- V2 level-design features around the core island (see Shared/WorldFeatures):
--   * cave mouths and interior lighting (tunnels are carved by TerrainBuilder),
--   * ruined passes between neighbouring Sanctuaries (cover, towers, gates),
--   * the Sky Route: bounce pad -> floating islands -> narrow rune bridges ->
--     High Ledge (no rails: a Pulse there is a fall),
--   * bounce pads up to the High Ledge and crystal veins on its cliff,
--   * prepared grapple anchors (the ability itself comes in a later phase).
-- Every function here has a gameplay role: escape, interception, risky
-- shortcut, verticality, landmark or future-mechanic anchor.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Layout = require(Shared.Layout)
local WorldFeatures = require(Shared.WorldFeatures)
local Parts = require(script.Parent.Parts)
local TerrainBuilder = require(script.Parent.TerrainBuilder)

local Outskirts = {}

local M = Enum.Material
local C = Layout.Colors
local polar = WorldFeatures.polar

local CAVE_GLOW = Color3.fromRGB(120, 220, 255)
local SKY_GLOW = Color3.fromRGB(140, 240, 255)
local GRAPPLE = Color3.fromRGB(170, 255, 240)
local GRASS = Color3.fromRGB(86, 168, 134)

local function groundAt(x: number, z: number): number
	return TerrainBuilder.heightAt(x, z) or Layout.GroundY
end

local function crystal(parent: Instance, cf: CFrame, height: number, color: Color3, name: string?): Part
	return Parts.block({
		size = Vector3.new(height * 0.26, height, height * 0.26),
		cf = cf * CFrame.new(0, height / 2 - 0.4, 0),
		color = color,
		material = M.Neon,
		collide = false,
		shadow = false,
		parent = parent,
		name = name or "Crystal",
	})
end

----------------------------------------------------------------------------
-- Caves
----------------------------------------------------------------------------

local function caveMouth(folder: Instance, at: Vector3, outward: Vector3, halfWidth: number, height: number, lit: boolean)
	local flat = Vector3.new(outward.X, 0, outward.Z).Unit
	local cf = CFrame.lookAt(at, at + flat)
	local side = cf.RightVector
	-- Lintel and jambs frame the opening in the ravine wall.
	Parts.block({ size = Vector3.new(halfWidth * 2 + 6, 3.6, 5), cf = cf * CFrame.new(0, height + 1.6, 0) * CFrame.Angles(0, 0, math.rad(3)), color = C.StoneDark, material = M.Slate, parent = folder, name = "CaveLintel" })
	for _, s in { -1, 1 } do
		Parts.block({
			size = Vector3.new(3, height + 2, 5),
			cf = cf * CFrame.new(s * (halfWidth + 1.2), (height + 2) / 2 - 0.5, 0) * CFrame.Angles(0, 0, math.rad(-s * 4)),
			color = C.Stone,
			material = M.Slate,
			parent = folder,
			name = "CaveJamb",
		})
		crystal(folder, CFrame.new(at + side * s * (halfWidth - 0.6) + flat * 2) * CFrame.Angles(math.rad(s * 12), math.rad(45), 0), 3.4, CAVE_GLOW, "CaveCrystal")
	end
	local lantern = Parts.block({ size = Vector3.new(1.2, 1.6, 1.2), cf = cf * CFrame.new(0, height - 0.6, -1), color = Color3.fromRGB(255, 220, 160), material = M.Neon, collide = false, shadow = false, parent = folder, name = "CaveLantern" })
	if lit then
		Parts.light(lantern, Color3.fromRGB(255, 200, 150), 18, 1.2)
	end
end

local function buildCaves(parent: Instance)
	for _, cave in WorldFeatures.Caves do
		local folder = Parts.folder(cave.name, parent)
		local points = cave.points
		for i = 1, #points - 1 do
			local p, q = points[i], points[i + 1]
			local a, b = WorldFeatures.cavePoint(p), WorldFeatures.cavePoint(q)
			-- Mouths: where open ravine meets tunnel.
			if p.covered ~= q.covered then
				local mouth = if p.covered then a else b
				local outward = if p.covered then b - a else a - b
				caveMouth(folder, mouth, outward, cave.halfWidth, cave.height, true)
			elseif p.covered and q.covered then
				-- Glowing crystal veins along the tunnel walls.
				local mid = (a + b) / 2
				local dir = Vector3.new(b.X - a.X, 0, b.Z - a.Z).Unit
				local side = Vector3.new(-dir.Z, 0, dir.X) * (if i % 2 == 0 then 1 else -1)
				local base = mid + side * (cave.halfWidth - 0.8)
				local main = crystal(folder, CFrame.new(base) * CFrame.Angles(0, math.rad(30), math.rad(if i % 2 == 0 then -14 else 14)), 4.2, CAVE_GLOW, "CaveVein")
				crystal(folder, CFrame.new(base + dir * 1.6) * CFrame.Angles(0.2, 0.6, 0.3), 2.4, Color3.fromRGB(190, 140, 255), "CaveVein")
				if i % 2 == 0 then
					Parts.light(main, CAVE_GLOW, 20, 1.1)
				end
			end
		end
		folder:SetAttribute("Feature", "Cave")
	end
end

----------------------------------------------------------------------------
-- Ruined passes
----------------------------------------------------------------------------

local function wall(folder: Instance, from: Vector3, to: Vector3, height: number, rng: Random)
	local a = Vector3.new(from.X, groundAt(from.X, from.Z), from.Z)
	local b = Vector3.new(to.X, groundAt(to.X, to.Z), to.Z)
	local length = (Vector3.new(b.X, 0, b.Z) - Vector3.new(a.X, 0, a.Z)).Magnitude
	local mid = (a + b) / 2
	local base = math.min(a.Y, b.Y) - 1
	local cf = CFrame.lookAt(Vector3.new(mid.X, base + height / 2, mid.Z), Vector3.new(b.X, base + height / 2, b.Z))
	Parts.block({ size = Vector3.new(1.8, height, length), cf = cf, color = C.StoneLight, material = M.Slate, parent = folder, name = "RuinWall" })
	-- Broken, uneven top.
	Parts.block({
		size = Vector3.new(2.2, 1.2, length * rng:NextNumber(0.35, 0.6)),
		cf = cf * CFrame.new(0, height / 2 + 0.4, length * rng:NextNumber(-0.2, 0.2)) * CFrame.Angles(math.rad(rng:NextNumber(-6, 6)), 0, 0),
		color = C.Stone,
		material = M.Slate,
		parent = folder,
		name = "RuinWallTop",
	})
end

local function column(folder: Instance, position: Vector3, rng: Random)
	local ground = groundAt(position.X, position.Z)
	local h = rng:NextNumber(5, 12)
	local base = CFrame.new(position.X, ground, position.Z) * CFrame.Angles(rng:NextNumber(-0.05, 0.05), rng:NextNumber(0, 6.28), rng:NextNumber(-0.05, 0.05))
	Parts.cylinder({ size = Vector3.new(3.6, 1, 3.6), cf = base * CFrame.new(0, 0.1, 0), color = C.Stone, material = M.Slate, parent = folder, name = "RuinColumnBase" })
	Parts.cylinder({ size = Vector3.new(2.5, h, 2.5), cf = base * CFrame.new(0, h / 2, 0), color = C.StoneLight, material = M.Marble, parent = folder, name = "RuinColumn" })
end

local function gate(folder: Instance, at: Vector3, facing: Vector3, span: number)
	local ground = groundAt(at.X, at.Z)
	local cf = CFrame.lookAt(Vector3.new(at.X, ground, at.Z), Vector3.new(at.X, ground, at.Z) + Vector3.new(facing.X, 0, facing.Z))
	for _, s in { -1, 1 } do
		Parts.block({ size = Vector3.new(2.6, 12, 2.6), cf = cf * CFrame.new(s * span / 2, 5.5, 0), color = C.StoneLight, material = M.Slate, parent = folder, name = "RuinGatePillar" })
		Parts.block({ size = Vector3.new(0.25, 7, 0.6), cf = cf * CFrame.new(s * span / 2, 6, -1.35), color = C.Rift, material = M.Neon, collide = false, shadow = false, parent = folder, name = "RuinGateRune" })
	end
	Parts.block({ size = Vector3.new(span + 4, 2.4, 3), cf = cf * CFrame.new(0, 12.6, 0) * CFrame.Angles(0, 0, math.rad(4)), color = C.Stone, material = M.Slate, parent = folder, name = "RuinGateLintel" })
end

local function tower(folder: Instance, at: Vector3, facingIn: Vector3)
	local ground = groundAt(at.X, at.Z)
	local cf = CFrame.lookAt(Vector3.new(at.X, ground, at.Z), Vector3.new(at.X, ground, at.Z) + Vector3.new(facingIn.X, 0, facingIn.Z))
	local h = 22
	-- Three walls; the side facing the pass is open (walk-in cover).
	Parts.block({ size = Vector3.new(9, h, 1.6), cf = cf * CFrame.new(0, h / 2 - 0.5, 4), color = C.StoneLight, material = M.Slate, parent = folder, name = "RuinTowerWall" })
	for _, s in { -1, 1 } do
		local wallH = if s == 1 then h else h - 6
		Parts.block({ size = Vector3.new(1.6, wallH, 9), cf = cf * CFrame.new(s * 4, wallH / 2 - 0.5, 0), color = C.Stone, material = M.Slate, parent = folder, name = "RuinTowerWall" })
	end
	Parts.block({ size = Vector3.new(9.6, 1.2, 9.6), cf = cf * CFrame.new(0, 9, 0), color = C.StoneDark, material = M.Slate, parent = folder, name = "RuinTowerFloor" })
	Parts.block({ size = Vector3.new(0.3, 8, 0.3), cf = cf * CFrame.new(-2.5, h - 6, 4.85), color = C.Rift, material = M.Neon, collide = false, shadow = false, parent = folder, name = "RuinTowerSlit" })
	Parts.block({ size = Vector3.new(10.4, 1.4, 2.4), cf = cf * CFrame.new(0, h, 4) * CFrame.Angles(0, 0, math.rad(-7)), color = C.StoneLight, material = M.Slate, parent = folder, name = "RuinTowerCrown" })
end

local function ruinPass(parent: Instance, deg: number, full: boolean, rng: Random)
	local folder = Parts.folder("RuinedPass" .. tostring(deg), parent)
	folder:SetAttribute("Feature", "RuinedPass")
	local inward = -polar(deg, 1, 0)
	-- Gate on each approach from the neighbouring Sanctuaries.
	for _, s in { -1, 1 } do
		local at = polar(deg + s * 4.6, 158, 0)
		local towardCenter = polar(deg, 168, 0) - at
		gate(folder, at, Vector3.new(towardCenter.X, 0, towardCenter.Z), 9)
	end
	-- Broken walls behind the pass (cover, line-of-sight breaks).
	-- (Everything stays >= 44 studs from both neighbouring Sanctuary centres.)
	wall(folder, polar(deg - 7, 184, 0), polar(deg - 1.5, 182, 0), 5.5, rng)
	wall(folder, polar(deg + 2, 181, 0), polar(deg + 6.5, 186, 0), 4, rng)
	wall(folder, polar(deg + 5, 197, 0), polar(deg + 8, 202, 0), 4.5, rng)
	-- Columns along the old colonnade.
	for k, spot in { { deg - 6, 170 }, { deg + 6.5, 172 }, { deg + 4.5, 192 }, { deg - 3, 194 } } do
		if full or k <= 2 then
			column(folder, polar(spot[1], spot[2], 0), rng)
		end
	end
	if full then
		tower(folder, polar(deg, 192, 0), inward)
		-- Raised dais with steps: a small vantage point in the middle of the ruins.
		local dais = polar(deg - 4.5, 176, 0)
		local ground = groundAt(dais.X, dais.Z)
		local cf = CFrame.lookAt(Vector3.new(dais.X, ground, dais.Z), Vector3.new(dais.X, ground, dais.Z) + inward)
		Parts.block({ size = Vector3.new(9, 3, 9), cf = cf * CFrame.new(0, 0.8, 0), color = C.Stone, material = M.Slate, parent = folder, name = "RuinDais" })
		Parts.block({ size = Vector3.new(4, 1.6, 2.4), cf = cf * CFrame.new(0, 0.1, -5.6), color = C.StoneLight, material = M.Slate, parent = folder, name = "RuinStep" })
		Parts.block({ size = Vector3.new(9.4, 0.3, 9.4), cf = cf * CFrame.new(0, 2.35, 0), color = C.Rift, material = M.Neon, transparency = 0.3, collide = false, shadow = false, parent = folder, name = "RuinDaisGlow" })
	end
	-- Rubble.
	for _ = 1, (if full then 4 else 2) do
		local p = polar(deg + rng:NextNumber(-7, 7), rng:NextNumber(178, 200), 0)
		local ground = groundAt(p.X, p.Z)
		local size = Vector3.new(rng:NextNumber(2, 4), rng:NextNumber(1.5, 3), rng:NextNumber(2, 4.5))
		Parts.block({ size = size, cf = CFrame.new(p.X, ground + size.Y * 0.3, p.Z) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 6), rng:NextNumber(-0.4, 0.4)), color = C.StoneLight, material = M.Slate, parent = folder, name = "Rubble" })
	end
end

local function buildRuins(parent: Instance)
	local rng = Random.new(6060)
	for _, deg in WorldFeatures.RuinPasses do
		ruinPass(parent, deg, deg ~= 22.5, rng)
	end
end

----------------------------------------------------------------------------
-- Bounce pads, Sky Route and High Ledge dressing
----------------------------------------------------------------------------

local function bouncePad(folder: Instance, name: string, position: Vector3, target: Vector3, vy: number, color: Color3)
	local ground = groundAt(position.X, position.Z)
	local padPos = Vector3.new(position.X, ground + 0.3, position.Z)
	local pad = Parts.cylinder({ size = Vector3.new(5, 0.6, 5), cf = CFrame.new(padPos), color = color, material = M.Neon, parent = folder, name = name })
	pad:SetAttribute("Launch", Parts.launchVelocity(padPos + Vector3.new(0, 3, 0), target, vy))
	pad:SetAttribute("Target", target)
	Parts.cylinder({ size = Vector3.new(6.4, 0.5, 6.4), cf = CFrame.new(padPos - Vector3.new(0, 0.12, 0)), color = C.StoneLight, material = M.Slate, parent = folder, name = "BounceRim" })
	-- Arrow chevrons pointing at the destination.
	local flat = Vector3.new(target.X - padPos.X, 0, target.Z - padPos.Z).Unit
	for k = 1, 2 do
		local p = padPos + flat * (3.6 + k * 1.6) + Vector3.new(0, -0.05, 0)
		Parts.block({ size = Vector3.new(2.4, 0.2, 0.5), cf = CFrame.lookAt(p, p + flat), color = color, material = M.Neon, transparency = 0.2 * k, collide = false, shadow = false, parent = folder, name = "PadArrow" })
	end
	return pad
end

local function skyIsland(folder: Instance, spec: WorldFeatures.SkyIsland, index: number)
	local p = spec.position
	local d = spec.radius * 2
	Parts.cylinder({ size = Vector3.new(d, 2, d), cf = CFrame.new(p), color = GRASS, material = M.Grass, parent = folder, name = "SkyIsland" .. index })
	Parts.cylinder({ size = Vector3.new(d + 0.6, 1.2, d + 0.6), cf = CFrame.new(p - Vector3.new(0, 0.6, 0)), color = SKY_GLOW, material = M.Neon, parent = folder, name = "SkyIslandRim" })
	Parts.ellipsoid({ size = Vector3.new(d * 0.92, 6, d * 0.92), cf = CFrame.new(p - Vector3.new(0, 3.6, 0)), color = C.StoneDark, material = M.Slate, parent = folder, name = "SkyIslandRock" })
	Parts.ellipsoid({ size = Vector3.new(d * 0.4, 6, d * 0.4), cf = CFrame.new(p - Vector3.new(0, 7, 0)), color = C.StoneDark, material = M.Slate, parent = folder, name = "SkyIslandRock" })
	crystal(folder, CFrame.new(p - Vector3.new(0, 9.5, 0)) * CFrame.Angles(math.rad(180), 0.6, 0), 3, SKY_GLOW, "SkyIslandShard")
end

local function runeBridge(folder: Instance, from: Vector3, to: Vector3, width: number, index: number)
	local length = (to - from).Magnitude
	local mid = (from + to) / 2
	local cf = CFrame.lookAt(mid, to)
	Parts.block({ size = Vector3.new(width, 0.8, length), cf = cf * CFrame.new(0, -0.4, 0), color = C.StoneLight, material = M.Marble, parent = folder, name = "RuneBridge" .. index })
	for _, s in { -1, 1 } do
		Parts.block({ size = Vector3.new(0.25, 0.3, length - 0.6), cf = cf * CFrame.new(s * (width / 2 - 0.12), 0.08, 0), color = SKY_GLOW, material = M.Neon, collide = false, shadow = false, parent = folder, name = "RuneEdge" })
	end
	local stone = Parts.block({ size = Vector3.new(2.2, 2.2, 2.2), cf = cf * CFrame.new(0, -4.5, 0) * CFrame.Angles(0.6, 0.8, 0.3), color = C.StoneDark, material = M.Slate, collide = false, parent = folder, name = "RuneStone" })
	stone.CanQuery = false
end

local function buildSkyRoute(parent: Instance)
	local spec = WorldFeatures.SkyRoute
	local folder = Parts.folder("SkyRoute", parent)
	folder:SetAttribute("Feature", "SkyRoute")
	local pads = Parts.folder("BouncePads", folder)
	local islands = spec.islands
	local first = islands[1].position
	local toward = Vector3.new(spec.pad.X - first.X, 0, spec.pad.Z - first.Z).Unit
	bouncePad(pads, "SkyPad", spec.pad, first + Vector3.new(0, 4, 0) + toward * 2, 86, SKY_GLOW)
	for i, island in islands do
		skyIsland(folder, island, i)
	end
	local function top(i: number): Vector3
		return islands[i].position + Vector3.new(0, 1, 0)
	end
	for i = 1, #islands - 1 do
		local a, b = top(i), top(i + 1)
		local dir = Vector3.new(b.X - a.X, 0, b.Z - a.Z).Unit
		runeBridge(folder, a + dir * (islands[i].radius - 0.6), b - dir * (islands[i + 1].radius - 0.6), spec.bridgeWidth, i)
	end
	local last = top(#islands)
	local landing = Vector3.new(spec.landing.X, groundAt(spec.landing.X, spec.landing.Z) + 0.4, spec.landing.Z)
	local dir = Vector3.new(landing.X - last.X, 0, landing.Z - last.Z).Unit
	runeBridge(folder, last + dir * (islands[#islands].radius - 0.6), landing, spec.bridgeWidth, #islands)
	-- Lantern on the first island to read the route from the meadow.
	local beacon = crystal(folder, CFrame.new(top(1) + Vector3.new(0, 0, 0)) * CFrame.Angles(0, 0.7, 0), 5, SKY_GLOW, "SkyBeacon")
	Parts.light(beacon, SKY_GLOW, 26, 1.3)
end

local function buildLedge(parent: Instance)
	local folder = Parts.folder("HighLedge", parent)
	folder:SetAttribute("Feature", "HighLedge")
	local pads = Parts.folder("BouncePads", folder)
	for i, spec in WorldFeatures.LedgePads do
		bouncePad(pads, "LedgePad" .. i, spec.position, spec.target, 112, Color3.fromRGB(255, 214, 120))
	end
	-- Crystal veins on the inner cliff face (mark the climb, light the back alleys).
	local rng = Random.new(4141)
	for k, deg in { 80, 118, 128, 147, 168, 194 } do
		local base = polar(deg, WorldFeatures.Ledge.inner - 3.5, 0)
		local y = Layout.GroundY + 6 + rng:NextNumber(0, 10)
		local outward = polar(deg, 1, 0)
		local cf = CFrame.lookAt(Vector3.new(base.X, y, base.Z), Vector3.new(base.X, y, base.Z) - outward) * CFrame.Angles(math.rad(-25), 0, 0)
		local main = crystal(folder, cf * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-20, 20))), rng:NextNumber(5, 8), C.Rift, "CliffCrystal")
		crystal(folder, cf * CFrame.new(1.6, -1, 0.4) * CFrame.Angles(0, 0, math.rad(-25)), 3, Color3.fromRGB(120, 210, 255), "CliffCrystal")
		if k % 2 == 1 then
			Parts.light(main, C.Rift, 22, 1)
		end
	end
end

----------------------------------------------------------------------------
-- Grapple anchors (prepared)
----------------------------------------------------------------------------

local function buildGrapplePoints(parent: Instance)
	local folder = Parts.folder("GrapplePoints", parent)
	for _, spec in WorldFeatures.GrapplePoints do
		local anchor = Parts.block({ size = Vector3.one, cf = CFrame.new(spec.position), transparency = 1, collide = false, shadow = false, parent = folder, name = spec.name })
		anchor.CanQuery = false
		anchor:SetAttribute("GrapplePoint", true)
		anchor:SetAttribute("Kind", spec.kind)
		anchor:SetAttribute("Range", WorldFeatures.GrappleRange)
		-- Consistent look: cyan-white hook gem inside a ring facing the Rift.
		Parts.block({ size = Vector3.new(1.3, 1.3, 1.3), cf = CFrame.new(spec.position) * CFrame.Angles(math.rad(45), 0, math.rad(45)), color = GRAPPLE, material = M.Neon, collide = false, shadow = false, parent = anchor, name = "Hook" }).CanQuery = false
		local facing = CFrame.lookAt(spec.position, Vector3.new(0, spec.position.Y, 0))
		Parts.beamRing(anchor, anchor.CFrame:ToObjectSpace(facing) * CFrame.Angles(math.rad(90), 0, 0), 1.9, 0.35, GRAPPLE, 0.15)
	end
end

function Outskirts.build(parent: Instance)
	local folder = Parts.folder("Outskirts", parent)
	buildCaves(folder)
	buildRuins(folder)
	task.wait()
	buildSkyRoute(folder)
	buildLedge(folder)
	buildGrapplePoints(parent)
end

return Outskirts
