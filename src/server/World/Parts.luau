--!strict
-- Tiny helpers for building static world geometry from code.

local Parts = {}

export type Spec = {
	size: Vector3,
	cf: CFrame,
	color: Color3?,
	material: Enum.Material?,
	transparency: number?,
	reflectance: number?,
	collide: boolean?,
	shadow: boolean?,
	name: string?,
	parent: Instance?,
	query: boolean?,
}

local function apply(part: BasePart, spec: Spec)
	part.Anchored = true
	part.Size = spec.size
	part.CFrame = spec.cf
	part.Color = spec.color or Color3.fromRGB(160, 150, 180)
	part.Material = spec.material or Enum.Material.SmoothPlastic
	part.Transparency = spec.transparency or 0
	part.Reflectance = spec.reflectance or 0
	part.CanCollide = spec.collide ~= false
	part.CanQuery = spec.query ~= false and spec.collide ~= false
	part.CanTouch = false
	part.CastShadow = spec.shadow ~= false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Name = spec.name or part.Name
	part.Locked = true
	if spec.parent then
		part.Parent = spec.parent
	end
end

function Parts.block(spec: Spec): Part
	local part = Instance.new("Part")
	apply(part, spec)
	return part
end

function Parts.ball(spec: Spec): Part
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Ball
	apply(part, spec)
	return part
end

-- Vertical cylinder: size = (diameter, height, diameter), cf = centre.
function Parts.cylinder(spec: Spec): Part
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Cylinder
	local s = spec.size
	local copy = table.clone(spec)
	copy.size = Vector3.new(s.Y, s.X, s.Z)
	copy.cf = spec.cf * CFrame.Angles(0, 0, math.pi / 2)
	apply(part, copy)
	return part
end

-- Ellipsoid via a sphere SpecialMesh (non-uniform size).
function Parts.ellipsoid(spec: Spec): Part
	local part = Instance.new("Part")
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	apply(part, spec)
	return part
end

function Parts.wedge(spec: Spec): WedgePart
	local part = Instance.new("WedgePart")
	apply(part, spec)
	return part
end

function Parts.cornerWedge(spec: Spec): CornerWedgePart
	local part = Instance.new("CornerWedgePart")
	apply(part, spec)
	return part
end

function Parts.light(parent: Instance, color: Color3, range: number, brightness: number, shadows: boolean?): PointLight
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = shadows == true
	light.Parent = parent
	return light
end

function Parts.attachment(parent: Instance, position: Vector3, name: string?): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Position = position
	attachment.Name = name or "Attachment"
	attachment.Parent = parent
	return attachment
end

function Parts.folder(name: string, parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

function Parts.model(name: string, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

-- Welds `part` to `root` (unanchored follower) so clients can animate the
-- whole assembly by moving the anchored root only.
function Parts.weldTo(root: BasePart, part: BasePart)
	part.Anchored = false
	part.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
end

-- Initial velocity so a character launched from `from` with vertical speed
-- `vy` lands on `to` (on the way down). Used by bounce pads.
function Parts.launchVelocity(from: Vector3, to: Vector3, vy: number): Vector3
	local g = workspace.Gravity
	local dy = to.Y - from.Y
	local disc = vy * vy - 2 * g * dy
	assert(disc > 0, "bounce pad cannot reach its target with this vertical speed")
	local t = (vy + math.sqrt(disc)) / g
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local horizontal = flat / t
	return Vector3.new(horizontal.X, vy, horizontal.Z)
end

local RING_K = 4 / 3

-- Glowing ring from two curved beams, centred on `parent` with the given
-- local CFrame (ring lies in the local XZ plane).
function Parts.beamRing(parent: BasePart, cf: CFrame, radius: number, width: number, color: Color3, transparency: number?): { Beam }
	local a0 = Instance.new("Attachment")
	local a1 = Instance.new("Attachment")
	local axis = cf.ZVector
	local normal = cf.YVector
	a0.CFrame = CFrame.fromMatrix((cf * CFrame.new(-radius, 0, 0)).Position, axis, normal)
	a1.CFrame = CFrame.fromMatrix((cf * CFrame.new(radius, 0, 0)).Position, axis, normal)
	a0.Parent = parent
	a1.Parent = parent
	local beams = {}
	for i = 1, 2 do
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		local k = RING_K * radius * (if i == 1 then 1 else -1)
		beam.CurveSize0 = k
		beam.CurveSize1 = -k
		beam.Width0 = width
		beam.Width1 = width
		beam.Color = ColorSequence.new(color)
		beam.Transparency = NumberSequence.new(transparency or 0)
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.FaceCamera = true
		beam.Segments = 24
		beam.Parent = parent
		table.insert(beams, beam)
	end
	return beams
end

return Parts
