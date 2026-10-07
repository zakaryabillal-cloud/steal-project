--!strict
-- Client-side atmosphere: blends the base night look with Rift event
-- ambiences, plays transient flashes/dims (Rift charges, heists, hits) on a
-- dedicated colour-correction layer, and runs event weather around the camera.

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Events = require(ReplicatedStorage.Shared.Config.Events)
local Tween = require(script.Parent.Parent.UI.Kit.Tween)
local Settings = require(script.Parent.Settings)

local LightingFX = {}

type Base = {
	ambient: Color3,
	outdoorAmbient: Color3,
	atmosphereColor: Color3,
	atmosphereDecay: Color3,
	atmosphereDensity: number,
	ccBrightness: number,
	ccSaturation: number,
	ccContrast: number,
	ccTint: Color3,
}

local base: Base
local atmosphere: Atmosphere?
local correction: ColorCorrectionEffect?
local fxCorrection: ColorCorrectionEffect
local weatherPart: Part
local weatherEmitter: ParticleEmitter
local currentEvent: string? = nil

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SQUARE = "rbxasset://textures/particles/SquareParticle.png"
local SPARK = "rbxasset://textures/particles/fire_sparks_main.dds"

local function capture()
	atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	correction = Lighting:FindFirstChild("ColorCorrection") :: ColorCorrectionEffect?
	base = {
		ambient = Lighting.Ambient,
		outdoorAmbient = Lighting.OutdoorAmbient,
		atmosphereColor = if atmosphere then atmosphere.Color else Color3.new(),
		atmosphereDecay = if atmosphere then atmosphere.Decay else Color3.new(),
		atmosphereDensity = if atmosphere then atmosphere.Density else 0.3,
		ccBrightness = if correction then correction.Brightness else 0,
		ccSaturation = if correction then correction.Saturation else 0,
		ccContrast = if correction then correction.Contrast else 0,
		ccTint = if correction then correction.TintColor else Color3.new(1, 1, 1),
	}
end

local WEATHER = {
	sparks = { texture = SPARKLE, color = Color3.fromRGB(150, 240, 255), speed = NumberRange.new(4, 8), rate = 60, size = 0.35, accel = Vector3.new(0, -2, 0), y = 30 },
	ash = { texture = SQUARE, color = Color3.fromRGB(110, 60, 200), speed = NumberRange.new(3, 6), rate = 70, size = 0.3, accel = Vector3.new(1, -3, 0), y = 30 },
	gold = { texture = SPARKLE, color = Color3.fromRGB(255, 214, 110), speed = NumberRange.new(2, 4), rate = 70, size = 0.4, accel = Vector3.new(0, -2, 0), y = 30 },
	embers = { texture = SPARK, color = Color3.fromRGB(255, 120, 60), speed = NumberRange.new(2, 5), rate = 55, size = 0.3, accel = Vector3.new(0, 3, 0), y = -12 },
}

local function setupWeather()
	weatherPart = Instance.new("Part")
	weatherPart.Name = "RiftWeather"
	weatherPart.Size = Vector3.new(140, 1, 140)
	weatherPart.Transparency = 1
	weatherPart.Anchored = true
	weatherPart.CanCollide = false
	weatherPart.CanQuery = false
	weatherPart.CanTouch = false
	weatherPart.Parent = workspace
	weatherEmitter = Instance.new("ParticleEmitter")
	weatherEmitter.Enabled = false
	weatherEmitter.Lifetime = NumberRange.new(5, 7)
	weatherEmitter.LightEmission = 1
	weatherEmitter.LightInfluence = 0
	weatherEmitter.RotSpeed = NumberRange.new(-90, 90)
	weatherEmitter.Rotation = NumberRange.new(0, 360)
	weatherEmitter.EmissionDirection = Enum.NormalId.Bottom
	weatherEmitter.Parent = weatherPart

	local offsetY = 30
	RunService.Heartbeat:Connect(function()
		local camera = workspace.CurrentCamera
		if camera and weatherEmitter.Enabled then
			weatherPart.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, offsetY, 0))
		end
	end)
	LightingFX.setWeatherOffset = function(y: number)
		offsetY = y
	end
end

LightingFX.setWeatherOffset = function(_y: number) end

local function setWeather(kind: string?)
	local spec = if kind then WEATHER[kind] else nil
	if not spec then
		weatherEmitter.Enabled = false
		return
	end
	weatherEmitter.Texture = spec.texture
	weatherEmitter.Color = ColorSequence.new(spec.color)
	weatherEmitter.Speed = spec.speed
	weatherEmitter.Acceleration = spec.accel
	weatherEmitter.EmissionDirection = if spec.y < 0 then Enum.NormalId.Top else Enum.NormalId.Bottom
	weatherEmitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.15, spec.size),
		NumberSequenceKeypoint.new(1, 0),
	})
	weatherEmitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	weatherEmitter.Rate = spec.rate * Settings.particleScale()
	LightingFX.setWeatherOffset(spec.y)
	weatherEmitter.Enabled = true
end

function LightingFX.setEvent(eventId: string?)
	if eventId == currentEvent then
		return
	end
	currentEvent = eventId
	local def = Events.get(eventId)
	local time = 3
	local a = if def then def.ambience else nil
	Tween.play(Lighting, time, {
		Ambient = if a then a.ambient else base.ambient,
		OutdoorAmbient = if a then a.outdoorAmbient else base.outdoorAmbient,
	}, Enum.EasingStyle.Sine)
	if atmosphere then
		Tween.play(atmosphere, time, {
			Color = if a then a.atmosphereColor else base.atmosphereColor,
			Decay = if a then a.atmosphereDecay else base.atmosphereDecay,
			Density = if a then a.atmosphereDensity else base.atmosphereDensity,
		}, Enum.EasingStyle.Sine)
	end
	if correction then
		Tween.play(correction, time, {
			Brightness = if a then a.brightness else base.ccBrightness,
			Saturation = if a then a.saturation else base.ccSaturation,
			Contrast = if a then a.contrast else base.ccContrast,
			TintColor = if a then a.tint else base.ccTint,
		}, Enum.EasingStyle.Sine)
	end
	setWeather(if a then a.weather else nil)
end

-- Short colour flash (e.g. a relic bursting out of the Rift).
function LightingFX.flash(color: Color3, strength: number, duration: number)
	fxCorrection.TintColor = Color3.new(1, 1, 1):Lerp(color, 0.5)
	fxCorrection.Brightness = strength
	Tween.play(fxCorrection, duration, { Brightness = 0, TintColor = Color3.new(1, 1, 1) }, Enum.EasingStyle.Quad)
end

-- Gradually dims and tints the world (Rift charge build-up), then restores.
function LightingFX.dim(amount: number, color: Color3, duration: number)
	Tween.play(fxCorrection, duration, {
		Brightness = -amount,
		TintColor = Color3.new(1, 1, 1):Lerp(color, 0.35),
		Saturation = -0.15,
	}, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
end

function LightingFX.restore(duration: number)
	Tween.play(fxCorrection, duration, { Brightness = 0, TintColor = Color3.new(1, 1, 1), Saturation = 0 }, Enum.EasingStyle.Sine)
end

function LightingFX.init()
	capture()
	fxCorrection = Instance.new("ColorCorrectionEffect")
	fxCorrection.Name = "RiftFX"
	fxCorrection.Parent = Lighting
	setupWeather()
	Settings.changed:Connect(function()
		if weatherEmitter.Enabled then
			local def = Events.get(currentEvent)
			local spec = if def then WEATHER[def.ambience.weather] else nil
			if spec then
				weatherEmitter.Rate = spec.rate * Settings.particleScale()
			end
		end
	end)
	local function sync()
		local id = workspace:GetAttribute("EventId")
		LightingFX.setEvent(if type(id) == "string" and id ~= "" then id else nil)
	end
	workspace:GetAttributeChangedSignal("EventId"):Connect(sync)
	sync()
end

return LightingFX
