--!strict
-- Brings THE RIFT to life on each client: the tear slowly turns, gimbal rings
-- and debris orbit, the core breathes. Spawns are staged as moments: the Rift
-- charges up (colour, speed, light, inflow), a light shaft marks the landing
-- spot, then a flash and shockwave release the relic. Legendary+ charges dim
-- the whole sky.
-- Phase 5.5: the Rift has a goofy face. Its eyes turn toward this client's
-- camera, the pupils follow your character, it blinks, raises its brows while
-- charging and opens its mouth to "burp" the relic out (with a BURP! pop).
-- Updated inside the single existing RenderStepped loop.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Rarities = require(Shared.Config.Rarities)
local Events = require(Shared.Config.Events)
local Layout = require(Shared.Layout)
local MathUtil = require(Shared.Util.MathUtil)
local Locale = require(Shared.Locale)
local Theme = require(Shared.Config.Theme)

local Tween = require(script.Parent.Parent.UI.Kit.Tween)
local Audio = require(script.Parent.Audio)
local CameraFX = require(script.Parent.CameraFX)
local LightingFX = require(script.Parent.LightingFX)
local Settings = require(script.Parent.Settings)

local RiftFX = {}

local tearRoot: BasePart
local tearBase: CFrame
local rings: { { part: BasePart, base: CFrame, speed: number } } = {}
local debrisRoot: BasePart
local debrisBase: CFrame
local light: PointLight
local inflow: ParticleEmitter?
local glowParts: { BasePart } = {}
local fxFolder: Folder

-- Face
type Face = {
	center: Vector3,
	layout: { [string]: number },
	parts: { [string]: BasePart },
	sizes: { [string]: Vector3 },
	blinkAt: number,
	blinkUntil: number,
	excite: number,
	exciteTarget: number,
	mouth: number,
}
local face: Face? = nil
local faceClock = 0

local spinTime = 0
local speed = 1
local targetSpeed = 1
local baseColor = Layout.Colors.Rift
local inflowBaseRate = 30

local function setRiftColor(color: Color3, time: number)
	Tween.play(light, time, { Color = color }, Enum.EasingStyle.Sine)
	for _, part in glowParts do
		Tween.play(part, time, { Color = color }, Enum.EasingStyle.Sine)
	end
	if inflow then
		inflow.Color = ColorSequence.new(Color3.new(1, 1, 1):Lerp(color, 0.3), color)
	end
end

local function shockwave(center: Vector3, color: Color3, radius: number, duration: number)
	local disc = Instance.new("Part")
	disc.Shape = Enum.PartType.Cylinder
	disc.Size = Vector3.new(0.3, 4, 4)
	disc.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2)
	disc.Material = Enum.Material.Neon
	disc.Color = color
	disc.Transparency = 0.2
	disc.Anchored = true
	disc.CanCollide = false
	disc.CanQuery = false
	disc.CanTouch = false
	disc.CastShadow = false
	disc.Parent = fxFolder
	Tween.play(disc, duration, { Size = Vector3.new(0.1, radius * 2, radius * 2), Transparency = 1 }, Enum.EasingStyle.Quart)

	local sphere = Instance.new("Part")
	sphere.Shape = Enum.PartType.Ball
	sphere.Size = Vector3.one * 6
	sphere.CFrame = CFrame.new(center)
	sphere.Material = Enum.Material.ForceField
	sphere.Color = color
	sphere.Anchored = true
	sphere.CanCollide = false
	sphere.CanQuery = false
	sphere.CanTouch = false
	sphere.CastShadow = false
	sphere.Parent = fxFolder
	Tween.play(sphere, duration * 0.8, { Size = Vector3.one * radius * 1.2, Transparency = 1 }, Enum.EasingStyle.Quart)
	task.delay(duration + 0.1, function()
		disc:Destroy()
		sphere:Destroy()
	end)
end

-- Vertical light shaft telling everyone where the relic will land.
local function marker(position: Vector3, color: Color3, duration: number)
	local shaft = Instance.new("Part")
	shaft.Shape = Enum.PartType.Cylinder
	shaft.Size = Vector3.new(60, 1.2, 1.2)
	shaft.CFrame = CFrame.new(position + Vector3.new(0, 26, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	shaft.Material = Enum.Material.Neon
	shaft.Color = color
	shaft.Transparency = 1
	shaft.Anchored = true
	shaft.CanCollide = false
	shaft.CanQuery = false
	shaft.CanTouch = false
	shaft.CastShadow = false
	shaft.Parent = fxFolder
	Tween.play(shaft, duration * 0.6, { Transparency = 0.55, Size = Vector3.new(60, 3, 3) }, Enum.EasingStyle.Sine)
	task.delay(duration, function()
		Tween.play(shaft, 0.5, { Transparency = 1, Size = Vector3.new(60, 0.2, 0.2) })
		task.delay(0.6, function()
			shaft:Destroy()
		end)
	end)
end

local FACE_PARTS = { "EyeWhiteL", "EyeWhiteR", "PupilL", "PupilR", "ShineL", "ShineR", "BrowL", "BrowR", "Mouth", "Tongue" }

local function setupFace(rift: Instance)
	local eyesRoot = rift:FindFirstChild("EyesRoot")
	if not eyesRoot or not eyesRoot:IsA("BasePart") then
		return
	end
	local parts: { [string]: BasePart } = {}
	local sizes: { [string]: Vector3 } = {}
	for _, name in FACE_PARTS do
		local part = rift:FindFirstChild(name)
		if not part or not part:IsA("BasePart") then
			return
		end
		parts[name] = part
		sizes[name] = part.Size
	end
	local layout: { [string]: number } = {}
	for _, key in { "eyeOffset", "pupilDepth", "shineDepth", "browHeight", "mouthY" } do
		local value = eyesRoot:GetAttribute(key)
		layout[key] = if type(value) == "number" then value else 0
	end
	face = { center = eyesRoot.Position, layout = layout, parts = parts, sizes = sizes, blinkAt = 2, blinkUntil = 0, excite = 0, exciteTarget = 0, mouth = 0 }
end

-- "BURP!" shout over the Rift's mouth.
local function burp(position: Vector3)
	local anchor = Instance.new("Part")
	anchor.Size = Vector3.one * 0.2
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = fxFolder
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(220, 70)
	gui.LightInfluence = 0
	gui.MaxDistance = 400
	gui.Adornee = anchor
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = Locale.t("fx.burp")
	label.TextSize = 44
	-- Luckiest Guy has no accented letters (FR): Fredoka for those.
	label.FontFace = if string.find(label.Text, "[\128-\255]") then Theme.Fonts.Display else Theme.Fonts.Burst
	label.TextColor3 = Theme.Colors.Gold
	label.Rotation = -8
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.Ink
	stroke.Thickness = 4
	stroke.Parent = label
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = label
	Tween.play(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	Tween.play(anchor, 1.5, { CFrame = CFrame.new(position + Vector3.new(0, 8, 0)) }, Enum.EasingStyle.Quint)
	Tween.play(label, 0.5, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 1)
	Tween.play(stroke, 0.5, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 1)
	task.delay(1.6, function()
		anchor:Destroy()
	end)
end

local function updateFace(dt: number)
	local f = face
	local camera = workspace.CurrentCamera
	if not f or not camera then
		return
	end
	faceClock += dt
	local t = faceClock
	local cameraPos = camera.CFrame.Position
	-- Turn the whole face toward this client's camera, with a little bob and wobble.
	local center = f.center + Vector3.new(0, math.sin(t * 1.7) * 0.4, 0)
	local flat = Vector3.new(cameraPos.X, center.Y, cameraPos.Z)
	local look = if (flat - center).Magnitude > 0.1 then CFrame.lookAt(center, flat) else CFrame.new(center)
	look *= CFrame.Angles(0, 0, math.sin(t * 1.3) * 0.06)
	-- Pupils follow your character (or the camera when there is none).
	local character = Players.LocalPlayer.Character
	local head = character and character:FindFirstChild("Head")
	local target = if head and head:IsA("BasePart") then head.Position else cameraPos
	local rel = look:PointToObjectSpace(target)
	local shift = Vector3.zero
	if rel.Magnitude > 0.01 then
		local d = rel.Unit
		shift = Vector3.new(d.X, d.Y, 0) * 1.6
		if shift.Magnitude > 1.4 then
			shift = shift.Unit * 1.4
		end
	end
	-- Blinks every few seconds; excitement while the Rift charges.
	if t >= f.blinkAt then
		f.blinkUntil = t + 0.16
		f.blinkAt = t + 2.5 + (math.sin(t * 7.3) + 1) * 1.5
	end
	local blink = if t < f.blinkUntil then 1 - 0.85 * math.sin(math.pi * (f.blinkUntil - t) / 0.16) else 1
	f.excite += (f.exciteTarget - f.excite) * MathUtil.damp(6, dt)
	f.mouth = math.max(0, f.mouth - dt * 1.4)
	local widen = 1 + f.excite * 0.18
	local parts = f.parts
	local L = f.layout
	for _, x in { -1, 1 } do
		local key = if x < 0 then "L" else "R"
		local eye = look * CFrame.new(x * L.eyeOffset, 0, -1.6)
		local white = parts["EyeWhite" .. key]
		local base = f.sizes["EyeWhite" .. key]
		white.Size = Vector3.new(base.X * widen, base.Y * widen * blink, base.Z * widen)
		white.CFrame = eye
		local pupil = parts["Pupil" .. key]
		pupil.CFrame = eye * CFrame.new(shift.X, shift.Y - 0.2, -L.pupilDepth)
		pupil.Transparency = if blink < 0.5 then 1 else 0
		local shine = parts["Shine" .. key]
		shine.CFrame = eye * CFrame.new(shift.X + 0.65, shift.Y + 0.3, -L.shineDepth)
		shine.Transparency = pupil.Transparency
		parts["Brow" .. key].CFrame = eye * CFrame.new(0, L.browHeight + f.excite * 1.2, -0.6) * CFrame.Angles(0, 0, math.rad(-x * (8 - f.excite * 18)))
	end
	-- Mouth: a smile that opens wide on a burp.
	local open = f.mouth
	local mouthSize = f.sizes.Mouth
	parts.Mouth.Size = Vector3.new(mouthSize.X + open * 1.6 + f.excite * 0.6, mouthSize.Y + open * 4.2 + f.excite * 0.8, mouthSize.Z)
	parts.Mouth.CFrame = look * CFrame.new(0, L.mouthY - open * 1.2, -1.2)
	parts.Tongue.CFrame = look * CFrame.new(0, L.mouthY - 0.6 - open * 2.4, -1.45)
end

function RiftFX.charge(payload: { [string]: any })
	local rarity = Rarities.get(payload.rarity)
	local duration = tonumber(payload.duration) or rarity.chargeTime
	local position = payload.position :: Vector3
	local color = rarity.color
	local big = rarity.order >= 5

	targetSpeed = 2.5 + rarity.order * 0.6
	setRiftColor(color:Lerp(baseColor, if big then 0 else 0.5), duration * 0.6)
	Tween.play(light, duration, { Brightness = 3 + rarity.order * 0.9, Range = 60 + rarity.order * 6 }, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
	if inflow then
		inflow.Rate = inflowBaseRate * (2 + rarity.order * 0.6) * Settings.particleScale()
	end
	marker(position, color, duration)
	Audio.playAt("RiftCharge", Layout.RiftCore, { pitch = 0.75 + rarity.order * 0.07, volume = if big then 1.6 else 1 })
	if big then
		LightingFX.dim(0.12 + (rarity.order - 5) * 0.04, color, duration)
		CameraFX.shake(0.15)
	end

	if face then
		(face :: Face).exciteTarget = 1
	end

	task.delay(duration, function()
		targetSpeed = 1
		-- BURP: the mouth pops open as the relic flies out.
		local f = face
		if f then
			f.exciteTarget = 0
			f.mouth = 1
			burp(f.center + Vector3.new(0, f.layout.mouthY, 0))
		end
		setRiftColor(baseColor, 1.2)
		local event = Events.get(workspace:GetAttribute("EventId") :: string?)
		if event then
			setRiftColor(event.ambience.riftColor, 1.2)
		end
		Tween.play(light, 1, { Brightness = 2.4, Range = 60 })
		if inflow then
			inflow.Rate = inflowBaseRate * Settings.particleScale()
		end
		shockwave(Layout.RiftCore, color, if big then 140 else 22 + rarity.order * 4, if big then 1.4 else 0.7)
		if big then
			LightingFX.restore(1.6)
			LightingFX.flash(color, 0.45, 1.2)
			CameraFX.shake(0.45)
			Audio.play("RareEmerge", { pitch = 1 - (rarity.order - 5) * 0.08 })
		else
			CameraFX.shakeAt(Layout.RiftCore, 0.12, 70)
		end
	end)
end

-- Tests / debug: the face state (nil before init).
function RiftFX.face(): any
	return face
end

function RiftFX.setEvent(eventId: string?)
	local event = Events.get(eventId)
	setRiftColor(if event then event.ambience.riftColor else baseColor, 2.5)
end

function RiftFX.init()
	local rift = workspace:WaitForChild("World"):WaitForChild("Rift")
	tearRoot = rift:WaitForChild("TearRoot") :: BasePart
	tearBase = tearRoot.CFrame
	debrisRoot = rift:WaitForChild("DebrisRoot") :: BasePart
	debrisBase = debrisRoot.CFrame
	light = tearRoot:WaitForChild("RiftLight") :: PointLight
	for i = 1, 3 do
		local ring = rift:WaitForChild("Ring" .. i) :: BasePart
		table.insert(rings, { part = ring, base = ring.CFrame, speed = (0.22 + i * 0.1) * (if i % 2 == 0 then -1 else 1) })
	end
	for _, name in { "TearGlow", "TearHalo" } do
		local part = rift:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			table.insert(glowParts, part)
		end
	end
	for _, child in rift:GetChildren() do
		if child.Name == "RingNode" and child:IsA("BasePart") then
			table.insert(glowParts, child)
		end
	end
	local shell = rift:FindFirstChild("InflowShell")
	inflow = if shell then shell:FindFirstChildOfClass("ParticleEmitter") else nil
	if inflow then
		inflowBaseRate = inflow.Rate
		inflow.Rate = inflowBaseRate * Settings.particleScale()
	end
	local hum = tearRoot:FindFirstChild("Hum")
	if hum and hum:IsA("Sound") then
		Audio.loopOn("RiftHum", hum)
	end

	fxFolder = Instance.new("Folder")
	fxFolder.Name = "RiftFX"
	fxFolder.Parent = workspace

	Settings.changed:Connect(function()
		if inflow then
			inflow.Rate = inflowBaseRate * Settings.particleScale()
		end
	end)

	setupFace(rift)
	local tear = rift:FindFirstChild("TearGlow") :: BasePart?
	RunService.RenderStepped:Connect(function(dt)
		updateFace(dt)
		speed += (targetSpeed - speed) * MathUtil.damp(2.5, dt)
		spinTime += dt * speed
		tearRoot.CFrame = tearBase * CFrame.Angles(0, spinTime * 0.11, 0)
		for _, ring in rings do
			ring.part.CFrame = ring.base * CFrame.Angles(0, spinTime * ring.speed, 0)
		end
		debrisRoot.CFrame = debrisBase * CFrame.Angles(0, spinTime * 0.045, 0)
		if tear then
			tear.Transparency = 0.15 + (math.sin(spinTime * 1.6) + 1) * 0.12
		end
	end)

	local function syncEvent()
		local id = workspace:GetAttribute("EventId")
		RiftFX.setEvent(if type(id) == "string" and id ~= "" then id else nil)
	end
	workspace:GetAttributeChangedSignal("EventId"):Connect(syncEvent)
	syncEvent()
end

return RiftFX
