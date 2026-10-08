--!strict
-- Emoji used by the interface (Phase 5.5). Only glyphs that Roblox draws in
-- colour on every platform are allowed:
--   * a single code point (no variation selector U+FE0F, no ZWJ sequence),
--   * default emoji presentation (Emoji_Presentation = Yes),
--   * Unicode 10.0 or older.
-- Anything else (gear, shield, snowflake, sun, heart...) is drawn with frames
-- in UI/Kit/Icons instead. tests/scenarios/V2ArtDirection.luau scans every
-- source file and fails on an emoji that is not listed here.

local Emoji = {}

Emoji.Glyphs = table.freeze({
	-- Menus and HUD
	upgrades = "🚀",
	dex = "📖",
	style = "🎨",
	settings = "🔧",
	loadout = "🎒",
	goal = "🎯",
	gem = "💎",
	power = "⚡",
	home = "🏠",
	carry = "🎒",
	alarm = "🚨",
	-- States
	locked = "🔒",
	equipped = "✅",
	new = "🆕",
	ready = "✨",
	nope = "❌",
	time = "⏳",
	-- Rewards and moments
	star = "⭐",
	party = "🎉",
	trophy = "🏆",
	crown = "👑",
	gift = "🎁",
	fire = "🔥",
	boom = "💥",
	swirl = "🌀",
	rainbow = "🌈",
	eyes = "👀",
	money = "💰",
	thumbs = "👍",
	wave = "👋",
	idea = "💡",
	-- Statuses
	strong = "💪",
	ghost = "👻",
	dizzy = "💫",
	snail = "🐌",
	sprout = "🌱",
	-- Events and settings
	moon = "🌙",
	sun = "🌞",
	candy = "🍭",
	music = "🎵",
	sound = "🔊",
	globe = "🌍",
	camera = "🎥",
	snowman = "⛄",
})

-- Every allowed code point (built from Glyphs, plus a few spare ones).
local allowed: { [number]: boolean } = {}
for _, glyph in Emoji.Glyphs do
	for _, codepoint in utf8.codes(glyph :: string) do
		allowed[codepoint] = true
	end
end
Emoji.Allowed = table.freeze(allowed)

-- Emoji whose default presentation is text (monochrome or missing without
-- U+FE0F on some devices): never use them, draw an icon instead.
Emoji.Unreliable = table.freeze({
	[0x2699] = "gear",
	[0x1F6E1] = "shield",
	[0x2744] = "snowflake",
	[0x2600] = "sun",
	[0x2601] = "cloud",
	[0x2764] = "heart",
	[0x2694] = "swords",
	[0x270F] = "pencil",
	[0x2B06] = "up arrow",
	[0x2714] = "check mark",
	[0x26A0] = "warning",
	[0x2763] = "heart exclamation",
	[0x1F5E1] = "dagger",
	[0x1F3F3] = "flag",
	[0x1F32A] = "tornado",
	[0x1F327] = "rain cloud",
})

function Emoji.get(key: string): string
	return Emoji.Glyphs[key] or ""
end

-- "🎨 Style" (or just the label when the key is unknown).
function Emoji.label(key: string, text: string): string
	local glyph = Emoji.Glyphs[key]
	return if glyph then glyph .. " " .. text else text
end

return table.freeze(Emoji)
