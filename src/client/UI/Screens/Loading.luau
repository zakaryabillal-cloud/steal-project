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
	root = Create("Frame", {
		Name = "Loading",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(10, 6, 24),
		ZIndex = 50,
		Parent = parent,
	})
	Create("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(40, 22, 80), Color3.fromRGB(6, 4, 16)),
		Rotation = 90,
		Parent = root,
	})
	-- Twinkling stars.
	local stars = {}
	local rng = Random.new(7)
	for _ = 1, 70 do
		local size = rng:NextInteger(2, 4)
		local star = Create("Frame", {
			Size = UDim2.fromOffset(size, size),
			Position = UDim2.fromScale(rng:NextNumber(), rng:NextNumber()),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = rng:NextNumber(0.2, 0.8),
			BorderSizePixel = 0,
			ZIndex = 51,
			Parent = root,
		})
		Style.corner(star, UDim.new(1, 0))
		table.insert(stars, { frame = star, phase = rng:NextNumber(0, 6.28), speed = rng:NextNumber(1, 3) })
	end

	slash = Create("Frame", {
		Size = UDim2.new(0, 10, 0.62, 0),
		Position = UDim2.fromScale(0.5, 0.42),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = 14,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 52,
		Parent = root,
	})
	Style.corner(slash, UDim.new(1, 0))
	Create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Theme.Colors.Essence),
			ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(1, Theme.Colors.EssenceDeep),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Rotation = 90,
		Parent = slash,
	})
	local halo = Create("Frame", {
		Size = UDim2.new(0, 70, 0.66, 0),
		Position = UDim2.fromScale(0.5, 0.42),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = 14,
		BackgroundColor3 = Theme.Colors.EssenceDeep,
		BackgroundTransparency = 0.75,
		BorderSizePixel = 0,
		ZIndex = 51,
		Parent = root,
	})
	Style.corner(halo, UDim.new(1, 0))
	Create("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = halo,
	})

	local title = Style.text({
		Size = UDim2.new(1, 0, 0, 120),
		Position = UDim2.fromScale(0.5, 0.42),
		AnchorPoint = Vector2.new(0.5, 0.5),
		TextXAlignment = Enum.TextXAlignment.Center,
		FontFace = Theme.Fonts.Display,
		TextSize = 104,
		Text = Locale.t("game.title"),
		ZIndex = 53,
		Parent = root,
	})
	Create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(140, 245, 255)),
			ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 140, 255)),
		}),
		Rotation = 0,
		Parent = title,
	})
	Create("UIStroke", { Thickness = 3, Color = Color3.fromRGB(60, 30, 120), Transparency = 0.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, Parent = title })

	tagline = Style.text({
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.new(0.5, 0, 0.42, 72),
		AnchorPoint = Vector2.new(0.5, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		FontFace = Theme.Fonts.BodyBold,
		TextSize = 22,
		TextColor3 = Theme.Colors.TextDim,
		Text = Locale.t("loading.tagline"),
		ZIndex = 53,
		Parent = root,
	})
	status = Style.text({
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.new(0.5, 0, 1, -70),
		AnchorPoint = Vector2.new(0.5, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		FontFace = Theme.Fonts.Heavy,
		TextSize = 18,
		TextColor3 = Theme.Colors.Essence,
		Text = Locale.t(statusKey),
		ZIndex = 53,
		Parent = root,
	})

	local clock = 0
	connection = RunService.RenderStepped:Connect(function(dt)
		clock += dt
		for _, star in stars do
			star.frame.BackgroundTransparency = 0.3 + (math.sin(clock * star.speed + star.phase) + 1) * 0.3
		end
		slash.Size = UDim2.new(0, 8 + math.sin(clock * 3) * 3, 0.62, 0)
		status.TextTransparency = 0.15 + (math.sin(clock * 4) + 1) * 0.2
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
