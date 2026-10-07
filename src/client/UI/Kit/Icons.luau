--!strict
-- Vector-style icons drawn with frames (no image assets needed). Each
-- builder fills the given parent (sized by the caller) and returns the root.

local Create = require(script.Parent.Create)

local Icons = {}

local function root(parent: Instance, name: string): Frame
	return Create("Frame", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = parent,
	})
end

local function bar(parent: Instance, size: UDim2, position: UDim2, rotation: number, color: Color3, round: boolean?): Frame
	local frame = Create("Frame", {
		Size = size,
		Position = position,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = rotation,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = parent,
	})
	if round ~= false then
		Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = frame })
	end
	return frame
end

local function ring(parent: Instance, scale: number, thickness: number, color: Color3, transparency: number?): Frame
	local frame = Create("Frame", {
		Size = UDim2.fromScale(scale, scale),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = frame })
	Create("UIStroke", { Color = color, Thickness = thickness, Transparency = transparency or 0, Parent = frame })
	Create("UIAspectRatioConstraint", { Parent = frame })
	return frame
end

-- Faceted gem: the Essence currency mark.
function Icons.essence(parent: Instance, a: Color3?, b: Color3?): Frame
	local r = root(parent, "EssenceIcon")
	local gem = Create("Frame", {
		Size = UDim2.fromScale(0.62, 0.62),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = 45,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = r,
	})
	Create("UICorner", { CornerRadius = UDim.new(0.18, 0), Parent = gem })
	Create("UIAspectRatioConstraint", { Parent = gem })
	Create("UIGradient", {
		Color = ColorSequence.new(a or Color3.fromRGB(130, 245, 255), b or Color3.fromRGB(160, 110, 255)),
		Rotation = 45,
		Parent = gem,
	})
	local shine = Create("Frame", {
		Size = UDim2.fromScale(0.38, 0.38),
		Position = UDim2.fromScale(0.3, 0.3),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Parent = gem,
	})
	Create("UICorner", { CornerRadius = UDim.new(0.3, 0), Parent = shine })
	return r
end

function Icons.upgrades(parent: Instance, color: Color3): Frame
	local r = root(parent, "UpgradesIcon")
	for i, y in { 0.42, 0.7 } do
		bar(r, UDim2.fromScale(0.42, 0.13), UDim2.fromScale(0.36, y), -40, color).BackgroundTransparency = (i - 1) * 0.35
		bar(r, UDim2.fromScale(0.42, 0.13), UDim2.fromScale(0.64, y), 40, color).BackgroundTransparency = (i - 1) * 0.35
	end
	return r
end

function Icons.dex(parent: Instance, color: Color3): Frame
	local r = root(parent, "DexIcon")
	for x = 0, 1 do
		for y = 0, 1 do
			local cell = Create("Frame", {
				Size = UDim2.fromScale(0.3, 0.3),
				Position = UDim2.fromScale(0.33 + x * 0.34, 0.33 + y * 0.34),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = color,
				BackgroundTransparency = if x + y == 1 then 0.35 else 0,
				BorderSizePixel = 0,
				Parent = r,
			})
			Create("UICorner", { CornerRadius = UDim.new(0.3, 0), Parent = cell })
		end
	end
	return r
end

function Icons.settings(parent: Instance, color: Color3): Frame
	local r = root(parent, "SettingsIcon")
	for i = 0, 3 do
		bar(r, UDim2.fromScale(0.78, 0.16), UDim2.fromScale(0.5, 0.5), i * 45, color, false)
	end
	local hub = ring(r, 0.5, 0, color)
	hub.BackgroundTransparency = 0
	hub.BackgroundColor3 = color
	local hole = ring(r, 0.22, 0, color)
	hole.BackgroundTransparency = 0
	hole.BackgroundColor3 = Color3.fromRGB(30, 26, 52)
	return r
end

function Icons.close(parent: Instance, color: Color3): Frame
	local r = root(parent, "CloseIcon")
	bar(r, UDim2.fromScale(0.7, 0.12), UDim2.fromScale(0.5, 0.5), 45, color)
	bar(r, UDim2.fromScale(0.7, 0.12), UDim2.fromScale(0.5, 0.5), -45, color)
	return r
end

function Icons.dash(parent: Instance, color: Color3): Frame
	local r = root(parent, "DashIcon")
	for i, x in { 0.36, 0.62 } do
		local alpha = (2 - i) * 0.4
		bar(r, UDim2.fromScale(0.36, 0.13), UDim2.fromScale(x, 0.38), 40, color).BackgroundTransparency = alpha
		bar(r, UDim2.fromScale(0.36, 0.13), UDim2.fromScale(x, 0.62), -40, color).BackgroundTransparency = alpha
	end
	return r
end

function Icons.pulse(parent: Instance, color: Color3): Frame
	local r = root(parent, "PulseIcon")
	local dot = ring(r, 0.26, 0, color)
	dot.BackgroundTransparency = 0
	dot.BackgroundColor3 = color
	ring(r, 0.56, 2.5, color, 0.1)
	ring(r, 0.86, 2, color, 0.5)
	return r
end

function Icons.seal(parent: Instance, color: Color3): Frame
	local r = root(parent, "SealIcon")
	local shackle = Create("Frame", {
		Size = UDim2.fromScale(0.42, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = r,
	})
	Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = shackle })
	Create("UIStroke", { Color = color, Thickness = 3, Parent = shackle })
	local body = Create("Frame", {
		Size = UDim2.fromScale(0.62, 0.42),
		Position = UDim2.fromScale(0.5, 0.66),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = r,
	})
	Create("UICorner", { CornerRadius = UDim.new(0.22, 0), Parent = body })
	local keyhole = Create("Frame", {
		Size = UDim2.fromScale(0.16, 0.36),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(30, 26, 52),
		BorderSizePixel = 0,
		Parent = body,
	})
	Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = keyhole })
	return r
end

-- Lightning bolt: the Power Level mark.
function Icons.power(parent: Instance, color: Color3): Frame
	local r = root(parent, "PowerIcon")
	bar(r, UDim2.fromScale(0.16, 0.48), UDim2.fromScale(0.57, 0.3), 24, color, false)
	bar(r, UDim2.fromScale(0.42, 0.15), UDim2.fromScale(0.5, 0.5), -24, color, false)
	bar(r, UDim2.fromScale(0.16, 0.48), UDim2.fromScale(0.43, 0.7), 24, color, false)
	return r
end

function Icons.arrow(parent: Instance, color: Color3): Frame
	local r = root(parent, "ArrowIcon")
	bar(r, UDim2.fromScale(0.5, 0.16), UDim2.fromScale(0.36, 0.5), 45, color)
	bar(r, UDim2.fromScale(0.5, 0.16), UDim2.fromScale(0.64, 0.5), -45, color)
	return r
end

function Icons.shield(parent: Instance, color: Color3): Frame
	local r = root(parent, "ShieldIcon")
	local top = Create("Frame", {
		Size = UDim2.fromScale(0.62, 0.42),
		Position = UDim2.fromScale(0.5, 0.36),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = r,
	})
	Create("UICorner", { CornerRadius = UDim.new(0.2, 0), Parent = top })
	local tip = Create("Frame", {
		Size = UDim2.fromScale(0.44, 0.44),
		Position = UDim2.fromScale(0.5, 0.56),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = 45,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = r,
	})
	Create("UICorner", { CornerRadius = UDim.new(0.15, 0), Parent = tip })
	Create("UIAspectRatioConstraint", { Parent = tip })
	return r
end

return Icons
