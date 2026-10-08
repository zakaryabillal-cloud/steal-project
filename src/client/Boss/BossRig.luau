--!strict
-- Shared pieces of the boss bodies (V2 phase 7A): the rig / pose types and
-- the native-part builder used by every boss model (VoidWardenModel,
-- ForgeheartModel). A model module exposes build / pose / defaultPose /
-- silhouette / destroy (see BossModels); BossFX, the portal card and the
-- Codex only talk to that interface.

local BossRig = {}

export type RigPart = {
	part: BasePart,
	base: CFrame,
	size: Vector3,
	-- body (scaled with squash), face, cap / head, limb, broom, glow...
	group: string,
	transparency: number,
}

export type Rig = {
	model: Model,
	scale: number,
	parts: { RigPart },
	byName: { [string]: RigPart },
	mood: string,
	clock: number,
	nextBlink: number,
}

export type Pose = {
	-- Vertical scale of the body (1 = rest, < 1 squash, > 1 stretch).
	squash: number,
	-- Forward / backward lean (radians) and extra spin around Y (radians).
	lean: number,
	spin: number,
	-- Main prop / arms: 0 = rest, 1 = raised high, -1 = swept low / slammed.
	broom: number,
	-- Mouth opening 0..1.
	mouth: number,
	mood: string,
	-- World point the pupils look at.
	lookAt: Vector3?,
	dizzy: boolean,
	eyesClosed: boolean,
	-- 0 = visible .. 1 = gone (fade out when he runs away).
	fade: number,
	-- Hands / fists bob offset (studs, before scale).
	hands: number,
	-- Phase 6.5 readability: body tint while he prepares an attack (yellow)
	-- or releases it (red), and a white flash when he is hit.
	tint: Color3?,
	tintAlpha: number,
	flash: number,
	-- Phase 7A (Forgeheart): heart / lava glow 0..1+ and comic deflation
	-- 0 (normal) .. 1 (flat balloon) when defeated.
	glow: number,
	deflate: number,
}

export type ModelModule = {
	build: (scale: number, parent: Instance?) -> Rig,
	pose: (rig: Rig, root: CFrame, pose: Pose, dt: number) -> (),
	defaultPose: () -> Pose,
	silhouette: (rig: Rig, color: Color3) -> (),
	destroy: (rig: Rig) -> (),
}

function BossRig.defaultPose(mood: string): Pose
	return {
		squash = 1,
		lean = 0,
		spin = 0,
		broom = 0,
		mouth = 0,
		mood = mood,
		lookAt = nil,
		dizzy = false,
		eyesClosed = false,
		fade = 0,
		hands = 0,
		tint = nil,
		tintAlpha = 0,
		flash = 0,
		glow = 0,
		deflate = 0,
	}
end

function BossRig.new(name: string, scale: number, mood: string): Rig
	local model = Instance.new("Model")
	model.Name = name
	return { model = model, scale = scale, parts = {}, byName = {}, mood = mood, clock = 0, nextBlink = 2 }
end

-- One native part of the rig. kind: Block | Ball | VCyl (standing cylinder)
-- | Ellipsoid (sphere mesh) | Neon* (same kinds, Neon material).
function BossRig.part(rig: Rig, name: string, kind: string, size: Vector3, base: CFrame, color: Color3, group: string, transparency: number?): RigPart
	local neon = string.sub(kind, 1, 4) == "Neon"
	if neon then
		kind = string.sub(kind, 5)
	end
	local part: BasePart
	local s = rig.scale
	if kind == "Ball" then
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Ball
		p.Size = size * s
		part = p
	elseif kind == "VCyl" then
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Cylinder
		-- Cylinders run along X: stand them up.
		p.Size = Vector3.new(size.Y, size.X, size.Z) * s
		base = base * CFrame.Angles(0, 0, math.pi / 2)
		part = p
	elseif kind == "Ellipsoid" then
		local p = Instance.new("Part")
		p.Size = size * s
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
		part = p
	else
		local p = Instance.new("Part")
		p.Size = size * s
		part = p
	end
	part.Name = name
	part.Color = color
	part.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = group == "body"
	part.Transparency = transparency or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = rig.model
	local entry: RigPart = { part = part, base = base, size = part.Size, group = group, transparency = transparency or 0 }
	table.insert(rig.parts, entry)
	rig.byName[name] = entry
	return entry
end

-- Paints the whole rig one colour (Codex silhouette of an unknown boss).
function BossRig.silhouette(rig: Rig, color: Color3)
	for _, entry in rig.parts do
		entry.part.Color = color
		entry.part.Material = Enum.Material.SmoothPlastic
		entry.part.Transparency = 0
		entry.transparency = 0
	end
end

function BossRig.destroy(rig: Rig)
	rig.model:Destroy()
end

-- Blink timer shared by the models: true while the eyes are shut.
function BossRig.blinking(rig: Rig): boolean
	local t = rig.clock
	if t >= rig.nextBlink then
		if t >= rig.nextBlink + 0.12 then
			rig.nextBlink = t + 2.5 + (math.sin(t * 7.3) + 1) * 1.5
		end
		return true
	end
	return false
end

-- Pupil offset (studs, before scale) toward a world point.
function BossRig.gaze(frame: CFrame, lookAt: Vector3?, amount: number): Vector3
	if not lookAt then
		return Vector3.zero
	end
	local localTarget = frame:PointToObjectSpace(lookAt)
	local flat = Vector3.new(localTarget.X, localTarget.Y, 0)
	return if flat.Magnitude > 0.01 then flat.Unit * amount else Vector3.zero
end

return BossRig
