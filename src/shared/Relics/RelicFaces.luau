--!strict
-- Cartoon faces for relics (Phase 5.5 "Cartoon & Goofy"). Purely visual.
--
-- A face is a few primitive parts welded to the relic: googly eyes (white +
-- ink pupil + shine), a mouth that depends on the relic's mood, and extras
-- (rosy cheeks, angry brows, sleepy lids, sunglasses...). Relics with a face
-- stop spinning: they turn toward the nearest player (or the camera) with a
-- little wobble, their pupils wander and they blink every few seconds.
--
-- Faces are built in relic units on the -Z side ("front") of the relic. Only
-- relics listed in FACES get one ("when it makes sense": mechanical or
-- abstract relics keep their look). Face parts use the "fx" role so
-- mutations never recolour the eyes; lids use "body" so they match the skin.

local Factory = require(script.Parent.RelicFactory)

type Ctx = Factory.Ctx
type Env = Factory.Env

local RelicFaces = {}

export type Mood = "happy" | "grumpy" | "sleepy" | "shy" | "surprised" | "silly" | "cool" | "cheeky" | "derp" | "smug"

export type FaceSpec = {
	-- Front centre of the face (relic units, -Z is the front).
	at: Vector3,
	-- Eye diameter (relic units).
	eye: number,
	mood: Mood,
	cheeks: boolean?,
}

local INK = Color3.fromRGB(30, 27, 75)
local MOUTH = Color3.fromRGB(70, 24, 60)
local TONGUE = Color3.fromRGB(255, 110, 150)
local BLUSH = Color3.fromRGB(255, 120, 170)
local WHITE = Color3.new(1, 1, 1)

-- Which relics get a face, and their personality.
RelicFaces.Faces = table.freeze({
	ember_shard = { at = Vector3.new(0, 0.15, -0.72), eye = 0.42, mood = "grumpy" },
	verdant_seed = { at = Vector3.new(0, -0.1, -0.74), eye = 0.42, mood = "happy", cheeks = true },
	tide_pearl = { at = Vector3.new(0, 0, -0.6), eye = 0.36, mood = "shy", cheeks = true },
	rune_tablet = { at = Vector3.new(0, 0.3, -0.24), eye = 0.42, mood = "sleepy" },
	frost_lotus = { at = Vector3.new(0, 0.14, -0.3), eye = 0.2, mood = "happy", cheeks = true },
	storm_crystal = { at = Vector3.new(0, 0.2, -0.82), eye = 0.46, mood = "surprised" },
	elder_root = { at = Vector3.new(0, 0.3, -0.6), eye = 0.32, mood = "sleepy", cheeks = true },
	ocean_orb = { at = Vector3.new(0, 0.1, -1.2), eye = 0.55, mood = "silly" },
	magma_heart = { at = Vector3.new(0, 0.1, -1.0), eye = 0.44, mood = "grumpy" },
	void_cube = { at = Vector3.new(0, 0.1, -1.25), eye = 0.5, mood = "derp" },
	sun_fragment = { at = Vector3.new(0, 0.05, -0.76), eye = 0.42, mood = "cool" },
	pocket_planet = { at = Vector3.new(0, 0.1, -1.02), eye = 0.44, mood = "happy", cheeks = true },
	rift_heart = { at = Vector3.new(0, 0.5, -0.34), eye = 0.36, mood = "cheeky" },
	eclipse_sigil = { at = Vector3.new(0, 0.05, -1.02), eye = 0.46, mood = "smug" },
	void_duster = { at = Vector3.new(0.18, 0.95, -0.78), eye = 0.36, mood = "cheeky", cheeks = true },
} :: { [string]: FaceSpec })

function RelicFaces.get(relicId: string): FaceSpec?
	return RelicFaces.Faces[relicId]
end

type Eye = { white: BasePart, pupil: BasePart?, shine: BasePart?, base: CFrame, size: Vector3, closed: boolean }

local function damp(sharpness: number, dt: number): number
	return 1 - math.exp(-sharpness * dt)
end

local function wrap(angle: number): number
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

-- Builds the face parts on `ctx` and registers its animator. No-op for relics
-- without a face.
function RelicFaces.attach(ctx: Ctx)
	local spec = RelicFaces.Faces[ctx.def.id]
	if not spec then
		return
	end
	local visual = ctx.visual
	local e = spec.eye
	local at = spec.at
	local mood = spec.mood
	local front = at.Z

	local function part(kind: string, size: Vector3, cf: CFrame, color: Color3, role: string?, material: Enum.Material?, name: string?): BasePart
		return ctx:part({ kind = kind, size = size, cf = cf, color = color, role = role or "fx", material = material, name = name or "Face" })
	end

	-- Eyes ------------------------------------------------------------------
	local eyes: { Eye } = {}
	for _, side in { -1, 1 } do
		local center = CFrame.new(at.X + side * e * 0.62, at.Y, front - e * 0.12)
		local winkClosed = mood == "cheeky" and side < 0
		if winkClosed then
			-- Closed eye: a little dark arc.
			part("Ellipsoid", Vector3.new(e * 0.95, e * 0.18, e * 0.3), center * CFrame.new(0, -e * 0.05, -e * 0.2), INK, nil, nil, "EyeClosed")
			continue
		end
		local white = part("Ball", Vector3.one * e, center, WHITE, nil, nil, "EyeWhite")
		local pupil: BasePart? = nil
		local shine: BasePart? = nil
		if mood ~= "cool" then
			local inward = if mood == "derp" then -side * e * 0.18 else 0
			pupil = part("Ball", Vector3.one * e * 0.56, center * CFrame.new(inward, -e * 0.05, -e * 0.3), INK, nil, nil, "Pupil")
			shine = part("Ball", Vector3.one * e * 0.2, center * CFrame.new(inward + e * 0.12, e * 0.1, -e * 0.5), WHITE, nil, Enum.Material.Neon, "Shine")
		end
		table.insert(eyes, { white = white, pupil = pupil, shine = shine, base = center, size = white.Size, closed = false })
		if mood == "sleepy" or mood == "smug" then
			-- Heavy lid in the relic's own colour (recoloured with mutations).
			part("Ellipsoid", Vector3.new(e * 1.08, e * 0.56, e * 1.08), center * CFrame.new(0, e * 0.26, -e * 0.04), ctx.def.primary, "body", nil, "Lid")
		end
		if mood == "grumpy" then
			part("Block", Vector3.new(e * 0.8, e * 0.17, e * 0.18), center * CFrame.new(side * e * 0.05, e * 0.62, -e * 0.3) * CFrame.Angles(0, 0, math.rad(side * 22)), INK, nil, nil, "Brow")
		end
		if mood == "surprised" then
			part("Block", Vector3.new(e * 0.7, e * 0.14, e * 0.16), center * CFrame.new(0, e * 0.78, -e * 0.25) * CFrame.Angles(0, 0, math.rad(-side * 12)), INK, nil, nil, "Brow")
		end
		if spec.cheeks then
			part("Ellipsoid", Vector3.new(e * 0.5, e * 0.3, e * 0.12), CFrame.new(at.X + side * e * 1.2, at.Y - e * 0.6, front - e * 0.02), BLUSH, nil, nil, "Cheek").Transparency = 0.25
		end
	end
	if mood == "cool" then
		-- Sunglasses: two dark lenses and a bridge.
		for _, side in { -1, 1 } do
			part("Block", Vector3.new(e * 1.05, e * 0.62, e * 0.16), CFrame.new(at.X + side * e * 0.62, at.Y + e * 0.02, front - e * 0.66), INK, nil, nil, "Shades")
		end
		part("Block", Vector3.new(e * 0.5, e * 0.12, e * 0.12), CFrame.new(at.X, at.Y + e * 0.18, front - e * 0.66), INK, nil, nil, "Shades")
	end

	-- Mouth -----------------------------------------------------------------
	local mouthCf = CFrame.new(at.X, at.Y - e * 0.95, front - e * 0.05)
	if mood == "happy" or mood == "silly" or mood == "derp" or mood == "cheeky" or mood == "smug" then
		part("Ellipsoid", Vector3.new(e * 1.15, e * 0.5, e * 0.3), mouthCf, MOUTH, nil, nil, "Mouth")
		if mood == "silly" or mood == "derp" then
			part("Ellipsoid", Vector3.new(e * 0.48, e * 0.6, e * 0.24), mouthCf * CFrame.new(e * 0.12, -e * 0.32, -e * 0.08), TONGUE, nil, nil, "Tongue")
		else
			part("Ellipsoid", Vector3.new(e * 0.55, e * 0.22, e * 0.2), mouthCf * CFrame.new(0, -e * 0.1, -e * 0.08), TONGUE, nil, nil, "Tongue")
		end
	elseif mood == "surprised" then
		part("Ellipsoid", Vector3.new(e * 0.45, e * 0.62, e * 0.3), mouthCf, MOUTH, nil, nil, "Mouth")
	elseif mood == "cool" then
		part("Ellipsoid", Vector3.new(e * 0.8, e * 0.22, e * 0.24), mouthCf * CFrame.new(e * 0.15, 0, 0) * CFrame.Angles(0, 0, math.rad(8)), MOUTH, nil, nil, "Mouth")
	elseif mood == "shy" then
		part("Ellipsoid", Vector3.new(e * 0.55, e * 0.2, e * 0.24), mouthCf, MOUTH, nil, nil, "Mouth")
	else -- grumpy / sleepy: flat little line
		part("Ellipsoid", Vector3.new(e * 0.75, e * 0.16, e * 0.24), mouthCf * CFrame.Angles(0, 0, math.rad(if mood == "grumpy" then -6 else 0)), MOUTH, nil, nil, "Mouth")
	end

	-- Behaviour -------------------------------------------------------------
	visual.spin = false
	visual.wantsFocus = true
	local yaw = 0
	local written: CFrame? = nil
	local shapeTransform = CFrame.identity
	local phase = (string.len(ctx.def.id) * 1.37) % 6.28
	local nextBlink = 1.5 + phase * 0.4
	local blinkUntil = 0
	local blinking = false

	ctx:animate(function(env: Env)
		-- Compose with what the shape / mutation animators wrote this frame.
		local current = visual.bodyTransform
		if written == nil or current ~= written then
			shapeTransform = current
		end
		local t = env.time
		local target = env.focus or env.camera
		if target then
			local localTarget = env.rootCFrame:PointToObjectSpace(target)
			if localTarget.X * localTarget.X + localTarget.Z * localTarget.Z > 0.01 then
				local desired = math.atan2(-localTarget.X, -localTarget.Z)
				yaw += wrap(desired - yaw) * damp(5, env.dt)
			end
		end
		-- Idle personality: a slow look-around and a happy wobble.
		local look = math.sin(t * 0.6 + phase) * 0.25
		local wobble = math.sin(t * 2.3 + phase) * (if mood == "sleepy" then 0.03 else 0.07)
		local transform = CFrame.Angles(0, yaw + look, 0) * CFrame.Angles(0, 0, wobble) * shapeTransform
		visual.bodyTransform = transform
		written = transform

		-- Blink (resize the whites for a split second).
		if t >= nextBlink and not blinking then
			blinking = true
			blinkUntil = t + 0.13
			for _, eye in eyes do
				eye.white.Size = Vector3.new(eye.size.X, eye.size.Y * 0.12, eye.size.Z)
				if eye.pupil then
					eye.pupil.Transparency = 1
				end
				if eye.shine then
					eye.shine.Transparency = 1
				end
			end
		elseif blinking and t >= blinkUntil then
			blinking = false
			nextBlink = t + 2.4 + (math.sin(t * 3.7 + phase) + 1) * 1.6
			for _, eye in eyes do
				eye.white.Size = eye.size
				if eye.pupil then
					eye.pupil.Transparency = 0
				end
				if eye.shine then
					eye.shine.Transparency = 0
				end
			end
		end

		-- Pupils wander (derp eyes stay crossed).
		if mood ~= "derp" then
			local px = math.sin(t * 0.9 + phase) * e * 0.12 - look * e * 0.35
			local py = math.cos(t * 0.7 + phase) * e * 0.06
			for _, eye in eyes do
				if eye.pupil then
					ctx:move(eye.pupil, eye.base * CFrame.new(px, py - e * 0.05, -e * 0.3))
				end
				if eye.shine then
					ctx:move(eye.shine, eye.base * CFrame.new(px + e * 0.12, py + e * 0.1, -e * 0.5))
				end
			end
		end
	end)
end

return RelicFaces
