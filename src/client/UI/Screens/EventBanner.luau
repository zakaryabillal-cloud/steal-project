--!strict
-- Active Rift event pill with a draining timer bar.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Events = require(Shared.Config.Events)
local Locale = require(Shared.Locale)
local Format = require(Shared.Util.Format)
local Emoji = require(Shared.Config.Emoji)

local Kit = script.Parent.Parent.Kit
local Create = require(Kit.Create)
local Style = require(Kit.Style)
local Tween = require(Kit.Tween)
local TopStack = require(script.Parent.TopStack)

local EventBanner = {}

local frame: Frame
local nameLabel: TextLabel
local descLabel: TextLabel
local timeLabel: TextLabel
local bar: Frame
local dot: Frame
local scale: UIScale
local emojiLabel: TextLabel
local activeId: string? = nil

-- One emoji per Rift event (Config/Emoji).
local EVENT_EMOJI: { [string]: string } = {
	RiftOverload = Emoji.get("power"),
	VoidStorm = Emoji.get("swirl"),
	GoldenSurge = Emoji.get("money"),
	Eclipse = Emoji.get("moon"),
}
local duration = 60

local function show(id: string?)
	activeId = id
	local def = Events.get(id)
	if not def then
		Tween.play(scale, 0.25, { Scale = 0.7 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.25, function()
			if activeId == nil then
				frame.Visible = false
			end
		end)
		return
	end
	duration = def.duration
	nameLabel.Text = Locale.t("event." .. def.id .. ".name")
	descLabel.Text = Locale.t("event." .. def.id .. ".desc")
	emojiLabel.Text = EVENT_EMOJI[def.id] or Emoji.get("ready")
	-- The whole banner takes the event's colour (darkened a touch for white text).
	frame.BackgroundColor3 = Style.vivid(def.color, 0.6, 0.85)
	dot.BackgroundColor3 = Style.Colors.Cream
	bar.BackgroundColor3 = Style.Colors.Gold
	frame.Visible = true
	scale.Scale = 0.4
	Tween.play(scale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
	Tween.wiggle(frame, 6)
end

function EventBanner.init(parent: Instance)
	local stack = TopStack.get(parent)
	frame = Style.panel({
		Name = "EventBanner",
		Size = UDim2.fromOffset(450, 70),
		LayoutOrder = 10,
		Visible = false,
		Parent = stack,
	})
	scale = Create("UIScale", { Parent = frame })
	dot = Create("Frame", {
		Name = "Bubble",
		Size = UDim2.fromOffset(46, 46),
		Position = UDim2.new(0, 10, 0, 8),
		BackgroundColor3 = Style.Colors.Cream,
		Parent = frame,
	})
	Style.corner(dot, UDim.new(1, 0))
	Style.stroke(dot, Style.Colors.Ink, 0, 2)
	emojiLabel = Style.text({ Name = "Emoji", Text = "", TextSize = 28, FontFace = Style.Fonts.Display, TextXAlignment = Enum.TextXAlignment.Center, Parent = dot })
	emojiLabel:SetAttribute("Emoji", true)
	nameLabel = Style.text({
		Size = UDim2.new(1, -150, 0, 28),
		Position = UDim2.fromOffset(66, 6),
		FontFace = Style.Fonts.Display,
		TextSize = 24,
		Parent = frame,
	})
	Style.ink(nameLabel, 2.5)
	timeLabel = Style.text({
		Size = UDim2.new(0, 76, 0, 28),
		Position = UDim2.new(1, -90, 0, 6),
		TextXAlignment = Enum.TextXAlignment.Right,
		FontFace = Style.Fonts.Display,
		TextSize = 22,
		TextColor3 = Style.Colors.Gold,
		Parent = frame,
	})
	Style.ink(timeLabel, 2)
	descLabel = Style.text({
		Size = UDim2.new(1, -84, 0, 18),
		Position = UDim2.fromOffset(66, 33),
		TextSize = 15,
		FontFace = Style.Fonts.BodyBold,
		Parent = frame,
	})
	Style.ink(descLabel, 1.5)
	local back = Create("Frame", {
		Size = UDim2.new(1, -84, 0, 9),
		Position = UDim2.new(0, 66, 1, -14),
		BackgroundColor3 = Style.Colors.Ink,
		BackgroundTransparency = 0.4,
		Parent = frame,
	})
	Style.corner(back, UDim.new(1, 0))
	Style.stroke(back, Style.Colors.Ink, 0, 1.5)
	bar = Create("Frame", { Size = UDim2.fromScale(1, 1), Parent = back })
	Style.corner(bar, UDim.new(1, 0))

	local function sync()
		local id = workspace:GetAttribute("EventId")
		local value = if type(id) == "string" and id ~= "" then id else nil
		if value ~= activeId then
			show(value)
		end
	end
	workspace:GetAttributeChangedSignal("EventId"):Connect(sync)
	sync()

	RunService.Heartbeat:Connect(function()
		if not activeId then
			return
		end
		local endsAt = workspace:GetAttribute("EventEndsAt")
		local remaining = if type(endsAt) == "number" then endsAt - workspace:GetServerTimeNow() else 0
		timeLabel.Text = Format.clock(remaining)
		bar.Size = UDim2.fromScale(math.clamp(remaining / duration, 0, 1), 1)
		dot.Rotation = math.sin(os.clock() * 3) * 8
	end)
	Locale.changed:Connect(function()
		if activeId then
			show(activeId)
		end
	end)
end

return EventBanner
