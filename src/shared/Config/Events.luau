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
			tint = Color3.fromRGB(225, 250, 255),
			atmosphereColor = Color3.fromRGB(110, 190, 230),
			atmosphereDecay = Color3.fromRGB(40, 90, 160),
			atmosphereDensity = 0.36,
			brightness = 0.05,
			saturation = 0.3,
			contrast = 0.16,
			ambient = Color3.fromRGB(40, 60, 90),
			outdoorAmbient = Color3.fromRGB(100, 150, 190),
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
			tint = Color3.fromRGB(220, 200, 255),
			atmosphereColor = Color3.fromRGB(70, 30, 120),
			atmosphereDecay = Color3.fromRGB(30, 10, 70),
			atmosphereDensity = 0.45,
			brightness = -0.04,
			saturation = 0.1,
			contrast = 0.22,
			ambient = Color3.fromRGB(30, 15, 55),
			outdoorAmbient = Color3.fromRGB(80, 50, 130),
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
			tint = Color3.fromRGB(255, 240, 215),
			atmosphereColor = Color3.fromRGB(230, 170, 110),
			atmosphereDecay = Color3.fromRGB(150, 80, 60),
			atmosphereDensity = 0.34,
			brightness = 0.06,
			saturation = 0.28,
			contrast = 0.12,
			ambient = Color3.fromRGB(70, 50, 40),
			outdoorAmbient = Color3.fromRGB(170, 130, 100),
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
			tint = Color3.fromRGB(255, 205, 195),
			atmosphereColor = Color3.fromRGB(60, 20, 30),
			atmosphereDecay = Color3.fromRGB(120, 30, 20),
			atmosphereDensity = 0.5,
			brightness = -0.08,
			saturation = 0.05,
			contrast = 0.28,
			ambient = Color3.fromRGB(35, 15, 20),
			outdoorAmbient = Color3.fromRGB(90, 45, 50),
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
