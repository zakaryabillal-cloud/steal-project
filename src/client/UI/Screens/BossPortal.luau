--!strict
-- Boss portal card (V2 phase 6): the "wrestling poster" shown before an
-- expedition (docs/ART_DIRECTION.md). Opened from the portal prompt on the
-- Boss Plateau or from the HUD Boss bar.
--
--   * the boss itself (live 3D model in a viewport), rank, difficulty stars;
--   * recommended Power vs yours, the Power record gate, the small capped
--     strike bonus your current Power gives (PvP is never affected);
--   * every possible reward with its EXACT probability for each eligible
--     player (straight from Config/Bosses, the same table the server rolls);
--   * the rules, the portal countdown, who is inside, and the ENTER button
--     (the server re-checks everything).
--   * phase 7A: the card follows the boss of the portal (Void Warden or
--     Forgeheart: model, colours, loot rows), shows its music theme and the
--     next boss of the rotation.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Bosses = require(Shared.Config.Bosses)
local Materials = require(Shared.Config.Materials)
local Theme = require(Shared.Config.Theme)
local Emoji = require(Shared.Config.Emoji)
local Locale = require(Shared.Locale)
local Format = require(Shared.Util.Format)

local Kit = script.Parent.Parent.Kit
local Create = require(Kit.Create)
local Style = require(Kit.Style)
local Tween = require(Kit.Tween)
local Button = require(Kit.Button)
local Modal = require(Kit.Modal)
local Juice = require(Kit.Juice)

local Controllers = script.Parent.Parent.Parent.Controllers
local Boss = require(Controllers.Boss)
local Store = require(Controllers.Store)
local Audio = require(Controllers.Audio)
local Music = require(Shared.Config.Music)
local BossFolder = script.Parent.Parent.Parent.Boss
local BossRig = require(BossFolder.BossRig)
local BossModels = require(BossFolder.BossModels)

local BossPortal = {}

local PURPLE = Color3.fromRGB(150, 96, 240)

local modal: Modal.Modal
local closeModal: () -> ()
local openCodex: (() -> ())? = nil
local openWeapons: (() -> ())? = nil
local isOpen = false
local rankLabel: TextLabel
local starsLabel: TextLabel
local loreLabel: TextLabel
local recommendedLabel: TextLabel
local yourLabel: TextLabel
local gateLabel: TextLabel
local bonusLabel: TextLabel
local lootRows: { [string]: TextLabel } = {}
local rulesLabel: TextLabel
local statusLabel: TextLabel
local enterButton: Button.Button
local reasonLabel: TextLabel
local viewport: ViewportFrame
local rig: BossRig.Rig? = nil
local rigModel: BossRig.ModelModule? = nil
local poster: Frame
local lootCard: Frame
local musicLabel: TextLabel
local nextLabel: TextLabel
local shownBoss = ""
-- Poster colour per boss.
local POSTER: { [string]: Color3 } = {
	VoidWarden = Color3.fromRGB(110, 70, 210),
	Forgeheart = Color3.fromRGB(196, 84, 44),
	TempestSeraph = Color3.fromRGB(70, 120, 210),
}
-- Model scale on the card (the big ones are shrunk to fit the poster).
local CARD_SCALE: { [string]: number } = {
	Forgeheart = 0.8,
	TempestSeraph = 0.8,
}
local lastReason: string? = nil
local reasonUntil = 0

local function lootText(entry: Bosses.LootEntry): (string, string)
	if entry.kind == "essence" then
		return Emoji.get("money"), Locale.t("loot.essence", { minutes = entry.minutes or 0 })
	elseif entry.kind == "material" then
		local def = Materials.get(entry.ref)
		local amount = if entry.min == entry.max then "×" .. tostring(entry.min) else Locale.t("loot.amount", { min = entry.min or 1, max = entry.max or 1 })
		return Emoji.get(if def then def.emoji else "gem"), Locale.t("mat." .. tostring(entry.ref)) .. "  " .. amount
	elseif entry.kind == "relic" then
		return Emoji.get("trophy"), Locale.relicName(tostring(entry.ref))
	elseif entry.kind == "cosmetic" then
		return Emoji.get("rainbow"), Locale.t("cos." .. tostring(entry.ref))
	end
	return Emoji.get("gift"), entry.id
end

-- Exact probability line, e.g. "8 %  ★" (rare rewards get a star).
function BossPortal.lootLine(entry: Bosses.LootEntry): string
	local icon, name = lootText(entry)
	local chance = Style.colored(Bosses.percent(entry.chance), if entry.chance >= 1 then Theme.Colors.Success else Theme.Colors.Gold)
	return string.format("%s  %s   <b>%s</b>%s", icon, name, chance, if entry.rare then "  " .. Style.colored("★", Theme.Colors.Gold) else "")
end

-- Why ENTER is greyed out (nil = looks fine; the server decides anyway).
function BossPortal.blockReason(): string?
	local view = Boss.portal()
	local def = Boss.portalBoss()
	if Boss.inFight() then
		return "already"
	elseif view.state == "Fight" then
		return "fighting"
	elseif view.state ~= "Open" then
		return "closed"
	elseif Store.state.powerPeak < def.minPowerRecord then
		return "power"
	elseif #Store.state.carrying > 0 then
		return "carrying"
	elseif Boss.portalDistance() > Bosses.Portal.JoinRadius then
		return "far"
	end
	return nil
end

local function buildPoster(body: Frame)
	poster = Style.card({ Name = "Poster", Size = UDim2.new(0, 300, 1, 0), BackgroundColor3 = POSTER.VoidWarden, ClipsDescendants = true, Parent = body })
	local rays = Juice.rays(poster, Color3.fromRGB(255, 200, 255), 12, 1)
	rays.Size = UDim2.fromOffset(520, 520)
	rays.Position = UDim2.new(0.5, 0, 0, 150)
	viewport = Create("ViewportFrame", {
		Name = "Viewport",
		Size = UDim2.fromOffset(280, 270),
		Position = UDim2.new(0.5, 0, 0, 6),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(200, 190, 230),
		LightColor = Color3.new(1, 1, 1),
		ZIndex = 3,
		Parent = poster,
	})
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.CFrame = CFrame.lookAt(Vector3.new(14, 6, -34), Vector3.new(0, 1, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	rankLabel = Style.display({ Name = "Rank", Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(10, 280), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 24, TextColor3 = Theme.Colors.Gold, ZIndex = 3, Parent = poster })
	starsLabel = Style.text({ Name = "Difficulty", Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(10, 312), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 20, FontFace = Theme.Fonts.Display, ZIndex = 3, Parent = poster })
	Style.ink(starsLabel, 2)
	loreLabel = Style.text({ Name = "Lore", Size = UDim2.new(1, -24, 0, 92), Position = UDim2.fromOffset(12, 344), TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, TextSize = 16, FontFace = Theme.Fonts.Body, TextColor3 = Theme.Colors.TextDim, ZIndex = 3, Parent = poster })
	-- Phase 7A: the boss theme and the rotation preview.
	musicLabel = Style.text({ Name = "Music", Size = UDim2.new(1, -24, 0, 20), Position = UDim2.fromOffset(12, 438), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 15, FontFace = Theme.Fonts.Heavy, ZIndex = 3, Parent = poster })
	Style.ink(musicLabel, 1.5)
	nextLabel = Style.text({ Name = "NextBoss", Size = UDim2.new(1, -24, 0, 22), Position = UDim2.fromOffset(12, 460), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 16, FontFace = Theme.Fonts.Display, TextColor3 = Theme.Colors.Gold, ZIndex = 3, Parent = poster })
	Style.ink(nextLabel, 1.5)
end

local function buildDetails(body: Frame)
	local column: Frame = Create("Frame", { Name = "Details", Size = UDim2.new(1, -316, 1, 0), Position = UDim2.fromOffset(316, 0), BackgroundTransparency = 1, Parent = body })
	local power = Style.card({ Name = "Power", Size = UDim2.new(1, 0, 0, 118), Parent = column })
	Style.padding(power, 8, 12)
	Style.list(power, 2, Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Left)
	recommendedLabel = Style.text({ Name = "Recommended", Size = UDim2.new(1, 0, 0, 24), TextSize = 18, FontFace = Theme.Fonts.Display, LayoutOrder = 1, Parent = power })
	Style.ink(recommendedLabel, 1.5)
	yourLabel = Style.text({ Name = "Yours", Size = UDim2.new(1, 0, 0, 24), TextSize = 18, FontFace = Theme.Fonts.Display, LayoutOrder = 2, Parent = power })
	Style.ink(yourLabel, 1.5)
	gateLabel = Style.text({ Name = "Gate", Size = UDim2.new(1, 0, 0, 20), TextSize = 15, FontFace = Theme.Fonts.Heavy, LayoutOrder = 3, Parent = power })
	bonusLabel = Style.text({ Name = "Bonus", Size = UDim2.new(1, 0, 0, 20), TextSize = 14, FontFace = Theme.Fonts.Body, TextColor3 = Theme.Colors.TextDim, TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = 4, Parent = power })

	local loot = Style.card({ Name = "Loot", Size = UDim2.new(1, 0, 0, 228), Position = UDim2.fromOffset(0, 128), Parent = column })
	lootCard = loot
	Style.padding(loot, 8, 12)
	Style.list(loot, 4, Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Left)
	local header = Style.text({ Name = "Header", Size = UDim2.new(1, 0, 0, 24), Text = Locale.t("boss.loot"), TextSize = 18, FontFace = Theme.Fonts.Display, TextColor3 = Theme.Colors.Gold, LayoutOrder = 0, Parent = loot })
	Style.ink(header, 1.5)
	header:SetAttribute("Key", "boss.loot")
	local note = Style.text({ Name = "Note", Size = UDim2.new(1, 0, 0, 34), TextSize = 13, TextWrapped = true, FontFace = Theme.Fonts.Body, TextColor3 = Theme.Colors.TextDim, LayoutOrder = 99, Parent = loot })
	note:SetAttribute("Key", "boss.lootNote")

	rulesLabel = Style.text({ Name = "Rules", Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromOffset(0, 364), TextSize = 14, TextWrapped = true, FontFace = Theme.Fonts.Body, TextColor3 = Theme.Colors.TextDim, Parent = column })
	statusLabel = Style.display({ Name = "Status", Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 400), TextSize = 19, TextColor3 = Theme.Colors.Gold, Parent = column })
	reasonLabel = Style.text({ Name = "Reason", Size = UDim2.new(1, -210, 0, 52), Position = UDim2.new(0, 0, 1, -4), AnchorPoint = Vector2.new(0, 1), TextSize = 15, TextWrapped = true, FontFace = Theme.Fonts.Heavy, TextColor3 = Color3.fromRGB(255, 200, 210), Parent = column })
	Style.ink(reasonLabel, 1.5)
	enterButton = Button.new({
		name = "Enter",
		size = UDim2.fromOffset(200, 62),
		position = UDim2.new(1, 0, 1, -2),
		anchor = Vector2.new(1, 1),
		kind = "green",
		corner = Theme.Radius.Large,
		text = Locale.t("boss.enter"),
		textSize = 26,
		font = Theme.Fonts.Display,
		parent = column,
		onClick = function()
			BossPortal.enter()
		end,
	})
end

-- Rebuilds what depends on the boss (model, colours, loot rows).
local function showBoss(def: Bosses.BossDef)
	shownBoss = def.id
	poster.BackgroundColor3 = POSTER[def.id] or POSTER.VoidWarden
	if rig and rigModel then
		rigModel.destroy(rig)
	end
	local model = BossModels.get(def.id)
	rigModel = model
	rig = model.build(CARD_SCALE[def.id] or 1, viewport)
	model.pose(rig :: BossRig.Rig, CFrame.Angles(0, math.pi, 0), model.defaultPose(), 0)
	for _, row in lootRows do
		row:Destroy()
	end
	table.clear(lootRows)
	for index, entry in def.loot do
		local row = Style.text({ Name = "Loot_" .. entry.id, Size = UDim2.new(1, 0, 0, 26), TextSize = 17, FontFace = Theme.Fonts.Heavy, TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = index, Parent = lootCard })
		Style.ink(row, 1.5)
		lootRows[entry.id] = row
	end
end

local function refresh()
	if not isOpen then
		return
	end
	local def = Boss.portalBoss()
	if def.id ~= shownBoss then
		showBoss(def)
	end
	local theme = Music.bossTheme(def.id)
	musicLabel.Text = if theme and theme.title then Emoji.get("music") .. " " .. Locale.t("boss.music", { title = theme.title }) else ""
	local after = Boss.portalNextBoss()
	nextLabel.Text = if after then Locale.t("boss.next", { boss = Locale.t("boss." .. after.id .. ".name") }) else ""
	local view = Boss.portal()
	local t = Boss.now()
	modal.title.Text = Locale.t("boss." .. def.id .. ".name")
	modal.subtitle.Text = Locale.t("boss." .. def.id .. ".title")
	rankLabel.Text = Locale.t("boss.rank", { rank = string.rep("I", def.rank) })
	starsLabel.Text = Locale.t("boss.difficulty") .. "  " .. Style.colored(string.rep("★", def.difficulty), Theme.Colors.Gold) .. Style.colored(string.rep("★", 5 - def.difficulty), Color3.fromRGB(120, 110, 170))
	loreLabel.Text = Locale.t("boss." .. def.id .. ".lore")
	local power = Store.state.power
	local peak = Store.state.powerPeak
	recommendedLabel.Text = string.format("%s %s  <b>%s</b>", Emoji.get("power"), Locale.t("boss.recommended"), Format.abbrev(def.recommendedPower))
	local yourColor = if power >= def.recommendedPower then Theme.Colors.Success elseif peak >= def.minPowerRecord then Theme.Colors.Warning else Theme.Colors.Danger
	yourLabel.Text = string.format("%s %s  <b>%s</b>", Emoji.get("strong"), Locale.t("boss.yourPower"), Style.colored(Format.abbrev(power), yourColor))
	gateLabel.Text = Style.colored(Locale.t("boss.minPower", { power = def.minPowerRecord }), if peak >= def.minPowerRecord then Theme.Colors.Success else Theme.Colors.Danger)
	bonusLabel.Text = Locale.t("boss.powerBonus", { bonus = math.floor(Bosses.powerBonus(power) * 100 + 0.5), cap = math.floor(Bosses.Strike.PowerBonusCap * 100 + 0.5) })
	for _, entry in def.loot do
		local row = lootRows[entry.id]
		if row then
			row.Text = BossPortal.lootLine(entry)
		end
	end
	for _, label in modal.body:GetDescendants() do
		local key = label:GetAttribute("Key")
		if type(key) == "string" and label:IsA("TextLabel") then
			label.Text = Locale.t(key)
		end
	end
	rulesLabel.Text = Locale.t("boss.rules", { hearts = Bosses.Combat.Hearts })
	if view.state == "Open" then
		statusLabel.Text = string.format("%s %s  ·  %s", Emoji.get("time"), Locale.t("boss.closesIn", { time = Format.clock(math.max(0, view.closesAt - t)) }), Locale.t("boss.participants", { count = view.count }))
	elseif view.state == "Fight" then
		statusLabel.Text = Emoji.get("boom") .. " " .. Locale.t("boss.inProgress", { count = view.count })
	else
		statusLabel.Text = Emoji.get("time") .. " " .. Locale.t("boss.opensIn", { time = Format.clock(math.max(0, view.opensAt - t)) })
	end
	local reason = BossPortal.blockReason()
	enterButton:setEnabled(reason == nil)
	if t < reasonUntil and lastReason then
		reasonLabel.Text = Locale.t("boss.join." .. lastReason)
	else
		reasonLabel.Text = if reason and reason ~= "closed" and reason ~= "fighting" then Locale.t("boss.join." .. reason) else ""
	end
	if rig and rigModel then
		local pose = rigModel.defaultPose()
		pose.squash = 1 + math.sin(os.clock() * 3) * 0.05
		pose.broom = 0.5 + math.sin(os.clock() * 2) * 0.3
		pose.mood = "grumpy"
		rigModel.pose(rig, CFrame.Angles(0, math.pi + math.sin(os.clock()) * 0.25, 0), pose, 0.25)
	end
end

function BossPortal.enter(): (boolean, string?)
	local ok, reason = Boss.join()
	if ok then
		Audio.play("Purchase")
		closeModal()
	else
		lastReason = reason or "error"
		reasonUntil = Boss.now() + 3
		Audio.play("UiError")
		Tween.wiggle(enterButton.instance, 6)
		refresh()
	end
	return ok, reason
end

-- Tests / debug.
function BossPortal.debugRows(): { [string]: string }
	local out = {}
	for id, row in lootRows do
		out[id] = row.Text
	end
	return out
end

function BossPortal.isEnterEnabled(): boolean
	return enterButton.enabled
end

function BossPortal.setCodexOpener(fn: () -> ())
	openCodex = fn
end

function BossPortal.setWeaponsOpener(fn: () -> ())
	openWeapons = fn
end

function BossPortal.init(parent: Instance, close: () -> ()): Modal.Modal
	closeModal = close
	modal = Modal.new({ name = "BossPortal", size = UDim2.fromOffset(780, 600), parent = parent, onClose = close, accent = PURPLE, emoji = Emoji.get("trophy") })
	buildPoster(modal.body)
	buildDetails(modal.body)
	local codex = Button.new({
		name = "Codex",
		size = UDim2.fromOffset(120, 44),
		position = UDim2.new(1, -70, 0, 26),
		anchor = Vector2.new(1, 0),
		kind = "blue",
		corner = Theme.Radius.Large,
		text = Emoji.get("dex") .. " Codex",
		textSize = 17,
		zIndex = 8,
		parent = modal.panel,
		onClick = function()
			if openCodex then
				openCodex()
			end
		end,
	})
	local _ = codex
	-- Boss weapons shop (phase 6.5), next to the Codex.
	Button.new({
		name = "WeaponsLink",
		size = UDim2.fromOffset(120, 44),
		position = UDim2.new(1, -198, 0, 26),
		anchor = Vector2.new(1, 0),
		kind = "orange",
		corner = Theme.Radius.Large,
		text = Emoji.get("weapons") .. " " .. Locale.t("hud.weapons"),
		textSize = 17,
		zIndex = 8,
		parent = modal.panel,
		onClick = function()
			if openWeapons then
				openWeapons()
			end
		end,
	})
	local baseOpen, baseClose = modal.open, modal.close
	modal.open = function()
		isOpen = true
		lastReason = nil
		refresh()
		baseOpen()
	end
	modal.close = function()
		isOpen = false
		baseClose()
	end
	local clock = 0
	RunService.Heartbeat:Connect(function(dt: number)
		clock += dt
		if clock >= 0.25 then
			clock = 0
			refresh()
		end
	end)
	Store.changed:Connect(refresh)
	Locale.changed:Connect(function()
		enterButton:setText(Locale.t("boss.enter"))
		refresh()
	end)
	return modal
end

return BossPortal
