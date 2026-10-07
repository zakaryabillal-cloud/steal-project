--!strict
-- Reusable UI decorations and primitives following the Theme tokens.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Create = require(script.Parent.Create)

local Style = {}

Style.Theme = Theme
Style.Colors = Theme.Colors
Style.Fonts = Theme.Fonts

function Style.corner(parent: Instance, radius: UDim?): UICorner
	return Create("UICorner", { CornerRadius = radius or Theme.Radius.Medium, Parent = parent })
end

function Style.stroke(parent: Instance, color: Color3?, transparency: number?, thickness: number?): UIStroke
	return Create("UIStroke", {
		Color = color or Theme.Colors.Stroke,
		Transparency = transparency or Theme.Transparency.Stroke,
		Thickness = thickness or 1.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function Style.textStroke(parent: Instance, transparency: number?, thickness: number?): UIStroke
	return Create("UIStroke", {
		Color = Color3.new(0, 0, 0),
		Transparency = transparency or 0.55,
		Thickness = thickness or 1.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Parent = parent,
	})
end

function Style.padding(parent: Instance, all: number, horizontal: number?): UIPadding
	local h = horizontal or all
	return Create("UIPadding", {
		PaddingTop = UDim.new(0, all),
		PaddingBottom = UDim.new(0, all),
		PaddingLeft = UDim.new(0, h),
		PaddingRight = UDim.new(0, h),
		Parent = parent,
	})
end

function Style.gradient(parent: Instance, a: Color3, b: Color3, rotation: number?): UIGradient
	return Create("UIGradient", {
		Color = ColorSequence.new(a, b),
		Rotation = rotation or 0,
		Parent = parent,
	})
end

function Style.list(parent: Instance, padding: number, direction: Enum.FillDirection?, hAlign: Enum.HorizontalAlignment?, vAlign: Enum.VerticalAlignment?): UIListLayout
	return Create("UIListLayout", {
		Padding = UDim.new(0, padding),
		FillDirection = direction or Enum.FillDirection.Vertical,
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Center,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
end

-- Dark glass panel.
function Style.panel(props: { [string]: any }): Frame
	local frame = Create("Frame", {
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = Theme.Transparency.Panel,
		BorderSizePixel = 0,
	})
	for key, value in props do
		if key ~= "Parent" and key ~= "CornerRadius" then
			(frame :: any)[key] = value
		end
	end
	Style.corner(frame, props.CornerRadius or Theme.Radius.Large)
	Style.stroke(frame)
	Create("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(205, 200, 225)),
		Rotation = 90,
		Parent = frame,
	})
	if props.Parent then
		frame.Parent = props.Parent
	end
	return frame
end

export type TextProps = { [string]: any }

function Style.text(props: TextProps): TextLabel
	local label = Create("TextLabel", {
		BackgroundTransparency = 1,
		TextColor3 = Theme.Colors.Text,
		FontFace = Theme.Fonts.BodyBold,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		RichText = true,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
	})
	for key, value in props do
		if key ~= "Parent" then
			(label :: any)[key] = value
		end
	end
	if props.Parent then
		label.Parent = props.Parent
	end
	return label
end

function Style.hex(color: Color3): string
	return string.format("#%02X%02X%02X", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
end

-- Wraps text in a RichText colour tag.
function Style.colored(text: string, color: Color3): string
	return string.format('<font color="%s">%s</font>', Style.hex(color), text)
end

-- Escapes user-provided text (player names) before inserting in RichText.
function Style.escape(text: string): string
	text = string.gsub(text, "&", "&amp;") :: string
	text = string.gsub(text, "<", "&lt;") :: string
	text = string.gsub(text, ">", "&gt;") :: string
	text = string.gsub(text, '"', "&quot;") :: string
	return text
end

return Style
