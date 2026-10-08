--!strict
-- Opening screen shown while the world is generated and your profile loads.
-- Status lines describe the real step in progress (no fake progress).

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Theme = require(Shared.Config.Theme)
local Locale = require(Shared.Locale)

local UIRoot = script.Parent.Parent
local Kit = UIRoot.Kit
local Create = require(Kit.Create)
local Style = require(Kit.Style)
local Tween = require(Kit.Tween)

local Loading = {}

local root: Frame
local status: TextLabel
local tagline: TextLabel
local slash: Frame
local connection: RBXScriptConnection? = nil
local statusKey = "loading.building"

function Loading.setStatus(key: string)
	statusKey = key
	status.Text = Locale.t(key)
end

function Loading.show(parent: Instance)
	-- Sunny sky, puffy clouds, a bouncing candy logo and a spinning pink portal.
	root = Create("Frame", {
		Name = "Loading",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 50,
		Parent = parent,
	})
	Create("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(86, 176, 255), Color3.fromRGB(176, 230, 255)),
		Rotation = 90,
		Parent = root,
	})
	-- Drifting clouds (three overlapping white bubbles each).
	local clouds = {}
	local rng = Random.new(7)
	for i = 1, 7 do
		local width = rng:NextInteger(140, 260)
		local cloud = Create("Frame", {
			Name = "Cloud",
			Size = UDim2.fromOffset(width, width * 0.42),
			Position = UDim2.fromScale(rng:NextNumber(-0.1, 1), rng:NextNumber(0.05, 0.85)),
			BackgroundTransparency = 1,
			ZIndex = 51,
			Parent = root,
		})
		for k, spec in { { 0, 0.35, 0.55, 0.65 }, { 0.3, 0.05, 0.45, 0.95 }, { 0.6, 0.3, 0.42, 0.7 } } do
			local puff = Create("Frame", {
				Size = UDim2.fromScale(spec[3], spec[4]),
				Position = UDim2.fromScale(spec[1], spec[2]),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = 0.05,
				BorderSizePixel = 0,
				ZIndex = 51,
				LayoutOrder = k,
				Parent = cloud,
			})
			Style.corner(puff, UDim.new(1, 0))
		end
		table.insert(clouds, { frame = cloud, speed = rng:NextNumber(0.008, 0.02) * (if i % 2 == 0 then 1 else 0.7) })
	end

	-- The Rift: a fat spinning pink ring behind the logo.
	slash = Create("Frame", {
		Name = "Portal",
		Size = UDim2.fromOffset(300, 300),
		Position = UDim2.fromScale(0.5, 0.42),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 52,
		Parent = root,
	})
	Style.corner(slash, UDim.new(1, 0))
	Create("UIStroke", { Thickness = 5, Color = Theme.Colors.Ink, Parent = slash })
	Create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Theme.Colors.Accent),
			ColorSequenceKeypoint.new(0.5, Theme.Colors.Gold),
			ColorSequenceKeypoint.new(1, Theme.Colors.EssenceDeep),
		}),
		Rotation = 45,
		Parent = slash,
	})
	local hole = Create("Frame", {
		Size = UDim2.fromScale(0.62, 0.62),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(110, 70, 220),
		ZIndex = 52,
		Parent = slash,
	})
	Style.corner(hole, UDim.new(1, 0))
	Create("UIStroke", { Thickness = 4, Color = Theme.Colors.Ink, Parent = hole })

	local title = Style.text({
		Name = "Logo",
		Size = UDim2.new(1, 0, 0, 130),
		Position = UDim2.fromScale(0.5, 0.42),
		AnchorPoint = Vector2.new(0.5, 0.5),
		TextXAlignment = Enum.TextXAlignment.Center,
		FontFace = Theme.Fonts.Burst,
		TextSize = 112,
		Text = Locale.t("game.title"),
		Rotation = -4,
		ZIndex = 53,
		Parent = root,
	})
	Create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Theme.Colors.Gold),
			ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(1, Theme.Colors.Accent),
		}),
		Rotation = 90,
		Parent = title,
	})
	Create("UIStroke", { Thickness = 7, Color = Theme.Colors.Ink, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, Parent = title })
	local titleScale = Create("UIScale", { Parent = title })

	tagline = Style.text({
		Size = UDim2.new(1, 0, 0, 34),
		Position = UDim2.new(0.5, 0, 0.42, 84),
		AnchorPoint = Vector2.new(0.5, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		FontFace = Theme.Fonts.Display,
		TextSize = 26,
		Text = Locale.t("loading.tagline"),
		ZIndex = 53,
		Parent = root,
	})
	Style.ink(tagline, Theme.Outline.Regular)
	local statusPill = Create("Frame", {
		Name = "Status",
		Size = UDim2.fromOffset(360, 44),
		Position = UDim2.new(0.5, 0, 1, -80),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Theme.Colors.Panel,
		ZIndex = 53,
		Parent = root,
	})
	Style.corner(statusPill, UDim.new(1, 0))
	Create("UIStroke", { Thickness = 3, Color = Theme.Colors.Ink, Parent = statusPill })
	status = Style.text({
		TextXAlignment = Enum.TextXAlignment.Center,
		FontFace = Theme.Fonts.Display,
		TextSize = 20,
		Text = Locale.t(statusKey),
		ZIndex = 54,
		Parent = statusPill,
	})
	Style.ink(status, 2)

	local clock = 0
	connection = RunService.RenderStepped:Connect(function(dt)
		clock += dt
		for _, cloud in clouds do
			local p = cloud.frame.Position
			local x = p.X.Scale + cloud.speed * dt
			cloud.frame.Position = UDim2.fromScale(if x > 1.1 then -0.25 else x, p.Y.Scale)
		end
		slash.Rotation = (clock * 40) % 360
		titleScale.Scale = 1 + math.sin(clock * 3) * 0.03
		title.Rotation = -4 + math.sin(clock * 1.6) * 2
	end)
	Locale.changed:Connect(function()
		if root.Parent then
			title.Text = Locale.t("game.title")
			tagline.Text = Locale.t("loading.tagline")
			status.Text = Locale.t(statusKey)
		end
	end)
end

function Loading.hide()
	if not root then
		return
	end
	status.Text = Locale.t("loading.ready")
	task.wait(0.35)
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("TextLabel") then
			Tween.play(descendant, 0.6, { TextTransparency = 1 })
		elseif descendant:IsA("Frame") then
			Tween.play(descendant, 0.6, { BackgroundTransparency = 1 })
		elseif descendant:IsA("UIStroke") then
			Tween.play(descendant, 0.6, { Transparency = 1 })
		end
	end
	Tween.play(root, 0.8, { BackgroundTransparency = 1 })
	task.delay(0.85, function()
		if connection then
			connection:Disconnect()
		end
		root:Destroy()
	end)
end

return Loading
