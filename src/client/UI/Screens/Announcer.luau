--!strict
-- Big centre-screen moments (rare relics, heists, ascensions). Never blocks
-- input; a newer announcement replaces the current one.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage.Shared.Config.Theme)

local Kit = script.Parent.Parent.Kit
local Create = require(Kit.Create)
local Style = require(Kit.Style)
local Tween = require(Kit.Tween)

local Announcer = {}

local root: Frame
local title: TextLabel
local subtitle: TextLabel
local gradient: UIGradient
local glow: UIStroke
local scale: UIScale
local token = 0

export type Options = {
	duration: number?,
	color: Color3?,
	secondary: Color3?,
}

function Announcer.show(mainText: string, subText: string?, options: Options?)
	token += 1
	local myToken = token
	local color = (options and options.color) or Theme.Colors.Essence
	local secondary = (options and options.secondary) or Color3.new(1, 1, 1)
	title.Text = mainText
	subtitle.Text = subText or ""
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, secondary),
		ColorSequenceKeypoint.new(0.5, color),
		ColorSequenceKeypoint.new(1, secondary),
	})
	glow.Color = color
	root.Visible = true
	title.TextTransparency = 1
	subtitle.TextTransparency = 1
	glow.Transparency = 1
	scale.Scale = 1.35
	gradient.Offset = Vector2.new(-0.6, 0)
	Tween.play(scale, 0.55, { Scale = 1 }, Enum.EasingStyle.Back)
	Tween.play(title, 0.25, { TextTransparency = 0 })
	Tween.play(glow, 0.4, { Transparency = 0.35 })
	Tween.play(subtitle, 0.35, { TextTransparency = 0 }, nil, nil, 0.15)
	Tween.play(gradient, 1.6, { Offset = Vector2.new(0.6, 0) }, Enum.EasingStyle.Sine)
	local duration = (options and options.duration) or 2.6
	task.delay(duration, function()
		if token ~= myToken then
			return
		end
		Tween.play(title, 0.4, { TextTransparency = 1 })
		Tween.play(subtitle, 0.4, { TextTransparency = 1 })
		Tween.play(glow, 0.4, { Transparency = 1 })
		Tween.play(scale, 0.4, { Scale = 0.9 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.45, function()
			if token == myToken then
				root.Visible = false
			end
		end)
	end)
end

function Announcer.init(parent: Instance)
	root = Create("Frame", {
		Name = "Announcer",
		Size = UDim2.fromOffset(900, 150),
		Position = UDim2.fromScale(0.5, 0.3),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = parent,
	})
	scale = Create("UIScale", { Parent = root })
	title = Style.text({
		Size = UDim2.new(1, 0, 0, 84),
		TextXAlignment = Enum.TextXAlignment.Center,
		FontFace = Theme.Fonts.Display,
		TextSize = 70,
		Parent = root,
	})
	gradient = Create("UIGradient", { Parent = title })
	glow = Create("UIStroke", {
		Thickness = 4,
		Transparency = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Parent = title,
	})
	subtitle = Style.text({
		Size = UDim2.new(1, 0, 0, 36),
		Position = UDim2.fromOffset(0, 86),
		TextXAlignment = Enum.TextXAlignment.Center,
		FontFace = Theme.Fonts.Heavy,
		TextSize = 26,
		Parent = root,
	})
	Style.textStroke(subtitle, 0.3, 2.5)
end

return Announcer
