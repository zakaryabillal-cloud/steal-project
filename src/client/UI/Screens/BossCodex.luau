--!strict
-- Boss Codex (V2 phase 6): one card per boss of Config/Bosses (extensible:
-- phase 7 bosses appear automatically), from the player's saved record:
-- discovered (else an ink silhouette and "???"), attempts, victories, best
-- time, rare rewards obtained. Below: boss materials kept for the future
-- Forge and the trophy pedestals unlocked by the Power record.

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
local Modal = require(Kit.Modal)

local Controllers = script.Parent.Parent.Parent.Controllers
local Store = require(Controllers.Store)
local BossFolder = script.Parent.Parent.Parent.Boss
local BossRig = require(BossFolder.BossRig)
local BossModels = require(BossFolder.BossModels)

local BossCodex = {}

local PURPLE = Color3.fromRGB(150, 96, 240)
local INK = Color3.fromRGB(30, 27, 75)

type Card = {
	def: Bosses.BossDef,
	frame: Frame,
	name: TextLabel,
	title: TextLabel,
	stats: TextLabel,
	rare: TextLabel,
	rig: BossRig.Rig?,
	model: BossRig.ModelModule,
	viewport: ViewportFrame,
	known: boolean?,
}

local modal: Modal.Modal
local cards: { Card } = {}
local materialsLabel: TextLabel
local trophiesLabel: TextLabel
local isOpen = false

local function buildCard(parent: Instance, def: Bosses.BossDef, order: number): Card
	local frame = Style.card({ Name = "Boss_" .. def.id, Size = UDim2.new(1, -8, 0, 210), LayoutOrder = order, Parent = parent })
	local viewport: ViewportFrame = Create("ViewportFrame", {
		Name = "Viewport",
		Size = UDim2.fromOffset(190, 190),
		Position = UDim2.fromOffset(10, 10),
		BackgroundColor3 = Color3.fromRGB(110, 70, 210),
		Ambient = Color3.fromRGB(200, 190, 230),
		LightColor = Color3.new(1, 1, 1),
		Parent = frame,
	})
	Style.corner(viewport, Theme.Radius.Medium)
	Style.stroke(viewport, INK, 0, 2)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.CFrame = CFrame.lookAt(Vector3.new(12, 5, -32), Vector3.new(0, 1, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	-- Every boss brings its own body (Client/Boss/BossModels).
	local model = BossModels.get(def.id)
	local scale = if def.id == "Forgeheart" then 0.8 else 1
	local rig = model.build(scale, viewport)
	model.pose(rig, CFrame.Angles(0, math.pi, 0), model.defaultPose(), 0)
	local name = Style.display({ Name = "Name", Size = UDim2.new(1, -230, 0, 34), Position = UDim2.fromOffset(214, 10), TextSize = 28, Parent = frame })
	local title = Style.text({ Name = "Title", Size = UDim2.new(1, -230, 0, 22), Position = UDim2.fromOffset(214, 44), TextSize = 16, TextWrapped = true, FontFace = Theme.Fonts.Body, TextColor3 = Theme.Colors.TextDim, Parent = frame })
	local stats = Style.text({ Name = "Stats", Size = UDim2.new(1, -230, 0, 60), Position = UDim2.fromOffset(214, 72), TextSize = 17, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, FontFace = Theme.Fonts.Heavy, Parent = frame })
	Style.ink(stats, 1.5)
	local rare = Style.text({ Name = "Rare", Size = UDim2.new(1, -230, 0, 66), Position = UDim2.fromOffset(214, 136), TextSize = 15, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, FontFace = Theme.Fonts.Heavy, Parent = frame })
	Style.ink(rare, 1.5)
	return { def = def, frame = frame, name = name, title = title, stats = stats, rare = rare, rig = rig, model = model, viewport = viewport, known = nil }
end

local function lootName(entry: Bosses.LootEntry): string
	if entry.kind == "relic" then
		return Emoji.get("trophy") .. " " .. Locale.relicName(tostring(entry.ref))
	elseif entry.kind == "cosmetic" then
		return Emoji.get("rainbow") .. " " .. Locale.t("cos." .. tostring(entry.ref))
	elseif entry.kind == "material" then
		local def = Materials.get(entry.ref)
		return Emoji.get(if def then def.emoji else "gem") .. " " .. Locale.t("mat." .. tostring(entry.ref))
	end
	return entry.id
end

function BossCodex.refresh()
	local codex = Store.state.bosses or {}
	local found = 0
	for _, card in cards do
		local record = codex[card.def.id]
		local known = record ~= nil and record.discovered == true
		if known then
			found += 1
		end
		local rig = card.rig
		if rig and card.known ~= known then
			if known and card.known == false then
				-- Discovered: the silhouette becomes the real (colourful) boss.
				card.model.destroy(rig)
				local fresh = card.model.build(if card.def.id == "Forgeheart" then 0.8 else 1, card.viewport)
				card.model.pose(fresh, CFrame.Angles(0, math.pi, 0), card.model.defaultPose(), 0)
				card.rig = fresh
			elseif not known then
				card.model.silhouette(rig, INK)
			end
			card.known = known
		end
		card.name.Text = if known then Locale.t("boss." .. card.def.id .. ".name") else Locale.t("boss.codex.unknown")
		card.title.Text = if known then Locale.t("boss." .. card.def.id .. ".title") .. "  ·  " .. Locale.t("boss.rank", { rank = string.rep("I", card.def.rank) }) else Locale.t("boss.codex.unknownHint")
		if known and record then
			local best = if record.bestTime > 0 then Format.clock(record.bestTime) else Locale.t("boss.codex.none")
			card.stats.Text = string.format("%s %s <b>%d</b>    %s %s <b>%d</b>\n%s %s <b>%s</b>", Emoji.get("goal"), Locale.t("boss.codex.attempts"), record.attempts, Emoji.get("crown"), Locale.t("boss.codex.wins"), record.wins, Emoji.get("time"), Locale.t("boss.codex.bestTime"), best)
			local lines = {}
			for _, entry in card.def.loot do
				if entry.rare then
					local count = record.rare[entry.id] or 0
					table.insert(lines, lootName(entry) .. "  " .. (if count > 0 then Style.colored("×" .. count, Theme.Colors.Gold) else Style.colored(Locale.t("boss.codex.none"), Theme.Colors.TextMuted)))
				end
			end
			card.rare.Text = Style.colored(Locale.t("boss.codex.rare"), Theme.Colors.Gold) .. "\n" .. table.concat(lines, "    ")
		else
			card.stats.Text = ""
			card.rare.Text = ""
		end
	end
	modal.subtitle.Text = Locale.t("boss.codex.subtitle", { found = found, total = #Bosses.list })
	local parts = {}
	for _, def in Materials.list do
		table.insert(parts, string.format("%s %s <b>%d</b>", Emoji.get(def.emoji), Locale.t("mat." .. def.id), Store.state.materials[def.id] or 0))
	end
	materialsLabel.Text = Style.colored(Locale.t("boss.codex.materials"), Theme.Colors.Gold) .. "   " .. table.concat(parts, "    ") .. "\n" .. Style.colored(Locale.t("boss.codex.forge"), Theme.Colors.TextMuted)
	local unlocked = Bosses.trophySlots(Store.state.powerPeak)
	local nextAt = Bosses.Trophies.Unlocks[unlocked + 1]
	trophiesLabel.Text = string.format("%s %s", Emoji.get("trophy"), Locale.t(if nextAt then "boss.codex.trophies" else "boss.codex.trophiesAll", { unlocked = unlocked, total = #Bosses.Trophies.Unlocks, next = nextAt or 0 }))
end

-- Tests / debug.
function BossCodex.debugCards(): { { id: string, name: string, stats: string } }
	local out = {}
	for _, card in cards do
		table.insert(out, { id = card.def.id, name = card.name.Text, stats = card.stats.Text })
	end
	return out
end

function BossCodex.init(parent: Instance, close: () -> ()): Modal.Modal
	modal = Modal.new({ name = "BossCodex", size = UDim2.fromOffset(720, 600), parent = parent, onClose = close, accent = PURPLE, emoji = Emoji.get("dex") })
	modal.title.Text = Locale.t("boss.codex.title")
	local scroll: ScrollingFrame = Create("ScrollingFrame", {
		Name = "List",
		Size = UDim2.new(1, 0, 1, -110),
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
	for index, def in Bosses.list do
		table.insert(cards, buildCard(scroll, def, index))
	end
	local footer = Style.card({ Name = "Footer", Size = UDim2.new(1, 0, 0, 100), Position = UDim2.new(0, 0, 1, 0), AnchorPoint = Vector2.new(0, 1), Parent = modal.body })
	Style.padding(footer, 8, 12)
	materialsLabel = Style.text({ Name = "Materials", Size = UDim2.new(1, 0, 0, 52), TextSize = 16, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, FontFace = Theme.Fonts.Heavy, Parent = footer })
	Style.ink(materialsLabel, 1.5)
	trophiesLabel = Style.text({ Name = "Trophies", Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 56), TextSize = 15, TextWrapped = true, FontFace = Theme.Fonts.Heavy, Parent = footer })
	Style.ink(trophiesLabel, 1.5)
	local baseOpen, baseClose = modal.open, modal.close
	modal.open = function()
		isOpen = true
		BossCodex.refresh()
		baseOpen()
	end
	modal.close = function()
		isOpen = false
		baseClose()
	end
	-- The models turn slowly while the Codex is open.
	RunService.Heartbeat:Connect(function(dt: number)
		if not isOpen then
			return
		end
		for _, card in cards do
			if card.rig then
				local pose = card.model.defaultPose()
				pose.squash = 1 + math.sin(os.clock() * 2.5) * 0.04
				pose.eyesClosed = card.known ~= true
				card.model.pose(card.rig, CFrame.Angles(0, math.pi + math.sin(os.clock() * 0.8) * 0.4, 0), pose, dt)
				if card.known ~= true then
					card.model.silhouette(card.rig, INK)
				end
			end
		end
	end)
	Store.changed:Connect(function()
		BossCodex.refresh()
	end)
	Locale.changed:Connect(function()
		modal.title.Text = Locale.t("boss.codex.title")
		BossCodex.refresh()
	end)
	BossCodex.refresh()
	return modal
end

return BossCodex
