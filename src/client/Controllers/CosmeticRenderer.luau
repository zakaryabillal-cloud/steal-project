--!strict
-- Draws every player's cosmetics (V2 phase 5). Display only: the server
-- publishes the equipped ids (player attributes "Cos_<category>", Sanctuary
-- attribute "Theme") after checking ownership; nothing here is ever sent back
-- or used by gameplay.
--
-- Performance rules (Config/Cosmetics.Budget):
--   * ONE update loop for all players (Heartbeat, throttled to UpdateInterval);
--     no per-player or per-effect connection. Trails and particles are
--     native Roblox effects that animate by themselves.
--   * Effects of other players are switched off beyond a distance per kind;
--     only the MaxAuras nearest auras and MaxLights nearest aura lights run;
--     Low quality hides other players' auras and carry effects.
--   * Titles hide while the player carries a relic (the carry marker must
--     stay readable in a chase); nothing is drawn over the carried relic.
--   * Everything is parented to the character (gone with it) or tracked and
--     destroyed on respawn, death, departure and cosmetic change.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Cosmetics = require(Shared.Config.Cosmetics)
local Locale = require(Shared.Locale)
local Signal = require(Shared.Util.Signal)

local Kit = script.Parent.Parent.UI.Kit
local Create = require(Kit.Create)
local Style = require(Kit.Style)
local Tween = require(Kit.Tween)

local Settings = require(script.Parent.Settings)
local RelicRenderer = require(script.Parent.RelicRenderer)

local CosmeticRenderer = {}

local B = Cosmetics.Budget
local localPlayer = Players.LocalPlayer

type View = {
	player: Player,
	character: Model?,
	-- category -> id currently drawn ("" = none)
	drawn: { [string]: string },
	trail: Trail?,
	aura: ParticleEmitter?,
	auraLight: PointLight?,
	carry: ParticleEmitter?,
	title: BillboardGui?,
	parts: { Instance },
	lastOneShot: number,
	distance: number,
	carrying: boolean,
	-- First character seen when the renderer started: no arrival FX for it.
	seenAtStart: boolean,
}

type ThemeState = { id: string, tier: number, parts: { [BasePart]: boolean }, lights: { [PointLight]: boolean }, motes: ParticleEmitter? }

local views: { [Player]: View } = {}
local themes: { [Model]: ThemeState } = {}
local folder: Folder
local guiFolder: Folder
local started = false

-- Local try-on: shows a cosmetic on your own character for a few seconds.
type Preview = { id: string, category: string, untilTime: number }
local preview: Preview? = nil

-- (kind, userId) one-shot effect played (tests / debug).
CosmeticRenderer.played = Signal.new()

local function equippedOf(player: Player, category: Cosmetics.CategoryDef): string
	if player == localPlayer and preview and preview.category == category.id and os.clock() < preview.untilTime then
		return preview.id
	end
	local value = player:GetAttribute(category.attribute)
	local def = Cosmetics.get(value)
	if def and def.category == category.id then
		return def.id
	end
	return ""
end

local function sequence(a: Color3, b: Color3): ColorSequence
	return ColorSequence.new({ ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b) })
end

local function emitter(parent: Instance, visual: { [string]: any }, texture: string?): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "CosmeticParticles"
	e.Texture = Cosmetics.Textures[texture or "sparkle"]
	e.Color = sequence(visual.color, visual.color2 or visual.color)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, visual.size), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.8, 1.4)
	e.Speed = NumberRange.new(visual.speed or 0.6, (visual.speed or 0.6) * 1.6)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rate = math.min(visual.rate or 4, B.MaxRate)
	e.Parent = parent
	return e
end

----------------------------------------------------------------------------
-- Per-category builders (each returns what it created)
----------------------------------------------------------------------------

local function clearCategory(view: View, category: string)
	if category == "trail" and view.trail then
		local trail = view.trail :: Trail
		local a0, a1 = trail.Attachment0, trail.Attachment1
		trail:Destroy()
		if a0 then
			a0:Destroy()
		end
		if a1 then
			a1:Destroy()
		end
		view.trail = nil
	elseif category == "aura" and view.aura then
		local parent = (view.aura :: ParticleEmitter).Parent
		if parent then
			parent:Destroy()
		end
		view.aura = nil
		view.auraLight = nil
	elseif category == "carry" and view.carry then
		local parent = (view.carry :: ParticleEmitter).Parent
		if parent then
			parent:Destroy()
		end
		view.carry = nil
	elseif category == "title" and view.title then
		(view.title :: BillboardGui):Destroy()
		view.title = nil
	end
	view.drawn[category] = ""
end

local function buildCategory(view: View, category: string, id: string)
	clearCategory(view, category)
	local character = view.character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local head = character and character:FindFirstChild("Head")
	view.drawn[category] = id
	local def = Cosmetics.get(id)
	if not def or not root or not root:IsA("BasePart") then
		return
	end
	local v = def.visual
	if category == "trail" then
		local a0: Attachment = Create("Attachment", { Name = "CosmeticTrailTop", Position = Vector3.new(0, 1.2, 0), Parent = root })
		local a1: Attachment = Create("Attachment", { Name = "CosmeticTrailBottom", Position = Vector3.new(0, -1.4, 0), Parent = root })
		view.trail = Create("Trail", {
			Name = "CosmeticTrail",
			Attachment0 = a0,
			Attachment1 = a1,
			Lifetime = math.min(v.lifetime, B.MaxTrailLifetime),
			WidthScale = NumberSequence.new(math.min(v.width, B.MaxTrailWidth) / 2.6),
			Color = sequence(v.colors[1], v.colors[2]),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }),
			LightEmission = v.light,
			LightInfluence = 0,
			FaceCamera = true,
			MinLength = 0.2,
			Parent = root,
		})
	elseif category == "aura" then
		local attachment: Attachment = Create("Attachment", { Name = "CosmeticAura", Position = Vector3.new(0, -0.5, 0), Parent = root })
		local e = emitter(attachment, v, v.texture)
		e.Acceleration = Vector3.new(0, 1.5, 0)
		view.aura = e
		if v.light then
			view.auraLight = Create("PointLight", { Name = "CosmeticAuraLight", Color = v.color, Range = v.light.range, Brightness = v.light.brightness, Shadows = false, Parent = attachment })
		end
	elseif category == "carry" then
		-- Around the carried relic's height, never on it (relic + marker stay readable).
		local attachment: Attachment = Create("Attachment", { Name = "CosmeticCarry", Position = Vector3.new(0, 4, 0), Parent = root })
		local e = emitter(attachment, v, "sparkle")
		-- A loose halo of `radius` studs around the relic (speed x lifetime).
		e.Speed = NumberRange.new(v.radius * 0.6, v.radius)
		e.Drag = 2
		e.Enabled = false
		view.carry = e
	elseif category == "title" then
		if not head or not head:IsA("BasePart") then
			view.drawn[category] = "" -- head not loaded yet: retry next update
			return
		end
		local gui: BillboardGui = Create("BillboardGui", {
			Name = "CosmeticTitle_" .. view.player.UserId,
			Size = UDim2.fromOffset(160, 20),
			StudsOffsetWorldSpace = Vector3.new(0, 2.1, 0),
			MaxDistance = B.TitleDistance,
			LightInfluence = 0,
			ResetOnSpawn = false,
			Adornee = head,
			Parent = guiFolder,
		})
		local label = Style.text({
			Name = "Title",
			Size = UDim2.fromScale(1, 1),
			Text = "« " .. Locale.t("cos." .. def.id) .. " »",
			TextSize = 13,
			FontFace = Style.Fonts.Heavy,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = v.color,
			Parent = gui,
		})
		Style.textStroke(label, 0.3, 1.5)
		view.title = gui
	end
end

----------------------------------------------------------------------------
-- One-shot effects (arrival, secure)
----------------------------------------------------------------------------

local function oneShot(kind: string, view: View?, userId: number, position: Vector3, id: string)
	local def = Cosmetics.get(id)
	if not def then
		return
	end
	if view then
		local now = os.clock()
		if now - view.lastOneShot < B.OneShotCooldown then
			return
		end
		view.lastOneShot = now
	end
	local v = def.visual
	local scale = Settings.particleScale()
	local holder = Instance.new("Part")
	holder.Name = "CosmeticBurst"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.one * 0.2
	holder.CFrame = CFrame.new(position)
	holder.Parent = folder
	local attachment = Instance.new("Attachment")
	attachment.Parent = holder
	local e = emitter(attachment, { color = v.color, color2 = v.color2, size = 0.6, rate = 0, speed = v.size }, "sparkle")
	e.Rate = 0
	e:Emit(math.max(2, math.floor(math.min(v.burst, B.MaxBurstParticles) * scale)))
	for ring = 1, v.rings or 1 do
		local part = Instance.new("Part")
		part.Name = "CosmeticRing"
		part.Shape = Enum.PartType.Cylinder
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Color = if ring % 2 == 1 then v.color else v.color2
		part.Transparency = 0.2
		part.Size = Vector3.new(0.2, 1, 1)
		part.CFrame = CFrame.new(position - Vector3.new(0, 2.6 - ring * 0.4, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		part.Parent = holder
		Tween.play(part, 0.5 + ring * 0.12, { Size = Vector3.new(0.05, v.size * (0.8 + ring * 0.3), v.size * (0.8 + ring * 0.3)), Transparency = 1 }, Enum.EasingStyle.Quart)
	end
	if v.pillar then
		local pillar = Instance.new("Part")
		pillar.Name = "CosmeticPillar"
		pillar.Anchored = true
		pillar.CanCollide = false
		pillar.CanQuery = false
		pillar.CanTouch = false
		pillar.CastShadow = false
		pillar.Material = Enum.Material.Neon
		pillar.Color = v.color
		pillar.Transparency = 0.3
		pillar.Size = Vector3.new(1.2, 14, 1.2)
		pillar.CFrame = CFrame.new(position + Vector3.new(0, 4, 0))
		pillar.Parent = holder
		Tween.play(pillar, 0.7, { Size = Vector3.new(0.1, 18, 0.1), Transparency = 1 }, Enum.EasingStyle.Quad)
	end
	task.delay(1.6, function()
		holder:Destroy()
	end)
	CosmeticRenderer.played:Fire(kind, userId)
end

-- A relic was placed / a heist secured by `userId` (Deposit / Fuse FX).
function CosmeticRenderer.secured(userId: number, position: Vector3?)
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return
	end
	local category = Cosmetics.category("secure") :: Cosmetics.CategoryDef
	local id = equippedOf(player, category)
	local view = views[player]
	if id == "" or not position then
		return
	end
	if view and player ~= localPlayer and view.distance > B.ThemeDistance then
		return
	end
	oneShot("secure", view, userId, position, id)
end

----------------------------------------------------------------------------
-- Sanctuary themes
----------------------------------------------------------------------------

local function closeColor(a: Color3, b: Color3): boolean
	return math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B) < 0.02
end

local function isExcluded(instance: Instance, model: Model): boolean
	-- Seal barrier and rarity-coloured pedestal rings keep their meaning.
	local node: Instance? = instance
	while node and node ~= model do
		if node.Name == "Barrier" or node.Name == "Ring" then
			return true
		end
		node = node.Parent
	end
	return false
end

local function applyTheme(model: Model, id: string)
	local accent = model:GetAttribute("Accent")
	if typeof(accent) ~= "Color3" then
		return
	end
	local state = themes[model]
	if not state then
		state = { id = "", tier = 0, parts = {}, lights = {}, motes = nil }
		themes[model] = state
	end
	local s = state :: ThemeState
	local def = Cosmetics.get(id)
	local target: Color3 = if def then def.visual.accent else accent
	-- (Re)discover accent parts (a tier change rebuilds part of the Sanctuary).
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and not s.parts[d] and closeColor(d.Color, accent) and not isExcluded(d, model) then
			s.parts[d] = true
		elseif d:IsA("PointLight") and not s.lights[d] and closeColor(d.Color, accent) and not isExcluded(d, model) then
			s.lights[d] = true
		end
	end
	for part in s.parts do
		if part.Parent then
			part.Color = target
		else
			s.parts[part] = nil
		end
	end
	for light in s.lights do
		if light.Parent then
			light.Color = target
		else
			s.lights[light] = nil
		end
	end
	if s.motes then
		local motesParent = (s.motes :: ParticleEmitter).Parent
		if motesParent then
			motesParent:Destroy()
		end
		s.motes = nil
	end
	local core = model.PrimaryPart
	if def and core then
		local attachment = Instance.new("Attachment")
		attachment.Name = "CosmeticThemeMotes"
		attachment.Position = Vector3.new(0, 8, 0)
		attachment.Parent = core
		local e = emitter(attachment, { color = def.visual.motes, color2 = def.visual.accent, size = 0.5, rate = def.visual.rate, speed = 0.8 }, "sparkle")
		e.Lifetime = NumberRange.new(2, 3.5)
		s.motes = e
	end
	s.id = id
	s.tier = (model:GetAttribute("Tier") :: number?) or 1
end

local function themeOf(model: Model): string
	local id = model:GetAttribute("Theme")
	local value = if type(id) == "string" then id else ""
	-- Preview on your own Sanctuary.
	local p = preview
	if p and p.category == "sanctuary" and os.clock() < p.untilTime and model:GetAttribute("OwnerId") == localPlayer.UserId then
		value = p.id
	end
	local def = Cosmetics.get(value)
	return if def and def.category == "sanctuary" then value else ""
end

local function updateThemes(cameraPosition: Vector3)
	local sanctuaries = workspace:FindFirstChild("Sanctuaries")
	if not sanctuaries then
		return
	end
	for _, model in sanctuaries:GetChildren() do
		if not model:IsA("Model") then
			continue
		end
		local id = themeOf(model)
		local state = themes[model]
		local tier = (model:GetAttribute("Tier") :: number?) or 1
		if (state and (state.id ~= id or state.tier ~= tier)) or (not state and id ~= "") then
			applyTheme(model, id)
			state = themes[model]
		end
		if state and state.motes then
			local core = model.PrimaryPart
			local far = core ~= nil and (core.Position - cameraPosition).Magnitude > B.ThemeDistance * Settings.lodScale()
			local motes = state.motes :: ParticleEmitter
			motes.Enabled = not far
		end
	end
end

----------------------------------------------------------------------------
-- The single update loop
----------------------------------------------------------------------------

local function newView(player: Player): View
	local view: View = {
		player = player,
		character = nil,
		drawn = {},
		trail = nil,
		aura = nil,
		auraLight = nil,
		carry = nil,
		title = nil,
		parts = {},
		lastOneShot = -math.huge,
		distance = 0,
		carrying = false,
		seenAtStart = not started,
	}
	views[player] = view
	return view
end

local function releaseView(view: View)
	for _, category in Cosmetics.Categories do
		clearCategory(view, category.id)
	end
end

local function carriers(): { [number]: boolean }
	local set = {}
	for _, record in RelicRenderer.records do
		if record.state == "Carried" and record.vanishStart == nil then
			local carrierId = record.anchor:GetAttribute("CarrierId")
			if type(carrierId) == "number" then
				set[carrierId] = true
			end
		end
	end
	return set
end

local function update()
	local camera = workspace.CurrentCamera
	local cameraPosition = if camera then camera.CFrame.Position else Vector3.zero
	local lod = Settings.lodScale()
	local low = Settings.quality == "Low"
	local carrying = carriers()
	local auraCandidates: { View } = {}
	-- Your own aura light counts against the light budget too.
	local ownLights = 0
	for _, player in Players:GetPlayers() do
		local view = views[player] or newView(player)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if character ~= view.character then
			-- New character (respawn) or gone: start clean.
			releaseView(view)
			local first = view.character == nil and view.seenAtStart
			view.character = character
			view.seenAtStart = false
			if character and root and root:IsA("BasePart") and not first then
				local arrival = equippedOf(player, Cosmetics.category("arrival") :: Cosmetics.CategoryDef)
				if arrival ~= "" then
					oneShot("arrival", view, player.UserId, root.Position, arrival)
				end
			end
		end
		if not character or not root or not root:IsA("BasePart") then
			continue
		end
		for _, category in Cosmetics.Categories do
			if category.id == "trail" or category.id == "aura" or category.id == "carry" or category.id == "title" then
				local id = equippedOf(player, category)
				if view.drawn[category.id] ~= id then
					buildCategory(view, category.id, id)
				end
			end
		end
		local isLocal = player == localPlayer
		view.distance = if isLocal then 0 else (root.Position - cameraPosition).Magnitude
		view.carrying = carrying[player.UserId] == true
		if view.trail then
			(view.trail :: Trail).Enabled = isLocal or view.distance <= B.TrailDistance * lod
		end
		if view.carry then
			(view.carry :: ParticleEmitter).Enabled = view.carrying and (isLocal or (not low and view.distance <= B.CarryDistance * lod))
		end
		if view.title then
			(view.title :: BillboardGui).Enabled = not view.carrying
		end
		if view.aura then
			if isLocal then
				(view.aura :: ParticleEmitter).Enabled = true
				if view.auraLight then
					(view.auraLight :: PointLight).Enabled = true
					ownLights = 1
				end
			else
				table.insert(auraCandidates, view)
			end
		end
	end
	-- Auras of others: nearest first, within distance and budgets.
	table.sort(auraCandidates, function(a, b)
		return a.distance < b.distance
	end)
	local auras, lights = 0, ownLights
	for _, view in auraCandidates do
		local allowed = not low and view.distance <= B.AuraDistance * lod and auras < B.MaxAuras
		if allowed then
			auras += 1
		end
		(view.aura :: ParticleEmitter).Enabled = allowed
		if view.auraLight then
			local lit = allowed and lights < B.MaxLights
			if lit then
				lights += 1
			end
			(view.auraLight :: PointLight).Enabled = lit
		end
	end
	updateThemes(cameraPosition)
end

-- Local try-on of any cosmetic (owned or not): your own client only.
function CosmeticRenderer.preview(id: string): boolean
	local def = Cosmetics.get(id)
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not def or not root or not root:IsA("BasePart") then
		return false
	end
	if def.category == "arrival" or def.category == "secure" then
		oneShot(def.category, nil, localPlayer.UserId, root.Position, def.id)
		return true
	end
	preview = { id = def.id, category = def.category, untilTime = os.clock() + B.PreviewSeconds }
	update()
	return true
end

function CosmeticRenderer.init()
	folder = Instance.new("Folder")
	folder.Name = "CosmeticFX"
	folder.Parent = workspace
	guiFolder = Instance.new("Folder")
	guiFolder.Name = "CosmeticFX"
	guiFolder.Parent = localPlayer:WaitForChild("PlayerGui")
	for _, player in Players:GetPlayers() do
		newView(player)
	end
	started = true
	Players.PlayerRemoving:Connect(function(player)
		local view = views[player]
		if view then
			releaseView(view)
			views[player] = nil
		end
	end)
	local timer = 0
	RunService.Heartbeat:Connect(function(dt)
		timer += dt
		if timer >= B.UpdateInterval then
			timer = 0
			local p = preview
			if p and os.clock() >= p.untilTime then
				preview = nil
			end
			update()
		end
	end)
end

-- Tests / debug: what is currently drawn.
function CosmeticRenderer.debugCounts(): { [string]: number }
	local counts = { views = 0, trails = 0, trailsOn = 0, auras = 0, aurasOn = 0, lights = 0, lightsOn = 0, carries = 0, carriesOn = 0, titles = 0, themed = 0 }
	for _, view in views do
		counts.views += 1
		if view.trail then
			counts.trails += 1
			counts.trailsOn += if (view.trail :: Trail).Enabled then 1 else 0
		end
		if view.aura then
			counts.auras += 1
			counts.aurasOn += if (view.aura :: ParticleEmitter).Enabled then 1 else 0
		end
		if view.auraLight then
			counts.lights += 1
			counts.lightsOn += if (view.auraLight :: PointLight).Enabled then 1 else 0
		end
		if view.carry then
			counts.carries += 1
			counts.carriesOn += if (view.carry :: ParticleEmitter).Enabled then 1 else 0
		end
		if view.title then
			counts.titles += 1
		end
	end
	for _, state in themes do
		if state.id ~= "" then
			counts.themed += 1
		end
	end
	return counts
end

-- Tests / debug: force one update now.
CosmeticRenderer.update = update

return CosmeticRenderer
