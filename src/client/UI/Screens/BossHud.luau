--!strict
-- Boss fight HUD (V2 phase 6), Cartoon & Goofy (docs/ART_DIRECTION.md):
--   * a big Health pill with the boss's little head, his mood ("GRUMPY",
--     "ANGRY!", "RED AS A TOMATO!"), phase notches and the 3:30 timer;
--   * our hearts (drawn hearts, not numbers), the attack hint banner
--     ("Broom wave: JUMP!") during every telegraph, "DIZZY! Hit him now!";
--   * the big STRIKE button (touch; also shown on PC / gamepad with its key)
--     and a small red Leave button;
--   * the waiting room card (countdown, ready count, READY! button);
--   * the results card (victory / oops, time, our hits, rewards) shown even
--     to players already sent back after a KO.
-- Display only: every number comes from replicated attributes / server FX.
--
-- Phase 7A: everything follows the boss of the arena (bar colours, head,
-- phase notches, "2/3" phase indicator, per-boss texts), big specials get a
-- "SPECIAL ATTACK!" banner + a pulsing red screen edge until they hit, and
-- the safe arrow also points to Forgeheart's green rocks.
-- Phase 7B: the Tempest Seraph's sky-blue bar and little cloud head with its
-- crooked crown; the safe arrow points to her lit cloud shelters (spots).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Bosses = require(Shared.Config.Bosses)
local Materials = require(Shared.Config.Materials)
local Theme = require(Shared.Config.Theme)
local Emoji = require(Shared.Config.Emoji)
local Locale = require(Shared.Locale)
local Format = require(Shared.Util.Format)

local Kit = script.Parent.Parent.Kit
local Create = require(Kit.Create)
local Style = require(Kit.Style)
local Tween = require(Kit.Tween)
local Button = require(Kit.Button)
local TouchSafe = require(Kit.TouchSafe)
local Juice = require(Kit.Juice)

local Controllers = script.Parent.Parent.Parent.Controllers
local Boss = require(Controllers.Boss)
local Audio = require(Controllers.Audio)
local BossFX = require(Controllers.BossFX)

local BossHud = {}

local JELLY = Color3.fromRGB(176, 110, 255)
-- Bar colours per boss (panel, fill from, fill to).
local BAR_COLORS: { [string]: { Color3 } } = {
	VoidWarden = { Color3.fromRGB(110, 70, 210), Color3.fromRGB(255, 120, 220), JELLY },
	Forgeheart = { Color3.fromRGB(196, 84, 44), Color3.fromRGB(255, 220, 90), Color3.fromRGB(255, 110, 40) },
	TempestSeraph = { Color3.fromRGB(70, 120, 210), Color3.fromRGB(255, 230, 90), Color3.fromRGB(110, 180, 255) },
}
local HEART = Color3.fromRGB(255, 96, 140)
local HEART_LOST = Color3.fromRGB(150, 156, 186)

local localPlayer = Players.LocalPlayer
local root: Frame
local resultsLayer: Instance
local hpFill: Frame
local barPanel: Frame
local barHead: Frame? = nil
local hpTrack: Frame
local notches: { Frame } = {}
local shownBoss = ""
local specialEdge: Frame
local specialUntil = 0
local hpLabel: TextLabel
local nameLabel: TextLabel
local moodLabel: TextLabel
local timerLabel: TextLabel
local banner: TextLabel
local bannerUntil = 0
local hearts: { Frame } = {}
local heartRow: Frame
local strikeButton: Button.Button
local strikeCooldown: Frame
local strikeKey: TextLabel
local leaveButton: Button.Button
local waiting: Frame
local waitingTitle: TextLabel
local waitingCount: TextLabel
local readyButton: Button.Button
local results: Frame? = nil
local topStack: GuiObject? = nil
local shownHearts = -1
local comboPips: { Frame } = {}
local strikeEmoji: TextLabel
local safeArrow: Frame
local safeArrowGlyph: TextLabel
local safeArrowText: TextLabel
local jumpHint: TextLabel
local isTouch = false

-- Layout (phase 6.5): the big Strike button sits LEFT of the ability
-- cluster (Hud), bottom-aligned with it, never on top of it; hearts sit
-- under the Health pill; Leave sits next to the pill (the player list owns
-- the top-right corner). Exposed for the overlap tests.
BossHud.Layout = table.freeze({
	-- Touch: the Y offset follows the ability cluster (BossHud.setTouchBottom).
	strikeTouch = table.freeze({ size = 120, position = UDim2.new(1, -272, 1, -TouchSafe.DefaultBottom) }),
	strikePc = table.freeze({ size = 104, position = UDim2.new(1, -284, 1, -26) }),
	hearts = table.freeze({ size = Vector2.new(200, 42), position = UDim2.new(0.5, 0, 0, 100) }),
	leave = table.freeze({ size = Vector2.new(110, 46), position = UDim2.new(0.5, 262, 0, 14) }),
	bar = table.freeze({ size = Vector2.new(500, 84), position = UDim2.new(0.5, 0, 0, 10) }),
})

----------------------------------------------------------------------------
-- Little drawings
----------------------------------------------------------------------------

-- Cartoon heart from two circles and a rotated square.
local function heartIcon(parent: Instance, order: number): Frame
	local frame: Frame = Create("Frame", { Name = "Heart" .. order, Size = UDim2.fromOffset(40, 38), BackgroundTransparency = 1, LayoutOrder = order, Parent = parent })
	local function piece(size: UDim2, position: UDim2, rotation: number, round: boolean)
		local p: Frame = Create("Frame", {
			Name = "Piece",
			Size = size,
			Position = position,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = rotation,
			BackgroundColor3 = HEART,
			Parent = frame,
		})
		if round then
			Style.corner(p, UDim.new(1, 0))
		else
			Style.corner(p, UDim.new(0, 4))
		end
		Style.stroke(p, Theme.Colors.Ink, 0, 2)
	end
	piece(UDim2.fromOffset(22, 22), UDim2.fromOffset(20, 25), 45, false)
	piece(UDim2.fromOffset(20, 20), UDim2.fromOffset(12, 14), 0, true)
	piece(UDim2.fromOffset(20, 20), UDim2.fromOffset(28, 14), 0, true)
	-- Cover the inner outlines with a borderless centre.
	local center: Frame = Create("Frame", { Size = UDim2.fromOffset(18, 14), Position = UDim2.fromOffset(20, 21), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = HEART, BorderSizePixel = 0, Name = "Center", Parent = frame })
	Style.corner(center, UDim.new(0, 6))
	return frame
end

local function paintHeart(frame: Frame, full: boolean)
	for _, child in frame:GetChildren() do
		if child:IsA("Frame") then
			child.BackgroundColor3 = if full then HEART else HEART_LOST
		end
	end
end

-- Forgeheart's little head: a round boulder, rocky brows, glowing mouth.
local function forgeheartHead(parent: Instance, size: number): Frame
	local head: Frame = Create("Frame", { Name = "BossHead", Size = UDim2.fromOffset(size, size), BackgroundColor3 = Color3.fromRGB(176, 106, 82), Parent = parent })
	Style.corner(head, UDim.new(1, 0))
	Style.stroke(head, Theme.Colors.Ink, 0, 3)
	Style.shade(head, 0.15)
	for k, spec in { { 0.3, 0.1, 0.2 }, { 0.55, 0.04, 0.16 }, { 0.74, 0.12, 0.13 } } do
		local drip: Frame = Create("Frame", { Name = "Lava" .. k, Size = UDim2.fromScale(spec[3], spec[3]), Position = UDim2.fromScale(spec[1], spec[2]), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(255, 160, 50), Parent = head })
		Style.corner(drip, UDim.new(1, 0))
	end
	for _, side in { -1, 1 } do
		local eye: Frame = Create("Frame", { Size = UDim2.fromScale(0.28, 0.28), Position = UDim2.fromScale(0.5 + side * 0.17, 0.45), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.new(1, 1, 1), Parent = head })
		Style.corner(eye, UDim.new(1, 0))
		Style.stroke(eye, Theme.Colors.Ink, 0, 2)
		local pupil: Frame = Create("Frame", { Size = UDim2.fromScale(0.45, 0.45), Position = UDim2.fromScale(0.5, 0.6), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Theme.Colors.Ink, Parent = eye })
		Style.corner(pupil, UDim.new(1, 0))
		local brow: Frame = Create("Frame", { Size = UDim2.fromScale(0.3, 0.09), Position = UDim2.fromScale(0.5 + side * 0.17, 0.27), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = side * 18, BackgroundColor3 = Color3.fromRGB(110, 66, 64), Parent = head })
		Style.corner(brow, UDim.new(1, 0))
	end
	local mouth: Frame = Create("Frame", { Size = UDim2.fromScale(0.46, 0.12), Position = UDim2.fromScale(0.5, 0.76), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(255, 200, 80), Parent = head })
	Style.corner(mouth, UDim.new(0, 3))
	Style.stroke(mouth, Color3.fromRGB(110, 66, 64), 0, 2)
	return head
end

-- The Tempest Seraph's little head (phase 7B): a puffy cloud (puffs behind
-- the face), big diva eyes, a smug little mouth and a golden crown worn
-- crooked. The frame itself is an invisible holder (same size as the others).
local function tempestHead(parent: Instance, size: number): Frame
	local head: Frame = Create("Frame", { Name = "BossHead", Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, Parent = parent })
	local cloud = Color3.fromRGB(240, 238, 255)
	for k, spec in { { 0.1, 0.62, 0.46 }, { 0.9, 0.62, 0.46 }, { 0.3, 0.2, 0.5 }, { 0.68, 0.18, 0.46 } } do
		local puff: Frame = Create("Frame", { Name = "Puff" .. k, Size = UDim2.fromScale(spec[3], spec[3]), Position = UDim2.fromScale(spec[1], spec[2]), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = if k <= 2 then Color3.fromRGB(214, 202, 255) else cloud, ZIndex = 1, Parent = head })
		Style.corner(puff, UDim.new(1, 0))
		Style.stroke(puff, Theme.Colors.Ink, 0, 3)
	end
	local face: Frame = Create("Frame", { Name = "Face", Size = UDim2.fromScale(0.84, 0.74), Position = UDim2.fromScale(0.5, 0.56), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = cloud, ZIndex = 2, Parent = head })
	Style.corner(face, UDim.new(1, 0))
	Style.stroke(face, Theme.Colors.Ink, 0, 3)
	Style.shade(face, 0.12)
	for _, side in { -1, 1 } do
		local eye: Frame = Create("Frame", { Size = UDim2.fromScale(0.3, 0.4), Position = UDim2.fromScale(0.5 + side * 0.18, 0.44), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.new(1, 1, 1), Parent = face })
		Style.corner(eye, UDim.new(1, 0))
		Style.stroke(eye, Theme.Colors.Ink, 0, 2)
		local pupil: Frame = Create("Frame", { Size = UDim2.fromScale(0.5, 0.42), Position = UDim2.fromScale(0.5 + side * 0.08, 0.62), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Theme.Colors.Ink, Parent = eye })
		Style.corner(pupil, UDim.new(1, 0))
		-- Diva eyeliner flick.
		local lash: Frame = Create("Frame", { Size = UDim2.fromScale(0.14, 0.05), Position = UDim2.fromScale(0.5 + side * 0.34, 0.24), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = side * 35, BackgroundColor3 = Theme.Colors.Ink, Parent = face })
		Style.corner(lash, UDim.new(1, 0))
		local cheek: Frame = Create("Frame", { Size = UDim2.fromScale(0.16, 0.09), Position = UDim2.fromScale(0.5 + side * 0.33, 0.7), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(255, 150, 196), BackgroundTransparency = 0.3, Parent = face })
		Style.corner(cheek, UDim.new(1, 0))
	end
	local mouth: Frame = Create("Frame", { Size = UDim2.fromScale(0.26, 0.07), Position = UDim2.fromScale(0.54, 0.8), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = -8, BackgroundColor3 = Theme.Colors.Ink, Parent = face })
	Style.corner(mouth, UDim.new(1, 0))
	-- The crown, worn crooked: a band and three gold tips.
	local crown: Frame = Create("Frame", { Name = "Crown", Size = UDim2.fromScale(0.46, 0.17), Position = UDim2.fromScale(0.64, 0.12), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = 18, BackgroundColor3 = Theme.Colors.Gold, ZIndex = 3, Parent = head })
	Style.corner(crown, UDim.new(0, 3))
	Style.stroke(crown, Theme.Colors.Ink, 0, 2)
	for k = 1, 3 do
		-- Square diamonds (the band is 0.46 x 0.17 of the head).
		local tip: Frame = Create("Frame", { Name = "Tip" .. k, Size = UDim2.fromScale(0.2, 0.54), Position = UDim2.fromScale(0.2 + (k - 1) * 0.3, -0.1), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = 45, BackgroundColor3 = Theme.Colors.Gold, ZIndex = 2, Parent = crown })
		Style.stroke(tip, Theme.Colors.Ink, 0, 2)
	end
	local gem: Frame = Create("Frame", { Name = "Gem", Size = UDim2.fromScale(0.2, 0.6), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(255, 96, 170), ZIndex = 4, Parent = crown })
	Style.corner(gem, UDim.new(1, 0))
	return head
end

-- The boss's little head (for the Health pill and the results card).
function BossHud.bossHead(parent: Instance, size: number, bossId: string?): Frame
	if bossId == "Forgeheart" then
		return forgeheartHead(parent, size)
	elseif bossId == "TempestSeraph" then
		return tempestHead(parent, size)
	end
	local head: Frame = Create("Frame", { Name = "BossHead", Size = UDim2.fromOffset(size, size), BackgroundColor3 = JELLY, Parent = parent })
	Style.corner(head, UDim.new(0, math.floor(size * 0.25)))
	Style.stroke(head, Theme.Colors.Ink, 0, 3)
	Style.shade(head, 0.15)
	local cap: Frame = Create("Frame", { Size = UDim2.new(1, 0, 0.24, 0), BackgroundColor3 = Color3.fromRGB(70, 128, 240), Parent = head })
	Style.corner(cap, UDim.new(0, math.floor(size * 0.2)))
	for _, side in { -1, 1 } do
		local eye: Frame = Create("Frame", { Size = UDim2.fromScale(0.32, 0.32), Position = UDim2.fromScale(0.5 + side * 0.18, 0.44), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.new(1, 1, 1), Parent = head })
		Style.corner(eye, UDim.new(1, 0))
		Style.stroke(eye, Theme.Colors.Ink, 0, 2)
		local pupil: Frame = Create("Frame", { Size = UDim2.fromScale(0.45, 0.45), Position = UDim2.fromScale(0.5, 0.6), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Theme.Colors.Ink, Parent = eye })
		Style.corner(pupil, UDim.new(1, 0))
	end
	local stache: Frame = Create("Frame", { Size = UDim2.fromScale(0.5, 0.13), Position = UDim2.fromScale(0.5, 0.74), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Theme.Colors.Ink, Parent = head })
	Style.corner(stache, UDim.new(1, 0))
	return head
end

----------------------------------------------------------------------------
-- Build
----------------------------------------------------------------------------

local function buildTop()
	local panel = Style.panel({
		Name = "BossBar",
		Size = UDim2.fromOffset(500, 84),
		Position = UDim2.new(0.5, 0, 0, 10),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(110, 70, 210),
		Parent = root,
	})
	barPanel = panel
	nameLabel = Style.display({ Name = "BossName", Size = UDim2.new(0, 170, 0, 26), Position = UDim2.fromOffset(82, 6), TextSize = 22, Parent = panel })
	-- Mood with the phase indicator ("2/3 ANGRY!").
	moodLabel = Style.text({ Name = "Mood", Size = UDim2.new(0, 230, 0, 26), Position = UDim2.new(1, -96, 0, 6), AnchorPoint = Vector2.new(1, 0), TextXAlignment = Enum.TextXAlignment.Right, TextSize = 17, FontFace = Theme.Fonts.Display, TextColor3 = Theme.Colors.Gold, Parent = panel })
	Style.ink(moodLabel, 2)
	-- Health track with the phase notches.
	local track: Frame = Create("Frame", { Name = "Track", Size = UDim2.new(1, -176, 0, 30), Position = UDim2.fromOffset(82, 40), BackgroundColor3 = Theme.Colors.Ink, Parent = panel })
	hpTrack = track
	Style.corner(track, UDim.new(1, 0))
	Style.stroke(track, Theme.Colors.Ink, 0, 3)
	hpFill = Create("Frame", { Name = "Fill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), Parent = track })
	Style.corner(hpFill, UDim.new(1, 0))
	Style.gradient(hpFill, Color3.fromRGB(255, 120, 220), JELLY, 0)
	Style.gloss(hpFill, 2)
	hpLabel = Style.text({ Name = "Percent", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 18, FontFace = Theme.Fonts.Display, ZIndex = 5, Parent = track })
	Style.ink(hpLabel, 2)
	local timerPill, label = Style.pill({ name = "Timer", text = "3:30", color = Theme.Colors.Warning, size = UDim2.fromOffset(78, 34), position = UDim2.new(1, -10, 0, 38), anchor = Vector2.new(1, 0), textSize = 20, parent = panel })
	local _ = timerPill
	timerLabel = label

	banner = Style.display({
		Name = "AttackBanner",
		Size = UDim2.fromOffset(640, 54),
		Position = UDim2.new(0.5, 0, 0, 148),
		AnchorPoint = Vector2.new(0.5, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 34,
		TextColor3 = Color3.fromRGB(255, 226, 90),
		Visible = false,
		Parent = root,
	})
	Create("UIScale", { Parent = banner })

	-- Special attacks: a pulsing red screen edge until the hit.
	specialEdge = Create("Frame", { Name = "SpecialEdge", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = root })
	Style.stroke(specialEdge, Color3.fromRGB(255, 70, 90), 0, 14)

	-- "JUMP!" when a broom wave is about to reach you.
	jumpHint = Style.text({
		Name = "JumpHint",
		Size = UDim2.fromOffset(360, 70),
		Position = UDim2.new(0.5, 0, 0.62, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "",
		TextSize = 56,
		FontFace = Theme.Fonts.Display,
		TextColor3 = Color3.fromRGB(255, 120, 120),
		Visible = false,
		Parent = root,
	})
	Style.ink(jumpHint, 4)

	-- Arrow toward the safe quarter of the Big Cleanup.
	safeArrow = Create("Frame", { Name = "SafeArrow", Size = UDim2.fromOffset(230, 120), Position = UDim2.new(0.5, 0, 0.36, 0), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Visible = false, Parent = root })
	safeArrowGlyph = Style.text({ Name = "Glyph", Size = UDim2.fromOffset(90, 90), Position = UDim2.new(0.5, 0, 0, 0), AnchorPoint = Vector2.new(0.5, 0), TextXAlignment = Enum.TextXAlignment.Center, Text = "➜", TextSize = 84, FontFace = Theme.Fonts.Display, TextColor3 = Color3.fromRGB(110, 255, 170), Parent = safeArrow })
	Style.ink(safeArrowGlyph, 4)
	safeArrowText = Style.text({ Name = "Text", Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 1, -30), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 22, FontFace = Theme.Fonts.Display, TextColor3 = Color3.fromRGB(110, 255, 170), Parent = safeArrow })
	Style.ink(safeArrowText, 2.5)
end

local function buildBottom(touch: boolean)
	isTouch = touch
	local L = BossHud.Layout
	heartRow = Create("Frame", { Name = "Hearts", Size = UDim2.fromOffset(L.hearts.size.X, L.hearts.size.Y), Position = L.hearts.position, AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 1, Parent = root })
	Style.list(heartRow, 6, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	for i = 1, Bosses.Combat.Hearts do
		table.insert(hearts, heartIcon(heartRow, i))
	end

	local spec = if touch then L.strikeTouch else L.strikePc
	local size = spec.size
	strikeButton = Button.new({
		name = "Strike",
		size = UDim2.fromOffset(size, size),
		position = spec.position,
		anchor = Vector2.new(1, 1),
		kind = "orange",
		corner = UDim.new(1, 0),
		parent = root,
		onClick = function()
			Boss.strike()
		end,
	})
	local emoji = Style.text({ Name = "Emoji", Size = UDim2.new(1, 0, 0.5, 0), Position = UDim2.fromScale(0, 0.08), TextXAlignment = Enum.TextXAlignment.Center, TextSize = math.floor(size * 0.34), FontFace = Theme.Fonts.Display, Text = Emoji.get("boom"), ZIndex = 4, Parent = strikeButton.content })
	emoji:SetAttribute("Emoji", true)
	strikeEmoji = emoji
	-- Combo pips (1-2-3) along the top of the button.
	local pips: Frame = Create("Frame", { Name = "Combo", Size = UDim2.fromOffset(60, 16), Position = UDim2.new(0.5, 0, 0, -10), AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 1, ZIndex = 7, Parent = strikeButton.instance })
	Style.list(pips, 4, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	for i = 1, 3 do
		local pip: Frame = Create("Frame", { Name = "Pip" .. i, Size = UDim2.fromOffset(16, 16), BackgroundColor3 = Theme.Colors.Cream, LayoutOrder = i, ZIndex = 7, Parent = pips })
		Style.corner(pip, UDim.new(1, 0))
		Style.stroke(pip, Theme.Colors.Ink, 0, 2)
		table.insert(comboPips, pip)
	end
	local caption = Style.display({ Name = "Caption", Size = UDim2.new(1, -8, 0.3, 0), Position = UDim2.new(0.5, 0, 0.6, 0), AnchorPoint = Vector2.new(0.5, 0), TextXAlignment = Enum.TextXAlignment.Center, TextSize = math.floor(size * 0.18), ZIndex = 4, Parent = strikeButton.content })
	caption.Text = Locale.t("boss.strike")
	strikeCooldown = Create("Frame", { Name = "Cooldown", Size = UDim2.fromScale(1, 0), Position = UDim2.fromScale(0, 1), AnchorPoint = Vector2.new(0, 1), BackgroundColor3 = Theme.Colors.Ink, BackgroundTransparency = 0.45, ZIndex = 5, Parent = strikeButton.content })
	Style.corner(strikeCooldown, UDim.new(1, 0))
	local chip: Frame = Create("Frame", { Name = "Key", Size = UDim2.fromOffset(40, 26), Position = UDim2.new(0.5, 0, 1, 10), AnchorPoint = Vector2.new(0.5, 1), BackgroundColor3 = Theme.Colors.Cream, ZIndex = 6, Visible = not touch, Parent = strikeButton.instance })
	Style.corner(chip, UDim.new(0, 8))
	Style.stroke(chip, Theme.Colors.Ink, 0, Theme.Outline.Thin)
	strikeKey = Style.text({ Text = "E", TextXAlignment = Enum.TextXAlignment.Center, TextSize = 15, FontFace = Theme.Fonts.Heavy, TextColor3 = Theme.Colors.Ink, ZIndex = 7, Parent = chip })

	leaveButton = Button.new({
		name = "Leave",
		size = UDim2.fromOffset(120, 46),
		position = L.leave.position,
		anchor = Vector2.new(0, 0),
		kind = "red",
		corner = Theme.Radius.Large,
		text = Locale.t("boss.leave"),
		textSize = 18,
		parent = root,
		onClick = function()
			Boss.leave()
		end,
	})

	-- Waiting room card.
	waiting = Style.panel({ Name = "Waiting", Size = UDim2.fromOffset(440, 150), Position = UDim2.new(0.5, 0, 0, 104), AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = Color3.fromRGB(110, 70, 210), Visible = false, Parent = root })
	waitingTitle = Style.display({ Name = "Title", Size = UDim2.new(1, -24, 0, 34), Position = UDim2.fromOffset(12, 10), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 24, Parent = waiting })
	waitingCount = Style.text({ Name = "Count", Size = UDim2.new(1, -24, 0, 22), Position = UDim2.fromOffset(12, 44), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 17, FontFace = Theme.Fonts.Heavy, TextColor3 = Theme.Colors.TextDim, Parent = waiting })
	readyButton = Button.new({
		name = "Ready",
		size = UDim2.fromOffset(220, 58),
		position = UDim2.new(0.5, 0, 1, -12),
		anchor = Vector2.new(0.5, 1),
		kind = "green",
		corner = Theme.Radius.Large,
		text = Locale.t("boss.ready"),
		textSize = 24,
		font = Theme.Fonts.Display,
		parent = waiting,
		onClick = function()
			Boss.ready()
			readyButton:setEnabled(false)
			Audio.play("UiClick")
		end,
	})
end

----------------------------------------------------------------------------
-- Refresh
----------------------------------------------------------------------------

-- Re-skins the top bar for the boss of the arena (colours, head, notches).
local function applyBoss(def: Bosses.BossDef)
	shownBoss = def.id
	local colors = BAR_COLORS[def.id] or BAR_COLORS.VoidWarden
	barPanel.BackgroundColor3 = colors[1]
	local gradient = hpFill:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient.Color = ColorSequence.new(colors[2], colors[3])
	end
	if barHead then
		barHead:Destroy()
	end
	local head = BossHud.bossHead(barPanel, 62, def.id)
	head.Position = UDim2.fromOffset(10, 11)
	barHead = head
	for _, notch in notches do
		notch:Destroy()
	end
	table.clear(notches)
	for index = 2, #def.phases do
		local notch: Frame = Create("Frame", { Name = "Notch", Size = UDim2.new(0, 4, 1, 6), Position = UDim2.new(def.phases[index].from, 0, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Theme.Colors.Cream, ZIndex = 4, Parent = hpTrack })
		Style.stroke(notch, Theme.Colors.Ink, 0, 1.5)
		table.insert(notches, notch)
	end
end

local function refresh()
	local inFight = Boss.inFight()
	local arena = Boss.arena()
	root.Visible = inFight and arena ~= nil
	if topStack then
		topStack.Position = if root.Visible then UDim2.new(0.5, 0, 0, 210) else UDim2.new(0.5, 0, 0, 10)
	end
	if not root.Visible then
		return
	end
	local t = Boss.now()
	local state = Boss.fightState()
	local def = Boss.arenaBoss() or Bosses.list[1]
	if def.id ~= shownBoss then
		applyBoss(def)
	end
	nameLabel.Text = Locale.t("boss." .. def.id .. ".name")
	local maxHp = math.max(1, Boss.attrNumber(arena, "MaxHP"))
	local hp = Boss.attrNumber(arena, "HP")
	local fraction = if state == "Open" then 1 else math.clamp(hp / maxHp, 0, 1)
	hpFill.Size = UDim2.fromScale(math.max(fraction, 0.001), 1)
	hpFill.Visible = fraction > 0
	hpLabel.Text = string.format("%d%%", math.ceil(fraction * 100))
	local phase = math.max(1, Boss.attrNumber(arena, "Phase"))
	moodLabel.Text = if state == "Open" then Locale.t("boss.portal.dormant") else string.format("%d/%d  %s", math.min(phase, #def.phases), #def.phases, Boss.text(def.id, "phase." .. math.clamp(phase, 1, #def.phases)))
	specialEdge.Visible = t < specialUntil
	if specialEdge.Visible then
		local stroke = specialEdge:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = 0.25 + math.sin(t * 14) * 0.25
		end
	end
	local endsAt = Boss.attrNumber(arena, "EndsAt")
	local left = if state == "Open" then Bosses.Combat.Duration elseif endsAt > 0 then math.max(0, endsAt - t) else 0
	timerLabel.Text = Format.clock(left)

	local h = Boss.hearts()
	if h ~= shownHearts then
		if shownHearts > h and shownHearts >= 0 then
			local lost = hearts[math.clamp(h + 1, 1, #hearts)]
			if lost then
				Tween.pop(lost, 0.3)
			end
		end
		shownHearts = h
		for i, heart in hearts do
			paintHeart(heart, i <= h)
		end
	end

	local open = state == "Open"
	waiting.Visible = open
	heartRow.Visible = not open
	strikeButton.instance.Visible = not open
	if open then
		local closesAt = Boss.attrNumber(arena, "ClosesAt")
		waitingTitle.Text = Locale.t("boss.waiting", { time = Format.clock(math.max(0, closesAt - t)) })
		waitingCount.Text = Locale.t("boss.readyCount", { ready = Boss.attrNumber(arena, "Ready"), count = Boss.attrNumber(arena, "Participants") })
	else
		readyButton:setEnabled(true)
	end
	strikeButton:setEnabled(Boss.canStrike())
	strikeCooldown.Size = UDim2.fromScale(1, Boss.cooldownFraction())
	local weapon = Boss.weapon()
	strikeEmoji.Text = Emoji.get(weapon.emoji)
	local step = Boss.comboStep()
	for i, pip in comboPips do
		pip.BackgroundColor3 = if i <= step then (if i == 3 then Color3.fromRGB(255, 120, 60) else Theme.Colors.Gold) else Theme.Colors.Cream
	end
	-- Safe-quarter arrow (screen space, from the camera).
	local zone = BossFX.safeZone
	local character = localPlayer.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	if zone and t < zone.untilTime and hrp and hrp:IsA("BasePart") and camera then
		local safe = false
		local goal = zone.position
		local spots = zone.spots
		if spots and #spots > 0 then
			-- Forgeheart / Tempest Seraph: the nearest green rock / lit shelter.
			local best = math.huge
			for _, spot in spots do
				local d = Vector3.new(hrp.Position.X - spot.X, 0, hrp.Position.Z - spot.Z).Magnitude
				if d < best then
					best, goal = d, spot
				end
			end
			safe = best <= zone.radius - 0.5
		elseif zone.safeAngle then
			local offset = Vector3.new(hrp.Position.X - zone.center.X, 0, hrp.Position.Z - zone.center.Z)
			local angle = math.atan2(offset.Z, offset.X)
			local diff = math.abs(((angle - zone.safeAngle + math.pi) % (math.pi * 2)) - math.pi)
			safe = diff <= math.pi / 4 - 0.05
		end
		safeArrow.Visible = true
		if safe then
			safeArrowGlyph.Text = Emoji.get("equipped")
			safeArrowGlyph.Rotation = 0
			safeArrowText.Text = Boss.text(def.id, "safeHere")
		else
			local toward = camera.CFrame:VectorToObjectSpace(goal - hrp.Position)
			safeArrowGlyph.Text = "➜"
			-- 0 deg = right on screen; screen up = camera forward (-Z).
			safeArrowGlyph.Rotation = math.deg(math.atan2(toward.Z, toward.X))
			safeArrowText.Text = Boss.text(def.id, "safeGo")
		end
	else
		safeArrow.Visible = false
	end
	-- "JUMP!" right before a broom wave reaches you.
	local eta = if hrp and hrp:IsA("BasePart") then BossFX.waveEta(hrp.Position) else nil
	jumpHint.Visible = eta ~= nil and eta < 0.9
	if jumpHint.Visible then
		jumpHint.Text = Locale.t("boss.jump")
	end
	strikeKey.Text = if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then "X" else "E"

	local anchor = Boss.anchor()
	if anchor and anchor:GetAttribute("Action") == "Dizzy" and t >= bannerUntil then
		banner.Text = Emoji.get("dizzy") .. " " .. Boss.text(def.id, "dizzy")
		banner.TextColor3 = Color3.fromRGB(255, 160, 230)
		banner.Visible = true
	elseif t >= bannerUntil then
		banner.Visible = false
	end
end

-- Attack hint during the telegraph (one line, the attack's own colour).
function BossHud.attack(payload: { [string]: any }, color: Color3?)
	if type(payload.attack) ~= "string" then
		return
	end
	local def = Boss.arenaBoss()
	local attack = if def then def.attacks[payload.attack] else nil
	local special = attack ~= nil and attack.big == true
	local hint = Locale.t("boss.attack." .. payload.attack)
	banner.Text = if special then string.format("%s %s %s\n%s", Emoji.get("alarm"), Locale.t("boss.special"), Emoji.get("alarm"), hint) else hint
	banner.Size = if special then UDim2.fromOffset(700, 96) else UDim2.fromOffset(640, 54)
	banner.TextColor3 = color or Color3.fromRGB(255, 226, 90)
	banner.Visible = true
	bannerUntil = (tonumber(payload.hitAt) or Boss.now()) + 0.4
	if special then
		specialUntil = tonumber(payload.hitAt) or Boss.now()
	end
	local scale = banner:FindFirstChildOfClass("UIScale")
	if scale then
		scale.Scale = 0.6
		Tween.play(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	Tween.wiggle(banner, 4)
end

----------------------------------------------------------------------------
-- Results card
----------------------------------------------------------------------------

local function rewardLine(entry: { [string]: any }): (string, string)
	local kind = entry.kind
	local amount = tonumber(entry.amount) or 0
	if kind == "essence" then
		return Emoji.get("money"), string.format("+%s %s", Format.abbrev(amount), Locale.t("common.essence"))
	elseif kind == "material" then
		local def = Materials.get(entry.ref)
		return Emoji.get(if def then def.emoji else "gem"), string.format("+%d %s", amount, Locale.t("mat." .. tostring(entry.ref)))
	elseif kind == "relic" then
		local note: string
		if entry.result == "placed" then
			note = Locale.t("boss.reward.placed")
		elseif entry.result == "levelUp" then
			note = Locale.t("boss.reward.levelUp")
		else
			note = Locale.t("boss.reward.converted", { amount = amount, material = Locale.t("mat." .. tostring(entry.fallback)) })
		end
		return Emoji.get("trophy"), Locale.relicName(tostring(entry.ref)) .. " · " .. note
	elseif kind == "cosmetic" then
		local note = if entry.result == "unlocked" then Emoji.get("new") else Locale.t("boss.reward.owned", { amount = amount, material = Locale.t("mat." .. tostring(entry.fallback)) })
		return Emoji.get("rainbow"), Locale.t("cos." .. tostring(entry.ref)) .. " · " .. note
	end
	return Emoji.get("gift"), tostring(entry.id)
end

function BossHud.results(payload: { [string]: any })
	if results then
		results:Destroy()
		results = nil
	end
	local victory = payload.result == "Victory"
	local card = Style.panel({
		Name = "BossResults",
		Size = UDim2.fromOffset(500, 470),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = if victory then (BAR_COLORS[tostring(payload.boss)] or BAR_COLORS.VoidWarden)[1] else Theme.Colors.Panel,
		Outline = Theme.Outline.Thick,
		ZIndex = 20,
		Parent = resultsLayer,
	})
	results = card
	if victory then
		local rays = Juice.rays(card, Theme.Colors.Gold, 12, 19)
		rays.Size = UDim2.fromOffset(700, 700)
	end
	local bossId = if type(payload.boss) == "string" then payload.boss else nil
	local head = BossHud.bossHead(card, 70, bossId)
	head.Position = UDim2.new(0.5, 0, 0, -30)
	head.AnchorPoint = Vector2.new(0.5, 0)
	head.ZIndex = 22
	local titleText = if victory then Locale.t("boss.victory") else Locale.t("boss.defeat")
	local title = Style.text({ Name = "Title", Size = UDim2.new(1, -24, 0, 56), Position = UDim2.fromOffset(12, 44), Text = titleText, TextSize = 46, FontFace = Style.burstFont(titleText), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = if victory then Theme.Colors.Gold else Color3.fromRGB(255, 170, 200), ZIndex = 22, Parent = card })
	Style.ink(title, 3.5)
	local sub = if victory then Boss.text(bossId, "victorySub") else Boss.text(bossId, "reason." .. tostring(payload.reason))
	local subLabel = Style.text({ Name = "Sub", Size = UDim2.new(1, -24, 0, 24), Position = UDim2.fromOffset(12, 100), Text = sub, TextSize = 18, FontFace = Theme.Fonts.Heavy, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 22, Parent = card })
	Style.ink(subLabel, 1.5)
	local stats = string.format("%s %s     %s", Emoji.get("time"), Locale.t("boss.results.time", { time = Format.clock(tonumber(payload.time) or 0) }), Locale.t("boss.results.damage", { hits = tonumber(payload.hits) or 0, damage = tonumber(payload.damage) or 0 }))
	Style.text({ Name = "Stats", Size = UDim2.new(1, -24, 0, 22), Position = UDim2.fromOffset(12, 128), Text = stats, TextSize = 16, TextColor3 = Theme.Colors.TextDim, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 22, Parent = card })

	local list: Frame = Create("Frame", { Name = "Rewards", Size = UDim2.new(1, -40, 0, 236), Position = UDim2.fromOffset(20, 158), BackgroundColor3 = Theme.Colors.PanelLight, ZIndex = 21, Parent = card })
	Style.corner(list, Theme.Radius.Medium)
	Style.stroke(list, Theme.Colors.Ink, 0, 2)
	Style.padding(list, 8, 10)
	Style.list(list, 6)
	local rewards = if type(payload.rewards) == "table" then payload.rewards else {}
	if #rewards > 0 then
		local header = Style.text({ Size = UDim2.new(1, 0, 0, 24), Text = Locale.t("boss.results.rewards"), TextSize = 18, FontFace = Theme.Fonts.Display, TextColor3 = Theme.Colors.Gold, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 22, LayoutOrder = 0, Parent = list })
		Style.ink(header, 1.5)
		for index, entry in rewards do
			local icon, text = rewardLine(entry)
			local row = Style.text({
				Name = "Reward",
				Size = UDim2.new(1, 0, 0, 30),
				Text = icon .. "  " .. text .. (if entry.rare then "  " .. Style.colored("★", Theme.Colors.Gold) else ""),
				TextSize = 18,
				FontFace = Theme.Fonts.Heavy,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 22,
				LayoutOrder = index,
				Parent = list,
			})
			Style.ink(row, 1.5)
			row:SetAttribute("RewardId", tostring(entry.id))
		end
	else
		local outcome = tostring(payload.outcome)
		local key = "boss.outcome." .. outcome
		local text = if Locale.has(key) then Locale.t(key, { needed = tonumber(payload.needed) or 0 }) else Locale.t("boss.results.none")
		Style.text({ Name = "Outcome", Size = UDim2.new(1, 0, 0, 60), Text = text, TextWrapped = true, TextSize = 18, FontFace = Theme.Fonts.Heavy, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 22, Parent = list })
	end
	local ok = Button.new({
		name = "Ok",
		size = UDim2.fromOffset(200, 56),
		position = UDim2.new(0.5, 0, 1, -12),
		anchor = Vector2.new(0.5, 1),
		kind = "green",
		corner = Theme.Radius.Large,
		text = "OK",
		textSize = 24,
		font = Theme.Fonts.Display,
		zIndex = 22,
		parent = card,
		onClick = function()
			if results == card then
				results = nil
			end
			card:Destroy()
		end,
	})
	local _ = ok
	Tween.popIn(card)
	if victory then
		Juice.burstFrom(card, 50)
		Audio.play("HeistSecured")
	else
		Audio.play("UiError")
	end
	task.delay(25, function()
		if results == card then
			results = nil
			card:Destroy()
		end
	end)
end

-- Tests / debug.
function BossHud.debugState(): { visible: boolean, hearts: number, strike: boolean, waiting: boolean, results: boolean, banner: string }
	return {
		visible = root.Visible,
		hearts = shownHearts,
		strike = strikeButton.instance.Visible,
		waiting = waiting.Visible,
		results = results ~= nil,
		banner = if banner.Visible then banner.Text else "",
	}
end

function BossHud.strikeButton(): GuiObject
	return strikeButton.instance
end

function BossHud.isTouchLayout(): boolean
	return isTouch
end

-- Touch only: keeps Strike bottom-aligned with the (lifted) ability cluster.
function BossHud.setTouchBottom(bottom: number)
	if isTouch and strikeButton then
		strikeButton.instance.Position = UDim2.new(1, -272, 1, -bottom)
	end
end

function BossHud.init(parent: Instance, overlay: Instance, touch: boolean, stack: GuiObject?)
	root = Create("Frame", { Name = "BossHud", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = parent })
	resultsLayer = overlay
	topStack = stack
	buildTop()
	buildBottom(touch)
	local clock = 0
	RunService.Heartbeat:Connect(function(dt: number)
		clock += dt
		if clock >= 0.1 then
			clock = 0
			refresh()
		end
	end)
	localPlayer:GetAttributeChangedSignal("BossFight"):Connect(refresh)
	localPlayer:GetAttributeChangedSignal("BossHearts"):Connect(refresh)
	Locale.changed:Connect(function()
		leaveButton:setText(Locale.t("boss.leave"))
		readyButton:setText(Locale.t("boss.ready"))
		local caption = strikeButton.content:FindFirstChild("Caption")
		if caption and caption:IsA("TextLabel") then
			caption.Text = Locale.t("boss.strike")
		end
	end)
	refresh()
end

return BossHud
