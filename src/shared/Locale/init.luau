--!strict
-- Localization front-end. The client picks the language from the player's
-- Roblox locale (French for any fr-* locale, English otherwise) and can switch
-- at runtime from Settings.

local Signal = require(script.Parent.Util.Signal)
local Strings = require(script.Strings)

local Locale = {}

local tables: { [string]: { [string]: string } } = Strings :: any

Locale.languages = { "en", "fr" }
Locale.language = "en"
Locale.changed = Signal.new()

function Locale.setLanguage(language: string)
	if tables[language] == nil then
		language = "en"
	end
	if language ~= Locale.language then
		Locale.language = language
		Locale.changed:Fire(language)
	end
end

function Locale.fromLocaleId(localeId: string): string
	local prefix = string.lower(string.sub(localeId, 1, 2))
	if tables[prefix] then
		return prefix
	end
	return "en"
end

function Locale.has(key: string): boolean
	return tables.en[key] ~= nil
end

function Locale.t(key: string, args: { [string]: any }?): string
	local text = tables[Locale.language][key] or tables.en[key] or key
	if args then
		text = string.gsub(text, "{(%w+)}", function(name: string): string
			local value = args[name]
			if value == nil then
				return "{" .. name .. "}"
			end
			return tostring(value)
		end) :: string
	end
	return text
end

function Locale.relicName(relicId: string): string
	return Locale.t("relic." .. relicId .. ".name")
end

function Locale.relicLore(relicId: string): string
	return Locale.t("relic." .. relicId .. ".lore")
end

function Locale.rarity(rarityId: string): string
	return Locale.t("rarity." .. rarityId)
end

function Locale.mutation(mutationId: string): string
	return Locale.t("mutation." .. mutationId)
end

-- Full display name: "Golden Storm Crystal" / "Cristal Tempête Dorée"
function Locale.relicTitle(relicId: string, mutation: string?): string
	local name = Locale.relicName(relicId)
	if mutation == nil or mutation == "" then
		return name
	end
	if Locale.language == "fr" then
		return name .. " " .. Locale.mutation(mutation)
	end
	return Locale.mutation(mutation) .. " " .. name
end

-- Expose raw tables for tooling/tests.
Locale._tables = tables

return Locale
