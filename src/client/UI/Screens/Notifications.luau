--!strict
-- Toast notifications. Max 3 visible, newest on top, duplicates merged.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage.Shared.Config.Theme)

local Kit = script.Parent.Parent.Kit
local Create = require(Kit.Create)
local Style = require(Kit.Style)
local Tween = require(Kit.Tween)
local Text = require(Kit.Text)
local TopStack = require(script.Parent.TopStack)

local Notifications = {}

local STYLE_COLORS: { [string]: Color3 } = {
	info = Theme.Colors.Accent,
	success = Theme.Colors.Success,
	warning = Theme.Colors.Warning,
	danger = Theme.Colors.Danger,
	rare = Theme.Colors.Gold,
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
	Tween.play(frame, 0.25, { BackgroundTransparency = 1 })
	Tween.play(toast.label, 0.2, { TextTransparency = 1 })
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if stroke then
		Tween.play(stroke, 0.2, { Transparency = 1 })
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
		Size = UDim2.fromOffset(440, 44),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.12,
		LayoutOrder = order,
		Parent = holder,
	})
	Style.corner(frame, Theme.Radius.Medium)
	Style.stroke(frame, color, 0.55, 1.5)
	local dot = Create("Frame", {
		Size = UDim2.fromOffset(8, 8),
		Position = UDim2.new(0, 16, 0, 18),
		BackgroundColor3 = color,
		Parent = frame,
	})
	Style.corner(dot, UDim.new(1, 0))
	local label = Style.text({
		Size = UDim2.new(1, -46, 0, 0),
		Position = UDim2.fromOffset(34, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextSize = 17,
		Text = text,
		Parent = frame,
	})
	Style.padding(label, 12, 0)
	local scale: UIScale = Create("UIScale", { Scale = 0.85, Parent = frame })
	Tween.play(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)

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
		Size = UDim2.fromOffset(440, 0),
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
