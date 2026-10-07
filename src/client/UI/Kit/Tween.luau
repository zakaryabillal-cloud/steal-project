--!strict
local TweenService = game:GetService("TweenService")

local Tween = {}

function Tween.play(instance: Instance, time: number, props: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?, delay: number?): Tween
	local info = TweenInfo.new(time, style or Enum.EasingStyle.Quint, direction or Enum.EasingDirection.Out, 0, false, delay or 0)
	local tween = TweenService:Create(instance, info, props)
	tween:Play()
	return tween
end

function Tween.info(time: number, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): TweenInfo
	return TweenInfo.new(time, style or Enum.EasingStyle.Quint, direction or Enum.EasingDirection.Out)
end

-- Quick "pop": scale up then settle. Requires a UIScale child (created if missing).
function Tween.pop(guiObject: GuiObject, amount: number?)
	local existing = guiObject:FindFirstChildOfClass("UIScale")
	local s: UIScale
	if existing then
		s = existing
	else
		s = Instance.new("UIScale")
		s.Parent = guiObject
	end
	s.Scale = 1 + (amount or 0.12)
	Tween.play(s, 0.35, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
end

return Tween
