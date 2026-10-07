--!strict
-- Premium reveal card for new RiftDex entries: silhouette -> flash -> full
-- colour model, sunburst, confetti, progress. Queued, auto-dismissed, and
-- skippable with a click/tap.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Theme = require(Shared.Config.Theme)
local Relics = require(Shared.Config.Relics)
local Rarities = require(Shared.Config.Rarities)
local Mutations = require(Shared.Config.Mutations)
local Locale = require(Shared.Locale)

local UIRoot = script.Parent.Parent
local Kit = UIRoot.Kit
local Create = require(Kit.Create)
local Style = require(Kit.Style)
local Tween = require(Kit.Tween)
local RelicViewport = require(Kit.RelicViewport)

local Audio = require(UIRoot.Parent.Controllers.Audio)

local Discovery = {}

export type Entry = {
	relicId: string,
	mutation: string?,
	isNew: boolean,
	isNewMutation: boolean,
	found: number,
	total: number,
}

local backdrop: TextButton
local card: Frame
local cardScale: UIScale
local caption: TextLabel
local nameLabel: TextLabel
local rarityLabel: TextLabel
local progressLabel: TextLabel
local loreLabel: TextLabel
local burst: Frame
local flash: Frame
local viewport: RelicViewport.Viewport
local queue: { Entry } = {}
local showing = false
local dismissToken = 0

local function confetti(color: Color3)
	for i = 1, 22 do
		local piece = Create("Frame", {
			Size = UDim2.fromOffset(math.random(6, 12), math.random(6, 12)),
			Position = UDim2.fromScale(0.5, 0.36),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = math.random(0, 90),
			BackgroundColor3 = if i % 3 == 0 then Color3.new(1, 1, 1) elseif i % 3 == 1 then color else Theme.Colors.Gold,
			ZIndex = 20,
			Parent = card,
		})
		local angle = math.random() * math.pi * 2
		local distance = math.random(160, 300)
		Tween.play(piece, 1.1, {
			Position = UDim2.new(0.5, math.cos(angle) * distance, 0.36, math.sin(angle) * distance * 0.7 + 80),
			Rotation = piece.Rotation + math.random(-360, 360),
			BackgroundTransparency = 1,
		}, Enum.EasingStyle.Quint)
		task.delay(1.15, function()
			piece:Destroy()
		end)
	end
end

local function hide()
	dismissToken += 1
	Tween.play(cardScale, 0.2, { Scale = 0.85 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	Tween.play(backdrop, 0.25, { BackgroundTransparency = 1 })
	task.delay(0.22, function()
		card.Visible = false
		backdrop.Visible = false
		showing = false
		local nextEntry = table.remove(queue, 1)
		if nextEntry then
			Discovery.show(nextEntry)
		end
	end)
end

function Discovery.show(entry: Entry)
	if showing then
		table.insert(queue, entry)
		return
	end
	showing = true
	dismissToken += 1
	local token = dismissToken
	local def = Relics.get(entry.relicId)
	if not def then
		showing = false
		return
	end
	local rarity = Rarities.get(def.rarity)
	local mutation = Mutations.get(entry.mutation)
	local color = if mutation and not entry.isNew then mutation.color else rarity.color

	caption.Text = if entry.isNew then Locale.t("dex.newDiscovery") else Locale.t("dex.newMutation")
	nameLabel.Text = Locale.relicTitle(entry.relicId, entry.mutation)
	nameLabel.TextColor3 = color
	rarityLabel.Text = string.upper(Locale.rarity(rarity.id)) .. (if mutation then "  ·  " .. string.upper(Locale.mutation(mutation.id)) else "")
	rarityLabel.TextColor3 = rarity.color
	progressLabel.Text = Locale.t("dex.progress", { found = entry.found, total = entry.total })
	loreLabel.Text = Locale.relicLore(entry.relicId)
	burst.BackgroundColor3 = color

	viewport:set(entry.relicId, entry.mutation, entry.isNew)
	backdrop.Visible = true
	backdrop.BackgroundTransparency = 1
	Tween.play(backdrop, 0.3, { BackgroundTransparency = 0.35 })
	card.Visible = true
	cardScale.Scale = 0.6
	Tween.play(cardScale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
	for _, label in { nameLabel, loreLabel, progressLabel, rarityLabel } do
		label.TextTransparency = 1
	end
	Audio.play("Discovery")

	task.delay(0.95, function()
		if token ~= dismissToken then
			return
		end
		flash.BackgroundTransparency = 0
		Tween.play(flash, 0.6, { BackgroundTransparency = 1 })
		viewport:set(entry.relicId, entry.mutation, false)
		confetti(color)
		Audio.play("Fuse", { pitch = 1.2 })
		if rarity.order >= 5 then
			Audio.play("RareEmerge", { volume = 0.6 })
		end
		for i, label in { nameLabel, rarityLabel, loreLabel, progressLabel } do
			Tween.play(label, 0.35, { TextTransparency = 0 }, nil, nil, i * 0.08)
		end
	end)
	task.delay(4.8, function()
		if token == dismissToken then
			hide()
		end
	end)
end

function Discovery.init(parent: Instance, fullscreen: Instance)
	backdrop = Create("TextButton", {
		Name = "DiscoveryBackdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(4, 2, 12),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Visible = false,
		Parent = fullscreen,
	})
	backdrop.Activated:Connect(hide)

	card = Create("Frame", {
		Name = "Discovery",
		Size = UDim2.fromOffset(460, 520),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = parent,
	})
	cardScale = Create("UIScale", { Parent = card })
	burst = Create("Frame", {
		Size = UDim2.fromOffset(440, 440),
		Position = UDim2.fromScale(0.5, 0.36),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		Parent = card,
	})
	-- Sunburst rays.
	for i = 0, 7 do
		local ray = Create("Frame", {
			Size = UDim2.new(0, 36, 1, 0),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = i * 22.5,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Parent = burst,
		})
		Create("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0.7),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = ray,
		})
	end
	local glow = Create("Frame", {
		Size = UDim2.fromOffset(260, 260),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.82,
		Parent = burst,
	})
	Style.corner(glow, UDim.new(1, 0))

	viewport = RelicViewport.new({ size = UDim2.fromOffset(300, 280), position = UDim2.new(0.5, 0, 0.36, 0), anchor = Vector2.new(0.5, 0.5), parent = card })
	flash = Create("Frame", {
		Size = UDim2.fromOffset(300, 280),
		Position = UDim2.new(0.5, 0, 0.36, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		Parent = card,
	})
	Style.corner(flash, UDim.new(1, 0))

	caption = Style.text({ Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 0), TextXAlignment = Enum.TextXAlignment.Center, FontFace = Theme.Fonts.Heavy, TextSize = 22, TextColor3 = Theme.Colors.Gold, Parent = card })
	Style.textStroke(caption, 0.3, 2)
	Create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Theme.Colors.Gold),
			ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(1, Theme.Colors.Gold),
		}),
		Parent = caption,
	})
	nameLabel = Style.text({ Size = UDim2.new(1, 0, 0, 44), Position = UDim2.new(0, 0, 0.66, 0), TextXAlignment = Enum.TextXAlignment.Center, FontFace = Theme.Fonts.Display, TextSize = 38, Parent = card })
	Style.textStroke(nameLabel, 0.2, 2.5)
	rarityLabel = Style.text({ Size = UDim2.new(1, 0, 0, 22), Position = UDim2.new(0, 0, 0.66, 46), TextXAlignment = Enum.TextXAlignment.Center, FontFace = Theme.Fonts.Heavy, TextSize = 16, Parent = card })
	Style.textStroke(rarityLabel, 0.3, 1.5)
	loreLabel = Style.text({ Size = UDim2.new(1, -40, 0, 40), Position = UDim2.new(0, 20, 0.66, 72), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true, FontFace = Theme.Fonts.Body, TextSize = 15, TextColor3 = Theme.Colors.TextDim, Parent = card })
	Style.textStroke(loreLabel, 0.5, 1.5)
	progressLabel = Style.text({ Size = UDim2.new(1, 0, 0, 22), Position = UDim2.new(0, 0, 1, -22), TextXAlignment = Enum.TextXAlignment.Center, FontFace = Theme.Fonts.Heavy, TextSize = 16, TextColor3 = Theme.Colors.Essence, Parent = card })
	Style.textStroke(progressLabel, 0.3, 1.5)

	RunService.RenderStepped:Connect(function(dt: number)
		if card.Visible then
			burst.Rotation = (burst.Rotation + dt * 18) % 360
		end
	end)
end

return Discovery
