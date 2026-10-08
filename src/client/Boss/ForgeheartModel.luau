--!strict
-- Forgeheart's cartoon body (V2 phase 7A), built on the client from native
-- Roblox parts only (balls, ellipsoids, blocks, Neon for the lava): no
-- sculpted mesh, no external asset. A huge round lava golem: a big boulder
-- body with glowing cracks and a burning heart, a smaller boulder head with
-- googly eyes, rocky eyebrows, a goofy glowing mouth with two square teeth,
-- lava "hair" drips, massive arms with boulder fists and stumpy feet
-- (docs/ART_DIRECTION.md, "Forgeheart").
--
-- Same interface as VoidWardenModel (BossRig.ModelModule). Pose fields used:
-- squash, lean, spin, broom (= both arms: 1 raised over the head, -1 slammed
-- down in front), hands (fists bob), mouth, mood, lookAt, dizzy, eyesClosed,
-- fade, tint / tintAlpha / flash, glow (heart and cracks) and deflate (the
-- comic defeat: he deflates like a sad balloon).

local BossRig = require(script.Parent.BossRig)

local ForgeheartModel = {}

export type Rig = BossRig.Rig
export type Pose = BossRig.Pose

local INK = Color3.fromRGB(30, 27, 75)
local WHITE = Color3.new(1, 1, 1)
local ROCK = Color3.fromRGB(176, 106, 82)
local ROCK_LIGHT = Color3.fromRGB(214, 148, 112)
local ROCK_DARK = Color3.fromRGB(110, 66, 64)
local LAVA = Color3.fromRGB(255, 120, 40)
local LAVA_HOT = Color3.fromRGB(255, 220, 90)
local RED = Color3.fromRGB(255, 70, 60)

function ForgeheartModel.defaultPose(): Pose
	return BossRig.defaultPose("grumpy")
end

local part = BossRig.part

-- Builds the rig. `scale` 1 = full size (body 15 studs wide, ~22 tall).
function ForgeheartModel.build(scale: number, parent: Instance?): Rig
	local rig = BossRig.new("Forgeheart", scale, "grumpy")
	local P = CFrame.new
	-- Body boulder, bumps, glowing cracks and the burning heart.
	part(rig, "Body", "Ellipsoid", Vector3.new(15, 14, 13), P(0, -1, 0), ROCK, "body")
	part(rig, "BumpA", "Ellipsoid", Vector3.new(5, 4, 4), P(-5.2, 3.2, -3.4), ROCK_LIGHT, "face")
	part(rig, "BumpB", "Ellipsoid", Vector3.new(4, 3.4, 3.6), P(5.4, -3.6, -3.6), ROCK_LIGHT, "face")
	part(rig, "BumpC", "Ellipsoid", Vector3.new(4.4, 3.6, 3.6), P(-4.2, -5.6, -3.2), ROCK_DARK, "face")
	part(rig, "Crack1", "NeonBlock", Vector3.new(0.6, 5, 0.3), P(-3.2, -1.6, -6.35) * CFrame.Angles(0, 0, math.rad(28)), LAVA, "glow")
	part(rig, "Crack2", "NeonBlock", Vector3.new(0.6, 4, 0.3), P(4.0, 1.6, -6.0) * CFrame.Angles(0, 0, math.rad(-20)), LAVA, "glow")
	part(rig, "Crack3", "NeonBlock", Vector3.new(0.5, 3.4, 0.3), P(1.6, -5.4, -5.9) * CFrame.Angles(0, 0, math.rad(60)), LAVA, "glow")
	part(rig, "HeartRim", "Ball", Vector3.one * 4.8, P(0, -1.2, -5.7), ROCK_DARK, "face")
	part(rig, "Heart", "NeonBall", Vector3.one * 3.6, P(0, -1.2, -6.5), LAVA_HOT, "glow")
	-- Head boulder with the face.
	part(rig, "Head", "Ellipsoid", Vector3.new(9, 7.6, 8.6), P(0, 7.8, -0.6), ROCK, "head")
	for _, side in { -1, 1 } do
		local key = if side < 0 then "L" else "R"
		part(rig, "EyeWhite" .. key, "Ball", Vector3.one * 3.2, P(side * 1.9, 8.7, -4.5), WHITE, "face")
		part(rig, "Pupil" .. key, "Ball", Vector3.one * 1.5, P(side * 1.9, 8.6, -5.9), INK, "face")
		part(rig, "Shine" .. key, "Ball", Vector3.one * 0.5, P(side * 1.9 + 0.35, 9.0, -6.5), WHITE, "face")
		part(rig, "Brow" .. key, "Block", Vector3.new(3.4, 1.1, 1.1), P(side * 1.9, 10.7, -4.6), ROCK_DARK, "face")
		part(rig, "Tooth" .. key, "Block", Vector3.new(0.9, 0.8, 0.3), P(side * 1.0, 5.95, -5.05), WHITE, "face")
		-- Shoulder, arm and boulder fist (they swing around the shoulder).
		part(rig, "Shoulder" .. key, "Ball", Vector3.one * 5.2, P(side * 7.4, 2.6, 0), ROCK_LIGHT, "face")
		part(rig, "Arm" .. key, "Ellipsoid", Vector3.new(3.8, 7.2, 3.8), P(side * 9.2, -1.4, -0.6), ROCK, "limb")
		part(rig, "Fist" .. key, "Ball", Vector3.one * 5.6, P(side * 9.6, -5.8, -1.6), ROCK_LIGHT, "limb")
		part(rig, "Knuckle" .. key, "NeonBlock", Vector3.new(2.6, 0.4, 0.3), P(side * 9.6, -5.2, -4.3), LAVA, "glow")
		part(rig, "Foot" .. key, "Ellipsoid", Vector3.new(4.6, 2.4, 5.6), P(side * 3.6, -8.4, -0.6), ROCK_DARK, "foot")
	end
	-- Goofy mouth: rocky lips, lava inside.
	part(rig, "MouthGlow", "NeonBlock", Vector3.new(4.4, 0.6, 0.4), P(0, 5.8, -4.85), LAVA_HOT, "face")
	part(rig, "LipTop", "Block", Vector3.new(5.2, 0.8, 0.7), P(0, 6.4, -4.95), ROCK_DARK, "face")
	part(rig, "LipBottom", "Block", Vector3.new(5.0, 0.8, 0.7), P(0, 5.2, -4.95), ROCK_DARK, "face")
	-- Lava "hair" bubbling on top of the head.
	part(rig, "Drip1", "NeonBall", Vector3.one * 1.6, P(-1.6, 11.5, -0.2), LAVA, "glow")
	part(rig, "Drip2", "NeonBall", Vector3.one * 1.3, P(0.9, 11.8, -1.0), LAVA_HOT, "glow")
	part(rig, "Drip3", "NeonBall", Vector3.one * 1.1, P(2.4, 11.2, 0.8), LAVA, "glow")
	if parent then
		rig.model.Parent = parent
	end
	return rig
end

local function browAngle(mood: string, side: number): (number, number)
	-- Returns (z rotation, y offset).
	if mood == "angry" then
		return math.rad(side * 26), -0.3
	elseif mood == "furious" then
		return math.rad(side * 36), -0.5
	elseif mood == "smug" then
		return if side < 0 then math.rad(-14) else math.rad(10), if side < 0 then 0.6 else 0
	elseif mood == "shocked" then
		return math.rad(side * -12), 1.1
	elseif mood == "sleepy" or mood == "dizzy" then
		return math.rad(side * -8), 0.2
	end
	return math.rad(side * 16), 0
end

-- Places every part for this frame.
function ForgeheartModel.pose(rig: Rig, root: CFrame, pose: Pose, dt: number)
	rig.clock += dt
	local t = rig.clock
	local shrink = 1 - math.clamp(pose.deflate, 0, 1) * 0.55
	local s = rig.scale * shrink
	local squash = math.clamp(pose.squash, 0.5, 1.6)
	local wide = 1 / math.sqrt(squash)
	-- Feet stay on the floor: the body drops when squashed or deflated.
	local drop = ((1 - squash) * 7.5 + (1 - shrink) * 9) * rig.scale
	local frame = root * CFrame.new(0, -drop, 0) * CFrame.Angles(0, pose.spin, 0) * CFrame.Angles(pose.lean, 0, 0)
	local closed = pose.eyesClosed or BossRig.blinking(rig)
	local gaze = BossRig.gaze(frame, pose.lookAt, 0.55)
	local furious = pose.mood == "furious"
	-- Lava glow: breathing, hotter when furious / charging (pose.glow).
	local glow = math.clamp(0.35 + math.sin(t * (if furious then 7 else 3)) * 0.25 + pose.glow * 0.6, 0, 1)
	local lava = LAVA:Lerp(LAVA_HOT, glow)
	local open = math.clamp(pose.mouth, 0, 1)
	local lips = 0.4 + open * 2.4
	-- Arms swing around the shoulders: raise (+) or slam (-).
	local raise = math.clamp(pose.broom, -1, 1)
	local armAngle = if raise >= 0 then -raise * math.rad(150) else -raise * math.rad(40)
	local slamReach = math.max(0, -raise)

	for _, entry in rig.parts do
		local p = entry.part
		local base = entry.base
		local name = p.Name
		local position = base.Position * s
		local rotation = base.Rotation
		local alpha = entry.transparency
		local size = entry.size * shrink
		local group = entry.group
		if group == "body" then
			size = Vector3.new(size.X * wide, size.Y * squash, size.Z * wide)
			local color = if furious then ROCK:Lerp(RED, 0.25 + math.sin(t * 6) * 0.1) else ROCK
			if pose.tint and pose.tintAlpha > 0 then
				color = color:Lerp(pose.tint, math.clamp(pose.tintAlpha, 0, 1))
			end
			if pose.flash > 0 then
				color = color:Lerp(WHITE, math.clamp(pose.flash, 0, 1))
			end
			p.Color = color
		elseif group == "head" then
			position = Vector3.new(position.X * wide, position.Y * squash, position.Z * wide)
			local color = ROCK
			if pose.flash > 0 then
				color = color:Lerp(WHITE, math.clamp(pose.flash, 0, 1))
			end
			p.Color = color
		elseif group == "face" or group == "glow" then
			position = Vector3.new(position.X * wide, position.Y * squash, position.Z * wide)
		end
		if group == "glow" then
			p.Color = if name == "Heart" then LAVA_HOT:Lerp(WHITE, math.clamp(pose.glow - 0.6, 0, 0.6)) else lava
			if name == "Heart" then
				size *= 1 + math.sin(t * (if furious then 9 else 4)) * 0.08 + math.clamp(pose.glow, 0, 1.5) * 0.18
			elseif string.sub(name, 1, 4) == "Drip" then
				position += Vector3.new(0, math.abs(math.sin(t * 2.4 + position.X)) * 0.6 * s, 0)
			end
		end
		-- Arms and fists swing around the shoulder.
		if group == "limb" or string.sub(name, 1, 7) == "Knuckle" then
			local side = if string.sub(name, -1) == "L" then -1 else 1
			local shoulder = Vector3.new(side * 7.4 * wide, 2.6 * squash, 0) * s
			local bob = (math.sin(t * 2.2 + side) * 0.4 + pose.hands) * s
			local offset = position - shoulder
			offset = (CFrame.Angles(armAngle, 0, side * math.rad(8) * raise)):PointToWorldSpace(offset)
			position = shoulder + offset + Vector3.new(0, bob, -slamReach * 3 * s)
			rotation = CFrame.Angles(armAngle, 0, 0) * rotation
		end
		-- Face details.
		if string.sub(name, 1, 5) == "Pupil" then
			if pose.dizzy then
				local side = if string.sub(name, -1) == "L" then 1 else -1
				local a = t * 9 * side
				position += Vector3.new(math.cos(a) * 0.6, math.sin(a) * 0.6, 0) * s
			else
				position += Vector3.new(gaze.X, gaze.Y, 0) * s
			end
			alpha = if closed then 1 else 0
		elseif string.sub(name, 1, 5) == "Shine" then
			position += Vector3.new(gaze.X, gaze.Y, 0) * s
			alpha = if closed or pose.dizzy then 1 else 0
		elseif string.sub(name, 1, 8) == "EyeWhite" then
			size = if closed then Vector3.new(size.X, size.Y * 0.18, size.Z) else size
		elseif string.sub(name, 1, 4) == "Brow" then
			local side = if string.sub(name, -1) == "L" then -1 else 1
			local angle, lift = browAngle(pose.mood, side)
			rotation = CFrame.Angles(0, 0, angle)
			position += Vector3.new(0, lift * s, 0)
		elseif name == "LipBottom" then
			position += Vector3.new(0, -(lips - 0.4) * s, 0)
		elseif name == "MouthGlow" then
			size = Vector3.new(size.X, lips * s, size.Z)
			position += Vector3.new(0, -(lips - 0.4) * 0.5 * s, 0)
			p.Color = lava
		elseif string.sub(name, 1, 5) == "Tooth" then
			alpha = if open > 0.15 then 0 else 1
		end
		p.Size = size
		p.CFrame = frame * CFrame.new(position) * rotation
		p.Transparency = math.max(alpha, math.clamp(pose.fade, 0, 1))
	end
end

ForgeheartModel.silhouette = BossRig.silhouette
ForgeheartModel.destroy = BossRig.destroy

return ForgeheartModel
