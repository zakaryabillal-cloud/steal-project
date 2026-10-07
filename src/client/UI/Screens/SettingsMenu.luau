--!strict
-- Settings modal: segmented controls for audio, effects quality, camera shake
-- and language.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Theme = require(Shared.Config.Theme)
local Locale = require(Shared.Locale)

local UIRoot = script.Parent.Parent
local Kit = UIRoot.Kit
local Create = require(Kit.Create)
local Style = require(Kit.Style)
local Tween = require(Kit.Tween)
local Modal = require(Kit.Modal)

local Controllers = UIRoot.Parent.Controllers
local Settings = require(Controllers.Settings)
local Store = require(Controllers.Store)
local Audio = require(Controllers.Audio)

local SettingsMenu = {}

type Option = { label: () -> string, value: any }
type Row = { key: string, title: string, options: { Option }, buttons: { TextButton }, labels: { TextLabel }, titleLabel: TextLabel }

local modal: Modal.Modal
local rows: { Row } = {}

local function current(key: string): any
	local settings = Store.state.settings :: any
	if key == "language" then
		return Locale.language
	end
	return settings[key]
end

local function refresh()
	modal.title.Text = Locale.t("settings.title")
	modal.subtitle.Text = ""
	for _, row in rows do
		row.titleLabel.Text = Locale.t(row.title)
		local value = current(row.key)
		for i, option in row.options do
			local selected = option.value == value
			row.labels[i].Text = option.label()
			Tween.play(row.buttons[i], 0.2, {
				BackgroundColor3 = if selected then Theme.Colors.Accent else Theme.Colors.PanelRaised,
				BackgroundTransparency = if selected then 0 else 0.3,
			})
		end
	end
end

local function addRow(parent: Instance, order: number, key: string, title: string, options: { Option })
	local frame = Create("Frame", { Size = UDim2.new(1, 0, 0, 72), BackgroundTransparency = 1, LayoutOrder = order, Parent = parent })
	local titleLabel = Style.text({ Size = UDim2.new(1, 0, 0, 22), FontFace = Theme.Fonts.Heavy, TextSize = 17, Parent = frame })
	local bar = Create("Frame", { Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 28), BackgroundTransparency = 1, Parent = frame })
	Style.list(bar, 8, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Left)
	local row: Row = { key = key, title = title, options = options, buttons = {}, labels = {}, titleLabel = titleLabel }
	local width = math.floor((480 - (#options - 1) * 8) / #options)
	for i, option in options do
		local button: TextButton = Create("TextButton", {
			Size = UDim2.fromOffset(width, 40),
			BackgroundColor3 = Theme.Colors.PanelRaised,
			AutoButtonColor = false,
			Text = "",
			LayoutOrder = i,
			Parent = bar,
		})
		Style.corner(button, Theme.Radius.Medium)
		local label = Style.text({ TextXAlignment = Enum.TextXAlignment.Center, FontFace = Theme.Fonts.BodyBold, TextSize = 15, Parent = button })
		button.Activated:Connect(function()
			Audio.play("UiClick")
			Settings.set(key, option.value)
			Tween.pop(button, 0.08)
			task.defer(refresh)
		end)
		table.insert(row.buttons, button)
		table.insert(row.labels, label)
	end
	table.insert(rows, row)
end

local function volumeOptions(): { Option }
	local list = {}
	for _, value in { 0, 0.25, 0.5, 0.75, 1 } do
		table.insert(list, {
			label = function()
				return if value == 0 then Locale.t("settings.off") else string.format("%d%%", value * 100)
			end,
			value = value,
		})
	end
	return list
end

function SettingsMenu.init(parent: Instance, close: () -> ()): Modal.Modal
	modal = Modal.new({ name = "Settings", size = UDim2.fromOffset(560, 520), parent = parent, onClose = close })
	local list = Create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = modal.body })
	Style.list(list, 6, Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Left)
	addRow(list, 1, "sfx", "settings.sfx", volumeOptions())
	addRow(list, 2, "music", "settings.music", volumeOptions())
	addRow(list, 3, "quality", "settings.quality", {
		{ label = function() return Locale.t("quality.Low") end, value = "Low" },
		{ label = function() return Locale.t("quality.Medium") end, value = "Medium" },
		{ label = function() return Locale.t("quality.High") end, value = "High" },
	})
	addRow(list, 4, "shake", "settings.shake", {
		{ label = function() return Locale.t("settings.on") end, value = true },
		{ label = function() return Locale.t("settings.off") end, value = false },
	})
	addRow(list, 5, "language", "settings.language", {
		{ label = function() return "English" end, value = "en" },
		{ label = function() return "Français" end, value = "fr" },
	})
	refresh()
	Store.changed:Connect(refresh)
	Locale.changed:Connect(refresh)
	return modal
end

return SettingsMenu
