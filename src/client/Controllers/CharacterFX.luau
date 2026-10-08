--!strict
-- Character-level feedback visible to everyone:
--   * floating carry marker above carriers (rarity, "STOLEN" tag), through
--     walls for big relics so chases are readable,
--   * red outline on thieves (during a steal hold, and for victims chasing),
--   * dash trails, pulse shockwaves, hit sparks and dazed stars.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Rarities = require(Shared.Config.Rarities)
local GameConfig = require(Shared.Config.GameConfig)
local Locale = require(Shared.Locale)
local Emoji = require(Shared.Config.Emoji)

local Kit = script.Parent.Parent.UI.Kit
local Create = require(Kit.Create)
local Style = require(Kit.Style)
local Tween = require(Kit.Tween)

local Audio = require(script.Parent.Audio)
local CameraFX = require(script.Parent.CameraFX)
local RelicRenderer = require(script.Parent.RelicRenderer)

local CharacterFX = {}

-- Carry marker text: stars + rarity (same on real carriers and decoys).
function CharacterFX.markerText(rarityId: string): string
	return Style.stars(rarityId) .. " " .. string.upper(Locale.rarity(rarityId))
end

local localPlayer = Players.LocalPlayer
local fxFolder: Folder
local worldFolder: Folder

type Marker = { gui: BillboardGui, chip: Frame, label: TextLabel, stolen: TextLabel }
local markers: { [Player]: Marker } = {}
local highlights: { [Player]: Highlight } = {}
local stealHighlightUntil: { [Player]: number } = {}

local function character(userId: number): (Model?, BasePart?)
	local player = Players:GetPlayerByUserId(userId)
	local model = player and player.Character
	local root = model and model:FindFirstChild("HumanoidRootPart")
	if model and root and root:IsA("BasePart") then
		return model, root
	end
	return nil, nil
end

----------------------------------------------------------------------------
-- Carry markers
----------------------------------------------------------------------------

local function ensureMarker(player: Player, head: BasePart): Marker
	local marker = markers[player]
	if marker and marker.gui.Parent then
		marker.gui.Adornee = head
		return marker
	end
	local gui: BillboardGui = Create("BillboardGui", {
		Name = "CarryMarker_" .. player.UserId,
		Size = UDim2.fromOffset(160, 48),
		StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0),
		LightInfluence = 0,
		MaxDistance = 400,
		ResetOnSpawn = false,
		Adornee = head,
		Parent = fxFolder,
	})
	local chip: Frame = Create("Frame", {
		Size = UDim2.fromOffset(136, 24),
		Position = UDim2.new(0.5, 0, 0, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Style.Colors.Panel,
		Parent = gui,
	})
	Style.corner(chip, UDim.new(1, 0))
	Style.stroke(chip, Style.Colors.Ink, 0, 2)
	local label = Style.text({
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		FontFace = Style.Fonts.Heavy,
		TextSize = 13,
		Parent = chip,
	})
	Style.ink(label, 1.5)
	local stolen = Style.text({
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.fromOffset(0, 26),
		TextXAlignment = Enum.TextXAlignment.Center,
		FontFace = Style.Fonts.Display,
		TextSize = 16,
		TextColor3 = Style.Colors.Danger,
		Text = "",
		Parent = gui,
	})
	Style.ink(stolen, 2)
	local created: Marker = { gui = gui, chip = chip, label = label, stolen = stolen }
	markers[player] = created
	return created
end

local function removeMarker(player: Player)
	local marker = markers[player]
	if marker then
		marker.gui:Destroy()
		markers[player] = nil
	end
end

local function setHighlight(player: Player, on: boolean)
	local existing = highlights[player]
	if on then
		local model = player.Character
		if not model then
			return
		end
		if existing and existing.Parent and existing.Adornee == model then
			return
		end
		if existing then
			existing:Destroy()
		end
		highlights[player] = Create("Highlight", {
			FillColor = Style.Colors.Danger,
			FillTransparency = 0.75,
			OutlineColor = Style.Colors.Danger,
			OutlineTransparency = 0,
			DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
			Adornee = model,
			Parent = worldFolder,
		})
	elseif existing then
		existing:Destroy()
		highlights[player] = nil
	end
end

local function refreshCarriers()
	local best: { [number]: { rarity: Rarities.Rarity, stolen: boolean, stolenFromMe: boolean } } = {}
	for _, record in RelicRenderer.records do
		if record.state == "Carried" and record.vanishStart == nil then
			local carrierId = record.anchor:GetAttribute("CarrierId")
			local stolenFrom = record.anchor:GetAttribute("StolenFrom")
			if type(carrierId) == "number" and carrierId ~= 0 then
				local entry = best[carrierId]
				local isStolen = type(stolenFrom) == "number" and stolenFrom ~= 0
				if not entry or record.rarity.order > entry.rarity.order then
					best[carrierId] = {
						rarity = record.rarity,
						stolen = isStolen or (entry ~= nil and entry.stolen),
						stolenFromMe = (isStolen and stolenFrom == localPlayer.UserId) or (entry ~= nil and entry.stolenFromMe),
					}
				elseif isStolen then
					entry.stolen = true
					entry.stolenFromMe = entry.stolenFromMe or stolenFrom == localPlayer.UserId
				end
			end
		end
	end

	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local info = best[player.UserId]
		local model = player.Character
		local head = model and model:FindFirstChild("Head")
		if info and head and head:IsA("BasePart") then
			local marker = ensureMarker(player, head)
			local rarity = info.rarity
			marker.label.Text = CharacterFX.markerText(rarity.id)
			marker.label.TextColor3 = Style.Colors.Text
			marker.chip.BackgroundColor3 = rarity.color
			marker.stolen.Text = if info.stolen then Emoji.label("alarm", Locale.t("tag.stolen")) else ""
			marker.gui.AlwaysOnTop = rarity.order >= 5 or info.stolenFromMe
			marker.gui.Enabled = player ~= localPlayer or info.stolen
		else
			removeMarker(player)
		end
		local chasing = info ~= nil and info.stolenFromMe
		setHighlight(player, chasing or (stealHighlightUntil[player] or 0) > now)
	end
end

-- Same carry marker (and red chase outline for the victim) on a decoy copy,
-- so a decoy reads exactly like the real carrier. Returns what to destroy.
function CharacterFX.decoyMarker(model: Model, head: BasePart, rarityId: string, stolenFrom: number): { Instance }
	local rarity = Rarities.get(rarityId)
	local created: { Instance } = {}
	local gui: BillboardGui = Create("BillboardGui", {
		Name = "DecoyMarker",
		Size = UDim2.fromOffset(160, 48),
		StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0),
		LightInfluence = 0,
		MaxDistance = 400,
		ResetOnSpawn = false,
		AlwaysOnTop = rarity.order >= 5 or stolenFrom == localPlayer.UserId,
		Adornee = head,
		Parent = fxFolder,
	})
	table.insert(created, gui)
	-- Must look exactly like the real carry marker (ensureMarker + update).
	local chip: Frame = Create("Frame", {
		Size = UDim2.fromOffset(136, 24),
		Position = UDim2.new(0.5, 0, 0, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = rarity.color,
		Parent = gui,
	})
	Style.corner(chip, UDim.new(1, 0))
	Style.stroke(chip, Style.Colors.Ink, 0, 2)
	local label = Style.text({
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		FontFace = Style.Fonts.Heavy,
		TextSize = 13,
		Text = CharacterFX.markerText(rarity.id),
		TextColor3 = Style.Colors.Text,
		Parent = chip,
	})
	Style.ink(label, 1.5)
	if stolenFrom ~= 0 then
		local stolen = Style.text({
			Size = UDim2.new(1, 0, 0, 20),
			Position = UDim2.fromOffset(0, 26),
			TextXAlignment = Enum.TextXAlignment.Center,
			FontFace = Style.Fonts.Display,
			TextSize = 16,
			TextColor3 = Style.Colors.Danger,
			Text = Emoji.label("alarm", Locale.t("tag.stolen")),
			Parent = gui,
		})
		Style.ink(stolen, 2)
	end
	if stolenFrom == localPlayer.UserId then
		table.insert(created, Create("Highlight", {
			FillColor = Style.Colors.Danger,
			FillTransparency = 0.75,
			OutlineColor = Style.Colors.Danger,
			OutlineTransparency = 0,
			DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
			Adornee = model,
			Parent = worldFolder,
		}))
	end
	return created
end

----------------------------------------------------------------------------
-- One-shot FX
----------------------------------------------------------------------------

function CharacterFX.stealAttempt(thiefId: number, duration: number)
	local player = Players:GetPlayerByUserId(thiefId)
	if player then
		stealHighlightUntil[player] = os.clock() + duration + 0.2
		setHighlight(player, true)
	end
end

function CharacterFX.stealEnded(thiefId: number)
	local player = Players:GetPlayerByUserId(thiefId)
	if player then
		stealHighlightUntil[player] = nil
	end
end

function CharacterFX.dash(userId: number)
	local model, root = character(userId)
	if not model or not root then
		return
	end
	local top = Create("Attachment", { Position = Vector3.new(0, 1.4, 0), Parent = root })
	local bottom = Create("Attachment", { Position = Vector3.new(0, -1.6, 0), Parent = root })
	local trail: Trail = Create("Trail", {
		Attachment0 = top,
		Attachment1 = bottom,
		Lifetime = 0.28,
		Color = ColorSequence.new(Color3.fromRGB(170, 240, 255), Color3.fromRGB(170, 120, 255)),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}),
		LightEmission = 1,
		LightInfluence = 0,
		FaceCamera = true,
		Parent = root,
	})
	if userId ~= localPlayer.UserId then
		Audio.playAt("Dash", root.Position)
	end
	task.delay(0.6, function()
		trail:Destroy()
		top:Destroy()
		bottom:Destroy()
	end)
end

function CharacterFX.pulse(position: Vector3, userId: number)
	local radius = GameConfig.Abilities.Pulse.Radius
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.4, 2, 2)
	ring.CFrame = CFrame.new(position - Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(150, 230, 255)
	ring.Transparency = 0.1
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Parent = worldFolder
	Tween.play(ring, 0.45, { Size = Vector3.new(0.1, radius * 2.1, radius * 2.1), Transparency = 1 }, Enum.EasingStyle.Quart)
	local dome = Instance.new("Part")
	dome.Shape = Enum.PartType.Ball
	dome.Size = Vector3.one * 3
	dome.CFrame = CFrame.new(position)
	dome.Material = Enum.Material.ForceField
	dome.Color = Color3.fromRGB(140, 210, 255)
	dome.Anchored = true
	dome.CanCollide = false
	dome.CanQuery = false
	dome.CanTouch = false
	dome.CastShadow = false
	dome.Parent = worldFolder
	Tween.play(dome, 0.4, { Size = Vector3.one * radius * 2, Transparency = 1 }, Enum.EasingStyle.Quart)
	task.delay(0.6, function()
		ring:Destroy()
		dome:Destroy()
	end)
	if userId == localPlayer.UserId then
		Audio.play("Pulse")
	else
		Audio.playAt("Pulse", position)
	end
	CameraFX.shakeAt(position, 0.25, 40)
end

function CharacterFX.hit(userId: number)
	local model, root = character(userId)
	if not model or not root then
		return
	end
	RelicRenderer.burst(root.Position, Color3.fromRGB(255, 240, 200), 5, nil)
	if userId == localPlayer.UserId then
		Audio.play("Hit")
	else
		Audio.playAt("Hit", root.Position)
	end
	local head = model:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local gui: BillboardGui = Create("BillboardGui", {
		Size = UDim2.fromOffset(80, 40),
		StudsOffsetWorldSpace = Vector3.new(0, 1.8, 0),
		LightInfluence = 0,
		ResetOnSpawn = false,
		Adornee = head,
		Parent = fxFolder,
	})
	-- Cartoon "BONK!" + dizzy stars circling the head.
	RelicRenderer.popText(head.Position + Vector3.new(0, 2.5, 0), Locale.t("fx.bonk"), Style.Colors.Gold)
	local stars = {}
	for _ = 1, 3 do
		local star = Style.text({
			Size = UDim2.fromOffset(24, 24),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Text = "★",
			TextSize = 22,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = Style.Colors.Gold,
			Parent = gui,
		})
		Style.ink(star, 2)
		table.insert(stars, star)
	end
	local start = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		if t > GameConfig.Abilities.Pulse.Stun + 0.4 then
			connection:Disconnect()
			gui:Destroy()
			return
		end
		for i, star in stars do
			local a = t * 8 + i * (math.pi * 2 / 3)
			star.Position = UDim2.new(0.5, math.cos(a) * 26, 0.5, math.sin(a) * 8)
		end
	end)
end

function CharacterFX.init()
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "CharacterFX"
	fxFolder.Parent = localPlayer:WaitForChild("PlayerGui")
	worldFolder = Instance.new("Folder")
	worldFolder.Name = "CharacterFXWorld"
	worldFolder.Parent = workspace

	Players.PlayerRemoving:Connect(function(player)
		removeMarker(player)
		setHighlight(player, false)
		stealHighlightUntil[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(0.2)
			refreshCarriers()
		end
	end)
end

return CharacterFX
