--!strict
-- Tempest Seraph's cartoon body (V2 phase 7B), built on the client from
-- native Roblox parts only (balls, ellipsoids, blocks, a cylinder, Neon for
-- the lightning): no sculpted mesh, no external asset. A puffy thunder-cloud
-- diva: a white / lavender cloud made of round puffs, BIG expressive eyes
-- with diva lashes, arched ink eyebrows, blush, a small ink mouth, a golden
-- crown worn crooked on top, two little white wings that flap and three neon
-- yellow zig-zag lightning bolts dangling under the cloud
-- (docs/ART_DIRECTION.md, "Tempest Seraph").
--
-- Same interface as ForgeheartModel (BossRig.ModelModule). She FLOATS: the
-- body is centred on the root CFrame (the server anchor is already `height`
-- studs above the floor) and gently bobs. Pose fields used: squash, lean,
-- spin, broom (= wings and puffy side "arms": 1 big flap up, -1 swoop down /
-- forward), hands (side puffs bob), mouth, mood (brows, eyes, mouth, storm
-- tint: grumpy / angry / furious / smug / shocked / sleepy / dizzy, plus an
-- extra "sad"), lookAt, dizzy (spiral pupils), eyesClosed, fade, tint /
-- tintAlpha / flash (white flash + a squint), glow (the bolts get brighter,
-- longer and flicker) and deflate (the comic defeat: the puffs pop one by
-- one, she shrinks into a sad little cloud, the crown slides over an eye and
-- the bolts turn into a drizzle; from deflate 0.85 she is "sad", not dizzy).
-- She is never scary: the furious "storm face" is a violet-blue cartoon
-- cloud, never grey-dark.

local BossRig = require(script.Parent.BossRig)

local TempestSeraphModel = {}

export type Rig = BossRig.Rig
export type Pose = BossRig.Pose

local INK = Color3.fromRGB(30, 27, 75)
local WHITE = Color3.new(1, 1, 1)
local CLOUD = Color3.fromRGB(240, 238, 255)
local PUFF = Color3.fromRGB(250, 249, 255)
local LAVENDER = Color3.fromRGB(214, 202, 255)
local SKY = Color3.fromRGB(196, 222, 255)
local STORM = Color3.fromRGB(150, 146, 236)
local GOLD = Color3.fromRGB(255, 200, 50)
local GOLD_LIGHT = Color3.fromRGB(255, 232, 120)
local GEM = Color3.fromRGB(255, 96, 170)
local BOLT = Color3.fromRGB(255, 226, 70)
local BOLT_HOT = Color3.fromRGB(255, 252, 205)
local RAIN = Color3.fromRGB(140, 196, 255)
local PINK = Color3.fromRGB(255, 150, 196)
local RED = Color3.fromRGB(255, 80, 100)
local TONGUE = Color3.fromRGB(255, 110, 150)
local WING = Color3.fromRGB(255, 252, 238)
local FEATHER = Color3.fromRGB(255, 234, 166)

-- Cloud parts and their rest colour (tinted / flashed every frame).
local CLOUD_COLORS: { [string]: Color3 } = {
	Body = CLOUD,
	PuffTop = PUFF,
	PuffTopL = PUFF,
	PuffTopR = PUFF,
	PuffL = CLOUD,
	PuffR = CLOUD,
	PuffBotL = LAVENDER,
	PuffBotR = LAVENDER,
	PuffBack = SKY,
}
-- Order in which the puffs pop when she is defeated (around the cloud).
local PUFF_ORDER: { [string]: number } = {
	PuffTop = 0,
	PuffTopR = 1,
	PuffR = 2,
	PuffBotR = 3,
	PuffBotL = 4,
	PuffL = 5,
	PuffTopL = 6,
	PuffBack = 7,
}

-- Attachment frames (studs before scale): the crooked crown, the wing roots
-- (X mirrored) and the tops of the three bolts. The parts of these groups
-- are built relative to their frame so they can wobble / flap / swing.
local CROWN = CFrame.new(1.5, 8.6, 0.6) * CFrame.Angles(math.rad(-8), 0, math.rad(-24))
local WING_ROOT = Vector3.new(6.2, 2.4, 1.8)
local BOLT_TOPS: { [string]: CFrame } = {
	L = CFrame.new(-5.2, -5.0, -0.4) * CFrame.Angles(0, 0, math.rad(-28)),
	M = CFrame.new(0, -4.7, -0.8),
	R = CFrame.new(5.2, -5.0, -0.4) * CFrame.Angles(0, 0, math.rad(28)),
}
-- One lightning bolt: a cartoon zig-zag (points under its top, studs).
local ZIGZAG = { Vector2.new(0, 0), Vector2.new(0.9, -1.5), Vector2.new(-0.5, -2.3), Vector2.new(0.5, -3.8) }
-- Eye centres (X mirrored) and the mouth line.
local EYE = Vector3.new(2.1, 1.0, -5.0)
local MOUTH_Y = -2.25

function TempestSeraphModel.defaultPose(): Pose
	-- The diva at rest (portal card, Codex): smug side-eye.
	return BossRig.defaultPose("smug")
end

local part = BossRig.part

-- Builds the rig. `scale` 1 = full size (cloud ~22 studs wide wings
-- included, ~20 tall from the crown to the tip of the bolts, centred on the
-- root).
function TempestSeraphModel.build(scale: number, parent: Instance?): Rig
	local rig = BossRig.new("TempestSeraph", scale, "smug")
	local P = CFrame.new
	-- Cloud: the main puff (her face) and the round puffs around it.
	part(rig, "Body", "Ellipsoid", Vector3.new(14, 10, 11), P(0, 0, 0), CLOUD, "body")
	part(rig, "PuffTop", "Ball", Vector3.one * 7.6, P(0.4, 4.4, 1.0), PUFF, "puff")
	part(rig, "PuffTopL", "Ball", Vector3.one * 6.0, P(-4.2, 3.0, 0.8), PUFF, "puff")
	part(rig, "PuffTopR", "Ball", Vector3.one * 6.2, P(4.4, 3.2, 1.0), PUFF, "puff")
	part(rig, "PuffL", "Ball", Vector3.one * 6.0, P(-6.8, -0.4, 0.6), CLOUD, "puff")
	part(rig, "PuffR", "Ball", Vector3.one * 5.8, P(6.8, -0.2, 0.6), CLOUD, "puff")
	part(rig, "PuffBotL", "Ball", Vector3.one * 5.0, P(-4.2, -3.4, 0.4), LAVENDER, "puff")
	part(rig, "PuffBotR", "Ball", Vector3.one * 5.0, P(4.2, -3.4, 0.4), LAVENDER, "puff")
	part(rig, "PuffBack", "Ball", Vector3.one * 7.4, P(0, 0.6, 3.6), SKY, "puff")
	for _, side in { -1, 1 } do
		local key = if side < 0 then "L" else "R"
		local ex = side * EYE.X
		-- Big expressive eyes with a diva eyeliner flick.
		part(rig, "EyeWhite" .. key, "Ellipsoid", Vector3.new(3.2, 3.9, 2.0), P(ex, EYE.Y, EYE.Z), WHITE, "face")
		part(rig, "Pupil" .. key, "Ball", Vector3.one * 1.7, P(ex, EYE.Y - 0.25, -5.75), INK, "face")
		part(rig, "Shine" .. key, "Ball", Vector3.one * 0.6, P(ex + 0.45, EYE.Y + 0.35, -6.45), WHITE, "face")
		part(rig, "Lash" .. key, "Block", Vector3.new(1.3, 0.32, 0.32), P(side * (EYE.X + 1.45), EYE.Y + 1.6, -5.1) * CFrame.Angles(0, 0, side * math.rad(35)), INK, "face")
		part(rig, "Brow" .. key, "Block", Vector3.new(2.8, 0.65, 0.5), P(ex, 3.6, -4.75), INK, "face")
		part(rig, "Cheek" .. key, "Ellipsoid", Vector3.new(1.9, 1.0, 0.4), P(side * 4.1, -0.9, -4.55), PINK, "face", 0.35)
		-- Little wings on the upper back (built relative to their root).
		part(rig, "Wing" .. key, "Ellipsoid", Vector3.new(5.4, 2.6, 0.5), P(side * 2.6, 1.0, 0) * CFrame.Angles(0, 0, side * math.rad(30)), WING, "wing")
		part(rig, "Feather" .. key, "Ellipsoid", Vector3.new(4.2, 1.7, 0.45), P(side * 2.3, -0.6, 0.1) * CFrame.Angles(0, 0, side * math.rad(8)), FEATHER, "wing")
	end
	-- Small ink mouth (three segments: frown, smile, open "O") + tongue.
	part(rig, "MouthL", "Block", Vector3.new(1.5, 0.5, 0.4), P(-1.3, MOUTH_Y + 0.2, -5.1), INK, "face")
	part(rig, "MouthM", "Block", Vector3.new(1.5, 0.5, 0.4), P(0, MOUTH_Y, -5.2), INK, "face")
	part(rig, "MouthR", "Block", Vector3.new(1.5, 0.5, 0.4), P(1.3, MOUTH_Y + 0.2, -5.1), INK, "face")
	part(rig, "Tongue", "Block", Vector3.new(1.2, 0.65, 0.3), P(0, MOUTH_Y - 0.35, -5.32), TONGUE, "face", 1)
	-- Crooked golden crown: band, five diamond tips, a pink gem (relative
	-- to the CROWN frame).
	part(rig, "CrownBand", "VCyl", Vector3.new(5.0, 1.6, 5.0), P(0, 0, 0), GOLD, "crown")
	for i = 1, 5 do
		local a = (i - 1) * math.pi * 2 / 5
		part(rig, "CrownTip" .. i, "Block", Vector3.new(1.25, 1.25, 0.4), CFrame.Angles(0, a, 0) * P(0, 1.15, -2.38) * CFrame.Angles(0, 0, math.pi / 4), GOLD_LIGHT, "crown")
	end
	part(rig, "CrownGem", "NeonBall", Vector3.one * 0.85, P(0, 0.05, -2.6), GEM, "crown")
	-- Three neon zig-zag bolts under the cloud (relative to their top).
	for _, key in { "L", "M", "R" } do
		local mirror = if key == "L" then -1 else 1
		local length = if key == "M" then 1.1 else 0.85
		for i = 1, 3 do
			local a, b = ZIGZAG[i], ZIGZAG[i + 1]
			local ax, ay = a.X * mirror * length, a.Y * length
			local bx, by = b.X * mirror * length, b.Y * length
			local dx, dy = bx - ax, by - ay
			local len = math.sqrt(dx * dx + dy * dy)
			local base = P((ax + bx) / 2, (ay + by) / 2, 0) * CFrame.Angles(0, 0, math.atan2(-dx, dy))
			part(rig, "Bolt" .. key .. i, "NeonBlock", Vector3.new(0.55, len + 0.35, 0.35), base, BOLT, "bolt")
		end
	end
	if parent then
		rig.model.Parent = parent
	end
	return rig
end

local function browAngle(mood: string, side: number): (number, number)
	-- Returns (z rotation, y offset).
	if mood == "angry" then
		return math.rad(side * 24), -0.3
	elseif mood == "furious" then
		return math.rad(side * 34), -0.45
	elseif mood == "smug" then
		-- One diva eyebrow raised.
		return if side < 0 then math.rad(-14) else math.rad(6), if side < 0 then 0.55 else 0
	elseif mood == "shocked" then
		return math.rad(side * -12), 1.0
	elseif mood == "sad" then
		return math.rad(side * -22), 0.35
	elseif mood == "sleepy" or mood == "dizzy" then
		return math.rad(side * -8), 0.2
	end
	return math.rad(side * 14), 0
end

local function mouthShape(mood: string, open: number): (number, number, number)
	-- Returns (corner Y offset, middle height, middle Y offset).
	if mood == "smug" or mood == "happy" then
		return 0.35, 0.45 + open * 1.6, -0.25 - open * 0.8
	elseif mood == "shocked" or mood == "dizzy" then
		return -0.05, 1.1 + open * 1.0, -0.4 - open * 0.5
	elseif mood == "sad" then
		return -0.5, 0.45 + open * 0.8, 0.1 - open * 0.4
	end
	-- grumpy / angry / furious / sleepy: frown (corners down).
	return -0.35, 0.45 + open * 1.6, -open * 0.8
end

-- Places every part for this frame.
function TempestSeraphModel.pose(rig: Rig, root: CFrame, pose: Pose, dt: number)
	rig.clock += dt
	local t = rig.clock
	local pop = math.clamp(pose.deflate, 0, 1)
	-- Defeated: the cloud shrinks to a sad little cloud (40 %).
	local shrink = 1 - pop * 0.6
	local s = rig.scale * shrink
	local squash = math.clamp(pose.squash, 0.5, 1.6)
	local wide = 1 / math.sqrt(squash)
	-- She floats: a gentle bob around the anchor (no feet to keep down).
	local bob = math.sin(t * 1.9) * 0.45 * rig.scale * (1 - pop)
	local frame = root * CFrame.new(0, bob, 0) * CFrame.Angles(0, pose.spin, 0) * CFrame.Angles(pose.lean, 0, 0)
	local sad = pose.mood == "sad" or pop >= 0.85
	local mood = if sad then "sad" else pose.mood
	local dizzy = pose.dizzy and not sad
	local furious = mood == "furious"
	local closed = pose.eyesClosed or BossRig.blinking(rig) or pose.flash > 0.55
	local fade = math.clamp(pose.fade, 0, 1)
	-- Eyes: pupils follow the target (smug diva side-eye, sad looks down).
	local gaze = BossRig.gaze(frame, pose.lookAt, 0.55)
	if mood == "smug" then
		gaze = Vector3.new(0.55, 0.12, 0)
	elseif sad then
		gaze = Vector3.new(0, -0.45, 0)
	end
	local eyeK = if mood == "shocked" then 1.18 elseif furious then 0.92 else 1
	local eyeKY = if mood == "smug" then eyeK * 0.72 else eyeK
	local pupilK = if mood == "shocked" then 0.7 elseif furious then 0.8 else 1
	local open = math.clamp(pose.mouth, 0, 1)
	local cornerY, middleH, middleY = mouthShape(mood, open)
	local cheekAlpha = if furious then 0.05 elseif mood == "angry" then 0.15 else 0.35
	-- Wings / puffy arms: 1 = big flap up, -1 = swoop down and forward.
	local broom = math.clamp(pose.broom, -1, 1)
	local flap, sweep = 0, 0
	if dizzy then
		flap, sweep = -0.25 + math.sin(t * 3) * 0.15, 0
	elseif broom >= 0 then
		flap = 0.1 + broom * 1.0 + math.sin(t * (7 + broom * 6)) * (0.22 + broom * 0.2)
		sweep = 0
	else
		flap = broom * 0.8 + math.sin(t * 7) * 0.08
		sweep = broom * 0.9
	end
	flap -= pop * 0.7
	local raise, swoop = math.max(0, broom), math.max(0, -broom)
	-- Lightning: brighter, longer and flickering more when charged / furious.
	local charge = math.clamp(pose.glow, 0, 1.5)
	local flickerSpeed = if furious then 31 else 19
	local boltLength = 1 + charge * 0.2
	local rain = math.clamp((pop - 0.25) / 0.2, 0, 1)
	-- Crown: wobbles, hops when shocked, slides over an eye when defeated.
	local crownWobble = math.sin(t * 3.1) * 0.06 + pose.flash * math.sin(t * 40) * 0.25 + (if dizzy then math.sin(t * 5) * 0.2 else 0) - pop * 0.45
	local crownHop = (if mood == "shocked" then 0.8 else 0) + raise * 0.3
	local crownScale = rig.scale * (1 - pop * 0.3)
	local crownPos = Vector3.new(CROWN.Position.X * wide, CROWN.Position.Y * squash, CROWN.Position.Z * wide) * s
		+ Vector3.new(0, crownHop * s, 0)
		+ Vector3.new(pop * 0.8, -pop * 1.7, 0) * rig.scale
	local crownFrame = CFrame.new(crownPos) * CROWN.Rotation * CFrame.Angles(0, 0, crownWobble)

	for _, entry in rig.parts do
		local p = entry.part
		local name = p.Name
		local group = entry.group
		local base = entry.base
		local alpha = entry.transparency
		local size = entry.size * shrink
		local cf: CFrame
		if group == "body" or group == "puff" then
			local position = base.Position * s
			position = Vector3.new(position.X * wide, position.Y * squash, position.Z * wide)
			if group == "body" then
				size = Vector3.new(size.X * wide, size.Y * squash, size.Z * wide)
			else
				-- Each puff breathes on its own and pops (swell, then gone)
				-- one after the other when she is defeated.
				local index = PUFF_ORDER[name] or 0
				local k = math.clamp((pop - index * 0.06) / 0.35, 0, 1)
				local popScale = if k < 0.3 then 1 + k / 0.3 * 0.25 else math.max(0, 1.25 * (1 - (k - 0.3) / 0.7))
				size *= (1 + math.sin(t * 2.3 + index * 1.3) * 0.035) * popScale * (1 + math.clamp(pose.flash, 0, 1) * 0.06)
				if popScale < 0.08 then
					alpha = 1
				end
				if name == "PuffL" or name == "PuffR" then
					-- The side puffs are her puffy arms: raised for a diva
					-- flourish, swept forward for a swoop, bobbing (hands).
					local side = if name == "PuffL" then -1 else 1
					local lift = raise * 1.6 - swoop * 0.6 + math.sin(t * 2.4 + side) * 0.3 + pose.hands * 0.6
					position += Vector3.new(side * raise * 0.6, lift, -swoop * 1.8) * s
				end
			end
			local color = CLOUD_COLORS[name] or CLOUD
			if furious then
				color = color:Lerp(STORM, 0.35 + math.sin(t * 6) * 0.08)
			elseif mood == "angry" then
				color = color:Lerp(STORM, 0.12)
			end
			if pose.tint and pose.tintAlpha > 0 then
				color = color:Lerp(pose.tint, math.clamp(pose.tintAlpha, 0, 1))
			end
			if pose.flash > 0 then
				color = color:Lerp(WHITE, math.clamp(pose.flash, 0, 1))
			end
			p.Color = color
			cf = frame * CFrame.new(position) * base.Rotation
		elseif group == "face" then
			local side = if string.sub(name, -1) == "L" then -1 else 1
			local position = base.Position
			local rotation = base.Rotation
			local prefix5 = string.sub(name, 1, 5)
			if prefix5 == "EyeWh" or prefix5 == "Pupil" or prefix5 == "Shine" or prefix5 == "LashL" or prefix5 == "LashR" then
				-- Eye parts scale around the eye centre (shocked / smug).
				local centre = Vector3.new(side * EYE.X, EYE.Y, EYE.Z)
				local offset = position - centre
				if prefix5 == "LashL" or prefix5 == "LashR" then
					if closed then
						-- The flick follows the closed-eye line.
						offset = Vector3.new(offset.X * 0.95, 0.25, offset.Z)
						rotation = CFrame.Angles(0, 0, side * math.rad(15))
					end
				end
				position = centre + Vector3.new(offset.X * eyeK, offset.Y * eyeKY, offset.Z)
			end
			position *= s
			position = Vector3.new(position.X * wide, position.Y * squash, position.Z * wide)
			if prefix5 == "EyeWh" then
				-- Closed eyes are happy ink lines (visible on the white cloud).
				size = Vector3.new(size.X * eyeK, size.Y * (if closed then 0.14 else eyeKY), size.Z)
				p.Color = if closed then INK else WHITE
			elseif prefix5 == "Pupil" then
				if dizzy then
					local a = t * 9 * -side
					local r = 0.3 + math.abs(math.sin(t * 2)) * 0.3
					position += Vector3.new(math.cos(a) * r, math.sin(a) * r, 0) * s
				else
					position += Vector3.new(gaze.X, gaze.Y, 0) * s
				end
				size *= pupilK
				alpha = if closed then 1 else 0
			elseif prefix5 == "Shine" then
				position += Vector3.new(gaze.X, gaze.Y, 0) * s
				alpha = if closed or dizzy then 1 else 0
			elseif string.sub(name, 1, 4) == "Brow" then
				local angle, lift = browAngle(mood, side)
				rotation = CFrame.Angles(0, 0, angle)
				position += Vector3.new(0, lift * s, 0)
			elseif prefix5 == "Cheek" then
				p.Color = if furious then RED else PINK
				alpha = cheekAlpha
			elseif name == "MouthL" or name == "MouthR" then
				position += Vector3.new(0, cornerY * s, 0)
				rotation = CFrame.Angles(0, 0, side * cornerY * 0.9)
			elseif name == "MouthM" then
				size = Vector3.new(size.X, middleH * s, size.Z)
				position += Vector3.new(0, middleY * s, 0)
			elseif name == "Tongue" then
				-- Sits at the bottom of the open mouth.
				local y = MOUTH_Y + middleY - middleH / 2 + 0.35
				position = Vector3.new(position.X, y * s * squash, position.Z)
				alpha = if open > 0.35 then 0 else 1
			end
			cf = frame * CFrame.new(position) * rotation
		elseif group == "crown" then
			size = entry.size * (1 - pop * 0.3)
			if name == "CrownGem" then
				p.Color = GEM:Lerp(WHITE, (math.sin(t * 4) + 1) * 0.15)
			end
			cf = frame * crownFrame * CFrame.new(base.Position * crownScale) * base.Rotation
		elseif group == "wing" then
			local side = if string.sub(name, -1) == "L" then -1 else 1
			local rootPos = Vector3.new(side * WING_ROOT.X * wide, WING_ROOT.Y * squash + raise * 0.4, WING_ROOT.Z * wide) * s
			local wingRoot = CFrame.new(rootPos) * CFrame.Angles(0, -side * (0.3 + sweep), 0) * CFrame.Angles(0, 0, side * flap)
			cf = frame * wingRoot * CFrame.new(base.Position * s) * base.Rotation
		else
			-- Lightning bolts.
			local col = string.sub(name, 5, 5)
			local seg = tonumber(string.sub(name, 6, 6)) or 1
			local colIndex = if col == "L" then -1 elseif col == "M" then 0 else 1
			if rain > 0 then
				-- Defeated: the bolts turn into a little drizzle falling from
				-- the sad cloud.
				local i = (colIndex + 1) * 3 + seg
				local fall = (t * 1.3 + i * 0.37) % 1
				local x = (i - 5) * 1.4 * s
				local z = (if i % 2 == 0 then -0.6 else 0.6) * s
				size = Vector3.new(0.22, 0.75, 0.22) * rig.scale
				p.Color = RAIN
				alpha = math.max(1 - rain, fall * fall * 0.9)
				cf = frame * CFrame.new(x, (-4.6 - fall * 9) * s, z)
			else
				local top = BOLT_TOPS[col] or BOLT_TOPS.M
				local topPos = Vector3.new(top.Position.X * wide, top.Position.Y * squash, top.Position.Z * wide) * s
				local swing = math.sin(t * 2.1 + colIndex * 1.7) * 0.09
				local zap = math.sin(t * 37 + seg * 2.1 + colIndex) * (0.05 + charge * 0.12)
				local boltTop = CFrame.new(topPos) * top.Rotation * CFrame.Angles(0, 0, swing)
				local position = base.Position * s * boltLength + Vector3.new(zap * s, 0, 0)
				size = Vector3.new(size.X * (1 + charge * 0.4), size.Y * boltLength, size.Z)
				local spark = math.sin(t * flickerSpeed + seg * 1.9 + colIndex * 2.7) * math.sin(t * 5.3 + colIndex * 1.1)
				p.Color = BOLT:Lerp(BOLT_HOT, math.clamp(0.15 + charge * 0.55 + math.max(0, spark) * 0.3, 0, 1))
				alpha = if spark > 0.8 - charge * 0.25 then 0.7 else 0
				alpha = math.max(alpha, math.clamp(pop / 0.25, 0, 1))
				cf = frame * boltTop * CFrame.new(position) * base.Rotation
			end
		end
		p.Size = size
		p.CFrame = cf
		p.Transparency = math.max(alpha, fade)
	end
end

TempestSeraphModel.silhouette = BossRig.silhouette
TempestSeraphModel.destroy = BossRig.destroy

return TempestSeraphModel
