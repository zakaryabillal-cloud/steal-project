--!strict
-- Shared modal shell: glass panel, title/subtitle header, close button,
-- open/close animations.

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
	title: TextLabel,
	subtitle: TextLabel,
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
}

function Modal.new(props: Props): Modal
	local panel = Style.panel({
		Name = props.name,
		Size = props.size,
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 0.06,
		Visible = false,
		ZIndex = 5,
		Parent = props.parent,
	})
	local scale: UIScale = Create("UIScale", { Parent = panel })
	-- Accent glow line along the top edge.
	local line = Create("Frame", {
		Size = UDim2.new(0.6, 0, 0, 3),
		Position = UDim2.new(0.5, 0, 0, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = panel,
	})
	Style.corner(line, UDim.new(1, 0))
	Create("UIGradient", {
		Color = ColorSequence.new(props.accent or Theme.Colors.Essence, Theme.Colors.EssenceDeep),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = line,
	})

	local header: Frame = Create("Frame", {
		Name = "Header",
		Size = UDim2.new(1, -40, 0, 70),
		Position = UDim2.fromOffset(20, 14),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = panel,
	})
	local title = Style.text({
		Size = UDim2.new(1, -60, 0, 40),
		FontFace = Theme.Fonts.Display,
		TextSize = 34,
		ZIndex = 6,
		Parent = header,
	})
	local subtitle = Style.text({
		Size = UDim2.new(1, -60, 0, 22),
		Position = UDim2.fromOffset(2, 40),
		FontFace = Theme.Fonts.Body,
		TextSize = 16,
		TextColor3 = Theme.Colors.TextDim,
		ZIndex = 6,
		Parent = header,
	})
	local close = Button.new({
		name = "Close",
		size = UDim2.fromOffset(42, 42),
		position = UDim2.new(1, 0, 0, 0),
		anchor = Vector2.new(1, 0),
		color = Theme.Colors.PanelRaised,
		corner = UDim.new(1, 0),
		zIndex = 7,
		parent = header,
		onClick = props.onClose,
	})
	local iconHolder = Create("Frame", {
		Size = UDim2.fromScale(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 8,
		Parent = close.instance,
	})
	Icons.close(iconHolder, Theme.Colors.Text)
	for _, child in iconHolder:GetDescendants() do
		if child:IsA("GuiObject") then
			child.ZIndex = 8
		end
	end

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
		title = title,
		subtitle = subtitle,
		scale = scale,
		open = function()
			token += 1
			panel.Visible = true
			scale.Scale = 0.88
			panel.Position = UDim2.new(0.5, 0, 0.5, 24)
			Tween.play(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
			Tween.play(panel, 0.3, { Position = UDim2.fromScale(0.5, 0.5) })
		end,
		close = function()
			token += 1
			local myToken = token
			Tween.play(scale, 0.16, { Scale = 0.92 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
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
