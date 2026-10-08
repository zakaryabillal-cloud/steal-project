--!strict
-- Reusable UI decorations and primitives following the Theme tokens
-- (Phase 5.5: cartoon panels, ink outlines, chips and badges).

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

-- Solid ink outline by default (cartoon look).
function Style.stroke(parent: Instance, color: Color3?, transparency: number?, thickness: number?): UIStroke
	return Create("UIStroke", {
		Color = color or Theme.Colors.Ink,
		Transparency = transparency or Theme.Transparency.Stroke,
		Thickness = thickness or Theme.Outline.Thin,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

-- Outline around text glyphs (ink).
function Style.textStroke(parent: Instance, transparency: number?, thickness: number?): UIStroke
	return Create("UIStroke", {
		Color = Theme.Colors.Ink,
		Transparency = transparency or 0.2,
		Thickness = thickness or 1.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Parent = parent,
	})
end

-- Opaque ink outline for display text (titles, numbers, button labels).
function Style.ink(label: Instance, thickness: number?): UIStroke
	return Style.textStroke(label, 0, thickness or Theme.Outline.Text)
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

-- Vertical "candy" shading: full colour on top, a touch darker below.
function Style.shade(parent: Instance, amount: number?): UIGradient
	local k = 1 - (amount or 0.18)
	return Create("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(k, k, k * 1.05)),
		Rotation = 90,
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

-- Cartoon panel: opaque royal blue, candy shading, thick ink outline.
function Style.panel(props: { [string]: any }): Frame
	local frame = Create("Frame", {
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = Theme.Transparency.Panel,
		BorderSizePixel = 0,
	})
	for key, value in props do
		if key ~= "Parent" and key ~= "CornerRadius" and key ~= "Outline" then
			(frame :: any)[key] = value
		end
	end
	Style.corner(frame, props.CornerRadius or Theme.Radius.Large)
	Style.stroke(frame, Theme.Colors.Ink, 0, props.Outline or Theme.Outline.Regular)
	Style.shade(frame, 0.2)
	if props.Parent then
		frame.Parent = props.Parent
	end
	return frame
end

-- Inset well inside a panel (cards, lists).
function Style.card(props: { [string]: any }): Frame
	local frame = Create("Frame", {
		BackgroundColor3 = Theme.Colors.PanelLight,
		BorderSizePixel = 0,
	})
	for key, value in props do
		if key ~= "Parent" and key ~= "CornerRadius" then
			(frame :: any)[key] = value
		end
	end
	Style.corner(frame, props.CornerRadius or Theme.Radius.Medium)
	Style.stroke(frame, Theme.Colors.Ink, 0, Theme.Outline.Thin)
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

-- Big rounded display text with an ink outline (titles, counters).
function Style.display(props: TextProps): TextLabel
	local merged: TextProps = { FontFace = Theme.Fonts.Display, TextSize = 24 }
	for key, value in props do
		merged[key] = value
	end
	local label = Style.text(merged)
	Style.ink(label, if (label.TextSize >= 28) then Theme.Outline.Regular else Theme.Outline.Text)
	return label
end

-- Coloured pill with centred text (rarity tags, rate chips, statuses).
function Style.pill(props: { text: string, color: Color3, size: UDim2?, position: UDim2?, anchor: Vector2?, textSize: number?, parent: Instance?, name: string?, zIndex: number?, layoutOrder: number? }): (Frame, TextLabel)
	local frame: Frame = Create("Frame", {
		Name = props.name or "Pill",
		Size = props.size or UDim2.fromOffset(80, 22),
		Position = props.position or UDim2.new(),
		AnchorPoint = props.anchor or Vector2.zero,
		BackgroundColor3 = props.color,
		BorderSizePixel = 0,
		ZIndex = props.zIndex or 1,
		LayoutOrder = props.layoutOrder or 0,
	})
	Style.corner(frame, Theme.Radius.Pill)
	Style.stroke(frame, Theme.Colors.Ink, 0, Theme.Outline.Thin)
	Style.shade(frame, 0.15)
	local label = Style.text({
		Name = "Label",
		Text = props.text,
		TextSize = props.textSize or 13,
		FontFace = Theme.Fonts.Heavy,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = (props.zIndex or 1) + 1,
		Parent = frame,
	})
	Style.ink(label, 1.5)
	if props.parent then
		frame.Parent = props.parent
	end
	return frame, label
end

-- Round notification badge ("!", "3") pinned to a corner of `parent`.
function Style.badge(parent: Instance, text: string, color: Color3?, size: number?): Frame
	local s = size or 22
	local frame: Frame = Create("Frame", {
		Name = "Badge",
		Size = UDim2.fromOffset(s, s),
		Position = UDim2.new(1, 4, 0, -4),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = color or Theme.Colors.Danger,
		ZIndex = 8,
		Parent = parent,
	})
	Style.corner(frame, Theme.Radius.Pill)
	Style.stroke(frame, Theme.Colors.Ink, 0, Theme.Outline.Thin)
	local label = Style.text({
		Text = text,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = math.floor(s * 0.62),
		FontFace = Theme.Fonts.Heavy,
		ZIndex = 9,
		Parent = frame,
	})
	Style.ink(label, 1.5)
	Create("UIScale", { Parent = frame })
	return frame
end

-- Glossy highlight across the top of a chunky element.
function Style.gloss(parent: Instance, zIndex: number?): Frame
	local gloss: Frame = Create("Frame", {
		Name = "Gloss",
		Size = UDim2.new(1, -10, 0.38, 0),
		Position = UDim2.new(0.5, 0, 0, 4),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.72,
		BorderSizePixel = 0,
		ZIndex = zIndex or 1,
		Parent = parent,
	})
	Style.corner(gloss, Theme.Radius.Pill)
	return gloss
end

-- Luckiest Guy (Burst) has no accented letters: use Fredoka for those strings.
function Style.burstFont(text: string): Font
	return if string.find(text, "[\128-\255]") then Theme.Fonts.Display else Theme.Fonts.Burst
end

-- "★★★" string for a rarity (readable without colour).
function Style.stars(rarityId: string): string
	local count = Theme.RarityStars[rarityId] or 1
	return string.rep("★", count)
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

-- Saturated version of a (possibly pastel) colour for chunky button faces.
function Style.vivid(color: Color3, minSaturation: number?, value: number?): Color3
	local h, sat, v = color:ToHSV()
	return Color3.fromHSV(h, math.max(sat, minSaturation or 0.55), math.clamp(value or math.max(v, 0.9), 0, 1))
end

-- Relative luminance / contrast ratio (WCAG), used by tests and pickers.
local function channel(c: number): number
	return if c <= 0.03928 then c / 12.92 else ((c + 0.055) / 1.055) ^ 2.4
end
function Style.luminance(color: Color3): number
	return 0.2126 * channel(color.R) + 0.7152 * channel(color.G) + 0.0722 * channel(color.B)
end
function Style.contrast(a: Color3, b: Color3): number
	local la, lb = Style.luminance(a), Style.luminance(b)
	if la < lb then
		la, lb = lb, la
	end
	return (la + 0.05) / (lb + 0.05)
end

return Style
