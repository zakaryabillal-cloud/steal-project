--!strict
-- Boss visuals (V2 phase 6), client only, Cartoon & Goofy
-- (docs/ART_DIRECTION.md):
--   * the boss's body (Client/Boss/BossModels: Void Warden, Forgeheart,
--     Tempest Seraph) follows the server anchor with squash & stretch, a face
--     per mood and one readable pose per action (anticipation before every
--     attack);
--   * phase 7A: per-boss attack drawings (the Void Warden's here,
--     Forgeheart's in Client/Boss/ForgeheartFX through the drawing kit),
--     per-boss warning / action sounds and arena ambience;
--   * phase 7B: the Tempest Seraph's drawings (Client/Boss/TempestSeraphFX,
--     same kit + a few helpers: bars between two points, "BossLock" reticle
--     positions from the server, shouts), her poses (Zap, Twirl, Blow,
--     Charge, Storm) and her defeat (she pops into a little drizzle);
--   * telegraphs: every attack draws its shape on the floor BEFORE it can
--     hurt, filling yellow -> red with an ink outline (rings, discs,
--     quarters), then a short impact effect in the attack's own colour;
--   * juicy feedback: "POW!" + stars on our strikes, "BONK!" on hits, dizzy
--     stars, confetti poof when he runs away sulking. No damage numbers;
--   * the portal: a countdown board above the ring and a brighter membrane
--     while it is open.
-- Particle bursts follow Settings.particleScale (fewer on Low / mobile) and
-- every instance created here is destroyed with its attack or the arena.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Bosses = require(Shared.Config.Bosses)
local Emoji = require(Shared.Config.Emoji)
local Locale = require(Shared.Locale)
local Format = require(Shared.Util.Format)

local Kit = script.Parent.Parent.UI.Kit
local Create = require(Kit.Create)
local Style = require(Kit.Style)
local Tween = require(Kit.Tween)

local Boss = require(script.Parent.Boss)
local Settings = require(script.Parent.Settings)
local Audio = require(script.Parent.Audio)
local CameraFX = require(script.Parent.CameraFX)
local CharacterFX = require(script.Parent.CharacterFX)
local RelicRenderer = require(script.Parent.RelicRenderer)
local BossFolder = script.Parent.Parent.Boss
local BossRig = require(BossFolder.BossRig)
local BossModels = require(BossFolder.BossModels)
local ForgeheartFX = require(BossFolder.ForgeheartFX)
local TempestSeraphFX = require(BossFolder.TempestSeraphFX)

local BossFX = {}

local INK = Color3.fromRGB(30, 27, 75)
local WARN = Color3.fromRGB(255, 220, 60)
local DANGER = Color3.fromRGB(255, 70, 90)
-- One attack = one colour (after impact).
local ATTACK_COLORS: { [string]: Color3 } = {
	broom_wave = Color3.fromRGB(255, 196, 90),
	goo_puddles = Color3.fromRGB(120, 230, 110),
	dust_bunnies = Color3.fromRGB(200, 200, 225),
	belly_flop = Color3.fromRGB(176, 110, 255),
	big_cleanup = Color3.fromRGB(90, 190, 255),
}
for attackId, color in ForgeheartFX.Colors do
	ATTACK_COLORS[attackId] = color
end
for attackId, color in TempestSeraphFX.Colors do
	ATTACK_COLORS[attackId] = color
end
BossFX.AttackColors = ATTACK_COLORS
local SAFE = Color3.fromRGB(110, 255, 170)
local POWS = { "POW!", "BAM!", "BONK!", "WHAM!", "BOP!" }

local localPlayer = Players.LocalPlayer
local folder: Folder
local rig: BossRig.Rig? = nil
local rigModel: BossRig.ModelModule? = nil
local rigBoss = ""
local lastAction: string? = nil
local ambience: { Sound } = {}
local rigAnchor: BasePart? = nil
local rigPosition: Vector3? = nil
local zzz: BillboardGui? = nil
local dizzyStars: BillboardGui? = nil
local wobble = 0
local hopLand = 0
local hitFlash = 0
local lastAttack: { [string]: any }? = nil
local bubble: BillboardGui? = nil
local bubbleLabel: TextLabel? = nil
local bubbleIcon: TextLabel? = nil
local bubbleFrame: Frame? = nil

-- Broom waves rolling right now (read by the HUD "JUMP!" hint).
type Wave = { origin: Vector3, startAt: number, speed: number, maxRadius: number }
local waves: { Wave } = {}

-- Seconds before a broom wave front reaches `position` (nil = none coming).
function BossFX.waveEta(position: Vector3): number?
	local t = workspace:GetServerTimeNow()
	local best: number? = nil
	for i = #waves, 1, -1 do
		local wave = waves[i]
		if t > wave.startAt + wave.maxRadius / wave.speed + 0.2 then
			table.remove(waves, i)
			continue
		end
		local d = Vector3.new(position.X - wave.origin.X, 0, position.Z - wave.origin.Z).Magnitude
		local front = math.max(0, t - wave.startAt) * wave.speed
		if front < d and d <= wave.maxRadius then
			local eta = (d - front) / wave.speed + math.max(0, wave.startAt - t)
			if best == nil or eta < (best :: number) then
				best = eta
			end
		end
	end
	return best
end

-- Safe area of the current special (read by the HUD arrow): the Big
-- Cleanup's quarter (safeAngle) or Forgeheart's safe rocks (spots).
export type SafeZone = { position: Vector3, radius: number, untilTime: number, safeAngle: number?, center: Vector3, spots: { Vector3 }? }
BossFX.safeZone = nil :: SafeZone?

type Visual = {
	kind: string,
	untilTime: number,
	update: ((now: number, dt: number) -> boolean)?,
	instances: { Instance },
}
local visuals: { Visual } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function floorY(): number
	return Bosses.Arena.Center.Y + 0.12
end

local function particleScale(): number
	return Settings.particleScale()
end

----------------------------------------------------------------------------
-- Drawing helpers (local parts only)
----------------------------------------------------------------------------

local function newPart(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(part :: any)[key] = value
	end
	part.Parent = folder
	return part
end

-- Flat disc lying on the floor (cylinder standing up).
local function disc(center: Vector3, radius: number, color: Color3, transparency: number, y: number?): Part
	return newPart({
		Name = "Disc",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.12, radius * 2, radius * 2),
		CFrame = CFrame.new(center.X, (y or floorY()), center.Z) * CFrame.Angles(0, 0, math.pi / 2),
		Color = color,
		Transparency = transparency,
		Material = Enum.Material.Neon,
	})
end

local function setDisc(part: BasePart, radius: number)
	part.Size = Vector3.new(part.Size.X, math.max(0.05, radius * 2), math.max(0.05, radius * 2))
end

-- Ring of two curved beams (radius can change every frame).
type Ring = { holder: Part, a0: Attachment, a1: Attachment, beams: { Beam } }
local RING_K = 4 / 3
local function ring(center: Vector3, radius: number, width: number, color: Color3, y: number?): Ring
	local holder = newPart({ Name = "Ring", Size = Vector3.one * 0.2, Transparency = 1, CFrame = CFrame.new(center.X, y or floorY() + 0.2, center.Z) })
	local a0 = Instance.new("Attachment")
	local a1 = Instance.new("Attachment")
	a0.Parent = holder
	a1.Parent = holder
	local beams = {}
	for i = 1, 2 do
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Width0 = width
		beam.Width1 = width
		beam.Color = ColorSequence.new(color)
		beam.Transparency = NumberSequence.new(0.05)
		beam.LightEmission = 0.6
		beam.LightInfluence = 0
		beam.FaceCamera = true
		beam.Segments = 24
		beam:SetAttribute("Side", i)
		beam.Parent = holder
		table.insert(beams, beam)
	end
	local r: Ring = { holder = holder, a0 = a0, a1 = a1, beams = beams }
	return r
end

local function setRing(r: Ring, radius: number, color: Color3?)
	local axis = Vector3.new(0, 0, 1)
	local normal = Vector3.new(0, 1, 0)
	r.a0.CFrame = CFrame.fromMatrix(Vector3.new(-radius, 0, 0), axis, normal)
	r.a1.CFrame = CFrame.fromMatrix(Vector3.new(radius, 0, 0), axis, normal)
	for i, beam in r.beams do
		local k = RING_K * radius * (if i == 1 then 1 else -1)
		beam.CurveSize0 = k
		beam.CurveSize1 = -k
		if color then
			beam.Color = ColorSequence.new(color)
		end
	end
end

-- Phase 7B: a bar from `a` to `b` (`width` across, `thickness` up: a flat
-- strip when both points are on the floor; vertical bars for lightning).
local function segmentFrame(a: Vector3, b: Vector3): CFrame
	local d = b - a
	local mid = (a + b) / 2
	if d.Magnitude < 1e-3 then
		return CFrame.new(mid)
	end
	local up = if math.abs(d.Unit.Y) > 0.9 then Vector3.new(1, 0, 0) else Vector3.new(0, 1, 0)
	return CFrame.lookAt(mid, b, up)
end

local function segment(a: Vector3, b: Vector3, width: number, color: Color3, transparency: number, thickness: number?): Part
	return newPart({
		Name = "Segment",
		Size = Vector3.new(width, thickness or 0.12, math.max(0.05, (b - a).Magnitude)),
		CFrame = segmentFrame(a, b),
		Color = color,
		Transparency = transparency,
		Material = Enum.Material.Neon,
	})
end

local function setSegment(part: BasePart, a: Vector3, b: Vector3, width: number?)
	part.Size = Vector3.new(width or part.Size.X, part.Size.Y, math.max(0.05, (b - a).Magnitude))
	part.CFrame = segmentFrame(a, b)
end

-- Flat triangle from two wedges (sector fill of the big special).
local function triangle(a: Vector3, b: Vector3, c: Vector3, w1: WedgePart, w2: WedgePart)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	if ab.Magnitude < 1e-3 or ac.Magnitude < 1e-3 or bc.Magnitude < 1e-3 then
		w1.Transparency, w2.Transparency = 1, 1
		return
	end
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	w1.Size = Vector3.new(0.12, height, math.abs(ab:Dot(back)))
	w1.CFrame = CFrame.fromMatrix((a + b) / 2, right, up, back)
	w2.Size = Vector3.new(0.12, height, math.abs(ac:Dot(back)))
	w2.CFrame = CFrame.fromMatrix((a + c) / 2, -right, up, -back)
end

local function wedge(color: Color3, transparency: number): WedgePart
	local w = Instance.new("WedgePart")
	w.Anchored = true
	w.CanCollide = false
	w.CanQuery = false
	w.CanTouch = false
	w.CastShadow = false
	w.Material = Enum.Material.Neon
	w.Color = color
	w.Transparency = transparency
	w.Parent = folder
	return w
end

-- Short world billboard text ("POW!", "BONK!", "SAFE").
local function shout(adornee: Instance?, position: Vector3?, text: string, color: Color3, size: number, duration: number)
	local holder: Part? = nil
	if not adornee and position then
		holder = newPart({ Name = "ShoutAnchor", Size = Vector3.one * 0.2, Transparency = 1, CFrame = CFrame.new(position) })
	end
	local gui: BillboardGui = Create("BillboardGui", {
		Name = "Shout",
		Size = UDim2.fromOffset(220, 90),
		StudsOffsetWorldSpace = Vector3.new(0, 2, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		Adornee = adornee or holder,
		Parent = folder,
	})
	local label = Style.text({
		Text = text,
		TextSize = size,
		FontFace = Style.burstFont(text),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = color,
		Rotation = math.random(-12, 12),
		Parent = gui,
	})
	Style.ink(label, 3)
	local scale: UIScale = Create("UIScale", { Scale = 0.3, Parent = label })
	Tween.play(scale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
	Tween.play(gui, duration, { StudsOffsetWorldSpace = Vector3.new(0, 5, 0) }, Enum.EasingStyle.Quad)
	Tween.play(label, duration * 0.4, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, duration * 0.6)
	task.delay(duration + 0.1, function()
		gui:Destroy()
		if holder then
			holder:Destroy()
		end
	end)
end
BossFX.shout = shout

local function burst(position: Vector3, color: Color3, size: number)
	if particleScale() <= 0 then
		return
	end
	RelicRenderer.burst(position, color, size * math.max(0.5, particleScale()), nil)
end

local function addVisual(kind: string, untilTime: number, instances: { Instance }, update: ((number, number) -> boolean)?)
	table.insert(visuals, { kind = kind, untilTime = untilTime, update = update, instances = instances })
end

-- Phase 7B: where the server froze each tracked reticle ("BossLock" FX,
-- key -> position): the drawings snap to it (the server is the authority).
local lockPositions: { [string]: { position: Vector3, at: number } } = {}

local function clearVisuals()
	BossFX.safeZone = nil
	table.clear(waves)
	table.clear(lockPositions)
	for _, visual in visuals do
		for _, instance in visual.instances do
			instance:Destroy()
		end
	end
	table.clear(visuals)
end

-- Phase 6.5 readability: YELLOW while he prepares, RED (flashing) from
-- Combat.DangerLead before the server applies the damage. Telegraphs are
-- parts (never particles): they stay visible on the lowest quality.
local DANGER_LEAD = Bosses.Combat.DangerLead
local dangerTickAt = 0

local function zoneColor(t: number, hitAt: number): (Color3, boolean)
	if t >= hitAt - DANGER_LEAD then
		local blink = math.floor(t * 16) % 2 == 0
		return if blink then DANGER else DANGER:Lerp(Color3.new(1, 1, 1), 0.35), true
	end
	return WARN, false
end
BossFX.zoneColor = zoneColor

-- One "tick!" when zones turn red (several puddles = one tick).
local function dangerTick()
	if os.clock() - dangerTickAt > 0.25 then
		dangerTickAt = os.clock()
		Audio.play("BossDanger")
	end
end

-- Disc telegraph: thick ink outline + edge ring + a yellow fill that grows
-- until the danger moment, then flashes red until `hitAt`, then `onImpact`.
local function discTelegraph(center: Vector3, radius: number, telegraphAt: number, hitAt: number, onImpact: (() -> ())?)
	local outline = disc(center, radius + 0.7, INK, 0.1, floorY() - 0.02)
	local back = disc(center, radius, WARN, 0.55, floorY())
	local fill = disc(center, 0.1, WARN, 0.15, floorY() + 0.02)
	local edge = ring(center, radius + 0.2, 0.8, WARN, floorY() + 0.3)
	setRing(edge, radius + 0.2)
	local fired, warned = false, false
	addVisual("disc", hitAt + 0.05, { outline, back, fill, edge.holder }, function(t: number)
		local k = math.clamp((t - telegraphAt) / math.max(0.05, hitAt - DANGER_LEAD - telegraphAt), 0, 1)
		setDisc(fill, radius * k)
		local color, danger = zoneColor(t, hitAt)
		fill.Color = color
		back.Color = color
		setRing(edge, radius + 0.2, color)
		if danger and not warned then
			warned = true
			dangerTick()
		end
		if t >= hitAt and not fired then
			fired = true
			if onImpact then
				onImpact()
			end
		end
		return true
	end)
end

----------------------------------------------------------------------------
-- Attacks
----------------------------------------------------------------------------

local function broomWave(data: { [string]: any }, telegraphAt: number)
	local origin = data.origin :: Vector3
	local speed = data.speed :: number
	local band = data.band :: number
	local maxRadius = data.maxRadius :: number
	for _, startAt in data.starts :: { number } do
		table.insert(waves, { origin = origin, startAt = startAt, speed = speed, maxRadius = maxRadius })
		-- Telegraph: a fat ring around him, filling yellow -> red.
		local warnRing = ring(origin, 9, band + 1, WARN, floorY() + 0.25)
		setRing(warnRing, 9)
		local fill = disc(origin, 0.1, WARN, 0.3, floorY() + 0.02)
		-- The rolling wave IS the danger: red, with a white crest to jump.
		local wave = ring(origin, 0.1, band, DANGER, floorY() + 0.3)
		local warned = false
		local crest = ring(origin, 0.1, band * 0.6, Color3.new(1, 1, 1), floorY() + 1.8)
		wave.holder.Parent = nil
		crest.holder.Parent = nil
		addVisual("wave", startAt + maxRadius / speed + 0.1, { warnRing.holder, fill, wave.holder, crest.holder }, function(t: number)
			if t < startAt then
				local k = math.clamp((t - telegraphAt) / math.max(0.05, startAt - DANGER_LEAD - telegraphAt), 0, 1)
				local color, danger = zoneColor(t, startAt)
				setRing(warnRing, 9 + math.sin(t * 20) * 0.3, color)
				setDisc(fill, 9 * k)
				fill.Color = color
				if danger and not warned then
					warned = true
					dangerTick()
				end
				return true
			end
			if warnRing.holder.Parent then
				warnRing.holder.Parent = nil
				fill.Parent = nil
				wave.holder.Parent = folder
				crest.holder.Parent = folder
				CameraFX.shake(0.15)
				Audio.playAt("VWSweep", origin)
			end
			local radius = (t - startAt) * speed
			setRing(wave, math.max(0.1, radius))
			setRing(crest, math.max(0.1, radius))
			return radius <= maxRadius
		end)
	end
end

local function gooPuddles(data: { [string]: any }, telegraphAt: number)
	local radius = data.radius :: number
	local hitAt = data.hitAt :: number
	local untilTime = data.untilTime :: number
	for _, spot in data.spots :: { Vector3 } do
		discTelegraph(spot, radius, telegraphAt, hitAt, function()
			local goo = disc(spot, radius, ATTACK_COLORS.goo_puddles, 0.15, floorY() + 0.04)
			goo.Material = Enum.Material.SmoothPlastic
			local shine = disc(spot + Vector3.new(radius * 0.3, 0, -radius * 0.25), radius * 0.25, Color3.new(1, 1, 1), 0.4, floorY() + 0.07)
			burst(spot + Vector3.new(0, 1, 0), ATTACK_COLORS.goo_puddles, 8)
			Audio.playAt("VWGooSplat", spot)
			addVisual("goo", untilTime, { goo, shine }, function(t: number)
				local left = untilTime - t
				if left < 0.6 then
					goo.Transparency = 1 - left / 0.6 * 0.85
					shine.Transparency = 1 - left / 0.6 * 0.6
				end
				return true
			end)
		end)
	end
end

local function bunny(position: Vector3): { Instance }
	local body = newPart({ Name = "DustBunny", Shape = Enum.PartType.Ball, Size = Vector3.one * 2.6, Color = ATTACK_COLORS.dust_bunnies, CFrame = CFrame.new(position) })
	local list: { Instance } = { body }
	if Settings.quality ~= "Low" then
		for _, side in { -1, 1 } do
			local eye = newPart({ Name = "Eye", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.8, Color = Color3.new(1, 1, 1) })
			local pupil = newPart({ Name = "Pupil", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.4, Color = INK })
			eye:SetAttribute("Side", side)
			pupil:SetAttribute("Side", side)
			table.insert(list, eye)
			table.insert(list, pupil)
		end
	end
	return list
end

local function dustBunnies(data: { [string]: any }, telegraphAt: number)
	local from = data.from :: Vector3
	local launchAt = data.launchAt :: number
	local radius = data.radius :: number
	local lands = data.lands :: { number }
	for i, spot in data.spots :: { Vector3 } do
		local landAt = lands[i] or launchAt + 1
		discTelegraph(spot, radius, telegraphAt, landAt, function()
			burst(spot + Vector3.new(0, 1, 0), ATTACK_COLORS.dust_bunnies, 7)
			Audio.playAt("VWDustPouf", spot)
		end)
		local parts = bunny(from)
		local target = Vector3.new(spot.X, floorY() + 1.3, spot.Z)
		addVisual("bunny", landAt, parts, function(t: number)
			local k = math.clamp((t - launchAt) / math.max(0.05, landAt - launchAt), 0, 1)
			local p = from:Lerp(target, k) + Vector3.new(0, 16 * 4 * k * (1 - k), 0)
			local spin = CFrame.Angles(t * 6, t * 4, 0)
			for _, instance in parts do
				local part = instance :: BasePart
				local side = part:GetAttribute("Side")
				if type(side) == "number" then
					local forward = (target - from)
					local look = if forward.Magnitude > 0.1 then CFrame.lookAt(p, p + Vector3.new(forward.X, 0, forward.Z)) else CFrame.new(p)
					local depth = if part.Name == "Pupil" then 1.45 else 1.15
					part.CFrame = look * CFrame.new(side * 0.55, 0.45, -depth)
				else
					part.CFrame = CFrame.new(p) * spin
				end
			end
			return true
		end)
	end
end

local function bellyFlop(data: { [string]: any }, telegraphAt: number)
	local to = data.to :: Vector3
	local landAt = data.landAt :: number
	local spot = Vector3.new(to.X, floorY(), to.Z)
	discTelegraph(spot, data.radius :: number, telegraphAt, landAt, function()
		hopLand = os.clock()
		burst(spot + Vector3.new(0, 1, 0), ATTACK_COLORS.belly_flop, 16)
		CameraFX.shakeAt(spot, 0.45, 70)
		Audio.playAt("VWImpact", spot)
	end)
end

local function bigCleanup(data: { [string]: any }, telegraphAt: number)
	local center = data.center :: Vector3
	local radius = (data.radius :: number) + 3
	local half = (data.safeWidth :: number) / 2
	local previous = telegraphAt
	for _, sweep in data.sweeps :: { { safeAngle: number, at: number } } do
		local startAt = previous
		local hitAt = sweep.at
		previous = hitAt
		local instances: { Instance } = {}
		local fans: { { w1: WedgePart, w2: WedgePart, a: number, b: number } } = {}
		for quarter = 0, 3 do
			local mid = quarter * math.pi / 2
			local diff = math.abs(((mid - sweep.safeAngle + math.pi) % (math.pi * 2)) - math.pi)
			if diff > half - 0.01 then
				for step = 0, 2 do
					local a = mid - math.pi / 4 + step * math.pi / 6
					local w1, w2 = wedge(WARN, 0.45), wedge(WARN, 0.45)
					table.insert(instances, w1)
					table.insert(instances, w2)
					table.insert(fans, { w1 = w1, w2 = w2, a = a, b = a + math.pi / 6 })
				end
			end
		end
		-- The safe quarter sparkles (and says so).
		local safeCenter = center + Vector3.new(math.cos(sweep.safeAngle), 0, math.sin(sweep.safeAngle)) * radius * 0.55
		local safe = disc(safeCenter, 11, SAFE, 0.45, floorY() + 0.03)
		table.insert(instances, safe)
		-- A tall green beacon you can see from anywhere in the arena.
		local beacon = newPart({
			Name = "SafeBeacon",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(40, 4, 4),
			CFrame = CFrame.new(safeCenter.X, floorY() + 20, safeCenter.Z) * CFrame.Angles(0, 0, math.pi / 2),
			Color = SAFE,
			Material = Enum.Material.Neon,
			Transparency = 0.45,
		})
		table.insert(instances, beacon)
		BossFX.safeZone = { position = Vector3.new(safeCenter.X, floorY(), safeCenter.Z), radius = 11, untilTime = hitAt, safeAngle = sweep.safeAngle, center = center }
		local label: BillboardGui = Create("BillboardGui", {
			Name = "Safe",
			Size = UDim2.fromOffset(240, 70),
			StudsOffsetWorldSpace = Vector3.new(0, 26, 0),
			AlwaysOnTop = true,
			LightInfluence = 0,
			Adornee = safe,
			Parent = folder,
		})
		local text = Style.text({ Text = Emoji.get("ready") .. " SAFE " .. Emoji.get("ready"), TextSize = 30, FontFace = Style.Fonts.Display, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = SAFE, Parent = label })
		Style.ink(text, 3)
		table.insert(instances, label)
		local fired, warned = false, false
		addVisual("cleanup", hitAt + 0.5, instances, function(t: number)
			local k = math.clamp((t - startAt) / math.max(0.05, hitAt - DANGER_LEAD - startAt), 0, 1)
			local zone, danger = zoneColor(t, hitAt)
			if danger and not warned then
				warned = true
				dangerTick()
			end
			local r = radius * math.max(0.05, k)
			local y = floorY() + 0.03
			for _, fan in fans do
				local a = center + Vector3.new(0, y - center.Y, 0)
				local b = a + Vector3.new(math.cos(fan.a), 0, math.sin(fan.a)) * r
				local c = a + Vector3.new(math.cos(fan.b), 0, math.sin(fan.b)) * r
				triangle(a, b, c, fan.w1, fan.w2)
				local color = if t >= hitAt then ATTACK_COLORS.big_cleanup else zone
				fan.w1.Color, fan.w2.Color = color, color
			end
			safe.Transparency = 0.35 + math.sin(t * 10) * 0.15
			beacon.Transparency = 0.4 + math.sin(t * 8) * 0.15
			if t >= hitAt and not fired then
				fired = true
				if BossFX.safeZone and BossFX.safeZone.untilTime == hitAt then
					BossFX.safeZone = nil
				end
				CameraFX.shake(0.35)
				Audio.playAt("VWCleanupSweep", center)
				for _, fan in fans do
					burst(center + Vector3.new(math.cos((fan.a + fan.b) / 2), 0.1, math.sin((fan.a + fan.b) / 2)) * radius * 0.6, ATTACK_COLORS.big_cleanup, 10)
				end
			end
			return true
		end)
	end
end

local PLAYERS: { [string]: ({ [string]: any }, number) -> () } = {
	broom_wave = broomWave,
	goo_puddles = gooPuddles,
	dust_bunnies = dustBunnies,
	belly_flop = bellyFlop,
	big_cleanup = bigCleanup,
}

-- One distinct warning sound and one icon per attack (the "!" bubble).
local WARN_SOUNDS: { [string]: string } = {
	broom_wave = "BossWarnWave",
	goo_puddles = "BossWarnGoo",
	dust_bunnies = "BossWarnBunny",
	belly_flop = "BossWarnFlop",
	big_cleanup = "BossWarnCleanup",
}
for attackId, key in ForgeheartFX.WarnSounds do
	WARN_SOUNDS[attackId] = key
end
for attackId, key in TempestSeraphFX.WarnSounds do
	WARN_SOUNDS[attackId] = key
end
BossFX.WarnSounds = WARN_SOUNDS
local ATTACK_ICONS: { [string]: string } = {
	broom_wave = "swirl",
	goo_puddles = "droplet",
	dust_bunnies = "bunny",
	belly_flop = "boom",
	big_cleanup = "water",
}
for attackId, icon in ForgeheartFX.Icons do
	ATTACK_ICONS[attackId] = icon
end
for attackId, icon in TempestSeraphFX.Icons do
	ATTACK_ICONS[attackId] = icon
end
BossFX.AttackIcons = ATTACK_ICONS

-- Sounds played when the boss changes action (server attribute "Action").
local ACTION_SOUNDS: { [string]: { [string]: string } } = {
	VoidWarden = { Intro = "VWAppear", Hop = "VWHop", Dizzy = "VWBounce", Defeated = "VWDefeat", PhaseChange = "BossPhaseUp" },
	Forgeheart = ForgeheartFX.ActionSounds :: any,
	TempestSeraph = TempestSeraphFX.ActionSounds :: any,
}
BossFX.ActionSounds = ACTION_SOUNDS

-- Drawing kit handed to the per-boss FX modules (same rules for everyone).
local function setSafeZone(zone: { [string]: any })
	BossFX.safeZone = zone :: any
end
local function clearSafeZone(untilTime: number)
	if BossFX.safeZone and BossFX.safeZone.untilTime == untilTime then
		BossFX.safeZone = nil
	end
end
local function safeLabel(adornee: BasePart, text: string, color: Color3): Instance
	local label: BillboardGui = Create("BillboardGui", {
		Name = "Safe",
		Size = UDim2.fromOffset(200, 60),
		StudsOffsetWorldSpace = Vector3.new(0, 24, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		Adornee = adornee,
		Parent = folder,
	})
	local textLabel = Style.text({ Text = Emoji.get("ready") .. " " .. text .. " " .. Emoji.get("ready"), TextSize = 28, FontFace = Style.Fonts.Display, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = color, Parent = label })
	Style.ink(textLabel, 3)
	return label
end
local kit: TempestSeraphFX.Kit = {
	now = now,
	floorY = floorY,
	newPart = newPart,
	disc = disc,
	setDisc = setDisc,
	ring = ring :: any,
	setRing = setRing :: any,
	discTelegraph = discTelegraph,
	zoneColor = zoneColor,
	dangerTick = dangerTick,
	burst = burst,
	addVisual = addVisual,
	addWave = function(origin: Vector3, startAt: number, speed: number, maxRadius: number)
		table.insert(waves, { origin = origin, startAt = startAt, speed = speed, maxRadius = maxRadius })
	end,
	setSafeZone = setSafeZone,
	clearSafeZone = clearSafeZone,
	safeLabel = safeLabel,
	playAt = function(key: string, position: Vector3, options: { [string]: any }?)
		Audio.playAt(key, position, options :: any)
	end,
	play = function(key: string)
		Audio.play(key)
	end,
	shake = function(amount: number)
		CameraFX.shake(amount)
	end,
	shakeAt = function(position: Vector3, amount: number, range: number)
		CameraFX.shakeAt(position, amount, range)
	end,
	colors = { Warn = WARN, Danger = DANGER, Safe = SAFE, Ink = INK },
	-- Phase 7B helpers (Tempest Seraph).
	segment = segment,
	setSegment = setSegment,
	lockPosition = function(key: string): Vector3?
		local entry = lockPositions[key]
		return if entry then entry.position else nil
	end,
	shout = function(position: Vector3, text: string, color: Color3, size: number, duration: number)
		shout(nil, position, text, color, size, duration)
	end,
	lowQuality = function(): boolean
		return Settings.quality == "Low"
	end,
}
for attackId, draw in ForgeheartFX.drawers(kit) do
	PLAYERS[attackId] = draw
end
for attackId, draw in TempestSeraphFX.drawers(kit) do
	PLAYERS[attackId] = draw
end

-- Draws an attack announced by the server ("BossAttack" FX).
function BossFX.attack(payload: { [string]: any })
	if not folder or type(payload.attack) ~= "string" or type(payload.data) ~= "table" then
		return
	end
	local draw = PLAYERS[payload.attack]
	if not draw then
		return
	end
	lastAttack = payload
	draw(payload.data, tonumber(payload.telegraphAt) or now())
	local anchor = Boss.anchor()
	Audio.playAt(WARN_SOUNDS[payload.attack] or "BossWarnWave", if anchor then anchor.Position else Bosses.Arena.Center, { volume = 1 })
end

-- Phase 7B: a tracked reticle froze on the server ("BossLock" FX: key,
-- position). Its drawing stops following its fighter and sits exactly there.
function BossFX.lock(payload: { [string]: any })
	if type(payload.key) ~= "string" or typeof(payload.position) ~= "Vector3" then
		return
	end
	local t = now()
	for key, entry in lockPositions do
		if t - entry.at > 20 then
			lockPositions[key] = nil
		end
	end
	lockPositions[payload.key] = { position = payload.position, at = t }
end

-- Tests / debug: the bolt reticles drawn right now (key -> position, locked).
function BossFX.reticles(): { [string]: { position: Vector3, locked: boolean, track: number? } }
	return TempestSeraphFX.debugReticles()
end

----------------------------------------------------------------------------
-- The boss body
----------------------------------------------------------------------------

local function attr(instance: Instance?, name: string): any
	return if instance then instance:GetAttribute(name) else nil
end

-- Forgeheart's own actions (phase 7A): arms = pose.broom, lava = pose.glow.
local function forgeheartPose(pose: BossRig.Pose, action: any, t: number, since: number, hitAt: number, attack: { [string]: any }?)
	if action == "Slam" then
		if t < hitAt then
			-- Fists raised high, leaning back: "WHOOM".
			local k = math.clamp(since / 0.5, 0, 1)
			pose.broom = k
			pose.lean = -0.18 * k
			pose.squash = 1 + 0.12 * k
			pose.mouth = 0.4
			pose.glow = 0.6
		elseif t < hitAt + 0.6 then
			pose.broom = -1
			pose.lean = 0.2
			pose.squash = 0.82
			pose.mouth = 0.9
		end
	elseif action == "Lob" then
		local launchAt = if attack and attack.data and type(attack.data.launchAt) == "number" then attack.data.launchAt else hitAt
		if t < launchAt then
			pose.broom = 0.4
			pose.lean = -0.25
			pose.glow = 0.8
		elseif t < launchAt + 0.5 then
			pose.broom = 0.9 - (t - launchAt) * 2
			pose.lean = 0.2
			pose.mouth = 0.6
		end
	elseif action == "Stomp" then
		if t < hitAt then
			-- Angry stomping: bounces and fists pumping.
			pose.squash = 1 + math.abs(math.sin(t * 9)) * 0.14 - 0.06
			pose.hands = math.sin(t * 9) * 1.2
			pose.mouth = 0.3
			pose.glow = 0.5
		elseif t < hitAt + 0.4 then
			pose.squash = 0.8
		end
	elseif action == "Roar" then
		if t < hitAt + 0.8 then
			-- Roaring at the sky, arms wide: meteors come.
			pose.mouth = 1
			pose.lean = -0.3
			pose.broom = 0.7 + math.sin(t * 6) * 0.1
			pose.squash = 1.08 + math.sin(t * 30) * 0.02
			pose.glow = 1
		end
	elseif action == "Erupt" then
		if t < hitAt then
			-- Heats up: glowing heart, shaking, arms up.
			pose.broom = 1
			pose.mouth = 0.7 + math.sin(t * 20) * 0.1
			pose.squash = 1.1 + math.sin(t * 40) * 0.03
			pose.glow = 1.4
		elseif t < hitAt + 0.6 then
			pose.broom = -1
			pose.squash = 0.75
			pose.mouth = 1
		end
	end
end

-- Last strike time of a Tempest Seraph attack (bolt volleys, storm waves).
local function lastStrike(attack: { [string]: any }?, hitAt: number): number
	local data = if attack and type(attack.data) == "table" then attack.data else nil
	local last = hitAt
	if data then
		for _, list in { data.bolts, data.waves } do
			if type(list) == "table" then
				for _, entry in list do
					if type(entry) == "table" and type(entry.at) == "number" then
						last = math.max(last, entry.at)
					end
				end
			end
		end
	end
	return last
end

-- Tempest Seraph's own actions (phase 7B): wings = pose.broom, side puffs =
-- pose.hands, her lightning bolts = pose.glow. Exaggerated diva acting.
local function tempestPose(pose: BossRig.Pose, action: any, t: number, since: number, hitAt: number, attack: { [string]: any }?)
	if action == "Zap" then
		local last = lastStrike(attack, hitAt)
		if t < hitAt then
			-- Takes aim like a diva: wings up, sparks building, smug grin.
			local k = math.clamp(since / 1, 0, 1)
			pose.mood = "smug"
			pose.broom = 0.7 * k
			pose.lean = 0.12 * k
			pose.glow = 0.4 + 0.8 * k
			pose.mouth = 0.25
			pose.hands = math.sin(t * 10) * 0.4
		elseif t < last + 0.45 then
			-- ZAP! Wings swoop down, bolts blazing.
			pose.broom = -1
			pose.lean = 0.2
			pose.squash = 0.86
			pose.mouth = 0.9
			pose.glow = 1.6
		end
	elseif action == "Twirl" then
		if t < hitAt then
			-- Spins faster and faster, flapping: "wheeee!"
			pose.spin = since * since * 4
			pose.broom = math.sin(t * 16)
			pose.mouth = 0.6
			pose.glow = 0.5
		elseif t < hitAt + 0.8 then
			pose.spin = since * 8
			pose.broom = 1
			pose.mouth = 0.8
			pose.squash = 1.08
		end
	elseif action == "Blow" then
		local data = if attack and type(attack.data) == "table" then attack.data else nil
		local endAt = if data and type(data.endAt) == "number" then data.endAt else hitAt + 1.5
		if t < hitAt then
			-- A HUGE breath in: she puffs up and leans back.
			local k = math.clamp(since / 1.2, 0, 1)
			pose.squash = 1 + 0.28 * k
			pose.lean = -0.2 * k
			pose.mouth = 0.1
			pose.broom = 0.4 * k
			pose.hands = 1.2 * k
		elseif t < endAt then
			-- ...and blows it all out, deflating as the wind crosses.
			local k = math.clamp((t - hitAt) / 1.2, 0, 1)
			pose.squash = 1.25 - 0.35 * k
			pose.lean = 0.25
			pose.mouth = 1
			pose.broom = -0.6 + math.sin(t * 12) * 0.2
		end
	elseif action == "Charge" then
		if t < hitAt then
			-- Charging up: wings high, buzzing, bolts flickering brighter.
			pose.broom = 1
			pose.glow = 0.8 + math.sin(t * 25) * 0.4 + math.min(since, 1.4) * 0.4
			pose.squash = 1.05 + math.sin(t * 40) * 0.03
			pose.mouth = 0.3
		elseif t < hitAt + 0.5 then
			pose.broom = -1
			pose.glow = 1.8
			pose.squash = 0.85
			pose.mouth = 1
		end
	elseif action == "Storm" then
		local last = lastStrike(attack, hitAt)
		if t < last + 0.4 then
			-- Full storm face: big flaps, roaring, lightning everywhere.
			pose.mood = "furious"
			pose.broom = math.sin(t * 14)
			pose.glow = 1.2 + math.sin(t * 30) * 0.3
			pose.mouth = 0.8 + math.sin(t * 9) * 0.2
			pose.squash = 1.12 + math.sin(t * 36) * 0.03
		end
	end
end

local function poseFor(anchor: BasePart, t: number): BossRig.Pose
	local pose = if rigModel then rigModel.defaultPose() else BossRig.defaultPose("grumpy")
	local forge = rigBoss == "Forgeheart"
	local tempest = rigBoss == "TempestSeraph"
	local action = attr(anchor, "Action")
	local actionAt = attr(anchor, "ActionAt")
	local mood = attr(anchor, "Mood")
	pose.mood = if type(mood) == "string" then mood else "grumpy"
	local since = if type(actionAt) == "number" then t - actionAt else 99
	local character = localPlayer.Character
	local head = character and character:FindFirstChild("Head")
	pose.lookAt = if head and head:IsA("BasePart") then head.Position else nil
	pose.squash = 1 + math.sin(t * 3) * 0.04
	local attack = lastAttack
	local hitAt = if attack and type(attack.hitAt) == "number" then attack.hitAt else t
	if action == "Sleep" then
		pose.eyesClosed = true
		pose.mood = "sleepy"
		pose.squash = 1 + math.sin(t * 1.3) * 0.06
	elseif action == "Intro" then
		if since < 0.9 then
			pose.squash = 1.3
		elseif since < 1.5 then
			pose.squash = 0.65 + (since - 0.9) / 0.6 * 0.35
		elseif since < 3 then
			pose.mouth = 1
			pose.mood = "angry"
			pose.squash = 1.05 + math.sin(t * 30) * 0.03
			pose.broom = 0.8
		end
	elseif action == "Sweep" then
		if t < hitAt then
			pose.squash = 0.85
			pose.lean = -0.22
			pose.broom = 1
			pose.mouth = 0.3
		elseif t < hitAt + 0.5 then
			pose.spin = (t - hitAt) / 0.5 * math.pi * 2
			pose.broom = -1
			pose.squash = 1.1
			pose.mouth = 0.8
		end
	elseif action == "Splat" then
		if t < hitAt then
			pose.squash = 1 + math.clamp(since / 1.2, 0, 1) * 0.3
			pose.mouth = 0.5
		elseif t < hitAt + 0.5 then
			pose.squash = 0.62 + (t - hitAt) / 0.5 * 0.38
		end
	elseif action == "Throw" then
		local launchAt = if attack and attack.data and type(attack.data.launchAt) == "number" then attack.data.launchAt else hitAt
		if t < launchAt then
			pose.lean = -0.3
			pose.broom = 0.9
		elseif t < launchAt + 0.4 then
			pose.lean = 0.25
			pose.broom = -0.7
			pose.mouth = 0.6
		end
	elseif action == "Hop" then
		local data = if attack and type(attack.data) == "table" then attack.data else nil
		local startAt = if data and type(data.startAt) == "number" then data.startAt else hitAt
		if t < startAt then
			pose.squash = 0.7
		elseif t < hitAt then
			pose.squash = 1.35
			pose.mouth = 0.7
			pose.hands = 2
		elseif t < hitAt + 0.45 then
			pose.squash = 0.6 + (t - hitAt) / 0.45 * 0.4
		end
	elseif action == "Spin" then
		if t < hitAt then
			pose.spin = since * since * 3
			pose.broom = -1
			pose.mouth = 0.4
		end
	elseif action == "Dizzy" then
		pose.dizzy = true
		pose.mood = "dizzy"
		pose.lean = math.sin(t * 5) * 0.12
		pose.squash = 0.92 + math.sin(t * 4) * 0.05
	elseif action == "PhaseChange" then
		if since < 1 then
			pose.mood = "shocked"
			pose.mouth = 1
			pose.squash = 1.15 + math.sin(t * 40) * 0.05
		else
			pose.squash = 1 + math.sin(t * 8) * 0.06
			pose.broom = 0.6
		end
	elseif action == "Defeated" and forge then
		-- Phase 7A: pressure builds, a cartoon explosion, then he deflates
		-- like a sad balloon and fades away.
		if since < 1 then
			pose.mood = "shocked"
			pose.squash = 1.15 + math.sin(t * 40) * 0.05
			pose.glow = 1.5
			pose.mouth = 1
		else
			pose.dizzy = true
			pose.mood = "dizzy"
			pose.deflate = math.clamp((since - 1) / 2.4, 0, 1)
			pose.squash = 1 - pose.deflate * 0.3
			pose.lean = math.sin(t * 7) * 0.1 * (1 - pose.deflate)
			pose.fade = math.clamp((since - 4.2) / 1.2, 0, 1)
		end
	elseif action == "Defeated" and tempest then
		-- Phase 7B: a last crackle, then she pops into a sad little drizzle
		-- (puffs pop, she shrinks) and fades away.
		if since < 1 then
			pose.mood = "shocked"
			pose.squash = 1.15 + math.sin(t * 40) * 0.05
			pose.glow = 1.6 + math.sin(t * 50) * 0.3
			pose.mouth = 1
		else
			pose.dizzy = true
			pose.mood = "dizzy"
			pose.deflate = math.clamp((since - 1) / 1.6, 0, 1)
			pose.squash = 1 - pose.deflate * 0.25
			pose.lean = math.sin(t * 5) * 0.1
			pose.fade = math.clamp((since - 4.2) / 1.2, 0, 1)
		end
	elseif action == "Defeated" then
		if since < 2.6 then
			pose.dizzy = true
			pose.mood = "dizzy"
			pose.lean = math.sin(t * 6) * 0.18
		else
			-- Runs away sulking (and fades out).
			pose.mood = "grumpy"
			pose.spin = math.pi
			pose.squash = 1 + math.abs(math.sin(t * 14)) * 0.15
			pose.fade = math.clamp((since - 4.2) / 1.2, 0, 1)
		end
	elseif action == "Gloat" then
		pose.mood = "smug"
		pose.mouth = 0.6 + math.sin(t * 16) * 0.3
		pose.squash = 1 + math.abs(math.sin(t * 9)) * 0.12
		pose.broom = 0.5 + math.sin(t * 6) * 0.4
	elseif forge then
		forgeheartPose(pose, action, t, since, hitAt, attack)
	elseif tempest then
		tempestPose(pose, action, t, since, hitAt, attack)
	end
	if wobble > 0 then
		pose.squash *= 1 - math.sin(wobble * math.pi) * 0.12
	end
	-- Body tint: yellow while an attack is prepared, red at the danger moment.
	if attack and type(attack.telegraphAt) == "number" and t >= attack.telegraphAt and t < hitAt then
		local color, danger = zoneColor(t, hitAt)
		pose.tint = color
		pose.tintAlpha = if danger then 0.55 else 0.25 + math.sin(t * 12) * 0.1
	end
	pose.flash = hitFlash
	if os.clock() - hopLand < 0.35 then
		pose.squash = math.min(pose.squash, 0.7)
	end
	return pose
end

local function stopAmbience()
	for _, sound in ambience do
		sound:Destroy()
	end
	table.clear(ambience)
end

local function destroyRig()
	if rig and rigModel then
		rigModel.destroy(rig)
	end
	stopAmbience()
	rig = nil
	rigModel = nil
	rigBoss = ""
	lastAction = nil
	rigAnchor = nil
	rigPosition = nil
	if zzz then
		zzz:Destroy()
		zzz = nil
	end
	if dizzyStars then
		dizzyStars:Destroy()
		dizzyStars = nil
	end
	lastAttack = nil
	clearVisuals()
end

local function ensureRig(anchor: BasePart)
	if rig and rigAnchor == anchor then
		return
	end
	destroyRig()
	local bossId = anchor:GetAttribute("BossId")
	rigBoss = if type(bossId) == "string" then bossId else "VoidWarden"
	local model = BossModels.get(rigBoss)
	rigModel = model
	local newRig = model.build(1, folder)
	rig = newRig
	-- The forge crackles (only with verified ambience ids; silent otherwise).
	if rigBoss == "Forgeheart" then
		for _, key in { "FHLavaAmbience", "FHLavaAmbience2" } do
			local loop = Audio.playLoop(key, anchor)
			if loop then
				loop.RollOffMaxDistance = 220
				table.insert(ambience, loop)
			end
		end
	end
	rigAnchor = anchor
	rigPosition = anchor.Position
	local body = newRig.byName.Body.part
	zzz = Create("BillboardGui", {
		Name = "Zzz",
		Size = UDim2.fromOffset(120, 60),
		StudsOffsetWorldSpace = Vector3.new(4, 10, 0),
		AlwaysOnTop = false,
		LightInfluence = 0,
		Adornee = body,
		Enabled = false,
		Parent = folder,
	})
	local text = Style.text({ Text = "Z z z", TextSize = 34, FontFace = Style.Fonts.Display, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = Color3.fromRGB(206, 160, 255), Parent = zzz })
	Style.ink(text, 3)
	dizzyStars = Create("BillboardGui", {
		Name = "DizzyStars",
		Size = UDim2.fromOffset(160, 60),
		StudsOffsetWorldSpace = Vector3.new(0, 11, 0),
		AlwaysOnTop = false,
		LightInfluence = 0,
		Adornee = body,
		Enabled = false,
		Parent = folder,
	})
	local stars = Style.text({ Name = "Stars", Text = "★  ★  ★", TextSize = 34, FontFace = Style.Fonts.Display, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = Color3.fromRGB(255, 220, 70), Parent = dizzyStars })
	Style.ink(stars, 3)
	-- "!" speech bubble with the attack icon: yellow while he prepares, red
	-- when it is about to hit (always on top: readable from anywhere).
	bubble = Create("BillboardGui", {
		Name = "AttackBubble",
		Size = UDim2.fromOffset(150, 96),
		StudsOffsetWorldSpace = Vector3.new(0, 15, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		Adornee = body,
		Enabled = false,
		Parent = folder,
	})
	local frame: Frame = Create("Frame", { Name = "Bubble", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WARN, Parent = bubble })
	Style.corner(frame, UDim.new(0, 26))
	Style.stroke(frame, INK, 0, 4)
	bubbleFrame = frame
	local mark = Style.text({ Name = "Mark", Size = UDim2.new(0.45, 0, 1, 0), Text = "!", TextSize = 70, FontFace = Style.Fonts.Burst, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = Color3.new(1, 1, 1), Parent = frame })
	Style.ink(mark, 4)
	bubbleLabel = mark
	local icon = Style.text({ Name = "Icon", Size = UDim2.new(0.55, 0, 1, 0), Position = UDim2.fromScale(0.45, 0), Text = "", TextSize = 52, FontFace = Style.Fonts.Display, TextXAlignment = Enum.TextXAlignment.Center, Parent = frame })
	bubbleIcon = icon
end

-- Tests / debug: the bubble state.
function BossFX.bubbleState(): (boolean, string, Color3?)
	if not bubble or not bubbleIcon or not bubbleFrame then
		return false, "", nil
	end
	return bubble.Enabled, bubbleIcon.Text, bubbleFrame.BackgroundColor3
end

local function stepRig(dt: number)
	local anchor = Boss.anchor()
	if not anchor then
		if rig then
			destroyRig()
		end
		return
	end
	ensureRig(anchor)
	local current = rig :: BossRig.Rig
	local t = now()
	local target = anchor.Position
	local position = rigPosition or target
	local motion = if lastAttack and type(lastAttack.motion) == "table" then lastAttack.motion else nil
	if motion and type(motion.startAt) == "number" and t >= motion.startAt and t <= motion.endAt + 0.05 then
		-- Exactly the server's arc (same formula, same server clock): the
		-- body lands when the damage lands.
		local k = math.clamp((t - motion.startAt) / math.max(0.05, motion.endAt - motion.startAt), 0, 1)
		position = (motion.from :: Vector3):Lerp(motion.to :: Vector3, k) + Vector3.new(0, motion.height * 4 * k * (1 - k), 0)
	else
		-- Smooth the server's 20 Hz moves.
		position = position:Lerp(target, math.clamp(dt * 24, 0, 1))
	end
	rigPosition = position
	wobble = math.max(0, wobble - dt * 4)
	hitFlash = math.max(0, hitFlash - dt * 6)
	-- "!" bubble during the telegraph.
	local attack = lastAttack
	if bubble and bubbleFrame and bubbleIcon and bubbleLabel then
		local showing = attack ~= nil and type(attack.hitAt) == "number" and t >= (attack.telegraphAt or 0) and t < attack.hitAt + 0.15
		bubble.Enabled = showing
		if showing and attack then
			local color, danger = zoneColor(t, attack.hitAt)
			bubbleFrame.BackgroundColor3 = color
			bubbleIcon.Text = Emoji.get(ATTACK_ICONS[attack.attack] or "boom")
			bubbleLabel.Rotation = if danger then math.sin(t * 40) * 12 else math.sin(t * 8) * 6
		end
	end
	local pose = poseFor(anchor, t)
	local root = CFrame.new(position) * anchor.CFrame.Rotation
	-- One sound per new action (appearance, hop, dizzy, defeat, phase...).
	local action = anchor:GetAttribute("Action")
	if type(action) == "string" and action ~= lastAction then
		lastAction = action
		local sounds = ACTION_SOUNDS[rigBoss]
		local key = sounds and sounds[action]
		if key then
			Audio.playAt(key, position)
		end
	end
	if anchor:GetAttribute("Action") == "Defeated" and rigBoss ~= "Forgeheart" and rigBoss ~= "TempestSeraph" then
		local since = t - ((anchor:GetAttribute("ActionAt") :: number?) or t)
		if since > 2.6 then
			-- Hop away toward the door.
			local run = math.min(since - 2.6, 3) * 14
			root = root * CFrame.new(0, math.abs(math.sin(since * 9)) * 2, run)
		end
	end
	if rigModel then
		rigModel.pose(current, root, pose, dt)
	end
	if zzz then
		zzz.Enabled = anchor:GetAttribute("Action") == "Sleep"
	end
	if dizzyStars then
		dizzyStars.Enabled = pose.dizzy
		local label = dizzyStars:FindFirstChild("Stars")
		if label and label:IsA("TextLabel") then
			label.Rotation = math.sin(t * 6) * 15
		end
	end
end

local function stepVisuals(dt: number)
	local t = now()
	for i = #visuals, 1, -1 do
		local visual = visuals[i]
		local keep = t <= visual.untilTime
		if keep and visual.update then
			local ok, result = pcall(visual.update, t, dt)
			keep = ok and result ~= false
		end
		if not keep then
			for _, instance in visual.instances do
				instance:Destroy()
			end
			table.remove(visuals, i)
		end
	end
end

----------------------------------------------------------------------------
-- Portal board
----------------------------------------------------------------------------

local portalBoard: BillboardGui? = nil
local portalTitle: TextLabel? = nil
local portalTimer: TextLabel? = nil
local portalNext: TextLabel? = nil
local portalPanel: Frame? = nil
local membraneOpen: boolean? = nil

local function buildPortalBoard()
	local plateau = Boss.plateau()
	local prompt = plateau and plateau:FindFirstChild("PortalPrompt")
	if not prompt or not prompt:IsA("BasePart") then
		return
	end
	local gui: BillboardGui = Create("BillboardGui", {
		Name = "PortalBoard",
		Size = UDim2.fromOffset(300, 138),
		StudsOffsetWorldSpace = Vector3.new(0, 34, 0),
		MaxDistance = 260,
		LightInfluence = 0,
		AlwaysOnTop = false,
		Adornee = prompt,
		Parent = folder,
	})
	local panel = Style.panel({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(150, 96, 240), Parent = gui })
	Style.gloss(panel)
	local title = Style.text({ Name = "Title", Size = UDim2.new(1, -16, 0, 44), Position = UDim2.fromOffset(8, 8), TextSize = 30, FontFace = Style.Fonts.Display, TextXAlignment = Enum.TextXAlignment.Center, Parent = panel })
	Style.ink(title, 3)
	local timer = Style.text({ Name = "Timer", Size = UDim2.new(1, -16, 0, 40), Position = UDim2.fromOffset(8, 56), TextSize = 26, FontFace = Style.Fonts.Display, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = Color3.fromRGB(255, 226, 90), Parent = panel })
	Style.ink(timer, 2.5)
	local nextLabel = Style.text({ Name = "Next", Size = UDim2.new(1, -16, 0, 26), Position = UDim2.fromOffset(8, 100), TextSize = 20, FontFace = Style.Fonts.Display, TextXAlignment = Enum.TextXAlignment.Center, Parent = panel })
	Style.ink(nextLabel, 2)
	portalBoard, portalTitle, portalTimer, portalNext, portalPanel = gui, title, timer, nextLabel, panel
end

-- Board colour per boss (the Void Warden's purple by default).
local BOARD_COLORS: { [string]: Color3 } = {
	Forgeheart = Color3.fromRGB(196, 84, 44),
	TempestSeraph = Color3.fromRGB(70, 120, 210),
}

local function refreshPortal()
	if not portalBoard then
		buildPortalBoard()
	end
	local view = Boss.portal()
	local t = now()
	if portalTitle and portalTimer then
		portalTitle.Text = Emoji.get("trophy") .. " " .. Locale.t("boss." .. Boss.portalBoss().id .. ".name")
		if view.state == "Open" then
			portalTimer.Text = Locale.t("boss.portal.open") .. "  " .. Format.clock(math.max(0, view.closesAt - t))
		elseif view.state == "Fight" then
			portalTimer.Text = Locale.t("boss.inProgress", { count = view.count })
		else
			portalTimer.Text = Locale.t("boss.opensIn", { time = Format.clock(math.max(0, view.opensAt - t)) })
		end
		-- Rotation preview: the boss after this one.
		local after = Boss.portalNextBoss()
		if portalNext then
			portalNext.Text = if after then Locale.t(if view.state == "Dormant" then "boss.after" else "boss.next", { boss = Locale.t("boss." .. after.id .. ".name") }) else ""
		end
		local def = Boss.portalBoss()
		if portalPanel then
			portalPanel.BackgroundColor3 = BOARD_COLORS[def.id] or Color3.fromRGB(150, 96, 240)
		end
	end
	-- The dormant membrane wakes up (brighter, pinker) while it is open.
	local isOpen = view.state == "Open"
	if membraneOpen ~= isOpen then
		membraneOpen = isOpen
		local plateau = Boss.plateau()
		local membrane = plateau and plateau:FindFirstChild("Membrane")
		if membrane and membrane:IsA("BasePart") then
			Tween.play(membrane, 0.8, {
				Color = if isOpen then Color3.fromRGB(255, 140, 230) else Color3.fromRGB(150, 70, 200),
				Transparency = if isOpen then 0.15 else 0.35,
			})
		end
		if isOpen then
			local prompt = plateau and plateau:FindFirstChild("PortalPrompt")
			if prompt and prompt:IsA("BasePart") then
				burst(prompt.Position + Vector3.new(0, 14, 0), Color3.fromRGB(255, 140, 230), 26)
			end
		end
	end
end

----------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------

function BossFX.struck(payload: { [string]: any })
	local anchor = Boss.anchor()
	if not anchor then
		return
	end
	wobble = 1
	hitFlash = if payload.finisher then 1 else 0.6
	local dizzy = payload.dizzy == true
	local finisher = payload.finisher == true
	local text = if finisher then "KAPOW!" else POWS[math.random(1, #POWS)]
	local color = if dizzy then Color3.fromRGB(255, 120, 220) elseif finisher then Color3.fromRGB(255, 150, 60) else Color3.fromRGB(255, 226, 70)
	shout(nil, anchor.Position + Vector3.new(math.random(-5, 5), 6, math.random(-3, 3)), if dizzy then text .. " x1.5" else text, color, if finisher then 46 elseif dizzy then 40 else 34, 0.7)
	burst(anchor.Position + Vector3.new(0, 4, -6), Color3.fromRGB(255, 230, 120), if finisher then 12 elseif dizzy then 9 else 6)
	Audio.playAt(if finisher then "PunchFinisher" elseif rigBoss == "Forgeheart" then "PunchHitRock" elseif rigBoss == "TempestSeraph" then "TSPunchHit" else "PunchHit", anchor.Position, { volume = 0.9 })
	if payload.weapon == "squeaky_mallet" then
		Audio.playAt("Squeak", anchor.Position)
	end
	if finisher then
		CameraFX.shake(0.25)
	end
	CameraFX.punch(if finisher then 4 else 2)
end

-- Feedback shouts above a fighter ("DODGED!", "BLOCK!", "+1 heart"...).
local function overPlayer(userId: any, text: string, color: Color3, size: number?, sound: string?)
	local player = Players:GetPlayerByUserId(tonumber(userId) or 0)
	local character = player and player.Character
	local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	if head then
		shout(head, nil, text, color, size or 28, 1)
	end
	if sound and player == localPlayer then
		Audio.play(sound)
	end
end

function BossFX.dodge(payload: { [string]: any })
	overPlayer(payload.userId, Locale.t("boss.dodge." .. tostring(payload.kind)), Color3.fromRGB(120, 255, 170), 28, "Dodge")
end

function BossFX.block(payload: { [string]: any })
	overPlayer(payload.userId, Locale.t("boss.block"), Color3.fromRGB(120, 210, 255), 30, "Block")
end

function BossFX.heal(payload: { [string]: any })
	overPlayer(payload.userId, Locale.t("boss.heal"), Color3.fromRGB(255, 130, 180), 28, "Recovered")
end

function BossFX.buff(payload: { [string]: any })
	overPlayer(payload.userId, Emoji.get("star") .. " " .. Locale.t("boss.buff"), Color3.fromRGB(255, 226, 90), 28, "Fuse")
end

-- An ability reached the boss: he resists the control, takes the hit.
function BossFX.ability(payload: { [string]: any })
	local anchor = Boss.anchor()
	if not anchor then
		return
	end
	local ability = tostring(payload.ability)
	local key = "boss.ability." .. ability
	local text = if Locale.has(key) then Locale.t(key) else "BOING!"
	shout(nil, anchor.Position + Vector3.new(0, 10, 0), text, Color3.fromRGB(150, 220, 255), 34, 1)
	if (tonumber(payload.amount) or 0) > 0 then
		wobble = 1
		hitFlash = 1
	end
	if payload.resist then
		shout(nil, anchor.Position + Vector3.new(0, 15, 0), Locale.t("boss.resist"), Color3.fromRGB(206, 160, 255), 22, 1.2)
	end
end

-- Visual of a swing from `character` (local or another fighter).
local function swingFrom(character: Model?, weaponId: string?)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local anchor = Boss.anchor()
	if weaponId == "bubble_blaster" and anchor then
		-- A soap bubble flies to the boss.
		local from = root.Position + Vector3.new(0, 1.5, 0)
		local to = anchor.Position
		local bubblePart = newPart({ Name = "Bubble", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.4, CFrame = CFrame.new(from), Color = Color3.fromRGB(190, 240, 255), Material = Enum.Material.Glass, Transparency = 0.35 })
		Tween.play(bubblePart, 0.22, { CFrame = CFrame.new(to) }, Enum.EasingStyle.Linear)
		task.delay(0.24, function()
			bubblePart:Destroy()
		end)
	elseif weaponId == "star_wand" and anchor then
		burst(root.Position:Lerp(anchor.Position, 0.5) + Vector3.new(0, 2, 0), Color3.fromRGB(255, 226, 90), 5)
	end
	local swoosh = newPart({
		Name = "Swoosh",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, 6, 6),
		CFrame = root.CFrame * CFrame.new(0, 0.5, -3) * CFrame.Angles(0, math.pi / 2, 0),
		Color = Color3.new(1, 1, 1),
		Material = Enum.Material.Neon,
		Transparency = 0.35,
	})
	Tween.play(swoosh, 0.18, { Size = Vector3.new(0.05, 9, 9), Transparency = 1 }, Enum.EasingStyle.Quad)
	task.delay(0.25, function()
		swoosh:Destroy()
	end)
end

function BossFX.otherSwing(player: Player, def: any, _payload: { [string]: any })
	swingFrom(player.Character, def.id)
end

function BossFX.swing()
	swingFrom(localPlayer.Character, Boss.weapon().id)
end

function BossFX.hit(payload: { [string]: any })
	local userId = payload.userId
	if type(userId) ~= "number" then
		return
	end
	CharacterFX.hit(userId)
	local player = Players:GetPlayerByUserId(userId)
	local character = player and player.Character
	local head = character and character:FindFirstChild("Head")
	if head then
		shout(head, nil, "BONK!", Color3.fromRGB(255, 160, 80), 30, 0.8)
	end
	if userId == localPlayer.UserId then
		CameraFX.shake(0.3)
		Audio.play("HeartLost")
	end
end

function BossFX.ko(payload: { [string]: any })
	local player = Players:GetPlayerByUserId(payload.userId or 0)
	local character = player and player.Character
	local head = character and character:FindFirstChild("Head")
	if head then
		shout(head, nil, Emoji.get("dizzy") .. " " .. Boss.text(if rigBoss ~= "" then rigBoss else nil, "ko"), Color3.fromRGB(206, 160, 255), 28, 1.3)
	end
end

-- Phase 7B: rain falling under the defeated Tempest Seraph for `duration`
-- seconds (a few looping drops, parts only).
local function drizzle(origin: Vector3, from: number, duration: number)
	local count = if Settings.quality == "Low" then 6 else 14
	local drops: { BasePart } = {}
	local instances: { Instance } = {}
	for i = 1, count do
		local drop = newPart({ Name = "Raindrop", Size = Vector3.new(0.25, 0.9, 0.25), Color = Color3.fromRGB(140, 200, 255), Material = Enum.Material.Neon, Transparency = 1 })
		drops[i] = drop
		instances[i] = drop
	end
	local fall = 0.7
	local top = origin.Y - 2
	local bottom = floorY() + 0.5
	addVisual("drizzle", from + duration, instances, function(t: number)
		for i, drop in drops do
			local phase = (((t - from) + i * fall / count) % fall) / fall
			local a = i * 2.4
			local r = 1 + (i % 4) * 1.1
			drop.CFrame = CFrame.new(origin.X + math.cos(a) * r, top + (bottom - top) * phase, origin.Z + math.sin(a) * r)
			drop.Transparency = 0.15 + phase * 0.5
		end
		return true
	end)
end

function BossFX.ended(payload: { [string]: any })
	clearVisuals()
	local anchor = Boss.anchor()
	if payload.result == "Victory" and anchor and rigBoss == "TempestSeraph" then
		-- A last crackle, then POP: rain-drop burst and a little drizzle while
		-- she deflates (pose "Defeated").
		local origin = anchor.Position
		task.delay(1, function()
			if Boss.anchor() == anchor then
				CameraFX.shake(0.3)
				for i = 0, 4 do
					burst(origin + Vector3.new(math.cos(i * 1.3) * 5, 1 + i * 0.6, math.sin(i * 1.3) * 5), if i % 2 == 0 then Color3.fromRGB(150, 210, 255) else Color3.new(1, 1, 1), 14)
				end
				drizzle(origin, now(), 2.8)
			end
		end)
	elseif payload.result == "Victory" and anchor and rigBoss == "Forgeheart" then
		-- The cartoon explosion before he deflates (pose "Defeated").
		task.delay(1, function()
			if Boss.anchor() == anchor then
				CameraFX.shake(0.5)
				for i = 0, 5 do
					burst(anchor.Position + Vector3.new(math.cos(i) * 6, 4 + i, math.sin(i) * 6), if i % 2 == 0 then Color3.fromRGB(255, 150, 60) else Color3.fromRGB(255, 220, 90), 16)
				end
			end
		end)
	elseif payload.result == "Victory" and anchor then
		task.delay(2.6, function()
			if Boss.anchor() == anchor then
				-- Confetti poof as he runs off.
				local colors = { Color3.fromRGB(255, 111, 190), Color3.fromRGB(255, 210, 63), Color3.fromRGB(90, 232, 255), Color3.fromRGB(120, 230, 110) }
				for i, color in colors do
					burst(anchor.Position + Vector3.new(math.cos(i * 1.6) * 5, 4 + i, math.sin(i * 1.6) * 5), color, 14)
				end
			end
		end)
	end
end

-- Tests / debug.
function BossFX.debugState(): { rig: boolean, visuals: number, parts: number, board: boolean }
	local parts = 0
	if folder then
		for _, d in folder:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
			end
		end
	end
	local kinds = 0
	for _ in visuals do
		kinds += 1
	end
	return { rig = rig ~= nil, visuals = kinds, parts = parts, board = portalBoard ~= nil }
end

function BossFX.rig(): BossRig.Rig?
	return rig
end

-- Tests / debug: which boss body is built ("" = none) and its ambience loops.
function BossFX.debugBoss(): (string, number)
	return rigBoss, #ambience
end

function BossFX.init()
	folder = Instance.new("Folder")
	folder.Name = "ClientBoss"
	folder.Parent = workspace
	local portalTimerClock = 0
	RunService.Heartbeat:Connect(function(dt: number)
		stepRig(dt)
		stepVisuals(dt)
		portalTimerClock += dt
		if portalTimerClock >= 0.25 then
			portalTimerClock = 0
			refreshPortal()
		end
	end)
	Boss.struck:Connect(BossFX.struck)
	Boss.swung:Connect(function(weapon: any)
		swingFrom(localPlayer.Character, if weapon then weapon.id else nil)
		Audio.play("PunchSwing")
	end)
	Boss.otherSwung:Connect(BossFX.otherSwing)
end

return BossFX
