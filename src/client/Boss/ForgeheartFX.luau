--!strict
-- Forgeheart's attack drawings and sounds (V2 phase 7A), client only.
-- Built by BossFX with its drawing kit, so every telegraph follows the same
-- readability rules as the Void Warden's (docs/ART_DIRECTION.md §11):
-- YELLOW while he prepares, flashing RED Combat.DangerLead before the server
-- applies the damage, parts only (visible on Low quality), one warning sound
-- per attack, impact in the attack's own colour. Burning lava stays drawn
-- red-orange for exactly as long as it hurts (no invisible damage).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Bosses = require(ReplicatedStorage.Shared.Config.Bosses)

local ForgeheartFX = {}

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
}

local LAVA = Color3.fromRGB(255, 120, 40)
local LAVA_HOT = Color3.fromRGB(255, 214, 72)
local COOL = Color3.fromRGB(150, 160, 196)
local ROCK = Color3.fromRGB(176, 106, 82)

-- One colour per attack (after the impact).
local COLORS: { [string]: Color3 } = {
	volcanic_hammer = Color3.fromRGB(255, 150, 60),
	lava_blobs = Color3.fromRGB(255, 110, 40),
	burning_floor = Color3.fromRGB(255, 80, 40),
	meteor_shower = Color3.fromRGB(255, 190, 90),
	final_eruption = Color3.fromRGB(255, 90, 30),
}
ForgeheartFX.Colors = COLORS

-- One distinct warning sound and one bubble icon per attack.
local WARN: { [string]: string } = {
	volcanic_hammer = "FHHammerWindup",
	lava_blobs = "FHWarnBlobs",
	burning_floor = "FHWarnFloor",
	meteor_shower = "FHWarnMeteors",
	final_eruption = "FHEruptionAlarm",
}
ForgeheartFX.WarnSounds = WARN
local ICONS: { [string]: string } = {
	volcanic_hammer = "hammer",
	lava_blobs = "lava",
	burning_floor = "fire",
	meteor_shower = "comet",
	final_eruption = "volcano",
}
ForgeheartFX.Icons = ICONS

-- Sounds played when the boss changes action (attribute "Action").
local ACTIONS: { [string]: string } = {
	Intro = "FHAppear",
	Dizzy = "FHDizzy",
	Defeated = "FHDefeat",
	PhaseChange = "BossPhaseUp",
}
ForgeheartFX.ActionSounds = ACTIONS

function ForgeheartFX.drawers(kit: Kit): { [string]: ({ [string]: any }, number) -> () }
	local DANGER = kit.colors.Danger
	local SAFE = kit.colors.Safe

	-- Lava pool that HURTS from `fromT` to `untilT`: drawn bright orange with
	-- a flashing red crust the whole time, then it cools down (grey fade).
	local function burnPool(center: Vector3, radius: number, fromT: number, untilT: number, sound: boolean)
		local pool = kit.disc(center, radius, LAVA, 1, kit.floorY() + 0.05)
		pool.Name = "Disc"
		local crust = kit.disc(center, radius + 0.6, DANGER, 1, kit.floorY() + 0.03)
		crust.Name = "Disc"
		local nextBubble = 0
		local started = false
		kit.addVisual("burn", untilT + 0.7, { pool, crust }, function(t: number)
			if t < fromT then
				return true
			end
			if t < untilT then
				if not started then
					started = true
					if sound then
						kit.playAt("FHLavaCrackle", center)
					end
				end
				local blink = math.floor(t * 6) % 2 == 0
				pool.Color = LAVA:Lerp(LAVA_HOT, 0.3 + math.sin(t * 5) * 0.2)
				pool.Transparency = 0.08
				crust.Color = if blink then DANGER else LAVA
				crust.Transparency = 0.2
				if t >= nextBubble then
					nextBubble = t + 0.45
					local a = (t * 7) % (math.pi * 2)
					kit.burst(center + Vector3.new(math.cos(a) * radius * 0.5, 0.6, math.sin(a) * radius * 0.5), LAVA_HOT, 3)
				end
			else
				local k = math.clamp((t - untilT) / 0.6, 0, 1)
				pool.Color = LAVA:Lerp(COOL, k)
				pool.Transparency = 0.08 + 0.92 * k
				crust.Transparency = 1
			end
			return true
		end)
	end

	-- Shockwave ring (phase 3 hammer): red, white crest to jump over.
	local function shockwave(center: Vector3, startAt: number, speed: number, band: number, maxRadius: number)
		kit.addWave(center, startAt, speed, maxRadius)
		local wave = kit.ring(center, 0.1, band, DANGER, kit.floorY() + 0.3)
		local crest = kit.ring(center, 0.1, band * 0.6, Color3.new(1, 1, 1), kit.floorY() + 1.8)
		wave.holder.Parent = nil
		crest.holder.Parent = nil
		kit.addVisual("shockwave", startAt + maxRadius / speed + 0.1, { wave.holder, crest.holder }, function(t: number)
			if t < startAt then
				return true
			end
			if wave.holder.Parent == nil then
				wave.holder.Parent = workspace:FindFirstChild("ClientBoss")
				crest.holder.Parent = wave.holder.Parent
			end
			local radius = (t - startAt) * speed
			kit.setRing(wave, math.max(0.1, radius))
			kit.setRing(crest, math.max(0.1, radius))
			return radius <= maxRadius
		end)
	end

	local function volcanicHammer(data: { [string]: any }, telegraphAt: number)
		local center = data.center :: Vector3
		local radius = data.radius :: number
		local hitAt = data.hitAt :: number
		kit.discTelegraph(center, radius, telegraphAt, hitAt, function()
			kit.burst(center + Vector3.new(0, 1, 0), ForgeheartFX.Colors.volcanic_hammer, 18)
			kit.shakeAt(center, 0.55, 90)
			kit.playAt("FHHammerHit", center)
		end)
		local wave = data.wave
		if type(wave) == "table" then
			shockwave(center, wave.startAt, wave.speed, wave.band, wave.maxRadius)
		end
	end

	local function lavaBlobs(data: { [string]: any }, telegraphAt: number)
		local from = data.from :: Vector3
		local launchAt = data.launchAt :: number
		local radius = data.radius :: number
		local puddle = (data.puddle :: number?) or radius * 0.8
		local linger = (data.linger :: number?) or 2.4
		local lands = data.lands :: { number }
		local launched = false
		for i, spot in data.spots :: { Vector3 } do
			local landAt = lands[i] or launchAt + 1
			kit.discTelegraph(spot, radius, telegraphAt, landAt, function()
				kit.burst(spot + Vector3.new(0, 1, 0), ForgeheartFX.Colors.lava_blobs, 9)
				kit.playAt("FHBlobPop", spot)
			end)
			burnPool(spot, puddle, landAt + 0.4, landAt + 0.4 + linger, i == 1)
			local ball = kit.newPart({ Name = "LavaBall", Shape = Enum.PartType.Ball, Size = Vector3.one * 2.4, Color = LAVA_HOT, Material = Enum.Material.Neon, CFrame = CFrame.new(from), Transparency = 1 })
			local target = Vector3.new(spot.X, kit.floorY() + 1.2, spot.Z)
			kit.addVisual("lavaBall", landAt, { ball }, function(t: number)
				if t < launchAt then
					return true
				end
				if not launched then
					launched = true
					kit.playAt("FHBlobLaunch", from)
				end
				local k = math.clamp((t - launchAt) / math.max(0.05, landAt - launchAt), 0, 1)
				ball.Transparency = 0
				ball.CFrame = CFrame.new(from:Lerp(target, k) + Vector3.new(0, 18 * 4 * k * (1 - k), 0))
				return true
			end)
		end
	end

	local function burningFloor(data: { [string]: any }, telegraphAt: number)
		local radius = data.radius :: number
		local hitAt = data.hitAt :: number
		local untilTime = data.untilTime :: number
		for i, spot in data.spots :: { Vector3 } do
			-- Glowing cracks on the warning disc (same yellow -> red rule).
			local cracks: { Instance } = {}
			for k = 0, 2 do
				local a = k * math.pi * 2 / 3 + i
				local crack = kit.newPart({
					Name = "Crack",
					Size = Vector3.new(0.5, 0.1, radius * 1.4),
					CFrame = CFrame.new(spot.X, kit.floorY() + 0.06, spot.Z) * CFrame.Angles(0, a, 0),
					Color = kit.colors.Warn,
					Material = Enum.Material.Neon,
				})
				table.insert(cracks, crack)
			end
			kit.addVisual("cracks", hitAt, cracks, function(t: number)
				local color = kit.zoneColor(t, hitAt)
				for _, crack in cracks do
					(crack :: BasePart).Color = color
				end
				return true
			end)
			kit.discTelegraph(spot, radius, telegraphAt, hitAt, function()
				kit.burst(spot + Vector3.new(0, 1, 0), ForgeheartFX.Colors.burning_floor, 8)
			end)
			burnPool(spot, radius, hitAt, untilTime, i == 1)
		end
	end

	local function meteorShower(data: { [string]: any }, telegraphAt: number)
		local radius = data.radius :: number
		local lands = data.lands :: { number }
		for i, spot in data.spots :: { Vector3 } do
			local landAt = lands[i] or telegraphAt + 1.2
			kit.discTelegraph(spot, radius, telegraphAt, landAt, function()
				kit.burst(spot + Vector3.new(0, 1, 0), ForgeheartFX.Colors.meteor_shower, 10)
				kit.shakeAt(spot, 0.2, 60)
				kit.playAt("FHMeteorBoom", spot)
			end)
			local fallFor = 0.9
			local start = Vector3.new(spot.X + 18, kit.floorY() + 80, spot.Z - 12)
			local target = Vector3.new(spot.X, kit.floorY() + 1.5, spot.Z)
			local rock = kit.newPart({ Name = "Meteor", Shape = Enum.PartType.Ball, Size = Vector3.one * 3.2, Color = ROCK, CFrame = CFrame.new(start), Transparency = 1 })
			local core = kit.newPart({ Name = "MeteorCore", Shape = Enum.PartType.Ball, Size = Vector3.one * 2.2, Color = LAVA_HOT, Material = Enum.Material.Neon, CFrame = CFrame.new(start), Transparency = 1 })
			local whistled = false
			kit.addVisual("meteor", landAt, { rock, core }, function(t: number)
				if t < landAt - fallFor then
					return true
				end
				if not whistled then
					whistled = true
					kit.playAt("FHMeteorWhistle", spot)
				end
				local k = math.clamp((t - (landAt - fallFor)) / fallFor, 0, 1)
				local p = start:Lerp(target, k * k)
				rock.Transparency, core.Transparency = 0, 0.2
				rock.CFrame = CFrame.new(p) * CFrame.Angles(t * 5, t * 3, 0)
				core.CFrame = CFrame.new(p + Vector3.new(0.6, 0.6, -0.6))
				return true
			end)
		end
	end

	local function finalEruption(data: { [string]: any }, telegraphAt: number)
		local center = data.center :: Vector3
		local def = Bosses.get("Forgeheart") :: Bosses.BossDef
		local pads = Bosses.arenaPads(def)
		local padRadius = (data.padRadius :: number?) or def.padRadius or 8
		local floorRadius = Bosses.Arena.Radius + 3
		local previous = telegraphAt
		task.delay(math.max(0, (data.waves[1].at :: number) - 1.4 - kit.now()), function()
			kit.play("FHEruptionBuild")
		end)
		for _, wave in data.waves :: { { at: number, safe: { number } } } do
			local startAt = previous
			local hitAt = wave.at
			previous = hitAt
			local instances: { Instance } = {}
			-- The whole floor fills yellow -> red, the safe rocks stay green on top.
			local floorFill = kit.disc(center, 0.1, kit.colors.Warn, 0.5, kit.floorY() + 0.04)
			table.insert(instances, floorFill)
			local spots: { Vector3 } = {}
			local greens: { BasePart } = {}
			local labels: { Instance } = {}
			for _, index in wave.safe do
				local spot = pads[index]
				if spot then
					table.insert(spots, spot)
					local safe = kit.disc(spot, padRadius, SAFE, 1, kit.floorY() + 0.16)
					safe.Name = "SafePadGlow"
					table.insert(instances, safe)
					table.insert(greens, safe)
					local beacon = kit.newPart({
						Name = "SafeBeacon",
						Shape = Enum.PartType.Cylinder,
						Size = Vector3.new(40, 4, 4),
						CFrame = CFrame.new(spot.X, kit.floorY() + 20, spot.Z) * CFrame.Angles(0, 0, math.pi / 2),
						Color = SAFE,
						Material = Enum.Material.Neon,
						Transparency = 1,
					})
					table.insert(instances, beacon)
					table.insert(greens, beacon)
					local label = kit.safeLabel(safe, "SAFE", SAFE)
					table.insert(instances, label)
					table.insert(labels, label)
				end
			end
			-- A later wave (phase 3) shows its own safe rocks only once the
			-- previous eruption has happened (never two sets of green at once).
			local shown = false
			local fired, warned = false, false
			kit.addVisual("eruption", hitAt + 0.8, instances, function(t: number)
				local active = t >= startAt and t < hitAt
				if active and not shown then
					shown = true
					kit.setSafeZone({ position = spots[1] or center, radius = padRadius, untilTime = hitAt, center = center, spots = spots })
				end
				for _, green in greens do
					green.Transparency = if active then (if green.Name == "SafeBeacon" then 0.4 else 0.3) + math.sin(t * 9) * 0.1 else 1
				end
				for _, label in labels do
					(label :: any).Enabled = active
				end
				local k = math.clamp((t - startAt) / math.max(0.05, hitAt - Bosses.Combat.DangerLead - startAt), 0, 1)
				kit.setDisc(floorFill, floorRadius * math.max(0.05, k))
				floorFill.Transparency = if t < startAt then 1 else 0.5
				local color, danger = kit.zoneColor(t, hitAt)
				if t < hitAt then
					floorFill.Color = color
				else
					floorFill.Color = ForgeheartFX.Colors.final_eruption
					floorFill.Transparency = math.clamp(0.2 + (t - hitAt) / 0.8, 0, 1)
				end
				if danger and not warned then
					warned = true
					kit.dangerTick()
				end
				if t >= hitAt and not fired then
					fired = true
					kit.clearSafeZone(hitAt)
					kit.shake(0.6)
					kit.playAt("FHBigImpact", center)
					for n = 0, 9 do
						local a = n / 10 * math.pi * 2
						kit.burst(center + Vector3.new(math.cos(a) * 44, 1, math.sin(a) * 44), ForgeheartFX.Colors.final_eruption, 12)
					end
				end
				return true
			end)
		end
	end

	return {
		volcanic_hammer = volcanicHammer,
		lava_blobs = lavaBlobs,
		burning_floor = burningFloor,
		meteor_shower = meteorShower,
		final_eruption = finalEruption,
	}
end

return ForgeheartFX
