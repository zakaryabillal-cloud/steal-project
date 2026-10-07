--!strict
-- Active Rift event pill with a draining timer bar.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Events = require(Shared.Config.Events)
local Locale = require(Shared.Locale)
local Format = require(Shared.Util.Format)

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
local stroke: UIStroke
local scale: UIScale
local activeId: string? = nil
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
	nameLabel.TextColor3 = def.color
	descLabel.Text = Locale.t("event." .. def.id .. ".desc")
	dot.BackgroundColor3 = def.color
	stroke.Color = def.color
	bar.BackgroundColor3 = def.color
	frame.Visible = true
	scale.Scale = 0.6
	Tween.play(scale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
end

function EventBanner.init(parent: Instance)
	local stack = TopStack.get(parent)
	frame = Style.panel({
		Name = "EventBanner",
		Size = UDim2.fromOffset(430, 64),
		LayoutOrder = 10,
		Visible = false,
		Parent = stack,
	})
	stroke = frame:FindFirstChildOfClass("UIStroke") :: UIStroke
	stroke.Transparency = 0.3
	scale = Create("UIScale", { Parent = frame })
	dot = Create("Frame", {
		Size = UDim2.fromOffset(14, 14),
		Position = UDim2.new(0, 18, 0, 17),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = frame,
	})
	Style.corner(dot, UDim.new(1, 0))
	nameLabel = Style.text({
		Size = UDim2.new(1, -120, 0, 26),
		Position = UDim2.fromOffset(42, 7),
		FontFace = Style.Fonts.Display,
		TextSize = 22,
		Parent = frame,
	})
	timeLabel = Style.text({
		Size = UDim2.new(0, 70, 0, 26),
		Position = UDim2.new(1, -86, 0, 7),
		TextXAlignment = Enum.TextXAlignment.Right,
		FontFace = Style.Fonts.Heavy,
		TextSize = 18,
		Parent = frame,
	})
	descLabel = Style.text({
		Size = UDim2.new(1, -60, 0, 18),
		Position = UDim2.fromOffset(42, 32),
		TextSize = 14,
		TextColor3 = Style.Colors.TextDim,
		FontFace = Style.Fonts.Body,
		Parent = frame,
	})
	local back = Create("Frame", {
		Size = UDim2.new(1, -36, 0, 4),
		Position = UDim2.new(0, 18, 1, -9),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.85,
		Parent = frame,
	})
	Style.corner(back, UDim.new(1, 0))
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
		dot.BackgroundTransparency = 0.2 + (math.sin(os.clock() * 5) + 1) * 0.2
	end)
	Locale.changed:Connect(function()
		if activeId then
			show(activeId)
		end
	end)
end

return EventBanner
