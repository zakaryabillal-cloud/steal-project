--!strict
-- The three V2 landmarks, 90 degrees apart around the outer crown so one is
-- always on the horizon:
--   * Observatory  (112.5) - tower on the High Ledge, outer stair to a
--                            viewing balcony (spot thieves crossing the map).
--   * Broken Arch  (202.5) - gateway spanning the ledge cliff over the trail.
--   * Boss Plateau (292.5) - promontory with the dormant boss portal
--                            (bosses arrive in a later phase).
-- Built from few, large parts; accents are Neon, lights are rare.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Layout = require(Shared.Layout)
local WorldFeatures = require(Shared.WorldFeatures)
local Parts = require(script.Parent.Parts)
local TerrainBuilder = require(script.Parent.TerrainBuilder)

local Landmarks = {}

local M = Enum.Material
local C = Layout.Colors
local polar = WorldFeatures.polar

local BOSS_RED = Color3.fromRGB(255, 96, 120)
local BOSS_EMBER = Color3.fromRGB(255, 186, 90)
-- Phase 5.5: candy grape stone instead of dark basalt (no gloomy boss lair).
local BASALT = Color3.fromRGB(124, 110, 210)
local LENS = Color3.fromRGB(140, 230, 255)

local function groundAt(position: Vector3): number
	return TerrainBuilder.heightAt(position.X, position.Z) or position.Y
end

-- CFrame at `deg`/`r` whose -Z (LookVector) faces the Rift.
local function facingRift(deg: number, r: number, y: number): CFrame
	local p = polar(deg, r, y)
	return CFrame.lookAt(p, Vector3.new(0, y, 0))
end

----------------------------------------------------------------------------
-- Observatory
----------------------------------------------------------------------------

local function buildObservatory(folder: Instance)
	local spec = WorldFeatures.Observatory
	local model = Parts.model("Observatory", folder)
	local base = spec.position
	local ground = groundAt(base)
	local origin = CFrame.new(base.X, ground, base.Z) * CFrame.Angles(0, math.rad(-112.5), 0)

	-- Plinth.
	Parts.cylinder({ size = Vector3.new(24, 5, 24), cf = origin * CFrame.new(0, 0.5, 0), color = C.StoneDark, material = M.Slate, parent = model, name = "Plinth" })
	Parts.cylinder({ size = Vector3.new(24.6, 0.6, 24.6), cf = origin * CFrame.new(0, 2.7, 0), color = C.Rift, material = M.Neon, collide = false, shadow = false, parent = model, name = "PlinthRing" })
	Parts.cylinder({ size = Vector3.new(22, 0.8, 22), cf = origin * CFrame.new(0, 3, 0), color = C.StoneLight, material = M.Marble, parent = model, name = "PlinthTop" })
	local floorY = ground + 3.4
	-- Two steps up the plinth from the trail (inner side, facing the Rift).
	local inward = -Vector3.new(base.X, 0, base.Z).Unit
	for k = 1, 2 do
		local p = Vector3.new(base.X, ground, base.Z) + inward * (12 + 3.2 - (k - 1) * 1.6)
		Parts.block({ size = Vector3.new(7, k * 1.15, 3.2), cf = CFrame.lookAt(Vector3.new(p.X, ground + k * 1.15 / 2, p.Z), Vector3.new(base.X, ground + k * 1.15 / 2, base.Z)), color = C.Stone, material = M.Slate, parent = model, name = "PlinthStep" })
	end

	-- Lower shaft up to the balcony.
	local balconyY = spec.balconyY
	local shaftH = balconyY - floorY
	Parts.cylinder({ size = Vector3.new(14, shaftH, 14), cf = CFrame.new(base.X, floorY + shaftH / 2, base.Z), color = C.StoneLight, material = M.Marble, parent = model, name = "Shaft" })
	for _, y in { floorY + shaftH * 0.33, floorY + shaftH * 0.66 } do
		Parts.cylinder({ size = Vector3.new(14.8, 1.2, 14.8), cf = CFrame.new(base.X, y, base.Z), color = C.Trim, material = M.Slate, parent = model, name = "Band" })
	end
	-- Tall window slits.
	for k = 0, 3 do
		local a = math.rad(k * 90 + 45)
		local cf = CFrame.new(base.X, floorY + shaftH * 0.5, base.Z) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -7.05)
		Parts.block({ size = Vector3.new(1.2, shaftH * 0.42, 0.3), cf = cf, color = LENS, material = M.Neon, collide = false, shadow = false, parent = model, name = "Window" })
	end

	-- Outer spiral stair (floating stone steps) from the plinth to the balcony.
	-- Steps run outside the balcony's radius and arrive at its parapet gap.
	local steps = 24
	local turns = 1.15
	local stepRadius = 15.5
	local startAngle = math.rad(-112.5 + 200)
	local rise = (balconyY - floorY) / steps
	local arrival = startAngle + turns * math.pi * 2
	for i = 1, steps do
		local t = i / steps
		local a = startAngle + t * turns * math.pi * 2
		local p = Vector3.new(base.X + math.cos(a) * stepRadius, floorY + i * rise - 0.5, base.Z + math.sin(a) * stepRadius)
		local cf = CFrame.lookAt(p, Vector3.new(base.X, p.Y, base.Z))
		Parts.block({ size = Vector3.new(5.2, 1, 4.6), cf = cf, color = C.Stone, material = M.Slate, parent = model, name = "ObservatoryStep" })
		if i % 4 == 0 then
			Parts.block({ size = Vector3.new(0.3, 0.2, 4.2), cf = cf * CFrame.new(1.7, 0.55, 0), color = C.Rift, material = M.Neon, collide = false, shadow = false, parent = model, name = "StepRune" })
		end
	end

	-- Balcony: the vantage point.
	Parts.cylinder({ size = Vector3.new(26, 1.4, 26), cf = CFrame.new(base.X, balconyY + 0.2, base.Z), color = C.Stone, material = M.Slate, parent = model, name = "Balcony" })
	Parts.cylinder({ size = Vector3.new(26.6, 0.5, 26.6), cf = CFrame.new(base.X, balconyY - 0.4, base.Z), color = C.Rift, material = M.Neon, collide = false, shadow = false, parent = model, name = "BalconyRing" })
	for k = 0, 9 do
		local a = math.rad(k * 36)
		-- Opening where the stair arrives.
		local diff = math.abs(((a - arrival) + math.pi) % (2 * math.pi) - math.pi)
		if diff < math.rad(20) then
			continue
		end
		local cf = CFrame.new(base.X, balconyY + 1.6, base.Z) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -12.4)
		Parts.block({ size = Vector3.new(6.6, 1.6, 0.8), cf = cf, color = C.StoneLight, material = M.Marble, parent = model, name = "Parapet" })
	end

	-- Upper tower, dome and telescope.
	local upperH = 24
	Parts.cylinder({ size = Vector3.new(10, upperH, 10), cf = CFrame.new(base.X, balconyY + 0.9 + upperH / 2, base.Z), color = C.StoneLight, material = M.Marble, parent = model, name = "Upper" })
	local domeY = balconyY + 0.9 + upperH
	Parts.cylinder({ size = Vector3.new(12, 1.4, 12), cf = CFrame.new(base.X, domeY, base.Z), color = C.Trim, material = M.Slate, parent = model, name = "DomeBase" })
	-- Roof deck around the dome (grapple target from the balcony).
	local deckR = spec.roofDeckRadius
	Parts.cylinder({ size = Vector3.new(deckR * 2, 1, deckR * 2), cf = CFrame.new(base.X, spec.roofDeckY - 0.5, base.Z), color = C.Stone, material = M.Slate, parent = model, name = "RoofDeck" })
	Parts.cylinder({ size = Vector3.new(deckR * 2 + 0.6, 0.4, deckR * 2 + 0.6), cf = CFrame.new(base.X, spec.roofDeckY - 0.9, base.Z), color = C.Rift, material = M.Neon, collide = false, shadow = false, parent = model, name = "RoofDeckRing" })
	local dome = Parts.ball({ size = Vector3.one * 12.5, cf = CFrame.new(base.X, domeY + 0.6, base.Z), color = Color3.fromRGB(150, 214, 255), material = M.Glass, transparency = 0.15, parent = model, name = "Dome" })
	dome.Reflectance = 0.2
	local scope = CFrame.new(base.X, domeY + 4, base.Z) * CFrame.Angles(0, math.rad(-112.5 + 180), 0) * CFrame.Angles(math.rad(55), 0, 0)
	Parts.cylinder({ size = Vector3.new(3, 18, 3), cf = scope * CFrame.new(0, 6, 0), color = C.Trim, material = M.Metal, parent = model, name = "Telescope" })
	local lens = Parts.cylinder({ size = Vector3.new(3.4, 0.5, 3.4), cf = scope * CFrame.new(0, 15.2, 0), color = LENS, material = M.Neon, collide = false, shadow = false, parent = model, name = "Lens" })
	Parts.light(lens, LENS, 30, 1.6)

	-- Faint beacon from the lens into the sky: readable from anywhere.
	local a0 = Parts.attachment(lens, Vector3.zero, "BeaconStart")
	local a1 = Parts.attachment(lens, Vector3.new(0, 0, 0), "BeaconEnd")
	a1.WorldPosition = lens.Position + (scope.UpVector * 220)
	local beam = Instance.new("Beam")
	beam.Name = "Beacon"
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = 2.5
	beam.Width1 = 12
	beam.Color = ColorSequence.new(LENS, Color3.fromRGB(190, 160, 255))
	beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Parent = lens
	model:SetAttribute("Landmark", "Observatory")
end

----------------------------------------------------------------------------
-- Broken Arch
----------------------------------------------------------------------------

local function buildBrokenArch(folder: Instance)
	local spec = WorldFeatures.BrokenArch
	local model = Parts.model("BrokenArch", folder)
	local deg = spec.deg
	local radius = (spec.outer - spec.inner) / 2
	local centerR = (spec.inner + spec.outer) / 2
	local springY = spec.springY
	local dir = polar(deg, 1, 0)
	local center = polar(deg, centerR, springY)
	-- Arch plane: radial direction x vertical; thickness along the tangent.
	local tangent = Vector3.new(-dir.Z, 0, dir.X)

	-- Inner leg rises from the back alley to the springing.
	local innerFoot = polar(deg, spec.inner, 0)
	local innerGround = groundAt(innerFoot)
	local legH = springY - innerGround + 1
	local legCf = CFrame.fromMatrix(Vector3.new(innerFoot.X, innerGround + legH / 2 - 1, innerFoot.Z), tangent, Vector3.yAxis)
	Parts.block({ size = Vector3.new(7, legH, 7), cf = legCf, color = C.StoneLight, material = M.Slate, parent = model, name = "ArchLeg" })
	Parts.block({ size = Vector3.new(8.4, 2, 8.4), cf = CFrame.new(innerFoot.X, innerGround, innerFoot.Z), color = C.Stone, material = M.Slate, parent = model, name = "ArchLegBase" })
	Parts.block({ size = Vector3.new(0.4, legH * 0.7, 0.4), cf = legCf * CFrame.new(0, 0, -3.6), color = C.Rift, material = M.Neon, collide = false, shadow = false, parent = model, name = "ArchRune" })
	-- Outer foot block on the ledge.
	local outerFoot = polar(deg, spec.outer, springY)
	Parts.block({ size = Vector3.new(8, 3, 8), cf = CFrame.fromMatrix(outerFoot + Vector3.new(0, 0.5, 0), tangent, Vector3.yAxis), color = C.Stone, material = M.Slate, parent = model, name = "ArchFoot" })

	-- Voussoirs along the semicircle (angle 0 = inner springing).
	local segments = 14
	local stepDeg = 180 / segments
	for i = 0, segments - 1 do
		local a0 = i * stepDeg
		local a1 = a0 + stepDeg
		local mid = (a0 + a1) / 2
		if mid > spec.gapFrom and mid < spec.gapTo then
			continue
		end
		local rad = math.rad(mid)
		-- Position on the circle: inner side is -dir.
		local p = center + (-dir) * (radius * math.cos(rad)) + Vector3.yAxis * (radius * math.sin(rad))
		local outward = ((-dir) * math.cos(rad) + Vector3.yAxis * math.sin(rad)).Unit
		local length = 2 * radius * math.sin(math.rad(stepDeg) / 2) + 0.6
		-- X = thickness (tangent), Y = outward, Z (computed) = along the arch.
		local cf = CFrame.fromMatrix(p, tangent, outward)
		Parts.block({ size = Vector3.new(6, 4.4, length), cf = cf, color = if i % 2 == 0 then C.StoneLight else C.Stone, material = M.Slate, parent = model, name = "Voussoir" })
		Parts.block({ size = Vector3.new(0.35, 0.35, length * 0.8), cf = cf * CFrame.new(0, -2.25, 0), color = C.Rift, material = M.Neon, collide = false, shadow = false, parent = model, name = "ArchGlow" })
	end
	-- Keystone-like crystal hanging at the broken tip.
	local tipRad = math.rad(spec.gapTo)
	local tip = center + (-dir) * (radius * math.cos(tipRad)) + Vector3.yAxis * (radius * math.sin(tipRad))
	local crystal = Parts.block({ size = Vector3.new(1.4, 4, 1.4), cf = CFrame.new(tip - Vector3.yAxis * 3.6) * CFrame.Angles(0, math.rad(45), 0), color = C.Rift, material = M.Neon, collide = false, shadow = false, parent = model, name = "TipCrystal" })
	Parts.light(crystal, C.Rift, 22, 1.2)

	-- Fallen blocks under the gap (cover in the back alley).
	local rng = Random.new(2025)
	for k = 1, 4 do
		local a = math.rad(spec.gapFrom + (spec.gapTo - spec.gapFrom) * (k / 5))
		local p = center + (-dir) * (radius * math.cos(a))
		local ground = groundAt(p)
		local size = Vector3.new(rng:NextNumber(4, 6.5), rng:NextNumber(3, 4.5), rng:NextNumber(4, 7))
		Parts.block({
			size = size,
			cf = CFrame.new(p.X + tangent.X * rng:NextNumber(-4, 4), ground + size.Y * 0.35, p.Z + tangent.Z * rng:NextNumber(-4, 4)) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6), rng:NextNumber(-0.4, 0.4)),
			color = C.StoneLight,
			material = M.Slate,
			parent = model,
			name = "Rubble",
		})
	end
	model:SetAttribute("Landmark", "BrokenArch")
end

----------------------------------------------------------------------------
-- Boss plateau + dormant portal
----------------------------------------------------------------------------

local function buildBossPlateau(folder: Instance)
	local spec = WorldFeatures.BossPlateau
	local model = Parts.model("BossPlateau", folder)
	local top = spec.top
	local plaza = polar(spec.deg, spec.center, top)

	-- Lobby circle where challengers will gather (segmented neon ring).
	local segments = 24
	for i = 0, segments - 1 do
		local a = (i / segments) * math.pi * 2
		local r = 12
		Parts.block({
			size = Vector3.new(0.7, 0.25, 2 * r * math.sin(math.pi / segments) * 0.8),
			cf = CFrame.new(plaza.X + math.cos(a) * r, top + 0.15, plaza.Z + math.sin(a) * r) * CFrame.Angles(0, -a, 0),
			color = BOSS_RED,
			material = M.Neon,
			transparency = 0.1,
			collide = false,
			shadow = false,
			parent = model,
			name = "LobbyRing",
		})
	end
	Parts.cylinder({ size = Vector3.new(7, 0.6, 7), cf = CFrame.new(plaza + Vector3.new(0, 0.1, 0)), color = BASALT, material = M.Basalt, parent = model, name = "LobbySeal" })
	Parts.cylinder({ size = Vector3.new(3, 0.7, 3), cf = CFrame.new(plaza + Vector3.new(0, 0.2, 0)), color = BOSS_EMBER, material = M.Neon, collide = false, shadow = false, parent = model, name = "LobbyCore" })

	-- Obelisks around the plaza.
	for _, rel in { -140, -100, -60, 60, 100, 140 } do
		local k = rel
		local a = math.rad(spec.deg) + math.rad(rel)
		local p = Vector3.new(plaza.X + math.cos(a) * 21, top, plaza.Z + math.sin(a) * 21)
		local ground = groundAt(p)
		local h = 13 + (if math.abs(k) == 100 then 4 else 0)
		local cf = CFrame.lookAt(Vector3.new(p.X, ground + h / 2 - 0.5, p.Z), Vector3.new(plaza.X, ground + h / 2 - 0.5, plaza.Z))
		Parts.block({ size = Vector3.new(3.4, h, 2.4), cf = cf, color = BASALT, material = M.Basalt, parent = model, name = "Obelisk" })
		Parts.block({ size = Vector3.new(0.5, h * 0.6, 0.2), cf = cf * CFrame.new(0, 0, -1.25), color = BOSS_RED, material = M.Neon, collide = false, shadow = false, parent = model, name = "ObeliskRune" })
		Parts.wedge({ size = Vector3.new(3.4, 2, 2.4), cf = cf * CFrame.new(0, h / 2 + 1, 0), color = BASALT, material = M.Basalt, parent = model, name = "ObeliskCap" })
	end

	-- Portal ring at the far end, facing the Rift.
	local portalBase = polar(spec.deg, spec.portalR, top)
	local ringRadius = spec.portalRadius
	local ringCenter = portalBase + Vector3.new(0, ringRadius + 2, 0)
	local facing = CFrame.lookAt(ringCenter, Vector3.new(0, ringCenter.Y, 0))
	local ringSegments = 18
	for i = 0, ringSegments - 1 do
		local a = (i / ringSegments) * math.pi * 2
		local nextA = ((i + 1) / ringSegments) * math.pi * 2
		local mid = (a + nextA) / 2
		local p = facing * CFrame.new(math.cos(mid) * ringRadius, math.sin(mid) * ringRadius, 0)
		local length = 2 * ringRadius * math.sin(math.pi / ringSegments) + 0.4
		-- Local Y becomes the ring tangent, local X points outward.
		local cf = p * CFrame.Angles(0, 0, mid)
		Parts.block({ size = Vector3.new(3.2, length, 4.2), cf = cf, color = if i % 3 == 0 then Color3.fromRGB(160, 146, 236) else BASALT, material = M.Basalt, parent = model, name = "PortalStone" })
		if i % 3 == 0 then
			Parts.block({ size = Vector3.new(1.1, 1.1, 4.6), cf = cf * CFrame.new(-1.9, 0, 0) * CFrame.Angles(0, 0, math.rad(45)), color = BOSS_EMBER, material = M.Neon, collide = false, shadow = false, parent = model, name = "PortalRune" })
		end
	end
	-- Inner glowing trim + dormant membrane.
	local holder = Parts.block({ size = Vector3.one, cf = facing, transparency = 1, collide = false, shadow = false, parent = model, name = "PortalCore" })
	holder.CanQuery = false
	Parts.beamRing(holder, CFrame.Angles(math.rad(90), 0, 0), ringRadius - 2.2, 1.2, BOSS_RED, 0.1)
	local membrane = Parts.cylinder({
		size = Vector3.new((ringRadius - 2) * 2, 0.4, (ringRadius - 2) * 2),
		cf = facing * CFrame.Angles(math.rad(90), 0, 0),
		color = Color3.fromRGB(150, 70, 200),
		material = M.ForceField,
		transparency = 0.35,
		collide = false,
		shadow = false,
		parent = model,
		name = "Membrane",
	})
	membrane.CanQuery = false
	Parts.light(holder, BOSS_RED, 40, 1.4)
	-- Claws holding the ring.
	for _, side in { -1, 1 } do
		local foot = facing * CFrame.new(side * (ringRadius - 1), -ringRadius - 1, 0)
		Parts.wedge({ size = Vector3.new(5, 9, 8), cf = foot * CFrame.new(0, 2.5, 0) * CFrame.Angles(0, if side == 1 then math.rad(90) else math.rad(-90), 0), color = BASALT, material = M.Basalt, parent = model, name = "PortalClaw" })
		Parts.block({ size = Vector3.new(6, 3, 9), cf = foot * CFrame.new(0, -1.5, 0), color = Color3.fromRGB(160, 146, 236), material = M.Basalt, parent = model, name = "PortalFoot" })
	end
	-- Gate pillars where the neck meets the plaza.
	local gateR = spec.neckTo + 2
	for _, side in { -1, 1 } do
		local cf = facingRift(spec.deg, gateR, top) * CFrame.new(side * (spec.neckHalfWidth - 1.5), 0, 0)
		local ground = groundAt(cf.Position)
		local h = 16
		local pillar = Parts.block({ size = Vector3.new(4, h, 4), cf = CFrame.new(cf.Position.X, ground + h / 2 - 0.5, cf.Position.Z) * cf.Rotation, color = BASALT, material = M.Basalt, parent = model, name = "GatePillar" })
		Parts.block({ size = Vector3.new(4.8, 1.2, 4.8), cf = pillar.CFrame * CFrame.new(0, h / 2 + 0.6, 0), color = Color3.fromRGB(160, 146, 236), material = M.Basalt, parent = model, name = "GateCap" })
		local brazier = Parts.block({ size = Vector3.new(1.8, 1.8, 1.8), cf = pillar.CFrame * CFrame.new(0, h / 2 + 2.4, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)), color = BOSS_EMBER, material = M.Neon, collide = false, shadow = false, parent = model, name = "Brazier" })
		if side == 1 then
			Parts.light(brazier, BOSS_EMBER, 24, 1.3)
		end
		Parts.block({ size = Vector3.new(0.4, h * 0.6, 0.2), cf = pillar.CFrame * CFrame.new(0, 0, -2.05), color = BOSS_RED, material = M.Neon, collide = false, shadow = false, parent = model, name = "GateRune" })
	end
	model:SetAttribute("Landmark", "BossPlateau")
	model:SetAttribute("PortalState", "Dormant")
end

function Landmarks.build(parent: Instance)
	local folder = Parts.folder("Landmarks", parent)
	buildObservatory(folder)
	task.wait()
	buildBrokenArch(folder)
	buildBossPlateau(folder)
end

return Landmarks
