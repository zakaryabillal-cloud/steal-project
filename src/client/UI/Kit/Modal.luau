--!strict
-- Shared modal shell (Phase 5.5): a chunky blue panel with a coloured title
-- ribbon (emoji + rounded title with an ink outline), a red round close
-- button, a subtitle line and a bouncy open / close.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage.Shared.Config.Theme)

local Create = require(script.Parent.Create)
local Style = require(script.Parent.Style)
local Tween = require(script.Parent.Tween)
local Icons = require(script.Parent.Icons)
local Button = require(script.Parent.Button)

local Modal = {}

export type Modal = {
	panel: Frame,
	body: Frame,
	header: Frame,
	ribbon: Frame,
	title: TextLabel,
	subtitle: TextLabel,
	emoji: TextLabel,
	scale: UIScale,
	open: () -> (),
	close: () -> (),
}

export type Props = {
	name: string,
	size: UDim2,
	parent: Instance,
	onClose: () -> (),
	accent: Color3?,
	-- Emoji shown at the start of the title ribbon (Config/Emoji glyph).
	emoji: string?,
}

function Modal.new(props: Props): Modal
	local accent = props.accent or Theme.Colors.Essence
	local panel = Style.panel({
		Name = props.name,
		Size = props.size,
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		ZIndex = 5,
		Outline = Theme.Outline.Thick,
		Parent = props.parent,
	})
	local scale: UIScale = Create("UIScale", { Parent = panel })

	-- Title ribbon: an accent-coloured tab overlapping the panel's top edge.
	local ribbon: Frame = Create("Frame", {
		Name = "Ribbon",
		Size = UDim2.new(1, -150, 0, 54),
		Position = UDim2.new(0, 22, 0, -16),
		BackgroundColor3 = accent,
		ZIndex = 6,
		Parent = panel,
	})
	Style.corner(ribbon, Theme.Radius.Large)
	Style.stroke(ribbon, Theme.Colors.Ink, 0, Theme.Outline.Regular)
	Style.shade(ribbon, 0.22)
	Style.gloss(ribbon, 6)

	local header: Frame = Create("Frame", {
		Name = "Header",
		Size = UDim2.new(1, -40, 0, 82),
		Position = UDim2.fromOffset(20, -16),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = panel,
	})
	local emoji = Style.text({
		Name = "Emoji",
		Size = UDim2.fromOffset(44, 54),
		Position = UDim2.fromOffset(12, 0),
		Text = props.emoji or "",
		TextSize = 32,
		FontFace = Theme.Fonts.Display,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 7,
		Parent = header,
	})
	local titleX = if props.emoji then 58 else 18
	local title = Style.text({
		Name = "Title",
		Size = UDim2.new(1, -(titleX + 150), 0, 54),
		Position = UDim2.fromOffset(titleX, 0),
		FontFace = Theme.Fonts.Display,
		TextSize = 34,
		TextScaled = true,
		ZIndex = 7,
		Parent = header,
	})
	Create("UITextSizeConstraint", { MaxTextSize = 34, MinTextSize = 18, Parent = title })
	Style.ink(title, Theme.Outline.Regular)
	local subtitle = Style.text({
		Name = "Subtitle",
		Size = UDim2.new(1, -70, 0, 22),
		Position = UDim2.fromOffset(4, 58),
		FontFace = Theme.Fonts.Body,
		TextSize = 16,
		TextColor3 = Theme.Colors.TextDim,
		ZIndex = 6,
		Parent = header,
	})
	local close = Button.new({
		name = "Close",
		size = UDim2.fromOffset(52, 52),
		position = UDim2.new(1, 18, 0, -22),
		anchor = Vector2.new(1, 0),
		kind = "red",
		corner = Theme.Radius.Pill,
		zIndex = 8,
		parent = panel,
		onClick = props.onClose,
	})
	local iconHolder = Create("Frame", {
		Size = UDim2.fromScale(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 10,
		Parent = close.content,
	})
	Icons.close(iconHolder, Theme.Colors.Text)

	local body: Frame = Create("Frame", {
		Name = "Body",
		Size = UDim2.new(1, -40, 1, -104),
		Position = UDim2.fromOffset(20, 92),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = panel,
	})

	local token = 0
	local modal: Modal = {
		panel = panel,
		body = body,
		header = header,
		ribbon = ribbon,
		title = title,
		subtitle = subtitle,
		emoji = emoji,
		scale = scale,
		open = function()
			token += 1
			panel.Visible = true
			scale.Scale = 0.7
			panel.Rotation = -3
			panel.Position = UDim2.new(0.5, 0, 0.5, 30)
			Tween.play(scale, 0.42, { Scale = 1 }, Enum.EasingStyle.Back)
			Tween.play(panel, 0.42, { Position = UDim2.fromScale(0.5, 0.5), Rotation = 0 }, Enum.EasingStyle.Back)
			-- The ribbon lands a beat later with a little wiggle.
			ribbon.Rotation = 4
			Tween.play(ribbon, 0.6, { Rotation = 0 }, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out, 0.1)
		end,
		close = function()
			token += 1
			local myToken = token
			Tween.play(scale, 0.16, { Scale = 0.85 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			task.delay(0.16, function()
				if token == myToken then
					panel.Visible = false
				end
			end)
		end,
	}
	return modal
end

return Modal
