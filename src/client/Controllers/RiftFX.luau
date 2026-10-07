--!strict
-- Brings THE RIFT to life on each client: the tear slowly turns, gimbal rings
-- and debris orbit, the core breathes. Spawns are staged as moments: the Rift
-- charges up (colour, speed, light, inflow), a light shaft marks the landing
-- spot, then a flash and shockwave release the relic. Legendary+ charges dim
-- the whole sky.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Rarities = require(Shared.Config.Rarities)
local Events = require(Shared.Config.Events)
local Layout = require(Shared.Layout)
local MathUtil = require(Shared.Util.MathUtil)

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

	task.delay(duration, function()
		targetSpeed = 1
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

	local tear = rift:FindFirstChild("TearGlow") :: BasePart?
	RunService.RenderStepped:Connect(function(dt)
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
