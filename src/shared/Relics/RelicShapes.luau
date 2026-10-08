--!strict
-- One builder per relic silhouette. Units are "relic units": the relic fits in
-- roughly a 3x3x3 box before rarity scaling. Every builder only describes
-- geometry + bespoke motion; rarity/mutation layers are added by RelicFactory.

local Factory = require(script.Parent.RelicFactory)

type Ctx = Factory.Ctx
type Env = Factory.Env

local M = Enum.Material
local rad = math.rad
local TEX = Factory.Textures

local Shapes: { [string]: (Ctx) -> () } = {}

local CORNER_UP = CFrame.Angles(rad(45), 0, rad(35.26))

local function damp(sharpness: number, dt: number): number
	return 1 - math.exp(-sharpness * dt)
end

-- Common: a glowing ember crystal with drifting splinters.
Shapes.EmberShard = function(ctx: Ctx)
	local def = ctx.def
	ctx:part({ kind = "Block", size = Vector3.new(0.5, 1.8, 0.5), cf = CFrame.Angles(0, rad(45), 0), color = def.glow, material = M.Neon, role = "glow" })
	ctx:part({ kind = "Block", size = Vector3.new(1, 2.2, 1), cf = CFrame.Angles(0, rad(45), 0), color = def.primary, material = M.Glass, transparency = 0.35, role = "body" })
	ctx:part({ kind = "Block", size = Vector3.new(0.72, 0.72, 0.72), cf = CFrame.new(0, 1.12, 0) * CORNER_UP, color = def.primary, material = M.Glass, transparency = 0.35, role = "body" })
	ctx:part({ kind = "Block", size = Vector3.new(0.6, 0.6, 0.6), cf = CFrame.new(0, -1.1, 0) * CORNER_UP, color = def.secondary, material = M.Glass, transparency = 0.2, role = "body" })

	local splinters = {}
	local layout = {
		{ r = 1.05, y = -0.3, tilt = -22, h = 1.1, phase = 0 },
		{ r = 1.0, y = 0.35, tilt = 18, h = 0.8, phase = 2.1 },
		{ r = 1.15, y = -0.7, tilt = 9, h = 0.65, phase = 4.2 },
	}
	for _, data in layout do
		local part = ctx:part({ kind = "Block", size = Vector3.new(0.32, data.h, 0.32), color = def.glow, material = M.Neon, role = "glow" })
		table.insert(splinters, { part = part, data = data })
	end
	ctx:animate(function(env: Env)
		for _, s in splinters do
			local d = s.data
			local angle = env.time * 0.7 + d.phase
			ctx:move(s.part, CFrame.Angles(0, angle, 0) * CFrame.new(d.r, d.y + math.sin(env.time * 1.6 + d.phase) * 0.12, 0) * CFrame.Angles(0, 0, rad(d.tilt)))
		end
	end)

	ctx:emitter({
		texture = TEX.spark,
		color = ColorSequence.new(Color3.fromRGB(255, 220, 140), def.primary),
		rate = 6,
		lifetime = NumberRange.new(0.6, 1.2),
		speed = NumberRange.new(0.6, 1.4),
		size = 0.16,
		spread = 40,
		acceleration = Vector3.new(0, 2, 0),
	})
end

-- Common: a seed sprouting two leaves, banded with living light.
Shapes.VerdantSeed = function(ctx: Ctx)
	local def = ctx.def
	ctx:part({ kind = "Ellipsoid", size = Vector3.new(1.5, 1.9, 1.5), color = Color3.fromRGB(122, 92, 70), role = "body" })
	ctx:part({ kind = "VCylinder", size = Vector3.new(1.56, 0.14, 1.56), cf = CFrame.new(0, -0.1, 0), color = def.glow, material = M.Neon, role = "glow" })
	ctx:part({ kind = "VCylinder", size = Vector3.new(1.36, 0.1, 1.36), cf = CFrame.new(0, 0.45, 0), color = def.glow, material = M.Neon, role = "glow" })
	ctx:part({ kind = "VCylinder", size = Vector3.new(0.16, 0.6, 0.16), cf = CFrame.new(0, 1.15, 0), color = def.primary, role = "body" })
	local leftLeaf = ctx:part({ kind = "Ellipsoid", size = Vector3.new(0.95, 0.1, 0.46), color = def.primary, role = "body" })
	local rightLeaf = ctx:part({ kind = "Ellipsoid", size = Vector3.new(0.95, 0.1, 0.46), color = def.primary, role = "body" })
	ctx:part({ kind = "Ball", size = Vector3.one * 0.22, cf = CFrame.new(0, 1.48, 0), color = def.glow, material = M.Neon, role = "glow" })

	ctx:animate(function(env: Env)
		local sway = math.sin(env.time * 1.8) * rad(9)
		ctx:move(leftLeaf, CFrame.new(-0.4, 1.38, 0) * CFrame.Angles(0, 0, rad(-28) - sway))
		ctx:move(rightLeaf, CFrame.new(0.4, 1.38, 0) * CFrame.Angles(0, 0, rad(28) - sway))
	end)

	ctx:emitter({
		texture = TEX.square,
		color = ColorSequence.new(def.glow, def.primary),
		rate = 2.5,
		lifetime = NumberRange.new(1.5, 2.5),
		speed = NumberRange.new(0.3, 0.7),
		size = 0.14,
		spread = 180,
		acceleration = Vector3.new(0, -0.4, 0),
		rotSpeed = NumberRange.new(-120, 120),
	})
end

-- Common: a luminous pearl inside a slowly breathing clam.
Shapes.TidePearl = function(ctx: Ctx)
	local def = ctx.def
	ctx:part({ kind = "Ball", size = Vector3.one * 0.85, color = def.glow, material = M.Neon, role = "glow" })
	ctx:part({ kind = "Ball", size = Vector3.one * 1.2, color = def.primary, material = M.Glass, transparency = 0.2, reflectance = 0.2, role = "body" })
	ctx:part({ kind = "Ellipsoid", size = Vector3.new(2.3, 0.42, 2.0), cf = CFrame.new(0, -0.82, 0), color = def.secondary, role = "body" })
	local top = ctx:part({ kind = "Ellipsoid", size = Vector3.new(2.3, 0.42, 2.0), color = def.secondary, role = "body" })
	ctx:ring({ radius = 1.55, width = 0.08, color = def.glow, cf = CFrame.new(0, -0.55, 0), transparency = 0.2 })

	ctx:animate(function(env: Env)
		local open = rad(28 + math.sin(env.time * 1.2) * 12)
		ctx:move(top, CFrame.new(0, 0.62, -1) * CFrame.Angles(-open, 0, 0) * CFrame.new(0, 0.2, 1))
	end)

	ctx:emitter({
		color = ColorSequence.new(Color3.fromRGB(230, 250, 255), def.glow),
		rate = 4,
		lifetime = NumberRange.new(1.2, 2),
		speed = NumberRange.new(0.4, 0.9),
		size = 0.18,
		spread = 25,
		acceleration = Vector3.new(0, 1.2, 0),
	})
end

-- Common: an arched stone tablet whose runes breathe light.
Shapes.RuneTablet = function(ctx: Ctx)
	local def = ctx.def
	ctx:part({ kind = "Block", size = Vector3.new(1.7, 2.0, 0.42), cf = CFrame.new(0, -0.2, 0), color = def.primary, material = M.Slate, role = "body" })
	ctx:part({ kind = "Cylinder", size = Vector3.new(0.42, 1.7, 1.7), cf = CFrame.new(0, 0.8, 0) * CFrame.Angles(0, rad(90), 0), color = def.primary, material = M.Slate, role = "body" })
	ctx:part({ kind = "Block", size = Vector3.new(1.9, 0.25, 0.55), cf = CFrame.new(0, -1.25, 0), color = def.secondary, material = M.Slate, role = "body" })

	local runes = {}
	-- Phase 5.5: glyphs frame the face (no cross: a tablet, not a tombstone).
	local glyphs = {
		{ size = Vector3.new(0.9, 0.1, 0.05), pos = Vector3.new(0, -0.72, 0) },
		{ size = Vector3.new(0.1, 0.32, 0.05), pos = Vector3.new(-0.62, -0.5, 0) },
		{ size = Vector3.new(0.1, 0.32, 0.05), pos = Vector3.new(0.62, -0.5, 0) },
		{ size = Vector3.new(0.5, 0.1, 0.05), pos = Vector3.new(0, 0.72, 0) },
		{ size = Vector3.new(0.26, 0.26, 0.05), pos = Vector3.new(0, 1.08, 0), diamond = true },
	}
	for _, side in { 0.22, -0.22 } do
		for _, glyph in glyphs do
			local cf = CFrame.new(glyph.pos + Vector3.new(0, 0, side))
			if (glyph :: any).diamond then
				cf *= CFrame.Angles(0, 0, rad(45))
			end
			table.insert(runes, ctx:part({ kind = "Block", size = glyph.size, cf = cf, color = def.glow, material = M.Neon, role = "glow" }))
		end
	end
	ctx:animate(function(env: Env)
		for i, rune in runes do
			rune.Transparency = 0.05 + (math.sin(env.time * 2.4 - i * 0.6) + 1) * 0.2
		end
	end)

	ctx:emitter({
		color = ColorSequence.new(def.glow),
		rate = 3,
		lifetime = NumberRange.new(1.5, 2.5),
		speed = NumberRange.new(0.1, 0.4),
		size = 0.12,
		spread = 180,
		acceleration = Vector3.new(0, 0.5, 0),
	})
end

-- Uncommon: a crystalline lotus whose petals breathe open and closed.
Shapes.FrostLotus = function(ctx: Ctx)
	local def = ctx.def
	ctx:part({ kind = "Ball", size = Vector3.one * 0.62, cf = CFrame.new(0, 0.1, 0), color = def.glow, material = M.Neon, role = "glow" })
	ctx:part({ kind = "Ellipsoid", size = Vector3.new(2.7, 0.12, 2.7), cf = CFrame.new(0, -0.3, 0), color = Color3.fromRGB(200, 240, 255), material = M.Ice, transparency = 0.2, role = "body" })

	local inner, outer = {}, {}
	for i = 0, 5 do
		table.insert(inner, { part = ctx:part({ kind = "Ellipsoid", size = Vector3.new(0.48, 0.12, 1.25), color = def.primary, material = M.Glass, transparency = 0.12, role = "body" }), angle = i * 60 })
	end
	for i = 0, 7 do
		table.insert(outer, { part = ctx:part({ kind = "Ellipsoid", size = Vector3.new(0.56, 0.12, 1.65), color = def.secondary, material = M.Glass, transparency = 0.18, role = "body" }), angle = i * 45 + 22.5 })
	end
	local function layout(t: number)
		local breathe = math.sin(t * 1.4)
		for _, petal in inner do
			ctx:move(petal.part, CFrame.Angles(0, rad(petal.angle), 0) * CFrame.new(0, 0.15, 0.5) * CFrame.Angles(rad(-42 - breathe * 7), 0, 0) * CFrame.new(0, 0, 0.45))
		end
		for _, petal in outer do
			ctx:move(petal.part, CFrame.Angles(0, rad(petal.angle), 0) * CFrame.new(0, -0.1, 0.75) * CFrame.Angles(rad(-16 - breathe * 4), 0, 0) * CFrame.new(0, 0, 0.6))
		end
	end
	layout(0)
	ctx:animate(function(env: Env)
		layout(env.time)
	end)

	ctx:emitter({
		color = ColorSequence.new(Color3.new(1, 1, 1), def.glow),
		rate = 5,
		lifetime = NumberRange.new(1.6, 2.6),
		speed = NumberRange.new(0.2, 0.5),
		size = 0.16,
		spread = 180,
		acceleration = Vector3.new(0, -0.6, 0),
		rotSpeed = NumberRange.new(-60, 60),
	})
end

-- Uncommon: a storm sealed in a crystal, lightning flickering inside.
Shapes.StormCrystal = function(ctx: Ctx)
	local def = ctx.def
	ctx:part({ kind = "Block", size = Vector3.new(1.15, 2.5, 1.15), cf = CFrame.Angles(0, rad(45), 0), color = def.primary, material = M.Glass, transparency = 0.45, role = "body" })
	ctx:part({ kind = "Block", size = Vector3.one * 0.82, cf = CFrame.new(0, 1.25, 0) * CORNER_UP, color = def.primary, material = M.Glass, transparency = 0.45, role = "body" })
	ctx:part({ kind = "Block", size = Vector3.one * 0.82, cf = CFrame.new(0, -1.25, 0) * CORNER_UP, color = def.primary, material = M.Glass, transparency = 0.45, role = "body" })
	ctx:part({ kind = "Ball", size = Vector3.one * 0.6, cf = CFrame.new(0, -0.2, 0), color = def.glow, material = M.Neon, role = "glow" })
	ctx:part({ kind = "Ellipsoid", size = Vector3.new(0.92, 0.5, 0.92), cf = CFrame.new(0, 0.4, 0), color = Color3.fromRGB(90, 100, 140), transparency = 0.25, role = "body" })

	local bolts = {}
	local segments = {
		{ pos = Vector3.new(0.05, 0.1, 0), tilt = 25 },
		{ pos = Vector3.new(-0.05, -0.25, 0), tilt = -30 },
		{ pos = Vector3.new(0.06, -0.58, 0), tilt = 20 },
	}
	for _, seg in segments do
		table.insert(bolts, ctx:part({ kind = "Block", size = Vector3.new(0.07, 0.42, 0.07), cf = CFrame.new(seg.pos) * CFrame.Angles(0, 0, rad(seg.tilt)), color = Color3.fromRGB(240, 250, 255), material = M.Neon, role = "glow" }))
	end

	local clouds = {}
	for i = 1, 5 do
		table.insert(clouds, ctx:part({ kind = "Ellipsoid", size = Vector3.new(0.78, 0.42, 0.56), color = Color3.fromRGB(150, 160, 200), role = "body" }))
	end

	local rng = Random.new()
	local nextFlash = 0
	ctx:animate(function(env: Env)
		for i, cloud in clouds do
			local angle = env.time * 0.8 + i * (math.pi * 2 / 5)
			ctx:move(cloud, CFrame.new(math.cos(angle) * 1.25, 0.15 + math.sin(env.time * 2 + i) * 0.08, math.sin(angle) * 1.25) * CFrame.Angles(0, -angle, 0))
		end
		if env.time > nextFlash then
			nextFlash = env.time + rng:NextNumber(0.08, 0.5)
			local visible = rng:NextNumber() > 0.35
			for _, bolt in bolts do
				bolt.Transparency = if visible then 0 else 1
			end
		end
	end)

	ctx:emitter({
		texture = TEX.spark,
		color = ColorSequence.new(Color3.fromRGB(230, 240, 255)),
		rate = 5,
		lifetime = NumberRange.new(0.15, 0.3),
		speed = NumberRange.new(2, 4),
		size = 0.12,
		spread = 180,
	})
end

-- Uncommon: ancient roots cradling a pulsing amber heart.
Shapes.ElderRoot = function(ctx: Ctx)
	local def = ctx.def
	local orb = ctx:part({ kind = "Ball", size = Vector3.one, cf = CFrame.new(0, 0.25, 0), color = def.glow, material = M.Neon, role = "glow" })
	ctx:part({ kind = "Ball", size = Vector3.one * 1.18, cf = CFrame.new(0, 0.25, 0), color = Color3.fromRGB(255, 190, 90), material = M.Glass, transparency = 0.5, role = "body" })
	ctx:part({ kind = "Ellipsoid", size = Vector3.new(1, 0.55, 1), cf = CFrame.new(0, -1.05, 0), color = def.primary, material = M.Wood, role = "body" })
	for i = 0, 4 do
		local yaw = CFrame.Angles(0, rad(i * 72 + 10), 0)
		ctx:part({ kind = "VCylinder", size = Vector3.new(0.26, 1.05, 0.26), cf = yaw * CFrame.new(0, -0.5, 0.42) * CFrame.Angles(rad(38), 0, 0), color = def.primary, material = M.Wood, role = "body" })
		ctx:part({ kind = "VCylinder", size = Vector3.new(0.2, 0.95, 0.2), cf = yaw * CFrame.new(0, 0.32, 0.8) * CFrame.Angles(rad(-18), 0, 0), color = def.primary, material = M.Wood, role = "body" })
		ctx:part({ kind = "Ellipsoid", size = Vector3.new(0.14, 0.28, 0.5), cf = yaw * CFrame.new(0, 0.85, 0.7) * CFrame.Angles(rad(-35), 0, 0), color = def.secondary, role = "body" })
	end
	local light = ctx:light(def.glow, 7, 1)
	ctx:animate(function(env: Env)
		local pulse = (math.sin(env.time * 2.2) + 1) * 0.5
		orb.Size = Vector3.one * (1 + pulse * 0.08) * ctx.scale
		light.Brightness = 0.8 + pulse * 1.2
	end)
	ctx:emitter({
		color = ColorSequence.new(def.glow),
		rate = 4,
		lifetime = NumberRange.new(1.5, 2.5),
		speed = NumberRange.new(0.2, 0.5),
		size = 0.14,
		spread = 180,
		acceleration = Vector3.new(0, 0.6, 0),
	})
end

-- Rare: a sea in a glass globe, currents swirling inside.
Shapes.OceanOrb = function(ctx: Ctx)
	local def = ctx.def
	ctx:part({ kind = "Ball", size = Vector3.one * 2.4, color = def.primary, material = M.Glass, transparency = 0.55, reflectance = 0.1, role = "body" })
	ctx:part({ kind = "Ball", size = Vector3.one * 1.15, color = def.secondary, material = M.Neon, transparency = 0.05, role = "glow" })
	local waveA = ctx:part({ kind = "Ellipsoid", size = Vector3.new(2, 0.1, 0.75), color = def.glow, material = M.Neon, transparency = 0.25, role = "glow" })
	local waveB = ctx:part({ kind = "Ellipsoid", size = Vector3.new(1.8, 0.1, 0.6), color = def.glow, material = M.Neon, transparency = 0.35, role = "glow" })
	local ring = ctx:ring({ radius = 1.6, width = 0.1, color = def.glow, transparency = 0.15 })
	ctx:animate(function(env: Env)
		local t = env.time
		ctx:move(waveA, CFrame.Angles(rad(25), t * 1.4, 0))
		ctx:move(waveB, CFrame.Angles(rad(-35), -t * 1.1, rad(20)))
		ctx:setRing(ring, CFrame.Angles(rad(18 + math.sin(t) * 6), t * 0.5, 0))
	end)
	ctx:emitter({
		color = ColorSequence.new(Color3.fromRGB(220, 250, 255), def.glow),
		rate = 6,
		lifetime = NumberRange.new(1, 1.8),
		speed = NumberRange.new(0.5, 1),
		size = 0.18,
		spread = 30,
		acceleration = Vector3.new(0, 1.5, 0),
	})
end

-- Rare: a crescent moon chunk with tiny stars in orbit.
Shapes.LunarFragment = function(ctx: Ctx)
	local def = ctx.def
	local count = 9
	for i = 0, count - 1 do
		local a = rad(-80 + i * (160 / (count - 1)))
		local thickness = 0.32 + 0.72 * math.cos(a) ^ 1.6
		ctx:part({ kind = "Ball", size = Vector3.one * thickness, cf = CFrame.new(-math.cos(a) * 1.05 + 0.45, math.sin(a) * 1.25, 0), color = def.primary, reflectance = 0.08, role = "body" })
	end
	-- Inner luminous edge.
	local edge = ctx:beam(Vector3.new(0.5, 1.2, 0), Vector3.new(0.5, -1.2, 0), 0.18, 0.18, ColorSequence.new(def.glow), NumberSequence.new(0.1))
	edge.CurveSize0 = -1
	edge.CurveSize1 = 1
	edge.Segments = 12

	local stars = {}
	for i = 1, 3 do
		table.insert(stars, ctx:part({ kind = "Block", size = Vector3.one * 0.22, color = Color3.new(1, 1, 1), material = M.Neon, role = "glow" }))
	end
	local visual = ctx.visual
	ctx:animate(function(env: Env)
		visual.bodyTransform = CFrame.Angles(0, 0, math.sin(env.time * 0.9) * 0.16)
		for i, star in stars do
			local angle = env.time * (0.9 + i * 0.3) + i * 2
			ctx:move(star, CFrame.new(math.cos(angle) * 1.7, math.sin(angle * 0.7) * 0.6, math.sin(angle) * 1.7) * CFrame.Angles(env.time, env.time, 0))
		end
	end)
	ctx:emitter({
		color = ColorSequence.new(Color3.fromRGB(235, 240, 255)),
		rate = 5,
		lifetime = NumberRange.new(1.2, 2),
		speed = NumberRange.new(0.2, 0.6),
		size = 0.14,
		spread = 180,
	})
end

-- Rare: a molten core inside cracked basalt that beats like a heart.
Shapes.MagmaHeart = function(ctx: Ctx)
	local def = ctx.def
	ctx:part({ kind = "Ball", size = Vector3.one * 1.35, color = def.secondary, material = M.Neon, role = "glow" })
	local directions = {
		Vector3.new(1, 0.3, 0.2),
		Vector3.new(-0.9, 0.4, -0.3),
		Vector3.new(0.2, 1, 0.1),
		Vector3.new(-0.3, -0.9, 0.4),
		Vector3.new(0.4, -0.5, -0.9),
		Vector3.new(-0.5, 0.2, 0.95),
		Vector3.new(0.75, -0.3, 0.7),
		Vector3.new(-0.2, 0.55, -0.85),
	}
	local chunks = {}
	for i, dir in directions do
		local unit = dir.Unit
		local size = 0.72 + (i % 3) * 0.12
		local rot = CFrame.Angles(i * 0.7, i * 1.3, i * 0.4)
		local part = ctx:part({ kind = "Block", size = Vector3.new(size, size * 0.85, size), color = def.primary, material = M.Basalt, role = "body" })
		table.insert(chunks, { part = part, dir = unit, rot = rot })
	end
	local light = ctx:light(def.glow, 9, 1.4)
	local function beat(t: number): number
		local p = t % 1.4
		return math.exp(-((p - 0.1) / 0.07) ^ 2) + 0.6 * math.exp(-((p - 0.34) / 0.07) ^ 2)
	end
	local function layout(t: number)
		local amp = beat(t)
		for _, chunk in chunks do
			ctx:move(chunk.part, CFrame.new(chunk.dir * (0.74 + amp * 0.13)) * chunk.rot)
		end
		light.Brightness = 1 + amp * 2.2
	end
	layout(0)
	ctx:animate(function(env: Env)
		layout(env.time)
	end)
	ctx:emitter({
		texture = TEX.fire,
		color = ColorSequence.new(Color3.fromRGB(255, 180, 80), Color3.fromRGB(255, 60, 20)),
		rate = 7,
		lifetime = NumberRange.new(0.5, 0.9),
		speed = NumberRange.new(0.5, 1.2),
		size = 0.55,
		spread = 30,
		acceleration = Vector3.new(0, 2.5, 0),
		transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.4),
			NumberSequenceKeypoint.new(1, 1),
		}),
	})
	ctx:emitter({
		texture = TEX.spark,
		color = ColorSequence.new(Color3.fromRGB(255, 200, 120)),
		rate = 5,
		lifetime = NumberRange.new(0.6, 1.2),
		speed = NumberRange.new(1, 2.5),
		size = 0.1,
		spread = 60,
		acceleration = Vector3.new(0, 1, 0),
	})
end

-- Epic: a black hole caged by fractured cube corners and an accretion disk.
Shapes.VoidCube = function(ctx: Ctx)
	local def = ctx.def
	local fragments = {}
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local part = ctx:part({ kind = "Block", size = Vector3.one * 0.8, color = def.primary, material = M.Slate, role = "body" })
				table.insert(fragments, { part = part, dir = Vector3.new(sx, sy, sz), twist = (sx + sy * 2 + sz * 3) * 0.3 })
			end
		end
	end
	ctx:part({ kind = "Ball", size = Vector3.one * 0.85, color = Color3.fromRGB(40, 26, 92), role = "fx", name = "Singularity" })
	ctx:part({ kind = "Ball", size = Vector3.one * 1.05, color = def.glow, material = M.ForceField, role = "fx" })
	local disk = ctx:part({ kind = "VCylinder", size = Vector3.new(2.3, 0.05, 2.3), color = def.glow, material = M.Neon, transparency = 0.4, role = "glow" })
	local diskCore = ctx:part({ kind = "VCylinder", size = Vector3.new(1.5, 0.06, 1.5), color = Color3.fromRGB(240, 220, 255), material = M.Neon, transparency = 0.15, role = "glow" })

	local function layout(t: number)
		local spread = 0.6 + math.sin(t * 1.3) * 0.11
		for _, f in fragments do
			ctx:move(f.part, CFrame.new(f.dir * spread) * CFrame.Angles(t * 0.4 + f.twist, t * 0.3, 0))
		end
		local tilt = CFrame.Angles(rad(22), 0, rad(8))
		ctx:move(disk, tilt * CFrame.Angles(0, t * 2.5, 0))
		ctx:move(diskCore, tilt * CFrame.Angles(0, -t * 3.5, 0))
	end
	layout(0)
	ctx:animate(function(env: Env)
		layout(env.time)
	end)
	ctx:emitter({
		color = ColorSequence.new(Color3.fromRGB(230, 200, 255), def.glow),
		rate = 14,
		lifetime = NumberRange.new(0.5, 0.8),
		speed = NumberRange.new(2.5, 3.5),
		size = 0.14,
		shell = 2.2,
		inward = true,
		essential = true,
	})
end

-- Epic: a splinter of a newborn sun bristling with light rays.
Shapes.SunFragment = function(ctx: Ctx)
	local def = ctx.def
	ctx:part({ kind = "Ball", size = Vector3.one * 1.45, color = def.primary, material = M.Neon, role = "glow" })
	ctx:part({ kind = "Ball", size = Vector3.one * 2.05, color = def.secondary, material = M.ForceField, role = "fx" })
	local rays = {}
	local count = 10
	local golden = math.pi * (3 - math.sqrt(5))
	for i = 0, count - 1 do
		local y = 1 - (i / (count - 1)) * 2
		local radius = math.sqrt(1 - y * y)
		local theta = golden * i
		local dir = Vector3.new(math.cos(theta) * radius, y * 0.8, math.sin(theta) * radius).Unit
		local part = ctx:part({ kind = "Block", size = Vector3.new(0.15, 0.15, 1.05), color = def.secondary, material = M.Neon, role = "glow" })
		table.insert(rays, { part = part, base = CFrame.lookAt(dir * 1.2, dir * 3) })
	end
	local function layout(t: number)
		local spin = CFrame.Angles(0, t * 0.6, 0)
		for i, ray in rays do
			local pulse = 1 + math.sin(t * 3 + i) * 0.06
			ctx:move(ray.part, spin * CFrame.new(ray.base.Position * pulse) * ray.base.Rotation)
		end
	end
	layout(0)
	ctx:animate(function(env: Env)
		layout(env.time)
	end)
	ctx:light(Color3.fromRGB(255, 210, 120), 12, 1.8)
	ctx:emitter({
		texture = TEX.spark,
		color = ColorSequence.new(Color3.fromRGB(255, 240, 180), def.secondary),
		rate = 10,
		lifetime = NumberRange.new(0.4, 0.8),
		speed = NumberRange.new(2, 4),
		size = 0.14,
		spread = 180,
	})
end

-- Epic: an hourglass that empties, then flips itself over.
Shapes.ChronoGlass = function(ctx: Ctx)
	local def = ctx.def
	for _, y in { 1.45, -1.45 } do
		ctx:part({ kind = "VCylinder", size = Vector3.new(1.9, 0.25, 1.9), cf = CFrame.new(0, y, 0), color = def.primary, material = M.Metal, role = "body" })
		ctx:part({ kind = "VCylinder", size = Vector3.new(2.02, 0.07, 2.02), cf = CFrame.new(0, y * 0.9, 0), color = def.glow, material = M.Neon, role = "glow" })
	end
	for i = 0, 2 do
		local a = rad(i * 120)
		ctx:part({ kind = "VCylinder", size = Vector3.new(0.13, 2.7, 0.13), cf = CFrame.new(math.cos(a) * 0.86, 0, math.sin(a) * 0.86), color = def.primary, material = M.Metal, role = "body" })
	end
	ctx:part({ kind = "Ellipsoid", size = Vector3.new(1.35, 1.42, 1.35), cf = CFrame.new(0, 0.68, 0), color = def.secondary, material = M.Glass, transparency = 0.6, role = "body" })
	ctx:part({ kind = "Ellipsoid", size = Vector3.new(1.35, 1.42, 1.35), cf = CFrame.new(0, -0.68, 0), color = def.secondary, material = M.Glass, transparency = 0.6, role = "body" })
	local topSand = ctx:part({ kind = "Ellipsoid", size = Vector3.new(0.9, 0.5, 0.9), color = def.glow, material = M.Neon, role = "glow" })
	local bottomSand = ctx:part({ kind = "Ellipsoid", size = Vector3.new(1, 0.1, 1), color = def.glow, material = M.Neon, role = "glow" })
	local stream = ctx:part({ kind = "VCylinder", size = Vector3.new(0.07, 0.72, 0.07), cf = CFrame.new(0, -0.35, 0), color = def.glow, material = M.Neon, role = "glow" })

	local visual = ctx.visual
	local CYCLE, FLOW = 9, 8.1
	ctx:animate(function(env: Env)
		local local_t = env.time % CYCLE
		local u = math.min(local_t / FLOW, 1)
		local s = ctx.scale
		topSand.Size = Vector3.new(0.9, math.max(0.05, 0.5 * (1 - u)), 0.9) * s
		ctx:move(topSand, CFrame.new(0, 0.32 + 0.25 * (1 - u) * 0.5, 0))
		bottomSand.Size = Vector3.new(1, math.max(0.05, 0.55 * u), 1) * s
		ctx:move(bottomSand, CFrame.new(0, -1.2 + 0.55 * u * 0.5, 0))
		stream.Transparency = if u < 1 then 0 else 1
		if local_t > FLOW then
			local p = (local_t - FLOW) / (CYCLE - FLOW)
			local eased = p * p * (3 - 2 * p)
			visual.bodyTransform = CFrame.Angles(0, 0, eased * math.pi)
		else
			visual.bodyTransform = CFrame.identity
		end
	end)
	ctx:emitter({
		color = ColorSequence.new(def.glow),
		rate = 6,
		lifetime = NumberRange.new(1.5, 2.5),
		speed = NumberRange.new(0.2, 0.5),
		size = 0.12,
		spread = 180,
	})
end

-- Legendary: a cosmic eye that turns to watch the nearest player.
Shapes.CosmicEye = function(ctx: Ctx)
	local def = ctx.def
	local visual = ctx.visual
	visual.spin = false
	visual.wantsFocus = true

	ctx:part({ kind = "Ball", size = Vector3.one * 2.1, color = def.primary, role = "body", name = "Eyeball" })
	local facing = CFrame.Angles(0, rad(90), 0)
	ctx:part({ kind = "Cylinder", size = Vector3.new(0.1, 1.22, 1.22), cf = CFrame.new(0, 0, -0.985) * facing, color = Color3.fromRGB(60, 20, 120), role = "body" })
	ctx:part({ kind = "Cylinder", size = Vector3.new(0.1, 1.04, 1.04), cf = CFrame.new(0, 0, -1.0) * facing, color = def.secondary, material = M.Neon, role = "glow" })
	local pupil = ctx:part({ kind = "Cylinder", size = Vector3.new(0.1, 0.46, 0.46), cf = CFrame.new(0, 0, -1.03) * facing, color = Color3.fromRGB(40, 26, 92), role = "fx" })
	ctx:part({ kind = "Ball", size = Vector3.one * 0.17, cf = CFrame.new(0.22, 0.24, -1.03), color = Color3.new(1, 1, 1), material = M.Neon, role = "fx" })

	local ringA = ctx:ring({ radius = 1.4, width = 0.08, color = def.glow, transparency = 0.1 })
	local ringB = ctx:ring({ radius = 1.6, width = 0.06, color = def.secondary, transparency = 0.3 })

	local current = CFrame.identity
	ctx:animate(function(env: Env)
		local t = env.time
		local rootCF = env.rootCFrame
		local origin = rootCF.Position
		local target: Vector3
		if env.focus then
			target = env.focus
		else
			target = origin + rootCF.LookVector * 10 + Vector3.new(math.sin(t * 0.4) * 6, math.sin(t * 0.7) * 2, math.cos(t * 0.3) * 6)
		end
		local worldLook = CFrame.lookAt(Vector3.zero, target - origin)
		local desired = rootCF.Rotation:Inverse() * worldLook
		current = current:Lerp(desired, damp(4, env.dt))
		visual.bodyTransform = current
		local dilation = if env.focus then 0.36 + math.sin(t * 6) * 0.03 else 0.46
		pupil.Size = Vector3.new(0.1, dilation, dilation) * ctx.scale
		ctx:setRing(ringA, CFrame.Angles(rad(70), t * 0.6, 0))
		ctx:setRing(ringB, CFrame.Angles(rad(-65), -t * 0.45, rad(10)))
	end)
	ctx:emitter({
		color = ColorSequence.new(def.glow, def.secondary),
		rate = 6,
		lifetime = NumberRange.new(1, 1.8),
		speed = NumberRange.new(0.3, 0.8),
		size = 0.2,
		spread = 180,
	})
end

-- Legendary: a celestial astrolabe of three gimbal rings around a star.
Shapes.Astrolabe = function(ctx: Ctx)
	local def = ctx.def
	ctx:part({ kind = "Ball", size = Vector3.one * 0.55, color = def.glow, material = M.Neon, role = "glow" })
	ctx:part({ kind = "Block", size = Vector3.new(1.3, 0.07, 0.07), cf = CFrame.Angles(0, 0, rad(45)), color = Color3.new(1, 1, 1), material = M.Neon, role = "glow" })
	ctx:part({ kind = "Block", size = Vector3.new(1.3, 0.07, 0.07), cf = CFrame.Angles(0, 0, rad(-45)), color = Color3.new(1, 1, 1), material = M.Neon, role = "glow" })
	ctx:part({ kind = "Ball", size = Vector3.one * 0.95, color = def.glow, material = M.ForceField, role = "fx" })
	local arm = ctx:part({ kind = "Block", size = Vector3.new(0.06, 0.06, 2.4), color = def.primary, material = M.Metal, role = "body" })

	local rings = {}
	local radii = { 1.0, 1.45, 1.9 }
	local widths = { 0.13, 0.11, 0.09 }
	local planetColors = { def.glow, Color3.fromRGB(255, 160, 120), Color3.fromRGB(170, 255, 200) }
	for i = 1, 3 do
		local ring = ctx:ring({ radius = radii[i], width = widths[i], color = def.primary, transparency = 0 })
		local planet = ctx:part({ kind = "Ball", size = Vector3.one * (0.3 - i * 0.03), color = planetColors[i], material = M.Neon, role = "glow" })
		table.insert(rings, { ring = ring, planet = planet, radius = radii[i] })
	end
	local function layout(t: number)
		local orientations = {
			CFrame.Angles(t * 0.9, 0, rad(20)),
			CFrame.Angles(rad(60), t * 0.6, t * 0.35),
			CFrame.Angles(rad(-30), -t * 0.4, rad(75)),
		}
		for i, data in rings do
			local cf = orientations[i]
			ctx:setRing(data.ring, cf)
			local angle = t * (1.6 - i * 0.3) + i * 2
			ctx:move(data.planet, cf * CFrame.new(math.cos(angle) * data.radius, 0, math.sin(angle) * data.radius))
		end
		ctx:move(arm, CFrame.Angles(0, t * 0.25, rad(15)))
	end
	layout(0)
	ctx:animate(function(env: Env)
		layout(env.time)
	end)
	ctx:emitter({
		color = ColorSequence.new(Color3.fromRGB(200, 230, 255), def.glow),
		rate = 7,
		lifetime = NumberRange.new(1.2, 2),
		speed = NumberRange.new(0.3, 0.8),
		size = 0.16,
		spread = 180,
	})
end

-- Mythic: a twisting tower of impossible colours.
Shapes.PrismaticAnomaly = function(ctx: Ctx)
	ctx:part({ kind = "VCylinder", size = Vector3.new(0.5, 3.3, 0.5), color = Color3.new(1, 1, 1), material = M.Glass, transparency = 0.35, role = "body" })
	local cubes = {}
	for i = 1, 7 do
		local size = 1.12 - math.abs(i - 4) * 0.13
		local part = ctx:part({ kind = "Block", size = Vector3.one * size, color = Color3.fromHSV(i / 7, 0.6, 1), material = M.Neon, transparency = 0.1, role = "glow" })
		table.insert(cubes, { part = part, y = -1.5 + (i - 1) * 0.5, index = i })
	end
	local prisms = {}
	for i = 1, 3 do
		table.insert(prisms, ctx:part({ kind = "CornerWedge", size = Vector3.one * 0.5, color = Color3.new(1, 1, 1), material = M.Glass, transparency = 0.15, reflectance = 0.3, role = "body" }))
	end
	local function layout(t: number)
		for _, cube in cubes do
			local yaw = cube.index * rad(20) + math.sin(t * 1.2 + cube.index * 0.5) * rad(40)
			ctx:move(cube.part, CFrame.new(0, cube.y, 0) * CFrame.Angles(rad(12), yaw, rad(12)))
			cube.part.Color = Color3.fromHSV((t * 0.15 + cube.index / 7) % 1, 0.6, 1)
		end
		for i, prism in prisms do
			local angle = t * 1.1 + i * (math.pi * 2 / 3)
			ctx:move(prism, CFrame.new(math.cos(angle) * 1.6, math.sin(t * 1.5 + i) * 0.8, math.sin(angle) * 1.6) * CFrame.Angles(t, t * 1.3, 0))
		end
	end
	layout(0)
	ctx:animate(function(env: Env)
		layout(env.time)
	end)
	ctx:emitter({
		color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 100, 100)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(120, 255, 140)),
			ColorSequenceKeypoint.new(0.66, Color3.fromRGB(100, 180, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 120, 240)),
		}),
		rate = 12,
		lifetime = NumberRange.new(1, 1.8),
		speed = NumberRange.new(0.5, 1.5),
		size = 0.24,
		spread = 180,
		rotSpeed = NumberRange.new(-120, 120),
		essential = true,
	})
end

-- Mythic: a tiny living world with rings, clouds and a moon.
Shapes.PocketPlanet = function(ctx: Ctx)
	local def = ctx.def
	local visual = ctx.visual
	visual.spin = false
	local tilt = CFrame.Angles(0, 0, rad(23))
	local surface = {}
	local function add(part: BasePart, base: CFrame)
		table.insert(surface, { part = part, base = base })
	end
	add(ctx:part({ kind = "Ball", size = Vector3.one * 2, color = def.primary, role = "body" }), CFrame.identity)
	local continents = {
		{ dir = Vector3.new(1, 0.2, 0.3), size = Vector3.new(0.95, 0.75, 0.32) },
		{ dir = Vector3.new(-0.6, 0.5, 0.6), size = Vector3.new(0.8, 0.6, 0.3) },
		{ dir = Vector3.new(-0.3, -0.4, -0.9), size = Vector3.new(1, 0.7, 0.32) },
		{ dir = Vector3.new(0.4, -0.6, 0.7), size = Vector3.new(0.6, 0.5, 0.28) },
		{ dir = Vector3.new(0.2, 0.7, -0.7), size = Vector3.new(0.7, 0.45, 0.28) },
	}
	for _, c in continents do
		local dir = c.dir.Unit
		local base = CFrame.lookAt(dir * 0.9, dir * 2)
		add(ctx:part({ kind = "Ellipsoid", size = c.size, color = def.secondary, role = "body" }), base)
	end
	add(ctx:part({ kind = "Ellipsoid", size = Vector3.new(0.95, 0.24, 0.95), color = Color3.fromRGB(245, 250, 255), role = "body" }), CFrame.new(0, 0.94, 0))
	add(ctx:part({ kind = "Ellipsoid", size = Vector3.new(0.85, 0.22, 0.85), color = Color3.fromRGB(245, 250, 255), role = "body" }), CFrame.new(0, -0.95, 0))
	ctx:part({ kind = "Ball", size = Vector3.one * 2.32, color = Color3.fromRGB(150, 210, 255), material = M.ForceField, role = "fx" })
	local clouds = {}
	for i = 1, 3 do
		table.insert(clouds, ctx:part({ kind = "Ellipsoid", size = Vector3.new(0.55, 0.12, 0.3), color = Color3.new(1, 1, 1), transparency = 0.1, role = "fx" }))
	end
	ctx:ring({ radius = 1.75, width = 0.34, color = Color3.fromRGB(235, 215, 170), transparency = 0.15, cf = tilt * CFrame.Angles(rad(-8), 0, 0), role = "body" })
	ctx:ring({ radius = 2.08, width = 0.12, color = Color3.fromRGB(215, 195, 160), transparency = 0.4, cf = tilt * CFrame.Angles(rad(-8), 0, 0), role = "body" })
	local moon = ctx:part({ kind = "Ball", size = Vector3.one * 0.42, color = Color3.fromRGB(190, 190, 205), role = "body" })

	local function layout(t: number)
		local spin = tilt * CFrame.Angles(0, t * 0.5, 0)
		for _, s in surface do
			ctx:move(s.part, spin * s.base)
		end
		for i, cloud in clouds do
			local a = t * 0.8 + i * 2.1
			local dir = Vector3.new(math.cos(a), math.sin(i * 1.7) * 0.5, math.sin(a)).Unit
			ctx:move(cloud, tilt * CFrame.lookAt(dir * 1.08, dir * 3) * CFrame.Angles(rad(90), 0, 0))
		end
		local m = t * 0.9
		ctx:move(moon, CFrame.Angles(rad(15), 0, rad(-10)) * CFrame.new(math.cos(m) * 2.7, 0, math.sin(m) * 2.7))
	end
	layout(0)
	ctx:animate(function(env: Env)
		layout(env.time)
	end)
	ctx:emitter({
		color = ColorSequence.new(Color3.fromRGB(220, 240, 255)),
		rate = 6,
		lifetime = NumberRange.new(1.5, 2.5),
		speed = NumberRange.new(0.2, 0.5),
		size = 0.14,
		spread = 180,
	})
end

-- Secret: a miniature Rift — a tear in space ringed by orbiting debris.
Shapes.RiftHeart = function(ctx: Ctx)
	local def = ctx.def
	local lens = ctx:part({ kind = "Ellipsoid", size = Vector3.new(0.85, 3, 0.3), color = def.glow, material = M.Neon, role = "glow" })
	local dark = ctx:part({ kind = "Ellipsoid", size = Vector3.new(0.55, 2.55, 0.36), color = Color3.fromRGB(40, 26, 92), role = "fx" })
	local outer = ctx:part({ kind = "Ellipsoid", size = Vector3.new(1.6, 3.8, 0.6), color = def.primary, material = M.ForceField, role = "fx" })
	local ringA = ctx:ring({ radius = 1.5, width = 0.1, color = def.glow, transparency = 0 })
	local ringB = ctx:ring({ radius = 1.95, width = 0.07, color = def.primary, transparency = 0.2 })
	local shards = {}
	for i = 1, 6 do
		table.insert(shards, ctx:part({ kind = "Block", size = Vector3.new(0.28, 0.5, 0.2), color = Color3.fromRGB(40, 25, 70), material = M.Slate, role = "body" }))
	end
	local function layout(t: number)
		local turn = CFrame.Angles(0, t * 0.35, 0)
		ctx:move(lens, turn)
		ctx:move(dark, turn)
		ctx:move(outer, turn)
		lens.Transparency = 0.05 + (math.sin(t * 3) + 1) * 0.08
		ctx:setRing(ringA, CFrame.Angles(rad(75), t * 1.2, 0))
		ctx:setRing(ringB, CFrame.Angles(rad(-60), -t * 0.8, rad(30)))
		for i, shard in shards do
			local a = t * 0.9 + i * (math.pi * 2 / 6)
			ctx:move(shard, CFrame.new(math.cos(a) * 2.1, math.sin(t * 1.3 + i) * 1.1, math.sin(a) * 2.1) * CFrame.Angles(t + i, t * 0.7, 0))
		end
	end
	layout(0)
	ctx:animate(function(env: Env)
		layout(env.time)
	end)
	ctx:emitter({
		texture = TEX.implosion,
		color = ColorSequence.new(def.glow, def.primary),
		rate = 6,
		lifetime = NumberRange.new(0.6, 1),
		speed = NumberRange.new(2, 3),
		size = 0.8,
		shell = 2.8,
		inward = true,
		essential = true,
	})
end

-- Secret (Eclipse only): a black sun with a burning corona that faces you.
Shapes.EclipseSigil = function(ctx: Ctx)
	local def = ctx.def
	local visual = ctx.visual
	visual.spin = false
	ctx:part({ kind = "Ball", size = Vector3.one * 2, color = Color3.fromRGB(40, 26, 92), role = "fx", name = "BlackSun" })
	ctx:part({ kind = "Ball", size = Vector3.one * 2.45, color = def.secondary, material = M.ForceField, role = "fx" })
	ctx:ring({ radius = 1.03, width = 0.24, color = def.secondary, transparency = 0, cf = CFrame.identity })
	ctx:ring({ radius = 1.28, width = 0.6, color = def.glow, transparency = 0.5, cf = CFrame.identity })
	local rays = {}
	for i = 0, 7 do
		table.insert(rays, { part = ctx:part({ kind = "Block", size = Vector3.new(0.12, 0.12, 1.1), color = def.secondary, material = M.Neon, role = "glow" }), angle = i * 45 })
	end
	local current = CFrame.identity
	ctx:animate(function(env: Env)
		local t = env.time
		if env.camera then
			local origin = env.rootCFrame.Position
			local facing = CFrame.lookAt(Vector3.zero, env.camera - origin) * CFrame.Angles(-math.pi / 2, 0, 0)
			current = current:Lerp(env.rootCFrame.Rotation:Inverse() * facing, damp(8, env.dt))
			visual.bodyTransform = current
		end
		for i, ray in rays do
			local a = rad(ray.angle) + t * 0.3
			local len = 1.75 + math.sin(t * 2 + i) * 0.12
			ctx:move(ray.part, CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -len))
		end
	end)
	ctx:emitter({
		texture = TEX.spark,
		color = ColorSequence.new(Color3.fromRGB(255, 200, 120), def.secondary),
		rate = 10,
		lifetime = NumberRange.new(0.6, 1.1),
		speed = NumberRange.new(1.5, 3),
		size = 0.14,
		spread = 180,
		essential = true,
	})
	ctx:emitter({
		texture = TEX.smoke,
		color = ColorSequence.new(Color3.fromRGB(40, 10, 10)),
		rate = 4,
		lifetime = NumberRange.new(1, 1.6),
		speed = NumberRange.new(0.5, 1),
		size = 1.2,
		spread = 180,
		emission = 0,
		transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.4, 0.6),
			NumberSequenceKeypoint.new(1, 1),
		}),
	})
end

-- Legendary (boss relic, V2 phase 6): the Void Warden's favourite feather
-- duster. A stubby handle, a gold band and a big fluffy puff that wiggles.
Shapes.VoidDuster = function(ctx: Ctx)
	local def = ctx.def
	local tilt = CFrame.Angles(0, 0, rad(-12))
	ctx:part({ kind = "VCylinder", size = Vector3.new(0.36, 1.7, 0.36), cf = tilt * CFrame.new(0, -0.75, 0), color = def.secondary, role = "body", name = "Handle" })
	ctx:part({ kind = "Ball", size = Vector3.one * 0.5, cf = tilt * CFrame.new(0, -1.62, 0), color = def.glow, material = M.Neon, role = "glow", name = "Knob" })
	ctx:part({ kind = "VCylinder", size = Vector3.new(0.6, 0.26, 0.6), cf = tilt * CFrame.new(0, 0.12, 0), color = Color3.fromRGB(255, 214, 72), role = "body", name = "Band" })
	ctx:part({ kind = "Ellipsoid", size = Vector3.new(1.75, 1.45, 1.6), cf = tilt * CFrame.new(0, 0.95, 0), color = def.primary, role = "body", name = "Puff" })
	local feathers = {}
	for i = 0, 5 do
		local a = i * 60
		local part = ctx:part({ kind = "Ellipsoid", size = Vector3.new(0.9, 0.42, 0.55), color = if i % 2 == 0 then def.primary else Color3.fromRGB(255, 196, 236), role = "body" })
		table.insert(feathers, { part = part, angle = rad(a), phase = i * 0.9 })
	end
	ctx:part({ kind = "Ellipsoid", size = Vector3.new(0.7, 0.55, 0.6), cf = tilt * CFrame.new(0, 1.68, 0.1), color = Color3.fromRGB(255, 196, 236), role = "body", name = "Tuft" })

	ctx:animate(function(env: Env)
		local t = env.time
		for _, f in feathers do
			local wiggle = math.sin(t * 3.2 + f.phase) * rad(10)
			ctx:move(f.part, tilt * CFrame.new(0, 1.0, 0) * CFrame.Angles(0, f.angle, 0) * CFrame.new(0.78, 0.05, 0) * CFrame.Angles(0, 0, rad(18) + wiggle))
		end
	end)

	ctx:emitter({
		texture = TEX.sparkle,
		color = ColorSequence.new(Color3.fromRGB(255, 255, 255), def.glow),
		rate = 5,
		lifetime = NumberRange.new(0.8, 1.4),
		speed = NumberRange.new(0.4, 0.9),
		size = 0.16,
		spread = 180,
		acceleration = Vector3.new(0, -0.3, 0),
		essential = true,
	})
end

-- Legendary (boss relic, V2 phase 7A): Forgeheart's pocket anvil, still hot.
-- A chunky cartoon anvil with glowing lava cracks, a tiny hammer bouncing
-- on top and embers popping off.
Shapes.EmberAnvil = function(ctx: Ctx)
	local def = ctx.def
	ctx:part({ kind = "Block", size = Vector3.new(1.3, 0.5, 1.0), cf = CFrame.new(0, -1.0, 0), color = def.primary, role = "body", name = "Foot" })
	ctx:part({ kind = "Block", size = Vector3.new(0.7, 0.7, 0.7), cf = CFrame.new(0, -0.45, 0), color = def.primary, role = "body", name = "Waist" })
	ctx:part({ kind = "Block", size = Vector3.new(2.0, 0.7, 1.15), cf = CFrame.new(0.1, 0.25, 0), color = def.primary, role = "body", name = "Top" })
	ctx:part({ kind = "Wedge", size = Vector3.new(1.15, 0.7, 0.9), cf = CFrame.new(-1.5, 0.25, 0) * CFrame.Angles(0, rad(90), 0), color = def.primary, role = "body", name = "Horn" })
	-- Glowing lava cracks and the hot top face.
	ctx:part({ kind = "Block", size = Vector3.new(1.8, 0.08, 0.9), cf = CFrame.new(0.1, 0.62, 0), color = def.secondary, material = M.Neon, role = "glow", name = "HotTop" })
	ctx:part({ kind = "Block", size = Vector3.new(0.12, 0.5, 0.06), cf = CFrame.new(0.5, 0.2, -0.6) * CFrame.Angles(0, 0, rad(25)), color = def.glow, material = M.Neon, role = "glow", name = "Crack" })
	ctx:part({ kind = "Block", size = Vector3.new(0.1, 0.4, 0.06), cf = CFrame.new(-0.3, -0.95, -0.52) * CFrame.Angles(0, 0, rad(-30)), color = def.glow, material = M.Neon, role = "glow", name = "Crack" })
	-- The tiny hammer bouncing on the anvil.
	local handle = ctx:part({ kind = "VCylinder", size = Vector3.new(0.16, 1.1, 0.16), color = Color3.fromRGB(196, 120, 70), role = "body" })
	local head = ctx:part({ kind = "Block", size = Vector3.new(0.55, 0.36, 0.36), color = Color3.fromRGB(90, 80, 110), role = "body" })

	ctx:animate(function(env: Env)
		local t = env.time
		local bounce = math.abs(math.sin(t * 3)) * 0.35
		local swing = CFrame.new(0.55, 0.95 + bounce, 0.1) * CFrame.Angles(0, 0, rad(-35) + math.sin(t * 6) * rad(25))
		ctx:move(handle, swing * CFrame.new(0, 0.45, 0))
		ctx:move(head, swing * CFrame.new(0, 1.0, 0))
	end)

	ctx:emitter({
		texture = TEX.spark,
		color = ColorSequence.new(Color3.fromRGB(255, 240, 160), def.secondary),
		rate = 7,
		lifetime = NumberRange.new(0.5, 1.1),
		speed = NumberRange.new(1, 2.2),
		size = 0.14,
		spread = 50,
		acceleration = Vector3.new(0, -2, 0),
		essential = true,
	})
end

return Shapes
