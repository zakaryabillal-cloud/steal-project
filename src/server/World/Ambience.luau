--!strict
-- Applies the sunny "Cartoon & Goofy" ambience (Config/Palette) at server
-- start: lighting, atmosphere, sky, clouds and post effects. The same values
-- are mirrored in default.project.json so Edit mode looks like Play mode
-- (tests/scenarios/V2ArtDirection.luau checks that both agree).
-- Clients tint this base during Rift events (Controllers/LightingFX).

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Palette = require(ReplicatedStorage.Shared.Config.Palette)

local Ambience = {}

local function ensure(parent: Instance, className: string, name: string): Instance
	local existing = parent:FindFirstChildOfClass(className)
	if existing then
		return existing
	end
	local created = Instance.new(className)
	created.Name = name
	created.Parent = parent
	return created
end

local function apply(target: Instance, values: { [string]: any })
	for key, value in values do
		(target :: any)[key] = value
	end
end

function Ambience.apply()
	apply(Lighting, Palette.Lighting)
	Lighting.GlobalShadows = true
	apply(ensure(Lighting, "Atmosphere", "Atmosphere"), Palette.Atmosphere)
	apply(ensure(Lighting, "Sky", "Sky"), Palette.Sky)
	apply(ensure(Lighting, "BloomEffect", "Bloom"), Palette.Effects.Bloom)
	apply(ensure(Lighting, "ColorCorrectionEffect", "ColorCorrection"), Palette.Effects.ColorCorrection)
	apply(ensure(Lighting, "SunRaysEffect", "SunRays"), Palette.Effects.SunRays)
	apply(ensure(Lighting, "DepthOfFieldEffect", "DepthOfField"), Palette.Effects.DepthOfField)
	apply(ensure(workspace.Terrain, "Clouds", "Clouds"), Palette.Clouds)
end

return Ambience
