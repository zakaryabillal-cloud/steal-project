--!strict
-- Builds THE RIFT: a dimensional tear hovering over a rune dais, ringed by
-- orbiting gimbal rings and debris, with a light pillar visible from the whole
-- island. Moving pieces are welded to anchored roots that clients rotate
-- locally (zero network cost).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Layout = require(Shared.Layout)
local Parts = require(script.Parent.Parts)
local TerrainBuilder = require(script.Parent.TerrainBuilder)

local RiftBuilder = {}

local M = Enum.Material
local C = Layout.Colors

local PARTICLE_SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local PARTICLE_VORTEX = "rbxasset://textures/particles/forcefield_vortex_main.dds"

local function root(name: string, cf: CFrame, parent: Instance): Part
	return Parts.block({
		size = Vector3.new(1, 1, 1),
		cf = cf,
		transparency = 1,
		collide = false,
		shadow = false,
		name = name,
		parent = parent,
	})
end

local function buildDais(model: Model)
	local y = Layout.DaisTopY
	local floor = Layout.BasinY
	local folder = Parts.folder("Dais", model)
	Parts.cylinder({ size = Vector3.new(31, y - floor, 31), cf = CFrame.new(0, floor + (y - floor - 1) / 2, 0), color = C.StoneDark, material = M.Slate, parent = folder })
	Parts.cylinder({ size = Vector3.new(27, 1.2, 27), cf = CFrame.new(0, y - 0.6, 0), color = C.Stone, material = M.Slate, parent = folder })
	Parts.cylinder({ size = Vector3.new(27.8, 1, 27.8), cf = CFrame.new(0, y - 0.75, 0), color = C.Rift, material = M.Neon, parent = folder, name = "DaisRing" })
	Parts.cylinder({ size = Vector3.new(15, 1.2, 15), cf = CFrame.new(0, y - 0.3, 0), color = C.StoneLight, material = M.Marble, parent = folder })
	Parts.cylinder({ size = Vector3.new(15.8, 1.2, 15.8), cf = CFrame.new(0, y - 0.48, 0), color = C.RiftCore, material = M.Neon, parent = folder, name = "InnerRing" })
	-- Star glyph inlaid in the dais.
	for i = 0, 3 do
		Parts.block({
			size = Vector3.new(0.5, 0.1, 12),
			cf = CFrame.new(0, y + 0.36, 0) * CFrame.Angles(0, math.rad(i * 45), 0),
			color = C.Rift,
			material = M.Neon,
			collide = false,
			parent = folder,
			name = "Glyph",
		})
	end
	-- Rune circle on the basin floor.
	local segments = 28
	for i = 0, segments - 1 do
		local a = (i / segments) * math.pi * 2
		local r = 34
		Parts.block({
			size = Vector3.new(0.6, 0.12, 2 * r * math.sin(math.pi / segments) * 0.82),
			cf = CFrame.new(math.cos(a) * r, floor + 0.35, math.sin(a) * r) * CFrame.Angles(0, -a, 0),
			color = C.Rift,
			material = M.Neon,
			transparency = 0.15,
			collide = false,
			shadow = false,
			parent = folder,
			name = "RuneCircle",
		})
	end
end

local function buildTear(model: Model)
	local core = Layout.RiftCore
	local tearRoot = root("TearRoot", CFrame.new(core), model)

	local tear = Parts.ellipsoid({ size = Vector3.new(13, Layout.RiftHeight - 4, 2.2), cf = CFrame.new(core), color = C.RiftCore, material = M.Neon, collide = false, shadow = false, parent = model, name = "Tear" })
	local dark = Parts.ellipsoid({ size = Vector3.new(8.5, Layout.RiftHeight - 10, 2.7), cf = CFrame.new(core), color = Color3.fromRGB(8, 4, 18), collide = false, shadow = false, parent = model, name = "TearDark" })
	local glow = Parts.ellipsoid({ size = Vector3.new(24, Layout.RiftHeight + 10, 6), cf = CFrame.new(core), color = C.Rift, material = M.ForceField, collide = false, shadow = false, parent = model, name = "TearGlow" })
	local halo = Parts.ellipsoid({ size = Vector3.new(36, Layout.RiftHeight + 22, 10), cf = CFrame.new(core), color = Color3.fromRGB(150, 90, 255), material = M.ForceField, transparency = 0.5, collide = false, shadow = false, parent = model, name = "TearHalo" })
	for _, part in { tear, dark, glow, halo } do
		Parts.weldTo(tearRoot, part)
	end

	local light = Parts.light(tearRoot, C.Rift, 60, 2.4)
	light.Name = "RiftLight"

	-- Particles drawn into the tear.
	local shell = Parts.ball({ size = Vector3.one * 46, cf = CFrame.new(core), transparency = 1, collide = false, shadow = false, parent = model, name = "InflowShell" })
	Parts.weldTo(tearRoot, shell)
	local inflow = Instance.new("ParticleEmitter")
	inflow.Name = "Inflow"
	inflow.Texture = PARTICLE_SPARKLE
	inflow.Color = ColorSequence.new(Color3.fromRGB(240, 220, 255), C.Rift)
	inflow.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.2, 0.9),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	inflow.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.2),
		NumberSequenceKeypoint.new(1, 0.6),
	})
	inflow.Lifetime = NumberRange.new(1.6, 2.2)
	inflow.Speed = NumberRange.new(10, 14)
	inflow.Rate = 30
	inflow.LightEmission = 1
	inflow.LightInfluence = 0
	inflow.Shape = Enum.ParticleEmitterShape.Sphere
	inflow.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	inflow.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	inflow.Parent = shell

	local wisps = Instance.new("ParticleEmitter")
	wisps.Name = "Wisps"
	wisps.Texture = PARTICLE_VORTEX
	wisps.Color = ColorSequence.new(C.Rift, Color3.fromRGB(110, 200, 255))
	wisps.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 6),
		NumberSequenceKeypoint.new(1, 14),
	})
	wisps.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.75),
		NumberSequenceKeypoint.new(1, 1),
	})
	wisps.Lifetime = NumberRange.new(2.5, 3.5)
	wisps.Speed = NumberRange.new(0.5, 1.5)
	wisps.RotSpeed = NumberRange.new(-40, 40)
	wisps.Rotation = NumberRange.new(0, 360)
	wisps.Rate = 3
	wisps.LightEmission = 1
	wisps.LightInfluence = 0
	wisps.Parent = tearRoot

	local hum = Instance.new("Sound")
	hum.Name = "Hum"
	hum.RollOffMode = Enum.RollOffMode.InverseTapered
	hum.RollOffMinDistance = 30
	hum.RollOffMaxDistance = 260
	hum.Looped = true
	hum.Parent = tearRoot

	-- Energy column feeding the dais.
	local top = Parts.attachment(tearRoot, Vector3.new(0, -(Layout.RiftHeight / 2) + 6, 0), "ColumnTop")
	local bottom = Parts.attachment(tearRoot, Vector3.new(0, Layout.DaisTopY - core.Y, 0), "ColumnBottom")
	local column = Instance.new("Beam")
	column.Name = "Column"
	column.Attachment0 = top
	column.Attachment1 = bottom
	column.Width0 = 3
	column.Width1 = 7
	column.Color = ColorSequence.new(C.RiftCore, C.Rift)
	column.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 0.65),
	})
	column.LightEmission = 1
	column.LightInfluence = 0
	column.FaceCamera = true
	column.Segments = 1
	column.Parent = tearRoot

	-- Sky pillar: a landmark visible from every Sanctuary.
	local pillarTop = core.Y + Layout.RiftHeight / 2 + 4
	Parts.cylinder({
		size = Vector3.new(3.2, 520, 3.2),
		cf = CFrame.new(0, pillarTop + 260, 0),
		color = C.Rift,
		material = M.Neon,
		transparency = 0.55,
		collide = false,
		shadow = false,
		parent = model,
		name = "SkyPillar",
	})
end

local function buildRings(model: Model)
	local core = Layout.RiftCore
	local specs = {
		{ radius = 19, width = 1.1, color = Color3.fromRGB(205, 160, 255), tilt = CFrame.Angles(math.rad(72), 0, math.rad(8)) },
		{ radius = 25, width = 0.8, color = Color3.fromRGB(120, 210, 255), tilt = CFrame.Angles(math.rad(-58), math.rad(30), 0) },
		{ radius = 31, width = 0.6, color = Color3.fromRGB(255, 150, 220), tilt = CFrame.Angles(math.rad(14), 0, math.rad(-20)) },
	}
	for i, spec in specs do
		local ringRoot = root("Ring" .. i, CFrame.new(core) * spec.tilt, model)
		ringRoot:SetAttribute("Radius", spec.radius)
		Parts.beamRing(ringRoot, CFrame.identity, spec.radius, spec.width, spec.color, 0.05)
		-- Rune nodes riding the ring.
		for k = 0, 3 do
			local a = k * math.pi / 2
			local node = Parts.block({
				size = Vector3.one * (2.2 - i * 0.3),
				cf = ringRoot.CFrame * CFrame.new(math.cos(a) * spec.radius, 0, math.sin(a) * spec.radius) * CFrame.Angles(math.rad(45), a, math.rad(45)),
				color = spec.color,
				material = M.Neon,
				collide = false,
				shadow = false,
				parent = model,
				name = "RingNode",
			})
			Parts.weldTo(ringRoot, node)
		end
	end
end

local function buildDebris(model: Model)
	local core = Layout.RiftCore
	local debrisRoot = root("DebrisRoot", CFrame.new(core.X, 0, core.Z), model)
	local rng = Random.new(91)
	for i = 1, 14 do
		local a = (i / 14) * math.pi * 2 + rng:NextNumber(-0.15, 0.15)
		local r = rng:NextNumber(36, 46)
		local y = rng:NextNumber(30, 64)
		local size = Vector3.new(rng:NextNumber(2.5, 5.5), rng:NextNumber(2, 4.5), rng:NextNumber(2.5, 5))
		local rock = Parts.block({
			size = size,
			cf = CFrame.new(math.cos(a) * r, y, math.sin(a) * r) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6)),
			color = if i % 3 == 0 then C.Stone else C.StoneDark,
			material = M.Slate,
			collide = false,
			parent = model,
			name = "Debris",
		})
		Parts.weldTo(debrisRoot, rock)
		if i % 4 == 0 then
			local crystal = Parts.block({
				size = Vector3.new(0.9, 2.6, 0.9),
				cf = rock.CFrame * CFrame.new(0, size.Y / 2 + 0.8, 0) * CFrame.Angles(0, math.rad(45), math.rad(12)),
				color = C.Rift,
				material = M.Neon,
				collide = false,
				shadow = false,
				parent = model,
				name = "DebrisCrystal",
			})
			Parts.weldTo(debrisRoot, crystal)
		end
	end
end

local function buildSpots(model: Model)
	local folder = Parts.folder("Spots", model)
	for index, spot in Layout.Spots do
		if spot.kind == "Ring" then
			local base = spot.position - Vector3.new(0, 3.6 + 0.5, 0)
			Parts.cylinder({ size = Vector3.new(6, 1, 6), cf = CFrame.new(base), color = C.Stone, material = M.Slate, parent = folder, name = "Pad" .. index })
			Parts.cylinder({ size = Vector3.new(6.6, 0.9, 6.6), cf = CFrame.new(base - Vector3.new(0, 0.08, 0)), color = C.Rift, material = M.Neon, parent = folder, name = "PadRing" })
		end
	end

	-- Floating islands with bounce pads below them.
	local bounce = Parts.folder("BouncePads", model)
	for i, island in Layout.FloatingIslands do
		Parts.cylinder({ size = Vector3.new(14, 2, 14), cf = CFrame.new(island), color = Color3.fromRGB(86, 168, 134), material = M.Grass, parent = folder, name = "Island" })
		Parts.cylinder({ size = Vector3.new(14.6, 1.2, 14.6), cf = CFrame.new(island - Vector3.new(0, 0.6, 0)), color = C.Rift, material = M.Neon, parent = folder, name = "IslandRim" })
		Parts.ellipsoid({ size = Vector3.new(13, 8, 13), cf = CFrame.new(island - Vector3.new(0, 4.5, 0)), color = C.StoneDark, material = M.Slate, parent = folder, name = "IslandRock" })
		Parts.ellipsoid({ size = Vector3.new(6, 7, 6), cf = CFrame.new(island - Vector3.new(0, 9.5, 0)), color = C.StoneDark, material = M.Slate, parent = folder, name = "IslandRock" })

		local dir = Vector3.new(island.X, 0, island.Z).Unit
		local padPos = dir * 18 + Vector3.new(0, Layout.BasinY + 0.3, 0)
		local pad = Parts.cylinder({ size = Vector3.new(5, 0.6, 5), cf = CFrame.new(padPos), color = Color3.fromRGB(120, 230, 255), material = M.Neon, parent = bounce, name = "BouncePad" .. i })
		pad:SetAttribute("Launch", Parts.launchVelocity(padPos + Vector3.new(0, 3, 0), island + Vector3.new(-dir.X * 2, 4, -dir.Z * 2), 86))
		Parts.cylinder({ size = Vector3.new(6.2, 0.5, 6.2), cf = CFrame.new(padPos - Vector3.new(0, 0.12, 0)), color = C.StoneLight, material = M.Slate, parent = bounce, name = "BounceRim" })
	end
end

local function buildMonoliths(model: Model)
	local folder = Parts.folder("Monoliths", model)
	for i = 0, 7 do
		local a = math.rad(i * 45)
		local r = 49
		local x, z = math.cos(a) * r, math.sin(a) * r
		local ground = TerrainBuilder.heightAt(x, z) or Layout.GroundY
		local height = 13 + (i % 2) * 4
		local cf = CFrame.lookAt(Vector3.new(x, ground + height / 2 - 1, z), Vector3.new(0, ground + height / 2 - 1, 0)) * CFrame.Angles(0, 0, math.rad((i % 3 - 1) * 4))
		Parts.block({ size = Vector3.new(4, height, 2.4), cf = cf, color = C.StoneDark, material = M.Slate, parent = folder, name = "Monolith" })
		Parts.block({ size = Vector3.new(0.6, height * 0.7, 0.2), cf = cf * CFrame.new(0, 0, -1.25), color = C.Rift, material = M.Neon, collide = false, parent = folder, name = "Rune" })
		Parts.block({ size = Vector3.new(1.6, 0.6, 0.2), cf = cf * CFrame.new(0, height * 0.2, -1.25), color = C.Rift, material = M.Neon, collide = false, parent = folder, name = "Rune" })
		Parts.block({ size = Vector3.new(4.6, 1, 3), cf = cf * CFrame.new(0, height / 2 + 0.3, 0), color = C.Stone, material = M.Slate, parent = folder, name = "Cap" })
	end
end

-- Crystal outcrops and glowing energy cracks so the basin floor is never empty.
local function buildBasinDetails(model: Model)
	local folder = Parts.folder("BasinDetails", model)
	local floor = Layout.BasinY
	local rng = Random.new(5150)
	for i = 0, 3 do
		local a = math.rad(45 + i * 90)
		local center = Vector3.new(math.cos(a) * 34, floor, math.sin(a) * 34)
		for k = 1, 4 do
			local h = if k == 1 then 7 else rng:NextNumber(2.5, 4.5)
			local offset = if k == 1 then Vector3.zero else Vector3.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2))
			Parts.block({
				size = Vector3.new(h * 0.24, h, h * 0.24),
				cf = CFrame.new(center + offset) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 3), rng:NextNumber(-0.3, 0.3)) * CFrame.new(0, h / 2 - 0.5, 0),
				color = if k % 2 == 1 then C.Rift else Color3.fromRGB(120, 210, 255),
				material = if k % 2 == 1 then M.Neon else M.Glass,
				transparency = if k % 2 == 1 then 0 else 0.2,
				shadow = false,
				parent = folder,
				name = "BasinCrystal",
			})
		end
	end
	-- Energy cracks radiating from the dais (skipping the bounce-pad axis).
	for i = 0, 7 do
		local base = i * 45
		if base % 180 == 0 then
			continue
		end
		local a = math.rad(base)
		local r0 = 15.5
		for segment = 1, 3 do
			local wobble = math.rad(((segment % 2) * 2 - 1) * 6)
			local dir = Vector3.new(math.cos(a + wobble), 0, math.sin(a + wobble))
			local length = 5
			local mid = Vector3.new(math.cos(a) * (r0 + length / 2), floor + 0.25, math.sin(a) * (r0 + length / 2))
			Parts.block({
				size = Vector3.new(0.35, 0.12, length),
				cf = CFrame.lookAt(mid, mid + dir),
				color = C.Rift,
				material = M.Neon,
				transparency = 0.1 + segment * 0.15,
				collide = false,
				shadow = false,
				parent = folder,
				name = "Crack",
			})
			r0 += length - 0.3
		end
	end
end

function RiftBuilder.build(parent: Instance): Model
	local model = Parts.model("Rift", parent)
	buildDais(model)
	buildTear(model)
	buildRings(model)
	buildDebris(model)
	buildSpots(model)
	buildMonoliths(model)
	buildBasinDetails(model)
	return model
end

return RiftBuilder
