--!strict
-- Server-wide Rift events. Gameplay modifiers are read by the server; the
-- `ambience` block drives client-side lighting/particles/sky.

export type Ambience = {
	tint: Color3,
	atmosphereColor: Color3,
	atmosphereDecay: Color3,
	atmosphereDensity: number,
	brightness: number,
	saturation: number,
	contrast: number,
	ambient: Color3,
	outdoorAmbient: Color3,
	riftColor: Color3,
	particleColor: Color3,
	-- "sparks" | "ash" | "gold" | "embers"
	weather: string,
}

export type EventDef = {
	id: string,
	weight: number,
	duration: number,
	color: Color3,
	spawnInterval: number?,
	maxActive: number?,
	-- Multiplies per-mutation chances, e.g. { Void = 8 }.
	mutationBoost: { [string]: number },
	-- Multiplies rarity weights, e.g. { Legendary = 2 }.
	rarityBoost: { [string]: number },
	-- Chance per spawn that the event's special relic replaces the roll.
	specialRelic: string?,
	specialChance: number?,
	ambience: Ambience,
}

local Events = {}

local list: { EventDef } = {
	{
		id = "RiftOverload",
		weight = 35,
		duration = 60,
		color = Color3.fromRGB(90, 230, 255),
		spawnInterval = 1.6,
		maxActive = 10,
		mutationBoost = { Charged = 3 },
		rarityBoost = {},
		ambience = {
			tint = Color3.fromRGB(230, 250, 255),
			atmosphereColor = Color3.fromRGB(170, 230, 255),
			atmosphereDecay = Color3.fromRGB(110, 190, 255),
			atmosphereDensity = 0.3,
			brightness = 0.06,
			saturation = 0.35,
			contrast = 0.1,
			ambient = Color3.fromRGB(110, 140, 170),
			outdoorAmbient = Color3.fromRGB(150, 190, 220),
			riftColor = Color3.fromRGB(90, 230, 255),
			particleColor = Color3.fromRGB(140, 240, 255),
			weather = "sparks",
		},
	},
	{
		id = "VoidStorm",
		weight = 25,
		duration = 75,
		color = Color3.fromRGB(150, 80, 255),
		mutationBoost = { Void = 8 },
		rarityBoost = {},
		ambience = {
			tint = Color3.fromRGB(235, 215, 255),
			atmosphereColor = Color3.fromRGB(190, 150, 255),
			atmosphereDecay = Color3.fromRGB(140, 100, 230),
			atmosphereDensity = 0.36,
			brightness = 0,
			saturation = 0.3,
			contrast = 0.12,
			ambient = Color3.fromRGB(110, 90, 150),
			outdoorAmbient = Color3.fromRGB(150, 120, 200),
			riftColor = Color3.fromRGB(150, 70, 255),
			particleColor = Color3.fromRGB(120, 60, 220),
			weather = "ash",
		},
	},
	{
		id = "GoldenSurge",
		weight = 25,
		duration = 75,
		color = Color3.fromRGB(255, 200, 70),
		mutationBoost = { Golden = 6 },
		rarityBoost = {},
		ambience = {
			tint = Color3.fromRGB(255, 245, 215),
			atmosphereColor = Color3.fromRGB(255, 220, 150),
			atmosphereDecay = Color3.fromRGB(255, 170, 90),
			atmosphereDensity = 0.3,
			brightness = 0.08,
			saturation = 0.35,
			contrast = 0.08,
			ambient = Color3.fromRGB(150, 130, 100),
			outdoorAmbient = Color3.fromRGB(200, 170, 130),
			riftColor = Color3.fromRGB(255, 200, 80),
			particleColor = Color3.fromRGB(255, 215, 110),
			weather = "gold",
		},
	},
	{
		id = "Eclipse",
		weight = 15,
		duration = 90,
		color = Color3.fromRGB(255, 80, 50),
		mutationBoost = { Corrupted = 4 },
		rarityBoost = { Epic = 1.5, Legendary = 2, Mythic = 2.5, Secret = 3 },
		specialRelic = "eclipse_sigil",
		specialChance = 0.06,
		ambience = {
			tint = Color3.fromRGB(255, 215, 205),
			atmosphereColor = Color3.fromRGB(255, 160, 150),
			atmosphereDecay = Color3.fromRGB(200, 90, 140),
			atmosphereDensity = 0.38,
			brightness = -0.04,
			saturation = 0.25,
			contrast = 0.15,
			ambient = Color3.fromRGB(110, 80, 100),
			outdoorAmbient = Color3.fromRGB(170, 120, 140),
			riftColor = Color3.fromRGB(255, 70, 40),
			particleColor = Color3.fromRGB(255, 110, 60),
			weather = "embers",
		},
	},
}

local byId: { [string]: EventDef } = {}
for _, def in list do
	byId[def.id] = def
end

Events.list = list
Events.byId = byId

function Events.get(id: string?): EventDef?
	if id == nil or id == "" then
		return nil
	end
	return byId[id]
end

return Events
