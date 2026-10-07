--!strict
-- Dresses the island: bridges and fords over the river, lamp-lit ring road,
-- stylised cosmic trees, crystal clusters, ruins, rocks and "starfalls"
-- pouring off the island edge. Placement is deterministic (seeded) and avoids
-- paths, the river and Sanctuary footprints.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Layout = require(Shared.Layout)
local Parts = require(script.Parent.Parts)
local TerrainBuilder = require(script.Parent.TerrainBuilder)

local Props = {}

local M = Enum.Material
local C = Layout.Colors
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

local TREE_STYLES = {
	{ canopy = Color3.fromRGB(240, 156, 206), fruit = Color3.fromRGB(255, 220, 240) },
	{ canopy = Color3.fromRGB(176, 150, 250), fruit = Color3.fromRGB(150, 230, 255) },
	{ canopy = Color3.fromRGB(96, 206, 182), fruit = Color3.fromRGB(255, 236, 150) },
	{ canopy = Color3.fromRGB(130, 186, 255), fruit = Color3.fromRGB(255, 180, 230) },
}

local CRYSTAL_COLORS = {
	Color3.fromRGB(190, 130, 255),
	Color3.fromRGB(110, 220, 255),
	Color3.fromRGB(255, 130, 210),
}

local PLOT_CENTERS: { Vector3 } = {}
for i = 1, Layout.PlotCount do
	table.insert(PLOT_CENTERS, Layout.plotCFrame(i).Position)
end

local function nearSanctuary(x: number, z: number, margin: number): boolean
	for i, center in PLOT_CENTERS do
		local dx, dz = x - center.X, z - center.Z
		if dx * dx + dz * dz < margin * margin then
			return true
		end
		-- Ramp corridor toward the road.
		local foot = Layout.rampFoot(i)
		local fx, fz = x - foot.X, z - foot.Z
		if fx * fx + fz * fz < 196 then
			return true
		end
	end
	return false
end

local function radialCFrame(angle: number, r: number, y: number): CFrame
	local position = Vector3.new(math.cos(angle) * r, y, math.sin(angle) * r)
	return CFrame.lookAt(position, Vector3.new(0, y, 0))
end

----------------------------------------------------------------------------

local function buildBridges(folder: Folder)
	for _, deg in Layout.BridgeAngles do
		local a = math.rad(deg)
		local model = Parts.model("Bridge", folder)
		local center = radialCFrame(a, Layout.RiverCenter, Layout.GroundY + 0.2)
		local length = Layout.RiverOuter - Layout.RiverInner + 14
		Parts.block({ size = Vector3.new(11, 1.4, length), cf = center, color = C.Stone, material = M.Cobblestone, parent = model, name = "Deck" })
		Parts.block({ size = Vector3.new(11.6, 0.6, length + 0.4), cf = center * CFrame.new(0, -0.9, 0), color = C.Trim, material = M.SmoothPlastic, parent = model })
		for _, side in { -1, 1 } do
			Parts.block({ size = Vector3.new(0.9, 2.2, length - 2), cf = center * CFrame.new(side * 5.3, 1.8, 0), color = C.StoneLight, material = M.Slate, parent = model, name = "Rail" })
			for k = -2, 2 do
				Parts.block({ size = Vector3.new(1.4, 3, 1.4), cf = center * CFrame.new(side * 5.3, 2.2, k * (length - 4) / 4), color = C.Stone, material = M.Slate, parent = model })
				Parts.block({ size = Vector3.new(0.7, 0.7, 0.7), cf = center * CFrame.new(side * 5.3, 4.05, k * (length - 4) / 4) * CFrame.Angles(math.rad(45), 0, math.rad(45)), color = C.Rift, material = M.Neon, collide = false, shadow = false, parent = model })
			end
		end
		for _, z in { -6, 6 } do
			Parts.cylinder({ size = Vector3.new(3.4, 14, 3.4), cf = center * CFrame.new(0, -7.6, z), color = C.StoneDark, material = M.Slate, parent = model, name = "Pier" })
		end
		-- Lanterns at both ends.
		for _, z in { -(length / 2 - 1.5), length / 2 - 1.5 } do
			for _, side in { -1, 1 } do
				local base = center * CFrame.new(side * 5.3, 3.7, z)
				Parts.cylinder({ size = Vector3.new(0.5, 3, 0.5), cf = base * CFrame.new(0, 1.5, 0), color = C.Trim, material = M.Metal, parent = model })
				local glow = Parts.ball({ size = Vector3.one * 1.4, cf = base * CFrame.new(0, 3.4, 0), color = Color3.fromRGB(255, 214, 150), material = M.Neon, collide = false, shadow = false, parent = model })
				if side == 1 then
					Parts.light(glow, Color3.fromRGB(255, 200, 140), 20, 1.1)
				end
			end
		end
	end
end

local function buildFords(folder: Folder)
	for _, deg in Layout.FordAngles do
		local a = math.rad(deg)
		local model = Parts.model("Ford", folder)
		local stones = 5
		for k = 0, stones - 1 do
			local r = Layout.RiverInner + 0.5 + k * ((Layout.RiverOuter - Layout.RiverInner - 1) / (stones - 1))
			local lateral = if k % 2 == 0 then 1.2 else -1.2
			local cf = radialCFrame(a, r, 0) * CFrame.new(lateral, 0, 0)
			local top = Layout.WaterY + 1.4
			local base = CFrame.new(cf.Position.X, top - 6, cf.Position.Z)
			Parts.cylinder({ size = Vector3.new(4, 12, 4), cf = base, color = C.StoneDark, material = M.Slate, parent = model, name = "Stone" })
			Parts.cylinder({ size = Vector3.new(4.2, 0.4, 4.2), cf = CFrame.new(cf.Position.X, top + 0.05, cf.Position.Z), color = C.Stone, material = M.Slate, parent = model })
			Parts.cylinder({ size = Vector3.new(1.6, 0.42, 1.6), cf = CFrame.new(cf.Position.X, top + 0.06, cf.Position.Z), color = Color3.fromRGB(120, 230, 255), material = M.Neon, collide = false, shadow = false, parent = model })
		end
	end
end

local function lampPost(folder: Instance, position: Vector3, facing: Vector3)
	local model = Parts.model("Lamp", folder)
	local cf = CFrame.lookAt(position, position + facing)
	Parts.cylinder({ size = Vector3.new(1.4, 0.8, 1.4), cf = cf * CFrame.new(0, 0.4, 0), color = C.StoneDark, material = M.Slate, parent = model })
	Parts.cylinder({ size = Vector3.new(0.6, 8, 0.6), cf = cf * CFrame.new(0, 4.4, 0), color = C.Trim, material = M.Metal, parent = model })
	Parts.block({ size = Vector3.new(0.35, 0.35, 2.2), cf = cf * CFrame.new(0, 8.2, -0.9), color = C.Trim, material = M.Metal, parent = model })
	local glow = Parts.ball({ size = Vector3.one * 1.5, cf = cf * CFrame.new(0, 7.3, -1.8), color = Color3.fromRGB(200, 170, 255), material = M.Neon, collide = false, shadow = false, parent = model })
	Parts.light(glow, Color3.fromRGB(190, 160, 255), 18, 1)
end

local function buildRoadLamps(folder: Folder)
	for i = 1, Layout.PlotCount do
		for _, offset in { -11.25, 11.25 } do
			local a = Layout.plotAngle(i) + math.rad(offset)
			local r = Layout.RingRoadRadius + 5.2
			local position = Vector3.new(math.cos(a) * r, Layout.GroundY, math.sin(a) * r)
			lampPost(folder, position, -Vector3.new(math.cos(a), 0, math.sin(a)))
		end
	end
end

local function tree(folder: Instance, position: Vector3, rng: Random, scale: number)
	local style = TREE_STYLES[rng:NextInteger(1, #TREE_STYLES)]
	local model = Parts.model("Tree", folder)
	local tilt = CFrame.Angles(rng:NextNumber(-0.08, 0.08), rng:NextNumber(0, 6.28), rng:NextNumber(-0.08, 0.08))
	local base = CFrame.new(position) * tilt
	local trunkH = 8 * scale
	Parts.cylinder({ size = Vector3.new(1.7, trunkH, 1.7) * Vector3.new(scale, 1, scale), cf = base * CFrame.new(0, trunkH / 2 - 0.5, 0), color = Color3.fromRGB(96, 70, 84), material = M.Wood, parent = model, name = "Trunk" })
	local bend = base * CFrame.new(0, trunkH - 0.5, 0) * CFrame.Angles(rng:NextNumber(-0.25, 0.25), 0, rng:NextNumber(-0.25, 0.25))
	Parts.cylinder({ size = Vector3.new(1.1 * scale, 5 * scale, 1.1 * scale), cf = bend * CFrame.new(0, 2.3 * scale, 0), color = Color3.fromRGB(96, 70, 84), material = M.Wood, parent = model })
	local top = bend * CFrame.new(0, 5 * scale, 0)
	local canopies = {
		{ offset = Vector3.new(0, 1.5, 0), size = 9 },
		{ offset = Vector3.new(3, 0.2, 1.2), size = 6.5 },
		{ offset = Vector3.new(-2.6, 0.4, -1.8), size = 6 },
		{ offset = Vector3.new(0.6, 3.6, -0.8), size = 5.5 },
	}
	for i, c in canopies do
		local color = style.canopy:Lerp(Color3.new(1, 1, 1), (i - 1) * 0.04)
		Parts.ball({ size = Vector3.one * c.size * scale, cf = top * CFrame.new(c.offset * scale), color = color, material = M.SmoothPlastic, parent = model, name = "Canopy" })
	end
	for _ = 1, 3 do
		local angle = rng:NextNumber(0, math.pi * 2)
		Parts.ball({
			size = Vector3.one * 0.7 * scale,
			cf = top * CFrame.new(math.cos(angle) * 3.4 * scale, -2.6 * scale, math.sin(angle) * 3.4 * scale),
			color = style.fruit,
			material = M.Neon,
			collide = false,
			shadow = false,
			parent = model,
			name = "Fruit",
		})
	end
end

local function crystalCluster(folder: Instance, position: Vector3, rng: Random, withLight: boolean)
	local color = CRYSTAL_COLORS[rng:NextInteger(1, #CRYSTAL_COLORS)]
	local model = Parts.model("Crystals", folder)
	local base = CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
	local count = rng:NextInteger(3, 5)
	local main: Part? = nil
	for k = 1, count do
		local h = if k == 1 then rng:NextNumber(6, 9) else rng:NextNumber(2.5, 5)
		local w = h * 0.24
		local angle = (k / count) * math.pi * 2
		local offset = if k == 1 then Vector3.zero else Vector3.new(math.cos(angle) * 1.4, 0, math.sin(angle) * 1.4)
		local tiltOut = if k == 1 then 0 else 0.35
		local part = Parts.block({
			size = Vector3.new(w, h, w),
			cf = base * CFrame.new(offset) * CFrame.Angles(math.sin(angle) * tiltOut, math.rad(45), -math.cos(angle) * tiltOut) * CFrame.new(0, h / 2 - 0.6, 0),
			color = color,
			material = if k % 2 == 1 then M.Neon else M.Glass,
			transparency = if k % 2 == 1 then 0 else 0.15,
			shadow = false,
			parent = model,
			name = "Crystal",
		})
		if k == 1 then
			main = part
		end
	end
	if withLight and main then
		Parts.light(main, color, 16, 1.2)
	end
end

local function brokenColumn(folder: Instance, position: Vector3, rng: Random)
	local h = rng:NextNumber(4, 11)
	local base = CFrame.new(position) * CFrame.Angles(rng:NextNumber(-0.06, 0.06), rng:NextNumber(0, 6.28), rng:NextNumber(-0.06, 0.06))
	Parts.cylinder({ size = Vector3.new(3.4, 1, 3.4), cf = base * CFrame.new(0, 0.2, 0), color = C.Stone, material = M.Slate, parent = folder })
	Parts.cylinder({ size = Vector3.new(2.4, h, 2.4), cf = base * CFrame.new(0, h / 2, 0), color = C.StoneLight, material = M.Marble, parent = folder })
	if rng:NextNumber() > 0.5 then
		-- Fallen drum lying next to it.
		Parts.cylinder({ size = Vector3.new(2.4, 3.5, 2.4), cf = base * CFrame.new(3.4, 1, 0.8) * CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(0, rng:NextNumber(0, 1), 0), color = C.StoneLight, material = M.Marble, parent = folder })
	end
end

local function archway(folder: Instance, angle: number, r: number, broken: boolean)
	local ground = TerrainBuilder.heightAt(math.cos(angle) * r, math.sin(angle) * r) or Layout.GroundY
	local cf = radialCFrame(angle, r, ground - 0.5) * CFrame.Angles(0, math.rad(90), 0)
	local model = Parts.model("Archway", folder)
	local span = 8
	for _, side in { -1, 1 } do
		local height = if broken and side == 1 then 7 else 15
		Parts.block({ size = Vector3.new(3, height, 3), cf = cf * CFrame.new(0, height / 2, side * span), color = C.StoneLight, material = M.Slate, parent = model })
		Parts.block({ size = Vector3.new(3.8, 1, 3.8), cf = cf * CFrame.new(0, 0.5, side * span), color = C.Stone, material = M.Slate, parent = model })
		Parts.block({ size = Vector3.new(0.25, height * 0.6, 0.6), cf = cf * CFrame.new(-1.55, height * 0.45, side * span), color = C.Rift, material = M.Neon, collide = false, shadow = false, parent = model })
	end
	if broken then
		Parts.block({ size = Vector3.new(3, 2.4, span * 2 + 3), cf = cf * CFrame.new(5, 1.4, -2) * CFrame.Angles(math.rad(8), math.rad(25), math.rad(-12)), color = C.StoneLight, material = M.Slate, parent = model })
	else
		Parts.block({ size = Vector3.new(3.4, 2.6, span * 2 + 4), cf = cf * CFrame.new(0, 16.3, 0), color = C.StoneLight, material = M.Slate, parent = model })
		Parts.block({ size = Vector3.new(1.6, 1.6, 1.6), cf = cf * CFrame.new(-1.8, 16.3, 0) * CFrame.Angles(math.rad(45), 0, 0), color = C.Rift, material = M.Neon, collide = false, shadow = false, parent = model })
	end
end

local function starfall(folder: Instance, angle: number)
	local r = Layout.IslandRadius - 12
	local ground = TerrainBuilder.heightAt(math.cos(angle) * r, math.sin(angle) * r) or 12
	local origin = Parts.block({
		size = Vector3.new(6, 1, 6),
		cf = CFrame.new(math.cos(angle) * (r + 10), ground - 1, math.sin(angle) * (r + 10)),
		transparency = 1,
		collide = false,
		shadow = false,
		parent = folder,
		name = "Starfall",
	})
	origin.CanQuery = false
	local a0 = Parts.attachment(origin, Vector3.zero, "Top")
	local a1 = Parts.attachment(origin, Vector3.new(0, -160, 0), "Bottom")
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = 7
	beam.Width1 = 2
	beam.Color = ColorSequence.new(Color3.fromRGB(200, 170, 255), Color3.fromRGB(110, 210, 255))
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Parent = origin
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = SPARKLE
	sparks.Color = ColorSequence.new(Color3.fromRGB(230, 210, 255))
	sparks.Size = NumberSequence.new(0.6)
	sparks.Lifetime = NumberRange.new(3, 4)
	sparks.Speed = NumberRange.new(10, 18)
	sparks.EmissionDirection = Enum.NormalId.Bottom
	sparks.SpreadAngle = Vector2.new(8, 8)
	sparks.Rate = 8
	sparks.LightEmission = 1
	sparks.Parent = origin
end

local function buildVegetation(folder: Folder)
	local rng = Random.new(4242)
	local terrain = workspace.Terrain
	local placed: { Vector3 } = {}
	local function free(x: number, z: number, spacing: number): boolean
		for _, p in placed do
			local dx, dz = p.X - x, p.Z - z
			if dx * dx + dz * dz < spacing * spacing then
				return false
			end
		end
		return true
	end

	local function tryPlace(minR: number, maxR: number, spacing: number): Vector3?
		for _ = 1, 30 do
			local a = rng:NextNumber(0, math.pi * 2)
			local r = rng:NextNumber(minR, maxR)
			local x, z = math.cos(a) * r, math.sin(a) * r
			local sample = TerrainBuilder.sample(x, z)
			if sample and sample.path == nil and sample.zone ~= "river" and not nearSanctuary(x, z, 50) and free(x, z, spacing) then
				local p = Vector3.new(x, sample.height, z)
				table.insert(placed, p)
				return p
			end
		end
		return nil
	end

	-- Trees: outer ring and a few on the meadow.
	for _ = 1, 44 do
		local p = tryPlace(122, 214, 11)
		if p then
			tree(folder, p - Vector3.new(0, 0.6, 0), rng, rng:NextNumber(0.85, 1.25))
		end
	end
	for _ = 1, 9 do
		local p = tryPlace(64, 82, 13)
		if p then
			tree(folder, p - Vector3.new(0, 0.6, 0), rng, rng:NextNumber(0.7, 0.95))
		end
	end

	-- Crystal clusters.
	for i = 1, 22 do
		local p = tryPlace(62, 220, 9)
		if p then
			crystalCluster(folder, p, rng, i % 3 == 0)
		end
	end

	-- Rock clusters (terrain).
	for _ = 1, 34 do
		local p = tryPlace(60, 222, 8)
		if p then
			TerrainBuilder.rock(terrain, p + Vector3.new(0, 1, 0), rng:NextNumber(3, 6.5), rng)
		end
	end
	-- Riverbank boulders.
	for k = 0, 15 do
		local a = math.rad(k * 22.5 + 11)
		local r = if k % 2 == 0 then Layout.RiverInner - 1 else Layout.RiverOuter + 1
		local x, z = math.cos(a) * r, math.sin(a) * r
		local sample = TerrainBuilder.sample(x, z)
		if sample and sample.path == nil then
			TerrainBuilder.rock(terrain, Vector3.new(x, Layout.WaterY, z), rng:NextNumber(3, 5), rng)
		end
	end

	-- Bushes.
	for _ = 1, 40 do
		local p = tryPlace(60, 218, 5)
		if p then
			local style = TREE_STYLES[rng:NextInteger(1, #TREE_STYLES)]
			local size = rng:NextNumber(2.5, 4)
			Parts.ball({ size = Vector3.one * size, cf = CFrame.new(p + Vector3.new(0, size * 0.25, 0)), color = style.canopy:Lerp(Color3.fromRGB(70, 150, 120), 0.5), parent = folder, name = "Bush" })
			Parts.ball({ size = Vector3.one * size * 0.7, cf = CFrame.new(p + Vector3.new(size * 0.45, size * 0.12, 0.3)), color = style.canopy:Lerp(Color3.fromRGB(70, 150, 120), 0.4), parent = folder, name = "Bush" })
		end
	end
end

local function buildRuins(folder: Folder)
	local rng = Random.new(777)
	for _, deg in Layout.BridgeAngles do
		archway(folder, math.rad(deg), 72, false)
	end
	for _, deg in Layout.FordAngles do
		archway(folder, math.rad(deg), 72, true)
	end
	-- Colonnade remains along the ridges between Sanctuaries.
	for i = 1, Layout.PlotCount do
		local a = Layout.plotAngle(i) + math.rad(22.5)
		for k = 0, 2 do
			local r = 150 + k * 18
			local x, z = math.cos(a) * r, math.sin(a) * r
			local ground = TerrainBuilder.heightAt(x, z)
			if ground then
				brokenColumn(folder, Vector3.new(x, ground - 0.4, z), rng)
			end
		end
	end
end

function Props.build(parent: Instance, isletTops: { Vector3 })
	local world = Parts.folder("Props", parent)
	buildBridges(Parts.folder("Bridges", world))
	buildFords(Parts.folder("Fords", world))
	buildRoadLamps(Parts.folder("Lamps", world))
	task.wait()
	buildVegetation(Parts.folder("Vegetation", world))
	task.wait()
	buildRuins(Parts.folder("Ruins", world))
	local edge = Parts.folder("Edge", world)
	for k = 0, 5 do
		starfall(edge, math.rad(k * 60 + 15))
	end
	-- Giant crystals on the distant islets.
	local rng = Random.new(99)
	for _, top in isletTops do
		crystalCluster(edge, top, rng, false)
		tree(edge, top + Vector3.new(6, -0.5, 4), rng, 1.1)
	end
end

return Props
