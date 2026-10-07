--!strict
-- Trauma-based camera shake and field-of-view punches, applied after the
-- default camera update each frame.

local RunService = game:GetService("RunService")
local Settings = require(script.Parent.Settings)

local CameraFX = {}

local trauma = 0
local fovOffset = 0
local fovVelocity = 0
local BASE_FOV = 70
local seed = math.random() * 1000
local clock = 0

function CameraFX.shake(amount: number)
	if not Settings.shake then
		return
	end
	trauma = math.min(1, trauma + amount)
end

-- Positional shake that fades with distance from the camera.
function CameraFX.shakeAt(position: Vector3, amount: number, radius: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local distance = (camera.CFrame.Position - position).Magnitude
	local falloff = math.clamp(1 - distance / radius, 0, 1)
	if falloff > 0 then
		CameraFX.shake(amount * falloff)
	end
end

function CameraFX.punch(fov: number)
	fovVelocity += fov * 14
end

function CameraFX.init()
	RunService:BindToRenderStep("RiftCameraFX", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		clock += dt
		if trauma > 0 then
			local power = trauma * trauma
			local pitch = math.noise(clock * 18, seed) * math.rad(2.4) * power
			local yaw = math.noise(clock * 18, seed + 10) * math.rad(2.4) * power
			local roll = math.noise(clock * 18, seed + 20) * math.rad(1.6) * power
			camera.CFrame *= CFrame.Angles(pitch, yaw, roll)
			trauma = math.max(0, trauma - dt * 1.6)
		end
		if fovOffset ~= 0 or fovVelocity ~= 0 then
			-- Damped spring back to the base FOV.
			local accel = -fovOffset * 180 - fovVelocity * 18
			fovVelocity += accel * dt
			fovOffset += fovVelocity * dt
			if math.abs(fovOffset) < 0.01 and math.abs(fovVelocity) < 0.05 then
				fovOffset, fovVelocity = 0, 0
			end
			camera.FieldOfView = BASE_FOV + fovOffset
		end
	end)
end

return CameraFX
