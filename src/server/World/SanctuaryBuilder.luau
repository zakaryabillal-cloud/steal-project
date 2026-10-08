--!strict
-- Builds a Sanctuary: a raised circular foundation with a gated ramp facing
-- the Rift, a pedestal ring around an Essence Core, a seal barrier, and five
-- architectural tiers that visibly stack up as the owner ascends:
--   1 Outpost  - foundation, balustrade, gate posts, lanterns
--   2 Shrine   - brazier pillars, floor runes, banners, gate arch
--   3 Temple   - colonnade + architrave ring, crystals, hanging lanterns
--   4 Citadel  - corner towers with sky beams, orbiting stones
--   5 Nexus    - floating golden halo, gilded rails, core sky beam
-- Parts of tier >= 2 carry a "Tier" attribute so clients can animate them in.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Layout = require(Shared.Layout)
local Theme = require(Shared.Config.Theme)
local Palette = require(Shared.Config.Palette)
local Parts = require(script.Parent.Parts)

local SanctuaryBuilder = {}

local M = Enum.Material
local C = Layout.Colors
local R = Layout.PlatformRadius
local ESSENCE = Color3.fromRGB(120, 235, 255)
local GOLD = Color3.fromRGB(255, 205, 100)
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

local CORNER_UP = CFrame.Angles(math.rad(45), 0, math.rad(35.26))

-- Position on the platform circle. phi is measured from the back (+Z) of the
-- Sanctuary; 180 degrees is the gate.
local function polar(phiDegrees: number, radius: number, y: number): CFrame
	local phi = math.rad(phiDegrees)
	local position = Vector3.new(math.sin(phi) * radius, y, math.cos(phi) * radius)
	return CFrame.lookAt(position, Vector3.new(0, y, 0))
end

type Builder = {
	model: Model,
	origin: CFrame,
	accent: Color3,
	folder: Instance,
	tier: number,
}

local function at(b: Builder, localCf: CFrame): CFrame
	return b.origin * localCf
end

local function tag(part: Instance, tier: number)
	if tier >= 2 then
		part:SetAttribute("Tier", tier)
	end
end

local function block(b: Builder, size: Vector3, localCf: CFrame, color: Color3, material: Enum.Material?, extra: { [string]: any }?): Part
	local spec: any = { size = size, cf = at(b, localCf), color = color, material = material, parent = b.folder }
	if extra then
		for k, v in extra do
			spec[k] = v
		end
	end
	local part = Parts.block(spec)
	tag(part, b.tier)
	return part
end

local function cylinder(b: Builder, size: Vector3, localCf: CFrame, color: Color3, material: Enum.Material?, extra: { [string]: any }?): Part
	local spec: any = { size = size, cf = at(b, localCf), color = color, material = material, parent = b.folder }
	if extra then
		for k, v in extra do
			spec[k] = v
		end
	end
	local part = Parts.cylinder(spec)
	tag(part, b.tier)
	return part
end

local function ball(b: Builder, diameter: number, localCf: CFrame, color: Color3, material: Enum.Material?, extra: { [string]: any }?): Part
	local spec: any = { size = Vector3.one * diameter, cf = at(b, localCf), color = color, material = material, parent = b.folder }
	if extra then
		for k, v in extra do
			spec[k] = v
		end
	end
	local part = Parts.ball(spec)
	tag(part, b.tier)
	return part
end

local function lantern(b: Builder, localCf: CFrame, withLight: boolean)
	block(b, Vector3.new(1.6, 0.5, 1.6), localCf, C.Trim, M.SmoothPlastic)
	local glass = block(b, Vector3.new(1.2, 1.6, 1.2), localCf * CFrame.new(0, 1.05, 0), b.accent, M.Neon, { collide = false, shadow = false })
	block(b, Vector3.new(1.8, 0.4, 1.8), localCf * CFrame.new(0, 2.05, 0), C.Trim, M.SmoothPlastic)
	if withLight then
		Parts.light(glass, b.accent, 18, 1.4)
	end
end

----------------------------------------------------------------------------
-- Tier 1: foundation, ramp, gate, balustrade
----------------------------------------------------------------------------

local function buildBase(b: Builder)
	local h = Layout.PlatformHeight
	-- Phase 5.5: the foundation wears a pastel of the Sanctuary's candy colour,
	-- so every home is recognisable from across the island.
	cylinder(b, Vector3.new(R * 2 + 4, h - 0.4, R * 2 + 4), CFrame.new(0, -(h + 0.4) / 2, 0), b.accent:Lerp(Color3.new(1, 1, 1), 0.3), M.Slate, { name = "Foundation" })
	cylinder(b, Vector3.new(R * 2 + 5.2, 1.4, R * 2 + 5.2), CFrame.new(0, -1.3, 0), C.Trim, M.SmoothPlastic, { name = "Ledge" })
	-- Stacked discs reveal thin glowing inlays; every layer is >= 0.15 studs
	-- apart vertically so nothing z-fights at a distance.
	cylinder(b, Vector3.new(R * 2 + 1, 0.5, R * 2 + 1), CFrame.new(0, -0.43, 0), b.accent, M.Neon, { name = "AccentRing", shadow = false })
	cylinder(b, Vector3.new(R * 2, 0.6, R * 2), CFrame.new(0, -0.3, 0), C.StoneLight, M.Cobblestone, { name = "Floor" })
	cylinder(b, Vector3.new(31, 0.4, 31), CFrame.new(0, -0.05, 0), b.accent, M.Neon, { name = "InnerRing", shadow = false })
	cylinder(b, Vector3.new(30, 0.5, 30), CFrame.new(0, 0.05, 0), Palette.Core.Cream, M.Marble, { name = "InnerFloor" })

	-- Ramp down to the ring road.
	local len = Layout.RampLength
	local rampCf = CFrame.new(0, -h / 2, -(R + len / 2))
	local ramp = Parts.wedge({ size = Vector3.new(Layout.GateWidth, h, len), cf = at(b, rampCf), color = C.Stone, material = M.Cobblestone, parent = b.folder })
	ramp.Name = "Ramp"
	local slope = math.atan(h / len)
	for _, side in { -1, 1 } do
		local x = side * (Layout.GateWidth / 2 + 0.6)
		block(b, Vector3.new(1.2, 2.2, math.sqrt(len * len + h * h)), CFrame.new(x, -h / 2 + 1.1, -(R + len / 2)) * CFrame.Angles(-slope, 0, 0), C.Trim, M.SmoothPlastic, { name = "RampRail" })
		block(b, Vector3.new(1.8, h + 2.6, 1.8), CFrame.new(x, -h / 2 + 1.3, -(R + len) + 0.9), C.Stone, M.Slate)
		lantern(b, CFrame.new(x, 2.6, -(R + len) + 0.9), false)
	end

	-- Glowing guide strips leading up the ramp.
	for _, side in { -1, 1 } do
		local x = side * (Layout.GateWidth / 2 - 0.9)
		block(b, Vector3.new(0.35, 0.2, math.sqrt(len * len + h * h) - 1), CFrame.new(x, -h / 2 + 0.12, -(R + len / 2)) * CFrame.Angles(-slope, 0, 0), b.accent, M.Neon, { collide = false, shadow = false, name = "RampGuide" })
	end

	-- Planters softening the starting Outpost.
	for _, phi in { 160, -160, 35, -35 } do
		local cf = polar(phi, R - 6.5, 0)
		block(b, Vector3.new(3, 1.2, 3), cf * CFrame.new(0, 0.6, 0), C.Stone, M.Slate, { name = "Planter" })
		block(b, Vector3.new(3.2, 0.3, 3.2), cf * CFrame.new(0, 1.25, 0), C.Trim, M.SmoothPlastic)
		ball(b, 2.8, cf * CFrame.new(0, 2, 0), Palette.World.Leaf, M.SmoothPlastic, { name = "Shrub" })
		ball(b, 0.45, cf * CFrame.new(0.7, 2.9, 0.4), b.accent, M.Neon, { collide = false, shadow = false, name = "Bloom" })
	end

	-- Gate posts with lanterns.
	for _, side in { -1, 1 } do
		local x = side * (Layout.GateWidth / 2 + 1.5)
		block(b, Vector3.new(2.8, 12, 2.8), CFrame.new(x, 6, -R + 0.6), C.StoneLight, M.Slate, { name = "GatePost" })
		block(b, Vector3.new(3.4, 0.8, 3.4), CFrame.new(x, 12.4, -R + 0.6), C.Trim, M.SmoothPlastic)
		lantern(b, CFrame.new(x, 13.05, -R + 0.6), true)
		block(b, Vector3.new(0.3, 7, 0.2), CFrame.new(x, 5.5, -R - 0.85), b.accent, M.Neon, { collide = false, shadow = false })
		-- Pennant on top of each gate post.
		cylinder(b, Vector3.new(0.3, 4, 0.3), CFrame.new(x, 15.5, -R + 0.6), C.Trim, M.SmoothPlastic, { collide = false, name = "FlagPole" })
		local pennant = Parts.wedge({ size = Vector3.new(0.15, 1.6, 2.6), cf = at(b, CFrame.new(x, 16.6, -R + 0.6 - 1.3) * CFrame.Angles(0, 0, 0) * CFrame.Angles(math.rad(90), 0, 0)), color = b.accent, material = M.SmoothPlastic, collide = false, shadow = false, parent = b.folder })
		pennant.Name = "Pennant"
		tag(pennant, b.tier)
	end
	-- Party bunting strung between the gate posts.
	local span = Layout.GateWidth + 3
	block(b, Vector3.new(span, 0.18, 0.18), CFrame.new(0, 10.6, -R - 0.2), C.StoneLight, M.SmoothPlastic, { collide = false, shadow = false, name = "BuntingCord" })
	local flags = 6
	for k = 1, flags do
		local x = -span / 2 + (k - 0.5) * span / flags
		local sag = -math.sin((k - 0.5) / flags * math.pi) * 0.9
		local flag = Parts.wedge({
			size = Vector3.new(0.12, 1.5, 1.3),
			cf = at(b, CFrame.new(x, 9.85 + sag, -R - 0.2) * CFrame.Angles(math.rad(180), math.rad(90), 0)),
			color = if k % 2 == 0 then Palette.Core.Sunny else b.accent,
			material = M.SmoothPlastic,
			collide = false,
			shadow = false,
			parent = b.folder,
		})
		flag.Name = "Bunting"
		tag(flag, b.tier)
	end

	-- Balustrade around the rim, open at the gate.
	local segments = 20
	local step = 360 / segments
	for k = 0, segments - 1 do
		local phi = step / 2 + k * step
		if math.abs(phi - 180) < step then
			continue
		end
		local length = 2 * (R - 0.8) * math.sin(math.rad(step / 2))
		block(b, Vector3.new(length, 3, 1.2), polar(phi, R - 0.8, 1.5), C.StoneLight, M.Slate, { name = "Wall" })
		block(b, Vector3.new(length + 0.2, 0.4, 1.6), polar(phi, R - 0.8, 3.15), C.Trim, M.SmoothPlastic, { name = "WallCap" })
		block(b, Vector3.new(1.8, 4, 1.8), polar(phi + step / 2, R - 0.8, 2), C.Stone, M.Slate, { name = "WallPost" })
		if k % 2 == 0 then
			block(b, Vector3.new(0.7, 0.7, 0.7), polar(phi + step / 2, R - 0.8, 4.5) * CFrame.Angles(math.rad(45), 0, math.rad(45)), b.accent, M.Neon, { collide = false, shadow = false, name = "PostGlow" })
		end
	end
end

----------------------------------------------------------------------------
-- Pedestals & Core
----------------------------------------------------------------------------

local function buildPedestals(model: Model, origin: CFrame, accent: Color3)
	local folder = Parts.folder("Pedestals", model)
	for slot = 1, #Layout.SlotAngles do
		local pedestal = Parts.model("Pedestal" .. slot, folder)
		pedestal:SetAttribute("Slot", slot)
		local cf = origin * Layout.slotLocal(slot)
		Parts.cylinder({ size = Vector3.new(5.4, 0.8, 5.4), cf = cf * CFrame.new(0, 0.4, 0), color = C.Stone, material = M.Slate, parent = pedestal, name = "Base" })
		Parts.cylinder({ size = Vector3.new(3.2, 2.1, 3.2), cf = cf * CFrame.new(0, 1.85, 0), color = C.StoneLight, material = M.Marble, parent = pedestal, name = "Column" })
		Parts.cylinder({ size = Vector3.new(5.3, 0.3, 5.3), cf = cf * CFrame.new(0, 2.95, 0), color = accent, material = M.Neon, parent = pedestal, name = "Ring", shadow = false })
		Parts.cylinder({ size = Vector3.new(5, 0.5, 5), cf = cf * CFrame.new(0, 3.05, 0), color = C.Trim, material = M.SmoothPlastic, parent = pedestal, name = "Top" })
		Parts.block({ size = Vector3.new(0.35, 1.3, 0.12), cf = cf * CFrame.new(0, 1.85, -1.62), color = accent, material = M.Neon, collide = false, shadow = false, parent = pedestal, name = "Rune" })
		pedestal:SetAttribute("State", "Hidden")
		for _, part in pedestal:GetChildren() do
			if part:IsA("BasePart") then
				part:SetAttribute("BaseTransparency", part.Transparency)
				part.Transparency = 1
				part.CanCollide = false
			end
		end
	end
end

local function buildCore(model: Model, origin: CFrame, accent: Color3)
	local core = Parts.model("Core", model)
	local function p(size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, name: string, collide: boolean?)
		return Parts.cylinder({ size = size, cf = origin * cf, color = color, material = material, parent = core, name = name, collide = collide, shadow = false })
	end
	p(Vector3.new(9, 1.4, 9), CFrame.new(0, 0.7, 0), C.StoneLight, M.Slate, "Base")
	p(Vector3.new(9.6, 0.5, 9.6), CFrame.new(0, 0.9, 0), accent, M.Neon, "BaseRing")
	for k = 0, 3 do
		local a = math.rad(45 + k * 90)
		Parts.block({ size = Vector3.new(0.9, 7.2, 0.9), cf = origin * CFrame.new(math.cos(a) * 3.9, 4.6, math.sin(a) * 3.9), color = C.Stone, material = M.Slate, parent = core, name = "Strut" })
	end
	p(Vector3.new(3.4, 6.2, 3.4), CFrame.new(0, 4.5, 0), Color3.fromRGB(200, 240, 255), M.Glass, "Capsule").Transparency = 0.65
	local fill = p(Vector3.new(2.6, 0.2, 2.6), CFrame.new(0, 1.6, 0), ESSENCE, M.Neon, "Fill", false)
	fill:SetAttribute("BottomY", 1.5)
	fill:SetAttribute("MaxHeight", 5.8)
	p(Vector3.new(5, 1, 5), CFrame.new(0, 8.1, 0), C.StoneLight, M.Slate, "Cap")
	p(Vector3.new(5.4, 0.4, 5.4), CFrame.new(0, 7.75, 0), accent, M.Neon, "CapRing")
	local crystal = Parts.block({ size = Vector3.one * 1.8, cf = origin * CFrame.new(0, 11, 0) * CORNER_UP, color = ESSENCE, material = M.Neon, collide = false, shadow = false, parent = core, name = "Crystal" })
	Parts.light(crystal, ESSENCE, 16, 1.5)
	-- Collection zone outline: a flat glowing circle around the Core.
	local padHolder = Parts.block({ size = Vector3.one, cf = origin * CFrame.new(0, 0.45, 0), transparency = 1, collide = false, shadow = false, parent = core, name = "PadRing" })
	padHolder.CanQuery = false
	Parts.beamRing(padHolder, CFrame.identity, 8, 0.35, accent, 0.15)

	local motes = Instance.new("ParticleEmitter")
	motes.Name = "Motes"
	motes.Texture = SPARKLE
	motes.Color = ColorSequence.new(ESSENCE)
	motes.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	motes.Lifetime = NumberRange.new(1.2, 2)
	motes.Speed = NumberRange.new(1, 2)
	motes.SpreadAngle = Vector2.new(25, 25)
	motes.Rate = 5
	motes.LightEmission = 1
	motes.Parent = crystal
	core.PrimaryPart = crystal
end

local function buildBarrier(model: Model, origin: CFrame, accent: Color3, index: number)
	local folder = Parts.folder("Barrier", model)
	local segments = 20
	local step = 360 / segments
	for k = 0, segments - 1 do
		local phi = step / 2 + k * step
		local radius = R + 0.6
		local length = 2 * radius * math.sin(math.rad(step / 2)) + 0.4
		local part = Parts.block({
			size = Vector3.new(length, 26, 1),
			cf = origin * polar(phi, radius, 12),
			color = accent,
			material = M.ForceField,
			transparency = 1,
			collide = false,
			shadow = false,
			parent = folder,
			name = "Wall",
		})
		part.CollisionGroup = "Barrier" .. index
		part.CanQuery = false
	end
	local dome = Parts.ball({
		size = Vector3.one * (R * 2 + 6),
		cf = origin,
		color = accent,
		material = M.ForceField,
		transparency = 1,
		collide = false,
		shadow = false,
		parent = folder,
		name = "Dome",
	})
	dome.CanQuery = false
end

----------------------------------------------------------------------------
-- Higher tiers
----------------------------------------------------------------------------

local function buildTier2(b: Builder)
	for _, phi in { 55, -55, 125, -125 } do
		local cf = polar(phi, 31, 0)
		cylinder(b, Vector3.new(2.8, 13, 2.8), cf * CFrame.new(0, 6.5, 0), C.StoneLight, M.Marble)
		cylinder(b, Vector3.new(3.2, 0.5, 3.2), cf * CFrame.new(0, 4, 0), b.accent, M.Neon, { shadow = false })
		cylinder(b, Vector3.new(3.2, 0.5, 3.2), cf * CFrame.new(0, 9, 0), b.accent, M.Neon, { shadow = false })
		cylinder(b, Vector3.new(4, 1.2, 4), cf * CFrame.new(0, 13.6, 0), C.Trim, M.SmoothPlastic)
		local bowl = cylinder(b, Vector3.new(3.2, 0.9, 3.2), cf * CFrame.new(0, 14.6, 0), C.StoneDark, M.Slate)
		local fire = Instance.new("ParticleEmitter")
		fire.Texture = FIRE
		fire.Color = ColorSequence.new(Color3.new(1, 1, 1), b.accent)
		fire.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.6),
			NumberSequenceKeypoint.new(1, 0.2),
		})
		fire.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		fire.Lifetime = NumberRange.new(0.6, 0.9)
		fire.Speed = NumberRange.new(3, 5)
		fire.SpreadAngle = Vector2.new(10, 10)
		fire.Rate = 14
		fire.LightEmission = 1
		fire.Parent = bowl
		Parts.light(bowl, b.accent, 20, 1.2)
	end
	-- Floor runes radiating from the inner circle.
	for k = 0, 7 do
		local phi = k * 45 + 22.5
		if math.abs(phi - 180) < 30 then
			continue
		end
		block(b, Vector3.new(0.5, 0.08, 6), polar(phi, 21.5 + 3, 0.02), b.accent, M.Neon, { collide = false, shadow = false, transparency = 0.2 })
	end
	-- Banners on the gate posts.
	for _, side in { -1, 1 } do
		local x = side * (Layout.GateWidth / 2 + 1.5)
		block(b, Vector3.new(2.2, 6.5, 0.15), CFrame.new(x, 7.5, -R - 0.85), b.accent, M.Fabric, { collide = false })
		block(b, Vector3.new(2.4, 0.3, 0.25), CFrame.new(x, 10.85, -R - 0.85), GOLD, M.Foil, { collide = false })
	end
	-- Gate arch.
	block(b, Vector3.new(Layout.GateWidth + 7, 2, 3.4), CFrame.new(0, 13.8, -R + 0.6), C.StoneLight, M.Slate)
	block(b, Vector3.new(Layout.GateWidth + 8, 0.6, 3.8), CFrame.new(0, 15, -R + 0.6), C.Trim, M.SmoothPlastic)
	block(b, Vector3.one * 2, CFrame.new(0, 13.8, -R - 0.4) * CFrame.Angles(0, 0, math.rad(45)), b.accent, M.Neon, { collide = false, shadow = false })
end

local function buildTier3(b: Builder)
	for _, phi in { 30, -30, 72, -72, 112, -112, 150, -150 } do
		local cf = polar(phi, R - 2.6, 0)
		cylinder(b, Vector3.new(2.4, 16.5, 2.4), cf * CFrame.new(0, 8.25, 0), C.StoneLight, M.Marble)
		cylinder(b, Vector3.new(3.2, 1, 3.2), cf * CFrame.new(0, 0.5, 0), C.Trim, M.SmoothPlastic)
	end
	-- Architrave ring.
	local segments = 16
	for k = 0, segments - 1 do
		local phi = k * (360 / segments)
		local radius = R - 2.6
		local length = 2 * radius * math.sin(math.rad(180 / segments)) + 0.3
		block(b, Vector3.new(length, 1.8, 2.6), polar(phi, radius, 17.4), C.StoneLight, M.Slate)
		block(b, Vector3.new(length, 0.35, 0.3), polar(phi, radius - 1.35, 17.4), b.accent, M.Neon, { collide = false, shadow = false })
	end
	-- Hanging lanterns.
	for i, phi in { 0, 90, -90, 145, -145 } do
		local cf = polar(phi, R - 6, 0)
		block(b, Vector3.new(0.12, 3.5, 0.12), cf * CFrame.new(0, 14.6, 0), C.Trim, M.Metal, { collide = false })
		local orb = ball(b, 1.5, cf * CFrame.new(0, 12.4, 0), b.accent, M.Neon, { collide = false, shadow = false })
		if i <= 2 then
			Parts.light(orb, b.accent, 16, 1)
		end
	end
	-- Crystal clusters between pedestals and walls.
	for _, phi in { 90, -90, 20, -20 } do
		local cf = polar(phi, 28.5, 0)
		block(b, Vector3.new(1.4, 5, 1.4), cf * CFrame.new(0, 2.2, 0) * CFrame.Angles(0, math.rad(45), math.rad(8)), b.accent, M.Neon, { shadow = false })
		block(b, Vector3.new(1, 3.4, 1), cf * CFrame.new(1, 1.4, 0.4) * CFrame.Angles(0, math.rad(20), math.rad(-24)), b.accent, M.Glass, { transparency = 0.2 })
		block(b, Vector3.new(0.9, 2.6, 0.9), cf * CFrame.new(-0.9, 1.1, -0.3) * CFrame.Angles(0, math.rad(60), math.rad(26)), b.accent, M.Glass, { transparency = 0.2 })
	end
end

local function buildTier4(b: Builder)
	for _, phi in { 50, -50, 130, -130 } do
		local cf = polar(phi, R + 4.5, 0)
		block(b, Vector3.new(6, 30, 6), cf * CFrame.new(0, 5, 0), C.Stone, M.Slate)
		block(b, Vector3.new(7, 1.2, 7), cf * CFrame.new(0, 20.6, 0), C.Trim, M.SmoothPlastic)
		block(b, Vector3.new(4.4, 8, 4.4), cf * CFrame.new(0, 25.2, 0), C.StoneLight, M.Slate)
		block(b, Vector3.new(0.5, 6, 4.5), cf * CFrame.new(0, 25.2, 0), b.accent, M.Neon, { collide = false, shadow = false })
		local tip = block(b, Vector3.new(3, 3, 3), cf * CFrame.new(0, 31, 0) * CORNER_UP, b.accent, M.Neon, { shadow = false })
		local a0 = Parts.attachment(tip, Vector3.zero, "BeamStart")
		local a1 = Parts.attachment(tip, Vector3.new(0, 0, 0), "BeamEnd")
		a1.WorldPosition = tip.Position + Vector3.new(0, 220, 0)
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Width0 = 1.6
		beam.Width1 = 0.2
		beam.Color = ColorSequence.new(b.accent)
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.FaceCamera = true
		beam.Parent = tip
		tag(beam, b.tier)
	end
	-- Orbiting stones (animated client-side around the Sanctuary centre).
	local orbit = Instance.new("Model")
	orbit.Name = "Orbit"
	orbit.Parent = b.folder
	tag(orbit, b.tier)
	local rng = Random.new(b.tier * 17 + math.floor(b.origin.Position.X))
	for k = 0, 9 do
		local a = math.rad(k * 36)
		local stone = Parts.block({
			size = Vector3.new(rng:NextNumber(2, 3.5), rng:NextNumber(1.6, 2.8), rng:NextNumber(2, 3.2)),
			cf = b.origin * CFrame.new(math.cos(a) * 26, 23 + math.sin(k * 1.7) * 2.5, math.sin(a) * 26) * CFrame.Angles(rng:NextNumber(0, 3), rng:NextNumber(0, 3), 0),
			color = C.StoneDark,
			material = M.Slate,
			collide = false,
			parent = orbit,
			name = "OrbitStone",
		})
		tag(stone, b.tier)
		local glow = Parts.block({
			size = Vector3.new(0.6, 0.6, 0.6),
			cf = stone.CFrame * CFrame.new(0, stone.Size.Y / 2 + 0.4, 0) * CORNER_UP,
			color = b.accent,
			material = M.Neon,
			collide = false,
			shadow = false,
			parent = orbit,
			name = "OrbitGlow",
		})
		tag(glow, b.tier)
	end
	orbit:SetAttribute("Center", b.origin.Position)
end

local function buildTier5(b: Builder)
	-- Floating halo.
	local halo = block(b, Vector3.one, CFrame.new(0, 34, 0), b.accent, M.SmoothPlastic, { transparency = 1, collide = false, shadow = false, name = "Halo" })
	Parts.beamRing(halo, CFrame.identity, 30, 1.4, GOLD, 0)
	Parts.beamRing(halo, CFrame.new(0, -1.5, 0), 23, 0.8, b.accent, 0.1)
	Parts.beamRing(halo, CFrame.new(0, 1.2, 0), 33, 0.4, Color3.new(1, 1, 1), 0.4)
	local aurora = Instance.new("ParticleEmitter")
	aurora.Texture = SPARKLE
	aurora.Color = ColorSequence.new(GOLD, b.accent)
	aurora.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 0.8),
		NumberSequenceKeypoint.new(1, 0),
	})
	aurora.Lifetime = NumberRange.new(2, 3)
	aurora.Speed = NumberRange.new(2, 4)
	aurora.SpreadAngle = Vector2.new(180, 30)
	aurora.Rate = 12
	aurora.LightEmission = 1
	aurora.Parent = halo
	-- Gilded rails on the balustrade.
	local segments = 20
	local step = 360 / segments
	for k = 0, segments - 1 do
		local phi = step / 2 + k * step
		if math.abs(phi - 180) < step then
			continue
		end
		local length = 2 * (R - 0.8) * math.sin(math.rad(step / 2))
		block(b, Vector3.new(length + 0.3, 0.3, 1.8), polar(phi, R - 0.8, 3.5), GOLD, M.Foil, { reflectance = 0.2 })
	end
	-- Sky beam from the core.
	local beacon = block(b, Vector3.one, CFrame.new(0, 12.5, 0), b.accent, M.SmoothPlastic, { transparency = 1, collide = false, shadow = false, name = "Beacon" })
	local a0 = Parts.attachment(beacon, Vector3.zero, "BeamStart")
	local a1 = Parts.attachment(beacon, Vector3.new(0, 420, 0), "BeamEnd")
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = 2.4
	beam.Width1 = 0.4
	beam.Color = ColorSequence.new(GOLD, b.accent)
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Parent = beacon
end

local TIER_BUILDERS: { [number]: (Builder) -> () } = {
	[2] = buildTier2,
	[3] = buildTier3,
	[4] = buildTier4,
	[5] = buildTier5,
}

----------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------

function SanctuaryBuilder.create(index: number, parent: Instance): Model
	local origin = Layout.plotCFrame(index)
	local accent = Theme.PlotColors[index] or Theme.PlotColors[1]
	local model = Parts.model("Sanctuary" .. index, parent)
	model:SetAttribute("Index", index)
	model:SetAttribute("Accent", accent)

	local base: Builder = { model = model, origin = origin, accent = accent, folder = Parts.folder("Base", model), tier = 1 }
	buildBase(base)
	Parts.folder("Structure", model)
	buildPedestals(model, origin, accent)
	buildCore(model, origin, accent)
	buildBarrier(model, origin, accent, index)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Size = Vector3.new(6, 0.4, 6)
	spawn.CFrame = origin * CFrame.new(0, 0.2, -12)
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn.CanTouch = false
	spawn.Transparency = 1
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.AllowTeamChangeOnTouch = false
	spawn.Enabled = true
	spawn.Parent = model

	local sign = Parts.block({
		size = Vector3.one,
		cf = origin * CFrame.new(0, 19, -R + 0.6),
		transparency = 1,
		collide = false,
		shadow = false,
		parent = model,
		name = "SignAnchor",
	})
	sign.CanQuery = false

	model.PrimaryPart = (model:FindFirstChild("Core") :: Model).PrimaryPart
	return model
end

-- Ensures the Structure folder contains exactly tiers 2..tier.
function SanctuaryBuilder.setTier(model: Model, tier: number)
	local structure = model:FindFirstChild("Structure") :: Folder
	local index = model:GetAttribute("Index") :: number
	local origin = Layout.plotCFrame(index)
	local accent = model:GetAttribute("Accent") :: Color3
	for _, child in structure:GetChildren() do
		local childTier = child:GetAttribute("Tier") :: number?
		if childTier and childTier > tier then
			child:Destroy()
		end
	end
	for t = 2, tier do
		if structure:FindFirstChild("Tier" .. t) == nil then
			local folder = Parts.folder("Tier" .. t, structure)
			folder:SetAttribute("Tier", t)
			local builder = TIER_BUILDERS[t]
			if builder then
				builder({ model = model, origin = origin, accent = accent, folder = folder, tier = t })
			end
		end
	end
	model:SetAttribute("Tier", tier)
end

return SanctuaryBuilder
