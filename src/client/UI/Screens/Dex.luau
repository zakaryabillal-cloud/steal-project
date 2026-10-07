--!strict
-- RiftDex modal: collection grid (silhouettes for unknown relics, rarity
-- frames, mutation pips) and a detail pane with a spinning model and lore.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Theme = require(Shared.Config.Theme)
local Relics = require(Shared.Config.Relics)
local Rarities = require(Shared.Config.Rarities)
local Mutations = require(Shared.Config.Mutations)
local Economy = require(Shared.Economy)
local Locale = require(Shared.Locale)
local Format = require(Shared.Util.Format)

local UIRoot = script.Parent.Parent
local Kit = UIRoot.Kit
local Create = require(Kit.Create)
local Style = require(Kit.Style)
local Tween = require(Kit.Tween)
local Modal = require(Kit.Modal)
local RelicViewport = require(Kit.RelicViewport)

local Store = require(UIRoot.Parent.Controllers.Store)
local Audio = require(UIRoot.Parent.Controllers.Audio)

local Dex = {}

type Cell = {
	def: Relics.RelicDef,
	button: TextButton,
	viewport: RelicViewport.Viewport,
	name: TextLabel,
	stroke: UIStroke,
	pips: { Frame },
	known: boolean?,
}

local modal: Modal.Modal
local grid: ScrollingFrame
local cells: { Cell } = {}
local built = false
local progressBar: Frame
local selected: Relics.RelicDef? = nil

-- Detail pane
local detailViewport: RelicViewport.Viewport
local detailName: TextLabel
local detailRarity: TextLabel
local detailLore: TextLabel
local detailStats: TextLabel
local detailMutations: TextLabel

local function isKnown(relicId: string): boolean
	return Store.state.dex[relicId] ~= nil
end

local function refreshHeader()
	local found, mutations = Store.dexCounts()
	local bonus = Economy.dexMultiplier(found, mutations) - 1
	modal.title.Text = Locale.t("dex.title")
	modal.subtitle.Text = Locale.t("dex.progress", { found = found, total = Relics.count }) .. "   ·   " .. Style.colored(Locale.t("dex.bonus", { pct = Format.percent(bonus) }), Theme.Colors.Essence)
	Tween.play(progressBar, 0.5, { Size = UDim2.fromScale(found / Relics.count, 1) })
end

local function refreshDetail()
	local def = selected
	if not def then
		return
	end
	local rarity = Rarities.get(def.rarity)
	local known = isKnown(def.id)
	local entry = Store.state.dex[def.id]
	detailViewport:set(def.id, nil, not known)
	detailName.Text = if known then Locale.relicName(def.id) else Locale.t("dex.unknown")
	detailName.TextColor3 = if known then rarity.color else Theme.Colors.TextDim
	detailRarity.Text = string.upper(Locale.rarity(rarity.id))
	detailRarity.TextColor3 = rarity.color
	detailLore.Text = if known then Locale.relicLore(def.id) else Locale.t("dex.hint")
	local lines = { Locale.t("dex.baseRate", { rate = Format.abbrev(Economy.relicBaseRate(def.id, 1, nil)) }) }
	if entry then
		table.insert(lines, Locale.t("dex.found", { count = entry.count }))
	end
	if def.eventOnly then
		table.insert(lines, Style.colored(Locale.t("dex.eventOnly", { event = Locale.t("event." .. def.eventOnly .. ".name") }), Theme.Colors.Warning))
	end
	detailStats.Text = table.concat(lines, "\n")
	local mutationLines = { "<b>" .. Locale.t("dex.mutations") .. "</b>" }
	for _, mutation in Mutations.list do
		local found = entry ~= nil and entry.mutations[mutation.id] == true
		local label = if found then Style.colored("◆ " .. Locale.mutation(mutation.id), mutation.color) .. Style.colored("  ×" .. mutation.multiplier, Theme.Colors.TextDim) else Style.colored("◇ ???", Theme.Colors.TextMuted)
		table.insert(mutationLines, label)
	end
	detailMutations.Text = table.concat(mutationLines, "\n")
end

local function refreshCells()
	for _, cell in cells do
		local known = isKnown(cell.def.id)
		local rarity = Rarities.get(cell.def.rarity)
		if cell.known ~= known then
			cell.known = known
			cell.viewport:set(cell.def.id, nil, not known)
		end
		cell.name.Text = if known then Locale.relicName(cell.def.id) else Locale.t("dex.unknown")
		cell.name.TextColor3 = if known then Theme.Colors.Text else Theme.Colors.TextMuted
		cell.stroke.Color = rarity.color
		cell.stroke.Transparency = if known then 0.15 else 0.65
		local entry = Store.state.dex[cell.def.id]
		for i, mutation in Mutations.list do
			local found = entry ~= nil and entry.mutations[mutation.id] == true
			cell.pips[i].BackgroundColor3 = if found then mutation.color else Theme.Colors.PanelRaised
		end
	end
end

local function select(def: Relics.RelicDef)
	selected = def
	refreshDetail()
	for _, cell in cells do
		Tween.play(cell.button, 0.2, { BackgroundTransparency = if cell.def == def then 0 else 0.25 })
	end
end

local function build()
	if built then
		return
	end
	built = true
	for index, def in Relics.list do
		local rarity = Rarities.get(def.rarity)
		local button: TextButton = Create("TextButton", {
			Name = def.id,
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Theme.Colors.PanelLight,
			BackgroundTransparency = 0.25,
			LayoutOrder = index,
			Parent = grid,
		})
		Style.corner(button, Theme.Radius.Medium)
		local stroke = Style.stroke(button, rarity.color, 0.4, 2)
		local viewport = RelicViewport.new({ size = UDim2.new(1, -12, 0, 96), position = UDim2.fromOffset(6, 6), spin = false, parent = button })
		local name = Style.text({
			Size = UDim2.new(1, -12, 0, 18),
			Position = UDim2.fromOffset(6, 104),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextSize = 13,
			FontFace = Theme.Fonts.Heavy,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = button,
		})
		Style.text({
			Size = UDim2.new(1, -12, 0, 14),
			Position = UDim2.fromOffset(6, 122),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextSize = 11,
			FontFace = Theme.Fonts.BodyBold,
			TextColor3 = rarity.color,
			Text = string.upper(Locale.rarity(rarity.id)),
			Parent = button,
		}):SetAttribute("Rarity", rarity.id)
		local pipRow = Create("Frame", { Size = UDim2.new(1, 0, 0, 8), Position = UDim2.fromOffset(0, 144), BackgroundTransparency = 1, Parent = button })
		Style.list(pipRow, 4, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center)
		local pips = {}
		for i = 1, #Mutations.list do
			local pip = Create("Frame", { Size = UDim2.fromOffset(8, 8), Rotation = 45, BackgroundColor3 = Theme.Colors.PanelRaised, LayoutOrder = i, Parent = pipRow })
			table.insert(pips, pip)
		end
		local cell: Cell = { def = def, button = button, viewport = viewport, name = name, stroke = stroke, pips = pips, known = nil }
		table.insert(cells, cell)
		button.MouseEnter:Connect(function()
			Tween.play(stroke, 0.15, { Thickness = 3 })
		end)
		button.MouseLeave:Connect(function()
			Tween.play(stroke, 0.15, { Thickness = 2 })
		end)
		button.Activated:Connect(function()
			Audio.play("UiClick")
			select(def)
		end)
	end
	refreshCells()
end

local function refreshLocale()
	for _, cell in cells do
		for _, child in cell.button:GetChildren() do
			if child:IsA("TextLabel") and child:GetAttribute("Rarity") then
				child.Text = string.upper(Locale.rarity(child:GetAttribute("Rarity") :: string))
			end
		end
	end
end

function Dex.init(parent: Instance, close: () -> ()): Modal.Modal
	modal = Modal.new({ name = "Dex", size = UDim2.fromOffset(900, 690), parent = parent, onClose = close, accent = Theme.Colors.Gold })
	local track = Create("Frame", {
		Size = UDim2.new(1, -60, 0, 6),
		Position = UDim2.fromOffset(2, 66),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.88,
		Parent = modal.header,
	})
	Style.corner(track, UDim.new(1, 0))
	progressBar = Create("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), Parent = track })
	Style.corner(progressBar, UDim.new(1, 0))
	Style.gradient(progressBar, Theme.Colors.Gold, Theme.Colors.Essence)

	grid = Create("ScrollingFrame", {
		Size = UDim2.new(1, -290, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.Colors.TextMuted,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = modal.body,
	})
	Create("UIGridLayout", {
		CellSize = UDim2.fromOffset(128, 160),
		CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	Style.padding(grid, 4, 4)

	local detail = Create("Frame", {
		Size = UDim2.new(0, 270, 1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Theme.Colors.PanelLight,
		BackgroundTransparency = 0.3,
		Parent = modal.body,
	})
	Style.corner(detail, Theme.Radius.Large)
	Style.stroke(detail)
	detailViewport = RelicViewport.new({ size = UDim2.new(1, -20, 0, 210), position = UDim2.fromOffset(10, 8), parent = detail })
	detailName = Style.text({ Size = UDim2.new(1, -24, 0, 30), Position = UDim2.fromOffset(12, 220), FontFace = Theme.Fonts.Display, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Center, TextScaled = false, Parent = detail })
	detailRarity = Style.text({ Size = UDim2.new(1, -24, 0, 18), Position = UDim2.fromOffset(12, 250), FontFace = Theme.Fonts.Heavy, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center, Parent = detail })
	detailLore = Style.text({ Size = UDim2.new(1, -28, 0, 54), Position = UDim2.fromOffset(14, 272), FontFace = Theme.Fonts.Body, TextSize = 14, TextColor3 = Theme.Colors.TextDim, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top, Parent = detail })
	detailStats = Style.text({ Size = UDim2.new(1, -28, 0, 60), Position = UDim2.fromOffset(14, 330), FontFace = Theme.Fonts.BodyBold, TextSize = 14, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Parent = detail })
	detailMutations = Style.text({ Size = UDim2.new(1, -28, 0, 130), Position = UDim2.fromOffset(14, 392), FontFace = Theme.Fonts.BodyBold, TextSize = 14, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, LineHeight = 1.15, Parent = detail })

	Store.changed:Connect(function(state, previous)
		if built and state.dex ~= previous.dex then
			refreshCells()
			refreshHeader()
			refreshDetail()
		end
	end)
	Locale.changed:Connect(function()
		if built then
			refreshCells()
			refreshLocale()
			refreshHeader()
			refreshDetail()
		end
	end)

	local baseOpen = modal.open
	modal.open = function()
		build()
		refreshCells()
		refreshHeader()
		if not selected then
			select(Relics.list[1])
		else
			refreshDetail()
		end
		baseOpen()
	end
	return modal
end

-- Opens the Dex focused on a relic (used by the discovery card).
function Dex.focus(relicId: string)
	local def = Relics.get(relicId)
	if def then
		selected = def
	end
end

return Dex
