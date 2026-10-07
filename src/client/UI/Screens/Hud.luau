--!strict
-- Main heads-up display:
--   left   : Essence counter + Power Level, menu buttons (Upgrades / RiftDex / Settings), next goal
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
	essenceCard = Style.panel({
		Name = "Essence",
		Size = UDim2.fromOffset(250, 102),
		LayoutOrder = 1,
		Parent = parent,
	})
	local stroke = essenceCard:FindFirstChildOfClass("UIStroke") :: UIStroke
	stroke.Name = "Stroke"
	essenceIcon = Create("Frame", {
		Size = UDim2.fromOffset(48, 48),
		Position = UDim2.new(0, 12, 0, 38),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
		Parent = essenceCard,
	})
	Icons.essence(essenceIcon)
	Create("UIScale", { Parent = essenceIcon })
	essenceLabel = Style.text({
		Size = UDim2.new(1, -78, 0, 38),
		Position = UDim2.fromOffset(68, 6),
		FontFace = Theme.Fonts.Display,
		TextSize = 34,
		Text = "0",
		Parent = essenceCard,
	})
	Style.textStroke(essenceLabel, 0.6, 1.5)
	rateLabel = Style.text({
		Size = UDim2.new(1, -78, 0, 20),
		Position = UDim2.fromOffset(69, 46),
		FontFace = Theme.Fonts.BodyBold,
		TextSize = 15,
		TextColor3 = Theme.Colors.Essence,
		Text = "+0/s",
		Parent = essenceCard,
	})

	-- Power Level row (progression summary, never spent).
	Create("Frame", {
		Name = "Divider",
		Size = UDim2.new(1, -24, 0, 1),
		Position = UDim2.fromOffset(12, 74),
		BackgroundColor3 = Theme.Colors.Stroke,
		BackgroundTransparency = 0.88,
		BorderSizePixel = 0,
		Parent = essenceCard,
	})
	local powerIcon = Create("Frame", {
		Name = "PowerIcon",
		Size = UDim2.fromOffset(16, 16),
		Position = UDim2.fromOffset(14, 80),
		BackgroundTransparency = 1,
		Parent = essenceCard,
	})
	Icons.power(powerIcon, Theme.Colors.Power)
	powerLabel = Style.text({
		Name = "Power",
		Size = UDim2.new(0.6, -36, 0, 20),
		Position = UDim2.fromOffset(36, 78),
		FontFace = Theme.Fonts.BodyBold,
		TextSize = 15,
		TextColor3 = Theme.Colors.Power,
		Text = Locale.t("hud.power") .. " 0",
		Parent = essenceCard,
	})
	powerPeakLabel = Style.text({
		Name = "PowerPeak",
		Size = UDim2.new(0.4, -12, 0, 20),
		Position = UDim2.new(0.6, 0, 0, 78),
		TextXAlignment = Enum.TextXAlignment.Right,
		FontFace = Theme.Fonts.Body,
		TextSize = 13,
		TextColor3 = Theme.Colors.TextDim,
		Text = "",
		Parent = essenceCard,
	})
end

local function menuButton(parent: Instance, name: string, order: number, label: string, icon: (Instance, Color3) -> Frame): Button.Button
	local button = Button.new({
		name = name,
		size = UDim2.fromOffset(78, 64),
		color = Theme.Colors.Panel,
		transparency = Theme.Transparency.Panel,
		corner = Theme.Radius.Large,
		layoutOrder = order,
		parent = parent,
		onClick = function()
			openModal(name)
		end,
	})
	local holder = Create("Frame", {
		Size = UDim2.fromOffset(30, 30),
		Position = UDim2.new(0.5, 0, 0, 8),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Parent = button.instance,
	})
	icon(holder, Theme.Colors.Text)
	local caption = Style.text({
		Name = "Caption",
		Size = UDim2.new(1, -4, 0, 16),
		Position = UDim2.new(0.5, 0, 1, -6),
		AnchorPoint = Vector2.new(0.5, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 12,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = Theme.Colors.TextDim,
		Text = label,
		Parent = button.instance,
	})
	caption:SetAttribute("Key", label)
	menuButtons[name] = button
	return button
end

local function buildMenu(parent: Instance)
	local row = Create("Frame", {
		Name = "Menu",
		Size = UDim2.fromOffset(250, 64),
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = parent,
	})
	Style.list(row, 8, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Left)
	local upgrades = menuButton(row, "Shop", 1, Locale.t("hud.upgrades"), Icons.upgrades)
	local dex = menuButton(row, "Dex", 2, Locale.t("hud.dex"), Icons.dex)
	menuButton(row, "Settings", 3, Locale.t("hud.settings"), Icons.settings)

	upgradesBadge = Create("Frame", {
		Size = UDim2.fromOffset(18, 18),
		Position = UDim2.new(1, -4, 0, 4),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Theme.Colors.Success,
		Visible = false,
		ZIndex = 3,
		Parent = upgrades.instance,
	})
	Style.corner(upgradesBadge, UDim.new(1, 0))
	Style.stroke(upgradesBadge, Theme.Colors.Panel, 0, 2)
	Style.text({ Text = "!", TextXAlignment = Enum.TextXAlignment.Center, TextSize = 13, FontFace = Theme.Fonts.Heavy, TextColor3 = Theme.Colors.Panel, ZIndex = 4, Parent = upgradesBadge })

	local chip = Create("Frame", {
		Size = UDim2.fromOffset(40, 18),
		Position = UDim2.new(1, -2, 0, 2),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Theme.Colors.PanelRaised,
		ZIndex = 3,
		Parent = dex.instance,
	})
	Style.corner(chip, UDim.new(1, 0))
	dexChip = Style.text({ Text = "0/0", TextXAlignment = Enum.TextXAlignment.Center, TextSize = 11, FontFace = Theme.Fonts.Heavy, ZIndex = 4, Parent = chip })
end

local function buildGoal(parent: Instance, order: number)
	local button = Button.new({
		name = "NextGoal",
		size = UDim2.fromOffset(250, 62),
		color = Theme.Colors.Panel,
		transparency = Theme.Transparency.Panel,
		corner = Theme.Radius.Large,
		layoutOrder = order,
		parent = parent,
		hoverScale = 1.03,
		onClick = function()
			openModal("Shop")
		end,
	})
	goalFrame = button.instance :: any
	goalStroke = goalFrame:FindFirstChildOfClass("UIStroke") :: UIStroke
	Style.text({
		Name = "Caption",
		Size = UDim2.new(1, -24, 0, 14),
		Position = UDim2.fromOffset(14, 8),
		TextSize = 11,
		FontFace = Theme.Fonts.Heavy,
		TextColor3 = Theme.Colors.TextMuted,
		Text = Locale.t("hud.nextGoal"),
		Parent = goalFrame,
	})
	goalName = Style.text({
		Size = UDim2.new(1, -110, 0, 22),
		Position = UDim2.fromOffset(14, 22),
		TextSize = 17,
		FontFace = Theme.Fonts.Heavy,
		Parent = goalFrame,
	})
	local costHolder = Create("Frame", {
		Size = UDim2.fromOffset(16, 16),
		Position = UDim2.new(1, -96, 0, 25),
		BackgroundTransparency = 1,
		Parent = goalFrame,
	})
	Icons.essence(costHolder)
	goalCost = Style.text({
		Size = UDim2.fromOffset(74, 22),
		Position = UDim2.new(1, -78, 0, 22),
		TextSize = 16,
		FontFace = Theme.Fonts.Display,
		Parent = goalFrame,
	})
	local back = Create("Frame", {
		Size = UDim2.new(1, -28, 0, 5),
		Position = UDim2.new(0, 14, 1, -11),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.85,
		Parent = goalFrame,
	})
	Style.corner(back, UDim.new(1, 0))
	goalBar = Create("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), Parent = back })
	Style.corner(goalBar, UDim.new(1, 0))
	Style.gradient(goalBar, Theme.Colors.Essence, Theme.Colors.EssenceDeep)
end

local function abilityButton(parent: Instance, key: string, size: number, position: UDim2, keyLabel: string, icon: (Instance, Color3) -> Frame, color: Color3, action: () -> ()): AbilityView
	local button = Button.new({
		name = key,
		size = UDim2.fromOffset(size, size),
		position = position,
		anchor = Vector2.new(0.5, 0.5),
		color = Theme.Colors.Panel,
		transparency = 0.1,
		corner = UDim.new(1, 0),
		strokeColor = color,
		parent = parent,
		silent = true,
		onClick = action,
	})
	local frame = button.instance
	local stroke = frame:FindFirstChildOfClass("UIStroke") :: UIStroke
	stroke.Thickness = 2.5
	local holder = Create("Frame", {
		Size = UDim2.fromScale(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = frame,
	})
	icon(holder, color)
	local overlay = Create("Frame", {
		Name = "Cooldown",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(8, 6, 16),
		BackgroundTransparency = 0.25,
		ZIndex = 3,
		Visible = false,
		Parent = frame,
	})
	Style.corner(overlay, UDim.new(1, 0))
	local dim = Create("Frame", {
		Name = "Unavailable",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(8, 6, 16),
		BackgroundTransparency = 0.45,
		ZIndex = 3,
		Visible = false,
		Parent = frame,
	})
	Style.corner(dim, UDim.new(1, 0))
	local gradient = Create("UIGradient", { Rotation = 90, Parent = overlay })
	local countdown = Style.text({
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = math.floor(size * 0.3),
		FontFace = Theme.Fonts.Display,
		ZIndex = 4,
		Text = "",
		Parent = frame,
	})
	Style.textStroke(countdown, 0.3, 2)
	if not touch then
		local chip = Create("Frame", {
			Size = UDim2.fromOffset(22, 20),
			Position = UDim2.new(0.5, 0, 1, 4),
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = 5,
			Parent = frame,
		})
		Style.corner(chip, UDim.new(0, 6))
		Style.text({ Text = keyLabel, TextXAlignment = Enum.TextXAlignment.Center, TextSize = 13, FontFace = Theme.Fonts.Heavy, TextColor3 = Theme.Colors.Panel, ZIndex = 6, Parent = chip })
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
	table.insert(abilityViews, abilityButton(abilityCluster, "seal", 60, UDim2.new(1, -58, 1, -148), if isGamepad() then "Y" else "G", Icons.seal, Color3.fromRGB(255, 205, 100), Abilities.seal))
	refreshAbilitySlots()

	-- Loadout screen: small round button left of the ability buttons.
	loadoutButton = Button.new({
		name = "LoadoutButton",
		size = UDim2.fromOffset(46, 46),
		position = UDim2.new(1, -214, 1, -42),
		anchor = Vector2.new(0.5, 0.5),
		color = Theme.Colors.Panel,
		transparency = 0.1,
		corner = UDim.new(1, 0),
		parent = abilityCluster,
		onClick = function()
			openModal("Loadout")
		end,
	})
	local holder = Create("Frame", {
		Size = UDim2.fromScale(0.52, 0.52),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = loadoutButton.instance,
	})
	Icons.loadout(holder, Theme.Colors.Text)
	loadoutBadge = Create("Frame", {
		Size = UDim2.fromOffset(16, 16),
		Position = UDim2.new(1, 2, 0, -2),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Theme.Colors.Success,
		Visible = false,
		ZIndex = 3,
		Parent = loadoutButton.instance,
	})
	Style.corner(loadoutBadge, UDim.new(1, 0))
	Style.text({ Text = "!", TextXAlignment = Enum.TextXAlignment.Center, TextSize = 12, FontFace = Theme.Fonts.Heavy, TextColor3 = Theme.Colors.Panel, ZIndex = 4, Parent = loadoutBadge })
	if not touch then
		local chip = Create("Frame", {
			Size = UDim2.fromOffset(22, 18),
			Position = UDim2.new(0.5, 0, 1, 4),
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = 5,
			Parent = loadoutButton.instance,
		})
		Style.corner(chip, UDim.new(0, 6))
		Style.text({ Text = if isGamepad() then "↑" else "L", TextXAlignment = Enum.TextXAlignment.Center, TextSize = 12, FontFace = Theme.Fonts.Heavy, TextColor3 = Theme.Colors.Panel, ZIndex = 6, Parent = chip })
	end

	-- Status chips above the buttons (only while something is active).
	statusRow = Create("Frame", {
		Name = "StatusRow",
		Size = UDim2.fromOffset(230, 24),
		Position = UDim2.new(1, 0, 1, -196),
		AnchorPoint = Vector2.new(1, 1),
		BackgroundTransparency = 1,
		Parent = abilityCluster,
	})
	Style.list(statusRow, 6, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Right)
end

local STATUS_ORDER = { "shield", "phase", "stun", "root", "slow" }
local STATUS_COLOR: { [string]: Color3 } = {
	shield = Color3.fromRGB(255, 215, 120),
	phase = Color3.fromRGB(120, 255, 220),
	stun = Color3.fromRGB(255, 230, 140),
	root = Color3.fromRGB(255, 160, 120),
	slow = Color3.fromRGB(140, 210, 255),
}

local function statusChip(kind: string): StatusChip
	local existing = statusChips[kind]
	if existing then
		return existing
	end
	local frame = Create("Frame", {
		Name = "Status_" .. kind,
		Size = UDim2.fromOffset(84, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.15,
		LayoutOrder = table.find(STATUS_ORDER, kind) or 9,
		Visible = false,
		Parent = statusRow,
	})
	Style.corner(frame, UDim.new(1, 0))
	Style.stroke(frame, STATUS_COLOR[kind], 0.2, 1.5)
	Style.padding(frame, 0, 8)
	local label = Style.text({
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		TextSize = 13,
		FontFace = Theme.Fonts.Heavy,
		TextColor3 = STATUS_COLOR[kind],
		Parent = frame,
	})
	local created = { frame = frame, label = label }
	statusChips[kind] = created
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
			chip.label.Text = text
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
		Size = UDim2.fromOffset(400, 0),
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
	local header = Create("Frame", { Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, LayoutOrder = 1, Parent = carryPanel })
	carryHeader = Style.text({ Size = UDim2.new(1, -80, 1, 0), TextSize = 13, FontFace = Theme.Fonts.Heavy, TextColor3 = Theme.Colors.TextDim, Parent = header })
	carryDistance = Style.text({ Size = UDim2.new(0, 80, 1, 0), Position = UDim2.new(1, -80, 0, 0), TextXAlignment = Enum.TextXAlignment.Right, TextSize = 15, FontFace = Theme.Fonts.Heavy, TextColor3 = Theme.Colors.Essence, Parent = header })
	carryRows = Create("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 2, Parent = carryPanel })
	Style.list(carryRows, 4)
	local footer = Create("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 3, Parent = carryPanel })
	carryHint = Style.text({ Size = UDim2.new(1, -120, 1, 0), TextSize = 15, TextWrapped = true, Parent = footer })
	dissolveButton = Button.new({
		name = "Dissolve",
		size = UDim2.fromOffset(110, 30),
		position = UDim2.new(1, 0, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		color = Theme.Colors.PanelRaised,
		text = Locale.t("hud.dissolve"),
		textSize = 14,
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
		local caption = button.instance:FindFirstChild("Caption") :: TextLabel?
		if caption then
			caption.Text = if name == "Shop" then Locale.t("hud.upgrades") elseif name == "Dex" then Locale.t("hud.dex") else Locale.t("hud.settings")
		end
	end
	if goalFrame then
		local caption = goalFrame:FindFirstChild("Caption") :: TextLabel?
		if caption then
			caption.Text = Locale.t("hud.nextGoal")
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
			goalStroke.Color = if ready then Theme.Colors.Success else Theme.Colors.Stroke
			goalStroke.Transparency = if ready then 0.2 else Theme.Transparency.Stroke
			goalCost.TextColor3 = if ready then Theme.Colors.Success else Theme.Colors.Text
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
		Style.text({
			Size = UDim2.new(1, -66, 0, 26),
			Position = UDim2.fromOffset(64, 4),
			TextSize = 19,
			FontFace = Theme.Fonts.Heavy,
			Text = Style.colored(Locale.relicTitle(record.relicId, record.mutation), color),
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = row,
		})
		local rate = Economy.relicBaseRate(record.relicId, record.level, record.mutation) * Store.state.multiplier
		Style.text({
			Size = UDim2.new(1, -66, 0, 20),
			Position = UDim2.fromOffset(64, 30),
			TextSize = 14,
			TextColor3 = Theme.Colors.TextDim,
			Text = string.format("%s  ·  %s/s", Locale.rarity(record.rarity.id), Format.abbrev(rate)),
			Parent = row,
		})
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
		carryDistance.Text = if distance < Layout.PlatformRadius then "✓" else string.format("%dm", math.floor(distance - Layout.PlatformRadius))
	else
		carryDistance.Text = ""
	end
	local myPlot = Store.plotModel()
	local placed = if myPlot then (myPlot:GetAttribute("PlacedCount") :: number? or 0) else 0
	local full = placed >= Economy.unlockedPedestals(Store.state.upgrades)
	if anyStolen then
		carryHeader.Text = Locale.t("hud.stolen")
		carryHeader.TextColor3 = Theme.Colors.Danger
		carryStroke.Color = Theme.Colors.Danger
		carryStroke.Transparency = 0.2 + (math.sin(os.clock() * 6) + 1) * 0.2
		carryHint.Text = Locale.t("hud.autoReturn", { time = Format.clock(stolenUntil - workspace:GetServerTimeNow()) })
		carryHint.TextColor3 = Theme.Colors.Warning
		dissolveButton.instance.Visible = false
	else
		carryHeader.Text = Locale.t("hud.carrying")
		carryHeader.TextColor3 = Theme.Colors.TextDim
		carryStroke.Color = Theme.Colors.Stroke
		carryStroke.Transparency = Theme.Transparency.Stroke
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
			view.stroke.Thickness = 4.5
			view.stroke.Transparency = 0
		elseif view.stroke.Thickness > 2.6 then
			view.stroke.Thickness = 2.5
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
				Tween.pop(view.frame, 0.15)
				view.stroke.Transparency = 0
				Tween.play(view.stroke, 0.6, { Transparency = 0.4 })
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
		stroke.Transparency = 0.1
		Tween.play(stroke, 0.6, { Transparency = Theme.Transparency.Stroke, Color = Theme.Colors.Stroke })
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
		Size = UDim2.fromOffset(250, 256),
		Position = if touch then UDim2.new(0, 12, 0.36, 0) else UDim2.new(0, 16, 0.5, -20),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	Style.list(column, 10, Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Left)
	buildEssence(column)
	buildMenu(column)
	if not touch then
		buildGoal(column, 3)
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
