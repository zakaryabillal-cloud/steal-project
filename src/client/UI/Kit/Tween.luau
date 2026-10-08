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
	-- Cartoon "wiggle": a quick left-right rotation that settles elastically.
function Tween.wiggle(guiObject: GuiObject, degrees: number?)
	local d = degrees or 8
	guiObject.Rotation = d
	Tween.play(guiObject, 0.55, { Rotation = 0 }, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
end

-- Squash and stretch on a UIScale-less object: pops from `from` (default 0) to
-- full size with an overshoot.
function Tween.popIn(guiObject: GuiObject, from: number?)
	local existing = guiObject:FindFirstChildOfClass("UIScale")
	local s: UIScale
	if existing then
		s = existing
	else
		s = Instance.new("UIScale")
		s.Parent = guiObject
	end
	s.Scale = from or 0
	Tween.play(s, 0.45, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
end

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

-- Cartoon "wiggle": a quick left-right rotation that settles elastically.
function Tween.wiggle(guiObject: GuiObject, degrees: number?)
	local d = degrees or 8
	guiObject.Rotation = d
	Tween.play(guiObject, 0.55, { Rotation = 0 }, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
end

-- Squash and stretch on a UIScale-less object: pops from `from` (default 0) to
-- full size with an overshoot.
function Tween.popIn(guiObject: GuiObject, from: number?)
	local existing = guiObject:FindFirstChildOfClass("UIScale")
	local s: UIScale
	if existing then
		s = existing
	else
		s = Instance.new("UIScale")
		s.Parent = guiObject
	end
	s.Scale = from or 0
	Tween.play(s, 0.45, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
end

return Tween
