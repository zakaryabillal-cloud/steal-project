--!strict
-- Tempest Seraph's attack drawings and sounds (V2 phase 7B), client only.
-- Built by BossFX with its drawing kit, so every telegraph follows the same
-- readability rules as the other bosses (docs/ART_DIRECTION.md §11): YELLOW
-- while she prepares, flashing RED Combat.DangerLead before the server
-- applies the damage, parts only (visible on Low quality), one warning sound
-- per attack, impact in the attack's own colour. Every drawing uses the SAME
-- formulas as the server shapes (Config/Bosses pathPosition / sweepFront /
-- sweepSide), so what is drawn is exactly what hurts:
--   targeted_bolt      a reticle follows its fighter's character until the
--                      lock, then sits where the server froze it (the
--                      "BossLock" FX position, read through the kit, is the
--                      authority) and the bolt strikes there;
--   dancing_tornadoes  dotted paths with arrow heads from the warning; the
--                      cartoon tornadoes pop up at the impact time and dance
--                      along them (red footprint = hurts now, a dot turns red
--                      just before a tornado reaches it);
--   sky_gust           the danger strips fill in the wind's direction from a
--                      yellow front on the start edge, green CALM lanes, then
--                      a red wind wall crosses the arena (gaps at the lanes);
--   chain_lightning    yellow nodes + arcs (the exact capsules) -> red -> ZAP;
--   mega_storm         the whole floor yellow -> red except the lit shelters
--                      (green discs, beacons, SHELTER label, HUD arrow), then
--                      lightning everywhere else.
-- Every telegraph fill is named "Disc" whatever its shape (like the other
-- bosses' fills). The sky arena's floor tiles and cloud shelters stand up to
-- 0.34 stud above the floor, so these drawings lie a bit higher than the
-- shared kit's discs.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Bosses = require(Shared.Config.Bosses)
local Locale = require(Shared.Locale)

local TempestSeraphFX = {}

-- BossFX's drawing kit (ForgeheartFX.Kit + the phase 7B helpers).
export type Kit = {
	now: () -> number,
	floorY: () -> number,
	newPart: ({ [string]: any }) -> Part,
	disc: (Vector3, number, Color3, number, number?) -> Part,
	setDisc: (BasePart, number) -> (),
	ring: (Vector3, number, number, Color3, number?) -> any,
	setRing: (any, number, Color3?) -> (),
	discTelegraph: (Vector3, number, number, number, (() -> ())?) -> (),
	zoneColor: (number, number) -> (Color3, boolean),
	dangerTick: () -> (),
	burst: (Vector3, Color3, number) -> (),
	addVisual: (string, number, { Instance }, ((number, number) -> boolean)?) -> (),
	addWave: (Vector3, number, number, number) -> (),
	setSafeZone: ({ [string]: any }) -> (),
	clearSafeZone: (number) -> (),
	safeLabel: (BasePart, string, Color3) -> Instance,
	playAt: (string, Vector3, { [string]: any }?) -> (),
	play: (string) -> (),
	shake: (number) -> (),
	shakeAt: (Vector3, number, number) -> (),
	colors: { [string]: Color3 },
	-- Phase 7B: a Neon bar from a to b (width across, thickness up: a flat
	-- strip on the floor by default) and moving it; the server's frozen
	-- position of a bolt reticle ("BossLock" FX, nil before it arrives); a
	-- world shout ("LOCKED!", "ZAP!"); Low quality (fewer decorative parts).
	segment: (Vector3, Vector3, number, Color3, number, number?) -> Part,
	setSegment: (BasePart, Vector3, Vector3, number?) -> (),
	lockPosition: (string) -> Vector3?,
	shout: (Vector3, string, Color3, number, number) -> (),
	lowQuality: () -> boolean,
}

local BOLT = Color3.fromRGB(255, 240, 120)
local CLOUD = Color3.fromRGB(246, 246, 255)
local CLOUD_SKY = Color3.fromRGB(196, 226, 255)
local SPARK = Color3.fromRGB(215, 242, 255)
local WHITE = Color3.new(1, 1, 1)
local LOCK_TEXT = Color3.fromRGB(255, 120, 140)

-- One colour per attack (after the impact).
local COLORS: { [string]: Color3 } = {
	targeted_bolt = Color3.fromRGB(255, 232, 80),
	dancing_tornadoes = Color3.fromRGB(150, 210, 255),
	sky_gust = Color3.fromRGB(140, 240, 230),
	chain_lightning = Color3.fromRGB(120, 200, 255),
	mega_storm = Color3.fromRGB(186, 150, 255),
}
TempestSeraphFX.Colors = COLORS

-- One distinct warning sound and one bubble icon per attack.
local WARN: { [string]: string } = {
	targeted_bolt = "TSWarnBolt",
	dancing_tornadoes = "TSTornado",
	sky_gust = "TSWarnGust",
	chain_lightning = "TSChainCharge",
	mega_storm = "TSStormAlarm",
}
TempestSeraphFX.WarnSounds = WARN
local ICONS: { [string]: string } = {
	targeted_bolt = "goal",
	dancing_tornadoes = "swirl",
	sky_gust = "wind",
	chain_lightning = "link",
	mega_storm = "power",
}
TempestSeraphFX.Icons = ICONS

-- Sounds played when the boss changes action (attribute "Action").
local ACTIONS: { [string]: string } = {
	Intro = "TSAppear",
	Dizzy = "TSDizzy",
	Defeated = "TSDefeat",
	PhaseChange = "BossPhaseUp",
}
TempestSeraphFX.ActionSounds = ACTIONS

-- Bolt reticles drawn right now (tests / debug): key -> where it is drawn.
type Reticle = { part: Part, position: Vector3, locked: boolean, track: number? }
local reticles: { [string]: Reticle } = {}

function TempestSeraphFX.debugReticles(): { [string]: { position: Vector3, locked: boolean, track: number? } }
	local out = {}
	for key, entry in reticles do
		if entry.part.Parent ~= nil then
			out[key] = { position = entry.position, locked = entry.locked, track = entry.track }
		end
	end
	return out
end

-- Floor point under a fighter's character, kept inside the arena (same
-- clamp as the server's tracked circle). nil = not followed (no fighter).
local function followed(userId: number?): Vector3?
	if not userId then
		return nil
	end
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return nil
	end
	-- A knocked-out fighter is not followed any more (server rule).
	local hearts = player:GetAttribute("BossHearts")
	if type(hearts) == "number" and hearts <= 0 then
		return nil
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local c = Bosses.Arena.Center
	local offset = Vector3.new(root.Position.X - c.X, 0, root.Position.Z - c.Z)
	if offset.Magnitude > Bosses.Arena.Radius then
		offset = offset.Unit * Bosses.Arena.Radius
	end
	return Vector3.new(c.X + offset.X, c.Y, c.Z + offset.Z)
end

-- Lateral slice of a sweep: [lo, hi] along the side vector, `half` = half
-- of the arena chord through it (the slice covers the arena floor).
type Slice = { lo: number, hi: number, half: number }

local function slicesOf(lo: number, hi: number, radius: number, step: number): { Slice }
	local out: { Slice } = {}
	local n = math.max(1, math.ceil((hi - lo) / step - 1e-6))
	for i = 0, n - 1 do
		local a = lo + (hi - lo) * i / n
		local b = lo + (hi - lo) * (i + 1) / n
		local m = if a <= 0 and b >= 0 then 0 else math.min(math.abs(a), math.abs(b))
		table.insert(out, { lo = a, hi = b, half = math.sqrt(math.max(0, radius * radius - m * m)) })
	end
	return out
end

function TempestSeraphFX.drawers(kit: Kit): { [string]: ({ [string]: any }, number) -> () }
	local WARN_COLOR = kit.colors.Warn
	local DANGER = kit.colors.Danger
	local SAFE = kit.colors.Safe
	local INK = kit.colors.Ink
	local LEAD = Bosses.Combat.DangerLead
	local UP = Vector3.new(0, 1, 0)

	-- Height of the drawings: just above the sky arena's tiles and shelters.
	local function base(): number
		return kit.floorY() + 0.3
	end

	-- A disc lying on the floor at height `y`.
	local function lying(p: Vector3, y: number): CFrame
		return CFrame.new(p.X, y, p.Z) * CFrame.Angles(0, 0, math.pi / 2)
	end

	local function blinkRed(t: number): Color3
		return if math.floor(t * 12) % 2 == 0 then DANGER else DANGER:Lerp(WHITE, 0.35)
	end

	-- The kit's disc telegraph at the sky arena's height: ink outline + edge
	-- ring + a yellow fill growing until the danger moment, then flashing
	-- red until `hitAt`, then `onImpact`.
	local function discWarning(center: Vector3, radius: number, telegraphAt: number, hitAt: number, onImpact: (() -> ())?)
		local y = base()
		local outline = kit.disc(center, radius + 0.7, INK, 0.1, y - 0.02)
		local back = kit.disc(center, radius, WARN_COLOR, 0.55, y)
		local fill = kit.disc(center, 0.1, WARN_COLOR, 0.15, y + 0.02)
		local edge = kit.ring(center, radius + 0.2, 0.8, WARN_COLOR, y + 0.3)
		kit.setRing(edge, radius + 0.2)
		local warned = false
		-- Generous window (slow devices skip frames); gone right at the impact.
		kit.addVisual("disc", hitAt + 0.3, { outline, back, fill, edge.holder }, function(t: number)
			if t >= hitAt then
				if onImpact then
					onImpact()
				end
				return false
			end
			local k = math.clamp((t - telegraphAt) / math.max(0.05, hitAt - LEAD - telegraphAt), 0, 1)
			kit.setDisc(fill, radius * k)
			local color, danger = kit.zoneColor(t, hitAt)
			fill.Color = color
			back.Color = color
			kit.setRing(edge, radius + 0.2, color)
			if danger and not warned then
				warned = true
				kit.dangerTick()
			end
			return true
		end)
	end

	-- Cartoon zig-zag lightning from the sky down to `target` (parts only),
	-- flickering, gone after `life` seconds.
	local function lightning(target: Vector3, height: number, color: Color3, life: number)
		local steps = if kit.lowQuality() then 3 else 5
		local ground = Vector3.new(target.X, base(), target.Z)
		local top = ground + Vector3.new(0, height, 0)
		local points: { Vector3 } = {}
		for i = 0, steps do
			local p = top:Lerp(ground, i / steps)
			if i > 0 and i < steps then
				p += Vector3.new((math.random() * 2 - 1) * 2.2, 0, (math.random() * 2 - 1) * 2.2)
			end
			table.insert(points, p)
		end
		local bolts: { BasePart } = {}
		local instances: { Instance } = {}
		for i = 2, #points do
			local piece = kit.segment(points[i - 1], points[i], 0.8, color, 0, 0.8)
			piece.Name = "Lightning"
			table.insert(bolts, piece)
			table.insert(instances, piece)
		end
		local flash = kit.disc(ground, 1, WHITE, 0.2, ground.Y + 0.06)
		flash.Name = "Flash"
		table.insert(instances, flash)
		local born = kit.now()
		kit.addVisual("lightning", born + life, instances, function(t: number)
			local k = math.clamp((t - born) / life, 0, 1)
			local flicker = if math.floor(t * 30) % 2 == 0 then 0 else 0.3
			for _, piece in bolts do
				piece.Transparency = math.min(1, flicker + k * 0.8)
			end
			kit.setDisc(flash, 1 + 6 * k)
			flash.Transparency = 0.2 + 0.8 * k
			return true
		end)
	end

	--------------------------------------------------------------------------
	-- "Éclair ciblé": reticles follow, lock, strike.
	--------------------------------------------------------------------------

	local function strike(position: Vector3)
		local ground = Vector3.new(position.X, base(), position.Z)
		lightning(ground, 46, BOLT, 0.35)
		kit.burst(ground + Vector3.new(0, 1, 0), COLORS.targeted_bolt, 10)
		kit.shakeAt(ground, 0.3, 50)
		kit.playAt("TSBoltStrike", ground)
	end

	local function targetedBolt(data: { [string]: any }, telegraphAt: number)
		local radius = data.radius :: number
		local hitAt = data.hitAt :: number
		-- Every reticle gets the full warning: the phase 3 second volley
		-- shows up 0.5 s after the first one (on the same fighters).
		local warning = hitAt - telegraphAt
		for key, entry in reticles do
			if entry.part.Parent == nil then
				reticles[key] = nil
			end
		end
		local localPlayer = Players.LocalPlayer
		local y = base()
		for _, bolt in data.bolts :: { { [string]: any } } do
			local key = tostring(bolt.key)
			local at = bolt.at :: number
			local lockAt = bolt.lockAt :: number
			local track: number? = if type(bolt.track) == "number" then bolt.track else nil
			local startAt = math.max(telegraphAt, at - warning)
			local position = bolt.center :: Vector3
			local outline = kit.disc(position, radius + 0.7, INK, 1, y - 0.02)
			outline.Name = "ReticleOutline"
			local back = kit.disc(position, radius, WARN_COLOR, 1, y)
			local fill = kit.disc(position, 0.1, WARN_COLOR, 1, y + 0.02)
			local edge = kit.ring(position, radius + 0.2, 0.8, WARN_COLOR, y + 0.3)
			kit.setRing(edge, radius + 0.2)
			-- A thin light column from the sky: you see where it aims from afar.
			local aim = kit.newPart({ Name = "AimBeam", Shape = Enum.PartType.Cylinder, Size = Vector3.new(36, 0.5, 0.5), Color = WARN_COLOR, Material = Enum.Material.Neon, Transparency = 1 })
			local instances: { Instance } = { outline, back, fill, edge.holder, aim }
			local ticks: { BasePart } = {}
			for _ = 1, 4 do
				local tick = kit.newPart({ Name = "ReticleTick", Size = Vector3.new(0.7, 0.2, 2.4), Color = INK, Transparency = 1 })
				table.insert(ticks, tick)
				table.insert(instances, tick)
			end
			local entry: Reticle = { part = back, position = position, locked = false, track = track }
			reticles[key] = entry
			local locked, warned = false, false
			local angle = 0
			-- Generous window (slow devices skip frames); gone right at the strike.
			kit.addVisual("reticle", at + 0.3, instances, function(t: number, dt: number)
				local shown = t >= startAt
				for _, beam in edge.beams do
					beam.Enabled = shown
				end
				if not shown then
					return true
				end
				-- Where it is: the server's lock wins; before the lock it
				-- follows its fighter; after it, it never moves again (our last
				-- sample until the server's position arrives).
				local server = kit.lockPosition(key)
				if server then
					position = server
				elseif t < lockAt then
					position = followed(track) or position
				end
				if (server or t >= lockAt) and not locked then
					locked = true
					kit.playAt("TSBoltLock", position)
					if track == nil or track == localPlayer.UserId then
						kit.shout(Vector3.new(position.X, y + 3, position.Z), Locale.t("boss.TempestSeraph.lock"), LOCK_TEXT, 26, 0.7)
					end
				end
				entry.position = position
				entry.locked = locked
				local k = math.clamp((t - startAt) / math.max(0.05, at - LEAD - startAt), 0, 1)
				local color, danger = kit.zoneColor(t, at)
				outline.CFrame = lying(position, y - 0.02)
				outline.Transparency = 0.1
				back.CFrame = lying(position, y)
				back.Color = color
				back.Transparency = 0.55
				fill.CFrame = lying(position, y + 0.02)
				kit.setDisc(fill, radius * k)
				fill.Color = color
				fill.Transparency = 0.15
				edge.holder.CFrame = CFrame.new(position.X, y + 0.3, position.Z)
				kit.setRing(edge, radius + 0.2 + (if locked then 0 else math.sin(t * 18) * 0.35), color)
				-- Crosshair: spins while it follows, stops and closes in once locked.
				if not locked then
					angle += dt * 4
				end
				for i, tick in ticks do
					local a = angle + (i - 1) * math.pi / 2
					local out = Vector3.new(math.cos(a), 0, math.sin(a))
					local p = Vector3.new(position.X, y + 0.1, position.Z) + out * (if locked then radius * 0.45 else radius * 0.8)
					tick.CFrame = CFrame.lookAt(p, p + out)
					tick.Transparency = 0
				end
				aim.CFrame = CFrame.new(position.X, y + 18, position.Z) * CFrame.Angles(0, 0, math.pi / 2)
				aim.Color = color
				aim.Transparency = if locked then 0.25 else 0.6
				if danger and not warned then
					warned = true
					kit.dangerTick()
				end
				if t >= at then
					strike(position)
					return false
				end
				return true
			end)
		end
	end

	--------------------------------------------------------------------------
	-- "Tornades dansantes": drawn paths, then the dance.
	--------------------------------------------------------------------------

	local function dancingTornadoes(data: { [string]: any }, telegraphAt: number)
		local radius = data.radius :: number
		local height = (data.height :: number?) or 18
		local low = kit.lowQuality()
		local spacing = if low then 5 else 3.5
		local y = base()
		for index, tornado in data.tornadoes :: { { points: { Vector3 }, startAt: number, endAt: number } } do
			local points = tornado.points
			local startAt, endAt = tornado.startAt, tornado.endAt
			local total = Bosses.pathLength(points)
			-- Arc length -> the moment the tornado gets there (constant speed,
			-- like Config/Bosses.pathPosition).
			local function reach(s: number): number
				return if total > 0 then startAt + (endAt - startAt) * s / total else startAt
			end
			-- Where it pops up: the usual disc warning.
			discWarning(points[1], radius, telegraphAt, startAt, function()
				kit.burst(points[1] + Vector3.new(0, 2, 0), CLOUD, 10)
				if index == 1 then
					kit.playAt("TSTornado", points[1])
				end
			end)
			local instances: { Instance } = {}
			type Mark = { part: Part, s: number }
			local marks: { Mark } = {}
			-- The dotted path...
			local s = spacing
			while s < total do
				local dot = kit.disc(Bosses.pathPosition(points, 0, total, s), 0.6, WARN_COLOR, 0.15, y + 0.04)
				dot.Name = "PathDot"
				table.insert(marks, { part = dot, s = s })
				table.insert(instances, dot)
				s += spacing
			end
			-- ...and an arrow head at the end of every leg (where it turns).
			local walked = 0
			for i = 2, #points do
				local a, b = points[i - 1], points[i]
				walked += (b - a).Magnitude
				local leg = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
				if leg.Magnitude > 1 then
					local dir = leg.Unit
					local side = Bosses.sweepSide(dir)
					local tip = Vector3.new(b.X, y + 0.08, b.Z)
					for _, sign in { -1, 1 } do
						local head = kit.segment(tip - dir * 1.8 + side * (1.5 * sign), tip, 0.55, WARN_COLOR, 0.1, 0.14)
						head.Name = "PathArrow"
						table.insert(marks, { part = head, s = walked })
						table.insert(instances, head)
					end
				end
			end
			-- The tornado: stacked cloud rings (as tall as the danger: no
			-- jumping over it), goofy eyes, and its red footprint on the floor.
			local layers = 5
			local rings: { BasePart } = {}
			for i = 1, layers do
				local k = (i - 1) / (layers - 1)
				local ringRadius = 1.4 + (radius - 1.4) * k
				local ringPart = kit.newPart({
					Name = "Tornado",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(height / layers + 0.4, ringRadius * 2, ringRadius * 2),
					Color = if i % 2 == 1 then CLOUD else CLOUD_SKY,
					Transparency = 1,
				})
				table.insert(rings, ringPart)
				table.insert(instances, ringPart)
			end
			local eyes: { BasePart } = {}
			if not low then
				for _, name in { "EyeL", "EyeR", "PupilL", "PupilR" } do
					local isPupil = string.sub(name, 1, 5) == "Pupil"
					local eye = kit.newPart({
						Name = "Tornado" .. name,
						Shape = Enum.PartType.Ball,
						Size = Vector3.one * (if isPupil then 0.6 else 1.3),
						Color = if isPupil then INK else WHITE,
						Transparency = 1,
					})
					table.insert(eyes, eye)
					table.insert(instances, eye)
				end
			end
			local foot = kit.disc(points[1], radius, DANGER, 1, y + 0.06)
			table.insert(instances, foot)
			local gone = false
			local facing = Vector3.new(0, 0, -1)
			kit.addVisual("tornado", endAt + 0.15, instances, function(t: number)
				-- Path marks: yellow while coming, red just before the tornado
				-- gets there, gone once it has passed.
				for _, mark in marks do
					local passAt = reach(mark.s)
					if t >= passAt then
						mark.part.Transparency = 1
					else
						mark.part.Color = (kit.zoneColor(t, passAt))
						mark.part.Transparency = 0.15
					end
				end
				if t < startAt then
					return true
				end
				if t >= endAt then
					if not gone then
						gone = true
						for _, part in rings do
							part.Transparency = 1
						end
						for _, eye in eyes do
							eye.Transparency = 1
						end
						foot.Transparency = 1
						kit.burst(points[#points] + Vector3.new(0, 2, 0), CLOUD, 8)
					end
					return true
				end
				local position = Bosses.pathPosition(points, startAt, endAt, t)
				local ahead = Bosses.pathPosition(points, startAt, endAt, t + 0.1)
				local move = Vector3.new(ahead.X - position.X, 0, ahead.Z - position.Z)
				if move.Magnitude > 0.05 then
					facing = move.Unit
				end
				foot.CFrame = lying(position, y + 0.06)
				foot.Color = blinkRed(t)
				foot.Transparency = 0.3
				local eyeAt: Vector3? = nil
				local eyeRadius = 0
				for i, part in rings do
					local k = (i - 1) / (#rings - 1)
					local sway = Vector3.new(math.sin(t * 6 + i), 0, math.cos(t * 5 + i)) * (0.7 * k)
					local p = Vector3.new(position.X + sway.X, y + (i - 0.5) * height / #rings, position.Z + sway.Z)
					part.CFrame = CFrame.new(p) * CFrame.Angles(0, t * 9 + i, math.pi / 2)
					part.Transparency = 0.2
					if i == #rings - 1 then
						eyeAt = p
						eyeRadius = part.Size.Y / 2
					end
				end
				if eyeAt and #eyes == 4 then
					local side = Bosses.sweepSide(facing)
					for n, eye in eyes do
						local sign = if n % 2 == 1 then -1 else 1
						local depth = if n > 2 then eyeRadius + 0.45 else eyeRadius
						eye.CFrame = CFrame.new(eyeAt + facing * depth + side * (0.9 * sign) + Vector3.new(0, 0.4, 0))
						eye.Transparency = 0
					end
				end
				return true
			end)
		end
	end

	--------------------------------------------------------------------------
	-- "Rafale céleste": a wind front crosses; only the calm lanes are safe.
	--------------------------------------------------------------------------

	local function skyGust(data: { [string]: any }, telegraphAt: number)
		local center = data.center :: Vector3
		local dir = data.dir :: Vector3
		local side = (data.side :: Vector3?) or Bosses.sweepSide(dir)
		local start = data.start :: number
		local speed = data.speed :: number
		local band = data.band :: number
		local lanes = data.lanes :: { Bosses.Lane }
		local radius = data.radius :: number
		local hitAt = data.hitAt :: number
		local endAt = data.endAt :: number
		local y = base()
		local low = kit.lowQuality()
		-- Floor point `lateral` studs along the side vector and `along` studs
		-- along the wind direction from the centre.
		local function at(lateral: number, along: number, lift: number): Vector3
			return Vector3.new(center.X, y + lift, center.Z) + side * lateral + dir * along
		end
		local function frame(lateral: number, along: number, lift: number): CFrame
			-- X = side (width), Y = up, Z = the wind direction (length).
			return CFrame.fromMatrix(at(lateral, along, lift), side, UP)
		end
		-- Lateral intervals: the calm lanes (sorted) and the danger between.
		local calm: { { number } } = {}
		for _, lane in lanes do
			local lo, hi = math.max(-radius, lane.offset - lane.width / 2), math.min(radius, lane.offset + lane.width / 2)
			if hi > lo then
				table.insert(calm, { lo, hi })
			end
		end
		table.sort(calm, function(a, b)
			return a[1] < b[1]
		end)
		local danger: { { number } } = {}
		local cursor = -radius
		for _, interval in calm do
			if interval[1] > cursor then
				table.insert(danger, { cursor, interval[1] })
			end
			cursor = math.max(cursor, interval[2])
		end
		if cursor < radius then
			table.insert(danger, { cursor, radius })
		end
		local instances: { Instance } = {}
		-- Danger slices: a fill (yellow -> red) and the wind front.
		type Strip = { slice: Slice, fill: Part, wall: Part }
		local strips: { Strip } = {}
		for _, interval in danger do
			for _, slice in slicesOf(interval[1], interval[2], radius, 6) do
				local width = slice.hi - slice.lo
				local fill = kit.newPart({ Name = "Disc", Size = Vector3.new(width, 0.1, 0.1), Color = WARN_COLOR, Material = Enum.Material.Neon, Transparency = 1 })
				local wall = kit.newPart({ Name = "WindWall", Size = Vector3.new(width, 1.2, 0.8), Color = WARN_COLOR, Material = Enum.Material.Neon, Transparency = 1 })
				table.insert(strips, { slice = slice, fill = fill, wall = wall })
				table.insert(instances, fill)
				table.insert(instances, wall)
			end
		end
		-- Calm lanes: green strips across the whole arena + a CALM tag.
		local greens: { BasePart } = {}
		for _, interval in calm do
			for _, slice in slicesOf(interval[1], interval[2], radius, 7) do
				local mid = (slice.lo + slice.hi) / 2
				local lane = kit.newPart({
					Name = "CalmLane",
					Size = Vector3.new(slice.hi - slice.lo, 0.1, math.max(0.1, slice.half * 2)),
					CFrame = frame(mid, 0, 0.02),
					Color = SAFE,
					Material = Enum.Material.Neon,
					Transparency = 0.45,
				})
				table.insert(greens, lane)
				table.insert(instances, lane)
			end
			local tag = kit.newPart({ Name = "CalmTag", Size = Vector3.one * 0.2, Transparency = 1, CFrame = CFrame.new(at((interval[1] + interval[2]) / 2, 0, 0)) })
			table.insert(instances, tag)
			local label = kit.safeLabel(tag, Locale.t("boss.TempestSeraph.calm"), SAFE);
			(label :: any).StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
			table.insert(instances, label)
		end
		-- Arrows on the danger strips: the way the wind will blow.
		type Arrow = { parts: { Part }, along: number }
		local arrows: { Arrow } = {}
		for _, interval in danger do
			if interval[2] - interval[1] >= 5 then
				local lateral = (interval[1] + interval[2]) / 2
				local tail, tip = at(lateral, -4, 0.1), at(lateral, 3, 0.1)
				local parts = { kit.segment(tail, tip, 1.1, WARN_COLOR, 0.05, 0.14) }
				for _, sign in { -1, 1 } do
					table.insert(parts, kit.segment(tip - dir * 2.6 + side * (2.2 * sign), tip, 0.9, WARN_COLOR, 0.05, 0.14))
				end
				for _, part in parts do
					part.Name = "GustArrow"
					table.insert(instances, part)
				end
				table.insert(arrows, { parts = parts, along = -4 })
			end
		end
		local fired, warned = false, false
		kit.addVisual("gust", endAt + 0.1, instances, function(t: number)
			local color, isDanger = kit.zoneColor(t, hitAt)
			local front = Bosses.sweepFront(start, speed, hitAt, t)
			-- Fighters behind this line have been resolved by the server.
			local passed = if t >= hitAt then front + band / 2 else -math.huge
			local k = math.clamp((t - telegraphAt) / math.max(0.05, hitAt - LEAD - telegraphAt), 0, 1)
			for _, strip in strips do
				local slice = strip.slice
				local mid = (slice.lo + slice.hi) / 2
				local width = slice.hi - slice.lo
				-- Fill: grows from the start edge in the wind direction, then only
				-- what the wind has not reached yet stays drawn.
				local from, to
				if t < hitAt then
					from, to = -slice.half, -slice.half + 2 * slice.half * k
				else
					from, to = math.max(-slice.half, passed), slice.half
				end
				if to - from > 0.05 then
					strip.fill.Size = Vector3.new(width, 0.1, to - from)
					strip.fill.CFrame = frame(mid, (from + to) / 2, 0)
					strip.fill.Color = color
					strip.fill.Transparency = 0.4
				else
					strip.fill.Transparency = 1
				end
				-- Front: a low yellow line on the start edge, then a tall red
				-- wind wall `band` thick moving exactly like the server's front.
				local wall = strip.wall
				if t < hitAt then
					wall.Size = Vector3.new(width, 1.2, 0.8)
					wall.CFrame = frame(mid, -slice.half, 0.6)
					wall.Color = color
					wall.Transparency = 0.1
				elseif front <= slice.half + band / 2 then
					wall.Size = Vector3.new(width, 10, band)
					wall.CFrame = frame(mid, math.max(front, -slice.half), 5)
					wall.Color = blinkRed(t)
					wall.Transparency = if low then 0.35 else 0.45
				else
					wall.Transparency = 1
				end
			end
			for _, lane in greens do
				lane.Transparency = 0.4 + math.sin(t * 8) * 0.1
			end
			for _, arrow in arrows do
				local gone = passed >= arrow.along
				for _, part in arrow.parts do
					part.Color = color
					part.Transparency = if gone then 1 else 0.05
				end
			end
			if isDanger and not warned then
				warned = true
				kit.dangerTick()
			end
			if t >= hitAt and not fired then
				fired = true
				kit.playAt("TSGust", at(0, -radius * 0.5, 3))
				kit.shout(at(0, 0, 8), Locale.t("boss.TempestSeraph.whoosh"), COLORS.sky_gust, 34, 0.9)
				kit.shake(0.2)
			end
			return true
		end)
	end

	--------------------------------------------------------------------------
	-- "Chaîne électrique": nodes and arcs zap together.
	--------------------------------------------------------------------------

	local function chainLightning(data: { [string]: any }, telegraphAt: number)
		local points = data.points :: { Vector3 }
		local radius = data.radius :: number
		local width = data.width :: number
		local hitAt = data.hitAt :: number
		local y = base()
		local low = kit.lowQuality()
		for _, node in points do
			discWarning(node, radius, telegraphAt, hitAt, function()
				kit.burst(node + Vector3.new(0, 1.5, 0), COLORS.chain_lightning, 8)
			end)
		end
		local instances: { Instance } = {}
		-- Arcs: the exact capsules (segment +- width / 2) on the floor, and a
		-- crackling zig-zag above each one.
		local fills: { BasePart } = {}
		type Leg = { a: Vector3, b: Vector3, side: Vector3, pieces: { BasePart } }
		local legs: { Leg } = {}
		for i = 2, #points do
			local a = Vector3.new(points[i - 1].X, y, points[i - 1].Z)
			local b = Vector3.new(points[i].X, y, points[i].Z)
			local outline = kit.segment(a - Vector3.new(0, 0.03, 0), b - Vector3.new(0, 0.03, 0), width + 0.8, INK, 0.1, 0.1)
			outline.Name = "ArcOutline"
			local fill = kit.segment(a + Vector3.new(0, 0.03, 0), b + Vector3.new(0, 0.03, 0), width, WARN_COLOR, 0.35, 0.12)
			fill.Name = "Disc"
			table.insert(instances, outline)
			table.insert(instances, fill)
			table.insert(fills, fill)
			local flat = b - a
			local legSide = if flat.Magnitude > 0.01 then Bosses.sweepSide(flat.Unit) else Vector3.new(1, 0, 0)
			local pieces: { BasePart } = {}
			for _ = 1, if low then 2 else 4 do
				local piece = kit.segment(a, b, 0.35, WARN_COLOR, 0, 0.35)
				piece.Name = "Arc"
				table.insert(pieces, piece)
				table.insert(instances, piece)
			end
			table.insert(legs, { a = a, b = b, side = legSide, pieces = pieces })
		end
		-- A charged orb bobbing above every node.
		local orbs: { BasePart } = {}
		for _, node in points do
			local orb = kit.newPart({ Name = "ChargeOrb", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.6, Color = WARN_COLOR, Material = Enum.Material.Neon, CFrame = CFrame.new(node.X, y + 3, node.Z) })
			table.insert(orbs, orb)
			table.insert(instances, orb)
		end
		local middle = points[math.max(1, math.ceil(#points / 2))] or Bosses.Arena.Center
		local nextJitter = 0
		local fired, warned = false, false
		kit.addVisual("chain", hitAt + 0.7, instances, function(t: number)
			local color, isDanger = kit.zoneColor(t, hitAt)
			local after = t >= hitAt
			local fade = if after then math.clamp((t - hitAt) / 0.6, 0, 1) else 0
			for _, fill in fills do
				fill.Color = if after then COLORS.chain_lightning else color
				fill.Transparency = if after then 0.2 + 0.8 * fade else 0.35
			end
			if t >= nextJitter then
				nextJitter = t + (if after then 0.04 else 0.09)
				local lift = Vector3.new(0, 1.3, 0)
				local amount = if after then 1.4 else 0.8
				for _, leg in legs do
					local n = #leg.pieces
					local previous = leg.a + lift
					for k, piece in leg.pieces do
						local nextPoint = if k == n then leg.b + lift else leg.a:Lerp(leg.b, k / n) + lift + leg.side * ((math.random() * 2 - 1) * amount)
						kit.setSegment(piece, previous, nextPoint, if after then 0.6 else 0.35)
						previous = nextPoint
					end
				end
			end
			for _, leg in legs do
				for _, piece in leg.pieces do
					piece.Color = if after then WHITE:Lerp(COLORS.chain_lightning, fade) else color
					piece.Transparency = if after then fade else (if math.random() < 0.15 then 0.6 else 0.05)
				end
			end
			for i, orb in orbs do
				local node = points[i]
				orb.CFrame = CFrame.new(node.X, y + 3 + math.sin(t * 6 + i) * 0.4, node.Z)
				orb.Color = if after then SPARK else color
				orb.Transparency = if after then fade else 0
			end
			if isDanger and not warned then
				warned = true
				kit.dangerTick()
			end
			if after and not fired then
				fired = true
				kit.playAt("TSChainZap", middle)
				kit.shout(Vector3.new(middle.X, y + 4, middle.Z), Locale.t("boss.TempestSeraph.zap"), COLORS.chain_lightning, 34, 0.8)
				kit.shakeAt(middle, 0.3, 60)
			end
			return true
		end)
	end

	--------------------------------------------------------------------------
	-- Special "MÉGA-TEMPÊTE": everything but the lit shelters is struck.
	--------------------------------------------------------------------------

	local function megaStorm(data: { [string]: any }, telegraphAt: number)
		local center = data.center :: Vector3
		local pads = data.pads :: { Vector3 }
		local padRadius = (data.padRadius :: number?) or 8
		local floorRadius = Bosses.Arena.Radius + 3
		local y = base()
		local shelterText = Locale.t("boss.TempestSeraph.shelter")
		local previous = telegraphAt
		for waveIndex, wave in data.waves :: { { at: number, safe: { number } } } do
			local startAt = previous
			local hitAt = wave.at
			previous = hitAt
			local instances: { Instance } = {}
			-- The whole floor fills yellow -> red; the lit shelters stay green
			-- on top, the dark ones get the floor's colour (never "safe-looking").
			local floorFill = kit.disc(center, 0.1, WARN_COLOR, 1, y)
			table.insert(instances, floorFill)
			local lit: { [number]: boolean } = {}
			for _, index in wave.safe do
				lit[index] = true
			end
			local spots: { Vector3 } = {}
			local greens: { BasePart } = {}
			local labels: { Instance } = {}
			type Dark = { part: Part, reachAt: number }
			local darks: { Dark } = {}
			for index, spot in pads do
				if lit[index] then
					table.insert(spots, spot)
					local safe = kit.disc(spot, padRadius, SAFE, 1, y + 0.06)
					safe.Name = "SafePadGlow"
					table.insert(instances, safe)
					table.insert(greens, safe)
					local beacon = kit.newPart({
						Name = "SafeBeacon",
						Shape = Enum.PartType.Cylinder,
						Size = Vector3.new(40, 4, 4),
						CFrame = CFrame.new(spot.X, y + 20, spot.Z) * CFrame.Angles(0, 0, math.pi / 2),
						Color = SAFE,
						Material = Enum.Material.Neon,
						Transparency = 1,
					})
					table.insert(instances, beacon)
					table.insert(greens, beacon)
					local label = kit.safeLabel(safe, shelterText, SAFE)
					table.insert(instances, label)
					table.insert(labels, label)
				else
					local dark = kit.disc(spot, padRadius, WARN_COLOR, 1, y + 0.06)
					table.insert(instances, dark)
					local distance = Vector3.new(spot.X - center.X, 0, spot.Z - center.Z).Magnitude
					-- Shown when the growing floor fill reaches it.
					table.insert(darks, { part = dark, reachAt = math.max(0, distance - padRadius) / floorRadius })
				end
			end
			-- A later wave (phase 3) shows its own shelters only once the
			-- previous strike has happened (never two sets of green at once).
			local shown, fired, warned = false, false, false
			kit.addVisual("storm", hitAt + 0.8, instances, function(t: number)
				local active = t >= startAt and t < hitAt
				if active and not shown then
					shown = true
					kit.setSafeZone({ position = spots[1] or center, radius = padRadius, untilTime = hitAt, center = center, spots = spots })
					if waveIndex > 1 then
						kit.playAt("TSStormAlarm", center)
					end
				end
				for _, green in greens do
					green.Transparency = if active then (if green.Name == "SafeBeacon" then 0.4 else 0.3) + math.sin(t * 9) * 0.1 else 1
				end
				for _, label in labels do
					(label :: any).Enabled = active
				end
				local k = math.clamp((t - startAt) / math.max(0.05, hitAt - LEAD - startAt), 0, 1)
				kit.setDisc(floorFill, floorRadius * math.max(0.05, k))
				local color, isDanger = kit.zoneColor(t, hitAt)
				local after = math.clamp(0.2 + (t - hitAt) / 0.8, 0, 1)
				if t < startAt then
					floorFill.Transparency = 1
				elseif t < hitAt then
					floorFill.Color = color
					floorFill.Transparency = 0.5
				else
					floorFill.Color = COLORS.mega_storm
					floorFill.Transparency = after
				end
				for _, dark in darks do
					if t >= hitAt then
						dark.part.Color = COLORS.mega_storm
						dark.part.Transparency = after
					else
						dark.part.Color = color
						dark.part.Transparency = if active and k >= dark.reachAt then 0.45 else 1
					end
				end
				if isDanger and not warned then
					warned = true
					kit.dangerTick()
				end
				if t >= hitAt and not fired then
					fired = true
					kit.clearSafeZone(hitAt)
					kit.shake(0.6)
					kit.playAt("TSStormBoom", center)
					-- Lightning everywhere except the lit shelters.
					local count = if kit.lowQuality() then 5 else 10
					for n = 1, count do
						local a = (n / count + waveIndex * 0.37) * math.pi * 2
						local r = 12 + (n % 4) * 12
						local p = Vector3.new(center.X + math.cos(a) * r, y, center.Z + math.sin(a) * r)
						local clear = true
						for _, spot in spots do
							if Vector3.new(p.X - spot.X, 0, p.Z - spot.Z).Magnitude < padRadius + 2 then
								clear = false
								break
							end
						end
						if clear then
							lightning(p, 50, BOLT, 0.4)
							kit.burst(p + Vector3.new(0, 1, 0), COLORS.mega_storm, 6)
						end
					end
				end
				return true
			end)
		end
	end

	return {
		targeted_bolt = targetedBolt,
		dancing_tornadoes = dancingTornadoes,
		sky_gust = skyGust,
		chain_lightning = chainLightning,
		mega_storm = megaStorm,
	}
end

return TempestSeraphFX
