--!nocheck
-- Phase 5.5 ("Cartoon & Goofy" art direction) scenarios. Called by
-- tests/run.luau with its helpers; runs on the same live server + client.
--
--   * tokens: contrast of white text on panels, button lips, built-in fonts,
--     rarity stars, emoji policy (source scan), no external asset ids;
--   * world: sunny lighting applied by the server = default.project.json,
--     toy-plastic materials, terrain palette, Rift face, decorations that
--     never block anything, Sanctuary colours / bunting;
--   * relic faces: who gets one, behaviour (turns toward the player, blinks),
--     mutations never recolour the eyes;
--   * client UI: HUD hierarchy, chunky buttons, modals with ribbons, reward
--     juice caps, rarity pills over relics, the Rift's "BURP!";
--   * no gameplay module reads the new visual modules.

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3
local Vector2 = roblox.Vector2
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local UDim2 = roblox.UDim2
local Enum = roblox.Enum

return function(ctx)
	local scenario, check, advance = ctx.scenario, ctx.check, ctx.advance
	local shared, Engine, Loader, game = ctx.shared, ctx.Engine, ctx.Loader, ctx.game
	local sessionOf, claimRelic = ctx.sessionOf, ctx.claimRelic
	local alice = ctx.alice()

	local Theme = shared("Config.Theme")
	local Palette = shared("Config.Palette")
	local Emoji = shared("Config.Emoji")
	local Rarities = shared("Config.Rarities")
	local Relics = shared("Config.Relics")
	local Mutations = shared("Config.Mutations")
	local Strings = shared("Locale.Strings")

	local Client = game:GetService("StarterPlayer").StarterPlayerScripts.Client
	local function creq(path)
		local node = Client
		for part in string.gmatch(path, "[^%.]+") do
			node = node:FindFirstChild(part)
		end
		return Loader.require("client", node)
	end
	local Style = creq("UI.Kit.Style")
	local Button = creq("UI.Kit.Button")
	local Juice = creq("UI.Kit.Juice")
	local UI = creq("UI")
	local Factory = Loader.require("client", game:GetService("ReplicatedStorage").Shared.Relics.RelicFactory)
	local RelicFaces = Loader.require("client", game:GetService("ReplicatedStorage").Shared.Relics.RelicFaces)

	local function sourceFiles(dir, out)
		out = out or {}
		for _, name in fs.readDir(dir) do
			local path = dir .. "/" .. name
			if fs.isDir(path) then
				sourceFiles(path, out)
			elseif string.sub(name, -5) == ".luau" then
				table.insert(out, path)
			end
		end
		return out
	end
	local function near(a, b, eps)
		return math.abs(a - b) <= (eps or 0.01)
	end
	local function colorNear(c, rgb, eps)
		return near(c.R, rgb[1], eps or 0.01) and near(c.G, rgb[2], eps or 0.01) and near(c.B, rgb[3], eps or 0.01)
	end

	--------------------------------------------------------------------------
	scenario("Art direction: tokens, contrast, fonts, rarity stars", function()
		local C = Theme.Colors
		check(Style.contrast(C.Text, C.Panel) >= 4.5, string.format("white text on panels >= 4.5:1 (%.2f)", Style.contrast(C.Text, C.Panel)))
		check(Style.contrast(C.Text, C.PanelLight) >= 7, string.format("white text on cards >= 7:1 (%.2f)", Style.contrast(C.Text, C.PanelLight)))
		check(Style.contrast(C.TextDim, C.PanelLight) >= 4.5, string.format("dim text on cards >= 4.5:1 (%.2f)", Style.contrast(C.TextDim, C.PanelLight)))
		check(Style.contrast(C.TextMuted, C.PanelLight) >= 3, string.format("muted captions on cards >= 3:1 (%.2f)", Style.contrast(C.TextMuted, C.PanelLight)))
		check(Style.luminance(C.Panel) > Style.luminance(C.Ink) * 4, "panels are bright colour, outlines are ink")
		check(Theme.Transparency.Panel == 0 and Theme.Transparency.Stroke == 0, "opaque panels, opaque ink outlines")
		local lipsOk, families = true, 0
		for name, family in Theme.Buttons do
			families += 1
			if Style.luminance(family.lip) >= Style.luminance(family.face) then
				lipsOk = false
				check(false, "button family " .. name .. ": lip darker than face")
			end
		end
		check(lipsOk and families >= 8, "8+ button colour families, each with a darker lip (" .. families .. ")")
		-- Fonts: built-in families only.
		local allowed = {}
		for _, family in Theme.FontFamilies do
			allowed[family] = true
			check(string.match(family, "^rbxasset://fonts/families/[%w]+%.json$") ~= nil, "built-in font family " .. family)
		end
		for key, font in Theme.Fonts do
			check(allowed[font.Family] == true, "font " .. key .. " uses an allowed family (" .. font.Family .. ")")
		end
		check(Style.burstFont("+250") == Theme.Fonts.Burst and Style.burstFont("DÉBLOQUÉ !") == Theme.Fonts.Display, "Luckiest Guy only for unaccented shouts (accents fall back to Fredoka)")
		-- Rarity: colour AND star count.
		local last = 0
		for _, rarity in Rarities.list do
			local stars = Theme.RarityStars[rarity.id]
			check(stars ~= nil and stars > last, "rarity " .. rarity.id .. " has more stars than the previous tier")
			last = stars or last
			check(Style.stars(rarity.id) == string.rep("★", stars or 0), "stars string for " .. rarity.id)
		end
		-- Sanctuary candy colours: all distinct and saturated.
		local seen = {}
		for i, color in Theme.PlotColors do
			local _, sat, value = color:ToHSV()
			check(sat >= 0.5 and value >= 0.75, "plot colour " .. i .. " is a saturated candy colour")
			local key = string.format("%d,%d,%d", color.R * 255, color.G * 255, color.B * 255)
			check(not seen[key], "plot colour " .. i .. " unique")
			seen[key] = true
		end
	end)

	--------------------------------------------------------------------------
	scenario("Art direction: emoji policy and assets (source scan)", function()
		local files = sourceFiles("src")
		local unknown, selectors, unreliable, uses = {}, {}, {}, 0
		local assetFiles = {}
		for _, path in files do
			local source = fs.readFile(path)
			for _, codepoint in utf8.codes(source) do
				if codepoint == 0xFE0F or codepoint == 0x200D then
					selectors[path] = true
				elseif Emoji.Unreliable[codepoint] then
					unreliable[path] = string.format("U+%X", codepoint)
				elseif codepoint >= 0x1F000 then
					uses += 1
					if not Emoji.Allowed[codepoint] then
						unknown[path] = string.format("U+%X", codepoint)
					end
				end
			end
			if string.find(source, "rbxassetid://%d") and not string.find(path, "Config/Music", 1, true) then
				-- Only the documented examples in comments are allowed elsewhere.
				for line in string.gmatch(source, "[^\n]+") do
					if string.find(line, "rbxassetid://%d") and not string.find(line, "^%s*%-%-") then
						assetFiles[path] = true
					end
				end
			end
		end
		local function keys(t)
			local list = {}
			for k, v in t do
				table.insert(list, k .. (if type(v) == "string" then " " .. v else ""))
			end
			table.sort(list)
			return table.concat(list, ", ")
		end
		check(next(unknown) == nil, "every emoji in src/ is in Config/Emoji.Glyphs (" .. keys(unknown) .. ")")
		check(next(selectors) == nil, "no variation selector / ZWJ sequence in src/ (" .. keys(selectors) .. ")")
		check(next(unreliable) == nil, "no text-presentation emoji (gear, shield, snowflake...) in src/ (" .. keys(unreliable) .. ")")
		check(uses >= 30, "the interface really uses emoji (" .. uses .. " occurrences)")
		check(next(assetFiles) == nil, "no asset id outside Config/Music (" .. keys(assetFiles) .. ")")
		for key, glyph in Emoji.Glyphs do
			local count = 0
			for _, codepoint in utf8.codes(glyph) do
				count += 1
				if codepoint ~= 0x26A1 and codepoint ~= 0x2728 and codepoint ~= 0x2B50 and codepoint ~= 0x2705 and codepoint ~= 0x274C and codepoint ~= 0x23F3 and codepoint ~= 0x26C4 and codepoint < 0x1F000 then
					check(false, "emoji " .. key .. " is a known default-emoji code point")
				end
			end
			check(count == 1, "emoji " .. key .. " is a single code point")
		end
		-- New fx strings exist in both languages.
		for _, key in { "fx.bonk", "fx.new", "fx.unlocked", "fx.levelUp", "fx.burp" } do
			check(Strings.en[key] ~= nil and Strings.fr[key] ~= nil, "string " .. key .. " (en + fr)")
		end
		check(fs.isFile("docs/ART_DIRECTION.md"), "docs/ART_DIRECTION.md exists")
		local doc = fs.readFile("docs/ART_DIRECTION.md")
		for _, section in { "Palette", "Typographie", "Icônes et emojis", "Animation", "Effets visuels", "Monde", "Reliques", "Boss", "Interfaces", "vrais assets" } do
			check(string.find(doc, section, 1, true) ~= nil, "art direction doc covers: " .. section)
		end
	end)

	--------------------------------------------------------------------------
	scenario("Art direction: sunny world, toy materials, project file in sync", function()
		local Lighting = game:GetService("Lighting")
		check(near(Lighting.ClockTime, Palette.Lighting.ClockTime) and Lighting.ClockTime > 10 and Lighting.ClockTime < 16, "daytime lighting applied by the server (" .. Lighting.ClockTime .. ")")
		check(Lighting.Brightness >= 2.5, "bright sun")
		-- (Rift events tint the atmosphere on the client, but it always stays light.)
		local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
		check(atmosphere and Style.luminance(atmosphere.Color) > 0.3, "light, airy atmosphere (never a dark night haze)")
		local clouds = Engine.workspace.Terrain:FindFirstChildOfClass("Clouds")
		check(clouds and clouds.Color == Color3.new(1, 1, 1) and clouds.Cover >= 0.5, "puffy white clouds")
		check(Lighting:FindFirstChildOfClass("Sky").StarCount == 0, "no stars in a daytime sky")
		-- default.project.json (Edit mode) mirrors the runtime ambience.
		local project = serde.decode("json", fs.readFile("default.project.json"))
		local props = project.tree.Lighting["$properties"]
		local function rgb(c)
			return { c.R, c.G, c.B }
		end
		local lightingOk = true
		for key, value in Palette.Lighting do
			local stored = props[key]
			if typeof(value) == "Color3" then
				lightingOk = lightingOk and stored ~= nil and colorNear(value, stored, 0.005)
			else
				lightingOk = lightingOk and stored ~= nil and near(stored, value, 0.001)
			end
		end
		check(lightingOk, "default.project.json Lighting = Palette.Lighting")
		local atmo = project.tree.Lighting.Atmosphere["$properties"]
		check(colorNear(Palette.Atmosphere.Color, atmo.Color, 0.005) and near(atmo.Density, Palette.Atmosphere.Density), "default.project.json Atmosphere = Palette.Atmosphere")
		local cc = project.tree.Lighting.ColorCorrection["$properties"]
		check(near(cc.Saturation, Palette.Effects.ColorCorrection.Saturation) and colorNear(Palette.Effects.ColorCorrection.TintColor, cc.TintColor, 0.005), "default.project.json ColorCorrection = Palette.Effects")
		check(project.tree.Workspace.Terrain.Clouds ~= nil, "clouds declared for Edit mode")
		local _ = rgb

		-- Toy materials: no realistic material left on world parts.
		local realistic, total = 0, 0
		for _, folderName in { "World", "Sanctuaries" } do
			for _, d in Engine.workspace:FindFirstChild(folderName):GetDescendants() do
				if d:IsA("BasePart") then
					total += 1
					if Palette.Stylize[d.Material] then
						realistic += 1
					end
				end
			end
		end
		check(total > 3000 and realistic == 0, "no Slate/Marble/Cobblestone/Metal/Wood left on " .. total .. " world parts (" .. realistic .. ")")
		for material in Palette.Stylize do
			check(material ~= Enum.Material.Neon and material ~= Enum.Material.Glass and material ~= Enum.Material.ForceField, "Neon / Glass / ForceField are kept")
		end
		-- Terrain palette.
		local terrain = Engine.workspace.Terrain
		check(terrain:GetMaterialColor(Enum.Material.Grass) == Palette.Terrain.Grass and terrain.WaterColor == Palette.Water.Color, "candy terrain colours applied")
		for name, color in Palette.Terrain do
			check(Style.luminance(color) >= 0.12, "terrain " .. name .. " is not gloomy")
		end

		-- Decorations never block or catch raycasts.
		local decor = Engine.workspace:FindFirstChild("World"):FindFirstChild("Props"):FindFirstChild("Decor")
		local flowers, mushrooms, solid = 0, 0, 0
		for _, d in decor:GetDescendants() do
			if d:IsA("Model") and d.Name == "Flower" then
				flowers += 1
			elseif d:IsA("Model") and d.Name == "Mushroom" then
				mushrooms += 1
			elseif d:IsA("BasePart") and (d.CanCollide or d.CanQuery) then
				solid += 1
			end
		end
		check(flowers >= 30 and mushrooms >= 12, string.format("giant flowers (%d) and mushrooms (%d) dress the island", flowers, mushrooms))
		check(solid == 0, "decorations are soft: never collide, never block a raycast (" .. solid .. ")")

		-- Sanctuaries: pastel candy foundations, all different; bunting at the gate.
		local foundations = {}
		for _, model in Engine.workspace:FindFirstChild("Sanctuaries"):GetChildren() do
			local foundation = model:FindFirstChild("Foundation", true)
			local bunting, pennants = 0, 0
			for _, d in model:GetDescendants() do
				if d.Name == "Bunting" then
					bunting += 1
				elseif d.Name == "Pennant" then
					pennants += 1
				end
			end
			check(foundation ~= nil and bunting >= 6 and pennants == 2, model.Name .. ": candy foundation, gate bunting and pennants")
			if foundation then
				local key = string.format("%.2f,%.2f,%.2f", foundation.Color.R, foundation.Color.G, foundation.Color.B)
				check(not foundations[key], model.Name .. " foundation colour is unique")
				foundations[key] = true
			end
		end
	end)

	--------------------------------------------------------------------------
	scenario("Art direction: the Rift's goofy face", function()
		local rift = Engine.workspace:FindFirstChild("World"):FindFirstChild("Rift")
		local root = rift:FindFirstChild("EyesRoot")
		check(root ~= nil and root:GetAttribute("eyeOffset") ~= nil and root:GetAttribute("mouthY") ~= nil, "EyesRoot carries the face layout")
		local names = { "EyeWhiteL", "EyeWhiteR", "PupilL", "PupilR", "ShineL", "ShineR", "BrowL", "BrowR", "Mouth", "Tongue" }
		local ok = true
		for _, name in names do
			local part = rift:FindFirstChild(name)
			if not part or part.CanCollide or part.CanQuery then
				ok = false
				check(false, "face part " .. name .. " exists and is non-solid")
			end
		end
		check(ok, "the Rift has eyes, pupils, shines, brows, a mouth and a tongue (non-solid)")
		check(rift:FindFirstChild("TearDark").Color ~= Color3.new(0, 0, 0) and Style.luminance(rift:FindFirstChild("TearDark").Color) > 0.05, "the portal inside is candy purple, not black")
		-- Client: the face turns toward this client's camera.
		local RiftFX = creq("Controllers.RiftFX")
		local face = RiftFX.face()
		check(face ~= nil, "client found the face")
		local camera = Engine.workspace.CurrentCamera
		local saved = camera.CFrame
		for _, angle in { 0, 2.1 } do
			local position = Vector3.new(math.cos(angle) * 120, 60, math.sin(angle) * 120)
			camera.CFrame = CFrame.lookAt(position, Vector3.new(0, 50, 0))
			advance(0.2)
			local left = rift:FindFirstChild("EyeWhiteL").Position
			local right = rift:FindFirstChild("EyeWhiteR").Position
			local center = (left + right) / 2
			local toCamera = Vector3.new(position.X - center.X, 0, position.Z - center.Z).Unit
			local axis = Vector3.new(right.X - left.X, 0, right.Z - left.Z).Unit
			check(math.abs(axis:Dot(toCamera)) < 0.2, string.format("eyes face the camera from angle %.1f (%.2f)", angle, axis:Dot(toCamera)))
		end
		camera.CFrame = saved
		-- Charging: brows up; release: BURP! and an open mouth.
		local mouthBefore = rift:FindFirstChild("Mouth").Size.Y
		RiftFX.charge({ rarity = "Common", duration = 0.3, position = Vector3.new(25, 12, 0) })
		advance(0.15)
		check(face.exciteTarget == 1, "the Rift gets excited while charging")
		advance(0.3)
		local burped = false
		for _, d in Engine.workspace:FindFirstChild("RiftFX"):GetDescendants() do
			if d:IsA("TextLabel") and (d.Text == Strings.en["fx.burp"] or d.Text == Strings.fr["fx.burp"]) then
				burped = true
			end
		end
		check(burped, "BURP! pops over the Rift when a relic comes out")
		check(rift:FindFirstChild("Mouth").Size.Y > mouthBefore + 1, "the mouth opens wide on the burp")
		advance(2)
		check(rift:FindFirstChild("Mouth").Size.Y < mouthBefore + 0.5, "and closes again")
	end)

	--------------------------------------------------------------------------
	scenario("Art direction: relic faces and personalities", function()
		local faced, plain = 0, 0
		for _, def in Relics.list do
			local visual = Factory.build(def.id, nil, { preview = true })
			local eyes, mouths = 0, 0
			for _, part in visual.parts do
				if part.Name == "EyeWhite" or part.Name == "EyeClosed" then
					eyes += 1
				elseif part.Name == "Mouth" then
					mouths += 1
				end
			end
			if RelicFaces.get(def.id) then
				faced += 1
				check(eyes == 2 and mouths == 1 and visual.spin == false and visual.wantsFocus, def.id .. ": two eyes, a mouth, looks at players instead of spinning")
			else
				plain += 1
				check(eyes == 0, def.id .. ": no face (abstract / mechanical relic)")
			end
			Factory.destroy(visual)
		end
		check(faced >= 12 and plain >= 3, string.format("%d relics have a face, %d keep their look", faced, plain))
		-- Behaviour: turns toward the focus, blinks, mutation-proof eyes.
		local visual = Factory.build("pocket_planet", "Golden", { preview = false })
		local white = nil
		for _, part in visual.parts do
			if part.Name == "EyeWhite" then
				white = part
			end
		end
		check(white and white.Color == Color3.new(1, 1, 1), "a Golden mutation never recolours the eyes")
		local focus = Vector3.new(30, 10, 0) -- to the +X side of the relic
		local env = { time = 0, dt = 1 / 30, focus = focus, camera = Vector3.new(0, 10, -40), rootCFrame = CFrame.new(0, 10, 0) }
		local minEye = white.Size.Y
		for frame = 1, 240 do
			env.time = frame / 30
			Factory.step(visual, env)
			minEye = math.min(minEye, white.Size.Y)
		end
		local facing = (env.rootCFrame * visual.bodyTransform).LookVector
		local toFocus = (focus - env.rootCFrame.Position).Unit
		check(facing:Dot(Vector3.new(toFocus.X, 0, toFocus.Z).Unit) > 0.8, string.format("the relic turned to look at the nearby player (%.2f)", facing:Dot(Vector3.new(toFocus.X, 0, toFocus.Z).Unit)))
		check(minEye < white.Size.Y * 0.5, "it blinked at least once in 8 s")
		Factory.destroy(visual)
		-- Every relic x mutation still builds with faces (detail levels too).
		local built = 0
		for _, relic in Relics.list do
			for _, mutation in Mutations.list do
				local v = Factory.build(relic.id, mutation.id, { preview = false })
				if v then
					built += 1
					Factory.step(v, env)
					Factory.setDetail(v, 0, 1)
					Factory.destroy(v)
				end
			end
		end
		check(built == #Relics.list * #Mutations.list, "every relic x mutation builds and steps with its face (" .. built .. ")")
	end)

	--------------------------------------------------------------------------
	scenario("Art direction: HUD, chunky buttons, modals, reward juice", function()
		local hud = alice.PlayerGui:FindFirstChild("RiftHUD")
		local menu = nil
		for _, d in hud:GetDescendants() do
			if d.Name == "Menu" and d:IsA("Frame") then
				menu = d
			end
		end
		check(menu ~= nil and menu:FindFirstChildOfClass("UIGridLayout") ~= nil, "menu is a 2x2 grid")
		local buttons = 0
		for _, child in menu:GetChildren() do
			if child:IsA("TextButton") then
				buttons += 1
				local face = child:FindFirstChild("Face")
				local emoji = face and face:FindFirstChild("Emoji")
				local caption = face and face:FindFirstChild("Caption")
				check(face and child:FindFirstChild("Lip") and emoji and caption, child.Name .. ": chunky button (face + lip) with emoji and caption")
				check(child.Size.X.Offset >= 44 and child.Size.Y.Offset >= 44, child.Name .. ": touch target >= 44 px")
				if emoji then
					local first = utf8.codepoint(emoji.Text, 1)
					check(Emoji.Allowed[first] == true, child.Name .. " emoji allowed")
				end
			end
		end
		check(buttons == 4, "Upgrades, RiftDex, Style, Settings")
		local amount = nil
		for _, d in hud:GetDescendants() do
			if d.Name == "Amount" and d:IsA("TextLabel") then
				amount = d
			end
		end
		check(amount and amount.FontFace.Family == Theme.Fonts.Display.Family and amount.TextSize >= 36, "big rounded Essence counter")
		-- Ability buttons: chunky round, >= 44 px.
		local abilities = hud:FindFirstChild("Abilities", true)
		for _, child in abilities:GetChildren() do
			if child:IsA("TextButton") then
				check(child.Size.X.Offset >= 44 and child:FindFirstChild("Face") ~= nil, "ability button " .. child.Name .. " is chunky and >= 44 px")
			end
		end
		-- Button kit behaviour.
		local holder = Engine.createInternal("Frame", "ButtonTest", alice.PlayerGui:FindFirstChild("RiftOverlay"))
		local b = Button.new({ size = UDim2.fromOffset(120, 50), kind = "green", text = "Go", parent = holder })
		check(b.content.BackgroundColor3 == Theme.Buttons.green.face and b.lipFrame.BackgroundColor3 == Theme.Buttons.green.lip, "kind = family colours")
		b:setEnabled(false)
		check(b.content.BackgroundColor3 ~= Theme.Buttons.green.face and b.label.TextTransparency >= 0, "disabled = desaturated face")
		b:setEnabled(true)
		b:setKind("red")
		check(b.content.BackgroundColor3 == Theme.Buttons.red.face, "setKind recolours face and lip")
		holder:Destroy()
		-- Modals: ribbon + emoji after opening.
		for _, name in { "Shop", "Dex", "Cosmetics", "Settings", "Loadout" } do
			UI.open(name)
			advance(0.6)
			local modals = alice.PlayerGui:FindFirstChild("RiftModals")
			local panel = modals:FindFirstChild(name, true)
			local ribbon = panel and panel:FindFirstChild("Ribbon")
			local emoji = panel and panel:FindFirstChild("Emoji", true)
			check(panel and panel.Visible and ribbon and emoji and emoji.Text ~= "", name .. ": title ribbon with an emoji")
			UI.close()
			advance(0.3)
		end
		-- Juice: confetti and bursts are capped.
		local overlay = alice.PlayerGui:FindFirstChild("RiftOverlay")
		local total = 0
		for _ = 1, 20 do
			total += Juice.confetti(overlay, Vector2.new(300, 300), 40)
		end
		check(total <= Juice.MaxConfetti and Juice.aliveConfetti() <= Juice.MaxConfetti, string.format("confetti capped (%d alive)", Juice.aliveConfetti()))
		advance(2)
		check(Juice.aliveConfetti() == 0, "confetti cleans itself up")
	end)

	--------------------------------------------------------------------------
	scenario("Art direction: rarity pills over relics, no gameplay reads", function()
		-- Relic labels near alice: every one carries a rarity pill with its stars.
		claimRelic(alice, "storm_crystal")
		advance(1)
		local labels, good = 0, 0
		for _, d in Engine.workspace:FindFirstChild("ClientRelics"):GetDescendants() do
			if d:IsA("BillboardGui") and d.Name == "RelicLabel" then
				labels += 1
				local def = Relics.get(d.Parent.Name)
				local pill = d:FindFirstChild("RarityPill")
				local sub = pill and pill:FindFirstChild("Sub")
				if def and pill and sub and pill.BackgroundColor3 == Rarities.get(def.rarity).color then
					local placed = string.find(sub.Text, "+", 1, true) ~= nil
					if placed or string.find(sub.Text, Style.stars(def.rarity), 1, true) then
						good += 1
					end
				end
			end
		end
		check(labels > 0 and good == labels, string.format("relic labels carry a rarity-coloured pill with stars (%d/%d)", good, labels))
		local _ = sessionOf
		-- The new visual modules are never read by gameplay code.
		local stray = {}
		for _, path in sourceFiles("src/server") do
			local source = fs.readFile(path)
			local visualOnly = string.find(path, "/World/", 1, true) ~= nil
			for _, module in { "Config%.Palette", "Config%.Emoji", "Relics%.RelicFaces", "Config%.Theme" } do
				if string.find(source, "require%([^)]*" .. module .. "%)") and not visualOnly then
					table.insert(stray, path .. " -> " .. module)
				end
			end
		end
		check(#stray == 0, "only world builders (server) read the palette / theme (" .. table.concat(stray, ", ") .. ")")
	end)
end
