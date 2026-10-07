--!strict
-- Client visuals for the V2 abilities (everything here is display only; the
-- server already decided every outcome):
--   * Blink wind-up and arrival, grapple cables, Frost Wave rings, Eruption
--     telegraphs, storm trails, slow sparks;
--   * rune traps (server parts in workspace.Abilities) get a rotating rune and
--     an "armed" glow;
--   * Shield bubbles and Spectral Phase ghosts from the ShieldUntil /
--     PhaseUntil character attributes (the carried relic is drawn by
--     RelicRenderer and stays fully visible);
--   * decoys: a copy of the owner's avatar runs along the server path with a
--     copy of the carried relic and carry marker; revealed (Cosmic Eye) decoys
--     and phasing players get a violet outline and a label.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Locale = require(Shared.Locale)
local Factory = require(Shared.Relics.RelicFactory)

local Kit = script.Parent.Parent.UI.Kit
local Create = require(Kit.Create)
local Style = require(Kit.Style)
local Tween = require(Kit.Tween)

local ClientNet = require(script.Parent.Parent.ClientNet)
local Audio = require(script.Parent.Audio)
local CameraFX = require(script.Parent.CameraFX)
local CharacterFX = require(script.Parent.CharacterFX)
local RelicRenderer = require(script.Parent.RelicRenderer)
local Settings = require(script.Parent.Settings)

local AbilityFX = {}

local localPlayer = Players.LocalPlayer
local folder: Folder
local guiFolder: Folder

local COLORS = {
	Blink = Color3.fromRGB(170, 120, 255),
	Grapple = Color3.fromRGB(110, 235, 255),
	Frost = Color3.fromRGB(150, 220, 255),
	Magma = Color3.fromRGB(255, 120, 60),
	Trap = Color3.fromRGB(205, 130, 255),
	Shield = Color3.fromRGB(255, 215, 120),
	Phase = Color3.fromRGB(120, 255, 220),
	Storm = Color3.fromRGB(150, 200, 255),
	Reveal = Color3.fromRGB(200, 120, 255),
}

local function characterOf(userId: number): (Model?, BasePart?)
	local player = Players:GetPlayerByUserId(userId)
	local model = player and player.Character
	local root = model and model:FindFirstChild("HumanoidRootPart")
	if model and root and root:IsA("BasePart") then
		return model, root
	end
	return nil, nil
end

local function fxPart(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	for key, value in props do
		(part :: any)[key] = value
	end
	part.Parent = folder
	return part
end

-- Flat ring on the ground growing to `radius`.
local function groundRing(position: Vector3, radius: number, color: Color3, time: number, startTransparency: number?)
	local ring = fxPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 2, 2),
		CFrame = CFrame.new(position - Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = color,
		Transparency = startTransparency or 0.15,
	})
	Tween.play(ring, time, { Size = Vector3.new(0.1, radius * 2, radius * 2), Transparency = 1 }, Enum.EasingStyle.Quart)
	task.delay(time + 0.1, function()
		ring:Destroy()
	end)
end

local function playAt(key: string, position: Vector3, userId: number)
	if userId == localPlayer.UserId then
		Audio.play(key)
	else
		Audio.playAt(key, position)
	end
end

----------------------------------------------------------------------------
-- Blink
----------------------------------------------------------------------------

function AbilityFX.blinkWindup(userId: number, duration: number)
	local _, root = characterOf(userId)
	if not root then
		return
	end
	local orb = fxPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * 7, CFrame = root.CFrame, Color = COLORS.Blink, Transparency = 0.75, Material = Enum.Material.ForceField })
	Tween.play(orb, duration, { Size = Vector3.one * 2.5, Transparency = 0.2 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local start = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		if os.clock() - start > duration + 0.05 or not root.Parent then
			connection:Disconnect()
			orb:Destroy()
			return
		end
		orb.CFrame = root.CFrame
	end)
	playAt("BlinkCharge", root.Position, userId)
end

function AbilityFX.blink(userId: number, from: Vector3, to: Vector3)
	RelicRenderer.burst(from, COLORS.Blink, 6, nil)
	RelicRenderer.burst(to, COLORS.Blink, 7, nil)
	local length = (to - from).Magnitude
	if length > 0.5 then
		local beam = fxPart({ Size = Vector3.new(0.35, 0.35, length), CFrame = CFrame.lookAt((from + to) / 2, to), Color = COLORS.Blink, Transparency = 0.2 })
		Tween.play(beam, 0.35, { Size = Vector3.new(0.05, 0.05, length), Transparency = 1 })
		task.delay(0.4, function()
			beam:Destroy()
		end)
	end
	playAt("Blink", to, userId)
	if userId == localPlayer.UserId then
		CameraFX.punch(8)
	end
end

----------------------------------------------------------------------------
-- Grapple cables
----------------------------------------------------------------------------

type Cable = { beam: Beam, anchorPart: Part, attachment: Attachment, untilTime: number }
local cables: { [number]: Cable } = {}

function AbilityFX.cutCable(userId: number)
	local cable = cables[userId]
	if cable then
		cables[userId] = nil
		cable.beam:Destroy()
		cable.attachment:Destroy()
		cable.anchorPart:Destroy()
	end
end

-- Draws (or refreshes) the cable from `userId` to `position` until `untilTime` (os.clock).
function AbilityFX.cable(userId: number, position: Vector3, untilTime: number)
	local _, root = characterOf(userId)
	if not root then
		return
	end
	AbilityFX.cutCable(userId)
	local anchorPart = fxPart({ Size = Vector3.one * 0.6, CFrame = CFrame.new(position), Color = COLORS.Grapple, Shape = Enum.PartType.Ball })
	local a1 = Create("Attachment", { Parent = anchorPart })
	local a0: Attachment = Create("Attachment", { Position = Vector3.new(0.6, 0.6, 0), Parent = root })
	local beam: Beam = Create("Beam", {
		Attachment0 = a0,
		Attachment1 = a1,
		Width0 = 0.35,
		Width1 = 0.2,
		Color = ColorSequence.new(COLORS.Grapple),
		LightEmission = 1,
		LightInfluence = 0,
		FaceCamera = true,
		Segments = 2,
		Parent = anchorPart,
	})
	cables[userId] = { beam = beam, anchorPart = anchorPart, attachment = a0, untilTime = untilTime }
	playAt("Grapple", root.Position, userId)
end

----------------------------------------------------------------------------
-- Control
----------------------------------------------------------------------------

function AbilityFX.frostWave(userId: number, position: Vector3, radius: number)
	groundRing(position, radius, COLORS.Frost, 0.5)
	local dome = fxPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * 3, CFrame = CFrame.new(position), Color = COLORS.Frost, Material = Enum.Material.Ice, Transparency = 0.5 })
	Tween.play(dome, 0.45, { Size = Vector3.one * radius * 2, Transparency = 1 }, Enum.EasingStyle.Quart)
	task.delay(0.55, function()
		dome:Destroy()
	end)
	playAt("FrostWave", position, userId)
	CameraFX.shakeAt(position, 0.12, 30)
end

type Telegraph = { part: Part, untilTime: number }
local telegraphs: { [number]: Telegraph } = {}

function AbilityFX.eruptionWindup(userId: number, position: Vector3, radius: number, duration: number)
	local existing = telegraphs[userId]
	if existing then
		existing.part:Destroy()
	end
	local disc = fxPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.25, radius * 2, radius * 2),
		CFrame = CFrame.new(position - Vector3.new(0, 2.7, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = COLORS.Magma,
		Transparency = 0.75,
	})
	Tween.play(disc, duration, { Transparency = 0.25 }, Enum.EasingStyle.Linear)
	telegraphs[userId] = { part = disc, untilTime = os.clock() + duration + 0.3 }
	playAt("EruptionCharge", position, userId)
end

function AbilityFX.endEruption(userId: number)
	local existing = telegraphs[userId]
	if existing then
		telegraphs[userId] = nil
		existing.part:Destroy()
	end
end

function AbilityFX.eruption(userId: number, position: Vector3, radius: number)
	AbilityFX.endEruption(userId)
	groundRing(position, radius, COLORS.Magma, 0.5, 0)
	RelicRenderer.burst(position, COLORS.Magma, radius, nil)
	playAt("Eruption", position, userId)
	CameraFX.shakeAt(position, 0.45, 50)
end

function AbilityFX.slowed(userId: number, kind: string)
	local _, root = characterOf(userId)
	if not root then
		return
	end
	local color = if kind == "frost" then COLORS.Frost elseif kind == "trap" then COLORS.Trap else COLORS.Storm
	RelicRenderer.burst(root.Position - Vector3.new(0, 2, 0), color, 4, nil)
end

-- Storm trail (Storm Crystal): a crackling line on the ground.
function AbilityFX.stormTrail(from: Vector3, to: Vector3, duration: number)
	local length = (to - from).Magnitude
	if length < 0.5 then
		return
	end
	local mid = (from + to) / 2 - Vector3.new(0, 2.6, 0)
	local line = fxPart({ Size = Vector3.new(1.6, 0.2, length), CFrame = CFrame.lookAt(mid, to - Vector3.new(0, 2.6, 0)), Color = COLORS.Storm, Transparency = 0.2 })
	Tween.play(line, duration, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(duration + 0.1, function()
		line:Destroy()
	end)
end

----------------------------------------------------------------------------
-- Rune traps (server parts)
----------------------------------------------------------------------------

local function decorateTrap(part: BasePart)
	if not part:IsA("BasePart") or part.Name ~= "RuneTrap" or part:FindFirstChild("Rune") then
		return
	end
	local gui: BillboardGui = Create("BillboardGui", {
		Name = "Rune",
		Size = UDim2.fromOffset(46, 46),
		StudsOffsetWorldSpace = Vector3.new(0, 1.6, 0),
		LightInfluence = 0,
		MaxDistance = 90,
		Adornee = part,
		Parent = part,
	})
	local glyph = Style.text({
		Size = UDim2.fromScale(1, 1),
		Text = "ᛟ",
		TextSize = 34,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = COLORS.Trap,
		Parent = gui,
	})
	Style.textStroke(glyph, 0.2, 2)
	local function refresh()
		local armed = part:GetAttribute("Armed") == true
		glyph.TextTransparency = if armed then 0 else 0.5
	end
	refresh()
	part:GetAttributeChangedSignal("Armed"):Connect(refresh)
end

function AbilityFX.trapTriggered(position: Vector3, userId: number)
	RelicRenderer.burst(position + Vector3.new(0, 0.5, 0), COLORS.Trap, 10, nil)
	playAt("TrapTrigger", position, userId)
end

----------------------------------------------------------------------------
-- Shield bubbles and phase ghosts (character attributes)
----------------------------------------------------------------------------

type Ghost = { highlight: Highlight, label: BillboardGui?, model: Model }
local bubbles: { [Player]: Part } = {}
local ghosts: { [Player]: Ghost } = {}
-- userId -> phase end (server time) revealed to us by the Cosmic Eye.
local revealedPhase: { [number]: number } = {}

local function attrTime(model: Model, name: string): number
	local value = model:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

local function setGhostParts(model: Model, value: number)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			d.LocalTransparencyModifier = value
		end
	end
end

local function clearGhost(player: Player)
	local ghost = ghosts[player]
	if ghost then
		ghosts[player] = nil
		ghost.highlight:Destroy()
		if ghost.label then
			ghost.label:Destroy()
		end
		if ghost.model.Parent then
			setGhostParts(ghost.model, 0)
		end
	end
end

local function refreshBuffs()
	local serverNow = workspace:GetServerTimeNow()
	for _, player in Players:GetPlayers() do
		local model = player.Character
		local root = model and model:FindFirstChild("HumanoidRootPart")
		if not model or not root or not root:IsA("BasePart") then
			local bubble = bubbles[player]
			if bubble then
				bubble:Destroy()
				bubbles[player] = nil
			end
			clearGhost(player)
			continue
		end
		-- Shield.
		local shielded = attrTime(model, "ShieldUntil") > serverNow
		local bubble = bubbles[player]
		if shielded then
			if not bubble then
				bubble = fxPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * 7.5, Color = COLORS.Shield, Material = Enum.Material.ForceField, Transparency = 0.1 })
				bubbles[player] = bubble
				playAt("Shield", root.Position, player.UserId)
			end
			(bubble :: Part).CFrame = root.CFrame
		elseif bubble then
			bubble:Destroy()
			bubbles[player] = nil
		end
		-- Spectral Phase.
		local phased = attrTime(model, "PhaseUntil") > serverNow
		local ghost = ghosts[player]
		if phased then
			if not ghost or ghost.model ~= model then
				clearGhost(player)
				local created: Ghost = {
					model = model,
					label = nil,
					highlight = Create("Highlight", {
						FillColor = COLORS.Phase,
						FillTransparency = 0.6,
						OutlineColor = COLORS.Phase,
						OutlineTransparency = 0.1,
						DepthMode = Enum.HighlightDepthMode.Occluded,
						Adornee = model,
						Parent = folder,
					}),
				}
				ghost = created
				ghosts[player] = created
				playAt("Phase", root.Position, player.UserId)
			end
			local current = ghost :: Ghost
			setGhostParts(model, 0.55)
			local revealed = (revealedPhase[player.UserId] or 0) > serverNow
			current.highlight.DepthMode = if revealed then Enum.HighlightDepthMode.AlwaysOnTop else Enum.HighlightDepthMode.Occluded
			current.highlight.OutlineColor = if revealed then COLORS.Reveal else COLORS.Phase
			if revealed and not current.label then
				local head = model:FindFirstChild("Head")
				if head and head:IsA("BasePart") then
					local gui: BillboardGui = Create("BillboardGui", {
						Size = UDim2.fromOffset(140, 24),
						StudsOffsetWorldSpace = Vector3.new(0, 4.4, 0),
						AlwaysOnTop = true,
						LightInfluence = 0,
						Adornee = head,
						Parent = guiFolder,
					})
					local text = Style.text({ Size = UDim2.fromScale(1, 1), Text = "👁 " .. Locale.t("fx.revealed"), TextSize = 15, FontFace = Style.Fonts.Heavy, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = COLORS.Reveal, Parent = gui })
					Style.textStroke(text, 0.2, 2)
					current.label = gui
				end
			end
		else
			clearGhost(player)
		end
	end
end

----------------------------------------------------------------------------
-- Decoys
----------------------------------------------------------------------------

type DecoyView = {
	id: number,
	model: Model?,
	extras: { Instance },
	relics: { Factory.Visual },
	origin: Vector3,
	direction: Vector3,
	length: number,
	speed: number,
	startAt: number,
	endAt: number,
	revealed: boolean,
	label: BillboardGui?,
	highlight: Highlight?,
}
local decoys: { [number]: DecoyView } = {}
local pendingReveal: { [number]: boolean } = {}

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
rayParams.RespectCanCollide = true

local function refreshRayFilter()
	local filter: { Instance } = { folder }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(filter, player.Character)
		end
	end
	for _, view in decoys do
		if view.model then
			table.insert(filter, view.model)
		end
	end
	for _, name in { "Relics", "Abilities", "CharacterFXWorld" } do
		local found = workspace:FindFirstChild(name)
		if found then
			table.insert(filter, found)
		end
	end
	rayParams.FilterDescendantsInstances = filter
end

-- Copy of the owner's avatar: no scripts, nothing that collides or can be touched.
local function copyAvatar(userId: number): Model?
	local source = characterOf(userId)
	if not source then
		return nil
	end
	local ok, clone = pcall(function()
		local was = source.Archivable
		source.Archivable = true
		local copy = source:Clone()
		source.Archivable = was
		return copy
	end)
	if not ok or not clone then
		return nil
	end
	local model = clone :: Model
	for _, d in model:GetDescendants() do
		if d:IsA("BaseScript") or d:IsA("ModuleScript") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	model.Parent = folder
	-- Running animation, taken from the owner's own Animate script (no asset id here).
	pcall(function()
		local animate = source:FindFirstChild("Animate")
		local run = animate and animate:FindFirstChild("run")
		local anim = run and run:FindFirstChildOfClass("Animation")
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		if anim and animator then
			local track = animator:LoadAnimation(anim)
			track.Looped = true
			track:Play()
		end
	end)
	return model
end

local function markRevealed(view: DecoyView)
	if view.revealed or not view.model then
		return
	end
	view.revealed = true
	local model = view.model :: Model
	view.highlight = Create("Highlight", {
		FillColor = COLORS.Reveal,
		FillTransparency = 0.5,
		OutlineColor = COLORS.Reveal,
		OutlineTransparency = 0,
		DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
		Adornee = model,
		Parent = folder,
	})
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local gui: BillboardGui = Create("BillboardGui", {
			Size = UDim2.fromOffset(140, 24),
			StudsOffsetWorldSpace = Vector3.new(0, 5.2, 0),
			AlwaysOnTop = true,
			LightInfluence = 0,
			Adornee = head,
			Parent = guiFolder,
		})
		local text = Style.text({ Size = UDim2.fromScale(1, 1), Text = "👁 " .. Locale.t("fx.decoy"), TextSize = 15, FontFace = Style.Fonts.Heavy, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = COLORS.Reveal, Parent = gui })
		Style.textStroke(text, 0.2, 2)
		view.label = gui
	end
end

function AbilityFX.spawnDecoy(payload: { [string]: any })
	local id = payload.id
	if type(id) ~= "number" or decoys[id] then
		return
	end
	local view: DecoyView = {
		id = id,
		model = copyAvatar(payload.userId),
		extras = {},
		relics = {},
		origin = payload.origin,
		direction = payload.direction,
		length = payload.length,
		speed = payload.speed,
		startAt = payload.startAt,
		endAt = payload.endAt,
		revealed = false,
		label = nil,
		highlight = nil,
	}
	decoys[id] = view
	local model = view.model
	local head = model and model:FindFirstChild("Head")
	if model and head and head:IsA("BasePart") and type(payload.relics) == "table" then
		local best = payload.relics[1]
		for _, relic in payload.relics do
			local visual = Factory.build(relic.id, if relic.mutation == "" then nil else relic.mutation, { particleScale = Settings.particleScale() })
			if visual then
				visual.model.Parent = folder
				table.insert(view.relics, visual)
			end
		end
		if best then
			for _, instance in CharacterFX.decoyMarker(model, head, best.rarity, best.stolenFrom or 0) do
				table.insert(view.extras, instance)
			end
		end
	end
	refreshRayFilter()
	if pendingReveal[id] then
		pendingReveal[id] = nil
		markRevealed(view)
	end
end

function AbilityFX.endDecoy(id: number, how: string, position: Vector3?)
	local view = decoys[id]
	if not view then
		return
	end
	decoys[id] = nil
	if view.model then
		view.model:Destroy()
	end
	for _, visual in view.relics do
		Factory.destroy(visual)
	end
	for _, instance in view.extras do
		instance:Destroy()
	end
	if view.label then
		view.label:Destroy()
	end
	if view.highlight then
		view.highlight:Destroy()
	end
	if position then
		RelicRenderer.burst(position, if how == "popped" then COLORS.Reveal else Color3.fromRGB(230, 230, 240), 6, nil)
		if how == "popped" then
			Audio.playAt("DecoyPop", position)
		end
	end
	refreshRayFilter()
end

local function stepDecoys()
	local serverNow = workspace:GetServerTimeNow()
	for _, view in decoys do
		local travelled = math.clamp((serverNow - view.startAt) * view.speed, 0, view.length)
		local flat = view.origin + view.direction * travelled
		local y = flat.Y
		local hit = workspace:Raycast(flat + Vector3.new(0, 3, 0), Vector3.new(0, -10, 0), rayParams)
		if hit then
			y = hit.Position.Y + 3
		end
		local at = Vector3.new(flat.X, y, flat.Z)
		local cf = CFrame.lookAt(at, at + view.direction)
		if view.model then
			view.model:PivotTo(cf)
		end
		for i, visual in view.relics do
			visual.model:PivotTo(CFrame.new(at + Vector3.new(0, 4 + (i - 1) * 1.6, 0)))
		end
	end
end

----------------------------------------------------------------------------
-- Init
----------------------------------------------------------------------------

function AbilityFX.init()
	folder = Instance.new("Folder")
	folder.Name = "AbilityFX"
	folder.Parent = workspace
	guiFolder = Instance.new("Folder")
	guiFolder.Name = "AbilityFX"
	guiFolder.Parent = localPlayer:WaitForChild("PlayerGui")

	ClientNet.on("BlinkWindup", function(payload)
		if payload.userId == localPlayer.UserId then
			return -- already predicted locally
		end
		AbilityFX.blinkWindup(payload.userId, math.max(0.05, (payload.at or 0) - workspace:GetServerTimeNow()))
	end)
	ClientNet.on("Blink", function(payload)
		AbilityFX.blink(payload.userId, payload.from, payload.to)
	end)
	ClientNet.on("BlinkFail", function(payload)
		local _, root = characterOf(payload.userId)
		if root then
			RelicRenderer.burst(root.Position, Color3.fromRGB(150, 140, 170), 3, nil)
		end
	end)
	ClientNet.on("Grapple", function(payload)
		if payload.userId == localPlayer.UserId then
			return -- already predicted locally
		end
		AbilityFX.cable(payload.userId, payload.position, os.clock() + math.max(0, (payload.untilTime or 0) - workspace:GetServerTimeNow()))
	end)
	ClientNet.on("GrappleEnd", function(payload)
		AbilityFX.cutCable(payload.userId)
	end)
	ClientNet.on("FrostWave", function(payload)
		if payload.userId == localPlayer.UserId then
			return -- already predicted locally
		end
		AbilityFX.frostWave(payload.userId, payload.position, payload.radius)
	end)
	ClientNet.on("EruptionWindup", function(payload)
		if payload.userId == localPlayer.UserId then
			return -- already predicted locally
		end
		AbilityFX.eruptionWindup(payload.userId, payload.position, payload.radius, math.max(0.05, (payload.at or 0) - workspace:GetServerTimeNow()))
	end)
	ClientNet.on("Eruption", function(payload)
		AbilityFX.eruption(payload.userId, payload.position, payload.radius)
	end)
	ClientNet.on("EruptionCancel", function(payload)
		AbilityFX.endEruption(payload.userId)
	end)
	ClientNet.on("Slowed", function(payload)
		AbilityFX.slowed(payload.userId, payload.kind)
	end)
	ClientNet.on("StormTrail", function(payload)
		AbilityFX.stormTrail(payload.from, payload.to, math.max(0.1, (payload.untilTime or 0) - workspace:GetServerTimeNow()))
	end)
	ClientNet.on("TrapPlaced", function(payload)
		playAt("TrapPlace", payload.position, payload.userId)
	end)
	ClientNet.on("TrapTriggered", function(payload)
		AbilityFX.trapTriggered(payload.position, payload.userId)
	end)
	ClientNet.on("Decoy", function(payload)
		AbilityFX.spawnDecoy(payload)
		playAt("Decoy", payload.origin, payload.userId)
	end)
	ClientNet.on("DecoyEnd", function(payload)
		AbilityFX.endDecoy(payload.id, payload.how, payload.position)
	end)
	ClientNet.on("Reveal", function(payload)
		if type(payload.decoy) == "number" then
			local view = decoys[payload.decoy]
			if view then
				markRevealed(view)
			else
				pendingReveal[payload.decoy] = true
			end
		elseif type(payload.userId) == "number" then
			revealedPhase[payload.userId] = payload.untilTime or 0
		end
	end)

	local abilities = workspace:FindFirstChild("Abilities")
	local function watch(container: Instance)
		for _, child in container:GetChildren() do
			decorateTrap(child :: any)
		end
		container.ChildAdded:Connect(function(child)
			decorateTrap(child :: any)
		end)
	end
	if abilities then
		watch(abilities)
	else
		workspace.ChildAdded:Connect(function(child)
			if child.Name == "Abilities" then
				watch(child)
			end
		end)
	end

	Players.PlayerRemoving:Connect(function(player)
		AbilityFX.cutCable(player.UserId)
		AbilityFX.endEruption(player.UserId)
		local bubble = bubbles[player]
		if bubble then
			bubble:Destroy()
			bubbles[player] = nil
		end
		clearGhost(player)
	end)

	local buffTimer = 0
	RunService.RenderStepped:Connect(function(dt)
		local now = os.clock()
		for userId, cable in cables do
			if now > cable.untilTime then
				AbilityFX.cutCable(userId)
			end
		end
		for userId, telegraph in telegraphs do
			if now > telegraph.untilTime then
				AbilityFX.endEruption(userId)
			end
		end
		stepDecoys()
		buffTimer += dt
		if buffTimer >= 0.05 then
			buffTimer = 0
			refreshBuffs()
		end
	end)
end

-- Tests / debug.
function AbilityFX.debugCounts(): { [string]: number }
	local n = function(t: { [any]: any }): number
		local count = 0
		for _ in t do
			count += 1
		end
		return count
	end
	return { cables = n(cables), decoys = n(decoys), bubbles = n(bubbles), ghosts = n(ghosts), telegraphs = n(telegraphs) }
end

return AbilityFX
