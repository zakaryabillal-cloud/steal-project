--!strict
-- Boss weapons screen (V2 phase 6.5): shop + inventory, Cartoon & Goofy.
--
--   * 6 cards (3D preview, name, rarity stars, owned / equipped / locked);
--   * the selected weapon in big, its damage / speed / reach bars compared
--     to the equipped one (green up, red down), its special, its price
--     (Essence + boss materials, what you have in colour) and its unlock
--     condition (boss victories);
--   * BUY / EQUIP buttons. The server validates everything; this screen
--     only shows and asks.
-- Weapons only work against bosses (no effect in PvP): said on the screen.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Weapons = require(Shared.Config.Weapons)
local Materials = require(Shared.Config.Materials)
local Theme = require(Shared.Config.Theme)
local Emoji = require(Shared.Config.Emoji)
local Locale = require(Shared.Locale)
local Format = require(Shared.Util.Format)
local WeaponModels = require(Shared.Weapons.WeaponModels)

local Kit = script.Parent.Parent.Kit
local Create = require(Kit.Create)
local Style = require(Kit.Style)
local Tween = require(Kit.Tween)
local Button = require(Kit.Button)
local Modal = require(Kit.Modal)
local Juice = require(Kit.Juice)

local Controllers = script.Parent.Parent.Parent.Controllers
local Store = require(Controllers.Store)
local Audio = require(Controllers.Audio)
local ClientNet = require(script.Parent.Parent.Parent.ClientNet)

local WeaponsScreen = {}

local ORANGE = Theme.Buttons.orange.face
local RARITY_COLORS: { [string]: Color3 } = {
	Common = Color3.fromRGB(200, 210, 230),
	Rare = Color3.fromRGB(90, 190, 255),
	Epic = Color3.fromRGB(190, 120, 255),
	Legendary = Color3.fromRGB(255, 200, 60),
}
local STARS: { [string]: number } = { Common = 1, Rare = 2, Epic = 3, Legendary = 4 }

type Card = {
	def: Weapons.WeaponDef,
	button: Button.Button,
	status: TextLabel,
}

type Bar = { fill: Frame, value: TextLabel, delta: TextLabel }

local modal: Modal.Modal
local cards: { Card } = {}
local selected: Weapons.WeaponDef = Weapons.get(Weapons.Starter) :: Weapons.WeaponDef
local detailViewport: ViewportFrame
local detailModel: Model? = nil
local detailName: TextLabel
local detailRarity: TextLabel
local detailSpecial: TextLabel
local detailPrice: TextLabel
local detailUnlock: TextLabel
local detailReason: TextLabel
local bars: { [string]: Bar } = {}
local buyButton: Button.Button
local equipButton: Button.Button
local busy = false
local isOpen = false

-- Pure display helpers -----------------------------------------------------------

local function wins(): number
	return Weapons.totalWins(Store.state.bosses)
end

local function owned(def: Weapons.WeaponDef): boolean
	return def.starter == true or (Store.state.weapons and Store.state.weapons.owned[def.id] == true)
end

local function equippedDef(): Weapons.WeaponDef
	local inventory = Store.state.weapons
	local def = Weapons.get(inventory and inventory.equipped)
	return if def and owned(def) then def else Weapons.get(Weapons.Starter) :: Weapons.WeaponDef
end

-- Why it cannot be bought now (nil = buyable). Same rule as the server.
function WeaponsScreen.blocker(def: Weapons.WeaponDef): string?
	local state = Store.state
	return Weapons.blocker(def, (state.weapons and state.weapons.owned) or {}, state.essence, state.materials or {}, wins())
end

local function stars(def: Weapons.WeaponDef): string
	return string.rep("★", STARS[def.rarity] or 1)
end

-- Price line, e.g. "💰 400K  ·  💎 6/10 Void Shards" (missing parts in red).
function WeaponsScreen.priceText(def: Weapons.WeaponDef): string
	if def.starter then
		return Style.colored(Locale.t("weapons.free"), Theme.Colors.Success)
	end
	local state = Store.state
	local parts = {}
	local essenceColor = if state.essence >= def.price.essence then Theme.Colors.Success else Color3.fromRGB(255, 150, 160)
	table.insert(parts, Emoji.get("money") .. " " .. Style.colored(Format.abbrev(def.price.essence), essenceColor))
	local ids = {}
	for materialId in def.price.materials do
		table.insert(ids, materialId)
	end
	table.sort(ids)
	for _, materialId in ids do
		local need = def.price.materials[materialId]
		local have = (state.materials or {})[materialId] or 0
		local material = Materials.get(materialId)
		local color = if have >= need then Theme.Colors.Success else Color3.fromRGB(255, 150, 160)
		table.insert(parts, string.format("%s %s %s", Emoji.get(if material then material.emoji else "gem"), Style.colored(string.format("%d/%d", have, need), color), Locale.t("mat." .. materialId)))
	end
	return table.concat(parts, "   ")
end

-- Stat bar value (0..1) and its comparison with the equipped weapon.
local function statValue(def: Weapons.WeaponDef, stat: string): number
	if stat == "damage" then
		return def.damage
	elseif stat == "speed" then
		return 1 / def.cooldown
	elseif stat == "reach" then
		return def.reach
	end
	return Weapons.dps(def)
end

local function statMax(stat: string): number
	local best = 0
	for _, def in Weapons.list do
		best = math.max(best, statValue(def, stat))
	end
	return best
end

-- "+25 %" / "-10 %" against the equipped weapon ("" when equal).
function WeaponsScreen.compare(def: Weapons.WeaponDef, stat: string): string
	local base = statValue(equippedDef(), stat)
	local value = statValue(def, stat)
	if base <= 0 or math.abs(value - base) < 1e-6 then
		return ""
	end
	local pct = math.floor((value / base - 1) * 100 + 0.5)
	if pct > 0 then
		return Style.colored("▲ +" .. pct .. "%", Theme.Colors.Success)
	end
	return Style.colored("▼ " .. pct .. "%", Color3.fromRGB(255, 150, 160))
end

-- Build ---------------------------------------------------------------------------

local function preview(viewport: ViewportFrame, def: Weapons.WeaponDef): Model
	local built = WeaponModels.build(def)
	WeaponModels.place(built, CFrame.new(if def.visual.kind == "gloves" then 1.25 else 0, 1.8, 0) * CFrame.Angles(0, 0, math.rad(-35)))
	built.model.Parent = viewport
	return built.model
end

local function newViewport(parent: Instance, size: UDim2, position: UDim2, zIndex: number?): ViewportFrame
	local viewport: ViewportFrame = Create("ViewportFrame", {
		Name = "Preview",
		Size = size,
		Position = position,
		BackgroundColor3 = Color3.fromRGB(255, 236, 200),
		Ambient = Color3.fromRGB(210, 200, 230),
		LightColor = Color3.new(1, 1, 1),
		ZIndex = zIndex or 3,
		Parent = parent,
	})
	Style.corner(viewport, Theme.Radius.Medium)
	Style.stroke(viewport, Theme.Colors.Ink, 0, 2)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 45
	camera.CFrame = CFrame.lookAt(Vector3.new(3, 1, -7.5), Vector3.new(0, 0.2, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	return viewport
end

local function buildCard(parent: Instance, def: Weapons.WeaponDef): Card
	local button = Button.new({
		name = "Weapon_" .. def.id,
		size = UDim2.fromOffset(136, 150),
		color = Theme.Colors.PanelLight,
		corner = Theme.Radius.Medium,
		layoutOrder = def.order,
		parent = parent,
		hoverScale = 1.04,
		onClick = function()
			WeaponsScreen.select(def.id)
		end,
	})
	local viewport = newViewport(button.content, UDim2.new(1, -16, 0, 82), UDim2.fromOffset(8, 8), 4)
	preview(viewport, def)
	local name = Style.text({ Name = "Name", Size = UDim2.new(1, -8, 0, 20), Position = UDim2.fromOffset(4, 92), Text = Locale.t("weapon." .. def.id .. ".name"), TextSize = 14, TextScaled = true, FontFace = Theme.Fonts.Display, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5, Parent = button.content })
	Create("UITextSizeConstraint", { MaxTextSize = 15, MinTextSize = 9, Parent = name })
	Style.ink(name, 1.5)
	local status = Style.text({ Name = "Status", Size = UDim2.new(1, -8, 0, 20), Position = UDim2.fromOffset(4, 114), TextSize = 13, FontFace = Theme.Fonts.Heavy, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5, Parent = button.content })
	Style.ink(status, 1.5)
	return { def = def, button = button, status = status }
end

local function buildBar(parent: Instance, stat: string, order: number)
	local row: Frame = Create("Frame", { Name = "Stat_" .. stat, Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, LayoutOrder = order, Parent = parent })
	local label = Style.text({ Name = "Label", Size = UDim2.new(0, 80, 1, 0), Text = Locale.t("weapons." .. stat), TextSize = 14, FontFace = Theme.Fonts.Heavy, Parent = row })
	label:SetAttribute("Key", "weapons." .. stat)
	local track: Frame = Create("Frame", { Name = "Track", Size = UDim2.new(1, -190, 0, 14), Position = UDim2.new(0, 82, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = Theme.Colors.Ink, Parent = row })
	Style.corner(track, UDim.new(1, 0))
	local fill: Frame = Create("Frame", { Name = "Fill", Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = Theme.Colors.Gold, Parent = track })
	Style.corner(fill, UDim.new(1, 0))
	local value = Style.text({ Name = "Value", Size = UDim2.new(0, 46, 1, 0), Position = UDim2.new(1, -104, 0, 0), TextSize = 14, FontFace = Theme.Fonts.Display, TextXAlignment = Enum.TextXAlignment.Right, Parent = row })
	Style.ink(value, 1.5)
	local delta = Style.text({ Name = "Delta", Size = UDim2.new(0, 56, 1, 0), Position = UDim2.new(1, -54, 0, 0), TextSize = 13, FontFace = Theme.Fonts.Heavy, TextXAlignment = Enum.TextXAlignment.Right, Parent = row })
	Style.ink(delta, 1.5)
	bars[stat] = { fill = fill, value = value, delta = delta }
end

local function statText(def: Weapons.WeaponDef, stat: string): string
	if stat == "damage" then
		return tostring(def.damage)
	elseif stat == "speed" then
		return string.format("%.1f/s", 1 / def.cooldown)
	elseif stat == "reach" then
		return tostring(def.reach)
	end
	return tostring(math.floor(Weapons.dps(def) + 0.5))
end

-- Refresh ---------------------------------------------------------------------------

function WeaponsScreen.refresh()
	if not modal then
		return
	end
	local equipped = equippedDef()
	modal.subtitle.Text = Locale.t("weapons.subtitle")
	for _, card in cards do
		local def = card.def
		local text: string
		if def.id == equipped.id then
			text = Style.colored(Emoji.get("equipped") .. " " .. Locale.t("weapons.equipped"), Theme.Colors.Success)
		elseif owned(def) then
			text = Locale.t("weapons.owned")
		elseif wins() < def.wins then
			text = Emoji.get("locked") .. " " .. Locale.t("weapons.winsShort", { wins = def.wins })
		else
			text = Emoji.get("money") .. " " .. Format.abbrev(def.price.essence)
		end
		card.status.Text = text
		card.button:setColor(if def.id == selected.id then RARITY_COLORS[def.rarity]:Lerp(Theme.Colors.PanelLight, 0.45) else Theme.Colors.PanelLight)
	end
	-- Detail of the selected weapon.
	local def = selected
	detailName.Text = Locale.t("weapon." .. def.id .. ".name")
	detailRarity.Text = Style.colored(stars(def), Theme.Colors.Gold) .. "  " .. Style.colored(Locale.t("weapons.style." .. def.style), RARITY_COLORS[def.rarity])
	for stat, bar in bars do
		bar.fill.Size = UDim2.fromScale(math.clamp(statValue(def, stat) / statMax(stat), 0.05, 1), 1)
		bar.value.Text = statText(def, stat)
		bar.delta.Text = WeaponsScreen.compare(def, stat)
	end
	detailSpecial.Text = Emoji.get("ready") .. " " .. Locale.t("weapon." .. def.id .. ".special")
	detailPrice.Text = WeaponsScreen.priceText(def)
	local needed = def.wins
	detailUnlock.Text = if needed > 0
		then Emoji.get("trophy") .. " " .. Style.colored(Locale.t("weapons.wins", { wins = math.min(wins(), needed), need = needed }), if wins() >= needed then Theme.Colors.Success else Color3.fromRGB(255, 150, 160))
		else ""
	local blocker = WeaponsScreen.blocker(def)
	local isOwned = owned(def)
	buyButton.instance.Visible = not isOwned
	equipButton.instance.Visible = isOwned
	buyButton:setEnabled(blocker == nil and not busy)
	equipButton:setEnabled(isOwned and def.id ~= equipped.id and not busy)
	equipButton:setText(if def.id == equipped.id then Locale.t("weapons.equipped") else Locale.t("weapons.equip"))
	detailReason.Text = if blocker and blocker ~= "owned" then Locale.t("weapons.reason." .. blocker) else ""
	for _, label in modal.body:GetDescendants() do
		local key = label:GetAttribute("Key")
		if type(key) == "string" and label:IsA("TextLabel") then
			label.Text = Locale.t(key)
		end
	end
end

local function setDetailModel(def: Weapons.WeaponDef)
	if detailModel then
		detailModel:Destroy()
	end
	detailModel = preview(detailViewport, def)
end

function WeaponsScreen.select(weaponId: string)
	local def = Weapons.get(weaponId)
	if not def then
		return
	end
	selected = def
	setDetailModel(def)
	Audio.play("UiClick")
	WeaponsScreen.refresh()
end

local function request(name: string, weaponId: string): (boolean, string?)
	if busy then
		return false, "busy"
	end
	busy = true
	WeaponsScreen.refresh()
	local ok, reason = ClientNet.invoke(name, weaponId)
	busy = false
	return ok, reason
end

function WeaponsScreen.buy(): (boolean, string?)
	local def = selected
	local ok, reason = request(Net.Functions.BuyWeapon, def.id)
	if ok then
		Audio.play("WeaponBuy")
		Juice.burstFrom(buyButton.instance, 40)
		Tween.pop(detailViewport, 0.2)
	else
		Audio.play("UiError")
		Tween.wiggle(buyButton.instance, 6)
		detailReason.Text = Locale.t("weapons.reason." .. tostring(reason))
	end
	WeaponsScreen.refresh()
	return ok, reason
end

function WeaponsScreen.equip(): (boolean, string?)
	local ok, reason = request(Net.Functions.EquipWeapon, selected.id)
	if ok then
		Audio.play("Purchase")
		Tween.pop(equipButton.instance, 0.15)
	else
		Audio.play("UiError")
		detailReason.Text = Locale.t("weapons.reason." .. tostring(reason))
	end
	WeaponsScreen.refresh()
	return ok, reason
end

-- Tests / debug.
function WeaponsScreen.debugState(): { selected: string, buyVisible: boolean, buyEnabled: boolean, equipVisible: boolean, equipEnabled: boolean, price: string, cards: number }
	return {
		selected = selected.id,
		buyVisible = buyButton.instance.Visible,
		buyEnabled = buyButton.enabled,
		equipVisible = equipButton.instance.Visible,
		equipEnabled = equipButton.enabled,
		price = detailPrice.Text,
		cards = #cards,
	}
end

function WeaponsScreen.init(parent: Instance, close: () -> ()): Modal.Modal
	modal = Modal.new({ name = "Weapons", size = UDim2.fromOffset(780, 600), parent = parent, onClose = close, accent = ORANGE, emoji = Emoji.get("weapons") })
	modal.title.Text = Locale.t("weapons.title")
	-- Cards (left).
	local grid: Frame = Create("Frame", { Name = "Grid", Size = UDim2.new(0, 436, 1, -36), BackgroundTransparency = 1, Parent = modal.body })
	Create("UIGridLayout", { CellSize = UDim2.fromOffset(136, 150), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	for _, def in Weapons.list do
		table.insert(cards, buildCard(grid, def))
	end
	local note = Style.text({ Name = "Note", Size = UDim2.new(0, 436, 0, 30), Position = UDim2.new(0, 0, 1, 0), AnchorPoint = Vector2.new(0, 1), TextSize = 14, TextWrapped = true, FontFace = Theme.Fonts.Body, TextColor3 = Theme.Colors.TextDim, Parent = modal.body })
	note:SetAttribute("Key", "weapons.bossOnly")
	-- Detail (right).
	local detail = Style.card({ Name = "Detail", Size = UDim2.new(1, -450, 1, 0), Position = UDim2.fromOffset(450, 0), Parent = modal.body })
	detailViewport = newViewport(detail, UDim2.new(1, -20, 0, 130), UDim2.fromOffset(10, 10))
	detailName = Style.display({ Name = "Name", Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(10, 144), TextSize = 24, Parent = detail })
	detailRarity = Style.text({ Name = "Rarity", Size = UDim2.new(1, -20, 0, 20), Position = UDim2.fromOffset(10, 174), TextSize = 15, FontFace = Theme.Fonts.Heavy, Parent = detail })
	Style.ink(detailRarity, 1.5)
	local stats: Frame = Create("Frame", { Name = "Stats", Size = UDim2.new(1, -20, 0, 112), Position = UDim2.fromOffset(10, 198), BackgroundTransparency = 1, Parent = detail })
	Style.list(stats, 4)
	for order, stat in { "damage", "speed", "reach", "dps" } do
		buildBar(stats, stat, order)
	end
	detailSpecial = Style.text({ Name = "Special", Size = UDim2.new(1, -20, 0, 40), Position = UDim2.fromOffset(10, 312), TextSize = 14, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, FontFace = Theme.Fonts.Heavy, TextColor3 = Theme.Colors.Gold, Parent = detail })
	Style.ink(detailSpecial, 1.5)
	detailPrice = Style.text({ Name = "Price", Size = UDim2.new(1, -20, 0, 40), Position = UDim2.fromOffset(10, 354), TextSize = 15, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, FontFace = Theme.Fonts.Heavy, Parent = detail })
	Style.ink(detailPrice, 1.5)
	detailUnlock = Style.text({ Name = "Unlock", Size = UDim2.new(1, -20, 0, 20), Position = UDim2.fromOffset(10, 396), TextSize = 14, FontFace = Theme.Fonts.Heavy, Parent = detail })
	Style.ink(detailUnlock, 1.5)
	detailReason = Style.text({ Name = "Reason", Size = UDim2.new(1, -20, 0, 18), Position = UDim2.fromOffset(10, 418), TextSize = 13, FontFace = Theme.Fonts.Body, TextColor3 = Color3.fromRGB(255, 200, 210), Parent = detail })
	buyButton = Button.new({
		name = "Buy",
		size = UDim2.new(1, -20, 0, 52),
		position = UDim2.new(0, 10, 1, -10),
		anchor = Vector2.new(0, 1),
		kind = "green",
		corner = Theme.Radius.Large,
		text = Locale.t("weapons.buy"),
		textSize = 22,
		font = Theme.Fonts.Display,
		parent = detail,
		onClick = function()
			WeaponsScreen.buy()
		end,
	})
	equipButton = Button.new({
		name = "Equip",
		size = UDim2.new(1, -20, 0, 52),
		position = UDim2.new(0, 10, 1, -10),
		anchor = Vector2.new(0, 1),
		kind = "blue",
		corner = Theme.Radius.Large,
		text = Locale.t("weapons.equip"),
		textSize = 22,
		font = Theme.Fonts.Display,
		parent = detail,
		onClick = function()
			WeaponsScreen.equip()
		end,
	})
	setDetailModel(selected)
	local baseOpen, baseClose = modal.open, modal.close
	modal.open = function()
		isOpen = true
		selected = equippedDef()
		setDetailModel(selected)
		WeaponsScreen.refresh()
		baseOpen()
	end
	modal.close = function()
		isOpen = false
		baseClose()
	end
	-- The big preview turns slowly while the screen is open.
	RunService.Heartbeat:Connect(function()
		if isOpen and detailModel then
			local camera = detailViewport.CurrentCamera
			if camera then
				local a = os.clock() * 0.8
				camera.CFrame = CFrame.lookAt(Vector3.new(math.sin(a) * 8, 1, -math.cos(a) * 8), Vector3.new(0, 0.2, 0))
			end
		end
	end)
	Store.changed:Connect(WeaponsScreen.refresh)
	Locale.changed:Connect(function()
		modal.title.Text = Locale.t("weapons.title")
		buyButton:setText(Locale.t("weapons.buy"))
		for _, card in cards do
			local name = card.button.content:FindFirstChild("Name")
			if name and name:IsA("TextLabel") then
				name.Text = Locale.t("weapon." .. card.def.id .. ".name")
			end
		end
		WeaponsScreen.refresh()
	end)
	WeaponsScreen.refresh()
	return modal
end

return WeaponsScreen
