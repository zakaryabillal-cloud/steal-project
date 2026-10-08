--!strict
-- Generates the floating island with smooth voxel terrain:
--   * a terraced basin cradling the Rift,
--   * a meadow ring, a river moat (water) with bridge/ford spokes,
--   * an outer ring road, ridges separating neighbouring Sanctuaries
--     (four of them lowered into ruined passes),
--   * V2: the outer crown (upland + loop trail), the High Ledge, the boss
--     promontory, two caves under the river (open ravines in the heightmap +
--     tunnels carved with Air),
--   * a jagged rock cone underneath and a few distant floating islets.
-- The surface is written with WriteVoxels from a deterministic heightmap.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Layout = require(Shared.Layout)
local WorldFeatures = require(Shared.WorldFeatures)
local MathUtil = require(Shared.Util.MathUtil)
local Palette = require(Shared.Config.Palette)

local TerrainBuilder = {}

local SEED = 7331
local RES = 4
local HALF = 320
local CHUNK = 64
local Y_MIN = -8
local Y_MAX = 76

local CROWN = WorldFeatures.Crown
local LEDGE = WorldFeatures.Ledge
local BOSS = WorldFeatures.BossPlateau
local BOSS_DIR = Vector3.new(math.cos(math.rad(BOSS.deg)), 0, math.sin(math.rad(BOSS.deg)))
local BOSS_SIDE = Vector3.new(-BOSS_DIR.Z, 0, BOSS_DIR.X)
local UNDERSIDE_SCALE = Layout.IslandRadius / 236

-- Ruined passes: ridge index (0..7) -> true.
local RUIN_RIDGE: { [number]: boolean } = {}
for _, deg in WorldFeatures.RuinPasses do
	RUIN_RIDGE[math.floor(((deg - 22.5 + 90) % 360) / 45 + 0.5) % 8] = true
end

-- Cave polylines in world space (floor heights in Y).
type CaveSeg = { a: Vector3, b: Vector3, covered: boolean, halfWidth: number, height: number, last: boolean }
local CAVE_SEGS: { CaveSeg } = {}
for _, cave in WorldFeatures.Caves do
	for i = 1, #cave.points - 1 do
		local p, q = cave.points[i], cave.points[i + 1]
		table.insert(CAVE_SEGS, {
			a = WorldFeatures.cavePoint(p),
			b = WorldFeatures.cavePoint(q),
			covered = p.covered and q.covered,
			halfWidth = cave.halfWidth,
			height = cave.height,
			last = i == #cave.points - 1,
		})
	end
end

local M = Enum.Material
local smooth = MathUtil.smoothstep

local PATH_ANGLES: { number } = {}
for _, a in Layout.BridgeAngles do
	table.insert(PATH_ANGLES, math.rad(a))
end
for _, a in Layout.FordAngles do
	table.insert(PATH_ANGLES, math.rad(a))
end

local PLOT_CENTERS: { Vector3 } = {}
for i = 1, Layout.PlotCount do
	table.insert(PLOT_CENTERS, Layout.plotCFrame(i).Position)
end

local function edgeRadius(theta: number): number
	return Layout.IslandRadius - 4 + MathUtil.fbm(math.cos(theta) * 2.2 + 50, math.sin(theta) * 2.2 + 50, SEED, 3) * 14
end

local function ridgeHeight(r: number, theta: number): number
	if r < 132 then
		return 0
	end
	local step = math.rad(45)
	local base = math.rad(-90 + 22.5)
	local rel = (theta - base) % step
	local index = math.floor((theta - base) / step + 0.5) % 8
	local arc = math.min(rel, step - rel) * r
	local across = 1 - smooth(0, 17, arc)
	-- V2: ridges fade into the outer crown instead of running to the edge.
	local along = smooth(132, 158, r) * (1 - smooth(196, 220, r))
	local wobble = 1 + MathUtil.noise2(r / 22, theta * 3, SEED + 9) * 0.25
	-- Ruined passes: the ridge is lowered into a walkable saddle.
	local scale = if RUIN_RIDGE[index] then 0.2 else 1
	return (across ^ 1.4) * along * 17 * wobble * scale
end

local function degreesOf(theta: number): number
	return math.deg(theta) % 360
end

-- High Ledge height (or nil outside it). `base` is the crown height there.
local function ledgeHeight(r: number, deg: number, base: number, x: number, z: number): (number?, number)
	if deg < LEDGE.from - LEDGE.ramp or deg > LEDGE.to + LEDGE.ramp or r < LEDGE.inner - 8 then
		return nil, 0
	end
	local fa = smooth(LEDGE.from - LEDGE.ramp, LEDGE.from, deg) * (1 - smooth(LEDGE.to, LEDGE.to + LEDGE.ramp, deg))
	local fr = smooth(LEDGE.inner - 7, LEDGE.inner, r) * (1 - smooth(LEDGE.outer, LEDGE.outer + 7, r))
	local w = fa * fr
	if w <= 0 then
		return nil, 0
	end
	local top = LEDGE.top + MathUtil.fbm(x / 30, z / 30, SEED + 21, 2) * 1.6
	return MathUtil.lerp(base, top, w), w
end

-- Boss promontory: (inside?, height, isPlaza)
local function promontory(x: number, z: number): (boolean, number, boolean)
	local along = x * BOSS_DIR.X + z * BOSS_DIR.Z
	local lateral = math.abs(x * BOSS_SIDE.X + z * BOSS_SIDE.Z)
	local plazaCenter = BOSS_DIR * BOSS.center
	local dx, dz = x - plazaCenter.X, z - plazaCenter.Z
	local plazaDist = math.sqrt(dx * dx + dz * dz)
	local wobble = MathUtil.noise2(x / 14, z / 14, SEED + 33) * 2.5
	if plazaDist <= BOSS.radius + wobble then
		return true, BOSS.top, true
	end
	if along >= BOSS.neckFrom - 6 and along <= BOSS.center and lateral <= BOSS.neckHalfWidth + wobble then
		local t = smooth(BOSS.neckFrom, BOSS.neckTo, along)
		local crownTop = Layout.GroundY + CROWN.height
		return true, MathUtil.lerp(crownTop, BOSS.top, t), false
	end
	return false, 0, false
end

-- Distance from (x, z) to segment a-b in XZ, the interpolated floor and the
-- unclamped projection parameter (0 at a, 1 at b).
local function segmentInfo(seg: CaveSeg, x: number, z: number): (number, number, number)
	local ax, az = seg.a.X, seg.a.Z
	local bx, bz = seg.b.X, seg.b.Z
	local vx, vz = bx - ax, bz - az
	local len2 = vx * vx + vz * vz
	local raw = ((x - ax) * vx + (z - az) * vz) / len2
	local t = math.clamp(raw, 0, 1)
	local px, pz = ax + vx * t, az + vz * t
	local d = math.sqrt((x - px) ^ 2 + (z - pz) ^ 2)
	return d, MathUtil.lerp(seg.a.Y, seg.b.Y, t), raw
end

export type Sample = {
	height: number,
	zone: string,
	path: string?,
}

-- Surface sample at (x, z); nil outside the island.
function TerrainBuilder.sample(x: number, z: number): Sample?
	local r = math.sqrt(x * x + z * z)
	local theta = math.atan2(z, x)
	local edge = edgeRadius(theta)
	local inPromontory, promontoryH, isPlaza = false, 0, false
	if r > 230 then
		inPromontory, promontoryH, isPlaza = promontory(x, z)
	end
	if r > edge and not inPromontory then
		return nil
	end
	local n = MathUtil.fbm(x / 48, z / 48, SEED, 3)
	local h: number
	local zone: string
	if r <= Layout.BasinRadius then
		h = Layout.BasinY + n * 0.35
		zone = "basin"
	elseif r <= Layout.RimRadius then
		local t = (r - Layout.BasinRadius) / (Layout.RimRadius - Layout.BasinRadius)
		local s = t * 3
		local k = math.floor(s)
		local f = s - k
		h = Layout.BasinY + (k + smooth(0.5, 1, f)) * ((Layout.GroundY - Layout.BasinY) / 3)
		zone = "rim"
	elseif r <= Layout.RiverInner then
		h = Layout.GroundY + n * 1.2 * smooth(Layout.RimRadius, Layout.RimRadius + 6, r)
		zone = "meadow"
	elseif r <= Layout.RiverOuter then
		local half = (Layout.RiverOuter - Layout.RiverInner) / 2
		local d = math.abs(r - Layout.RiverCenter) / half
		h = Layout.RiverBedY + (Layout.GroundY - Layout.RiverBedY) * smooth(0.45, 1, d)
		zone = "river"
	else
		h = Layout.GroundY + n * 2.4 * smooth(Layout.RiverOuter, Layout.RiverOuter + 20, r) + ridgeHeight(r, theta)
		zone = "outer"
		-- Outer crown: an upland behind the Sanctuaries, cresting along the trail.
		if r > CROWN.riseFrom then
			local crownH = Layout.GroundY + smooth(CROWN.riseFrom, CROWN.riseTo, r) * (CROWN.height + MathUtil.fbm(x / 40, z / 40, SEED + 17, 3) * 3.5)
			h = math.max(h, crownH)
			zone = "crown"
		end
		h -= smooth(edge - 22, edge, r) * 9
		if r > edge - 10 then
			zone = "edge"
		end
	end

	local path: string? = nil

	-- Spokes: ramps from the river down through the terraces into the basin.
	if r > Layout.BasinRadius - 6 and r < Layout.RiverInner + 1 then
		for _, a in PATH_ANGLES do
			local ux, uz = math.cos(a), math.sin(a)
			local along = x * ux + z * uz
			if along > 0 then
				local dist = math.abs(x * uz - z * ux)
				if dist < 6 then
					local t = math.clamp((along - Layout.BasinRadius + 2) / (Layout.RimRadius - Layout.BasinRadius + 4), 0, 1)
					local pathH = MathUtil.lerp(Layout.BasinY, Layout.GroundY, t)
					local w = 1 - smooth(3.5, 6, dist)
					h = MathUtil.lerp(h, pathH, w)
					if dist < 3.6 then
						path = "spoke"
					end
				end
			end
		end
	end

	-- Ring road hugging the outer river bank.
	local roadDist = math.abs(r - Layout.RingRoadRadius)
	if roadDist < 7 then
		local w = 1 - smooth(4.5, 7, roadDist)
		h = MathUtil.lerp(h, Layout.GroundY, w)
		if roadDist < 4.5 then
			path = "road"
		end
	end

	-- Paved plaza around the dais.
	if r < 19 then
		path = "plaza"
	end

	-- Flatten under each Sanctuary foundation and its approach.
	for _, center in PLOT_CENTERS do
		local dx, dz = x - center.X, z - center.Z
		local d = math.sqrt(dx * dx + dz * dz)
		if d < 56 then
			local w = 1 - smooth(42, 56, d)
			h = MathUtil.lerp(h, Layout.GroundY, w)
		end
	end

	if r > 200 then
		local deg = degreesOf(theta)
		-- Loop trail along the crown crest (also runs over the ledge).
		local trailDist = math.abs(r - WorldFeatures.trailRadiusAt(deg))
		if trailDist < CROWN.trailHalfWidth + 2 and not inPromontory then
			if trailDist < CROWN.trailHalfWidth then
				path = "trail"
			end
		end
		-- High Ledge.
		local ledgeH, ledgeW = ledgeHeight(r, deg, h, x, z)
		if ledgeH then
			h = ledgeH
			if ledgeW > 0.98 and r > LEDGE.inner + 1 and r < LEDGE.outer - 1 then
				zone = "ledge"
			end
		end
		-- Boss promontory (neck + plaza), beyond the normal island edge.
		if inPromontory then
			h = if isPlaza then promontoryH else math.max(h, promontoryH)
			zone = "plateau"
			if isPlaza then
				local portal = BOSS_DIR * BOSS.portalR
				local pd = math.sqrt((x - portal.X) ^ 2 + (z - portal.Z) ^ 2)
				path = if pd < 9 then "lava" else "plaza"
			else
				local lateral = math.abs(x * BOSS_SIDE.X + z * BOSS_SIDE.Z)
				if lateral < 4 then
					path = "bossway"
				end
			end
		end
	end

	-- Cave ravines: open cave segments are cut into the heightmap.
	if r > 60 and r < 170 then
		for _, seg in CAVE_SEGS do
			if seg.covered then
				continue
			end
			local d, floor, raw = segmentInfo(seg, x, z)
			-- Each open segment only shapes the ground beside it: never before its
			-- start (keeps the ring road intact at the tunnel mouth) and never past
			-- its end, except for the cave's final segment which fades out.
			if d < seg.halfWidth + 3 and floor < h and raw > 0 and (raw <= 1 or seg.last) then
				local w = 1 - smooth(seg.halfWidth, seg.halfWidth + 3, d)
				h = MathUtil.lerp(h, floor, w)
				if d < seg.halfWidth - 0.5 then
					path = "ravine"
				end
			end
		end
	end

	return { height = h, zone = zone, path = path }
end

local function surfaceMaterial(sample: Sample, slope: number, x: number, z: number): Enum.Material
	local p = sample.path
	if p == "road" then
		return M.Pavement
	elseif p == "spoke" or p == "bossway" then
		return M.Cobblestone
	elseif p == "plaza" then
		return if sample.zone == "plateau" then M.Basalt else M.Slate
	elseif p == "lava" then
		return M.CrackedLava
	elseif p == "trail" then
		return if slope > 0.9 then M.Rock else M.Ground
	elseif p == "ravine" then
		return if slope > 0.6 then M.Rock else M.Ground
	end
	local zone = sample.zone
	if zone == "plateau" then
		return if slope > 0.6 then M.Basalt else M.Slate
	elseif zone == "ledge" then
		if slope > 0.6 then
			return M.Rock
		end
		-- Mostly meadow on top, with a few pale stone outcrops.
		return if MathUtil.noise2(x / 22, z / 22, SEED + 5) > 0.62 then M.Limestone else M.LeafyGrass
	end
	if zone == "basin" then
		return M.Slate
	elseif zone == "river" then
		if sample.height < Layout.WaterY - 1 then
			return M.Sand
		end
		return M.Ground
	elseif zone == "edge" then
		return if slope > 0.5 then M.Rock else M.Grass
	end
	if slope > 0.75 then
		return M.Rock
	end
	local patch = MathUtil.noise2(x / 26, z / 26, SEED + 3)
	if patch > 0.25 then
		return M.LeafyGrass
	end
	return M.Grass
end

-- Surface material at (x, z) (nil outside the island). Used by tools/tests.
function TerrainBuilder.materialAt(x: number, z: number): Enum.Material?
	local sample = TerrainBuilder.sample(x, z)
	if not sample then
		return nil
	end
	local sx = TerrainBuilder.sample(x + 2, z)
	local sz = TerrainBuilder.sample(x, z + 2)
	local slope = 0
	if sx and sz then
		slope = math.max(math.abs(sx.height - sample.height), math.abs(sz.height - sample.height)) / 2
	end
	return surfaceMaterial(sample, slope, x, z)
end

local function writeSurface(terrain: Terrain)
	local cols = (HALF * 2) // RES
	local heights: { { number } } = {}
	local mats: { { Enum.Material } } = {}
	local waters: { { boolean } } = {}

	for ix = 1, cols do
		local x = -HALF + (ix - 0.5) * RES
		local hRow, mRow, wRow = {}, {}, {}
		for iz = 1, cols do
			local z = -HALF + (iz - 0.5) * RES
			local sample = TerrainBuilder.sample(x, z)
			if sample then
				local sx = TerrainBuilder.sample(x + 2, z)
				local sz = TerrainBuilder.sample(x, z + 2)
				local slope = 0
				if sx and sz then
					slope = math.max(math.abs(sx.height - sample.height), math.abs(sz.height - sample.height)) / 2
				end
				hRow[iz] = sample.height
				mRow[iz] = surfaceMaterial(sample, slope, x, z)
				wRow[iz] = sample.zone == "river" and sample.height < Layout.WaterY
			else
				hRow[iz] = -math.huge
				mRow[iz] = M.Air
				wRow[iz] = false
			end
		end
		heights[ix] = hRow
		mats[ix] = mRow
		waters[ix] = wRow
	end

	local cellsY = (Y_MAX - Y_MIN) // RES
	local chunkCells = CHUNK // RES
	for cx = 0, (HALF * 2) // CHUNK - 1 do
		for cz = 0, (HALF * 2) // CHUNK - 1 do
			local materials: { { { Enum.Material } } } = {}
			local occupancy: { { { number } } } = {}
			local any = false
			for lx = 1, chunkCells do
				local ix = cx * chunkCells + lx
				local mx: { { Enum.Material } } = {}
				local ox: { { number } } = {}
				for ly = 1, cellsY do
					local yb = Y_MIN + (ly - 1) * RES
					local my: { Enum.Material } = {}
					local oy: { number } = {}
					for lz = 1, chunkCells do
						local iz = cz * chunkCells + lz
						local h = heights[ix][iz]
						local occ = math.clamp((h - yb) / RES, 0, 1)
						local material = M.Air
						if occ > 0 then
							material = if h - yb <= 8 then mats[ix][iz] else M.Rock
							any = true
						end
						if waters[ix][iz] and yb < Layout.WaterY then
							if occ < 1 then
								if occ >= 0.5 then
									occ = 1
								else
									material = M.Water
									occ = math.clamp((Layout.WaterY - yb) / RES, 0, 1)
								end
							end
						end
						if occ <= 0 then
							material = M.Air
						end
						my[lz] = material
						oy[lz] = occ
					end
					mx[ly] = my
					ox[ly] = oy
				end
				materials[lx] = mx
				occupancy[lx] = ox
			end
			if any then
				local min = Vector3.new(-HALF + cx * CHUNK, Y_MIN, -HALF + cz * CHUNK)
				local region = Region3.new(min, min + Vector3.new(CHUNK, Y_MAX - Y_MIN, CHUNK)):ExpandToGrid(RES)
				terrain:WriteVoxels(region, RES, materials, occupancy)
			end
		end
		task.wait()
	end
end

local function writeUnderside(terrain: Terrain)
	local rng = Random.new(SEED)
	local layers = {
		{ top = -4, bottom = -24, radius = 218 },
		{ top = -20, bottom = -42, radius = 196 },
		{ top = -38, bottom = -60, radius = 168 },
		{ top = -56, bottom = -78, radius = 136 },
		{ top = -74, bottom = -96, radius = 102 },
		{ top = -92, bottom = -116, radius = 68 },
		{ top = -112, bottom = -136, radius = 38 },
		{ top = -132, bottom = -160, radius = 16 },
	}
	for index, layer in layers do
		local height = (layer.top - layer.bottom) * UNDERSIDE_SCALE
		local mid = (layer.top + layer.bottom) / 2 * UNDERSIDE_SCALE
		local radius = layer.radius * UNDERSIDE_SCALE
		local material = if index <= 2 then M.Rock else M.Basalt
		terrain:FillCylinder(CFrame.new(0, mid, 0), height, radius, material)
		local count = math.max(6, math.floor(radius / 9))
		for k = 1, count do
			local a = (k / count) * math.pi * 2 + rng:NextNumber(-0.1, 0.1)
			local rr = radius * rng:NextNumber(0.86, 1.02)
			local size = rng:NextNumber(8, 16) * (0.6 + radius / 300)
			terrain:FillBall(Vector3.new(math.cos(a) * rr, mid + rng:NextNumber(-height, height) * 0.4, math.sin(a) * rr), size, material)
		end
	end
	-- Hanging stalactites.
	for _ = 1, 16 do
		local a = rng:NextNumber(0, math.pi * 2)
		local rr = rng:NextNumber(30, 200)
		local y = -40 - (1 - rr / 260) * 80
		for s = 0, 3 do
			terrain:FillBall(Vector3.new(math.cos(a) * rr, y - s * 9, math.sin(a) * rr), 9 - s * 2, M.Basalt)
		end
	end
	-- Rock mass hanging under the boss promontory.
	for k = 0, 5 do
		local along = BOSS.neckFrom + 10 + k * 13
		local center = BOSS_DIR * along
		local drop = 10 + k * 4
		terrain:FillBall(Vector3.new(center.X, -drop, center.Z), 20 - k * 1.5, M.Basalt)
		terrain:FillBall(Vector3.new(center.X, -drop - 22, center.Z), 11 - k, M.Basalt)
	end
	task.wait()
end

-- Carves the cave tunnels (covered cave segments) out of the terrain.
local function carveCaves(terrain: Terrain)
	for _, seg in CAVE_SEGS do
		if not seg.covered then
			continue
		end
		local up = Vector3.new(0, seg.height / 2, 0)
		local a, b = seg.a + up, seg.b + up
		local length = (b - a).Magnitude
		local cf = CFrame.lookAt((a + b) / 2, b)
		terrain:FillBlock(cf, Vector3.new(seg.halfWidth * 2, seg.height, length + 3), M.Air)
		terrain:FillBall(a, seg.height / 2 + 0.5, M.Air)
		terrain:FillBall(b, seg.height / 2 + 0.5, M.Air)
	end
	task.wait()
end

local function writeIslets(terrain: Terrain): { Vector3 }
	local rng = Random.new(SEED + 1)
	local tops = {}
	for i = 1, 7 do
		local a = (i / 7) * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local dist = rng:NextNumber(345, 420)
		local y = rng:NextNumber(-10, 50)
		local radius = rng:NextNumber(14, 26)
		local center = Vector3.new(math.cos(a) * dist, y, math.sin(a) * dist)
		terrain:FillCylinder(CFrame.new(center), 6, radius, M.Grass)
		terrain:FillBall(center - Vector3.new(0, radius * 0.45, 0), radius * 0.85, M.Rock)
		terrain:FillBall(center - Vector3.new(0, radius * 1.05, 0), radius * 0.45, M.Basalt)
		table.insert(tops, center + Vector3.new(0, 3, 0))
	end
	return tops
end

-- Rock clusters (terrain balls blend better than parts and cost nothing).
function TerrainBuilder.rock(terrain: Terrain, position: Vector3, size: number, rng: Random)
	terrain:FillBall(position, size, M.Rock)
	for _ = 1, 2 do
		local offset = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.3, 0.6), rng:NextNumber(-1, 1)) * size
		terrain:FillBall(position + offset, size * rng:NextNumber(0.45, 0.75), if rng:NextNumber() > 0.5 then M.Rock else M.Slate)
	end
end

function TerrainBuilder.styleTerrain(terrain: Terrain)
	-- Bright candy terrain (Config/Palette.Terrain): green grass, sandy paths,
	-- lavender cliffs and a turquoise river.
	for name, color in Palette.Terrain do
		terrain:SetMaterialColor((Enum.Material :: any)[name], color :: Color3)
	end
	terrain.WaterColor = Palette.Water.Color
	terrain.WaterTransparency = Palette.Water.Transparency
	terrain.WaterReflectance = Palette.Water.Reflectance
	terrain.WaterWaveSize = Palette.Water.WaveSize
	terrain.WaterWaveSpeed = Palette.Water.WaveSpeed
end

function TerrainBuilder.build(): { Vector3 }
	local terrain = workspace.Terrain
	terrain:Clear()
	TerrainBuilder.styleTerrain(terrain)
	writeSurface(terrain)
	writeUnderside(terrain)
	carveCaves(terrain)
	return writeIslets(terrain)
end

-- Height of the walkable surface (terrain only) at x, z.
function TerrainBuilder.heightAt(x: number, z: number): number?
	local sample = TerrainBuilder.sample(x, z)
	return if sample then sample.height else nil
end

return TerrainBuilder
