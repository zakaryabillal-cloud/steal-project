--!strict
-- Toast notifications. Max 3 visible, newest on top, duplicates merged.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Emoji = require(ReplicatedStorage.Shared.Config.Emoji)

local Kit = script.Parent.Parent.Kit
local Create = require(Kit.Create)
local Style = require(Kit.Style)
local Tween = require(Kit.Tween)
local Text = require(Kit.Text)
local TopStack = require(script.Parent.TopStack)

local Notifications = {}

-- Candy toast colours (Theme.Buttons faces) + an emoji per style.
local STYLE_COLORS: { [string]: Color3 } = {
	info = Theme.Buttons.blue.face,
	success = Theme.Buttons.green.face,
	warning = Theme.Buttons.orange.face,
	danger = Theme.Buttons.red.face,
	rare = Theme.Buttons.yellow.face,
}
local STYLE_EMOJI: { [string]: string } = {
	info = Emoji.get("idea"),
	success = Emoji.get("ready"),
	warning = Emoji.get("time"),
	danger = Emoji.get("alarm"),
	rare = Emoji.get("star"),
}

type Toast = { frame: Frame, text: string, expires: number, label: TextLabel }

local holder: Frame
local toasts: { Toast } = {}
local order = 1000
local playSound: ((string) -> ())? = nil

function Notifications.setSoundHandler(handler: (string) -> ())
	playSound = handler
end

local function remove(toast: Toast)
	local index = table.find(toasts, toast)
	if index then
		table.remove(toasts, index)
	end
	local frame = toast.frame
	local scale = frame:FindFirstChildOfClass("UIScale")
	if scale then
		Tween.play(scale, 0.22, { Scale = 0.6 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	end
	Tween.play(frame, 0.25, { BackgroundTransparency = 1 })
	Tween.play(toast.label, 0.2, { TextTransparency = 1 })
	for _, d in frame:GetDescendants() do
		if d:IsA("UIStroke") then
			Tween.play(d, 0.2, { Transparency = 1 })
		elseif d:IsA("TextLabel") and d ~= toast.label then
			Tween.play(d, 0.2, { TextTransparency = 1 })
		elseif d:IsA("Frame") then
			Tween.play(d, 0.2, { BackgroundTransparency = 1 })
		end
	end
	task.delay(0.26, function()
		frame:Destroy()
	end)
end

function Notifications.push(text: string, style: string?, duration: number?)
	local now = os.clock()
	for _, toast in toasts do
		if toast.text == text then
			toast.expires = now + (duration or 3.6)
			Tween.pop(toast.frame, 0.06)
			return
		end
	end
	local color = STYLE_COLORS[style or "info"] or Theme.Colors.Accent
	order -= 1
	local frame: Frame = Create("Frame", {
		Name = "Toast",
		Size = UDim2.fromOffset(460, 52),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = color,
		LayoutOrder = order,
		Parent = holder,
	})
	Style.corner(frame, Theme.Radius.Large)
	Style.stroke(frame, Theme.Colors.Ink, 0, Theme.Outline.Regular)
	Style.shade(frame, 0.2)
	local bubble = Create("Frame", {
		Name = "Bubble",
		Size = UDim2.fromOffset(38, 38),
		Position = UDim2.new(0, 8, 0, 7),
		BackgroundColor3 = Theme.Colors.Cream,
		Parent = frame,
	})
	Style.corner(bubble, UDim.new(1, 0))
	Style.stroke(bubble, Theme.Colors.Ink, 0, Theme.Outline.Thin)
	local emoji = Style.text({
		Name = "Emoji",
		Text = STYLE_EMOJI[style or "info"] or STYLE_EMOJI.info,
		TextSize = 22,
		FontFace = Theme.Fonts.Display,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = bubble,
	})
	emoji:SetAttribute("Emoji", true)
	local label = Style.text({
		Size = UDim2.new(1, -66, 0, 0),
		Position = UDim2.fromOffset(54, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextSize = 18,
		FontFace = Theme.Fonts.Heavy,
		Text = text,
		Parent = frame,
	})
	Style.ink(label, 2)
	Style.padding(label, 14, 0)
	local scale: UIScale = Create("UIScale", { Scale = 0.5, Parent = frame })
	Tween.play(scale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	if style == "rare" or style == "danger" then
		Tween.wiggle(frame, 6)
	end

	local toast: Toast = { frame = frame, text = text, expires = now + (duration or 3.6), label = label }
	table.insert(toasts, 1, toast)
	while #toasts > 3 do
		remove(toasts[#toasts])
	end
	if playSound then
		playSound(if style == "danger" then "StealAlert" elseif style == "rare" then "Notify" else "Notify")
	end
end

function Notifications.fromServer(key: string, args: { [string]: any }, style: string)
	Notifications.push(Text.format(key, args), style, if style == "danger" or style == "rare" then 5 else 3.6)
end

function Notifications.init(parent: Instance)
	local stack = TopStack.get(parent)
	holder = Create("Frame", {
		Name = "Toasts",
		Size = UDim2.fromOffset(460, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 30,
		Parent = stack,
	})
	Style.list(holder, 6, Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Center)
	task.spawn(function()
		while true do
			task.wait(0.2)
			local now = os.clock()
			for i = #toasts, 1, -1 do
				local toast = toasts[i]
				if now > toast.expires then
					remove(toast)
				end
			end
		end
	end)
end

return Notifications
