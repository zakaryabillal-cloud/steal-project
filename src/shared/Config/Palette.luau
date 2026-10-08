--!strict
-- World art palette (Phase 5.5 "Cartoon & Goofy"). One source of truth for the
-- island's colours, terrain colours, part materials and the daytime lighting.
-- UI colours live in Config/Theme; docs/ART_DIRECTION.md explains the rules.
--
-- Everything here is purely visual: no gameplay code reads it.

local Palette = {}

local rgb = Color3.fromRGB

-- Brand colours (shared with the UI tokens and the art direction doc).
Palette.Core = table.freeze({
	Sky = rgb(110, 200, 255),
	Grass = rgb(98, 214, 92),
	Sunny = rgb(255, 210, 63),
	Bubblegum = rgb(255, 111, 181),
	Grape = rgb(155, 107, 255),
	Tangerine = rgb(255, 154, 60),
	Mint = rgb(95, 227, 192),
	Cherry = rgb(255, 79, 94),
	Cream = rgb(255, 246, 229),
	Ink = rgb(30, 27, 75),
})

-- Structural colours used by the world builders (exposed as Layout.Colors).
Palette.World = table.freeze({
	-- Paths, ruins, pillars: warm biscuit.
	Stone = rgb(255, 222, 170),
	-- Foundations, piers, monoliths: periwinkle.
	StoneDark = rgb(140, 150, 245),
	-- Floors, caps, light trims: cream.
	StoneLight = rgb(255, 245, 226),
	-- Railings, lantern caps, ledges: sunny yellow.
	Trim = rgb(255, 208, 72),
	Wood = rgb(214, 128, 74),
	-- The Rift's signature colour: bubblegum magenta, core white.
	Rift = rgb(255, 92, 206),
	RiftCore = rgb(255, 255, 255),
	-- Vegetation.
	Leaf = rgb(98, 214, 92),
	LeafDark = rgb(56, 178, 80),
	Trunk = rgb(196, 120, 70),
	-- Accents for lamps and small glows.
	LampGlow = rgb(255, 236, 150),
	Water = rgb(64, 205, 255),
})

-- Candy-coloured canopies (trees, bushes) and decorative crystals.
Palette.Canopies = table.freeze({
	table.freeze({ canopy = rgb(255, 128, 196), fruit = rgb(255, 238, 120) }),
	table.freeze({ canopy = rgb(98, 214, 92), fruit = rgb(255, 92, 110) }),
	table.freeze({ canopy = rgb(255, 186, 72), fruit = rgb(255, 255, 255) }),
	table.freeze({ canopy = rgb(130, 200, 255), fruit = rgb(255, 150, 220) }),
})
Palette.Crystals = table.freeze({ rgb(196, 140, 255), rgb(110, 225, 255), rgb(255, 150, 220) })
Palette.Flowers = table.freeze({ rgb(255, 92, 120), rgb(255, 214, 64), rgb(255, 150, 220), rgb(150, 120, 255), rgb(255, 255, 255) })

-- Terrain material colours (Terrain:SetMaterialColor).
Palette.Terrain = table.freeze({
	Grass = rgb(98, 214, 92),
	LeafyGrass = rgb(70, 192, 86),
	Rock = rgb(168, 150, 240),
	Slate = rgb(196, 168, 255),
	Cobblestone = rgb(255, 226, 172),
	Pavement = rgb(255, 214, 150),
	Sand = rgb(255, 232, 160),
	Ground = rgb(214, 156, 104),
	Basalt = rgb(122, 104, 206),
	Limestone = rgb(255, 246, 226),
	CrackedLava = rgb(255, 128, 60),
})

Palette.Water = table.freeze({
	Color = rgb(64, 205, 255),
	Transparency = 0.55,
	Reflectance = 0.35,
	WaveSize = 0.1,
	WaveSpeed = 8,
})

-- Realistic materials are drawn as clean toy plastic. Neon, Glass, ForceField,
-- Grass (floating islets) and every material not listed are kept.
Palette.Stylize = table.freeze({
	[Enum.Material.Slate] = Enum.Material.SmoothPlastic,
	[Enum.Material.Marble] = Enum.Material.SmoothPlastic,
	[Enum.Material.Cobblestone] = Enum.Material.SmoothPlastic,
	[Enum.Material.Granite] = Enum.Material.SmoothPlastic,
	[Enum.Material.Concrete] = Enum.Material.SmoothPlastic,
	[Enum.Material.Brick] = Enum.Material.SmoothPlastic,
	[Enum.Material.Basalt] = Enum.Material.SmoothPlastic,
	[Enum.Material.Pebble] = Enum.Material.SmoothPlastic,
	[Enum.Material.Metal] = Enum.Material.SmoothPlastic,
	[Enum.Material.DiamondPlate] = Enum.Material.SmoothPlastic,
	[Enum.Material.CorrodedMetal] = Enum.Material.SmoothPlastic,
	[Enum.Material.Wood] = Enum.Material.SmoothPlastic,
	[Enum.Material.WoodPlanks] = Enum.Material.SmoothPlastic,
	[Enum.Material.Rock] = Enum.Material.SmoothPlastic,
})

function Palette.material(material: Enum.Material): Enum.Material
	return Palette.Stylize[material] or material
end

-- Sunny-afternoon lighting, applied by the server at start (World/Ambience)
-- and mirrored in default.project.json for Edit mode.
Palette.Lighting = table.freeze({
	ClockTime = 14.3,
	GeographicLatitude = 23,
	Brightness = 3,
	Ambient = rgb(120, 118, 150),
	OutdoorAmbient = rgb(156, 160, 190),
	ColorShift_Top = rgb(255, 242, 214),
	ColorShift_Bottom = rgb(90, 110, 160),
	EnvironmentDiffuseScale = 0.8,
	EnvironmentSpecularScale = 0.25,
	ExposureCompensation = 0.1,
	ShadowSoftness = 0.55,
})

Palette.Atmosphere = table.freeze({
	Density = 0.24,
	Offset = 0.12,
	Color = rgb(196, 226, 255),
	Decay = rgb(140, 190, 255),
	Glare = 0.18,
	Haze = 0.7,
})

Palette.Sky = table.freeze({
	StarCount = 0,
	CelestialBodiesShown = true,
	SunAngularSize = 21,
	MoonAngularSize = 11,
})

Palette.Clouds = table.freeze({
	Cover = 0.58,
	Density = 0.42,
	Color = rgb(255, 255, 255),
})

Palette.Effects = table.freeze({
	Bloom = table.freeze({ Intensity = 0.55, Size = 24, Threshold = 1.9 }),
	ColorCorrection = table.freeze({ Brightness = 0.04, Contrast = 0.08, Saturation = 0.28, TintColor = rgb(255, 251, 244) }),
	SunRays = table.freeze({ Intensity = 0.05, Spread = 0.55 }),
	DepthOfField = table.freeze({ FarIntensity = 0.05, FocusDistance = 120, InFocusRadius = 200, NearIntensity = 0 }),
})

return table.freeze(Palette)
