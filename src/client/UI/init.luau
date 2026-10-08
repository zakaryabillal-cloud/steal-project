--!strict
-- UI root: three ScreenGui layers (HUD, modals, overlays), resolution-aware
-- scaling, and a simple modal manager (one modal at a time, ESC / B closes).

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Create = require(script.Kit.Create)
local Tween = require(script.Kit.Tween)
local Signal = require(game:GetService("ReplicatedStorage").Shared.Util.Signal)

local UI = {}

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui

UI.touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
UI.scale = 1
UI.scaleChanged = Signal.new()

export type Modal = {
	open: () -> (),
	close: () -> (),
}

local modals: { [string]: Modal } = {}
local current: string? = nil

local function layer(name: string, order: number, ignoreInset: boolean): (ScreenGui, Frame)
	local gui: ScreenGui = Create("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = ignoreInset,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = order,
		ScreenInsets = if ignoreInset then Enum.ScreenInsets.None else Enum.ScreenInsets.CoreUISafeInsets,
		Parent = playerGui,
	})
	local container: Frame = Create("Frame", {
		Name = "Scaled",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	return gui, container
end

local hudGui, hud = layer("RiftHUD", 5, false)
local modalGui, modal = layer("RiftModals", 10, false)
local overlayGui, overlay = layer("RiftOverlay", 20, true)

UI.hudGui = hudGui
UI.modalGui = modalGui
UI.overlayGui = overlayGui
UI.hud = hud
UI.modal = modal
UI.overlay = overlay

-- Unscaled full-screen layer for effects that must cover the screen exactly.
UI.fullscreen = Create("Frame", {
	Name = "Fullscreen",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Parent = overlayGui,
})

local scales: { UIScale } = {}
for _, container in { hud, modal, overlay } do
	table.insert(scales, Create("UIScale", { Parent = container }))
end

local function computeScale(): number
	local camera = workspace.CurrentCamera
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	if UI.touch then
		return math.clamp(math.min(size.Y / 560, size.X / 900), 0.62, 1.1)
	end
	return math.clamp(math.min(size.Y / 900, size.X / 1440), 0.72, 1.3)
end

local function applyScale()
	local scale = computeScale()
	UI.scale = scale
	for i, uiScale in scales do
		uiScale.Scale = scale
		local container = ({ hud, modal, overlay })[i]
		container.Size = UDim2.fromScale(1 / scale, 1 / scale)
	end
	UI.scaleChanged:Fire(scale)
end

-- Dimmed backdrop shared by modals.
local backdrop: TextButton = Create("TextButton", {
	Name = "Backdrop",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(16, 20, 64),
	BackgroundTransparency = 1,
	Text = "",
	AutoButtonColor = false,
	Visible = false,
	ZIndex = 0,
	Parent = modalGui,
})

function UI.registerModal(name: string, modalApi: Modal)
	modals[name] = modalApi
end

function UI.isOpen(name: string?): boolean
	if name then
		return current == name
	end
	return current ~= nil
end

function UI.close()
	local name = current
	if not name then
		return
	end
	current = nil
	modals[name].close()
	Tween.play(backdrop, 0.2, { BackgroundTransparency = 1 })
	task.delay(0.2, function()
		if current == nil then
			backdrop.Visible = false
		end
	end)
	GuiService.SelectedObject = nil
end

function UI.open(name: string)
	if current == name then
		UI.close()
		return
	end
	if current then
		modals[current].close()
	end
	current = name
	backdrop.Visible = true
	Tween.play(backdrop, 0.25, { BackgroundTransparency = 0.5 })
	modals[name].open()
end

function UI.toggle(name: string)
	if current == name then
		UI.close()
	else
		UI.open(name)
	end
end

function UI.init()
	applyScale()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyScale)
	end
	backdrop.Activated:Connect(UI.close)
	UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			if current and not processed then
				UI.close()
			end
		end
	end)
end

return UI
