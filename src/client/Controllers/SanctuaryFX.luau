--!strict
-- Client presentation of the 8 Sanctuaries:
--   * owner sign (avatar, name, tier, protection badge) above each gate
--   * Essence Core gauge (liquid fill, spinning crystal, billboard counter)
--   * pedestal unlock "rise" animation, tier-up construction sequence
--   * orbiting stones (Citadel) and floating halo (Nexus)
--   * seal barrier shimmer and the red "heist in progress" beacon

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Layout = require(Shared.Layout)
local Locale = require(Shared.Locale)
local Format = require(Shared.Util.Format)

local Kit = script.Parent.Parent.UI.Kit
local Create = require(Kit.Create)
local Style = require(Kit.Style)
local Tween = require(Kit.Tween)
local Icons = require(Kit.Icons)

local Audio = require(script.Parent.Audio)
local CameraFX = require(script.Parent.CameraFX)
local RelicRenderer = require(script.Parent.RelicRenderer)

local SanctuaryFX = {}

type OrbitPart = { part: BasePart, base: CFrame }

type PlotView = {
	index: number,
	model: Model,
	origin: CFrame,
	accent: Color3,
	crystal: BasePart?,
	crystalBase: CFrame,
	fill: BasePart?,
	fillBottom: number,
	fillMax: number,
	fillLevel: number,
	signName: TextLabel,
	signSub: TextLabel,
	signCard: Frame,
	signGui: BillboardGui,
	signCompact: boolean,
	signAvatar: ImageLabel,
	badge: Frame,
	badgeText: TextLabel,
	coreAmount: TextLabel,
	coreRate: TextLabel,
	coreBar: Frame,
	coreGui: BillboardGui,
	orbit: { OrbitPart },
	orbitReady: boolean,
	halo: BasePart?,
	haloBase: CFrame,
	beacon: Part?,
	walls: { BasePart },
	sealed: boolean,
	thumbFor: number,
}

local views: { PlotView } = {}
local localPlayer = Players.LocalPlayer
local clock = 0

local PROTECTION_COLORS = {
	Novice = Color3.fromRGB(120, 220, 255),
	Aegis = Color3.fromRGB(255, 205, 90),
	Sealed = Color3.fromRGB(190, 140, 255),
	Resting = Color3.fromRGB(170, 170, 200),
	LastRelics = Color3.fromRGB(140, 230, 170),
}

local PROTECTION_KEYS = {
	Novice = "block.novice",
	Aegis = "block.aegis",
	Sealed = "block.sealed",
	Resting = "block.resting",
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

----------------------------------------------------------------------------
-- Billboards
----------------------------------------------------------------------------

-- Owner sign above each gate. V2: sized in studs (BillboardGui scale) so it
-- shrinks with distance instead of staying a fixed 340 px card across the
-- whole map; shown up to SIGN_MAX_DISTANCE, name-only beyond SIGN_COMPACT_DISTANCE.
local SIGN_WIDTH = 11
local SIGN_HEIGHT = 3.2
local SIGN_MAX_DISTANCE = 150
local SIGN_COMPACT_DISTANCE = 60

local function scaledText(props: { [string]: any }, maxSize: number): TextLabel
	props.TextScaled = true
	local label = Style.text(props)
	Create("UITextSizeConstraint", { MaxTextSize = maxSize, MinTextSize = 6, Parent = label })
	return label
end

local function buildSign(view: PlotView, anchor: BasePart)
	local gui: BillboardGui = Create("BillboardGui", {
		Name = "Sign",
		Size = UDim2.fromScale(SIGN_WIDTH, SIGN_HEIGHT),
		LightInfluence = 0,
		MaxDistance = SIGN_MAX_DISTANCE,
		Adornee = anchor,
		Parent = anchor,
	})
	local card = Style.panel({
		Name = "Card",
		Size = UDim2.fromScale(1, 0.74),
		BackgroundTransparency = 0.25,
		Parent = gui,
	})
	local accentBar = Create("Frame", {
		Size = UDim2.fromScale(0.012, 0.6),
		Position = UDim2.fromScale(0.03, 0.2),
		BackgroundColor3 = view.accent,
		BorderSizePixel = 0,
		Parent = card,
	})
	Style.corner(accentBar, UDim.new(1, 0))
	local avatar: ImageLabel = Create("ImageLabel", {
		Size = UDim2.fromScale(0.2, 0.74),
		Position = UDim2.fromScale(0.06, 0.5),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Style.Colors.PanelRaised,
		Image = "",
		Parent = card,
	})
	Create("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height, Parent = avatar })
	Style.corner(avatar, UDim.new(1, 0))
	Style.stroke(avatar, view.accent, 0.1, 2)
	view.signAvatar = avatar
	view.signName = scaledText({
		Name = "OwnerName",
		Size = UDim2.fromScale(0.68, 0.44),
		Position = UDim2.fromScale(0.28, 0.1),
		FontFace = Style.Fonts.Display,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = card,
	}, 26)
	view.signSub = scaledText({
		Name = "Details",
		Size = UDim2.fromScale(0.68, 0.3),
		Position = UDim2.fromScale(0.28, 0.58),
		FontFace = Style.Fonts.BodyBold,
		TextColor3 = Style.Colors.TextDim,
		Parent = card,
	}, 16)
	local badge: Frame = Create("Frame", {
		Size = UDim2.fromScale(0.5, 0.24),
		Position = UDim2.fromScale(0.5, 1),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = Style.Colors.Panel,
		BackgroundTransparency = 0.15,
		Visible = false,
		Parent = gui,
	})
	Style.corner(badge, UDim.new(1, 0))
	local badgeStroke = Style.stroke(badge, Style.Colors.Gold, 0.3, 1.5)
	badgeStroke.Name = "BadgeStroke"
	local iconHolder = Create("Frame", {
		Size = UDim2.fromScale(0.1, 0.66),
		Position = UDim2.fromScale(0.04, 0.5),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
		Parent = badge,
	})
	Create("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height, Parent = iconHolder })
	Icons.shield(iconHolder, Color3.new(1, 1, 1))
	view.badgeText = scaledText({
		Size = UDim2.fromScale(0.8, 0.8),
		Position = UDim2.fromScale(0.16, 0.1),
		FontFace = Style.Fonts.BodyBold,
		Parent = badge,
	}, 14)
	view.badge = badge
	view.signCard = card
	view.signGui = gui
end

-- Far away the sign collapses to just the owner's name.
local function setSignCompact(view: PlotView, compact: boolean)
	if view.signCompact == compact then
		return
	end
	view.signCompact = compact
	view.signAvatar.Visible = not compact
	view.signSub.Visible = not compact
	if compact then
		view.signCard.Size = UDim2.fromScale(0.7, 0.5)
		view.signCard.Position = UDim2.fromScale(0.15, 0.2)
		view.signName.Size = UDim2.fromScale(0.9, 0.8)
		view.signName.Position = UDim2.fromScale(0.05, 0.1)
		view.signName.TextXAlignment = Enum.TextXAlignment.Center
	else
		view.signCard.Size = UDim2.fromScale(1, 0.74)
		view.signCard.Position = UDim2.fromScale(0, 0)
		view.signName.Size = UDim2.fromScale(0.68, 0.44)
		view.signName.Position = UDim2.fromScale(0.28, 0.1)
		view.signName.TextXAlignment = Enum.TextXAlignment.Left
	end
end

local function buildCoreGui(view: PlotView, crystal: BasePart)
	local gui: BillboardGui = Create("BillboardGui", {
		Name = "CoreGauge",
		Size = UDim2.fromOffset(190, 64),
		StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0),
		LightInfluence = 0,
		MaxDistance = 85,
		Adornee = crystal,
		Parent = crystal,
	})
	local holder = Create("Frame", {
		Size = UDim2.fromOffset(22, 22),
		Position = UDim2.fromOffset(4, 4),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	Icons.essence(holder)
	view.coreAmount = Style.text({
		Size = UDim2.new(1, -30, 0, 28),
		Position = UDim2.fromOffset(30, 1),
		FontFace = Style.Fonts.Display,
		TextSize = 20,
		Parent = gui,
	})
	Style.textStroke(view.coreAmount, 0.3, 2)
	local back = Create("Frame", {
		Size = UDim2.new(1, -8, 0, 8),
		Position = UDim2.fromOffset(4, 34),
		BackgroundColor3 = Color3.fromRGB(20, 16, 36),
		BackgroundTransparency = 0.2,
		Parent = gui,
	})
	Style.corner(back, UDim.new(1, 0))
	Style.stroke(back, Color3.new(1, 1, 1), 0.7, 1)
	local bar = Create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = back,
	})
	Style.corner(bar, UDim.new(1, 0))
	Style.gradient(bar, Style.Colors.Essence, Style.Colors.EssenceDeep)
	view.coreBar = bar
	view.coreRate = Style.text({
		Size = UDim2.new(1, -8, 0, 18),
		Position = UDim2.fromOffset(4, 44),
		FontFace = Style.Fonts.BodyBold,
		TextSize = 14,
		TextColor3 = Style.Colors.Essence,
		Parent = gui,
	})
	Style.textStroke(view.coreRate, 0.4, 1.5)
	view.coreGui = gui
end

local function refreshSign(view: PlotView)
	local model = view.model
	local ownerId = attrNumber(model, "OwnerId")
	local tier = math.max(1, attrNumber(model, "Tier"))
	if ownerId == 0 then
		view.signName.Text = Locale.t("sign.free")
		view.signName.TextColor3 = Style.Colors.TextMuted
		view.signSub.Text = ""
		view.signAvatar.Image = ""
		view.badge.Visible = false
		view.coreGui.Enabled = false
		return
	end
	view.coreGui.Enabled = true
	local name = attrString(model, "OwnerName")
	view.signName.Text = Locale.t("sign.owner", { name = Style.escape(name) })
	view.signName.TextColor3 = if ownerId == localPlayer.UserId then Style.Colors.Essence else Style.Colors.Text
	view.signSub.Text = string.format("%s  ·  %d ◆", Locale.t("tier." .. tier), attrNumber(model, "PlacedCount"))
	if view.thumbFor ~= ownerId then
		view.thumbFor = ownerId
		task.spawn(function()
			local ok, image = pcall(function()
				return Players:GetUserThumbnailAsync(ownerId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
			end)
			if ok and view.thumbFor == ownerId then
				view.signAvatar.Image = image
			end
		end)
	end
end

local function refreshBadge(view: PlotView)
	local model = view.model
	local kind = attrString(model, "Protection")
	if kind == "" or attrNumber(model, "OwnerId") == 0 then
		view.badge.Visible = false
		return
	end
	view.badge.Visible = true
	local color = PROTECTION_COLORS[kind] or Style.Colors.Gold
	local untilTime = attrNumber(model, "ProtectionUntil")
	local remaining = untilTime - workspace:GetServerTimeNow()
	local key = PROTECTION_KEYS[kind] or "hud.protected"
	view.badgeText.Text = Locale.t(key, { time = Format.clock(remaining) })
	if kind == "Novice" and remaining > 0 then
		view.badgeText.Text ..= "  " .. Format.clock(remaining)
	end
	view.badgeText.TextColor3 = color
	local stroke = view.badge:FindFirstChild("BadgeStroke") :: UIStroke?
	if stroke then
		stroke.Color = color
	end
end

local function refreshCore(view: PlotView)
	local model = view.model
	local stored = attrNumber(model, "CoreStored")
	local capacity = math.max(1, attrNumber(model, "CoreCapacity"))
	local rate = attrNumber(model, "Rate")
	local fraction = math.clamp(stored / capacity, 0, 1)
	view.coreAmount.Text = string.format("%s<font color=\"#9A92C8\" size=\"15\"> / %s</font>", Format.abbrev(stored), Format.abbrev(capacity))
	view.coreRate.Text = if fraction >= 1 then Locale.t("core.full") else "+" .. Format.abbrev(rate) .. "/s"
	view.coreRate.TextColor3 = if fraction >= 1 then Style.Colors.Warning else Style.Colors.Essence
	Tween.play(view.coreBar, 0.5, { Size = UDim2.fromScale(fraction, 1) })
	view.fillLevel = fraction
end

----------------------------------------------------------------------------
-- Animations
----------------------------------------------------------------------------

local function riseIn(parts: { BasePart }, center: Vector3, lift: number, stagger: number)
	for _, part in parts do
		local final = part.CFrame
		local finalTransparency = part.Transparency
		if finalTransparency >= 1 then
			continue
		end
		part.CFrame = final - Vector3.new(0, lift, 0)
		part.Transparency = 1
		local delay = (Vector3.new(part.Position.X, 0, part.Position.Z) - Vector3.new(center.X, 0, center.Z)).Magnitude * stagger + math.random() * 0.15
		task.delay(delay, function()
			Tween.play(part, 0.75, { CFrame = final }, Enum.EasingStyle.Back)
			Tween.play(part, 0.4, { Transparency = finalTransparency }, Enum.EasingStyle.Quad)
		end)
	end
end

local function collectOrbit(view: PlotView)
	table.clear(view.orbit)
	view.halo = nil
	local structure = view.model:FindFirstChild("Structure")
	if not structure then
		return
	end
	for _, descendant in structure:GetDescendants() do
		if descendant:IsA("Model") and descendant.Name == "Orbit" then
			for _, part in descendant:GetChildren() do
				if part:IsA("BasePart") then
					table.insert(view.orbit, { part = part, base = part.CFrame })
				end
			end
		elseif descendant:IsA("BasePart") and descendant.Name == "Halo" then
			view.halo = descendant
			view.haloBase = descendant.CFrame
		end
	end
	view.orbitReady = true
end

function SanctuaryFX.tierUp(plot: number, tier: number, userId: number)
	local view = views[plot]
	if not view then
		return
	end
	view.orbitReady = false
	task.spawn(function()
		local structure = view.model:WaitForChild("Structure", 5)
		local folder = structure and structure:WaitForChild("Tier" .. tier, 5)
		if not folder then
			collectOrbit(view)
			return
		end
		task.wait(0.05)
		local parts = {}
		for _, descendant in folder:GetDescendants() do
			if descendant:IsA("BasePart") then
				table.insert(parts, descendant)
			end
		end
		riseIn(parts, view.origin.Position, 9, 0.022)
		RelicRenderer.burst(view.origin.Position + Vector3.new(0, 1, 0), view.accent, 60, nil)
		Audio.playAt("TierUp", view.origin.Position, { volume = 1.4 })
		if userId == localPlayer.UserId then
			CameraFX.shake(0.4)
		end
		task.wait(1.6)
		collectOrbit(view)
	end)
end

function SanctuaryFX.pedestalRise(plot: number, slot: number)
	local view = views[plot]
	local pedestal = view and view.model:FindFirstChild("Pedestals")
	local model = pedestal and pedestal:FindFirstChild("Pedestal" .. slot)
	if not view or not model then
		return
	end
	local parts = {}
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			table.insert(parts, part)
		end
	end
	riseIn(parts, view.origin.Position, 4, 0)
	local top = (view.origin * Layout.slotLocal(slot)).Position + Vector3.new(0, Layout.PedestalHeight, 0)
	task.delay(0.35, function()
		RelicRenderer.burst(top, view.accent, 9, "Purchase")
	end)
end

function SanctuaryFX.coreBurst(plot: number)
	local view = views[plot]
	if view and view.crystal then
		RelicRenderer.burst(view.crystal.Position, Color3.fromRGB(120, 235, 255), 12, nil)
	end
end

function SanctuaryFX.seal(plot: number, on: boolean)
	local view = views[plot]
	if not view then
		return
	end
	view.sealed = on
	local center = view.origin.Position
	if on then
		RelicRenderer.burst(center + Vector3.new(0, 2, 0), view.accent, 80, "Seal")
	else
		Audio.playAt("Seal", center, { pitch = 0.7 })
	end
end

function SanctuaryFX.corePosition(plot: number): Vector3?
	local view = views[plot]
	if view and view.crystal then
		return view.crystal.Position
	end
	return nil
end

local function setBeacon(view: PlotView, on: boolean)
	if on and not view.beacon then
		local beacon = Instance.new("Part")
		beacon.Shape = Enum.PartType.Cylinder
		beacon.Size = Vector3.new(220, 4, 4)
		beacon.CFrame = CFrame.new(view.origin.Position + Vector3.new(0, 110, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		beacon.Material = Enum.Material.Neon
		beacon.Color = Style.Colors.Danger
		beacon.Transparency = 0.5
		beacon.Anchored = true
		beacon.CanCollide = false
		beacon.CanQuery = false
		beacon.CanTouch = false
		beacon.CastShadow = false
		beacon.Parent = workspace
		view.beacon = beacon
	elseif not on and view.beacon then
		view.beacon:Destroy()
		view.beacon = nil
	end
end

----------------------------------------------------------------------------
-- Setup & frame loop
----------------------------------------------------------------------------

local function setupPlot(model: Model)
	local index = attrNumber(model, "Index")
	local core = model:WaitForChild("Core")
	local crystal = core:FindFirstChild("Crystal") :: BasePart?
	local fill = core:FindFirstChild("Fill") :: BasePart?
	local walls = {}
	local barrier = model:FindFirstChild("Barrier")
	if barrier then
		for _, child in barrier:GetChildren() do
			if child:IsA("BasePart") and child.Name == "Wall" then
				table.insert(walls, child)
			end
		end
	end
	local accentValue = model:GetAttribute("Accent")
	local view: PlotView = {
		index = index,
		model = model,
		origin = Layout.plotCFrame(index),
		accent = if typeof(accentValue) == "Color3" then accentValue else Color3.new(1, 1, 1),
		crystal = crystal,
		crystalBase = if crystal then crystal.CFrame else CFrame.identity,
		fill = fill,
		fillBottom = if fill then attrNumber(fill, "BottomY") else 0,
		fillMax = if fill then attrNumber(fill, "MaxHeight") else 0,
		fillLevel = 0,
		signName = nil :: any,
		signSub = nil :: any,
		signCard = nil :: any,
		signGui = nil :: any,
		signCompact = false,
		signAvatar = nil :: any,
		badge = nil :: any,
		badgeText = nil :: any,
		coreAmount = nil :: any,
		coreRate = nil :: any,
		coreBar = nil :: any,
		coreGui = nil :: any,
		orbit = {},
		orbitReady = false,
		halo = nil,
		haloBase = CFrame.identity,
		beacon = nil,
		walls = walls,
		sealed = attrNumber(model, "SealedUntil") > workspace:GetServerTimeNow(),
		thumbFor = 0,
	}
	views[index] = view
	buildSign(view, model:WaitForChild("SignAnchor") :: BasePart)
	if crystal then
		buildCoreGui(view, crystal)
	end
	refreshSign(view)
	refreshBadge(view)
	refreshCore(view)
	collectOrbit(view)

	for _, name in { "OwnerId", "OwnerName", "Tier", "PlacedCount" } do
		model:GetAttributeChangedSignal(name):Connect(function()
			refreshSign(view)
			refreshBadge(view)
		end)
	end
	for _, name in { "Protection", "ProtectionUntil" } do
		model:GetAttributeChangedSignal(name):Connect(function()
			refreshBadge(view)
		end)
	end
	for _, name in { "CoreStored", "CoreCapacity", "Rate" } do
		model:GetAttributeChangedSignal(name):Connect(function()
			refreshCore(view)
		end)
	end
	model:GetAttributeChangedSignal("UnderAttack"):Connect(function()
		setBeacon(view, attrNumber(model, "UnderAttack") ~= 0)
	end)
	model:GetAttributeChangedSignal("Tier"):Connect(function()
		if attrNumber(model, "Tier") <= 1 then
			collectOrbit(view)
		end
	end)
	model:GetAttributeChangedSignal("SealedUntil"):Connect(function()
		view.sealed = attrNumber(model, "SealedUntil") > workspace:GetServerTimeNow()
		if not view.sealed then
			for _, wall in view.walls do
				wall.Transparency = 1
			end
		end
	end)

	-- Pedestal unlock animation (only for live changes).
	local pedestals = model:WaitForChild("Pedestals")
	for _, pedestal in pedestals:GetChildren() do
		local previous = attrString(pedestal, "State")
		pedestal:GetAttributeChangedSignal("State"):Connect(function()
			local state = attrString(pedestal, "State")
			if state == "Active" and previous ~= "Active" then
				SanctuaryFX.pedestalRise(index, attrNumber(pedestal, "Slot"))
			end
			previous = state
		end)
	end
end

function SanctuaryFX.init()
	local folder = workspace:WaitForChild("Sanctuaries")
	for i = 1, Layout.PlotCount do
		setupPlot(folder:WaitForChild("Sanctuary" .. i) :: Model)
	end
	Locale.changed:Connect(function()
		for _, view in views do
			refreshSign(view)
			refreshBadge(view)
			refreshCore(view)
		end
	end)

	local badgeTimer = 0
	local orbitTimer = 0
	local signTimer = 0
	RunService.RenderStepped:Connect(function(dt)
		clock += dt
		badgeTimer += dt
		orbitTimer += dt
		local camera = workspace.CurrentCamera
		local cameraPos = if camera then camera.CFrame.Position else Vector3.zero
		local updateOrbit = orbitTimer > 1 / 30
		if updateOrbit then
			orbitTimer = 0
		end
		for _, view in views do
			local near = (view.origin.Position - cameraPos).Magnitude < 380
			if near and view.crystal then
				local spin = CFrame.Angles(0, clock * 1.2, 0)
				view.crystal.CFrame = CFrame.new(view.crystalBase.Position + Vector3.new(0, math.sin(clock * 2) * 0.35, 0)) * spin * view.crystalBase.Rotation
			end
			if near and view.fill then
				local height = math.max(0.15, view.fillMax * view.fillLevel)
				local current = view.fill.Size.X
				local smooth = current + (height - current) * math.min(1, dt * 4)
				view.fill.Size = Vector3.new(smooth, view.fill.Size.Y, view.fill.Size.Z)
				view.fill.CFrame = view.origin * CFrame.new(0, view.fillBottom + smooth / 2, 0) * CFrame.Angles(0, 0, math.pi / 2)
			end
			if near and updateOrbit and view.orbitReady then
				local angle = clock * 0.18
				local center = view.origin.Position
				local rotation = CFrame.new(center) * CFrame.Angles(0, angle, 0) * CFrame.new(-center)
				local parts, cframes = {}, {}
				for _, item in view.orbit do
					table.insert(parts, item.part)
					table.insert(cframes, rotation * item.base * CFrame.new(0, math.sin(clock + item.base.Position.X) * 0.02, 0))
				end
				if #parts > 0 then
					workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
				end
				if view.halo then
					view.halo.CFrame = view.haloBase * CFrame.Angles(0, clock * 0.25, 0)
				end
			end
			if view.sealed then
				local alpha = 0.5 + math.sin(clock * 5) * 0.12
				for _, wall in view.walls do
					wall.Transparency = alpha
				end
			end
			if view.beacon then
				view.beacon.Transparency = 0.35 + (math.sin(clock * 8) + 1) * 0.2
			end
		end
		if badgeTimer > 1 then
			badgeTimer = 0
			for _, view in views do
				if view.badge.Visible then
					refreshBadge(view)
				end
			end
		end
		signTimer += dt
		if signTimer > 0.25 then
			signTimer = 0
			for _, view in views do
				local distance = (view.signGui.Parent :: BasePart).Position - cameraPos
				setSignCompact(view, distance.Magnitude > SIGN_COMPACT_DISTANCE)
			end
		end
	end)
end

return SanctuaryFX
