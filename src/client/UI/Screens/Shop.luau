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

local ICON_COLORS: { [string]: { Color3 } } = {
	pedestal = { Color3.fromRGB(120, 220, 255), Color3.fromRGB(90, 120, 255) },
	tier = { Color3.fromRGB(255, 205, 100), Color3.fromRGB(255, 120, 90) },
	resonance = { Color3.fromRGB(150, 245, 255), Color3.fromRGB(170, 110, 255) },
	stride = { Color3.fromRGB(190, 160, 255), Color3.fromRGB(110, 90, 255) },
	harness = { Color3.fromRGB(120, 240, 160), Color3.fromRGB(60, 170, 140) },
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
		pip.BackgroundColor3 = if filled then Theme.Colors.Essence else Theme.Colors.PanelRaised
		pip.BackgroundTransparency = if filled then 0 else 0.2
	end
	local blocker = Economy.upgradeBlocker(card.id, upgrades)
	local cost = Economy.upgradeCost(card.id, level)
	if blocker == "max" or cost == nil then
		card.effect.Text = ""
		card.costLabel.Text = Locale.t("shop.max")
		card.costLabel.TextColor3 = Theme.Colors.Gold
		card.costIcon.Visible = false
		card.buy:setEnabled(false)
		return
	end
	card.effect.Text = effectText(card.id, upgrades)
	card.costIcon.Visible = blocker == nil
	if blocker == "needTier" then
		card.costLabel.Text = Locale.t("shop.needTier")
		card.costLabel.TextColor3 = Theme.Colors.TextDim
		card.buy:setEnabled(false)
		return
	end
	local affordable = state.essence >= cost
	card.costLabel.Text = Format.abbrev(cost)
	card.costLabel.TextColor3 = if affordable then Theme.Colors.Text else Theme.Colors.Danger
	card.buy:setEnabled(affordable and not card.busy)
end

local function refreshAll()
	balance.Text = Format.commas(Store.state.essence)
	for _, card in cards do
		refreshCard(card)
	end
	modal.title.Text = Locale.t("shop.title")
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
	local frame: Frame = Create("Frame", {
		Name = def.id,
		Size = UDim2.new(1, -8, 0, 104),
		BackgroundColor3 = Theme.Colors.PanelLight,
		BackgroundTransparency = 0.2,
		LayoutOrder = def.order,
		Parent = parent,
	})
	Style.corner(frame, Theme.Radius.Large)
	Style.stroke(frame)
	local colors = ICON_COLORS[def.id] or { Theme.Colors.Essence, Theme.Colors.EssenceDeep }
	local tile = Create("Frame", {
		Size = UDim2.fromOffset(72, 72),
		Position = UDim2.new(0, 16, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = frame,
	})
	Style.corner(tile, Theme.Radius.Medium)
	Style.gradient(tile, colors[1], colors[2], 45)
	local iconHolder = Create("Frame", {
		Size = UDim2.fromScale(0.56, 0.56),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = tile,
	})
	iconFor(def.id, iconHolder)

	local name = Style.text({ Size = UDim2.new(1, -270, 0, 24), Position = UDim2.fromOffset(104, 12), FontFace = Theme.Fonts.Heavy, TextSize = 20, Parent = frame })
	local pipRow = Create("Frame", { Size = UDim2.new(0, 160, 0, 8), Position = UDim2.fromOffset(105, 40), BackgroundTransparency = 1, Parent = frame })
	Style.list(pipRow, 4, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Left)
	local pips = {}
	local pipWidth = math.clamp(math.floor(150 / def.maxLevel) - 4, 8, 26)
	for i = 1, def.maxLevel do
		local pip = Create("Frame", { Size = UDim2.fromOffset(pipWidth, 8), BackgroundColor3 = Theme.Colors.PanelRaised, LayoutOrder = i, Parent = pipRow })
		Style.corner(pip, UDim.new(1, 0))
		table.insert(pips, pip)
	end
	local desc = Style.text({ Size = UDim2.new(1, -270, 0, 18), Position = UDim2.fromOffset(104, 54), FontFace = Theme.Fonts.Body, TextSize = 14, TextColor3 = Theme.Colors.TextDim, TextTruncate = Enum.TextTruncate.AtEnd, Parent = frame })
	local effect = Style.text({ Size = UDim2.new(1, -270, 0, 18), Position = UDim2.fromOffset(104, 76), FontFace = Theme.Fonts.BodyBold, TextSize = 14, TextColor3 = Theme.Colors.Essence, Parent = frame })

	local card: Card
	local buy = Button.new({
		name = "Buy",
		size = UDim2.fromOffset(140, 52),
		position = UDim2.new(1, -16, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		color = Color3.new(1, 1, 1),
		gradient = { Color3.fromRGB(110, 225, 255), Color3.fromRGB(150, 105, 255) },
		corner = Theme.Radius.Medium,
		parent = frame,
		onClick = function()
			purchase(card)
		end,
	})
	local costIcon = Create("Frame", { Size = UDim2.fromOffset(20, 20), Position = UDim2.new(0, 16, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundTransparency = 1, Parent = buy.instance })
	Icons.essence(costIcon, Color3.new(1, 1, 1), Color3.fromRGB(220, 240, 255))
	local costLabel = Style.text({ Size = UDim2.new(1, -46, 1, 0), Position = UDim2.fromOffset(40, 0), FontFace = Theme.Fonts.Display, TextSize = 20, Parent = buy.instance })
	Style.textStroke(costLabel, 0.5, 1.5)
	local flash = Create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, ZIndex = 9, Parent = frame })
	Style.corner(flash, Theme.Radius.Large)
	card = { id = def.id, frame = frame, name = name, desc = desc, effect = effect, pips = pips, buy = buy, costLabel = costLabel, costIcon = costIcon, flash = flash, busy = false }
	cards[def.id] = card
end

function Shop.init(parent: Instance, close: () -> ()): Modal.Modal
	modal = Modal.new({ name = "Shop", size = UDim2.fromOffset(640, 690), parent = parent, onClose = close })
	-- Balance pill in the header.
	local pill = Create("Frame", {
		Size = UDim2.fromOffset(170, 40),
		Position = UDim2.new(1, -54, 0, 2),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Theme.Colors.PanelRaised,
		Parent = modal.header,
	})
	Style.corner(pill, UDim.new(1, 0))
	local icon = Create("Frame", { Size = UDim2.fromOffset(24, 24), Position = UDim2.new(0, 10, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundTransparency = 1, Parent = pill })
	Icons.essence(icon)
	balance = Style.text({ Size = UDim2.new(1, -46, 1, 0), Position = UDim2.fromOffset(40, 0), FontFace = Theme.Fonts.Display, TextSize = 20, Parent = pill })

	local scroll: ScrollingFrame = Create("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.Colors.TextMuted,
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
