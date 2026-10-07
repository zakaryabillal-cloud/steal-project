--!strict
-- Inspect panel for your own displayed relic: model, level stars, live
-- Essence/s, fusion hint, and a hold-to-confirm Dissolve button.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Theme = require(Shared.Config.Theme)
local Rarities = require(Shared.Config.Rarities)
local Mutations = require(Shared.Config.Mutations)
local GameConfig = require(Shared.Config.GameConfig)
local Economy = require(Shared.Economy)
local Net = require(Shared.Net)
local Locale = require(Shared.Locale)
local Format = require(Shared.Util.Format)

local UIRoot = script.Parent.Parent
local Kit = UIRoot.Kit
local Create = require(Kit.Create)
local Style = require(Kit.Style)
local Tween = require(Kit.Tween)
local Modal = require(Kit.Modal)
local RelicViewport = require(Kit.RelicViewport)

local Controllers = UIRoot.Parent.Controllers
local Store = require(Controllers.Store)
local Audio = require(Controllers.Audio)
local ClientNet = require(UIRoot.Parent.ClientNet)

local Inspect = {}

local modal: Modal.Modal
local viewport: RelicViewport.Viewport
local nameLabel: TextLabel
local infoLabel: TextLabel
local starsLabel: TextLabel
local rateLabel: TextLabel
local hintLabel: TextLabel
local holdButton: TextButton
local holdFill: Frame
local holdLabel: TextLabel
local currentAnchor: BasePart? = nil
local closeModal: () -> () = function() end
local holdToken = 0

local HOLD_TIME = 1.1

local function attr(anchor: Instance, name: string): any
	return anchor:GetAttribute(name)
end

local function refresh()
	local anchor = currentAnchor
	if not anchor then
		return
	end
	local relicId = attr(anchor, "RelicId") :: string
	local mutationId = attr(anchor, "Mutation") :: string
	local mutation = if mutationId ~= "" then mutationId else nil
	local level = (attr(anchor, "Level") :: number?) or 1
	local rarity = Rarities.get(attr(anchor, "Rarity") :: string)
	local mutationDef = Mutations.get(mutation)
	local titleColor = if mutationDef then mutationDef.color:Lerp(rarity.color, 0.3) else rarity.color
	nameLabel.Text = Style.colored(Locale.relicTitle(relicId, mutation), titleColor)
	local info = string.upper(Locale.rarity(rarity.id))
	if mutationDef then
		info ..= "  ·  " .. Locale.mutation(mutationDef.id) .. " ×" .. mutationDef.multiplier
	end
	infoLabel.Text = info
	infoLabel.TextColor3 = rarity.color
	starsLabel.Text = Format.stars(level, GameConfig.Economy.MaxRelicLevel) .. "   " .. Locale.t("inspect.level", { level = level })
	local rate = Economy.relicBaseRate(relicId, level, mutation) * Store.state.multiplier
	rateLabel.Text = Locale.t("inspect.rate", { rate = Format.abbrev(rate) })
	hintLabel.Text = if level >= GameConfig.Economy.MaxRelicLevel then Locale.t("inspect.maxLevel") else Locale.t("inspect.fuseHint")
	local value = Economy.dissolveValue(relicId, level, mutation, Store.state.multiplier)
	holdLabel.Text = Locale.t("inspect.dissolve", { value = Format.abbrev(value) })
end

function Inspect.show(anchor: BasePart)
	currentAnchor = anchor
	local relicId = attr(anchor, "RelicId") :: string
	local mutationId = attr(anchor, "Mutation") :: string
	viewport:set(relicId, if mutationId ~= "" then mutationId else nil, false)
	refresh()
end

local function startHold()
	holdToken += 1
	local token = holdToken
	holdFill.Size = UDim2.fromScale(0, 1)
	Tween.play(holdFill, HOLD_TIME, { Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Linear)
	Audio.play("UiClick", { pitch = 0.8 })
	task.delay(HOLD_TIME, function()
		if token ~= holdToken or not currentAnchor then
			return
		end
		holdToken += 1
		local uid = currentAnchor:GetAttribute("Uid")
		if type(uid) ~= "string" then
			return
		end
		task.spawn(function()
			local ok = ClientNet.invoke(Net.Functions.Dissolve, uid)
			if ok then
				currentAnchor = nil
				closeModal()
			else
				Audio.play("UiError")
			end
		end)
	end)
end

local function cancelHold()
	holdToken += 1
	Tween.play(holdFill, 0.2, { Size = UDim2.fromScale(0, 1) })
end

function Inspect.init(parent: Instance, close: () -> ()): Modal.Modal
	closeModal = close
	modal = Modal.new({ name = "Inspect", size = UDim2.fromOffset(560, 330), parent = parent, onClose = close })
	modal.header.Size = UDim2.new(1, -40, 0, 44)
	modal.body.Position = UDim2.fromOffset(20, 20)
	modal.body.Size = UDim2.new(1, -40, 1, -40)
	viewport = RelicViewport.new({ size = UDim2.fromOffset(200, 200), position = UDim2.fromOffset(0, 10), parent = modal.body })
	local x = 214
	nameLabel = Style.text({ Size = UDim2.new(1, -x - 50, 0, 32), Position = UDim2.fromOffset(x, 4), FontFace = Theme.Fonts.Display, TextSize = 26, TextWrapped = true, Parent = modal.body })
	infoLabel = Style.text({ Size = UDim2.new(1, -x, 0, 18), Position = UDim2.fromOffset(x, 40), FontFace = Theme.Fonts.Heavy, TextSize = 14, Parent = modal.body })
	starsLabel = Style.text({ Size = UDim2.new(1, -x, 0, 22), Position = UDim2.fromOffset(x, 66), FontFace = Theme.Fonts.Heavy, TextSize = 18, TextColor3 = Theme.Colors.Gold, Parent = modal.body })
	rateLabel = Style.text({ Size = UDim2.new(1, -x, 0, 24), Position = UDim2.fromOffset(x, 96), FontFace = Theme.Fonts.Display, TextSize = 22, TextColor3 = Theme.Colors.Essence, Parent = modal.body })
	hintLabel = Style.text({ Size = UDim2.new(1, -x, 0, 36), Position = UDim2.fromOffset(x, 126), FontFace = Theme.Fonts.Body, TextSize = 14, TextColor3 = Theme.Colors.TextDim, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Parent = modal.body })

	holdButton = Create("TextButton", {
		Name = "Dissolve",
		Size = UDim2.new(1, -x, 0, 50),
		Position = UDim2.new(0, x, 1, -60),
		BackgroundColor3 = Theme.Colors.PanelRaised,
		AutoButtonColor = false,
		Text = "",
		ClipsDescendants = true,
		Parent = modal.body,
	})
	Style.corner(holdButton, Theme.Radius.Medium)
	Style.stroke(holdButton, Theme.Colors.Danger, 0.4, 1.5)
	holdFill = Create("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Theme.Colors.Danger, BackgroundTransparency = 0.35, Parent = holdButton })
	holdLabel = Style.text({ TextXAlignment = Enum.TextXAlignment.Center, FontFace = Theme.Fonts.Heavy, TextSize = 16, Parent = holdButton })
	holdButton.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch or input.KeyCode == Enum.KeyCode.ButtonA then
			startHold()
		end
	end)
	holdButton.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch or input.KeyCode == Enum.KeyCode.ButtonA then
			cancelHold()
		end
	end)
	Store.changed:Connect(function()
		if modal.panel.Visible then
			refresh()
		end
	end)
	return modal
end

return Inspect
