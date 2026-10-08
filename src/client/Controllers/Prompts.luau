--!strict
-- Custom proximity prompt cards (keyboard, gamepad and touch) plus the
-- client-side mirror of steal eligibility: ineligible Steal prompts are
-- disabled locally and replaced with a lock hint explaining why (the server
-- still enforces everything).

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Rarities = require(Shared.Config.Rarities)
local Mutations = require(Shared.Config.Mutations)
local GameConfig = require(Shared.Config.GameConfig)
local Economy = require(Shared.Economy)
local Locale = require(Shared.Locale)
local Format = require(Shared.Util.Format)
local Signal = require(Shared.Util.Signal)

local Kit = script.Parent.Parent.UI.Kit
local Create = require(Kit.Create)
local Style = require(Kit.Style)
local Tween = require(Kit.Tween)

local Store = require(script.Parent.Store)
local Audio = require(script.Parent.Audio)
local RelicRenderer = require(script.Parent.RelicRenderer)

local Prompts = {}

-- (anchor: BasePart) fired when the local player inspects their own relic.
Prompts.inspect = Signal.new()

local localPlayer = Players.LocalPlayer
local guiFolder: Folder
local tracked: { [ProximityPrompt]: boolean } = {}

type Card = {
	gui: BillboardGui,
	scale: UIScale,
	fill: Frame?,
	connections: { RBXScriptConnection },
}
local cards: { [ProximityPrompt]: Card } = {}

-- Prompt card colour per action (Theme.Buttons families: one meaning each).
local ACTION_COLORS = {
	Claim = Color3.fromRGB(76, 217, 100),
	Grab = Color3.fromRGB(255, 205, 50),
	Recover = Color3.fromRGB(80, 225, 190),
	Steal = Color3.fromRGB(255, 84, 96),
	Inspect = Color3.fromRGB(70, 170, 255),
	-- Boss portal (V2 phase 6): the Void Warden's purple.
	Boss = Color3.fromRGB(176, 110, 255),
}

local PROTECTION_KEYS = {
	Novice = "block.novice",
	Aegis = "block.aegis",
	Sealed = "block.sealed",
	Resting = "block.resting",
	Expedition = "block.expedition",
	LastRelics = "block.lastRelics",
}

local function attrNumber(instance: Instance, name: string): number
	local value = instance:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

local function attrString(instance: Instance, name: string): string
	local value = instance:GetAttribute(name)
	return if type(value) == "string" then value else ""
end

local function plotModel(index: number): Instance?
	local folder = workspace:FindFirstChild("Sanctuaries")
	return if folder then folder:FindFirstChild("Sanctuary" .. index) else nil
end

local function canFuse(relicId: string, mutation: string): boolean
	for _, record in RelicRenderer.records do
		if record.state == "Placed" and attrNumber(record.anchor, "OwnerId") == localPlayer.UserId and record.relicId == relicId and (record.mutation or "") == mutation and record.level < GameConfig.Economy.MaxRelicLevel then
			return true
		end
	end
	return false
end

-- Why the local player cannot steal this relic right now (nil = allowed).
function Prompts.lockReason(anchor: Instance): (string?, { [string]: any }?)
	local plot = plotModel(attrNumber(anchor, "Plot"))
	if plot then
		local kind = attrString(plot, "Protection")
		local key = PROTECTION_KEYS[kind]
		if key then
			return key, { time = Format.clock(attrNumber(plot, "ProtectionUntil") - workspace:GetServerTimeNow()) }
		end
	end
	local state = Store.state
	if state.plot == 0 then
		return "block.noPlot", nil
	end
	local cooldown = Store.cooldownRemaining("steal")
	if cooldown > 0 then
		return "block.cooldown", { time = Format.clock(cooldown) }
	end
	if #state.carrying >= Store.carryCapacity() then
		return "block.capacity", nil
	end
	local myPlot = plotModel(state.plot)
	if myPlot then
		local placed = attrNumber(myPlot, "PlacedCount")
		if placed >= Economy.unlockedPedestals(state.upgrades) and not canFuse(attrString(anchor, "RelicId"), attrString(anchor, "Mutation")) then
			return "block.pedestals", nil
		end
	end
	return nil, nil
end

local function actionFor(prompt: ProximityPrompt): string
	local action = attrString(prompt, "Action")
	if action == "Grab" and prompt.Parent and attrNumber(prompt.Parent, "StolenFrom") == localPlayer.UserId then
		return "Recover"
	end
	return action
end

----------------------------------------------------------------------------
-- Cards
----------------------------------------------------------------------------

local function keyText(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): string
	if inputType == Enum.ProximityPromptInputType.Touch then
		return if prompt.HoldDuration > 0 then Locale.t("prompt.hold") else Locale.t("prompt.tap")
	elseif inputType == Enum.ProximityPromptInputType.Gamepad then
		return (string.gsub(prompt.GamepadKeyCode.Name, "Button", ""))
	end
	return prompt.KeyboardKeyCode.Name
end

local function destroyCard(prompt: ProximityPrompt, animate: boolean)
	local card = cards[prompt]
	if not card then
		return
	end
	cards[prompt] = nil
	for _, connection in card.connections do
		connection:Disconnect()
	end
	if animate then
		Tween.play(card.scale, 0.15, { Scale = 0.6 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.16, function()
			card.gui:Destroy()
		end)
	else
		card.gui:Destroy()
	end
end

local function buildCard(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
	destroyCard(prompt, false)
	local anchor = prompt.Parent
	if not anchor or not anchor:IsA("BasePart") then
		return
	end
	local action = actionFor(prompt)
	local color = ACTION_COLORS[action] or Color3.new(1, 1, 1)
	local relicId = attrString(anchor, "RelicId")
	local rarityId = attrString(anchor, "Rarity")
	local rarity = Rarities.byId[rarityId] or Rarities.list[1]
	local mutationId = attrString(anchor, "Mutation")
	local level = math.max(1, attrNumber(anchor, "Level"))
	local touch = inputType == Enum.ProximityPromptInputType.Touch

	local gui: BillboardGui = Create("BillboardGui", {
		Name = "PromptCard",
		Size = UDim2.fromOffset(290, 78),
		StudsOffsetWorldSpace = Vector3.new(0, -(2.4 * rarity.scale + 1.4), 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		Active = true,
		Adornee = anchor,
		ResetOnSpawn = false,
		Parent = guiFolder,
	})
	local root: TextButton = Create("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Parent = gui,
	})
	local scale: UIScale = Create("UIScale", { Scale = 0.6, Parent = root })
	-- The whole card takes the action's colour (green claim, red steal...).
	local panel = Style.panel({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, Parent = root })
	panel.ZIndex = 1
	Style.gloss(panel)

	local key = Create("Frame", {
		Size = UDim2.fromOffset(if touch then 64 else 50, 50),
		Position = UDim2.new(0, 12, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Style.Colors.Cream,
		Parent = panel,
	})
	Style.corner(key, UDim.new(0, 14))
	Style.stroke(key, Style.Colors.Ink, 0, 2.5)
	Style.text({
		Text = keyText(prompt, inputType),
		TextColor3 = Style.Colors.Ink,
		FontFace = Style.Fonts.Display,
		TextSize = if touch then 15 else 26,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = key,
	})

	local textX = if touch then 90 else 74
	local actionKey = "prompt." .. string.lower(action)
	local actionLabel = Style.text({
		Size = UDim2.new(1, -textX - 10, 0, 28),
		Position = UDim2.fromOffset(textX, 7),
		Text = Locale.t(actionKey),
		FontFace = Style.Fonts.Display,
		TextSize = 24,
		Parent = panel,
	})
	Style.ink(actionLabel, 2.5)
	local detail: string
	if action == "Boss" then
		-- Boss portal: which boss, and whether it is open right now.
		local plateau = anchor.Parent
		local bossId = if plateau then attrString(plateau, "PortalBoss") else ""
		local state = if plateau then attrString(plateau, "PortalState") else ""
		detail = string.format("%s  ·  %s", Locale.t("boss." .. bossId .. ".name"), Locale.t("boss.portal." .. string.lower(if state == "" then "dormant" else state)))
	elseif action == "Steal" or action == "Inspect" then
		local title = Locale.relicTitle(relicId, if mutationId == "" then nil else mutationId)
		local rate = Economy.relicBaseRate(relicId, level, if mutationId == "" then nil else mutationId)
		detail = string.format("%s  %s  +%s/s", title, Style.colored(string.rep("★", level), Style.Colors.Gold), Format.abbrev(rate))
	else
		local title = Locale.relicTitle(relicId, if mutationId == "" then nil else mutationId)
		local mutation = Mutations.get(mutationId)
		local titleColor = if mutation then mutation.color:Lerp(rarity.color, 0.3) else rarity.color
		detail = string.format("%s  %s", title, Style.colored(Style.stars(rarity.id), titleColor:Lerp(Color3.new(1, 1, 1), 0.2)))
	end
	local detailLabel = Style.text({
		Size = UDim2.new(1, -textX - 10, 0, 20),
		Position = UDim2.fromOffset(textX, 37),
		Text = detail,
		TextSize = 15,
		FontFace = Style.Fonts.Heavy,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = panel,
	})
	Style.ink(detailLabel, 1.5)

	local fill: Frame? = nil
	if prompt.HoldDuration > 0 then
		local back = Create("Frame", {
			Size = UDim2.new(1, -textX - 14, 0, 9),
			Position = UDim2.fromOffset(textX, 60),
			BackgroundColor3 = Style.Colors.Ink,
			BackgroundTransparency = 0.35,
			Parent = panel,
		})
		Style.corner(back, UDim.new(1, 0))
		Style.stroke(back, Style.Colors.Ink, 0, 1.5)
		local bar = Create("Frame", {
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = Style.Colors.Gold,
			Parent = back,
		})
		Style.corner(bar, UDim.new(1, 0))
		fill = bar
	end

	local card: Card = { gui = gui, scale = scale, fill = fill, connections = {} }
	cards[prompt] = card
	Tween.play(scale, 0.28, { Scale = 1 }, Enum.EasingStyle.Back)

	table.insert(card.connections, prompt.PromptButtonHoldBegan:Connect(function()
		if card.fill then
			card.fill.Size = UDim2.fromScale(0, 1)
			Tween.play(card.fill, prompt.HoldDuration, { Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Linear)
		end
		Tween.play(scale, 0.2, { Scale = 1.06 })
	end))
	table.insert(card.connections, prompt.PromptButtonHoldEnded:Connect(function()
		if card.fill then
			Tween.play(card.fill, 0.2, { Size = UDim2.fromScale(0, 1) })
		end
		Tween.play(scale, 0.2, { Scale = 1 })
	end))
	table.insert(card.connections, prompt.Triggered:Connect(function()
		Tween.pop(panel, 0.15)
	end))
	-- Touch / mouse: drive the prompt directly.
	table.insert(card.connections, root.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			prompt:InputHoldBegin()
		end
	end))
	table.insert(card.connections, root.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			prompt:InputHoldEnd()
		end
	end))
end

----------------------------------------------------------------------------
-- Eligibility + lock hint
----------------------------------------------------------------------------

local hint: BillboardGui
local hintText: TextLabel

local function buildHint()
	hint = Create("BillboardGui", {
		Name = "LockHint",
		Size = UDim2.fromOffset(260, 34),
		ResetOnSpawn = false,
		AlwaysOnTop = true,
		LightInfluence = 0,
		Enabled = false,
		Parent = guiFolder,
	})
	local pill = Style.panel({ Size = UDim2.fromScale(1, 1), Parent = hint })
	Style.corner(pill, UDim.new(1, 0))
	hintText = Style.text({
		Size = UDim2.new(1, -16, 1, 0),
		Position = UDim2.fromOffset(8, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 15,
		FontFace = Style.Fonts.Heavy,
		TextColor3 = Style.Colors.Gold,
		Parent = pill,
	})
	Style.ink(hintText, 1.5)
end

local function refresh()
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local position = if root and root:IsA("BasePart") then root.Position else nil
	local nearestLocked: BasePart? = nil
	local nearestReason: string? = nil
	local nearestArgs: { [string]: any }? = nil
	local nearestDistance = 12

	for prompt in tracked do
		local anchor = prompt.Parent
		if not anchor or not anchor:IsA("BasePart") then
			tracked[prompt] = nil
			continue
		end
		local action = attrString(prompt, "Action")
		local ownerId = attrNumber(anchor, "OwnerId")
		local enabled = true
		if action == "Steal" then
			enabled = false
			if ownerId ~= localPlayer.UserId then
				local reason, args = Prompts.lockReason(anchor)
				enabled = reason == nil
				if reason and position then
					local distance = (anchor.Position - position).Magnitude
					if distance < nearestDistance then
						nearestDistance = distance
						nearestLocked = anchor
						nearestReason = reason
						nearestArgs = args
					end
				end
			end
		elseif action == "Inspect" then
			enabled = ownerId == localPlayer.UserId
		end
		if prompt.Enabled ~= enabled then
			prompt.Enabled = enabled
		end
	end

	if nearestLocked and nearestReason then
		hint.Adornee = nearestLocked
		hint.StudsOffsetWorldSpace = Vector3.new(0, -3.6, 0)
		hintText.Text = "🔒  " .. Locale.t(nearestReason, nearestArgs)
		hint.Enabled = true
	else
		hint.Enabled = false
	end
end

function Prompts.init()
	guiFolder = Instance.new("Folder")
	guiFolder.Name = "Prompts"
	guiFolder.Parent = localPlayer:WaitForChild("PlayerGui")
	buildHint()

	local relics = workspace:WaitForChild("Relics")
	local function track(descendant: Instance)
		if descendant:IsA("ProximityPrompt") then
			tracked[descendant] = true
			if attrString(descendant, "Action") ~= "Claim" then
				descendant.Enabled = false
			end
			descendant.Triggered:Connect(function()
				if attrString(descendant, "Action") == "Inspect" and descendant.Parent and descendant.Parent:IsA("BasePart") then
					Prompts.inspect:Fire(descendant.Parent)
				end
			end)
			descendant.Destroying:Connect(function()
				tracked[descendant] = nil
				destroyCard(descendant, false)
			end)
		end
	end
	relics.DescendantAdded:Connect(track)
	for _, descendant in relics:GetDescendants() do
		track(descendant)
	end
	-- Boss portal prompt (V2 phase 6) on the Boss Plateau.
	task.spawn(function()
		local world = workspace:WaitForChild("World", 30)
		local landmarks = world and world:WaitForChild("Landmarks", 30)
		local plateau = landmarks and landmarks:WaitForChild("BossPlateau", 30)
		if plateau then
			plateau.DescendantAdded:Connect(track)
			for _, descendant in plateau:GetDescendants() do
				track(descendant)
			end
		end
	end)

	ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
		if prompt.Style == Enum.ProximityPromptStyle.Custom and tracked[prompt] then
			buildCard(prompt, inputType)
			Audio.play("UiHover", { volume = 0.6 })
		end
	end)
	ProximityPromptService.PromptHidden:Connect(function(prompt)
		destroyCard(prompt, true)
	end)

	task.spawn(function()
		while true do
			task.wait(0.2)
			refresh()
		end
	end)
end

return Prompts
