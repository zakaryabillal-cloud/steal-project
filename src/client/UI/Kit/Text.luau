--!strict
-- Turns a localisation key + raw server arguments into display RichText.
-- Argument conventions: relic/rarity/mutation/upgrade/tier are ids, time is
-- seconds, amount is a number, player-name fields are escaped and bolded.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Locale = require(Shared.Locale)
local Format = require(Shared.Util.Format)
local Relics = require(Shared.Config.Relics)
local Rarities = require(Shared.Config.Rarities)
local Mutations = require(Shared.Config.Mutations)
local Style = require(script.Parent.Style)

local Text = {}

local NAME_FIELDS = { thief = true, player = true, victim = true, name = true }

function Text.args(args: { [string]: any }?): { [string]: any }
	local out: { [string]: any } = {}
	if not args then
		return out
	end
	for key, value in args do
		if key == "relic" and type(value) == "string" then
			local def = Relics.get(value)
			local color = if def then Rarities.get(def.rarity).color else Style.Colors.Text
			out[key] = "<b>" .. Style.colored(Locale.relicName(value), color) .. "</b>"
		elseif key == "rarity" and type(value) == "string" then
			local rarity = Rarities.byId[value]
			out[key] = "<b>" .. Style.colored(Locale.rarity(value), if rarity then rarity.color else Style.Colors.Text) .. "</b>"
		elseif key == "mutation" and type(value) == "string" then
			local mutation = Mutations.get(value)
			out[key] = "<b>" .. Style.colored(Locale.mutation(value), if mutation then mutation.color else Style.Colors.Text) .. "</b>"
		elseif key == "upgrade" and type(value) == "string" then
			out[key] = "<b>" .. Locale.t("upgrade." .. value .. ".name") .. "</b>"
		elseif key == "tier" and type(value) == "number" then
			out[key] = "<b>" .. Locale.t("tier." .. value) .. "</b>"
		elseif key == "time" and type(value) == "number" then
			out[key] = Format.clock(value)
		elseif key == "amount" and type(value) == "number" then
			out[key] = "<b>" .. Format.abbrev(value) .. "</b>"
		elseif NAME_FIELDS[key] and type(value) == "string" then
			out[key] = "<b>" .. Style.escape(value) .. "</b>"
		else
			out[key] = value
		end
	end
	return out
end

function Text.format(key: string, args: { [string]: any }?): string
	return Locale.t(key, Text.args(args))
end

return Text
