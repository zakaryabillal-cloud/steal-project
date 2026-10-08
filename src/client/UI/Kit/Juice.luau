--!strict
-- Reward "juice" (Phase 5.5): confetti bursts, floating "+250!" text, star
-- pops and spinning sun rays. Pure tweens (no per-frame loop), capped and
-- throttled so a flood of rewards can never flood the screen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local Theme = require(ReplicatedStorage.Shared.Config.Theme)

local Create = require(script.Parent.Create)
local Style = require(script.Parent.Style)
local Tween = require(script.Parent.Tween)

local Juice = {}

-- At most this many confetti pieces alive at once, and bursts per second.
Juice.MaxConfetti = 60
Juice.MaxBurstsPerSecond = 4

local CONFETTI_COLORS = {
	Theme.Colors.Gold,
	Theme.Colors.Accent,
	Theme.Colors.Essence,
	Theme.Colors.Success,
	Theme.Colors.Power,
	Color3.fromRGB(180, 120, 255),
}

local alive = 0
local burstTimes: { number } = {}
local rng = Random.new()

local function allowBurst(): boolean
	local now = os.clock()
	local kept: { number } = {}
	for _, t in burstTimes do
		if now - t < 1 then
			table.insert(kept, t)
		end
	end
	burstTimes = kept
	if #burstTimes >= Juice.MaxBurstsPerSecond then
		return false
	end
	table.insert(burstTimes, now)
	return true
end

-- Confetti exploding from `origin` (pixels inside `parent`), then falling.
function Juice.confetti(parent: Instance, origin: Vector2, count: number?, colors: { Color3 }?): number
	if not allowBurst() then
		return 0
	end
	local palette = colors or CONFETTI_COLORS
	local n = math.min(count or 16, Juice.MaxConfetti - alive)
	for i = 1, n do
		alive += 1
		local w = rng:NextInteger(7, 12)
		local piece = Create("Frame", {
			Name = "Confetti",
			Size = UDim2.fromOffset(w, math.floor(w * 0.6)),
			Position = UDim2.fromOffset(origin.X, origin.Y),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = palette[(i - 1) % #palette + 1],
			BorderSizePixel = 0,
			Rotation = rng:NextNumber(0, 360),
			ZIndex = 40,
			Parent = parent,
		})
		Style.corner(piece, UDim.new(0, 3))
		local angle = rng:NextNumber(0, math.pi * 2)
		local power = rng:NextNumber(70, 170)
		local mid = origin + Vector2.new(math.cos(angle) * power, math.sin(angle) * power * 0.7 - 40)
		local fall = mid + Vector2.new(rng:NextNumber(-30, 30), rng:NextNumber(90, 160))
		Tween.play(piece, 0.35, { Position = UDim2.fromOffset(mid.X, mid.Y), Rotation = piece.Rotation + rng:NextNumber(-180, 180) }, Enum.EasingStyle.Quad)
		task.delay(0.35, function()
			Tween.play(piece, 0.75, { Position = UDim2.fromOffset(fall.X, fall.Y), Rotation = piece.Rotation + rng:NextNumber(-360, 360), BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.delay(0.8, function()
				alive -= 1
				piece:Destroy()
			end)
		end)
	end
	return n
end

-- "+250!" popping at `position` (pixels in `parent`), floating up and fading.
function Juice.floatText(parent: Instance, text: string, position: Vector2, color: Color3?, size: number?): TextLabel
	local label = Style.text({
		Name = "FloatText",
		Size = UDim2.fromOffset(240, 50),
		Position = UDim2.fromOffset(position.X, position.Y),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = text,
		TextSize = size or 30,
		FontFace = Style.burstFont(text),
		TextColor3 = color or Theme.Colors.Gold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Rotation = rng:NextNumber(-8, 8),
		ZIndex = 41,
		Parent = parent,
	})
	local stroke = Style.ink(label, 3)
	Tween.popIn(label, 0.2)
	task.delay(0.35, function()
		Tween.play(label, 0.8, { Position = UDim2.fromOffset(position.X, position.Y - 60), TextTransparency = 1, Rotation = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Tween.play(stroke, 0.8, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.85, function()
			label:Destroy()
		end)
	end)
	return label
end

-- A ring of "★" stars popping around a GuiObject's centre.
function Juice.stars(target: GuiObject, count: number?, color: Color3?)
	if not allowBurst() then
		return
	end
	local n = count or 6
	local size = target.AbsoluteSize
	local radius = math.max(size.X, size.Y) * 0.55 + 10
	for i = 1, n do
		local angle = (i / n) * math.pi * 2
		local star = Style.text({
			Name = "Star",
			Size = UDim2.fromOffset(26, 26),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Text = "★",
			TextSize = 24,
			FontFace = Theme.Fonts.Display,
			TextColor3 = color or Theme.Colors.Gold,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 30,
			Parent = target,
		})
		Style.ink(star, 2)
		Tween.play(star, 0.5, {
			Position = UDim2.new(0.5, math.cos(angle) * radius, 0.5, math.sin(angle) * radius),
			Rotation = 180,
			TextTransparency = 1,
		}, Enum.EasingStyle.Quint)
		task.delay(0.55, function()
			star:Destroy()
		end)
	end
end

-- Slowly spinning sun rays behind a reward (returns the holder; destroy it to stop).
function Juice.rays(parent: Instance, color: Color3?, count: number?, zIndex: number?): Frame
	local holder: Frame = Create("Frame", {
		Name = "Rays",
		Size = UDim2.fromScale(1.6, 1.6),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = zIndex or 1,
		Parent = parent,
	})
	Create("UIAspectRatioConstraint", { Parent = holder })
	local n = count or 10
	for i = 1, n do
		local ray = Create("Frame", {
			Size = UDim2.new(0.16, 0, 1, 0),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = (i / n) * 180,
			BackgroundColor3 = color or Theme.Colors.Gold,
			BackgroundTransparency = 0.7,
			BorderSizePixel = 0,
			ZIndex = zIndex or 1,
			Parent = holder,
		})
		Create("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Rotation = 90,
			Parent = ray,
		})
	end
	-- One looping tween per ray holder (no per-frame script).
	local info = TweenInfo.new(14, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1)
	TweenService:Create(holder, info, { Rotation = 360 }):Play()
	return holder
end

-- Full-screen layer (ignores the GUI inset) used by the *From helpers.
local layer: Instance? = nil
function Juice.setLayer(frame: Instance)
	layer = frame
end

local function centerOf(target: GuiObject): Vector2
	local inset = GuiService:GetGuiInset()
	return target.AbsolutePosition + target.AbsoluteSize / 2 + inset
end

-- Confetti from the centre of any on-screen GuiObject.
function Juice.burstFrom(target: GuiObject, count: number?, colors: { Color3 }?): number
	if not layer then
		return 0
	end
	return Juice.confetti(layer :: Instance, centerOf(target), count, colors)
end

-- Floating text above any on-screen GuiObject.
function Juice.floatFrom(target: GuiObject, text: string, color: Color3?, size: number?): TextLabel?
	if not layer then
		return nil
	end
	local at = centerOf(target) - Vector2.new(0, target.AbsoluteSize.Y * 0.5 + 10)
	return Juice.floatText(layer :: Instance, text, at, color, size)
end

function Juice.aliveConfetti(): number
	return alive
end

return Juice
