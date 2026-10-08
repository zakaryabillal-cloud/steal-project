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
local Button = require(Kit.Button)
local Modal = require(Kit.Modal)
local Juice = require(Kit.Juice)
local Emoji = require(Shared.Config.Emoji)

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
	statusPill: Frame,
	hint: TextLabel,
	action: Button.Button,
	try: Button.Button,
	busy: boolean,
}

local modal: Modal.Modal
local cards: { Card } = {}
local tabs: { [string]: Button.Button } = {}
local current = "trail"

-- One emoji per category tab / card badge (Config/Emoji).
local CATEGORY_EMOJI: { [string]: string } = {
	trail = Emoji.get("rainbow"),
	aura = Emoji.get("ready"),
	carry = Emoji.get("carry"),
	sanctuary = Emoji.get("home"),
	arrival = Emoji.get("boom"),
	secure = Emoji.get("party"),
	title = Emoji.get("crown"),
}
function CosmeticsScreen.categoryEmoji(categoryId: string): string
	return CATEGORY_EMOJI[categoryId] or ""
end

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
			Tween.pop(card.frame, 0.06)
			if id ~= "" then
				Juice.stars(card.action.instance, 6, Rarities.get(card.def.rarity).color)
			end
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
	card.rarity.Text = Style.stars(def.rarity)
	card.stroke.Color = if equipped then Theme.Colors.Gold else Theme.Colors.Ink
	card.stroke.Thickness = if equipped then Theme.Outline.Thick else Theme.Outline.Thin
	-- The status label keeps the plain word; its emoji sits in front of it.
	local statusEmoji = card.statusPill:FindFirstChild("Emoji") :: TextLabel
	if equipped then
		card.status.Text = Locale.t("cos.equipped")
		statusEmoji.Text = Emoji.get("equipped")
		card.statusPill.BackgroundColor3 = Theme.Buttons.green.face
	elseif owned then
		card.status.Text = Locale.t("cos.owned")
		statusEmoji.Text = Emoji.get("star")
		card.statusPill.BackgroundColor3 = Theme.Buttons.blue.face
	else
		card.status.Text = Emoji.get("locked") .. " " .. Locale.t("cos.locked")
		statusEmoji.Text = ""
		card.statusPill.BackgroundColor3 = Theme.Buttons.gray.face
	end
	card.hint.Text = if owned then "" else CosmeticsScreen.hintText(def)
	card.action:setKind(if equipped then "red" else "green")
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
	modal.emoji.Text = Emoji.get("style")
	modal.subtitle.Text = Locale.t("cos.subtitle", { owned = owned, total = total })
	for id, tab in tabs do
		tab:setText(CosmeticsScreen.categoryEmoji(id) .. " " .. Locale.t("cos.cat." .. id))
		tab:setKind(if id == current then "pink" else "neutral")
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
	local frame: Frame = Style.card({
		Name = def.id,
		LayoutOrder = def.order,
		CornerRadius = Theme.Radius.Large,
		Parent = parent,
	})
	local stroke = frame:FindFirstChildOfClass("UIStroke") :: UIStroke
	-- Swatch: the cosmetic's colours, a big category emoji and its rarity stars.
	local a, b = colorsOf(def)
	local swatch = Create("Frame", {
		Name = "Swatch",
		Size = UDim2.new(1, -16, 0, 52),
		Position = UDim2.fromOffset(8, 8),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = frame,
	})
	Style.corner(swatch, Theme.Radius.Medium)
	Style.stroke(swatch, Theme.Colors.Ink, 0, Theme.Outline.Thin)
	Style.gradient(swatch, a, b, 0)
	Style.gloss(swatch)
	local bubble = Create("Frame", {
		Size = UDim2.fromOffset(40, 40),
		Position = UDim2.new(0, 6, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Theme.Colors.Cream,
		Parent = swatch,
	})
	Style.corner(bubble, Theme.Radius.Pill)
	Style.stroke(bubble, Theme.Colors.Ink, 0, Theme.Outline.Thin)
	local emoji = Style.text({ Name = "Emoji", Text = CosmeticsScreen.categoryEmoji(def.category), TextSize = 24, FontFace = Theme.Fonts.Display, TextXAlignment = Enum.TextXAlignment.Center, Parent = bubble })
	emoji:SetAttribute("Emoji", true)
	local rarityColor = Rarities.get(def.rarity).color
	local rarityPill, rarity = Style.pill({ name = "Rarity", text = "", color = rarityColor, size = UDim2.fromOffset(100, 22), position = UDim2.new(1, -6, 0.5, 0), anchor = Vector2.new(1, 0.5), textSize = 13, parent = swatch })
	local _ = rarityPill
	local name = Style.text({ Size = UDim2.new(1, -16, 0, 22), Position = UDim2.fromOffset(8, 64), FontFace = Theme.Fonts.Display, TextSize = 16, TextTruncate = Enum.TextTruncate.AtEnd, Parent = frame })
	Style.ink(name, 1.5)
	local statusPill = Create("Frame", {
		Name = "Status",
		Size = UDim2.fromOffset(60, 20),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.fromOffset(8, 88),
		BackgroundColor3 = Theme.Buttons.gray.face,
		Parent = frame,
	})
	Style.corner(statusPill, Theme.Radius.Pill)
	Style.stroke(statusPill, Theme.Colors.Ink, 0, 1.5)
	Style.padding(statusPill, 0, 7)
	Style.list(statusPill, 3, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	Style.text({ Name = "Emoji", Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, TextSize = 12, FontFace = Theme.Fonts.Display, LayoutOrder = 1, Parent = statusPill })
	local status = Style.text({ Name = "Label", Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, FontFace = Theme.Fonts.Heavy, TextSize = 12, LayoutOrder = 2, Parent = statusPill })
	Style.ink(status, 1.5)
	local hint = Style.text({ Size = UDim2.new(1, -16, 0, 28), Position = UDim2.fromOffset(8, 112), FontFace = Theme.Fonts.Body, TextSize = 12, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = Theme.Colors.TextDim, Parent = frame })
	local card: Card
	local action = Button.new({
		name = "Action",
		size = UDim2.new(0.6, -10, 0, 48),
		position = UDim2.new(0, 8, 1, -8),
		anchor = Vector2.new(0, 1),
		kind = "green",
		corner = Theme.Radius.Medium,
		text = "",
		textSize = 16,
		parent = frame,
		onClick = function()
			local equipped = Store.state.cosmetics.equipped[def.category] == def.id
			request(card, def.category, if equipped then "" else def.id)
		end,
	})
	local try = Button.new({
		name = "Try",
		size = UDim2.new(0.4, -6, 0, 48),
		position = UDim2.new(1, -8, 1, -8),
		anchor = Vector2.new(1, 1),
		kind = "pink",
		corner = Theme.Radius.Medium,
		text = "",
		textSize = 15,
		parent = frame,
		onClick = function()
			if CosmeticRenderer.preview(def.id) then
				Audio.play("UiClick")
			end
		end,
	})
	card = { def = def, frame = frame, stroke = stroke, name = name, rarity = rarity, status = status, statusPill = statusPill, hint = hint, action = action, try = try, busy = false }
	table.insert(cards, card)
end

function CosmeticsScreen.init(parent: Instance, close: () -> ()): Modal.Modal
	modal = Modal.new({ name = "Cosmetics", size = UDim2.fromOffset(700, 660), parent = parent, onClose = close, accent = Theme.Buttons.pink.face, emoji = Emoji.get("style") })
	-- Category tabs (scroll sideways on narrow screens).
	local tabRow: ScrollingFrame = Create("ScrollingFrame", {
		Name = "Tabs",
		Size = UDim2.new(1, 0, 0, 56),
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
			size = UDim2.fromOffset(118, 50),
			kind = "neutral",
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
		Size = UDim2.new(1, 0, 1, -64),
		Position = UDim2.fromOffset(0, 64),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Theme.Colors.Cream,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = modal.body,
	})
	Create("UIGridLayout", {
		CellSize = UDim2.fromOffset(204, 200),
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
