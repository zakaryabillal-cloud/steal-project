--!strict
-- Builds the visual model of a relic from primitives (no external meshes).
--
-- A visual is a client-side Model: one anchored invisible `Root` part and
-- welded, non-colliding detail parts. Moving the root moves everything.
-- Shape builders (RelicShapes) describe silhouettes; this module layers
-- rarity dressing (aura, orbiters, light pillar...) and mutation looks on top.

local Shared = script.Parent.Parent
local Rarities = require(Shared.Config.Rarities)
local Relics = require(Shared.Config.Relics)
local Mutations = require(Shared.Config.Mutations)

export type Env = {
	time: number,
	dt: number,
	-- World position the relic may react to (nearest character), if any.
	focus: Vector3?,
	-- Current camera position.
	camera: Vector3?,
	-- World CFrame of the root before bodyTransform.
	rootCFrame: CFrame,
}

export type PartSpec = {
	kind: string, -- Block | Ball | Ellipsoid | Cylinder | VCylinder | Wedge | CornerWedge
	size: Vector3,
	cf: CFrame?,
	color: Color3,
	material: Enum.Material?,
	-- "body" (recoloured by mutations), "glow" (emissive, tinted), "fx" (untouched)
	role: string?,
	transparency: number?,
	reflectance: number?,
	name: string?,
}

export type RingSpec = {
	radius: number,
	width: number,
	color: Color3,
	cf: CFrame?,
	transparency: number?,
	emission: number?,
	role: string?,
}

export type Ring = {
	a0: Attachment,
	a1: Attachment,
	beams: { Beam },
	-- Preview mode (ViewportFrames cannot render beams): ring made of segments.
	segments: { BasePart },
	width: number,
	radius: number,
	cf: CFrame,
	role: string,
}

export type EmitterRecord = {
	emitter: ParticleEmitter,
	rate: number,
	essential: boolean,
}

export type Visual = {
	model: Model,
	root: BasePart,
	def: Relics.RelicDef,
	rarity: Rarities.Rarity,
	mutation: string?,
	scale: number,
	radius: number,
	-- Extra local transform the renderer applies to the root (flips, looks...).
	bodyTransform: CFrame,
	-- Whether the renderer should apply its idle yaw spin.
	spin: boolean,
	-- Wants env.focus (nearest character) computed.
	wantsFocus: boolean,
	animators: { (env: Env) -> () },
	emitters: { EmitterRecord },
	lights: { PointLight },
	beams: { Beam },
	parts: { BasePart },
	glowParts: { BasePart },
	rings: { Ring },
}

export type BuildOptions = {
	-- Static preview for ViewportFrames: no particles, no light pillar.
	preview: boolean?,
	-- Particle density multiplier (quality setting).
	particleScale: number?,
	-- Override the rarity scale.
	scale: number?,
}

type PartInfo = { part: BasePart, weld: Weld, role: string }

local RING_K = 4 / 3

local Factory = {}

local Ctx = {}
Ctx.__index = Ctx

export type Ctx = typeof(setmetatable(
	{} :: {
		visual: Visual,
		def: Relics.RelicDef,
		rarity: Rarities.Rarity,
		scale: number,
		preview: boolean,
		particleScale: number,
		infos: { PartInfo },
		weldOf: { [BasePart]: Weld },
	},
	Ctx
))

local function scaled(cf: CFrame, s: number): CFrame
	return CFrame.new(cf.Position * s) * cf.Rotation
end

local function newCtx(def: Relics.RelicDef, mutation: string?, options: BuildOptions?): Ctx
	local rarity = Rarities.get(def.rarity)
	local scale = (options and options.scale) or rarity.scale

	local model = Instance.new("Model")
	model.Name = def.id

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.Locked = true
	root.Parent = model
	model.PrimaryPart = root

	local visual: Visual = {
		model = model,
		root = root,
		def = def,
		rarity = rarity,
		mutation = if mutation == "" then nil else mutation,
		scale = scale,
		radius = 1.6 * scale,
		bodyTransform = CFrame.identity,
		spin = true,
		wantsFocus = false,
		animators = {},
		emitters = {},
		lights = {},
		beams = {},
		parts = {},
		glowParts = {},
		rings = {},
	}

	local self = setmetatable({
		visual = visual,
		def = def,
		rarity = rarity,
		scale = scale,
		preview = options ~= nil and options.preview == true,
		particleScale = (options and options.particleScale) or 1,
		infos = {},
		weldOf = {},
	}, Ctx)
	return self
end

function Ctx.part(self: Ctx, spec: PartSpec): BasePart
	local s = self.scale
	local kind = spec.kind
	local cf = spec.cf or CFrame.identity
	local size = spec.size * s

	local part: Part = Instance.new("Part")
	if kind == "Ball" then
		part.Shape = Enum.PartType.Ball
	elseif kind == "Cylinder" then
		part.Shape = Enum.PartType.Cylinder
	elseif kind == "VCylinder" then
		-- Cylinder whose axis is the local Y axis; size is (diameter, height, diameter).
		part.Shape = Enum.PartType.Cylinder
		size = Vector3.new(spec.size.Y, spec.size.X, spec.size.Z) * s
		cf = cf * CFrame.Angles(0, 0, math.pi / 2)
	elseif kind == "Ellipsoid" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
	end

	local basePart: BasePart = part
	if kind == "Wedge" then
		part:Destroy()
		basePart = Instance.new("WedgePart")
	elseif kind == "CornerWedge" then
		part:Destroy()
		basePart = Instance.new("CornerWedgePart")
	end

	basePart.Name = spec.name or kind
	basePart.Size = size
	basePart.Color = spec.color
	basePart.Material = spec.material or Enum.Material.SmoothPlastic
	basePart.Transparency = spec.transparency or 0
	basePart.Reflectance = spec.reflectance or 0
	basePart.Anchored = false
	basePart.CanCollide = false
	basePart.CanQuery = false
	basePart.CanTouch = false
	basePart.CastShadow = false
	basePart.Massless = true
	basePart.Locked = true
	basePart.TopSurface = Enum.SurfaceType.Smooth
	basePart.BottomSurface = Enum.SurfaceType.Smooth

	local root = self.visual.root
	local c0 = scaled(cf, s)
	basePart.CFrame = root.CFrame * c0
	local weld = Instance.new("Weld")
	weld.Part0 = root
	weld.Part1 = basePart
	weld.C0 = c0
	weld.Parent = basePart
	basePart.Parent = self.visual.model

	local role = spec.role or "body"
	table.insert(self.infos, { part = basePart, weld = weld, role = role })
	table.insert(self.visual.parts, basePart)
	if role == "glow" then
		table.insert(self.visual.glowParts, basePart)
	end
	self.weldOf[basePart] = weld
	return basePart
end

-- Re-positions a part relative to the root, in unscaled units.
function Ctx.move(self: Ctx, part: BasePart, cf: CFrame)
	local weld = self.weldOf[part]
	if weld then
		weld.C0 = scaled(cf, self.scale)
	end
end

function Ctx.animate(self: Ctx, fn: (env: Env) -> ())
	table.insert(self.visual.animators, fn)
end

local RING_SEGMENTS = 18

local function setRing(ring: Ring, cf: CFrame, radius: number, scale: number)
	ring.cf = cf
	ring.radius = radius
	local r = radius * scale
	local origin = scaled(cf, scale)
	if #ring.segments > 0 then
		local root = ring.a0.Parent :: BasePart
		local length = 2 * r * math.sin(math.pi / RING_SEGMENTS) * 1.08
		for i, segment in ring.segments do
			local angle = (i / RING_SEGMENTS) * math.pi * 2
			segment.Size = Vector3.new(ring.width * scale, ring.width * scale, length)
			local local_cf = origin * CFrame.Angles(0, angle, 0) * CFrame.new(r, 0, 0)
			segment.CFrame = root.CFrame * local_cf
			local weld = segment:FindFirstChildOfClass("Weld")
			if weld then
				weld.C0 = local_cf
			end
		end
		return
	end
	local axis = origin.ZVector
	local normal = origin.YVector
	local p0 = (origin * CFrame.new(-r, 0, 0)).Position
	local p1 = (origin * CFrame.new(r, 0, 0)).Position
	ring.a0.CFrame = CFrame.fromMatrix(p0, axis, normal)
	ring.a1.CFrame = CFrame.fromMatrix(p1, axis, normal)
	local k = RING_K * r
	ring.beams[1].CurveSize0 = k
	ring.beams[1].CurveSize1 = -k
	ring.beams[2].CurveSize0 = -k
	ring.beams[2].CurveSize1 = k
end

-- Glowing circle made of two curved beams. Cheap to rotate: only two
-- attachments move.
function Ctx.ring(self: Ctx, spec: RingSpec): Ring
	local root = self.visual.root
	local a0 = Instance.new("Attachment")
	a0.Name = "RingA"
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = "RingB"
	a1.Parent = root
	local beams = {}
	local segments = {}
	if self.preview then
		for _ = 1, RING_SEGMENTS do
			local segment = self:part({
				kind = "Block",
				size = Vector3.new(spec.width, spec.width, 0.5),
				color = spec.color,
				material = Enum.Material.Neon,
				transparency = spec.transparency,
				role = "fx",
				name = "RingSegment",
			})
			table.insert(segments, segment)
		end
	else
		for _ = 1, 2 do
			local beam = Instance.new("Beam")
			beam.Attachment0 = a0
			beam.Attachment1 = a1
			beam.Width0 = spec.width * self.scale
			beam.Width1 = spec.width * self.scale
			beam.Color = ColorSequence.new(spec.color)
			beam.Transparency = NumberSequence.new(spec.transparency or 0)
			beam.LightEmission = spec.emission or 1
			beam.LightInfluence = 0
			beam.FaceCamera = true
			beam.Segments = 14
			beam.Parent = root
			table.insert(beams, beam)
			table.insert(self.visual.beams, beam)
		end
	end
	local ring: Ring = {
		a0 = a0,
		a1 = a1,
		beams = beams,
		segments = segments,
		width = spec.width,
		radius = spec.radius,
		cf = spec.cf or CFrame.identity,
		role = spec.role or "glow",
	}
	setRing(ring, ring.cf, spec.radius, self.scale)
	table.insert(self.visual.rings, ring)
	return ring
end

function Ctx.setRing(self: Ctx, ring: Ring, cf: CFrame, radius: number?)
	setRing(ring, cf, radius or ring.radius, self.scale)
end

function Ctx.setRingColor(_self: Ctx, ring: Ring, color: Color3, transparency: number?)
	for _, segment in ring.segments do
		segment.Color = color
		if transparency then
			segment.Transparency = transparency
		end
	end
	for _, beam in ring.beams do
		beam.Color = ColorSequence.new(color)
		if transparency then
			beam.Transparency = NumberSequence.new(transparency)
		end
	end
end

export type EmitterSpec = {
	offset: Vector3?,
	texture: string?,
	color: ColorSequence | Color3,
	rate: number,
	lifetime: NumberRange,
	speed: NumberRange,
	size: NumberSequence | number,
	transparency: NumberSequence?,
	spread: number?,
	acceleration: Vector3?,
	drag: number?,
	rotSpeed: NumberRange?,
	emission: number?,
	lockedToPart: boolean?,
	zOffset: number?,
	-- Emit from the surface of a sphere of this radius (moving inward if `inward`).
	shell: number?,
	inward: boolean?,
	-- Kept at reduced detail levels.
	essential: boolean?,
	orientation: Enum.ParticleOrientation?,
}

local TEXTURES = {
	sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	square = "rbxasset://textures/particles/SquareParticle.png",
	fire = "rbxasset://textures/particles/fire_main.dds",
	spark = "rbxasset://textures/particles/fire_sparks_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
	implosion = "rbxasset://textures/particles/explosion01_implosion_main.dds",
	shockwave = "rbxasset://textures/particles/explosion01_shockwave_main.dds",
	glow = "rbxasset://textures/particles/forcefield_glow_main.dds",
	vortex = "rbxasset://textures/particles/forcefield_vortex_main.dds",
}
Factory.Textures = TEXTURES

function Ctx.emitter(self: Ctx, spec: EmitterSpec): ParticleEmitter?
	if self.preview then
		return nil
	end
	local s = self.scale
	local parent: Instance
	if spec.shell then
		-- ParticleEmitter shapes come from the parent part, so use an invisible shell.
		local shell = self:part({
			kind = "Ball",
			size = Vector3.one * spec.shell * 2,
			cf = CFrame.new(spec.offset or Vector3.zero),
			color = Color3.new(1, 1, 1),
			transparency = 1,
			role = "fx",
			name = "EmitShell",
		})
		parent = shell
	else
		local attachment = Instance.new("Attachment")
		attachment.Name = "Emitter"
		attachment.Position = (spec.offset or Vector3.zero) * s
		attachment.Parent = self.visual.root
		parent = attachment
	end

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = spec.texture or TEXTURES.sparkle
	if typeof(spec.color) == "Color3" then
		emitter.Color = ColorSequence.new(spec.color :: Color3)
	else
		emitter.Color = spec.color :: ColorSequence
	end
	local rate = spec.rate * self.particleScale
	emitter.Rate = rate
	emitter.Lifetime = spec.lifetime
	emitter.Speed = NumberRange.new(spec.speed.Min * s, spec.speed.Max * s)
	if typeof(spec.size) == "number" then
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.15, (spec.size :: number) * s),
			NumberSequenceKeypoint.new(1, 0),
		})
	else
		local seq = spec.size :: NumberSequence
		local points = {}
		for _, kp in seq.Keypoints do
			table.insert(points, NumberSequenceKeypoint.new(kp.Time, kp.Value * s, kp.Envelope * s))
		end
		emitter.Size = NumberSequence.new(points)
	end
	emitter.Transparency = spec.transparency
		or NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(0.8, 0.4),
			NumberSequenceKeypoint.new(1, 1),
		})
	emitter.SpreadAngle = Vector2.new(spec.spread or 180, spec.spread or 180)
	emitter.Acceleration = (spec.acceleration or Vector3.zero) * s
	emitter.Drag = spec.drag or 0
	emitter.RotSpeed = spec.rotSpeed or NumberRange.new(0)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.LightEmission = spec.emission or 1
	emitter.LightInfluence = 0
	emitter.LockedToPart = spec.lockedToPart == true
	emitter.ZOffset = spec.zOffset or 0
	if spec.orientation then
		emitter.Orientation = spec.orientation
	end
	if spec.shell then
		emitter.Shape = Enum.ParticleEmitterShape.Sphere
		emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		emitter.ShapeInOut = if spec.inward then Enum.ParticleEmitterShapeInOut.Inward else Enum.ParticleEmitterShapeInOut.Outward
	end
	emitter.Parent = parent
	table.insert(self.visual.emitters, { emitter = emitter, rate = rate, essential = spec.essential == true })
	return emitter
end

function Ctx.light(self: Ctx, color: Color3, range: number, brightness: number): PointLight
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = self.visual.root
	table.insert(self.visual.lights, light)
	return light
end

-- Straight beam between two root-relative points (unscaled units).
function Ctx.beam(
	self: Ctx,
	from: Vector3,
	to: Vector3,
	width0: number,
	width1: number,
	color: ColorSequence,
	transparency: NumberSequence
): Beam
	local s = self.scale
	local a0 = Instance.new("Attachment")
	a0.Position = from * s
	a0.Parent = self.visual.root
	local a1 = Instance.new("Attachment")
	a1.Position = to * s
	a1.Parent = self.visual.root
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = width0 * s
	beam.Width1 = width1 * s
	beam.Color = color
	beam.Transparency = transparency
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Parent = self.visual.root
	table.insert(self.visual.beams, beam)
	return beam
end

Factory.Ctx = Ctx

----------------------------------------------------------------------------
-- Rarity dressing
----------------------------------------------------------------------------

local function dressRarity(ctx: Ctx)
	local rarity = ctx.rarity
	local visual = ctx.visual
	local color = rarity.color

	ctx:light(color:Lerp(ctx.def.glow, 0.5), rarity.lightRange, rarity.lightBrightness)

	ctx:emitter({
		color = ColorSequence.new(rarity.glow, color),
		rate = rarity.particleRate,
		lifetime = NumberRange.new(0.9, 1.8),
		speed = NumberRange.new(0.4, 1.4),
		size = 0.22,
		spread = 180,
		acceleration = Vector3.new(0, 0.8, 0),
		essential = rarity.order >= 5,
	})

	if rarity.groundRing then
		local ring = ctx:ring({
			radius = 1.7,
			width = 0.12,
			color = color,
			transparency = 0.25,
			cf = CFrame.new(0, -1.7, 0),
			role = "fx",
		})
		ctx:animate(function(env)
			local pulse = 1.7 + math.sin(env.time * 2.2) * 0.12
			ctx:setRing(ring, CFrame.new(0, -1.7, 0), pulse)
		end)
	end

	if rarity.aura then
		local aura = ctx:part({
			kind = "Ball",
			size = Vector3.one * 3.3,
			color = color,
			material = Enum.Material.ForceField,
			transparency = 0.15,
			role = "fx",
			name = "Aura",
		})
		ctx:animate(function(env)
			aura.Transparency = 0.12 + (math.sin(env.time * 1.7) + 1) * 0.12
		end)
	end

	if rarity.orbiters > 0 then
		local orbiters = {}
		for i = 1, rarity.orbiters do
			local orb = ctx:part({
				kind = "Ball",
				size = Vector3.one * 0.24,
				color = rarity.glow,
				material = Enum.Material.Neon,
				role = "glow",
				name = "Orbiter",
			})
			table.insert(orbiters, orb)
			local tilt = math.rad(25 + i * 23)
			local phase = i * (math.pi * 2 / rarity.orbiters)
			local speed = 1.1 + i * 0.25
			local radius = 1.9 + (i % 2) * 0.35
			ctx:animate(function(env)
				local angle = env.time * speed + phase
				ctx:move(orb, CFrame.Angles(tilt, 0, tilt * 0.5) * CFrame.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
			end)
		end
	end

	if rarity.pillar and not ctx.preview then
		ctx:beam(
			Vector3.new(0, 0, 0),
			Vector3.new(0, 60 / ctx.scale, 0),
			1.1,
			0.15,
			ColorSequence.new(color, rarity.glow),
			NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.35),
				NumberSequenceKeypoint.new(0.7, 0.75),
				NumberSequenceKeypoint.new(1, 1),
			})
		)
	end

	if rarity.id == "Mythic" or rarity.id == "Secret" then
		-- Periodic shockwave ring.
		local wave = ctx:ring({
			radius = 1,
			width = 0.18,
			color = rarity.glow,
			transparency = 1,
			cf = CFrame.identity,
			role = "fx",
		})
		local period = if rarity.id == "Secret" then 2.2 else 2.8
		ctx:animate(function(env)
			local t = (env.time % period) / period
			ctx:setRing(wave, CFrame.Angles(math.rad(90), 0, 0), 1 + t * 3.2)
			ctx:setRingColor(wave, rarity.glow, 0.15 + t * 0.85)
		end)
	end

	if rarity.id == "Secret" then
		-- Glitch: brief jitters and black/white flicker.
		local nextGlitch = 0
		local glitchUntil = 0
		local rng = Random.new()
		local originals = {}
		for _, part in visual.glowParts do
			originals[part] = part.Color
		end
		local glitching = false
		ctx:animate(function(env)
			if env.time > nextGlitch then
				glitchUntil = env.time + 0.12
				nextGlitch = env.time + rng:NextNumber(1.4, 3.2)
			end
			if env.time < glitchUntil then
				glitching = true
				visual.bodyTransform = CFrame.new(rng:NextNumber(-0.15, 0.15), rng:NextNumber(-0.1, 0.1), 0)
				for part in originals do
					part.Color = if rng:NextNumber() > 0.5 then Color3.new(1, 1, 1) else Color3.new(0.05, 0.02, 0.1)
				end
			elseif glitching then
				glitching = false
				visual.bodyTransform = CFrame.identity
				for part, original in originals do
					part.Color = original
				end
			end
		end)
	end
end

----------------------------------------------------------------------------
-- Mutation looks
----------------------------------------------------------------------------

local function hueCycle(t: number, offset: number): Color3
	return Color3.fromHSV((t * 0.18 + offset) % 1, 0.65, 1)
end

local function applyMutation(ctx: Ctx, mutationId: string)
	local mutation = Mutations.get(mutationId)
	if not mutation then
		return
	end
	local visual = ctx.visual

	if mutationId == "Charged" then
		for _, info in ctx.infos do
			if info.role == "glow" then
				info.part.Color = info.part.Color:Lerp(Color3.fromRGB(140, 240, 255), 0.6)
			elseif info.role == "body" then
				info.part.Color = info.part.Color:Lerp(Color3.fromRGB(120, 200, 255), 0.25)
			end
		end
		ctx:light(mutation.color, 8, 1.2)
		ctx:emitter({
			texture = TEXTURES.spark,
			color = ColorSequence.new(Color3.fromRGB(220, 255, 255), mutation.color),
			rate = 14,
			lifetime = NumberRange.new(0.15, 0.35),
			speed = NumberRange.new(3, 6),
			size = 0.18,
			spread = 180,
		})
		-- Flickering electric arcs.
		local arcs = {}
		for i = 1, 2 do
			local beam = ctx:beam(
				Vector3.new(-1.3, 0, 0),
				Vector3.new(1.3, 0, 0),
				0.12,
				0.12,
				ColorSequence.new(Color3.fromRGB(230, 255, 255)),
				NumberSequence.new(0)
			)
			beam.Segments = 6
			table.insert(arcs, { beam = beam, seed = i })
		end
		local rng = Random.new()
		local nextFlick = 0
		ctx:animate(function(env)
			if env.time < nextFlick then
				return
			end
			nextFlick = env.time + rng:NextNumber(0.05, 0.14)
			local s = ctx.scale
			for _, arc in arcs do
				local a0 = arc.beam.Attachment0 :: Attachment
				local a1 = arc.beam.Attachment1 :: Attachment
				local theta = rng:NextNumber(0, math.pi * 2)
				local r = 1.4 * s
				a0.Position = Vector3.new(math.cos(theta) * r, rng:NextNumber(-1, 1) * s, math.sin(theta) * r)
				a1.Position = Vector3.new(math.cos(theta + 2.4) * r, rng:NextNumber(-1, 1) * s, math.sin(theta + 2.4) * r)
				arc.beam.CurveSize0 = rng:NextNumber(-2, 2) * s
				arc.beam.CurveSize1 = rng:NextNumber(-2, 2) * s
				arc.beam.Transparency = NumberSequence.new(if rng:NextNumber() > 0.3 then 0 else 1)
			end
		end)
	elseif mutationId == "Golden" then
		for _, info in ctx.infos do
			if info.role == "body" then
				info.part.Color = info.part.Color:Lerp(Color3.fromRGB(255, 196, 70), 0.85)
				info.part.Material = Enum.Material.Foil
				info.part.Reflectance = 0.15
			elseif info.role == "glow" then
				info.part.Color = Color3.fromRGB(255, 226, 130)
			end
		end
		for _, ring in visual.rings do
			if ring.role ~= "fx" then
				ctx:setRingColor(ring, Color3.fromRGB(255, 220, 120))
			end
		end
		ctx:light(Color3.fromRGB(255, 210, 110), 10, 1.4)
		ctx:emitter({
			color = ColorSequence.new(Color3.fromRGB(255, 240, 180), Color3.fromRGB(255, 190, 60)),
			rate = 10,
			lifetime = NumberRange.new(1.2, 2.2),
			speed = NumberRange.new(0.2, 0.6),
			size = 0.25,
			spread = 180,
			acceleration = Vector3.new(0, -1.2, 0),
			rotSpeed = NumberRange.new(-90, 90),
		})
	elseif mutationId == "Void" then
		for _, info in ctx.infos do
			if info.role == "body" then
				info.part.Color = Color3.fromRGB(26, 12, 46)
				info.part.Material = Enum.Material.SmoothPlastic
				info.part.Reflectance = 0.12
			elseif info.role == "glow" then
				info.part.Color = Color3.fromRGB(170, 90, 255)
			end
		end
		for _, ring in visual.rings do
			if ring.role ~= "fx" then
				ctx:setRingColor(ring, Color3.fromRGB(150, 70, 255))
			end
		end
		ctx:part({
			kind = "Ball",
			size = Vector3.one * 3.8,
			color = Color3.fromRGB(70, 10, 140),
			material = Enum.Material.ForceField,
			transparency = 0.1,
			role = "fx",
			name = "VoidShell",
		})
		ctx:emitter({
			texture = TEXTURES.smoke,
			color = ColorSequence.new(Color3.fromRGB(60, 20, 110), Color3.fromRGB(10, 0, 20)),
			rate = 10,
			lifetime = NumberRange.new(0.8, 1.4),
			speed = NumberRange.new(1, 2),
			size = 0.9,
			shell = 2.4,
			inward = true,
			emission = 0,
			transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.3, 0.5),
				NumberSequenceKeypoint.new(1, 1),
			}),
		})
	elseif mutationId == "Corrupted" then
		for _, info in ctx.infos do
			if info.role == "body" then
				info.part.Color = Color3.fromRGB(70, 12, 22)
				info.part.Material = Enum.Material.CrackedLava
			elseif info.role == "glow" then
				info.part.Color = Color3.fromRGB(255, 40, 60)
			end
		end
		for _, ring in visual.rings do
			if ring.role ~= "fx" then
				ctx:setRingColor(ring, Color3.fromRGB(255, 50, 70))
			end
		end
		ctx:light(Color3.fromRGB(255, 50, 60), 9, 1.3)
		ctx:emitter({
			texture = TEXTURES.square,
			color = ColorSequence.new(Color3.fromRGB(255, 40, 60), Color3.fromRGB(20, 0, 5)),
			rate = 12,
			lifetime = NumberRange.new(0.3, 0.8),
			speed = NumberRange.new(0.5, 2),
			size = 0.3,
			spread = 180,
			emission = 0.6,
		})
		-- Glitchy per-part jitter.
		local rng = Random.new()
		local base: { [Weld]: CFrame } = {}
		for _, info in ctx.infos do
			if info.role ~= "fx" then
				base[info.weld] = info.weld.C0
			end
		end
		local nextJitter = 0
		local jittering = false
		ctx:animate(function(env)
			if env.time < nextJitter then
				return
			end
			if jittering then
				for weld, c0 in base do
					weld.C0 = c0
				end
				jittering = false
				nextJitter = env.time + rng:NextNumber(0.4, 1.6)
			else
				for weld, c0 in base do
					if rng:NextNumber() > 0.6 then
						weld.C0 = c0 * CFrame.new(rng:NextNumber(-0.12, 0.12), rng:NextNumber(-0.12, 0.12), 0)
					end
				end
				jittering = true
				nextJitter = env.time + 0.07
			end
		end)
	elseif mutationId == "Prismatic" then
		for _, info in ctx.infos do
			if info.role == "body" then
				info.part.Color = info.part.Color:Lerp(Color3.new(1, 1, 1), 0.55)
				info.part.Reflectance = 0.3
			end
		end
		local glow = visual.glowParts
		local light = ctx:light(Color3.new(1, 1, 1), 11, 1.6)
		ctx:emitter({
			color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
				ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 220, 90)),
				ColorSequenceKeypoint.new(0.4, Color3.fromRGB(110, 255, 140)),
				ColorSequenceKeypoint.new(0.6, Color3.fromRGB(90, 220, 255)),
				ColorSequenceKeypoint.new(0.8, Color3.fromRGB(150, 110, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 110, 230)),
			}),
			rate = 16,
			lifetime = NumberRange.new(1, 2),
			speed = NumberRange.new(0.6, 1.6),
			size = 0.28,
			spread = 180,
			rotSpeed = NumberRange.new(-120, 120),
		})
		ctx:animate(function(env)
			for i, part in glow do
				part.Color = hueCycle(env.time, i * 0.11)
			end
			for i, ring in visual.rings do
				if ring.role ~= "fx" then
					ctx:setRingColor(ring, hueCycle(env.time, 0.5 + i * 0.2))
				end
			end
			light.Color = hueCycle(env.time, 0)
		end)
	end
end

----------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------

local shapes: { [string]: (Ctx) -> () }? = nil

function Factory.build(relicId: string, mutation: string?, options: BuildOptions?): Visual?
	local def = Relics.get(relicId)
	if not def then
		return nil
	end
	if shapes == nil then
		shapes = require(script.Parent.RelicShapes) :: any
	end
	local builder = (shapes :: { [string]: (Ctx) -> () })[def.shape]
	if not builder then
		warn("[RelicFactory] No shape builder for", def.shape)
		return nil
	end
	local ctx = newCtx(def, mutation, options)
	builder(ctx)
	dressRarity(ctx)
	if mutation and mutation ~= "" then
		applyMutation(ctx, mutation)
	end
	return ctx.visual
end

-- Runs every animator; errors in one animator never stop the others.
function Factory.step(visual: Visual, env: Env)
	for _, animator in visual.animators do
		animator(env)
	end
end

-- 2 = full, 1 = reduced (no particles except essential), 0 = static/far.
function Factory.setDetail(visual: Visual, level: number, particleScale: number)
	for _, record in visual.emitters do
		local enabled = level >= 2 or (level == 1 and record.essential)
		record.emitter.Enabled = enabled
		record.emitter.Rate = record.rate * particleScale
	end
	local keepLights = level >= 1 or visual.rarity.order >= 5
	for _, light in visual.lights do
		light.Enabled = keepLights
	end
end

function Factory.destroy(visual: Visual)
	visual.model:Destroy()
	table.clear(visual.animators)
end

return Factory
