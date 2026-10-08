--!strict
-- Chunky cartoon button (Phase 5.5): a coloured face sitting on a darker
-- "lip", ink outline, glossy highlight and a rounded label with an ink stroke.
-- Hover grows it, press pushes the face down onto the lip, a refused click
-- wobbles it. Works with mouse, touch and gamepad. Visual only: actions are
-- passed in via `onClick`.
--
-- Put icons / extra content in `button.content` (the face) so they move with
-- the press animation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage.Shared.Config.Theme)

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
	-- Face colour, or a Theme.Buttons family name ("green", "pink"...).
	color: Color3?,
	kind: string?,
	-- Lip colour (defaults to the family lip, or a darker face).
	lipColor: Color3?,
	-- Lip height in px (0 = flat).
	lip: number?,
	transparency: number?,
	gradient: { Color3 }?,
	text: string?,
	textSize: number?,
	textColor: Color3?,
	font: Font?,
	corner: UDim?,
	stroke: boolean?,
	strokeColor: Color3?,
	gloss: boolean?,
	layoutOrder: number?,
	name: string?,
	zIndex: number?,
	onClick: (() -> ())?,
	hoverScale: number?,
	silent: boolean?,
}

export type Button = {
	instance: TextButton,
	-- The face: parent icons and extra labels here.
	content: Frame,
	lipFrame: Frame,
	scale: UIScale,
	label: TextLabel?,
	stroke: UIStroke,
	enabled: boolean,
	color: Color3,
	setEnabled: (self: Button, enabled: boolean) -> (),
	setText: (self: Button, text: string) -> (),
	setColor: (self: Button, face: Color3, lip: Color3?) -> (),
	setKind: (self: Button, kind: string) -> (),
	pulse: (self: Button) -> (),
}

local DISABLED = Color3.fromRGB(150, 156, 186)

local methods = {}
methods.__index = methods

local function lipOf(face: Color3): Color3
	return face:Lerp(Theme.Colors.Ink, 0.32)
end

local function paint(self: Button)
	local face = if self.enabled then self.color else self.color:Lerp(DISABLED, 0.7)
	self.content.BackgroundColor3 = face
	local lip = (self :: any).lipColor :: Color3?
	self.lipFrame.BackgroundColor3 = if self.enabled then (lip or lipOf(self.color)) else lipOf(face)
end

function methods.setEnabled(self: Button, enabled: boolean)
	self.enabled = enabled
	self.instance.AutoButtonColor = false
	paint(self)
	if self.label then
		Tween.play(self.label, 0.2, { TextTransparency = if enabled then 0 else 0.3 })
	end
end

function methods.setText(self: Button, text: string)
	if self.label then
		self.label.Text = text
	end
end

function methods.setColor(self: Button, face: Color3, lip: Color3?)
	self.color = face;
	(self :: any).lipColor = lip
	paint(self)
end

function methods.setKind(self: Button, kind: string)
	local family = Theme.Buttons[kind]
	if family then
		methods.setColor(self, family.face, family.lip)
	end
end

function methods.pulse(self: Button)
	Tween.pop(self.instance, 0.12)
end

function Button.new(props: Props): Button
	local family = if props.kind then Theme.Buttons[props.kind] else nil
	local faceColor = props.color or (family and family.face) or Theme.Buttons.neutral.face
	local lipColor = props.lipColor or (if family and props.color == nil then family.lip else nil)
	local transparency = props.transparency or 0
	local lipHeight = props.lip or Theme.Lip
	local corner = props.corner or Theme.Radius.Medium
	local z = props.zIndex or 1

	local instance: TextButton = Create("TextButton", {
		Name = props.name or "Button",
		Size = props.size,
		Position = props.position or UDim2.new(),
		AnchorPoint = props.anchor or Vector2.zero,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = props.layoutOrder or 0,
		ZIndex = z,
		Selectable = true,
	})
	instance:SetAttribute("BaseTransparency", transparency)

	-- Lip: same shape, shifted down; the face covers it except at the bottom.
	local lipFrame: Frame = Create("Frame", {
		Name = "Lip",
		Size = UDim2.new(1, 0, 1, -lipHeight),
		Position = UDim2.fromOffset(0, lipHeight),
		BackgroundColor3 = lipColor or lipOf(faceColor),
		BackgroundTransparency = transparency,
		BorderSizePixel = 0,
		ZIndex = z,
		Parent = instance,
	})
	Style.corner(lipFrame, corner)
	local content: Frame = Create("Frame", {
		Name = "Face",
		Size = UDim2.new(1, 0, 1, -lipHeight),
		BackgroundColor3 = faceColor,
		BackgroundTransparency = transparency,
		BorderSizePixel = 0,
		ZIndex = z + 1,
		Parent = instance,
	})
	Style.corner(content, corner)
	local strokeColor = props.strokeColor or Theme.Colors.Ink
	local stroke = Style.stroke(content, strokeColor, if props.stroke == false then 1 else 0, Theme.Outline.Thin + 0.5)
	if props.stroke ~= false then
		Style.stroke(lipFrame, strokeColor, 0, Theme.Outline.Thin + 0.5)
	end
	if props.gradient then
		local colors = props.gradient
		Style.gradient(content, colors[1], colors[2] or colors[1], 90)
	else
		Style.shade(content, 0.14)
	end
	if props.gloss ~= false and transparency < 0.5 then
		Style.gloss(content, z + 1)
	end
	local scale: UIScale = Create("UIScale", { Parent = instance })

	local label: TextLabel? = nil
	if props.text then
		label = Style.text({
			Name = "Label",
			Text = props.text,
			TextSize = props.textSize or 18,
			TextColor3 = props.textColor or Theme.Colors.Text,
			FontFace = props.font or Theme.Fonts.Heavy,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = z + 2,
			Parent = content,
		})
		Style.ink(label :: TextLabel, if (props.textSize or 18) >= 20 then 2.5 else 2)
	end

	local self: Button = setmetatable({
		instance = instance,
		content = content,
		lipFrame = lipFrame,
		scale = scale,
		label = label,
		stroke = stroke,
		enabled = true,
		color = faceColor,
		lipColor = lipColor,
	}, methods) :: any

	local hoverScale = props.hoverScale or 1.06
	local hovering = false
	local pressed = false
	local function refresh()
		local target = if pressed then 0.96 elseif hovering then hoverScale else 1
		Tween.play(scale, if pressed then 0.06 else 0.25, { Scale = target }, if pressed then Enum.EasingStyle.Quad else Enum.EasingStyle.Back)
		local down = if pressed then lipHeight else 0
		Tween.play(content, if pressed then 0.05 else 0.18, { Position = UDim2.fromOffset(0, down) }, Enum.EasingStyle.Quad)
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
			-- "Nope" wobble.
			Tween.play(instance, 0.05, { Rotation = 4 })
			task.delay(0.05, function()
				Tween.play(instance, 0.35, { Rotation = 0 }, Enum.EasingStyle.Elastic)
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
