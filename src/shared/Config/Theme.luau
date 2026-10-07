--!strict
-- UI design tokens. Every colour, radius and font used by the interface.

local Theme = {}

Theme.Colors = {
	Panel = Color3.fromRGB(18, 15, 32),
	PanelLight = Color3.fromRGB(30, 26, 52),
	PanelRaised = Color3.fromRGB(40, 34, 68),
	Stroke = Color3.fromRGB(255, 255, 255),
	Text = Color3.fromRGB(246, 243, 255),
	TextDim = Color3.fromRGB(176, 168, 210),
	TextMuted = Color3.fromRGB(120, 112, 156),
	Essence = Color3.fromRGB(120, 235, 255),
	EssenceDeep = Color3.fromRGB(150, 110, 255),
	Accent = Color3.fromRGB(140, 120, 255),
	Success = Color3.fromRGB(110, 240, 160),
	Danger = Color3.fromRGB(255, 78, 104),
	Warning = Color3.fromRGB(255, 196, 80),
	Gold = Color3.fromRGB(255, 205, 90),
	Power = Color3.fromRGB(255, 160, 96),
	Shadow = Color3.fromRGB(0, 0, 0),
}

Theme.Transparency = {
	Panel = 0.12,
	PanelSoft = 0.3,
	Stroke = 0.86,
	StrokeStrong = 0.6,
}

Theme.Radius = {
	Small = UDim.new(0, 8),
	Medium = UDim.new(0, 12),
	Large = UDim.new(0, 18),
	Pill = UDim.new(1, 0),
}

local BUILDER = "rbxasset://fonts/families/BuilderSans.json"
local FREDOKA = "rbxasset://fonts/families/FredokaOne.json"
local MICHROMA = "rbxasset://fonts/families/Michroma.json"

Theme.Fonts = {
	Body = Font.new(BUILDER, Enum.FontWeight.Medium),
	BodyBold = Font.new(BUILDER, Enum.FontWeight.Bold),
	Heavy = Font.new(BUILDER, Enum.FontWeight.Heavy),
	Display = Font.new(FREDOKA, Enum.FontWeight.Regular),
	Tech = Font.new(MICHROMA, Enum.FontWeight.Regular),
}

-- Plot accent colours, one per Sanctuary (index = plot index).
Theme.PlotColors = {
	Color3.fromRGB(90, 230, 255),
	Color3.fromRGB(255, 110, 200),
	Color3.fromRGB(255, 200, 80),
	Color3.fromRGB(120, 240, 140),
	Color3.fromRGB(255, 140, 70),
	Color3.fromRGB(110, 150, 255),
	Color3.fromRGB(190, 120, 255),
	Color3.fromRGB(255, 90, 100),
}

return Theme
