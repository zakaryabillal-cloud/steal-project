--!strict
-- Renders every relic entity locally from its server anchor's attributes.
--   * idle hover + spin + bespoke animators (RelicFactory)
--   * follows carriers smoothly, stacked above their heads
--   * flight arcs for emerge / deposit / fuse / drop / return moments
--   * vanish animations, name labels, through-wall outlines for big relics
--   * distance LOD (animator cadence, particles, lights)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Factory = require(Shared.Relics.RelicFactory)
local Rarities = require(Shared.Config.Rarities)
local Mutations = require(Shared.Config.Mutations)
local GameConfig = require(Shared.Config.GameConfig)
local Layout = require(Shared.Layout)
local Locale = require(Shared.Locale)
local Format = require(Shared.Util.Format)
local Economy = require(Shared.Economy)
local MathUtil = require(Shared.Util.MathUtil)
local Signal = require(Shared.Util.Signal)

local Kit = script.Parent.Parent.UI.Kit
local Create = require(Kit.Create)
local Style = require(Kit.Style)
local Tween = require(Kit.Tween)

local Settings = require(script.Parent.Settings)
local Audio = require(script.Parent.Audio)
local Store = require(script.Parent.Store)

local RelicRenderer = {}

type Flight = {
	from: Vector3,
	height: number,
	start: number,
	duration: number,
	target: () -> Vector3,
	onLand: (() -> ())?,
}

export type Record = {
	uid: string,
	anchor: BasePart,
	relicId: string,
	rarity: Rarities.Rarity,
	mutation: string?,
	visual: Factory.Visual,
	state: string,
	level: number,
	position: Vector3,
	yaw: number,
	phase: number,
	detail: number,
	frame: number,
	flight: Flight?,
	vanishStart: number?,
	vanishReason: string?,
	awaitingFuse: boolean,
	label: BillboardGui?,
	labelText: TextLabel?,
	labelSub: TextLabel?,
	highlight: Highlight?,
	stealRing: BillboardGui?,
	focus: Vector3?,
	focusAt: number,
	bump: number,
	connections: { RBXScriptConnection },
}

local records: { [string]: Record } = {}
local container: Folder
local localPlayer = Players.LocalPlayer
local clock = 0

RelicRenderer.records = records
-- Fired when the local player's carried relic list may have changed visually.
RelicRenderer.recordAdded = Signal.new()

local function attrNumber(instance: Instance, name: string): number
	local value = instance:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

local function attrString(instance: Instance, name: string): string
	local value = instance:GetAttribute(name)
	return if type(value) == "string" then value else ""
end

local function carrierRoot(record: Record): BasePart?
	local carrierId = attrNumber(record.anchor, "CarrierId")
	if carrierId == 0 then
		return nil
	end
	local player = Players:GetPlayerByUserId(carrierId)
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Index of this relic among everything its carrier holds (for stacking).
local function carrySlot(record: Record): (number, number)
	local carrierId = attrNumber(record.anchor, "CarrierId")
	local index, total = 1, 0
	local uids = {}
	for uid, other in records do
		if other.state == "Carried" and attrNumber(other.anchor, "CarrierId") == carrierId and other.vanishStart == nil then
			table.insert(uids, uid)
		end
	end
	table.sort(uids)
	total = #uids
	index = table.find(uids, record.uid) or 1
	return index, math.max(total, 1)
end

local function targetPosition(record: Record): Vector3
	if record.state == "Carried" then
		local root = carrierRoot(record)
		if root then
			local index, total = carrySlot(record)
			local lateral = (index - (total + 1) / 2) * 2.8
			local lift = 4.4 + (record.visual.scale - 1) * 1.8
			return (root.CFrame * CFrame.new(lateral, lift, 1.4)).Position
		end
	end
	return record.anchor.Position
end

----------------------------------------------------------------------------
-- Labels & outlines
----------------------------------------------------------------------------

local function labelTitle(record: Record): string
	local rarity = record.rarity
	local title = Locale.relicTitle(record.relicId, record.mutation)
	local mutation = Mutations.get(record.mutation)
	if mutation then
		return Style.colored(title, mutation.color:Lerp(rarity.color, 0.3))
	end
	return Style.colored(title, rarity.color)
end

local function labelSubtitle(record: Record): string
	local rarityName = Locale.rarity(record.rarity.id)
	if record.state == "Placed" then
		local rate = Economy.relicBaseRate(record.relicId, record.level, record.mutation)
		if attrNumber(record.anchor, "OwnerId") == localPlayer.UserId then
			rate *= Store.state.multiplier
		end
		return string.format("%s  ·  %s  ·  +%s/s", string.upper(rarityName), Format.stars(record.level, GameConfig.Economy.MaxRelicLevel), Format.abbrev(rate))
	end
	return Style.stars(record.rarity.id) .. " " .. string.upper(rarityName)
end

local function ensureLabel(record: Record)
	if record.label then
		return
	end
	local gui: BillboardGui = Create("BillboardGui", {
		Name = "RelicLabel",
		Size = UDim2.fromOffset(260, 60),
		StudsOffsetWorldSpace = Vector3.new(0, 2.4 * record.visual.scale + 0.6, 0),
		AlwaysOnTop = false,
		LightInfluence = 0,
		MaxDistance = 140,
		Adornee = record.visual.root,
		Parent = record.visual.model,
	})
	local title = Style.text({
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Center,
		FontFace = Style.Fonts.Display,
		TextSize = 22,
		Text = labelTitle(record),
		Parent = gui,
	})
	Style.ink(title, 3)
	-- Rarity pill: colour + stars, readable from afar and without colour.
	local pill = Create("Frame", {
		Name = "RarityPill",
		Size = UDim2.fromOffset(40, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.new(0.5, 0, 0, 31),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = record.rarity.color,
		Parent = gui,
	})
	Style.corner(pill, UDim.new(1, 0))
	Style.stroke(pill, Style.Colors.Ink, 0, 2)
	Style.padding(pill, 0, 8)
	local sub = Style.text({
		Name = "Sub",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		TextXAlignment = Enum.TextXAlignment.Center,
		FontFace = Style.Fonts.Heavy,
		TextSize = 14,
		Text = labelSubtitle(record),
		Parent = pill,
	})
	Style.ink(sub, 1.5)
	record.label = gui
	record.labelText = title
	record.labelSub = sub
end

local function refreshLabel(record: Record)
	if record.labelText then
		record.labelText.Text = labelTitle(record)
	end
	if record.labelSub then
		record.labelSub.Text = labelSubtitle(record)
	end
end

local function updateHighlight(record: Record)
	local wants = record.rarity.order >= 5 and (record.state == "Carried" or record.state == "Rift" or record.state == "Dropped") and record.vanishStart == nil
	if wants and not record.highlight then
		record.highlight = Create("Highlight", {
			FillTransparency = 1,
			OutlineColor = record.rarity.color,
			OutlineTransparency = 0.15,
			DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
			Adornee = record.visual.model,
			Parent = record.visual.model,
		})
	elseif not wants and record.highlight then
		record.highlight:Destroy()
		record.highlight = nil
	end
end

----------------------------------------------------------------------------
-- One-shot effects
----------------------------------------------------------------------------

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

-- Expanding glowing ring + particle burst at a position.
function RelicRenderer.burst(position: Vector3, color: Color3, size: number, sound: string?)
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(0.2, 1, 1)
	part.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 0.1
	part.Parent = container
	Tween.play(part, 0.55, { Size = Vector3.new(0.05, size, size), Transparency = 1 }, Enum.EasingStyle.Quart)

	local attachment = Instance.new("Attachment")
	attachment.Parent = part
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARKLE
	emitter.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Lifetime = NumberRange.new(0.4, 0.9)
	emitter.Speed = NumberRange.new(size * 0.8, size * 1.6)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 4
	emitter.LightEmission = 1
	emitter.Rate = 0
	emitter.Parent = attachment
	emitter:Emit(math.floor(18 * Settings.particleScale() + 4))
	task.delay(1.2, function()
		part:Destroy()
	end)
	if sound then
		Audio.playAt(sound, position)
	end
end

-- Floating "+12/s" style text in the world.
function RelicRenderer.popText(position: Vector3, text: string, color: Color3)
	local anchor = Instance.new("Part")
	anchor.Size = Vector3.one * 0.2
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = container
	local gui: BillboardGui = Create("BillboardGui", {
		Size = UDim2.fromOffset(200, 50),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 120,
		Adornee = anchor,
		Parent = anchor,
	})
	local label = Style.text({
		Text = text,
		TextSize = 32,
		FontFace = Style.burstFont(text),
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Center,
		Rotation = math.random(-8, 8),
		Parent = gui,
	})
	Style.ink(label, 3)
	local scale: UIScale = Create("UIScale", { Scale = 0.4, Parent = label })
	Tween.play(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	Tween.play(anchor, 1.4, { CFrame = CFrame.new(position + Vector3.new(0, 5, 0)) }, Enum.EasingStyle.Quint)
	Tween.play(label, 0.5, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0.9)
	task.delay(1.5, function()
		anchor:Destroy()
	end)
end

----------------------------------------------------------------------------
-- Records
----------------------------------------------------------------------------

local function setLocalTransparency(record: Record, value: number)
	for _, part in record.visual.parts do
		part.LocalTransparencyModifier = value
	end
end

local function startVanish(record: Record, reason: string)
	if record.vanishStart then
		return
	end
	record.vanishStart = clock
	record.vanishReason = reason
	record.flight = nil
	for _, beam in record.visual.beams do
		beam.Enabled = false
	end
	for _, item in record.visual.emitters do
		item.emitter.Enabled = false
	end
	if record.label then
		record.label.Enabled = false
	end
	if record.highlight then
		record.highlight:Destroy()
		record.highlight = nil
	end
	if record.stealRing then
		record.stealRing:Destroy()
		record.stealRing = nil
	end
	local color = record.rarity.color
	if reason == "Dissolved" then
		RelicRenderer.burst(record.position, Color3.fromRGB(120, 235, 255), 7, "Dissolve")
	elseif reason == "Fused" then
		RelicRenderer.burst(record.position, Color3.fromRGB(255, 220, 120), 6, nil)
	elseif reason ~= "Leave" then
		RelicRenderer.burst(record.position, color, 4, nil)
	end
end

local function destroyRecord(record: Record)
	records[record.uid] = nil
	for _, connection in record.connections do
		connection:Disconnect()
	end
	Factory.destroy(record.visual)
end

local function flyTo(record: Record, from: Vector3, height: number, duration: number, onLand: (() -> ())?)
	record.flight = {
		from = from,
		height = height,
		start = clock,
		duration = duration,
		target = function()
			return targetPosition(record)
		end,
		onLand = onLand,
	}
	record.position = from
end

local function onStateChanged(record: Record)
	local state = attrString(record.anchor, "State")
	if state == record.state then
		return
	end
	local previous = record.state
	record.state = state
	if state == "Dropped" and previous == "Carried" then
		flyTo(record, record.position, 2.5, 0.4, function()
			RelicRenderer.burst(record.anchor.Position, record.rarity.color, 3, nil)
		end)
	end
	updateHighlight(record)
	refreshLabel(record)
end

local function addRecord(anchor: BasePart)
	local uid = attrString(anchor, "Uid")
	if uid == "" or records[uid] then
		return
	end
	local relicId = attrString(anchor, "RelicId")
	local mutation = attrString(anchor, "Mutation")
	local visual = Factory.build(relicId, if mutation == "" then nil else mutation, { particleScale = Settings.particleScale() })
	if not visual then
		return
	end
	visual.model.Parent = container
	local rarity = Rarities.get(attrString(anchor, "Rarity"))

	local record: Record = {
		uid = uid,
		anchor = anchor,
		relicId = relicId,
		rarity = rarity,
		mutation = if mutation == "" then nil else mutation,
		visual = visual,
		state = attrString(anchor, "State"),
		level = math.max(1, attrNumber(anchor, "Level")),
		position = anchor.Position,
		yaw = math.random() * math.pi * 2,
		phase = math.random() * math.pi * 2,
		detail = 2,
		frame = math.random(0, 2),
		flight = nil,
		vanishStart = nil,
		vanishReason = nil,
		awaitingFuse = false,
		label = nil,
		labelText = nil,
		labelSub = nil,
		highlight = nil,
		stealRing = nil,
		focus = nil,
		focusAt = 0,
		bump = 0,
		connections = {},
	}
	records[uid] = record
	Factory.setDetail(visual, 2, Settings.particleScale())

	-- Fresh Rift spawns fly out of the tear.
	local spawnedAt = attrNumber(anchor, "SpawnedAt")
	if record.state == "Rift" and workspace:GetServerTimeNow() - spawnedAt < 1.5 then
		flyTo(record, Layout.RiftCore, 9, 0.95, function()
			RelicRenderer.burst(anchor.Position, rarity.color, 6, "RelicEmerge")
		end)
	elseif record.state == "Carried" then
		local root = carrierRoot(record)
		if root then
			record.position = root.Position
		end
	end

	table.insert(record.connections, anchor:GetAttributeChangedSignal("State"):Connect(function()
		onStateChanged(record)
	end))
	table.insert(record.connections, anchor:GetAttributeChangedSignal("Level"):Connect(function()
		record.level = math.max(1, attrNumber(anchor, "Level"))
		record.bump = 1
		refreshLabel(record)
	end))
	table.insert(record.connections, anchor:GetAttributeChangedSignal("Vanish"):Connect(function()
		local reason = attrString(anchor, "Vanish")
		if reason == "Fused" then
			-- Wait for the Fuse FX to fly it into its twin; fade anyway if it never comes.
			record.awaitingFuse = true
			task.delay(0.4, function()
				if record.awaitingFuse and not record.flight then
					startVanish(record, reason)
				end
			end)
		else
			startVanish(record, reason)
		end
	end))
	table.insert(record.connections, anchor.AncestryChanged:Connect(function()
		if anchor.Parent == nil and not record.vanishStart then
			startVanish(record, "Leave")
		end
	end))
	updateHighlight(record)
	RelicRenderer.recordAdded:Fire(record)
end

----------------------------------------------------------------------------
-- FX hooks (called by the FX router)
----------------------------------------------------------------------------

function RelicRenderer.get(uid: string?): Record?
	return if uid then records[uid] else nil
end

function RelicRenderer.positionOf(uid: string): Vector3?
	local record = records[uid]
	return if record then record.position else nil
end

function RelicRenderer.onPickup(uid: string, userId: number)
	local record = records[uid]
	if not record then
		return
	end
	RelicRenderer.burst(record.position, record.rarity.color, 5, nil)
	if userId == localPlayer.UserId then
		Audio.play("Pickup")
	else
		Audio.playAt("Pickup", record.position)
	end
end

function RelicRenderer.onDeposit(uid: string, from: Vector3, userId: number)
	local record = records[uid]
	if not record then
		return
	end
	flyTo(record, from + Vector3.new(0, 3, 0), 12, 0.6, function()
		local landing = record.anchor.Position - Vector3.new(0, Layout.RelicHover - 0.2, 0)
		RelicRenderer.burst(landing, record.rarity.color, 9, "Deposit")
		local rate = Economy.relicBaseRate(record.relicId, record.level, record.mutation)
		if userId == localPlayer.UserId then
			rate *= Store.state.multiplier
		end
		RelicRenderer.popText(record.anchor.Position + Vector3.new(0, 2, 0), "+" .. Format.abbrev(rate) .. "/s", Color3.fromRGB(130, 240, 255))
	end)
end

function RelicRenderer.onFuse(uid: string, targetUid: string, from: Vector3, level: number)
	local record = records[uid]
	local target = records[targetUid]
	if not record or not target then
		if record then
			startVanish(record, "Fused")
		end
		return
	end
	record.awaitingFuse = false
	record.flight = {
		from = from + Vector3.new(0, 3, 0),
		height = 10,
		start = clock,
		duration = 0.65,
		target = function()
			return target.position
		end,
		onLand = function()
			startVanish(record, "Fused")
			target.bump = 1
			RelicRenderer.burst(target.position, Color3.fromRGB(255, 220, 120), 10, "Fuse")
			RelicRenderer.popText(target.position + Vector3.new(0, 2.5, 0), string.rep("★", level), Color3.fromRGB(255, 220, 120))
		end,
	}
	record.position = from + Vector3.new(0, 3, 0)
end

function RelicRenderer.onReturnHome(uid: string)
	local record = records[uid]
	if not record then
		return
	end
	flyTo(record, record.position, 16, 1.1, function()
		RelicRenderer.burst(record.anchor.Position, record.rarity.color, 8, "Recovered")
	end)
end

function RelicRenderer.onStolen(uid: string)
	local record = records[uid]
	if record then
		RelicRenderer.burst(record.position, Color3.fromRGB(255, 70, 90), 7, "StealGrab")
	end
end

-- Progress ring over a relic while someone holds the Steal prompt.
function RelicRenderer.showSteal(uid: string, duration: number)
	local record = records[uid]
	if not record then
		return
	end
	if record.stealRing then
		record.stealRing:Destroy()
	end
	local gui: BillboardGui = Create("BillboardGui", {
		Size = UDim2.fromOffset(150, 34),
		StudsOffsetWorldSpace = Vector3.new(0, -2.6 * record.visual.scale, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 220,
		Adornee = record.visual.root,
		Parent = record.visual.model,
	})
	local back = Create("Frame", {
		Size = UDim2.new(1, 0, 0, 14),
		Position = UDim2.fromScale(0, 0.5),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Style.Colors.Ink,
		BackgroundTransparency = 0.2,
		Parent = gui,
	})
	Style.corner(back, UDim.new(1, 0))
	Style.stroke(back, Style.Colors.Ink, 0, 2.5)
	local fill = Create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Style.Colors.Danger,
		Parent = back,
	})
	Style.corner(fill, UDim.new(1, 0))
	Tween.play(fill, duration, { Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Linear)
	record.stealRing = gui
end

function RelicRenderer.hideSteal(uid: string)
	local record = records[uid]
	if record and record.stealRing then
		record.stealRing:Destroy()
		record.stealRing = nil
	end
end

----------------------------------------------------------------------------
-- Frame update
----------------------------------------------------------------------------

local env: Factory.Env = {
	time = 0,
	dt = 0,
	focus = nil,
	camera = nil,
	rootCFrame = CFrame.identity,
}

local function nearestCharacter(position: Vector3, radius: number): Vector3?
	local best: Vector3? = nil
	local bestDistance = radius
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local head = character and character:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			local distance = (head.Position - position).Magnitude
			if distance < bestDistance then
				bestDistance = distance
				best = head.Position
			end
		end
	end
	return best
end

local labelTimer = 0

local function step(dt: number)
	clock += dt
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local cameraPos = camera.CFrame.Position
	local lod = Settings.lodScale()
	local nearDistance = 85 * lod
	local midDistance = 220 * lod
	local particleScale = Settings.particleScale()
	labelTimer += dt
	local refreshLabels = labelTimer > 0.25
	if refreshLabels then
		labelTimer = 0
	end

	env.dt = dt
	env.time = clock
	env.camera = cameraPos

	for _, record in records do
		local visual = record.visual

		-- Vanishing
		if record.vanishStart then
			local t = (clock - record.vanishStart) / 0.8
			if t >= 1 then
				destroyRecord(record)
				continue
			end
			setLocalTransparency(record, t)
			record.position += Vector3.new(0, dt * 2.2, 0)
			visual.root.CFrame = CFrame.new(record.position) * CFrame.Angles(0, record.yaw + t * 4, 0) * visual.bodyTransform
			continue
		end

		-- Position
		local target = targetPosition(record)
		local flight = record.flight
		if flight then
			local t = math.clamp((clock - flight.start) / flight.duration, 0, 1)
			local eased = MathUtil.easeInOutSine(t)
			local finish = flight.target()
			local control = (flight.from + finish) / 2 + Vector3.new(0, flight.height, 0)
			record.position = MathUtil.bezier(flight.from, control, finish, eased)
			if t >= 1 then
				record.flight = nil
				if flight.onLand then
					flight.onLand()
				end
			end
		else
			local sharpness = if record.state == "Carried" then 14 else 7
			record.position = record.position:Lerp(target, MathUtil.damp(sharpness, dt))
		end

		local distance = (record.position - cameraPos).Magnitude
		local detail = if distance < nearDistance then 2 elseif distance < midDistance then 1 else 0
		if detail ~= record.detail then
			record.detail = detail
			Factory.setDetail(visual, detail, particleScale)
		end

		if visual.spin then
			record.yaw += dt * (0.55 + record.rarity.order * 0.06)
		end
		local bob = math.sin(clock * 1.7 + record.phase) * 0.28 * visual.scale
		if record.bump > 0 then
			record.bump = math.max(0, record.bump - dt * 2.2)
			bob += math.sin(record.bump * math.pi) * 1.2
		end
		local base = CFrame.new(record.position + Vector3.new(0, bob, 0)) * CFrame.Angles(0, record.yaw, 0)

		-- Animators (with LOD cadence)
		record.frame += 1
		local animate = detail == 2 or (detail == 1 and record.frame % 3 == 0)
		if animate and #visual.animators > 0 then
			env.rootCFrame = base
			if visual.wantsFocus then
				if clock - record.focusAt > 0.2 then
					record.focusAt = clock
					record.focus = nearestCharacter(record.position, 45)
				end
				env.focus = record.focus
			else
				env.focus = nil
			end
			env.dt = if detail == 2 then dt else dt * 3
			Factory.step(visual, env)
		end
		visual.root.CFrame = base * visual.bodyTransform

		-- Labels
		if refreshLabels then
			local labelRange = if record.state == "Placed" then 26 elseif record.state == "Carried" then 0 else 70
			local show = distance < labelRange
			if show then
				ensureLabel(record)
				refreshLabel(record)
			end
			if record.label then
				record.label.Enabled = show
			end
		end
	end
end

function RelicRenderer.init()
	container = Instance.new("Folder")
	container.Name = "ClientRelics"
	container.Parent = workspace

	local relicsFolder = workspace:WaitForChild("Relics")
	local function onChild(child: Instance)
		if child:IsA("BasePart") then
			-- Attributes are set before parenting on the server; defer once in case.
			if attrString(child, "Uid") == "" then
				task.wait()
			end
			addRecord(child)
		end
	end
	relicsFolder.ChildAdded:Connect(onChild)
	for _, child in relicsFolder:GetChildren() do
		task.spawn(onChild, child)
	end

	Store.changed:Connect(function(state, previous)
		if state.multiplier ~= previous.multiplier then
			for _, record in records do
				if record.label and record.state == "Placed" then
					refreshLabel(record)
				end
			end
		end
	end)
	Settings.changed:Connect(function()
		for _, record in records do
			record.detail = -1
		end
	end)
	Locale.changed:Connect(function()
		for _, record in records do
			refreshLabel(record)
		end
	end)

	RunService.RenderStepped:Connect(step)
end

return RelicRenderer
