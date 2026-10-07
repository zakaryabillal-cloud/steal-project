--!strict
-- Ambient life around the camera: drifting fireflies / star motes. One
-- emitter follows the camera so cost stays constant anywhere on the island.

local RunService = game:GetService("RunService")
local Settings = require(script.Parent.Settings)

local WorldFX = {}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

function WorldFX.init()
	local holder = Instance.new("Part")
	holder.Name = "AmbientMotes"
	holder.Size = Vector3.new(90, 18, 90)
	holder.Transparency = 1
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Parent = workspace

	local motes = Instance.new("ParticleEmitter")
	motes.Texture = SPARKLE
	motes.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 170)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(170, 240, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 170, 255)),
	})
	motes.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 0.32),
		NumberSequenceKeypoint.new(0.7, 0.22),
		NumberSequenceKeypoint.new(1, 0),
	})
	motes.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	motes.Lifetime = NumberRange.new(4, 7)
	motes.Speed = NumberRange.new(0.3, 1)
	motes.SpreadAngle = Vector2.new(180, 180)
	motes.Acceleration = Vector3.new(0, 0.25, 0)
	motes.LightEmission = 1
	motes.LightInfluence = 0
	motes.Parent = holder

	local function refresh()
		motes.Rate = 14 * Settings.particleScale()
	end
	refresh()
	Settings.changed:Connect(refresh)

	RunService.Heartbeat:Connect(function()
		local camera = workspace.CurrentCamera
		if camera then
			holder.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, -2, 0))
		end
	end)
end

return WorldFX
