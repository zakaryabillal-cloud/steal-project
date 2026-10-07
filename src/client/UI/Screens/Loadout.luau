--!strict
-- Abilities modal (the loadout screen).
--
--   * one section per slot (Mobility Q/R1, Control F/L1, Utility R/R2), one
--     card per ability: name, description, effective numbers (harmonies
--     included), harmony badge, and one action button:
--       Equip / Equipped / Remove (Utility) — only usable inside your own
--       Sanctuary (the server checks again);
--       Unlock (Power record + Essence) — usable anywhere.
--   * a Harmonies section: the 6 relics, whether each is displayed in your
--     Sanctuary, and an on/off switch (inside your Sanctuary).
-- Big touch targets (48 px buttons), one scrolling column: works on phones.
-- The screen only sends requests; the server validates everything.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Theme = require(Shared.Config.Theme)
local AbilityConfig = require(Shared.Config.Abilities)
local GameConfig = require(Shared.Config.GameConfig)
local Layout = require(Shared.Layout)
local Net = require(Shared.Net)
local Locale = require(Shared.Locale)
local Format = require(Shared.Util.Format)

local UIRoot = script.Parent.Parent
local Kit = UIRoot.Kit
local Create = require(Kit.Create)
local Style = require(Kit.Style)
local Tween = require(Kit.Tween)
local Icons = require(Kit.Icons)
local Button = require(Kit.Button)
local Modal = require(Kit.Modal)

local Controllers = UIRoot.Parent.Controllers
local Store = require(Controllers.Store)
local Audio = require(Controllers.Audio)
local ClientNet = require(UIRoot.Parent.ClientNet)

local Loadout = {}

type Card = {
	def: AbilityConfig.AbilityDef,
	slotIndex: number,
	frame: Frame,
	stroke: UIStroke,
	name: TextLabel,
	desc: TextLabel,
	stats: TextLabel,
	badge: TextLabel,
	requirement: TextLabel,
	action: Button.Button,
	busy: boolean,
}

type HarmonyRow = {
	harmony: AbilityConfig.HarmonyDef,
	frame: Frame,
	title: TextLabel,
	desc: TextLabel,
	state: TextLabel,
	toggle: Button.Button,
	busy: boolean,
}

local modal: Modal.Modal
local cards: { Card } = {}
local rows: { HarmonyRow } = {}
local slotHeaders: { [number]: TextLabel } = {}
local harmonyHeader: TextLabel
local harmonyHint: TextLabel
local powerLabel: TextLabel
local essenceLabel: TextLabel

local localPlayer = Players.LocalPlayer

local GAMEPAD_NAMES: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.ButtonR1] = "R1",
	[Enum.KeyCode.ButtonL1] = "L1",
	[Enum.KeyCode.ButtonR2] = "R2",
}

-- Same test as the server's (display only: the server decides).
function Loadout.atHome(): boolean
	local plot = Store.state.plot
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if plot == 0 or not root or not root:IsA("BasePart") then
		return false
	end
	local rel = Layout.plotCFrame(plot):PointToObjectSpace(root.Position)
	return math.sqrt(rel.X * rel.X + rel.Z * rel.Z) <= Layout.PlatformRadius - 0.5 and rel.Y > -4 and rel.Y < 40
end

local function harmonies(): { [string]: boolean }
	return AbilityConfig.activeHarmonies(Store.state.harmonies, Store.state.harmonyOff)
end

local function num(value: number): string
	if math.abs(value - math.floor(value)) < 0.01 then
		return tostring(math.floor(value))
	end
	return string.format("%.1f", value)
end

function Loadout.statsText(def: AbilityConfig.AbilityDef, active: { [string]: boolean }): string
	local t = AbilityConfig.tuning(def, active)
	return Locale.t("ability." .. def.id .. ".stats", {
		cd = num(AbilityConfig.cooldown(def, active)),
		range = num(t.Range or 0),
		carry = num((t.Range or 0) * (t.CarryFactor or 1)),
		radius = num(t.Radius or 0),
		stun = num(t.Stun or 0),
		slow = num((t.Slow or 0) * 100),
		duration = num(t.SlowDuration or t.Duration or 0),
		arm = num(t.ArmTime or 0),
		self = num((t.SelfSlow or 0) * 100),
	})
end

function Loadout.harmonyText(relic: string): string
	local H = GameConfig.Harmonies
	if relic == "storm_crystal" then
		return Locale.t("harmony.storm_crystal", { slow = num(H.StormTrail.Slow * 100), duration = num(H.StormTrail.SlowDuration) })
	elseif relic == "void_cube" then
		return Locale.t("harmony.void_cube", { range = num(H.VoidBlink.Range), carry = num(H.VoidBlink.CarryFactor) })
	elseif relic == "magma_heart" then
		return Locale.t("harmony.magma_heart", { radius = num(H.Eruption.Radius), cd = num(H.Eruption.Cooldown) })
	elseif relic == "frost_lotus" then
		return Locale.t("harmony.frost_lotus", { radius = num(H.FrostLotus.Radius), slow = num(H.FrostLotus.Slow * 100), duration = num(H.FrostLotus.SlowDuration) })
	elseif relic == "chrono_glass" then
		return Locale.t("harmony.chrono_glass", { percent = num((1 - H.ChronoGlass.CooldownFactor) * 100) })
	end
	return Locale.t("harmony.cosmic_eye", { range = num(H.CosmicEye.RevealRadius) })
end

local function shake(frame: GuiObject)
	local origin = frame.Position
	Tween.play(frame, 0.05, { Position = origin + UDim2.fromOffset(6, 0) })
	task.delay(0.05, function()
		Tween.play(frame, 0.3, { Position = origin }, Enum.EasingStyle.Elastic)
	end)
end

local refreshAll: () -> ()

local function request(card: Card, fn: string, ...: any)
	if card.busy then
		return
	end
	card.busy = true
	local args = table.pack(...)
	task.spawn(function()
		local ok = ClientNet.invoke(fn, table.unpack(args, 1, args.n))
		card.busy = false
		if ok then
			Audio.play(if fn == Net.Functions.UnlockAbility then "Purchase" else "UiClick")
			Tween.pop(card.frame, 0.04)
		else
			Audio.play("UiError")
			shake(card.frame)
		end
		refreshAll()
	end)
end

local function refreshCard(card: Card, home: boolean, active: { [string]: boolean })
	local state = Store.state
	local def = card.def
	local unlocked = state.unlocked[def.id] == true
	local equipped = state.loadout[card.slotIndex] == def.id
	local isEruption = def.id == "pulse" and active.magma_heart == true
	card.name.Text = if isEruption then Locale.t("ability.eruption") else Locale.t("ability." .. def.id)
	card.desc.Text = Locale.t("ability." .. def.id .. ".desc")
	card.stats.Text = Loadout.statsText(def, active)
	local relics = AbilityConfig.harmoniesFor(def, active)
	card.badge.Text = if #relics > 0 then Locale.t("harmony.badge", { relic = Locale.relicName(relics[1]) }) else ""
	card.stroke.Color = if equipped then def.color else Theme.Colors.Stroke
	card.stroke.Transparency = if equipped then 0.1 else Theme.Transparency.Stroke
	card.requirement.Text = ""
	if not unlocked then
		local requirement = def.unlock
		local powerOk = requirement ~= nil and state.powerPeak >= requirement.power
		local essenceOk = requirement ~= nil and state.essence >= requirement.essence
		if requirement then
			card.requirement.Text = Locale.t("loadout.needPower", { power = Format.commas(requirement.power) }) .. "  ·  " .. Format.abbrev(requirement.essence) .. " " .. Locale.t("common.essence")
			card.requirement.TextColor3 = if powerOk and essenceOk then Theme.Colors.Success elseif powerOk then Theme.Colors.Warning else Theme.Colors.TextMuted
		end
		card.action:setText(Locale.t("loadout.unlock"))
		card.action:setEnabled(powerOk and essenceOk and not card.busy)
	elseif equipped then
		local slot = AbilityConfig.Slots[card.slotIndex]
		if slot.optional then
			card.action:setText(Locale.t("loadout.remove"))
			card.action:setEnabled(home and not card.busy)
		else
			card.action:setText(Locale.t("loadout.equipped"))
			card.action:setEnabled(false)
		end
	else
		card.action:setText(if home then Locale.t("loadout.equip") else Locale.t("loadout.goHome"))
		card.action:setEnabled(home and not card.busy)
	end
end

local function refreshRow(row: HarmonyRow, home: boolean)
	local relic = row.harmony.relic
	local displayed = table.find(Store.state.harmonies, relic) ~= nil
	local off = Store.state.harmonyOff[relic] == true
	row.title.Text = Locale.relicName(relic)
	row.desc.Text = Loadout.harmonyText(relic)
	if not displayed then
		row.state.Text = Locale.t("harmony.missing")
		row.state.TextColor3 = Theme.Colors.TextMuted
	elseif off then
		row.state.Text = Locale.t("harmony.off")
		row.state.TextColor3 = Theme.Colors.Warning
	else
		row.state.Text = Locale.t("harmony.active")
		row.state.TextColor3 = Theme.Colors.Success
	end
	row.toggle:setText(if off then Locale.t("harmony.turnOn") else Locale.t("harmony.turnOff"))
	row.toggle:setEnabled(home and not row.busy)
end

refreshAll = function()
	if not modal then
		return
	end
	local home = Loadout.atHome()
	local active = harmonies()
	modal.title.Text = Locale.t("loadout.title")
	modal.subtitle.Text = if home then Locale.t("loadout.home") else Locale.t("loadout.away")
	powerLabel.Text = Format.commas(math.floor(Store.state.powerPeak))
	essenceLabel.Text = Format.abbrev(Store.state.essence)
	for index, slot in AbilityConfig.Slots do
		local header = slotHeaders[index]
		if header then
			header.Text = Locale.t("loadout.slot." .. slot.id) .. "   " .. Locale.t("loadout.keys", { key = slot.keyboard.Name, pad = GAMEPAD_NAMES[slot.gamepad] or slot.gamepad.Name })
		end
	end
	harmonyHeader.Text = Locale.t("harmony.title")
	harmonyHint.Text = Locale.t("harmony.hint")
	for _, card in cards do
		refreshCard(card, home, active)
	end
	for _, row in rows do
		refreshRow(row, home)
	end
end

local function sectionHeader(parent: Instance, order: number): TextLabel
	return Style.text({
		Size = UDim2.new(1, -8, 0, 28),
		LayoutOrder = order,
		FontFace = Theme.Fonts.Heavy,
		TextSize = 15,
		TextColor3 = Theme.Colors.TextDim,
		Parent = parent,
	})
end

local function buildCard(parent: Instance, def: AbilityConfig.AbilityDef, slotIndex: number, order: number)
	local frame: Frame = Create("Frame", {
		Name = def.id,
		Size = UDim2.new(1, -8, 0, 112),
		BackgroundColor3 = Theme.Colors.PanelLight,
		BackgroundTransparency = 0.2,
		LayoutOrder = order,
		Parent = parent,
	})
	Style.corner(frame, Theme.Radius.Large)
	local stroke = Style.stroke(frame)
	stroke.Thickness = 2
	local tile = Create("Frame", {
		Size = UDim2.fromOffset(64, 64),
		Position = UDim2.new(0, 14, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Theme.Colors.Panel,
		Parent = frame,
	})
	Style.corner(tile, UDim.new(1, 0))
	Style.stroke(tile, def.color, 0, 2.5)
	local iconHolder = Create("Frame", {
		Size = UDim2.fromScale(0.55, 0.55),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = tile,
	})
	local icon = (Icons :: any)[def.icon] or Icons.pulse
	icon(iconHolder, def.color)
	local name = Style.text({ Size = UDim2.new(1, -250, 0, 24), Position = UDim2.fromOffset(92, 8), FontFace = Theme.Fonts.Heavy, TextSize = 19, Parent = frame })
	local badge = Style.text({ Size = UDim2.new(0, 150, 0, 18), Position = UDim2.new(1, -168, 0, 10), FontFace = Theme.Fonts.Heavy, TextSize = 12, TextColor3 = Theme.Colors.Gold, TextXAlignment = Enum.TextXAlignment.Right, Parent = frame })
	local desc = Style.text({ Size = UDim2.new(1, -250, 0, 36), Position = UDim2.fromOffset(92, 32), FontFace = Theme.Fonts.Body, TextSize = 14, TextColor3 = Theme.Colors.TextDim, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Parent = frame })
	local stats = Style.text({ Size = UDim2.new(1, -250, 0, 18), Position = UDim2.fromOffset(92, 70), FontFace = Theme.Fonts.BodyBold, TextSize = 13, TextColor3 = def.color, TextTruncate = Enum.TextTruncate.AtEnd, Parent = frame })
	local requirement = Style.text({ Size = UDim2.new(1, -110, 0, 16), Position = UDim2.fromOffset(92, 90), FontFace = Theme.Fonts.BodyBold, TextSize = 12, TextColor3 = Theme.Colors.TextMuted, Parent = frame })
	local card: Card
	local action = Button.new({
		name = "Action",
		size = UDim2.fromOffset(136, 48),
		position = UDim2.new(1, -14, 0.5, 6),
		anchor = Vector2.new(1, 0.5),
		color = Color3.new(1, 1, 1),
		gradient = { def.color, Theme.Colors.EssenceDeep },
		corner = Theme.Radius.Medium,
		text = "",
		textSize = 17,
		parent = frame,
		onClick = function()
			local state = Store.state
			if not state.unlocked[def.id] then
				request(card, Net.Functions.UnlockAbility, def.id)
			elseif state.loadout[slotIndex] == def.id then
				request(card, Net.Functions.SetLoadout, slotIndex, "")
			else
				request(card, Net.Functions.SetLoadout, slotIndex, def.id)
			end
		end,
	})
	card = { def = def, slotIndex = slotIndex, frame = frame, stroke = stroke, name = name, desc = desc, stats = stats, badge = badge, requirement = requirement, action = action, busy = false }
	table.insert(cards, card)
end

local function buildHarmonyRow(parent: Instance, harmony: AbilityConfig.HarmonyDef, order: number)
	local frame: Frame = Create("Frame", {
		Name = "Harmony_" .. harmony.relic,
		Size = UDim2.new(1, -8, 0, 78),
		BackgroundColor3 = Theme.Colors.PanelLight,
		BackgroundTransparency = 0.35,
		LayoutOrder = order,
		Parent = parent,
	})
	Style.corner(frame, Theme.Radius.Medium)
	local iconHolder = Create("Frame", { Size = UDim2.fromOffset(30, 30), Position = UDim2.new(0, 14, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundTransparency = 1, Parent = frame })
	local icon = (Icons :: any)[harmony.icon] or Icons.eye
	icon(iconHolder, Theme.Colors.Gold)
	local title = Style.text({ Size = UDim2.new(1, -230, 0, 22), Position = UDim2.fromOffset(56, 8), FontFace = Theme.Fonts.Heavy, TextSize = 16, Parent = frame })
	local state = Style.text({ Size = UDim2.new(0, 120, 0, 18), Position = UDim2.new(1, -150, 0, 6), FontFace = Theme.Fonts.Heavy, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right, Parent = frame })
	local desc = Style.text({ Size = UDim2.new(1, -200, 0, 40), Position = UDim2.fromOffset(56, 32), FontFace = Theme.Fonts.Body, TextSize = 13, TextColor3 = Theme.Colors.TextDim, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Parent = frame })
	local row: HarmonyRow
	local toggle = Button.new({
		name = "Toggle",
		size = UDim2.fromOffset(120, 44),
		position = UDim2.new(1, -12, 0.5, 8),
		anchor = Vector2.new(1, 0.5),
		color = Theme.Colors.PanelRaised,
		corner = Theme.Radius.Medium,
		text = "",
		textSize = 15,
		parent = frame,
		onClick = function()
			if row.busy then
				return
			end
			row.busy = true
			local enable = Store.state.harmonyOff[harmony.relic] == true
			task.spawn(function()
				local ok = ClientNet.invoke(Net.Functions.SetHarmony, harmony.relic, enable)
				row.busy = false
				Audio.play(if ok then "UiClick" else "UiError")
				refreshAll()
			end)
		end,
	})
	row = { harmony = harmony, frame = frame, title = title, desc = desc, state = state, toggle = toggle, busy = false }
	table.insert(rows, row)
end

function Loadout.init(parent: Instance, close: () -> ()): Modal.Modal
	modal = Modal.new({ name = "Loadout", size = UDim2.fromOffset(680, 700), parent = parent, onClose = close, accent = Color3.fromRGB(170, 120, 255) })
	-- Power record + Essence pills in the header.
	local pills = Create("Frame", {
		Size = UDim2.fromOffset(250, 40),
		Position = UDim2.new(1, -54, 0, 2),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Parent = modal.header,
	})
	Style.list(pills, 8, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Right)
	local function pill(order: number, icon: (Instance) -> ()): TextLabel
		local frame = Create("Frame", { Size = UDim2.fromOffset(118, 40), BackgroundColor3 = Theme.Colors.PanelRaised, LayoutOrder = order, Parent = pills })
		Style.corner(frame, UDim.new(1, 0))
		local holder = Create("Frame", { Size = UDim2.fromOffset(22, 22), Position = UDim2.new(0, 10, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundTransparency = 1, Parent = frame })
		icon(holder)
		return Style.text({ Size = UDim2.new(1, -42, 1, 0), Position = UDim2.fromOffset(38, 0), FontFace = Theme.Fonts.Display, TextSize = 18, Parent = frame })
	end
	powerLabel = pill(1, function(holder)
		Icons.power(holder, Theme.Colors.Gold)
	end)
	essenceLabel = pill(2, function(holder)
		Icons.essence(holder)
	end)

	local scroll: ScrollingFrame = Create("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = Theme.Colors.TextMuted,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = modal.body,
	})
	Style.list(scroll, 8)
	Style.padding(scroll, 4, 2)
	local order = 0
	for index, slot in AbilityConfig.Slots do
		order += 1
		slotHeaders[index] = sectionHeader(scroll, order)
		local defs = {}
		for _, def in AbilityConfig.list do
			if def.slot == slot.id then
				table.insert(defs, def)
			end
		end
		table.sort(defs, function(a, b)
			return a.order < b.order
		end)
		for _, def in defs do
			order += 1
			buildCard(scroll, def, index, order)
		end
	end
	order += 1
	harmonyHeader = sectionHeader(scroll, order)
	order += 1
	harmonyHint = Style.text({ Size = UDim2.new(1, -8, 0, 20), LayoutOrder = order, FontFace = Theme.Fonts.Body, TextSize = 13, TextColor3 = Theme.Colors.TextMuted, TextWrapped = true, Parent = scroll })
	for _, harmony in AbilityConfig.Harmonies do
		order += 1
		buildHarmonyRow(scroll, harmony, order)
	end

	refreshAll()
	Store.changed:Connect(refreshAll)
	Locale.changed:Connect(refreshAll)
	-- Walking in / out of the Sanctuary while the screen is open.
	task.spawn(function()
		local wasHome = Loadout.atHome()
		while true do
			task.wait(0.5)
			local home = Loadout.atHome()
			if home ~= wasHome then
				wasHome = home
				refreshAll()
			end
		end
	end)
	return modal
end

-- Tests / debug.
function Loadout.cards(): { Card }
	return cards
end

return Loadout
