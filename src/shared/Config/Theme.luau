--!strict
-- UI design tokens (Phase 5.5 "Cartoon & Goofy"). Every colour, radius and
-- font used by the interface. Rules and rationale: docs/ART_DIRECTION.md.
--
-- Look: saturated royal-blue panels, thick ink outlines, white rounded text
-- with an ink stroke, chunky coloured buttons with a darker "lip" below.

local Theme = {}

local rgb = Color3.fromRGB

Theme.Colors = {
	-- Panels: opaque royal blue (white text keeps >= 4.5:1 contrast).
	Panel = rgb(60, 110, 235),
	-- Inset wells / cards inside a panel (darker, white text >= 7:1).
	PanelLight = rgb(40, 78, 196),
	-- Neutral raised surfaces (secondary buttons, empty pips).
	PanelRaised = rgb(110, 160, 255),
	-- Outlines are solid ink, not translucent white.
	Stroke = rgb(30, 27, 75),
	Ink = rgb(30, 27, 75),
	Text = rgb(255, 255, 255),
	TextDim = rgb(222, 234, 255),
	TextMuted = rgb(186, 206, 250),
	-- Currencies and brand
	Essence = rgb(90, 232, 255),
	EssenceDeep = rgb(130, 110, 255),
	Accent = rgb(255, 111, 181),
	Success = rgb(88, 222, 96),
	Danger = rgb(255, 78, 96),
	Warning = rgb(255, 200, 60),
	Gold = rgb(255, 210, 63),
	Power = rgb(255, 154, 60),
	Shadow = rgb(16, 14, 48),
	Cream = rgb(255, 246, 229),
}

Theme.Transparency = {
	Panel = 0,
	PanelSoft = 0.15,
	-- Ink outlines are opaque.
	Stroke = 0,
	StrokeStrong = 0,
}

Theme.Radius = {
	Small = UDim.new(0, 10),
	Medium = UDim.new(0, 14),
	Large = UDim.new(0, 22),
	Pill = UDim.new(1, 0),
}

-- Outline thickness (px, before UI scaling).
Theme.Outline = {
	Thin = 2,
	Regular = 3,
	Thick = 4,
	Text = 2,
}

-- Height of the darker "lip" under chunky buttons (px).
Theme.Lip = 4

-- Button colour families: face (top), lip (shade below).
export type ButtonColors = { face: Color3, lip: Color3 }
Theme.Buttons = {
	green = { face = rgb(76, 217, 100), lip = rgb(38, 150, 70) },
	yellow = { face = rgb(255, 205, 50), lip = rgb(214, 146, 20) },
	orange = { face = rgb(255, 150, 50), lip = rgb(206, 96, 26) },
	red = { face = rgb(255, 84, 96), lip = rgb(188, 40, 64) },
	blue = { face = rgb(70, 170, 255), lip = rgb(36, 108, 214) },
	pink = { face = rgb(255, 111, 190), lip = rgb(206, 60, 140) },
	purple = { face = rgb(160, 110, 255), lip = rgb(110, 66, 210) },
	mint = { face = rgb(80, 225, 190), lip = rgb(36, 160, 140) },
	neutral = { face = rgb(110, 160, 255), lip = rgb(64, 104, 214) },
	gray = { face = rgb(160, 170, 205), lip = rgb(110, 118, 160) },
} :: { [string]: ButtonColors }

local BUILDER = "rbxasset://fonts/families/BuilderSans.json"
local FREDOKA = "rbxasset://fonts/families/FredokaOne.json"
local LUCKIEST = "rbxasset://fonts/families/LuckiestGuy.json"

-- Built-in Roblox font families only (no uploaded fonts).
Theme.FontFamilies = { BUILDER, FREDOKA, LUCKIEST }

Theme.Fonts = {
	Body = Font.new(BUILDER, Enum.FontWeight.Bold),
	BodyBold = Font.new(BUILDER, Enum.FontWeight.Heavy),
	-- Rounded display font: titles, buttons, numbers, captions.
	Heavy = Font.new(FREDOKA, Enum.FontWeight.Regular),
	Display = Font.new(FREDOKA, Enum.FontWeight.Regular),
	-- Comic burst font: rewards and short shouts ("+250", "NEW!"). Latin only.
	Burst = Font.new(LUCKIEST, Enum.FontWeight.Regular),
	-- Former sci-fi font, kept as an alias so older call sites stay rounded.
	Tech = Font.new(FREDOKA, Enum.FontWeight.Regular),
}

-- Plot accent colours, one per Sanctuary (index = plot index): candy brights.
Theme.PlotColors = {
	rgb(64, 200, 255),
	rgb(255, 96, 190),
	rgb(255, 200, 40),
	rgb(90, 222, 96),
	rgb(255, 140, 50),
	rgb(110, 130, 255),
	rgb(180, 100, 255),
	rgb(255, 76, 96),
}

-- Rarity presentation (UI only; the gameplay tiers live in Config/Rarities).
-- Stars make the tier readable without relying on colour alone.
Theme.RarityStars = {
	Common = 1,
	Uncommon = 2,
	Rare = 3,
	Epic = 4,
	Legendary = 5,
	Mythic = 6,
	Secret = 7,
}

return Theme
