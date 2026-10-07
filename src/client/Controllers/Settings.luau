--!strict
-- Applies player settings locally (quality, volumes, shake, language) and
-- persists changes through the server.

local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local Locale = require(Shared.Locale)
local Store = require(script.Parent.Store)
local ClientNet = require(script.Parent.Parent.ClientNet)

local Settings = {}

Settings.quality = "High"
Settings.sfx = 1
Settings.music = 0.6
Settings.shake = true
Settings.changed = Signal.new()

local PARTICLE_SCALE = { Low = 0.35, Medium = 0.65, High = 1 }
local LOD_SCALE = { Low = 0.6, Medium = 0.8, High = 1 }

function Settings.particleScale(): number
	return PARTICLE_SCALE[Settings.quality] or 1
end

function Settings.lodScale(): number
	return LOD_SCALE[Settings.quality] or 1
end

local function detectLanguage(): string
	local ok, localeId = pcall(function()
		return LocalizationService.RobloxLocaleId
	end)
	if ok and type(localeId) == "string" and localeId ~= "" then
		return Locale.fromLocaleId(localeId)
	end
	return Locale.fromLocaleId(Players.LocalPlayer.LocaleId)
end

local function apply(settings: { [string]: any })
	Settings.quality = settings.quality or "High"
	Settings.sfx = settings.sfx or 1
	Settings.music = settings.music or 0.6
	Settings.shake = settings.shake ~= false
	local language = settings.language
	if language == nil or language == "" then
		language = detectLanguage()
	end
	Locale.setLanguage(language)
	Settings.changed:Fire()
end

function Settings.init()
	Locale.setLanguage(detectLanguage())
	Store.changed:Connect(function(state, previous)
		local a, b = state.settings, previous.settings
		if a.quality ~= b.quality or a.sfx ~= b.sfx or a.music ~= b.music or a.shake ~= b.shake or a.language ~= b.language or not Store.ready then
			apply(a)
		end
	end)
	Store.becameReady:Connect(function()
		apply(Store.state.settings)
	end)
end

function Settings.set(key: string, value: any)
	local current = table.clone(Store.state.settings) :: any
	current[key] = value
	apply(current)
	ClientNet.fire(Net.Events.Settings, key, value)
end

return Settings
