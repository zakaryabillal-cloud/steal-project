--!strict
-- Number and time formatting shared by every UI surface.

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

-- 999 -> "999", 1234 -> "1.23K", 45678 -> "45.7K", 1250000 -> "1.25M"
function Format.abbrev(value: number): string
	if value ~= value then
		return "0"
	end
	local negative = value < 0
	local n = math.abs(value)
	if n < 1000 then
		local text: string
		if n < 10 and n ~= math.floor(n) then
			text = string.format("%.1f", math.floor(n * 10) / 10)
		else
			text = tostring(math.floor(n))
		end
		return (negative and "-" or "") .. text
	end
	local tier = math.min(math.floor(math.log10(n) / 3), #SUFFIXES - 1)
	local scaled = n / (1000 ^ tier)
	local text: string
	if scaled >= 100 then
		text = string.format("%d", math.floor(scaled))
	elseif scaled >= 10 then
		text = string.format("%.1f", math.floor(scaled * 10) / 10)
	else
		text = string.format("%.2f", math.floor(scaled * 100) / 100)
	end
	if string.find(text, ".", 1, true) then
		text = string.gsub(text, "0+$", "") :: string
		text = string.gsub(text, "%.$", "") :: string
	end
	return (negative and "-" or "") .. text .. SUFFIXES[tier + 1]
end

-- 1234567 -> "1,234,567"
function Format.commas(value: number): string
	local n = math.floor(math.abs(value))
	local text = tostring(n)
	local result = string.reverse(text)
	result = string.gsub(result, "(%d%d%d)", "%1,") :: string
	result = string.reverse(result)
	if string.sub(result, 1, 1) == "," then
		result = string.sub(result, 2)
	end
	return (value < 0 and "-" or "") .. result
end

-- 75 -> "1:15", 3725 -> "1:02:05"
function Format.clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	local h = math.floor(s / 3600)
	local m = math.floor((s % 3600) / 60)
	local sec = s % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, sec)
	end
	return string.format("%d:%02d", m, sec)
end

-- Short human duration: 45 -> "45s", 125 -> "2m", 7300 -> "2h"
function Format.short(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	if s < 60 then
		return s .. "s"
	elseif s < 3600 then
		return math.floor(s / 60) .. "m"
	end
	return math.floor(s / 3600) .. "h"
end

function Format.percent(fraction: number): string
	return string.format("%d%%", math.floor(fraction * 100 + 0.5))
end

function Format.stars(level: number, maxLevel: number): string
	return string.rep("★", level) .. string.rep("☆", math.max(0, maxLevel - level))
end

return Format
