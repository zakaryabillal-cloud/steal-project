--!strict
-- Upgrades modal: one card per upgrade with level pips, the concrete effect of
-- the next level, and a buy button that reacts to affordability.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Theme = require(Shared.Config.Theme)
local Upgrades = require(Shared.Config.Upgrades)
local Economy = require(Shared.Economy)
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
local Juice = require(Kit.Juice)
local Emoji = require(Shared.Config.Emoji)

local Controllers = UIRoot.Parent.Controllers
local Store = require(Controllers.Store)
local Audio = require(Controllers.Audio)
local ClientNet = require(UIRoot.Parent.ClientNet)

local Shop = {}

type Card = {
	id: string,
	frame: Frame,
	name: TextLabel,
	desc: TextLabel,
	effect: TextLabel,
	pips: { Frame },
	buy: Button.Button,
	costLabel: TextLabel,
	costIcon: Frame,
	flash: Frame,
	busy: boolean,
}

local modal: Modal.Modal
local cards: { [string]: Card } = {}
local balance: TextLabel

-- Candy tile per upgrade (Theme.Buttons families).
local ICON_COLORS: { [string]: { Color3 } } = {
	pedestal = { Theme.Buttons.blue.face, Theme.Buttons.blue.lip },
	tier = { Theme.Buttons.yellow.face, Theme.Buttons.orange.face },
	resonance = { Theme.Buttons.mint.face, Theme.Buttons.blue.face },
	stride = { Theme.Buttons.purple.face, Theme.Buttons.pink.face },
	harness = { Theme.Buttons.green.face, Theme.Buttons.green.lip },
}

local function pedestalIcon(parent: Instance, color: Color3)
	local function bar(size: UDim2, position: UDim2)
		local frame = Create("Frame", { Size = size, Position = position, AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = color, BorderSizePixel = 0, Parent = parent })
		Style.corner(frame, UDim.new(0.3, 0))
	end
	bar(UDim2.fromScale(0.7, 0.14), UDim2.fromScale(0.5, 0.82))
	bar(UDim2.fromScale(0.36, 0.42), UDim2.fromScale(0.5, 0.56))
	bar(UDim2.fromScale(0.62, 0.12), UDim2.fromScale(0.5, 0.32))
	local gem = Create("Frame", { Size = UDim2.fromScale(0.24, 0.24), Position = UDim2.fromScale(0.5, 0.14), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = 45, BackgroundColor3 = color, BorderSizePixel = 0, Parent = parent })
	Create("UIAspectRatioConstraint", { Parent = gem })
end

local function iconFor(id: string, parent: Instance)
	local color = Color3.new(1, 1, 1)
	if id == "pedestal" then
		pedestalIcon(parent, color)
	elseif id == "tier" then
		Icons.upgrades(parent, color)
	elseif id == "resonance" then
		Icons.pulse(parent, color)
	elseif id == "stride" then
		Icons.dash(parent, color)
	else
		Icons.dex(parent, color)
	end
end

local function effectText(id: string, upgrades: Economy.UpgradeLevels): string
	local nextLevels = table.clone(upgrades);
	(nextLevels :: any)[id] += 1
	if id == "pedestal" then
		return Locale.t("shop.effect.pedestals", { from = Economy.unlockedPedestals(upgrades), to = Economy.unlockedPedestals(nextLevels) })
	elseif id == "tier" then
		return Locale.t("shop.effect.tier", { from = Locale.t("tier." .. Economy.tier(upgrades)), to = Locale.t("tier." .. Economy.tier(nextLevels)) })
	elseif id == "resonance" then
		return Locale.t("shop.effect.essenceMultiplier", {
			from = string.format("%.2f", Economy.resonanceMultiplier(upgrades.resonance)),
			to = string.format("%.2f", Economy.resonanceMultiplier(nextLevels.resonance)),
		})
	elseif id == "stride" then
		return Locale.t("shop.effect.walkSpeed", { from = string.format("%.1f", Economy.walkSpeed(upgrades.stride)), to = string.format("%.1f", Economy.walkSpeed(nextLevels.stride)) })
	end
	return Locale.t("shop.effect.carryCapacity", { from = Economy.carryCapacity(upgrades.harness), to = Economy.carryCapacity(nextLevels.harness) })
end

local function sparkle(card: Card)
	local frame = card.frame
	for i = 1, 10 do
		local spark = Create("Frame", {
			Size = UDim2.fromOffset(8, 8),
			Position = UDim2.new(1, -80, 0.5, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = 45,
			BackgroundColor3 = if i % 2 == 0 then Theme.Colors.Essence else Theme.Colors.Gold,
			ZIndex = 10,
			Parent = frame,
		})
		local angle = (i / 10) * math.pi * 2
		Tween.play(spark, 0.6, {
			Position = UDim2.new(1, -80 + math.cos(angle) * 90, 0.5, math.sin(angle) * 50),
			BackgroundTransparency = 1,
			Rotation = 225,
		}, Enum.EasingStyle.Quint)
		task.delay(0.65, function()
			spark:Destroy()
		end)
	end
end

local function refreshCard(card: Card)
	local state = Store.state
	local upgrades = state.upgrades
	local def = Upgrades.get(card.id)
	if not def then
		return
	end
	local level = (upgrades :: any)[card.id] :: number
	card.name.Text = Locale.t("upgrade." .. card.id .. ".name")
	card.desc.Text = Locale.t("upgrade." .. card.id .. ".desc")
	for i, pip in card.pips do
		local filled = i <= level
		pip.BackgroundColor3 = if filled then Theme.Colors.Gold else Theme.Colors.Panel
		pip.BackgroundTransparency = 0
	end
	local blocker = Economy.upgradeBlocker(card.id, upgrades)
	local cost = Economy.upgradeCost(card.id, level)
	if blocker == "max" or cost == nil then
		card.effect.Text = ""
		card.costLabel.Text = Emoji.label("trophy", Locale.t("shop.max"))
		card.costLabel.TextColor3 = Theme.Colors.Gold
		card.costIcon.Visible = false
		card.buy:setEnabled(false)
		return
	end
	card.effect.Text = effectText(card.id, upgrades)
	card.costIcon.Visible = blocker == nil
	if blocker == "needTier" then
		card.costLabel.Text = Locale.t("shop.needTier")
		card.costLabel.TextColor3 = Theme.Colors.Text
		card.buy:setEnabled(false)
		return
	end
	local affordable = state.essence >= cost
	card.costLabel.Text = Format.abbrev(cost)
	card.costLabel.TextColor3 = if affordable then Theme.Colors.Text else Theme.Colors.Warning
	card.buy:setEnabled(affordable and not card.busy)
end

local function refreshAll()
	balance.Text = Format.commas(Store.state.essence)
	for _, card in cards do
		refreshCard(card)
	end
	modal.title.Text = Locale.t("shop.title")
	modal.emoji.Text = Emoji.get("upgrades")
	modal.subtitle.Text = Locale.t("shop.subtitle")
end

local function purchase(card: Card)
	if card.busy then
		return
	end
	card.busy = true
	card.costLabel.Text = "…"
	task.spawn(function()
		local ok = ClientNet.invoke(Net.Functions.Purchase, card.id)
		card.busy = false
		if ok then
			Audio.play("Purchase")
			card.flash.BackgroundTransparency = 0.4
			Tween.play(card.flash, 0.5, { BackgroundTransparency = 1 })
			Tween.pop(card.frame, 0.04)
			sparkle(card)
			Juice.burstFrom(card.buy.instance, 18)
			Juice.floatFrom(card.buy.instance, Locale.t("fx.levelUp"), Theme.Colors.Gold, 28)
		else
			Audio.play("UiError")
			local frame = card.frame
			local origin = frame.Position
			Tween.play(frame, 0.05, { Position = origin + UDim2.fromOffset(6, 0) })
			task.delay(0.05, function()
				Tween.play(frame, 0.3, { Position = origin }, Enum.EasingStyle.Elastic)
			end)
		end
		refreshCard(card)
	end)
end

local function buildCard(parent: Instance, def: Upgrades.UpgradeDef)
	local frame: Frame = Style.card({
		Name = def.id,
		Size = UDim2.new(1, -8, 0, 110),
		LayoutOrder = def.order,
		CornerRadius = Theme.Radius.Large,
		Parent = parent,
	})
	local colors = ICON_COLORS[def.id] or { Theme.Colors.Essence, Theme.Colors.EssenceDeep }
	local tile = Create("Frame", {
		Size = UDim2.fromOffset(76, 76),
		Position = UDim2.new(0, 14, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Rotation = -4,
		Parent = frame,
	})
	Style.corner(tile, Theme.Radius.Large)
	Style.stroke(tile, Theme.Colors.Ink, 0, Theme.Outline.Regular)
	Style.gradient(tile, colors[1], colors[2], 60)
	Style.gloss(tile)
	local iconHolder = Create("Frame", {
		Size = UDim2.fromScale(0.56, 0.56),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = tile,
	})
	iconFor(def.id, iconHolder)

	local name = Style.text({ Size = UDim2.new(1, -280, 0, 26), Position = UDim2.fromOffset(104, 10), FontFace = Theme.Fonts.Display, TextSize = 22, Parent = frame })
	Style.ink(name, 2)
	local pipRow = Create("Frame", { Size = UDim2.new(0, 170, 0, 12), Position = UDim2.fromOffset(105, 40), BackgroundTransparency = 1, Parent = frame })
	Style.list(pipRow, 4, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Left)
	local pips = {}
	local pipWidth = math.clamp(math.floor(160 / def.maxLevel) - 4, 10, 28)
	for i = 1, def.maxLevel do
		local pip = Create("Frame", { Size = UDim2.fromOffset(pipWidth, 12), BackgroundColor3 = Theme.Colors.Panel, LayoutOrder = i, Parent = pipRow })
		Style.corner(pip, UDim.new(1, 0))
		Style.stroke(pip, Theme.Colors.Ink, 0, 1.5)
		table.insert(pips, pip)
	end
	local desc = Style.text({ Size = UDim2.new(1, -280, 0, 18), Position = UDim2.fromOffset(104, 58), FontFace = Theme.Fonts.Body, TextSize = 14, TextColor3 = Theme.Colors.TextDim, TextTruncate = Enum.TextTruncate.AtEnd, Parent = frame })
	local effect = Style.text({ Size = UDim2.new(1, -280, 0, 20), Position = UDim2.fromOffset(104, 80), FontFace = Theme.Fonts.Heavy, TextSize = 15, TextColor3 = Theme.Colors.Gold, Parent = frame })
	Style.ink(effect, 1.5)

	local card: Card
	local buy = Button.new({
		name = "Buy",
		size = UDim2.fromOffset(150, 60),
		position = UDim2.new(1, -14, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		kind = "green",
		corner = Theme.Radius.Large,
		parent = frame,
		onClick = function()
			purchase(card)
		end,
	})
	local costIcon = Create("Frame", { Size = UDim2.fromOffset(24, 24), Position = UDim2.new(0, 14, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundTransparency = 1, ZIndex = 3, Parent = buy.content })
	Icons.essence(costIcon)
	local costLabel = Style.text({ Size = UDim2.new(1, -48, 1, 0), Position = UDim2.fromOffset(42, 0), FontFace = Theme.Fonts.Display, TextSize = 22, TextScaled = true, ZIndex = 3, Parent = buy.content })
	Create("UITextSizeConstraint", { MaxTextSize = 22, MinTextSize = 11, Parent = costLabel })
	Style.ink(costLabel, 2)
	local flash = Create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, ZIndex = 9, Parent = frame })
	Style.corner(flash, Theme.Radius.Large)
	card = { id = def.id, frame = frame, name = name, desc = desc, effect = effect, pips = pips, buy = buy, costLabel = costLabel, costIcon = costIcon, flash = flash, busy = false }
	cards[def.id] = card
end

function Shop.init(parent: Instance, close: () -> ()): Modal.Modal
	modal = Modal.new({ name = "Shop", size = UDim2.fromOffset(660, 700), parent = parent, onClose = close, accent = Theme.Buttons.green.face, emoji = Emoji.get("upgrades") })
	-- Balance pill on the subtitle row.
	modal.subtitle.Size = UDim2.new(1, -230, 0, 22)
	local pill = Create("Frame", {
		Name = "Balance",
		Size = UDim2.fromOffset(180, 40),
		Position = UDim2.new(1, -4, 0, 48),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Theme.Colors.PanelLight,
		ZIndex = 6,
		Parent = modal.header,
	})
	Style.corner(pill, UDim.new(1, 0))
	Style.stroke(pill, Theme.Colors.Ink, 0, Theme.Outline.Thin)
	local icon = Create("Frame", { Size = UDim2.fromOffset(28, 28), Position = UDim2.new(0, 8, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundTransparency = 1, ZIndex = 7, Parent = pill })
	Icons.essence(icon)
	balance = Style.text({ Size = UDim2.new(1, -48, 1, 0), Position = UDim2.fromOffset(42, 0), FontFace = Theme.Fonts.Display, TextSize = 22, ZIndex = 7, Parent = pill })
	Style.ink(balance, 2)

	local scroll: ScrollingFrame = Create("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Theme.Colors.Cream,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = modal.body,
	})
	Style.list(scroll, 10)
	Style.padding(scroll, 4, 2)
	for _, def in Upgrades.list do
		buildCard(scroll, def)
	end
	refreshAll()
	Store.changed:Connect(refreshAll)
	Locale.changed:Connect(refreshAll)
	return modal
end

return Shop
