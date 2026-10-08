--!strict
-- The boss arena (V2 phase 6): a round floating floor far away from the
-- island (Config/Bosses Arena.Center), with one decor THEME per boss
-- (BossDef.theme):
--   closet   the Void Warden's "janitor's closet of the Void": pastel tiles,
--            a fat candy bumper, giant cleaning props, floating bubbles; the
--            quadrant lines help read the "Grand Ménage" special;
--   volcano  Forgeheart's forge (phase 7A): warm cartoon rock, glowing lava
--            cracks, six cooled-rock SAFE PADS (Final Eruption), a ring of
--            round boulders, a lava sea below and a volcano behind.
--
-- Built by BossService when the portal opens, destroyed after every
-- expedition. Shared by every theme: the same floor size, invisible walls so
-- nobody falls off (no frustration for young players), the four grapple
-- anchors and the arrival points. Native parts only, within
-- Bosses.Arena.PartBudget, 2 lights, 1 emitter per theme. The decor never
-- hurts: only announced attacks do (no invisible damage).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Bosses = require(Shared.Config.Bosses)
local Palette = require(Shared.Config.Palette)
local Parts = require(script.Parent.Parts)

local ArenaBuilder = {}

local M = Enum.Material
local A = Bosses.Arena

local FLOOR = Color3.fromRGB(214, 200, 255)
local TILE = Color3.fromRGB(255, 236, 250)
local LINE = Color3.fromRGB(150, 130, 230)
local BUMPER_A = Palette.Core.Sunny
local BUMPER_B = Color3.fromRGB(255, 150, 214)
local UNDER = Color3.fromRGB(150, 120, 235)
local BUCKET = Color3.fromRGB(90, 170, 255)
local SOAP = Color3.fromRGB(120, 230, 170)
local SPONGE = Color3.fromRGB(255, 226, 90)
local BUBBLE = Color3.fromRGB(205, 245, 255)
-- Volcano theme (phase 7A): warm cartoon rock, never black.
local ROCK = Color3.fromRGB(150, 98, 86)
local ROCK_LIGHT = Color3.fromRGB(196, 136, 110)
local ROCK_COOL = Color3.fromRGB(150, 160, 196)
local LAVA = Color3.fromRGB(255, 120, 40)
local LAVA_HOT = Color3.fromRGB(255, 214, 72)

export type Arena = {
	model: Model,
	center: Vector3,
	floorY: number,
	-- Arrival points (on the -Z side, facing the centre).
	spawns: { CFrame },
}

-- Arrival point k of n (spread on an arc around -Z).
function ArenaBuilder.spawnCFrame(k: number, n: number): CFrame
	local c = A.Center
	local spread = math.rad(70)
	local t = if n <= 1 then 0.5 else (k - 1) / (n - 1)
	local angle = -math.pi / 2 + (t - 0.5) * spread
	local p = Vector3.new(c.X + math.cos(angle) * A.SpawnRadius, c.Y + 3, c.Z + math.sin(angle) * A.SpawnRadius)
	return CFrame.lookAt(p, Vector3.new(c.X, p.Y, c.Z))
end

-- Is `position` inside the arena bounds?
function ArenaBuilder.inside(position: Vector3, margin: number?): boolean
	local c = A.Center
	local flat = Vector3.new(position.X - c.X, 0, position.Z - c.Z).Magnitude
	local dy = position.Y - c.Y
	return flat <= A.Radius + (margin or A.BoundsMargin) and dy > -12 and dy < A.BoundsHeight
end

-- Void Warden: the janitor's closet of the Void.
local function buildCloset(model: Model, c: Vector3, R: number, top: number): BasePart

	-- Floor: a fat pastel disc with a target pattern and quadrant lines.
	local floor = Parts.cylinder({ size = Vector3.new(R * 2 + 8, 4, R * 2 + 8), cf = CFrame.new(c.X, top - 2, c.Z), color = FLOOR, parent = model, name = "Floor" })
	Parts.cylinder({ size = Vector3.new(R * 1.5, 0.2, R * 1.5), cf = CFrame.new(c.X, top + 0.02, c.Z), color = TILE, collide = false, shadow = false, parent = model, name = "Tile" })
	Parts.cylinder({ size = Vector3.new(R * 0.9, 0.24, R * 0.9), cf = CFrame.new(c.X, top + 0.06, c.Z), color = FLOOR, collide = false, shadow = false, parent = model, name = "Tile" })
	Parts.cylinder({ size = Vector3.new(R * 0.36, 0.28, R * 0.36), cf = CFrame.new(c.X, top + 0.1, c.Z), color = TILE, collide = false, shadow = false, parent = model, name = "Tile" })
	for _, angle in { 0, math.pi / 2 } do
		Parts.block({ size = Vector3.new(R * 2, 0.32, 0.8), cf = CFrame.new(c.X, top + 0.12, c.Z) * CFrame.Angles(0, angle + math.pi / 4, 0), color = LINE, collide = false, shadow = false, parent = model, name = "QuarterLine" })
	end
	-- Underside: a stack of shrinking discs (floating island / upside-down bucket).
	Parts.cylinder({ size = Vector3.new(R * 1.7, 8, R * 1.7), cf = CFrame.new(c.X, top - 8, c.Z), color = UNDER, parent = model, name = "Under" })
	Parts.cylinder({ size = Vector3.new(R * 1.1, 10, R * 1.1), cf = CFrame.new(c.X, top - 17, c.Z), color = Palette.World.StoneDark, parent = model, name = "Under" })
	Parts.ball({ size = Vector3.one * R * 0.5, cf = CFrame.new(c.X, top - 24, c.Z), color = Palette.World.Rift, material = M.Neon, collide = false, shadow = false, parent = model, name = "UnderGlow" })

	-- Candy bumper around the edge (low: you can see out, never fall out).
	local segments = 24
	for i = 0, segments - 1 do
		local a = (i + 0.5) / segments * math.pi * 2
		local length = 2 * (R + 1.5) * math.sin(math.pi / segments) + 0.6
		local p = Vector3.new(c.X + math.cos(a) * (R + 1.5), top + 1.1, c.Z + math.sin(a) * (R + 1.5))
		Parts.block({
			size = Vector3.new(length, 2.2, 2.6),
			cf = CFrame.lookAt(p, Vector3.new(c.X, p.Y, c.Z)),
			color = if i % 2 == 0 then BUMPER_A else BUMPER_B,
			parent = model,
			name = "Bumper",
		})
	end

	-- Arrival door: a cartoon closet door frame behind the spawn arc.
	local doorAt = Vector3.new(c.X, top, c.Z - (R + 5))
	local door = CFrame.lookAt(doorAt, Vector3.new(c.X, top, c.Z))
	Parts.block({ size = Vector3.new(1.6, 14, 1.6), cf = door * CFrame.new(-5, 7, 0), color = BUMPER_B, parent = model, name = "DoorPost" })
	Parts.block({ size = Vector3.new(1.6, 14, 1.6), cf = door * CFrame.new(5, 7, 0), color = BUMPER_B, parent = model, name = "DoorPost" })
	Parts.block({ size = Vector3.new(12, 1.8, 2), cf = door * CFrame.new(0, 14.4, 0), color = BUMPER_A, parent = model, name = "DoorTop" })
	local portal = Parts.block({ size = Vector3.new(8.4, 12.6, 0.4), cf = door * CFrame.new(0, 6.6, 0.4), color = Color3.fromRGB(176, 110, 255), material = M.Neon, transparency = 0.25, collide = false, shadow = false, parent = model, name = "DoorGlow" })
	Parts.light(portal, Color3.fromRGB(200, 150, 255), 24, 1.2)

	-- Giant cleaning props outside the bumper (silhouettes readable from far).
	local function polar(deg: number, r: number): CFrame
		local a = math.rad(deg)
		local p = Vector3.new(c.X + math.cos(a) * r, top, c.Z + math.sin(a) * r)
		return CFrame.lookAt(p, Vector3.new(c.X, top, c.Z))
	end
	-- Bucket (with a handle and soapy foam on top).
	local bucket = polar(20, R + 13)
	Parts.cylinder({ size = Vector3.new(14, 12, 14), cf = bucket * CFrame.new(0, 2, 0), color = BUCKET, parent = model, name = "Bucket" })
	Parts.cylinder({ size = Vector3.new(14.8, 1.2, 14.8), cf = bucket * CFrame.new(0, 8.4, 0), color = Palette.Core.Cream, parent = model, name = "BucketRim" })
	Parts.ellipsoid({ size = Vector3.new(13, 5, 13), cf = bucket * CFrame.new(0, 9.4, 0), color = BUBBLE, collide = false, parent = model, name = "Foam" })
	Parts.block({ size = Vector3.new(0.8, 0.8, 18), cf = bucket * CFrame.new(0, 13, 0) * CFrame.Angles(0, math.rad(90), 0), color = Palette.World.StoneDark, collide = false, parent = model, name = "Handle" })
	-- Soap bottle with its pump.
	local soap = polar(150, R + 12)
	Parts.block({ size = Vector3.new(9, 18, 6), cf = soap * CFrame.new(0, 7, 0), color = SOAP, parent = model, name = "SoapBottle" })
	Parts.block({ size = Vector3.new(6, 6, 0.4), cf = soap * CFrame.new(0, 7, -3.1), color = Palette.Core.Cream, collide = false, parent = model, name = "SoapLabel" })
	Parts.cylinder({ size = Vector3.new(3, 4, 3), cf = soap * CFrame.new(0, 18, 0), color = Palette.Core.Cream, parent = model, name = "SoapPump" })
	Parts.block({ size = Vector3.new(1.2, 1.2, 5), cf = soap * CFrame.new(0, 20, -2), color = Palette.Core.Cream, collide = false, parent = model, name = "SoapNozzle" })
	-- Stacked sponges.
	local sponge = polar(-150, R + 11)
	for k = 0, 2 do
		Parts.block({ size = Vector3.new(10, 3.4, 6), cf = sponge * CFrame.new(0, 1 + k * 3.5, 0) * CFrame.Angles(0, math.rad(k * 17), 0), color = if k % 2 == 0 then SPONGE else BUMPER_B, parent = model, name = "Sponge" })
	end
	-- A mop leaning on the bumper.
	local mop = polar(-40, R + 9)
	Parts.cylinder({ size = Vector3.new(1, 26, 1), cf = mop * CFrame.new(0, 12, 0) * CFrame.Angles(math.rad(18), 0, 0), color = Palette.World.Trunk, collide = false, parent = model, name = "MopStick" })
	Parts.ellipsoid({ size = Vector3.new(6, 4, 6), cf = mop * CFrame.new(0, 1.6, -3), color = Palette.Core.Cream, collide = false, parent = model, name = "MopHead" })
	-- Floating bubbles (one emitter for the drifting small ones).
	local bubbles = {
		{ 60, R + 16, 22, 5 }, { 100, R + 22, 30, 3.5 }, { -100, R + 18, 26, 4.5 }, { -10, R + 24, 34, 3 },
		{ 200, R + 20, 18, 4 }, { -70, R + 26, 40, 6 }, { 125, R + 28, 46, 3 },
	}
	for _, spec in bubbles do
		local cf = polar(spec[1], spec[2])
		Parts.ball({ size = Vector3.one * spec[4], cf = cf * CFrame.new(0, spec[3], 0), color = BUBBLE, material = M.Glass, transparency = 0.45, collide = false, shadow = false, parent = model, name = "Bubble" })
	end
	local holder = Parts.block({ size = Vector3.new(R * 1.6, 1, R * 1.6), cf = CFrame.new(c.X, top - 4, c.Z), transparency = 1, collide = false, shadow = false, parent = model, name = "BubbleSource" })
	holder.CanQuery = false
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Bubbles"
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(BUBBLE, Color3.fromRGB(255, 200, 240))
	emitter.Size = NumberSequence.new(0.6, 1.2)
	emitter.Transparency = NumberSequence.new(0.3, 1)
	emitter.Lifetime = NumberRange.new(4, 6)
	emitter.Speed = NumberRange.new(2, 4)
	emitter.Rate = 3
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.Parent = holder
	local sun = Parts.block({ size = Vector3.one, cf = CFrame.new(c.X, top + 24, c.Z), transparency = 1, collide = false, shadow = false, parent = model, name = "Sun" })
	sun.CanQuery = false
	Parts.light(sun, Color3.fromRGB(255, 235, 250), 60, 0.8)
	floor:SetAttribute("ArenaFloor", true)
	return floor
end

-- Forgeheart: the forge in the volcano (phase 7A). Warm cartoon rock, glowing
-- cracks, six cooled-rock safe pads, a ring of round boulders, a lava sea
-- far below and a volcano on the horizon. Decor never hurts anyone.
local function buildVolcano(model: Model, c: Vector3, R: number, top: number, def: Bosses.BossDef): BasePart
	local floor = Parts.cylinder({ size = Vector3.new(R * 2 + 8, 4, R * 2 + 8), cf = CFrame.new(c.X, top - 2, c.Z), color = ROCK, parent = model, name = "Floor" })
	Parts.cylinder({ size = Vector3.new(R * 1.55, 0.2, R * 1.55), cf = CFrame.new(c.X, top + 0.02, c.Z), color = ROCK_LIGHT, collide = false, shadow = false, parent = model, name = "Tile" })
	Parts.cylinder({ size = Vector3.new(R * 0.5, 0.26, R * 0.5), cf = CFrame.new(c.X, top + 0.06, c.Z), color = ROCK, collide = false, shadow = false, parent = model, name = "Tile" })
	-- Glowing lava cracks between the pads (pure decor, flush with the floor).
	for k = 0, 5 do
		local a = math.rad(30 + k * 60)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local mid = c + dir * (R * 0.55)
		Parts.block({ size = Vector3.new(0.9, 0.3, R * 0.62), cf = CFrame.lookAt(Vector3.new(mid.X, top + 0.1, mid.Z), Vector3.new(c.X, top + 0.1, c.Z)), color = LAVA, material = M.Neon, collide = false, shadow = false, parent = model, name = "Crack" })
		local side = c + dir * (R * 0.7) + Vector3.new(-dir.Z, 0, dir.X) * 3
		Parts.block({ size = Vector3.new(0.7, 0.3, 7), cf = CFrame.new(side.X, top + 0.1, side.Z) * CFrame.Angles(0, a + math.rad(40), 0), color = LAVA_HOT, material = M.Neon, collide = false, shadow = false, parent = model, name = "Crack" })
	end
	-- Cooled-rock safe pads (Final Eruption: every other one stays safe).
	local padRadius = def.padRadius or 8
	for index, spot in Bosses.arenaPads(def) do
		local pad = Parts.cylinder({ size = Vector3.new(padRadius * 2, 0.4, padRadius * 2), cf = CFrame.new(spot.X, top + 0.12, spot.Z), color = ROCK_COOL, collide = false, shadow = false, parent = model, name = "SafePad" })
		pad:SetAttribute("PadIndex", index)
		Parts.cylinder({ size = Vector3.new(padRadius * 2 + 1.2, 0.3, padRadius * 2 + 1.2), cf = CFrame.new(spot.X, top + 0.06, spot.Z), color = Color3.fromRGB(96, 100, 140), collide = false, shadow = false, parent = model, name = "PadRim" })
	end
	-- Ring of round boulders (low: you see out, you never fall out).
	local boulders = 22
	for i = 0, boulders - 1 do
		local a = (i + 0.5) / boulders * math.pi * 2
		local size = if i % 3 == 0 then 5.2 else 4.4
		Parts.ball({ size = Vector3.one * size, cf = CFrame.new(c.X + math.cos(a) * (R + 2.2), top + size * 0.3, c.Z + math.sin(a) * (R + 2.2)), color = if i % 2 == 0 then ROCK else ROCK_LIGHT, parent = model, name = "Boulder" })
	end
	-- Underside and the lava sea far below.
	Parts.cylinder({ size = Vector3.new(R * 1.7, 8, R * 1.7), cf = CFrame.new(c.X, top - 8, c.Z), color = ROCK, parent = model, name = "Under" })
	Parts.cylinder({ size = Vector3.new(R * 1.1, 10, R * 1.1), cf = CFrame.new(c.X, top - 17, c.Z), color = Palette.World.StoneDark, parent = model, name = "Under" })
	Parts.ball({ size = Vector3.one * R * 0.5, cf = CFrame.new(c.X, top - 24, c.Z), color = LAVA, material = M.Neon, collide = false, shadow = false, parent = model, name = "UnderGlow" })
	local sea = Parts.cylinder({ size = Vector3.new(R * 2 + 200, 2, R * 2 + 200), cf = CFrame.new(c.X, top - 40, c.Z), color = LAVA, material = M.Neon, collide = false, shadow = false, parent = model, name = "LavaSea" })
	sea.CanQuery = false
	local function polar(deg: number, r: number): CFrame
		local a = math.rad(deg)
		local p = Vector3.new(c.X + math.cos(a) * r, top, c.Z + math.sin(a) * r)
		return CFrame.lookAt(p, Vector3.new(c.X, top, c.Z))
	end
	for k, spec in { { 40, R + 40, 14 }, { 150, R + 55, 18 }, { 215, R + 45, 12 }, { 320, R + 60, 16 }, { 260, R + 80, 10 }, { 10, R + 90, 20 } } do
		local cf = polar(spec[1], spec[2])
		Parts.ellipsoid({ size = Vector3.new(spec[3], spec[3] * 0.6, spec[3]), cf = cf * CFrame.new(0, -40, 0), color = if k % 2 == 0 then ROCK else ROCK_LIGHT, collide = false, parent = model, name = "LavaIsland" })
	end
	-- Rock spires outside the boulders (silhouettes readable from far).
	for k, spec in { { 25, R + 12, 26 }, { 75, R + 16, 34 }, { 130, R + 13, 22 }, { 200, R + 15, 30 }, { 245, R + 12, 20 }, { 335, R + 14, 28 } } do
		local cf = polar(spec[1], spec[2])
		Parts.cylinder({ size = Vector3.new(7, spec[3], 7), cf = cf * CFrame.new(0, spec[3] / 2 - 2, 0), color = if k % 2 == 0 then ROCK else ROCK_LIGHT, parent = model, name = "Spire" })
		Parts.ball({ size = Vector3.one * 7.4, cf = cf * CFrame.new(0, spec[3] - 2, 0), color = if k % 2 == 0 then ROCK_LIGHT else ROCK, parent = model, name = "SpireTop" })
	end
	-- The volcano on the horizon (behind the boss), smoking with a neon crater.
	local volcano = polar(90, R + 120)
	for k, spec in { { 110, 20 }, { 86, 18 }, { 64, 16 }, { 44, 14 } } do
		Parts.cylinder({ size = Vector3.new(spec[1], spec[2], spec[1]), cf = volcano * CFrame.new(0, -30 + (k - 1) * 16, 0), color = if k % 2 == 0 then ROCK_LIGHT else ROCK, collide = false, parent = model, name = "Volcano" })
	end
	local crater = Parts.cylinder({ size = Vector3.new(30, 2, 30), cf = volcano * CFrame.new(0, 26, 0), color = LAVA_HOT, material = M.Neon, collide = false, shadow = false, parent = model, name = "Crater" })
	crater.CanQuery = false
	for k = 0, 2 do
		Parts.block({ size = Vector3.new(4, 44, 2), cf = volcano * CFrame.Angles(0, math.rad(k * 50 - 50), 0) * CFrame.new(0, 4, -32) * CFrame.Angles(math.rad(-28), 0, 0), color = LAVA, material = M.Neon, collide = false, shadow = false, parent = model, name = "LavaFlow" })
	end
	-- Arrival arch: two boulder posts and a glowing lava curtain.
	local doorAt = Vector3.new(c.X, top, c.Z - (R + 5))
	local door = CFrame.lookAt(doorAt, Vector3.new(c.X, top, c.Z))
	Parts.cylinder({ size = Vector3.new(3, 14, 3), cf = door * CFrame.new(-5, 7, 0), color = ROCK_LIGHT, parent = model, name = "DoorPost" })
	Parts.cylinder({ size = Vector3.new(3, 14, 3), cf = door * CFrame.new(5, 7, 0), color = ROCK_LIGHT, parent = model, name = "DoorPost" })
	Parts.block({ size = Vector3.new(13, 2.4, 3), cf = door * CFrame.new(0, 14.6, 0), color = ROCK, parent = model, name = "DoorTop" })
	local portal = Parts.block({ size = Vector3.new(8.4, 12.6, 0.4), cf = door * CFrame.new(0, 6.6, 0.4), color = LAVA, material = M.Neon, transparency = 0.25, collide = false, shadow = false, parent = model, name = "DoorGlow" })
	Parts.light(portal, Color3.fromRGB(255, 170, 90), 24, 1.2)
	-- Embers rising from the lava sea (the only emitter).
	local holder = Parts.block({ size = Vector3.new(R * 2.4, 1, R * 2.4), cf = CFrame.new(c.X, top - 30, c.Z), transparency = 1, collide = false, shadow = false, parent = model, name = "EmberSource" })
	holder.CanQuery = false
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Embers"
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(LAVA_HOT, LAVA)
	emitter.Size = NumberSequence.new(0.5, 1)
	emitter.Transparency = NumberSequence.new(0.2, 1)
	emitter.Lifetime = NumberRange.new(4, 6)
	emitter.Speed = NumberRange.new(5, 9)
	emitter.Rate = 4
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Parent = holder
	local sun = Parts.block({ size = Vector3.one, cf = CFrame.new(c.X, top + 24, c.Z), transparency = 1, collide = false, shadow = false, parent = model, name = "Sun" })
	sun.CanQuery = false
	Parts.light(sun, Color3.fromRGB(255, 220, 190), 60, 0.8)
	floor:SetAttribute("ArenaFloor", true)
	return floor
end

function ArenaBuilder.build(parent: Instance, bossId: string): Arena
	local c = A.Center
	local R = A.Radius
	local model = Parts.model("BossArena", parent)
	model:SetAttribute("BossId", bossId)
	local def = Bosses.get(bossId)
	local theme = if def then def.theme else "closet"
	model:SetAttribute("Theme", theme)
	local top = c.Y
	if theme == "volcano" and def then
		buildVolcano(model, c, R, top, def)
	else
		buildCloset(model, c, R, top)
	end
	-- Invisible walls (cylinder approximated by 16 slabs).
	local walls = 16
	for i = 0, walls - 1 do
		local a = (i + 0.5) / walls * math.pi * 2
		local length = 2 * (R + 3.5) * math.sin(math.pi / walls) + 1
		local p = Vector3.new(c.X + math.cos(a) * (R + 3.5), top + A.WallHeight / 2, c.Z + math.sin(a) * (R + 3.5))
		-- Queryable: Blink, Grapple and every raycast stop at the walls.
		Parts.block({ size = Vector3.new(length, A.WallHeight, 1), cf = CFrame.lookAt(p, Vector3.new(c.X, p.Y, c.Z)), transparency = 1, shadow = false, parent = model, name = "Wall" })
	end

	-- Floating bubble anchors for the Grapple (phase 6.5).
	-- Volcano: floating hot rocks with a glowing core instead of bubbles.
	local anchors = Parts.folder("GrapplePoints", model)
	local hot = theme == "volcano"
	for _, point in Bosses.arenaGrapplePoints() do
		local shell = Parts.ball({ size = Vector3.one * 2.6, cf = CFrame.new(point.position), color = if hot then ROCK_LIGHT else BUBBLE, material = M.Glass, transparency = if hot then 0.15 else 0.35, collide = false, shadow = false, parent = anchors, name = "Anchor" })
		shell:SetAttribute("GrapplePoint", point.index)
		Parts.ball({ size = Vector3.one * 1.1, cf = CFrame.new(point.position), color = if hot then LAVA_HOT else Color3.fromRGB(120, 240, 255), material = M.Neon, collide = false, shadow = false, parent = anchors, name = "AnchorCore" })
	end

	local spawns = {}
	for k = 1, 8 do
		table.insert(spawns, ArenaBuilder.spawnCFrame(k, 8))
	end
	return { model = model, center = c, floorY = top, spawns = spawns }
end

return ArenaBuilder
