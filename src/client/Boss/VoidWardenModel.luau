--!strict
-- The Void Warden's cartoon body (V2 phase 6), built on the client from
-- native Roblox parts (blocks, balls, cylinders, sphere meshes): no sculpted
-- mesh, no external asset. A big purple jelly cube with a janitor cap, huge
-- googly eyes, a fat moustache, floating white gloves, sneakers and a giant
-- broom (docs/ART_DIRECTION.md, "Void Warden").
--
-- The server only moves an invisible anchor; BossFX calls `pose` every frame
-- with the anchor CFrame and a Pose (squash & stretch, lean, spin, broom
-- swing, mouth, mood, gaze, dizzy eyes). Also used at small scale in the
-- portal card and the Codex (ViewportFrame).

local VoidWardenModel = {}

local INK = Color3.fromRGB(30, 27, 75)
local WHITE = Color3.new(1, 1, 1)
local JELLY = Color3.fromRGB(176, 110, 255)
local JELLY_ANGRY = Color3.fromRGB(226, 96, 196)
local LAVENDER = Color3.fromRGB(226, 204, 255)
local CAP = Color3.fromRGB(70, 128, 240)
local GOLD = Color3.fromRGB(255, 214, 72)
local PINK = Color3.fromRGB(255, 140, 190)
local RED = Color3.fromRGB(255, 70, 90)
local WOOD = Color3.fromRGB(196, 120, 70)
local STRAW = Color3.fromRGB(255, 220, 110)

export type RigPart = {
	part: BasePart,
	base: CFrame,
	size: Vector3,
	-- body (scaled with squash), face, cap, limb, broom
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
	-- Broom angle: 0 = resting on the floor, 1 = raised high, -1 = swept low.
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
	-- Gloves bob offset (studs, before scale).
	hands: number,
}

function VoidWardenModel.defaultPose(): Pose
	return { squash = 1, lean = 0, spin = 0, broom = 0, mouth = 0, mood = "grumpy", lookAt = nil, dizzy = false, eyesClosed = false, fade = 0, hands = 0 }
end

local function makePart(rig: Rig, name: string, kind: string, size: Vector3, base: CFrame, color: Color3, group: string, transparency: number?): RigPart
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
	part.Material = Enum.Material.SmoothPlastic
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

-- Builds the rig. `scale` 1 = full size (body 12 studs wide).
function VoidWardenModel.build(scale: number, parent: Instance?): Rig
	local model = Instance.new("Model")
	model.Name = "VoidWarden"
	local rig: Rig = { model = model, scale = scale, parts = {}, byName = {}, mood = "grumpy", clock = 0, nextBlink = 2 }
	local P = CFrame.new
	-- Body (jelly cube) and its gloss.
	makePart(rig, "Body", "Block", Vector3.new(12, 11, 12), P(0, 0, 0), JELLY, "body", 0.08)
	makePart(rig, "Belly", "Block", Vector3.new(8, 4.6, 0.3), P(0, -2.6, -6.05), LAVENDER, "face")
	makePart(rig, "Gloss", "Ellipsoid", Vector3.new(3.2, 1.2, 2), P(-3.4, 4.7, -4.4), WHITE, "face", 0.35)
	-- Eyes.
	for _, side in { -1, 1 } do
		local key = if side < 0 then "L" else "R"
		makePart(rig, "EyeWhite" .. key, "Ball", Vector3.one * 4.2, P(side * 2.5, 2.2, -5.9), WHITE, "face")
		makePart(rig, "Pupil" .. key, "Ball", Vector3.one * 1.9, P(side * 2.5, 2.0, -7.7), INK, "face")
		makePart(rig, "Shine" .. key, "Ball", Vector3.one * 0.6, P(side * 2.5 + 0.45, 2.5, -8.5), WHITE, "face")
		makePart(rig, "Brow" .. key, "Block", Vector3.new(3.6, 0.8, 0.6), P(side * 2.5, 4.9, -6.3), INK, "face")
		makePart(rig, "Stache" .. key, "Ellipsoid", Vector3.new(3.4, 1.3, 1.2), P(side * 1.7, -0.5, -6.4) * CFrame.Angles(0, 0, math.rad(side * -14)), INK, "face")
		makePart(rig, "Cheek" .. key, "Ellipsoid", Vector3.new(2.2, 1.2, 0.4), P(side * 4.4, -0.8, -6.1), PINK, "face", 0.25)
		makePart(rig, "Hand" .. key, "Ball", Vector3.one * 2.8, P(side * 8, -1, -1), WHITE, "limb")
		makePart(rig, "Foot" .. key, "Ellipsoid", Vector3.new(3.5, 1.8, 4.5), P(side * 3, -6.1, -0.8), CAP, "limb")
	end
	-- Mouth (three segments: frown, smile, open) + tongue.
	makePart(rig, "MouthL", "Block", Vector3.new(1.9, 0.6, 0.4), P(-1.8, -2.1, -6.3), INK, "face")
	makePart(rig, "MouthM", "Block", Vector3.new(1.9, 0.6, 0.4), P(0, -2.3, -6.3), INK, "face")
	makePart(rig, "MouthR", "Block", Vector3.new(1.9, 0.6, 0.4), P(1.8, -2.1, -6.3), INK, "face")
	makePart(rig, "Tongue", "Block", Vector3.new(1.6, 0.9, 0.3), P(0, -2.9, -6.25), RED, "face", 1)
	-- Janitor cap.
	makePart(rig, "CapTop", "VCyl", Vector3.new(10, 2.6, 10), P(0, 6.9, 0), CAP, "cap")
	makePart(rig, "CapBand", "VCyl", Vector3.new(10.4, 0.7, 10.4), P(0, 5.8, 0), GOLD, "cap")
	makePart(rig, "CapBrim", "Block", Vector3.new(8, 0.5, 4), P(0, 5.6, -6.6), CAP, "cap")
	makePart(rig, "CapBadge", "Block", Vector3.new(1.6, 1.2, 0.3), P(0, 6.8, -5.1), GOLD, "cap")
	-- Giant broom (held by the right glove; pivots around it).
	makePart(rig, "BroomHandle", "VCyl", Vector3.new(0.9, 20, 0.9), P(0, 7, 0), WOOD, "broom")
	makePart(rig, "BroomBand", "Block", Vector3.new(3, 0.8, 1.6), P(0, -3.2, 0), RED, "broom")
	makePart(rig, "BroomBristles", "Block", Vector3.new(6, 3.6, 2.2), P(0, -5.4, 0), STRAW, "broom")
	if parent then
		model.Parent = parent
	end
	return rig
end

local function mouthShape(mood: string, open: number): (number, number, number)
	-- Returns (corner Y offset, middle height, middle Y offset).
	if mood == "smug" or mood == "happy" then
		return 0.45, 0.6 + open * 2, -0.3 - open
	elseif mood == "shocked" or mood == "dizzy" then
		return -0.1, 1.4 + open * 1.2, -0.6 - open * 0.6
	end
	-- grumpy / angry / furious / sleepy: frown (corners down).
	return -0.5, 0.6 + open * 2, -open
end

local function browAngle(mood: string, side: number): (number, number)
	-- Returns (z rotation, y offset).
	if mood == "angry" then
		return math.rad(side * 24), -0.3
	elseif mood == "furious" then
		return math.rad(side * 32), -0.5
	elseif mood == "smug" then
		return if side < 0 then math.rad(-12) else math.rad(8), if side < 0 then 0.6 else 0
	elseif mood == "shocked" then
		return math.rad(side * -10), 1
	elseif mood == "sleepy" or mood == "dizzy" then
		return math.rad(side * -6), 0.2
	end
	return math.rad(side * 14), 0
end

-- Places every part for this frame.
function VoidWardenModel.pose(rig: Rig, root: CFrame, pose: Pose, dt: number)
	rig.clock += dt
	local s = rig.scale
	local t = rig.clock
	local squash = math.clamp(pose.squash, 0.5, 1.6)
	local wide = 1 / math.sqrt(squash)
	-- Feet stay on the floor: the body centre drops when squashed.
	local drop = (1 - squash) * 5.5 * s
	local frame = root * CFrame.new(0, -drop, 0) * CFrame.Angles(0, pose.spin, 0) * CFrame.Angles(pose.lean, 0, 0)

	-- Blink every few seconds (unless asleep / dizzy).
	local blinking = false
	if t >= rig.nextBlink then
		blinking = true
		if t >= rig.nextBlink + 0.12 then
			rig.nextBlink = t + 2.5 + (math.sin(t * 7.3) + 1) * 1.5
		end
	end
	local closed = pose.eyesClosed or blinking

	-- Gaze: pupils slide toward the target inside the eye whites.
	local gaze = Vector3.zero
	if pose.lookAt then
		local localTarget = frame:PointToObjectSpace(pose.lookAt)
		local flat = Vector3.new(localTarget.X, localTarget.Y, 0)
		if flat.Magnitude > 0.01 then
			gaze = flat.Unit * 0.7
		end
	end
	local cornerY, middleH, middleY = mouthShape(pose.mood, pose.mouth)
	local furious = pose.mood == "furious"
	local cheekAlpha = if furious then 0 elseif pose.mood == "angry" then 0.15 else 0.45

	for _, entry in rig.parts do
		local part = entry.part
		local base = entry.base
		local position = base.Position * s
		local rotation = base.Rotation
		local name = part.Name
		local alpha = entry.transparency
		if entry.group == "body" then
			part.Size = Vector3.new(entry.size.X * wide, entry.size.Y * squash, entry.size.Z * wide)
			part.Color = if furious then JELLY:Lerp(JELLY_ANGRY, 0.5 + math.sin(t * 6) * 0.2) else JELLY
		elseif entry.group == "face" or entry.group == "cap" then
			position = Vector3.new(position.X * wide, position.Y * squash, position.Z * wide)
		elseif entry.group == "limb" then
			if string.sub(name, 1, 4) == "Hand" then
				local side = if string.sub(name, -1) == "L" then -1 else 1
				local bob = math.sin(t * 2.6 + side) * 0.5 + pose.hands
				position = Vector3.new(position.X * wide, position.Y + bob * s, position.Z)
				if side > 0 then
					-- The right glove follows the broom swing.
					position += Vector3.new(0, pose.broom * 3 * s, -math.abs(pose.broom) * 1.5 * s)
				end
			else
				position = Vector3.new(position.X * wide, position.Y, position.Z)
			end
		end
		-- Face details.
		if string.sub(name, 1, 5) == "Pupil" then
			if pose.dizzy then
				local side = if string.sub(name, -1) == "L" then 1 else -1
				local a = t * 9 * side
				position += Vector3.new(math.cos(a) * 0.8, math.sin(a) * 0.8, 0) * s
			else
				position += Vector3.new(gaze.X, gaze.Y, 0) * s
			end
			alpha = if closed then 1 else 0
		elseif string.sub(name, 1, 5) == "Shine" then
			position += Vector3.new(gaze.X, gaze.Y, 0) * s
			alpha = if closed or pose.dizzy then 1 else 0
		elseif string.sub(name, 1, 8) == "EyeWhite" then
			part.Size = if closed then Vector3.new(entry.size.X, entry.size.Y * 0.18, entry.size.Z) else entry.size
		elseif string.sub(name, 1, 4) == "Brow" then
			local side = if string.sub(name, -1) == "L" then -1 else 1
			local angle, lift = browAngle(pose.mood, side)
			rotation = CFrame.Angles(0, 0, angle)
			position += Vector3.new(0, lift * s, 0)
		elseif name == "MouthL" or name == "MouthR" then
			position += Vector3.new(0, cornerY * s, 0)
		elseif name == "MouthM" then
			part.Size = Vector3.new(entry.size.X, middleH * s, entry.size.Z)
			position += Vector3.new(0, middleY * s, 0)
		elseif name == "Tongue" then
			alpha = if pose.mouth > 0.35 then 0 else 1
			position += Vector3.new(0, (middleY - pose.mouth * 0.6) * s, -0.05 * s)
		elseif string.sub(name, 1, 5) == "Cheek" then
			part.Color = if furious then RED else PINK
			alpha = cheekAlpha
		end
		local cf = frame * CFrame.new(position) * rotation
		if entry.group == "broom" then
			-- Pivot the broom around the right glove.
			local hand = rig.byName.HandR
			local handPos = Vector3.new(hand.base.Position.X * wide, hand.base.Position.Y, hand.base.Position.Z) * s
			local swing = CFrame.Angles(math.rad(-70) * pose.broom, 0, math.rad(-12))
			cf = frame * CFrame.new(handPos) * swing * CFrame.new(base.Position * s) * base.Rotation
		end
		part.CFrame = cf
		part.Transparency = math.max(alpha, math.clamp(pose.fade, 0, 1))
	end
end

-- Paints the whole rig one colour (Codex silhouette of an unknown boss).
function VoidWardenModel.silhouette(rig: Rig, color: Color3)
	for _, entry in rig.parts do
		entry.part.Color = color
		entry.part.Transparency = 0
		entry.transparency = 0
	end
end

function VoidWardenModel.destroy(rig: Rig)
	rig.model:Destroy()
end

return VoidWardenModel
