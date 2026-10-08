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
local Emoji = require(Shared.Config.Emoji)

local Controllers = UIRoot.Parent.Controllers
local Settings = require(Controllers.Settings)
local Store = require(Controllers.Store)
local Audio = require(Controllers.Audio)

local SettingsMenu = {}

type Option = { label: () -> string, value: any }
type Row = { key: string, title: string, emoji: string, options: { Option }, buttons: { TextButton }, labels: { TextLabel }, strokes: { UIStroke }, titleLabel: TextLabel }

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
		row.titleLabel.Text = row.emoji .. " " .. Locale.t(row.title)
		local value = current(row.key)
		for i, option in row.options do
			local selected = option.value == value
			row.labels[i].Text = option.label()
			Tween.play(row.buttons[i], 0.2, {
				BackgroundColor3 = if selected then Theme.Buttons.green.face else Theme.Colors.PanelLight,
			})
			row.strokes[i].Thickness = if selected then Theme.Outline.Regular else Theme.Outline.Thin
		end
	end
end

local function addRow(parent: Instance, order: number, key: string, title: string, emoji: string, options: { Option })
	local frame = Create("Frame", { Size = UDim2.new(1, 0, 0, 76), BackgroundTransparency = 1, LayoutOrder = order, Parent = parent })
	local titleLabel = Style.text({ Size = UDim2.new(1, 0, 0, 24), FontFace = Theme.Fonts.Display, TextSize = 19, Parent = frame })
	Style.ink(titleLabel, 2)
	local bar = Create("Frame", { Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 29), BackgroundTransparency = 1, Parent = frame })
	Style.list(bar, 8, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Left)
	local row: Row = { key = key, title = title, emoji = emoji, options = options, buttons = {}, labels = {}, strokes = {}, titleLabel = titleLabel }
	local width = math.floor((500 - (#options - 1) * 8) / #options)
	for i, option in options do
		local button: TextButton = Create("TextButton", {
			Size = UDim2.fromOffset(width, 44),
			BackgroundColor3 = Theme.Colors.PanelLight,
			AutoButtonColor = false,
			Text = "",
			LayoutOrder = i,
			Parent = bar,
		})
		Style.corner(button, Theme.Radius.Medium)
		local stroke = Style.stroke(button, Theme.Colors.Ink, 0, Theme.Outline.Thin)
		Style.shade(button, 0.15)
		table.insert(row.strokes, stroke)
		local label = Style.text({ TextXAlignment = Enum.TextXAlignment.Center, FontFace = Theme.Fonts.Display, TextSize = 16, Parent = button })
		Style.ink(label, 1.5)
		button.Activated:Connect(function()
			Audio.play("UiClick")
			Settings.set(key, option.value)
			Tween.pop(button, 0.12)
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
	modal = Modal.new({ name = "Settings", size = UDim2.fromOffset(580, 540), parent = parent, onClose = close, accent = Theme.Buttons.purple.face, emoji = Emoji.get("settings") })
	local list = Create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = modal.body })
	Style.list(list, 6, Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Left)
	addRow(list, 1, "sfx", "settings.sfx", Emoji.get("sound"), volumeOptions())
	addRow(list, 2, "music", "settings.music", Emoji.get("music"), volumeOptions())
	addRow(list, 3, "quality", "settings.quality", Emoji.get("ready"), {
		{ label = function() return Locale.t("quality.Low") end, value = "Low" },
		{ label = function() return Locale.t("quality.Medium") end, value = "Medium" },
		{ label = function() return Locale.t("quality.High") end, value = "High" },
	})
	addRow(list, 4, "shake", "settings.shake", Emoji.get("camera"), {
		{ label = function() return Locale.t("settings.on") end, value = true },
		{ label = function() return Locale.t("settings.off") end, value = false },
	})
	addRow(list, 5, "language", "settings.language", Emoji.get("globe"), {
		{ label = function() return "English" end, value = "en" },
		{ label = function() return "Français" end, value = "fr" },
	})
	refresh()
	Store.changed:Connect(refresh)
	Locale.changed:Connect(refresh)
	return modal
end

return SettingsMenu
