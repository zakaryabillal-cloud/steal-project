--!strict
-- Animated button with hover / press / click feedback on mouse, touch and
-- gamepad. Visual only: actions are passed in via `onClick`.

local Create = require(script.Parent.Create)
local Style = require(script.Parent.Style)
local Tween = require(script.Parent.Tween)

local Button = {}

local soundHandler: ((key: string) -> ())? = nil

function Button.setSoundHandler(handler: (key: string) -> ())
	soundHandler = handler
end

local function sound(key: string)
	if soundHandler then
		soundHandler(key)
	end
end

export type Props = {
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	parent: Instance?,
	color: Color3?,
	transparency: number?,
	gradient: { Color3 }?,
	text: string?,
	textSize: number?,
	textColor: Color3?,
	font: Font?,
	corner: UDim?,
	stroke: boolean?,
	strokeColor: Color3?,
	layoutOrder: number?,
	name: string?,
	zIndex: number?,
	onClick: (() -> ())?,
	hoverScale: number?,
	silent: boolean?,
}

export type Button = {
	instance: TextButton,
	scale: UIScale,
	label: TextLabel?,
	enabled: boolean,
	setEnabled: (self: Button, enabled: boolean) -> (),
	setText: (self: Button, text: string) -> (),
	pulse: (self: Button) -> (),
}

local methods = {}
methods.__index = methods

function methods.setEnabled(self: Button, enabled: boolean)
	self.enabled = enabled
	self.instance.AutoButtonColor = false
	Tween.play(self.instance, 0.2, { BackgroundTransparency = if enabled then (self.instance:GetAttribute("BaseTransparency") :: number? or 0) else 0.55 })
	if self.label then
		Tween.play(self.label, 0.2, { TextTransparency = if enabled then 0 else 0.35 })
	end
end

function methods.setText(self: Button, text: string)
	if self.label then
		self.label.Text = text
	end
end

function methods.pulse(self: Button)
	Tween.pop(self.instance, 0.1)
end

function Button.new(props: Props): Button
	local transparency = props.transparency or 0
	local instance: TextButton = Create("TextButton", {
		Name = props.name or "Button",
		Size = props.size,
		Position = props.position or UDim2.new(),
		AnchorPoint = props.anchor or Vector2.zero,
		BackgroundColor3 = props.color or Style.Colors.PanelRaised,
		BackgroundTransparency = transparency,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = props.layoutOrder or 0,
		ZIndex = props.zIndex or 1,
		Selectable = true,
	})
	instance:SetAttribute("BaseTransparency", transparency)
	Style.corner(instance, props.corner)
	if props.stroke ~= false then
		Style.stroke(instance, props.strokeColor, if props.strokeColor then 0.4 else nil)
	end
	if props.gradient then
		local colors = props.gradient
		Style.gradient(instance, colors[1], colors[2] or colors[1], 90)
	end
	local scale: UIScale = Create("UIScale", { Parent = instance })

	local label: TextLabel? = nil
	if props.text then
		label = Style.text({
			Name = "Label",
			Text = props.text,
			TextSize = props.textSize or 18,
			TextColor3 = props.textColor or Style.Colors.Text,
			FontFace = props.font or Style.Fonts.Heavy,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = (props.zIndex or 1) + 1,
			Parent = instance,
		})
	end

	local self: Button = setmetatable({
		instance = instance,
		scale = scale,
		label = label,
		enabled = true,
	}, methods) :: any

	local hoverScale = props.hoverScale or 1.05
	local hovering = false
	local pressed = false
	local function refresh()
		local target = if pressed then 0.93 elseif hovering then hoverScale else 1
		Tween.play(scale, if pressed then 0.08 else 0.22, { Scale = target }, Enum.EasingStyle.Quint)
	end

	instance.MouseEnter:Connect(function()
		hovering = true
		refresh()
		if not props.silent and self.enabled then
			sound("UiHover")
		end
	end)
	instance.MouseLeave:Connect(function()
		hovering = false
		pressed = false
		refresh()
	end)
	instance.SelectionGained:Connect(function()
		hovering = true
		refresh()
	end)
	instance.SelectionLost:Connect(function()
		hovering = false
		refresh()
	end)
	instance.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			pressed = true
			refresh()
		end
	end)
	instance.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			pressed = false
			refresh()
		end
	end)
	instance.Activated:Connect(function()
		if not self.enabled then
			if not props.silent then
				sound("UiError")
			end
			Tween.play(instance, 0.05, { Rotation = 3 })
			task.delay(0.05, function()
				Tween.play(instance, 0.25, { Rotation = 0 }, Enum.EasingStyle.Elastic)
			end)
			return
		end
		if not props.silent then
			sound("UiClick")
		end
		if props.onClick then
			props.onClick()
		end
	end)

	if props.parent then
		instance.Parent = props.parent
	end
	return self
end

return Button
