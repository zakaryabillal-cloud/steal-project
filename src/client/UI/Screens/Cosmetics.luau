--!strict
-- Cosmetics modal ("Style"): one tab per category, one card per cosmetic.
--   * state at a glance: EQUIPPED (accent outline) / OWNED / LOCKED + how to
--     unlock it (with progress when the game can measure it);
--   * Equip / Unequip (owned only — the server checks ownership again);
--   * Try: a 5-second local preview on your own character / Sanctuary, also
--     for locked cosmetics (your client only, nobody else sees it).
-- Phones: tabs scroll sideways, cards wrap in a scrolling grid, 44 px buttons.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Theme = require(Shared.Config.Theme)
local Cosmetics = require(Shared.Config.Cosmetics)
local Rarities = require(Shared.Config.Rarities)
local Economy = require(Shared.Economy)
local Net = require(Shared.Net)
local Locale = require(Shared.Locale)

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
local CosmeticRenderer = require(Controllers.CosmeticRenderer)
local ClientNet = require(UIRoot.Parent.ClientNet)

local CosmeticsScreen = {}

type Card = {
	def: Cosmetics.CosmeticDef,
	frame: Frame,
	stroke: UIStroke,
	name: TextLabel,
	rarity: TextLabel,
	status: TextLabel,
	hint: TextLabel,
	action: Button.Button,
	try: Button.Button,
	busy: boolean,
}

local modal: Modal.Modal
local cards: { Card } = {}
local tabs: { [string]: Button.Button } = {}
local current = "trail"

local function colorsOf(def: Cosmetics.CosmeticDef): (Color3, Color3)
	local v = def.visual
	if v.colors then
		return v.colors[1], v.colors[2]
	elseif v.accent then
		return v.accent, v.motes or v.accent
	end
	return v.color or Color3.new(1, 1, 1), v.color2 or v.color or Color3.new(1, 1, 1)
end

local function progressData(): Cosmetics.Progress
	local state = Store.state
	local found = Store.dexCounts()
	return {
		powerPeak = state.powerPeak,
		stats = state.stats,
		dexFound = found,
		tier = Economy.tier(state.upgrades),
		-- Play time is not synced: no progress bar for it.
		playTime = 0,
	}
end

-- How to unlock `def`, e.g. "Reach Power record 150 · 62%".
function CosmeticsScreen.hintText(def: Cosmetics.CosmeticDef): string
	local u = def.unlock
	local key = "cos.unlock." .. u.kind
	if u.kind == "stat" then
		key ..= "." .. tostring(u.stat)
	end
	local value: any = u.value or 0
	if u.kind == "playtime" then
		value = math.floor((u.value or 0) / 3600 + 0.5)
	end
	local text = Locale.t(key, { value = value })
	if Cosmetics.UnlockKinds[u.kind].auto and u.kind ~= "starter" and u.kind ~= "playtime" then
		text ..= string.format("  ·  %d%%", math.floor(Cosmetics.progress(def, progressData()) * 100))
	end
	return text
end

local function request(card: Card, categoryId: string, id: string)
	if card.busy then
		return
	end
	card.busy = true
	task.spawn(function()
		local ok = ClientNet.invoke(Net.Functions.EquipCosmetic, categoryId, id)
		card.busy = false
		Audio.play(if ok then "UiClick" else "UiError")
		if ok then
			Tween.pop(card.frame, 0.04)
		end
		CosmeticsScreen.refresh()
	end)
end

local function refreshCard(card: Card)
	local state = Store.state.cosmetics
	local def = card.def
	local owned = state.owned[def.id] == true
	local equipped = state.equipped[def.category] == def.id
	card.frame.Visible = def.category == current
	card.name.Text = Locale.t("cos." .. def.id)
	card.rarity.Text = string.upper(Locale.rarity(def.rarity))
	card.stroke.Color = if equipped then Rarities.get(def.rarity).color else Theme.Colors.Stroke
	card.stroke.Transparency = if equipped then 0 else Theme.Transparency.Stroke
	card.stroke.Thickness = if equipped then 2.5 else 1
	if equipped then
		card.status.Text = Locale.t("cos.equipped")
		card.status.TextColor3 = Theme.Colors.Success
	elseif owned then
		card.status.Text = Locale.t("cos.owned")
		card.status.TextColor3 = Theme.Colors.Text
	else
		card.status.Text = "🔒 " .. Locale.t("cos.locked")
		card.status.TextColor3 = Theme.Colors.TextMuted
	end
	card.hint.Text = if owned then "" else CosmeticsScreen.hintText(def)
	card.action:setText(if equipped then Locale.t("cos.unequip") else Locale.t("cos.equip"))
	card.action:setEnabled(owned and not card.busy)
	card.try:setText(Locale.t("cos.preview"))
end

function CosmeticsScreen.refresh()
	if not modal then
		return
	end
	local owned, total = 0, #Cosmetics.list
	for _, def in Cosmetics.list do
		if Store.state.cosmetics.owned[def.id] then
			owned += 1
		end
	end
	modal.title.Text = Locale.t("cos.title")
	modal.subtitle.Text = Locale.t("cos.subtitle", { owned = owned, total = total })
	for id, tab in tabs do
		tab:setText(Locale.t("cos.cat." .. id))
		tab.instance.BackgroundColor3 = if id == current then Theme.Colors.Essence else Theme.Colors.PanelRaised
	end
	for _, card in cards do
		refreshCard(card)
	end
end

function CosmeticsScreen.select(categoryId: string)
	if Cosmetics.category(categoryId) then
		current = categoryId
		CosmeticsScreen.refresh()
	end
end

local function buildCard(parent: Instance, def: Cosmetics.CosmeticDef)
	local frame: Frame = Create("Frame", {
		Name = def.id,
		BackgroundColor3 = Theme.Colors.PanelLight,
		BackgroundTransparency = 0.2,
		LayoutOrder = def.order,
		Parent = parent,
	})
	Style.corner(frame, Theme.Radius.Large)
	local stroke = Style.stroke(frame)
	-- Swatch: the cosmetic's colours + its category icon.
	local a, b = colorsOf(def)
	local swatch = Create("Frame", {
		Size = UDim2.new(1, -16, 0, 46),
		Position = UDim2.fromOffset(8, 8),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = frame,
	})
	Style.corner(swatch, Theme.Radius.Medium)
	Style.gradient(swatch, a, b, 0)
	local iconHolder = Create("Frame", { Size = UDim2.fromOffset(28, 28), Position = UDim2.new(0, 10, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundTransparency = 1, Parent = swatch })
	local category = Cosmetics.category(def.category) :: Cosmetics.CategoryDef
	local icon = (Icons :: any)[category.icon] or Icons.dex
	icon(iconHolder, Color3.new(1, 1, 1))
	local rarity = Style.text({ Size = UDim2.new(1, -50, 0, 16), Position = UDim2.new(1, -8, 0, 6), AnchorPoint = Vector2.new(1, 0), FontFace = Theme.Fonts.Heavy, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Color3.new(1, 1, 1), Parent = swatch })
	Style.textStroke(rarity, 0.3, 1.5)
	local name = Style.text({ Size = UDim2.new(1, -16, 0, 20), Position = UDim2.fromOffset(8, 58), FontFace = Theme.Fonts.Heavy, TextSize = 15, TextTruncate = Enum.TextTruncate.AtEnd, Parent = frame })
	local status = Style.text({ Size = UDim2.new(1, -16, 0, 14), Position = UDim2.fromOffset(8, 78), FontFace = Theme.Fonts.Heavy, TextSize = 11, Parent = frame })
	local hint = Style.text({ Size = UDim2.new(1, -16, 0, 28), Position = UDim2.fromOffset(8, 92), FontFace = Theme.Fonts.Body, TextSize = 11, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = Theme.Colors.TextDim, Parent = frame })
	local card: Card
	local action = Button.new({
		name = "Action",
		size = UDim2.new(0.62, -10, 0, 44),
		position = UDim2.new(0, 8, 1, -8),
		anchor = Vector2.new(0, 1),
		color = Color3.new(1, 1, 1),
		gradient = { Color3.fromRGB(110, 225, 255), Color3.fromRGB(150, 105, 255) },
		corner = Theme.Radius.Medium,
		text = "",
		textSize = 15,
		parent = frame,
		onClick = function()
			local equipped = Store.state.cosmetics.equipped[def.category] == def.id
			request(card, def.category, if equipped then "" else def.id)
		end,
	})
	local try = Button.new({
		name = "Try",
		size = UDim2.new(0.38, -6, 0, 44),
		position = UDim2.new(1, -8, 1, -8),
		anchor = Vector2.new(1, 1),
		color = Theme.Colors.PanelRaised,
		corner = Theme.Radius.Medium,
		text = "",
		textSize = 14,
		parent = frame,
		onClick = function()
			if CosmeticRenderer.preview(def.id) then
				Audio.play("UiClick")
			end
		end,
	})
	card = { def = def, frame = frame, stroke = stroke, name = name, rarity = rarity, status = status, hint = hint, action = action, try = try, busy = false }
	table.insert(cards, card)
end

function CosmeticsScreen.init(parent: Instance, close: () -> ()): Modal.Modal
	modal = Modal.new({ name = "Cosmetics", size = UDim2.fromOffset(680, 640), parent = parent, onClose = close, accent = Color3.fromRGB(255, 160, 210) })
	-- Category tabs (scroll sideways on narrow screens).
	local tabRow: ScrollingFrame = Create("ScrollingFrame", {
		Name = "Tabs",
		Size = UDim2.new(1, 0, 0, 48),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		Parent = modal.body,
	})
	Style.list(tabRow, 6, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Left)
	for _, category in Cosmetics.Categories do
		tabs[category.id] = Button.new({
			name = "Tab_" .. category.id,
			size = UDim2.fromOffset(88, 44),
			color = Theme.Colors.PanelRaised,
			corner = UDim.new(1, 0),
			text = "",
			textSize = 14,
			layoutOrder = category.order,
			parent = tabRow,
			onClick = function()
				CosmeticsScreen.select(category.id)
			end,
		})
	end
	local scroll: ScrollingFrame = Create("ScrollingFrame", {
		Name = "Grid",
		Size = UDim2.new(1, 0, 1, -56),
		Position = UDim2.fromOffset(0, 56),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = Theme.Colors.TextMuted,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = modal.body,
	})
	Create("UIGridLayout", {
		CellSize = UDim2.fromOffset(200, 186),
		CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = scroll,
	})
	Style.padding(scroll, 4, 2)
	for _, def in Cosmetics.list do
		buildCard(scroll, def)
	end
	CosmeticsScreen.refresh()
	Store.changed:Connect(CosmeticsScreen.refresh)
	Locale.changed:Connect(CosmeticsScreen.refresh)
	return modal
end

-- Tests / debug.
function CosmeticsScreen.cards(): { Card }
	return cards
end

return CosmeticsScreen
