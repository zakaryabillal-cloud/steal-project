--!strict
-- Main heads-up display:
--   left   : Essence bubble, Power bar, 2x2 grid of big emoji menu buttons
--            (Upgrades / RiftDex / Style / Settings), next goal with a progress bar
--   bottom : carry panel (what you hold, where home is, theft timers)
--   right  : ability buttons with cooldown fills (one per equipped loadout slot + Seal)
-- plus Essence collection orbs and the danger vignette.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Theme = require(Shared.Config.Theme)
local Emoji = require(Shared.Config.Emoji)
local Upgrades = require(Shared.Config.Upgrades)
local Relics = require(Shared.Config.Relics)
local Mutations = require(Shared.Config.Mutations)
local GameConfig = require(Shared.Config.GameConfig)
local AbilityConfig = require(Shared.Config.Abilities)
local Economy = require(Shared.Economy)
local Layout = require(Shared.Layout)
local Locale = require(Shared.Locale)
local Format = require(Shared.Util.Format)
local MathUtil = require(Shared.Util.MathUtil)

local UIRoot = script.Parent.Parent
local Kit = UIRoot.Kit
local Create = require(Kit.Create)
local Style = require(Kit.Style)
local Tween = require(Kit.Tween)
local Icons = require(Kit.Icons)
local Button = require(Kit.Button)
local RelicViewport = require(Kit.RelicViewport)
local Juice = require(Kit.Juice)

local Controllers = UIRoot.Parent.Controllers
local Store = require(Controllers.Store)
local Audio = require(Controllers.Audio)
local Abilities = require(Controllers.Abilities)
local GrappleTargeting = require(Controllers.GrappleTargeting)
local RelicRenderer = require(Controllers.RelicRenderer)
local SanctuaryFX = require(Controllers.SanctuaryFX)
local ClientNet = require(UIRoot.Parent.ClientNet)
local Net = require(Shared.Net)

local Hud = {}

local localPlayer = Players.LocalPlayer
local touch = false
local openModal: (string) -> () = function(_name: string) end

-- Essence card
local essenceLabel: TextLabel
local rateLabel: TextLabel
local essenceCard: Frame
local essenceIcon: Frame
local displayedEssence = 0
local powerLabel: TextLabel
local powerPeakLabel: TextLabel
local displayedPower = -1

-- Menu
local menuButtons: { [string]: Button.Button } = {}
local upgradesBadge: Frame
local dexChip: TextLabel

-- Next goal
local goalFrame: Frame
local goalName: TextLabel
local goalCost: TextLabel
local goalBar: Frame
local goalStroke: UIStroke
local goalReady = false

-- Abilities
type AbilityView = {
	key: string,
	frame: TextButton,
	overlay: Frame,
	gradient: UIGradient,
	countdown: TextLabel,
	stroke: UIStroke,
	wasReady: boolean,
	-- Dims the button when it cannot be used right now (no grapple anchor).
	dim: Frame,
	color: Color3,
}
local abilityViews: { AbilityView } = {}
local abilityCluster: Frame
-- Loadout slot index -> its button (nil when the slot is empty).
local slotViews: { [number]: AbilityView } = {}
-- Loadout screen button (next to the ability buttons) and its badge.
local loadoutButton: Button.Button
local loadoutBadge: Frame
-- Active status chips (shield, phase, slowed, stunned).
local statusRow: Frame
type StatusChip = { frame: Frame, label: TextLabel }
local statusChips: { [string]: StatusChip } = {}
local shownLoadout = ""
-- Button size and position per loadout slot (Mobility, Control, Utility).
local SLOT_LAYOUT = {
	{ size = 70, position = UDim2.new(1, -150, 1, -40) },
	{ size = 88, position = UDim2.new(1, -48, 1, -50) },
	{ size = 60, position = UDim2.new(1, -150, 1, -122) },
}

-- Carry panel
local carryPanel: Frame
local carryHeader: TextLabel
local carryDistance: TextLabel
local carryRows: Frame
local carryHint: TextLabel
local carryStroke: UIStroke
local dissolveButton: Button.Button
local carryViewports: { RelicViewport.Viewport } = {}
local carriedKey = ""

-- Overlays
local fullscreen: Frame
local vignette: Frame

----------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------

local function nextGoal(): (string?, number?)
	local upgrades = Store.state.upgrades
	local bestId: string? = nil
	local bestCost: number? = nil
	for _, def in Upgrades.list do
		if Economy.upgradeBlocker(def.id, upgrades) == nil then
			local cost = Economy.upgradeCost(def.id, (upgrades :: any)[def.id])
			if cost and (bestCost == nil or cost < bestCost) then
				bestId = def.id
				bestCost = cost
			end
		end
	end
	return bestId, bestCost
end

function Hud.anyAffordable(): boolean
	local upgrades = Store.state.upgrades
	for _, def in Upgrades.list do
		if Economy.upgradeBlocker(def.id, upgrades) == nil then
			local cost = Economy.upgradeCost(def.id, (upgrades :: any)[def.id])
			if cost and cost <= Store.state.essence then
				return true
			end
		end
	end
	return false
end

local function formatEssence(value: number): string
	if value < 100000 then
		return Format.commas(value)
	end
	return Format.abbrev(value)
end

----------------------------------------------------------------------------
-- Build
----------------------------------------------------------------------------

local function buildEssence(parent: Instance)
	-- Big currency bubble: the gem pokes out of the left edge, huge number,
	-- green "+x/s" chip underneath.
	essenceCard = Style.panel({
		Name = "Essence",
		Size = UDim2.fromOffset(270, 80),
		LayoutOrder = 1,
		CornerRadius = Theme.Radius.Pill,
		Parent = parent,
	})
	local stroke = essenceCard:FindFirstChildOfClass("UIStroke") :: UIStroke
	stroke.Name = "Stroke"
	local gemBack = Create("Frame", {
		Name = "GemBack",
		Size = UDim2.fromOffset(66, 66),
		Position = UDim2.new(0, 7, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Theme.Colors.PanelLight,
		Parent = essenceCard,
	})
	Style.corner(gemBack, Theme.Radius.Pill)
	Style.stroke(gemBack, Theme.Colors.Ink, 0, Theme.Outline.Thin)
	essenceIcon = Create("Frame", {
		Size = UDim2.fromOffset(58, 58),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = gemBack,
	})
	Icons.essence(essenceIcon)
	Create("UIScale", { Parent = essenceIcon })
	essenceLabel = Style.text({
		Name = "Amount",
		Size = UDim2.new(1, -90, 0, 42),
		Position = UDim2.fromOffset(80, 3),
		FontFace = Theme.Fonts.Display,
		TextSize = 38,
		TextScaled = true,
		Text = "0",
		Parent = essenceCard,
	})
	Create("UITextSizeConstraint", { MaxTextSize = 38, MinTextSize = 20, Parent = essenceLabel })
	Style.ink(essenceLabel, Theme.Outline.Regular)
	local ratePill
	ratePill, rateLabel = Style.pill({
		name = "Rate",
		text = "+0/s",
		color = Theme.Buttons.green.face,
		size = UDim2.fromOffset(104, 24),
		position = UDim2.fromOffset(80, 48),
		textSize = 15,
		parent = essenceCard,
	})
	ratePill.AutomaticSize = Enum.AutomaticSize.X
	Style.padding(ratePill, 0, 10)
	rateLabel.AutomaticSize = Enum.AutomaticSize.X
	rateLabel.Size = UDim2.fromScale(0, 1)

	-- Power Level bar (progression summary, never spent).
	local powerBar = Create("Frame", {
		Name = "PowerBar",
		Size = UDim2.fromOffset(270, 42),
		BackgroundColor3 = Theme.Buttons.orange.face,
		LayoutOrder = 2,
		Parent = parent,
	})
	Style.corner(powerBar, Theme.Radius.Pill)
	Style.stroke(powerBar, Theme.Colors.Ink, 0, Theme.Outline.Regular)
	Style.shade(powerBar, 0.2)
	Style.gloss(powerBar)
	local powerIconBack = Create("Frame", {
		Size = UDim2.fromOffset(32, 32),
		Position = UDim2.new(0, 6, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Theme.Buttons.orange.lip,
		Parent = powerBar,
	})
	Style.corner(powerIconBack, Theme.Radius.Pill)
	local powerIcon = Create("Frame", {
		Name = "PowerIcon",
		Size = UDim2.fromScale(0.62, 0.62),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = powerIconBack,
	})
	Icons.power(powerIcon, Theme.Colors.Text)
	powerLabel = Style.text({
		Name = "Power",
		Size = UDim2.new(0.62, -44, 1, 0),
		Position = UDim2.fromOffset(46, 0),
		FontFace = Theme.Fonts.Display,
		TextSize = 21,
		TextScaled = true,
		Text = Locale.t("hud.power") .. " 0",
		Parent = powerBar,
	})
	Create("UITextSizeConstraint", { MaxTextSize = 21, MinTextSize = 12, Parent = powerLabel })
	Style.ink(powerLabel, Theme.Outline.Text)
	powerPeakLabel = Style.text({
		Name = "PowerPeak",
		Size = UDim2.new(0.38, -14, 1, 0),
		Position = UDim2.new(0.62, 0, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		FontFace = Theme.Fonts.Heavy,
		TextSize = 14,
		Text = "",
		Parent = powerBar,
	})
	Style.ink(powerPeakLabel, 1.5)
end

-- Menu button colours + emoji (Config/Emoji).
local MENU_STYLE: { [string]: { kind: string, emoji: string } } = {
	Shop = { kind = "green", emoji = Emoji.get("upgrades") },
	Dex = { kind = "blue", emoji = Emoji.get("dex") },
	Cosmetics = { kind = "pink", emoji = Emoji.get("style") },
	Settings = { kind = "purple", emoji = Emoji.get("settings") },
}

local function menuButton(parent: Instance, name: string, order: number, label: string): Button.Button
	local style = MENU_STYLE[name]
	local button = Button.new({
		name = name,
		size = UDim2.fromOffset(131, 62),
		kind = style.kind,
		corner = Theme.Radius.Large,
		layoutOrder = order,
		parent = parent,
		onClick = function()
			openModal(name)
		end,
	})
	local emoji = Style.text({
		Name = "Emoji",
		Size = UDim2.fromOffset(40, 40),
		Position = UDim2.new(0, 6, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 30,
		FontFace = Theme.Fonts.Display,
		Text = style.emoji,
		ZIndex = 3,
		Parent = button.content,
	})
	emoji:SetAttribute("Emoji", true)
	local caption = Style.text({
		Name = "Caption",
		Size = UDim2.new(1, -52, 1, -10),
		Position = UDim2.new(0, 46, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 17,
		TextScaled = true,
		FontFace = Theme.Fonts.Display,
		Text = label,
		ZIndex = 3,
		Parent = button.content,
	})
	Create("UITextSizeConstraint", { MaxTextSize = 17, MinTextSize = 10, Parent = caption })
	Style.ink(caption, Theme.Outline.Text)
	caption:SetAttribute("Key", label)
	menuButtons[name] = button
	return button
end

local function buildMenu(parent: Instance)
	local row = Create("Frame", {
		Name = "Menu",
		Size = UDim2.fromOffset(270, 140),
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		Parent = parent,
	})
	Create("UIGridLayout", {
		CellSize = UDim2.fromOffset(131, 64),
		CellPadding = UDim2.fromOffset(8, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})
	local upgrades = menuButton(row, "Shop", 1, Locale.t("hud.upgrades"))
	local dex = menuButton(row, "Dex", 2, Locale.t("hud.dex"))
	menuButton(row, "Cosmetics", 3, Locale.t("hud.cosmetics"))
	menuButton(row, "Settings", 4, Locale.t("hud.settings"))

	upgradesBadge = Style.badge(upgrades.instance, "!", Theme.Colors.Danger, 24)
	upgradesBadge.Visible = false

	local chip
	chip, dexChip = Style.pill({
		name = "DexChip",
		text = "0/0",
		color = Theme.Colors.Gold,
		size = UDim2.fromOffset(46, 20),
		position = UDim2.new(1, 6, 0, -8),
		anchor = Vector2.new(1, 0),
		textSize = 12,
		zIndex = 8,
		parent = dex.instance,
	})
	local _ = chip
end

local function buildGoal(parent: Instance, order: number)
	local button = Button.new({
		name = "NextGoal",
		size = UDim2.fromOffset(270, 76),
		color = Theme.Colors.Panel,
		corner = Theme.Radius.Large,
		layoutOrder = order,
		parent = parent,
		hoverScale = 1.03,
		onClick = function()
			openModal("Shop")
		end,
	})
	goalFrame = button.instance :: any
	goalStroke = button.stroke
	local face = button.content
	local caption = Style.text({
		Name = "Caption",
		Size = UDim2.new(1, -24, 0, 16),
		Position = UDim2.fromOffset(14, 7),
		TextSize = 13,
		FontFace = Theme.Fonts.Heavy,
		TextColor3 = Theme.Colors.Gold,
		Text = Emoji.label("goal", Locale.t("hud.nextGoal")),
		ZIndex = 3,
		Parent = face,
	})
	Style.ink(caption, 1.5)
	goalName = Style.text({
		Size = UDim2.new(1, -110, 0, 22),
		Position = UDim2.fromOffset(14, 24),
		TextSize = 18,
		FontFace = Theme.Fonts.Display,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 3,
		Parent = face,
	})
	Style.ink(goalName, 1.5)
	local costHolder = Create("Frame", {
		Size = UDim2.fromOffset(20, 20),
		Position = UDim2.new(1, -96, 0, 25),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = face,
	})
	Icons.essence(costHolder)
	goalCost = Style.text({
		Size = UDim2.fromOffset(72, 22),
		Position = UDim2.new(1, -74, 0, 24),
		TextSize = 18,
		FontFace = Theme.Fonts.Display,
		ZIndex = 3,
		Parent = face,
	})
	Style.ink(goalCost, 1.5)
	local back = Create("Frame", {
		Name = "Track",
		Size = UDim2.new(1, -28, 0, 12),
		Position = UDim2.new(0, 14, 1, -18),
		BackgroundColor3 = Theme.Colors.Ink,
		BackgroundTransparency = 0.35,
		ZIndex = 3,
		Parent = face,
	})
	Style.corner(back, Theme.Radius.Pill)
	Style.stroke(back, Theme.Colors.Ink, 0, Theme.Outline.Thin)
	goalBar = Create("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 4, Parent = back })
	Style.corner(goalBar, Theme.Radius.Pill)
	Style.gradient(goalBar, Theme.Colors.Gold, Theme.Colors.Power)
	Style.gloss(goalBar, 5)
end

local function abilityButton(parent: Instance, key: string, size: number, position: UDim2, keyLabel: string, icon: (Instance, Color3) -> Frame, color: Color3, action: () -> ()): AbilityView
	local face = Style.vivid(color)
	local button = Button.new({
		name = key,
		size = UDim2.fromOffset(size, size + Theme.Lip),
		position = position,
		anchor = Vector2.new(0.5, 0.5),
		color = face,
		corner = Theme.Radius.Pill,
		parent = parent,
		silent = true,
		onClick = action,
	})
	local frame = button.instance
	local stroke = button.stroke
	stroke.Thickness = Theme.Outline.Regular
	local holder = Create("Frame", {
		Size = UDim2.fromScale(0.52, 0.52),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = button.content,
	})
	icon(holder, Theme.Colors.Text)
	local overlay = Create("Frame", {
		Name = "Cooldown",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Ink,
		BackgroundTransparency = 0.2,
		ZIndex = 4,
		Visible = false,
		Parent = button.content,
	})
	Style.corner(overlay, UDim.new(1, 0))
	local dim = Create("Frame", {
		Name = "Unavailable",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Ink,
		BackgroundTransparency = 0.45,
		ZIndex = 4,
		Visible = false,
		Parent = button.content,
	})
	Style.corner(dim, UDim.new(1, 0))
	local gradient = Create("UIGradient", { Rotation = 90, Parent = overlay })
	local countdown = Style.text({
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = math.floor(size * 0.34),
		FontFace = Theme.Fonts.Display,
		ZIndex = 5,
		Text = "",
		Parent = button.content,
	})
	Style.ink(countdown, Theme.Outline.Regular)
	if not touch then
		local chip = Create("Frame", {
			Name = "Key",
			Size = UDim2.fromOffset(26, 22),
			Position = UDim2.new(0.5, 0, 1, 8),
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundColor3 = Theme.Colors.Cream,
			ZIndex = 6,
			Parent = frame,
		})
		Style.corner(chip, UDim.new(0, 8))
		Style.stroke(chip, Theme.Colors.Ink, 0, Theme.Outline.Thin)
		Style.text({ Text = keyLabel, TextXAlignment = Enum.TextXAlignment.Center, TextSize = 14, FontFace = Theme.Fonts.Heavy, TextColor3 = Theme.Colors.Ink, ZIndex = 7, Parent = chip })
	end
	return { key = key, frame = frame, overlay = overlay, gradient = gradient, countdown = countdown, stroke = stroke, wasReady = true, dim = dim, color = color }
end

local GAMEPAD_LABEL: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.ButtonR1] = "R1",
	[Enum.KeyCode.ButtonL1] = "L1",
	[Enum.KeyCode.ButtonR2] = "R2",
	[Enum.KeyCode.ButtonY] = "Y",
}
local function isGamepad(): boolean
	return UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled
end

-- (Re)builds one button per equipped loadout slot when the loadout changes.
local function refreshAbilitySlots()
	local loadout = Store.state.loadout
	local signature = table.concat(loadout, ",")
	if signature == shownLoadout then
		return
	end
	shownLoadout = signature
	for index, slot in AbilityConfig.Slots do
		local existing = slotViews[index]
		local def = AbilityConfig.get(loadout[index])
		if existing and def and existing.key == def.id then
			continue
		end
		if existing then
			local at = table.find(abilityViews, existing)
			if at then
				table.remove(abilityViews, at)
			end
			existing.frame:Destroy()
			slotViews[index] = nil
		end
		if def then
			local layout = SLOT_LAYOUT[index]
			local icon = (Icons :: any)[def.icon] or Icons.pulse
			local keyLabel = if isGamepad() then GAMEPAD_LABEL[slot.gamepad] or slot.gamepad.Name else slot.keyboard.Name
			local view = abilityButton(abilityCluster, def.id, layout.size, layout.position, keyLabel, icon, def.color, function()
				Abilities.useSlot(index)
			end)
			slotViews[index] = view
			table.insert(abilityViews, view)
		end
	end
end

local function buildAbilities(parent: Instance)
	abilityCluster = Create("Frame", {
		Name = "Abilities",
		Size = UDim2.fromOffset(230, 190),
		Position = if touch then UDim2.new(1, -16, 1, -150) else UDim2.new(1, -22, 1, -22),
		AnchorPoint = Vector2.new(1, 1),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	table.insert(abilityViews, abilityButton(abilityCluster, "seal", 60, UDim2.new(1, -58, 1, -148), if isGamepad() then "Y" else "G", Icons.seal, Theme.Colors.Gold, Abilities.seal))
	refreshAbilitySlots()

	-- Loadout screen: round backpack button left of the ability buttons.
	loadoutButton = Button.new({
		name = "LoadoutButton",
		size = UDim2.fromOffset(50, 50 + Theme.Lip),
		position = UDim2.new(1, -214, 1, -42),
		anchor = Vector2.new(0.5, 0.5),
		kind = "purple",
		corner = UDim.new(1, 0),
		parent = abilityCluster,
		onClick = function()
			openModal("Loadout")
		end,
	})
	local backpack = Style.text({
		Name = "Emoji",
		Text = Emoji.get("loadout"),
		TextSize = 26,
		FontFace = Theme.Fonts.Display,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 3,
		Parent = loadoutButton.content,
	})
	backpack:SetAttribute("Emoji", true)
	loadoutBadge = Style.badge(loadoutButton.instance, "!", Theme.Colors.Danger, 20)
	loadoutBadge.Visible = false
	if not touch then
		local chip = Create("Frame", {
			Name = "Key",
			Size = UDim2.fromOffset(24, 20),
			Position = UDim2.new(0.5, 0, 1, 8),
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundColor3 = Theme.Colors.Cream,
			ZIndex = 6,
			Parent = loadoutButton.instance,
		})
		Style.corner(chip, UDim.new(0, 8))
		Style.stroke(chip, Theme.Colors.Ink, 0, Theme.Outline.Thin)
		Style.text({ Text = if isGamepad() then "↑" else "L", TextXAlignment = Enum.TextXAlignment.Center, TextSize = 13, FontFace = Theme.Fonts.Heavy, TextColor3 = Theme.Colors.Ink, ZIndex = 7, Parent = chip })
	end

	-- Status chips above the buttons (only while something is active).
	statusRow = Create("Frame", {
		Name = "StatusRow",
		Size = UDim2.fromOffset(230, 26),
		Position = UDim2.new(1, 0, 1, -200),
		AnchorPoint = Vector2.new(1, 1),
		BackgroundTransparency = 1,
		Parent = abilityCluster,
	})
	Style.list(statusRow, 6, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Right)
end

local STATUS_ORDER = { "shield", "phase", "stun", "root", "slow" }
local STATUS_COLOR: { [string]: Color3 } = {
	shield = Theme.Buttons.yellow.face,
	phase = Theme.Buttons.mint.face,
	stun = Theme.Buttons.orange.face,
	root = Theme.Buttons.red.face,
	slow = Theme.Buttons.blue.face,
}
-- A goofy emoji in front of each status (Config/Emoji).
local STATUS_EMOJI: { [string]: string } = {
	shield = Emoji.get("strong"),
	phase = Emoji.get("ghost"),
	stun = Emoji.get("dizzy"),
	root = Emoji.get("sprout"),
	slow = Emoji.get("snail"),
}

local function statusChip(kind: string): StatusChip
	local existing = statusChips[kind]
	if existing then
		return existing
	end
	local frame = Create("Frame", {
		Name = "Status_" .. kind,
		Size = UDim2.fromOffset(84, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = STATUS_COLOR[kind],
		LayoutOrder = table.find(STATUS_ORDER, kind) or 9,
		Visible = false,
		Parent = statusRow,
	})
	Style.corner(frame, UDim.new(1, 0))
	Style.stroke(frame, Theme.Colors.Ink, 0, Theme.Outline.Thin)
	Style.shade(frame, 0.15)
	Style.padding(frame, 0, 9)
	local label = Style.text({
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		TextSize = 14,
		FontFace = Theme.Fonts.Heavy,
		Parent = frame,
	})
	Style.ink(label, 1.5)
	local created = { frame = frame, label = label }
	statusChips[kind] = created
	Tween.popIn(frame, 0.4)
	return created
end

local function updateStatus()
	local status = Store.state.status
	local t = Store.now()
	local active: { [string]: string } = {}
	if status.shieldUntil > t then
		active.shield = Locale.t("status.shield", { time = string.format("%.1f", status.shieldUntil - t) })
	end
	if status.phaseUntil > t then
		active.phase = Locale.t("status.phase", { time = string.format("%.1f", status.phaseUntil - t) })
	end
	if status.stunUntil > t then
		active.stun = Locale.t("status.stun")
	end
	if status.rootUntil > t then
		active.root = Locale.t("status.root")
	end
	if status.slow > 0 and status.slowUntil > t then
		active.slow = Locale.t("status.slow", { amount = math.floor(status.slow * 100 + 0.5) })
	end
	for _, kind in STATUS_ORDER do
		local text = active[kind]
		local chip = statusChips[kind]
		if text then
			chip = statusChip(kind)
			if not chip.frame.Visible then
				Tween.popIn(chip.frame, 0.5)
			end
			chip.label.Text = STATUS_EMOJI[kind] .. " " .. text
			chip.frame.Visible = true
		elseif chip then
			chip.frame.Visible = false
		end
	end
end

-- Any ability the player can unlock right now (Power record + Essence)?
function Hud.unlockAvailable(): boolean
	local state = Store.state
	for _, def in AbilityConfig.list do
		local requirement = def.unlock
		if requirement and not state.unlocked[def.id] and state.powerPeak >= requirement.power and state.essence >= requirement.essence then
			return true
		end
	end
	return false
end

local function refreshPower()
	local state = Store.state
	if state.power ~= displayedPower then
		if displayedPower >= 0 and state.power > displayedPower then
			Tween.pop(powerLabel, 0.08)
		end
		displayedPower = state.power
	end
	powerLabel.Text = Locale.t("hud.power") .. " " .. Format.commas(math.floor(state.power))
	-- The record only shows when it differs (e.g. after a theft).
	if state.powerPeak > state.power then
		powerPeakLabel.Text = Locale.t("hud.powerPeak", { peak = Format.abbrev(state.powerPeak) })
	else
		powerPeakLabel.Text = ""
	end
end

local function buildCarry(parent: Instance)
	carryPanel = Style.panel({
		Name = "Carry",
		Size = UDim2.fromOffset(420, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = if touch then UDim2.new(0.5, 0, 1, -12) else UDim2.new(0.5, 0, 1, -22),
		AnchorPoint = Vector2.new(0.5, 1),
		Visible = false,
		Parent = parent,
	})
	carryStroke = carryPanel:FindFirstChildOfClass("UIStroke") :: UIStroke
	Style.padding(carryPanel, 12, 14)
	Style.list(carryPanel, 6)
	Create("UIScale", { Parent = carryPanel })
	local header = Create("Frame", { Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, LayoutOrder = 1, Parent = carryPanel })
	carryHeader = Style.text({ Size = UDim2.new(1, -100, 1, 0), TextSize = 16, FontFace = Theme.Fonts.Heavy, Parent = header })
	Style.ink(carryHeader, 1.5)
	carryDistance = Style.text({ Size = UDim2.new(0, 100, 1, 0), Position = UDim2.new(1, -100, 0, 0), TextXAlignment = Enum.TextXAlignment.Right, TextSize = 18, FontFace = Theme.Fonts.Display, TextColor3 = Theme.Colors.Gold, Parent = header })
	Style.ink(carryDistance, 1.5)
	carryRows = Create("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 2, Parent = carryPanel })
	Style.list(carryRows, 4)
	local footer = Create("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, LayoutOrder = 3, Parent = carryPanel })
	carryHint = Style.text({ Size = UDim2.new(1, -130, 1, 0), TextSize = 16, TextWrapped = true, FontFace = Theme.Fonts.Heavy, Parent = footer })
	Style.ink(carryHint, 1.5)
	dissolveButton = Button.new({
		name = "Dissolve",
		size = UDim2.fromOffset(122, 40),
		position = UDim2.new(1, 0, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		kind = "orange",
		text = Locale.t("hud.dissolve"),
		textSize = 15,
		corner = UDim.new(1, 0),
		parent = footer,
		onClick = function()
			local uid = Store.state.carrying[1]
			if uid then
				ClientNet.fire(Net.Events.DissolveCarried, uid)
			end
		end,
	})
end

local function buildVignette()
	vignette = Create("Frame", { Name = "Vignette", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = fullscreen })
	local edges = {
		{ size = UDim2.fromScale(1, 0.22), position = UDim2.fromScale(0, 0), rotation = 90 },
		{ size = UDim2.fromScale(1, 0.22), position = UDim2.fromScale(0, 0.78), rotation = -90 },
		{ size = UDim2.fromScale(0.16, 1), position = UDim2.fromScale(0, 0), rotation = 0 },
		{ size = UDim2.fromScale(0.16, 1), position = UDim2.fromScale(0.84, 0), rotation = 180 },
	}
	for _, edge in edges do
		local frame = Create("Frame", {
			Size = edge.size,
			Position = edge.position,
			BackgroundColor3 = Theme.Colors.Danger,
			BorderSizePixel = 0,
			Parent = vignette,
		})
		Create("UIGradient", {
			Rotation = edge.rotation,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.35),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = frame,
		})
	end
	vignette.Visible = false
end

----------------------------------------------------------------------------
-- Updates
----------------------------------------------------------------------------

local function refreshMenuText()
	for name, button in menuButtons do
		local caption = button.content:FindFirstChild("Caption") :: TextLabel?
		if caption then
			caption.Text = if name == "Shop" then Locale.t("hud.upgrades") elseif name == "Dex" then Locale.t("hud.dex") elseif name == "Cosmetics" then Locale.t("hud.cosmetics") else Locale.t("hud.settings")
		end
	end
	if goalFrame then
		local caption = goalFrame:FindFirstChild("Caption", true) :: TextLabel?
		if caption then
			caption.Text = Emoji.label("goal", Locale.t("hud.nextGoal"))
		end
	end
	dissolveButton:setText(Locale.t("hud.dissolve"))
end

local function refreshStatic()
	local state = Store.state
	rateLabel.Text = Locale.t("hud.perSecond", { rate = Format.abbrev(state.rate) })
	refreshPower()
	refreshAbilitySlots()
	local found = Store.dexCounts()
	dexChip.Text = string.format("%d/%d", found, Relics.count)
	upgradesBadge.Visible = Hud.anyAffordable()
	loadoutBadge.Visible = Hud.unlockAvailable()

	local id, cost = nextGoal()
	if goalFrame then
		if id and cost then
			goalFrame.Visible = true
			goalName.Text = Locale.t("upgrade." .. id .. ".name")
			goalCost.Text = Format.abbrev(cost)
			local fraction = math.clamp(state.essence / cost, 0, 1)
			Tween.play(goalBar, 0.4, { Size = UDim2.fromScale(fraction, 1) })
			local ready = fraction >= 1
			goalStroke.Color = if ready then Theme.Colors.Success else Theme.Colors.Ink
			goalStroke.Thickness = if ready then Theme.Outline.Thick else Theme.Outline.Thin + 0.5
			goalCost.TextColor3 = if ready then Theme.Colors.Success else Theme.Colors.Text
			if ready and not goalReady then
				Tween.wiggle(goalFrame, 5)
			end
			goalReady = ready
		else
			goalFrame.Visible = false
		end
	end
end

local function clearCarryRows()
	for _, viewport in carryViewports do
		viewport:destroy()
	end
	table.clear(carryViewports)
	for _, child in carryRows:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
end

local function rebuildCarry()
	local uids = Store.state.carrying
	local key = table.concat(uids, ",")
	local missing = false
	for _, uid in uids do
		if not RelicRenderer.get(uid) then
			missing = true
		end
	end
	if key == carriedKey and not missing then
		return
	end
	carriedKey = if missing then "" else key
	clearCarryRows()
	if #uids == 0 then
		if carryPanel.Visible then
			Tween.play(carryPanel, 0.2, { BackgroundTransparency = 1 })
			task.delay(0.2, function()
				if #Store.state.carrying == 0 then
					carryPanel.Visible = false
					carryPanel.BackgroundTransparency = Theme.Transparency.Panel
				end
			end)
		end
		return
	end
	for i, uid in uids do
		local record = RelicRenderer.get(uid)
		if not record then
			continue
		end
		local row = Create("Frame", { Size = UDim2.new(1, 0, 0, 54), BackgroundTransparency = 1, LayoutOrder = i, Parent = carryRows })
		local viewport = RelicViewport.new({ size = UDim2.fromOffset(54, 54), parent = row })
		viewport:set(record.relicId, record.mutation, false)
		table.insert(carryViewports, viewport)
		local mutation = Mutations.get(record.mutation)
		local color = if mutation then mutation.color:Lerp(record.rarity.color, 0.3) else record.rarity.color
		local title = Style.text({
			Size = UDim2.new(1, -66, 0, 26),
			Position = UDim2.fromOffset(64, 2),
			TextSize = 20,
			FontFace = Theme.Fonts.Display,
			Text = Style.colored(Locale.relicTitle(record.relicId, record.mutation), color),
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = row,
		})
		Style.ink(title, 1.5)
		local rate = Economy.relicBaseRate(record.relicId, record.level, record.mutation) * Store.state.multiplier
		Style.pill({
			name = "Rarity",
			text = Style.stars(record.rarity.id) .. " " .. string.upper(Locale.rarity(record.rarity.id)),
			color = record.rarity.color,
			size = UDim2.fromOffset(150, 20),
			position = UDim2.fromOffset(64, 31),
			textSize = 12,
			parent = row,
		})
		local rateText = Style.text({
			Size = UDim2.new(1, -226, 0, 20),
			Position = UDim2.fromOffset(222, 31),
			TextSize = 15,
			FontFace = Theme.Fonts.Heavy,
			TextColor3 = Theme.Colors.Essence,
			Text = string.format("+%s/s", Format.abbrev(rate)),
			Parent = row,
		})
		Style.ink(rateText, 1.5)
	end
	if not carryPanel.Visible then
		carryPanel.Visible = true
		Tween.pop(carryPanel, 0.15)
		Audio.play("Pickup", { pitch = 1.2, volume = 0.5 })
	end
end

local function updateCarry()
	local uids = Store.state.carrying
	if #uids == 0 then
		return
	end
	local stolenUntil = 0
	local anyStolen = false
	for _, uid in uids do
		local record = RelicRenderer.get(uid)
		if record then
			local stolenFrom = record.anchor:GetAttribute("StolenFrom")
			if type(stolenFrom) == "number" and stolenFrom ~= 0 then
				anyStolen = true
				local at = record.anchor:GetAttribute("StolenAt")
				if type(at) == "number" then
					stolenUntil = math.max(stolenUntil, at + GameConfig.Carry.StolenMaxCarry)
				end
			end
		end
	end
	local plot = Store.state.plot
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if plot ~= 0 and root and root:IsA("BasePart") then
		local gate = Layout.plotCFrame(plot).Position
		local distance = (Vector3.new(gate.X, 0, gate.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude
		carryDistance.Text = if distance < Layout.PlatformRadius then Emoji.get("home") .. " ✓" else string.format("%s %dm", Emoji.get("home"), math.floor(distance - Layout.PlatformRadius))
	else
		carryDistance.Text = ""
	end
	local myPlot = Store.plotModel()
	local placed = if myPlot then (myPlot:GetAttribute("PlacedCount") :: number? or 0) else 0
	local full = placed >= Economy.unlockedPedestals(Store.state.upgrades)
	if anyStolen then
		carryHeader.Text = Emoji.label("alarm", Locale.t("hud.stolen"))
		carryHeader.TextColor3 = Theme.Colors.Warning
		carryStroke.Color = Theme.Colors.Danger
		carryStroke.Thickness = Theme.Outline.Thick + (math.sin(os.clock() * 8) + 1) * 1.5
		carryPanel.BackgroundColor3 = Theme.Colors.Panel:Lerp(Theme.Colors.Danger, 0.35 + (math.sin(os.clock() * 8) + 1) * 0.1)
		carryHint.Text = Locale.t("hud.autoReturn", { time = Format.clock(stolenUntil - workspace:GetServerTimeNow()) })
		carryHint.TextColor3 = Theme.Colors.Warning
		dissolveButton.instance.Visible = false
	else
		carryHeader.Text = Emoji.label("carry", Locale.t("hud.carrying"))
		carryHeader.TextColor3 = Theme.Colors.Text
		carryStroke.Color = Theme.Colors.Ink
		carryStroke.Thickness = Theme.Outline.Regular
		carryPanel.BackgroundColor3 = Theme.Colors.Panel
		carryHint.Text = if full then Locale.t("hud.pedestalsFull") else Locale.t("hud.returnHome")
		carryHint.TextColor3 = if full then Theme.Colors.Warning else Theme.Colors.Text
		dissolveButton.instance.Visible = full
	end
end

local function updateAbilities()
	local status = Store.state.status
	local t = Store.now()
	for _, view in abilityViews do
		local remaining = Abilities.remaining(view.key)
		local duration = Abilities.duration(view.key)
		-- Shield / Spectral Phase: glowing ring while the effect is on.
		local activeUntil = if view.key == "shield" then status.shieldUntil elseif view.key == "phase" then status.phaseUntil else 0
		if activeUntil > t then
			view.stroke.Thickness = Theme.Outline.Thick + 1.5
			view.stroke.Color = Theme.Colors.Gold
		elseif view.stroke.Thickness > Theme.Outline.Regular + 0.1 then
			view.stroke.Thickness = Theme.Outline.Regular
			view.stroke.Color = Theme.Colors.Ink
		end
		-- Grapple: dimmed when no anchor is in reach.
		view.dim.Visible = view.key == "grapple" and remaining <= 0.05 and GrappleTargeting.current() == nil
		local sealedUntil = 0
		if view.key == "seal" then
			local model = Store.plotModel()
			local value = model and model:GetAttribute("SealedUntil")
			sealedUntil = if type(value) == "number" then value else 0
		end
		local sealActive = sealedUntil > workspace:GetServerTimeNow()
		if remaining > 0.05 then
			local fraction = math.clamp(remaining / duration, 0, 1)
			view.overlay.Visible = true
			local edge = math.clamp(1 - fraction, 0.001, 0.999)
			view.gradient.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(edge - 0.001, 1),
				NumberSequenceKeypoint.new(edge, 0.25),
				NumberSequenceKeypoint.new(1, 0.25),
			})
			view.countdown.Text = if sealActive then Format.clock(sealedUntil - workspace:GetServerTimeNow()) elseif remaining >= 10 then tostring(math.ceil(remaining)) else string.format("%.1f", remaining)
			view.countdown.TextColor3 = if sealActive then Theme.Colors.Gold else Theme.Colors.Text
			view.wasReady = false
		else
			view.overlay.Visible = false
			view.countdown.Text = ""
			if not view.wasReady then
				view.wasReady = true
				Tween.pop(view.frame, 0.2)
				-- "Ready!" flash: white outline that settles back to ink.
				view.stroke.Color = Color3.new(1, 1, 1)
				Tween.play(view.stroke, 0.5, { Color = Theme.Colors.Ink })
			end
		end
	end
end

----------------------------------------------------------------------------
-- Effects
----------------------------------------------------------------------------

function Hud.pulseEssence()
	local scale = essenceIcon:FindFirstChildOfClass("UIScale")
	if scale then
		scale.Scale = 1.35
		Tween.play(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	local stroke = essenceCard:FindFirstChild("Stroke") :: UIStroke?
	if stroke then
		stroke.Color = Theme.Colors.Essence
		Tween.play(stroke, 0.6, { Color = Theme.Colors.Ink })
	end
end

-- Essence orbs flying from the Core to the counter.
function Hud.collect(amount: number)
	local camera = workspace.CurrentCamera
	local corePosition = SanctuaryFX.corePosition(Store.state.plot)
	if not camera or not corePosition then
		Hud.pulseEssence()
		return
	end
	local screen, onScreen = camera:WorldToViewportPoint(corePosition)
	local inset = GuiService:GetGuiInset()
	local target = essenceIcon.AbsolutePosition + essenceIcon.AbsoluteSize / 2 + inset
	local start = if onScreen then Vector2.new(screen.X, screen.Y) else Vector2.new(target.X + 300, target.Y + 200)
	local count = math.clamp(math.floor(math.log10(math.max(amount, 1)) * 4) + 4, 5, 18)
	-- "+250!" pops next to the counter when the orbs land.
	task.delay(0.75, function()
		local at = essenceLabel.AbsolutePosition + Vector2.new(essenceLabel.AbsoluteSize.X * 0.5, -6) + inset
		Juice.floatText(fullscreen, "+" .. Format.abbrev(amount), at, Theme.Colors.Essence, 30)
	end)
	for i = 1, count do
		local orb = Create("Frame", {
			Size = UDim2.fromOffset(20, 20),
			Position = UDim2.fromOffset(start.X, start.Y),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Parent = fullscreen,
		})
		Icons.essence(orb)
		local spread = Vector2.new(math.random(-90, 90), math.random(-90, 40))
		local mid = start + spread
		task.delay(i * 0.035, function()
			Tween.play(orb, 0.25, { Position = UDim2.fromOffset(mid.X, mid.Y) }, Enum.EasingStyle.Quad)
			task.delay(0.25, function()
				Tween.play(orb, 0.45, { Position = UDim2.fromOffset(target.X, target.Y), Size = UDim2.fromOffset(12, 12) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
				task.delay(0.45, function()
					orb:Destroy()
					Audio.play("EssenceTick", { pitch = 1 + i * 0.05 })
					Hud.pulseEssence()
				end)
			end)
		end)
	end
	Audio.play("EssenceCollect")
end

local dangerToken = 0
function Hud.flashDanger(duration: number?)
	dangerToken += 1
	local token = dangerToken
	vignette.Visible = true
	for _, frame in vignette:GetChildren() do
		if frame:IsA("Frame") then
			frame.BackgroundTransparency = 0
			Tween.play(frame, duration or 1.2, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
		end
	end
	task.delay(duration or 1.2, function()
		if token == dangerToken then
			vignette.Visible = false
		end
	end)
end

function Hud.menuButton(name: string): GuiObject?
	local button = menuButtons[name]
	return if button then button.instance else nil
end

----------------------------------------------------------------------------
-- Init
----------------------------------------------------------------------------

export type Options = {
	touch: boolean,
	open: (string) -> (),
}

function Hud.init(parent: Instance, fullscreenLayer: Frame, options: Options)
	touch = options.touch
	openModal = options.open
	fullscreen = fullscreenLayer

	local column = Create("Frame", {
		Name = "LeftColumn",
		Size = UDim2.fromOffset(270, 360),
		Position = if touch then UDim2.new(0, 12, 0.36, 0) else UDim2.new(0, 16, 0.5, -20),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	Style.list(column, 10, Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Left)
	buildEssence(column)
	buildMenu(column)
	if not touch then
		buildGoal(column, 4)
	end
	buildAbilities(parent)
	buildCarry(parent)
	buildVignette()

	displayedEssence = Store.state.essence
	refreshStatic()
	Store.changed:Connect(function(state, previous)
		refreshStatic()
		rebuildCarry()
		if state.essence > previous.essence and state.essence - previous.essence >= 1 then
			Tween.pop(essenceLabel, 0.06)
		end
	end)
	RelicRenderer.recordAdded:Connect(function()
		if #Store.state.carrying > 0 then
			rebuildCarry()
		end
	end)
	Locale.changed:Connect(function()
		refreshMenuText()
		refreshStatic()
		carriedKey = ""
		rebuildCarry()
	end)

	-- Under attack: red vignette pulses while someone steals from you.
	task.spawn(function()
		while true do
			task.wait(0.9)
			local model = Store.plotModel()
			local attacker = model and model:GetAttribute("UnderAttack")
			if type(attacker) == "number" and attacker ~= 0 then
				Hud.flashDanger(0.85)
				Audio.play("StealAlert", { volume = 0.7 })
			end
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		local target = Store.state.essence
		if math.abs(target - displayedEssence) < 0.5 then
			displayedEssence = target
		else
			displayedEssence += (target - displayedEssence) * MathUtil.damp(9, dt)
		end
		essenceLabel.Text = formatEssence(math.floor(displayedEssence + 0.5))
		updateAbilities()
		updateStatus()
		updateCarry()
	end)
end

return Hud
