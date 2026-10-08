--!nocheck
-- Exports the generated world (terrain samples + part footprints + the art
-- direction palette) to JSON so tools/render/render_map.py / render_view.py
-- can draw overview and perspective previews.
--   lune run tools/render/export_world.luau [tier]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Api = require("../../tests/harness/Api")
local Engine = require("../../tests/harness/Engine")
local Loader = require("../../tests/harness/Loader")

local ROOT = process.cwd
Api.load(ROOT .. "/tools/.cache/API-Dump.json")
local game = Engine.createGame()
Loader.mount(game, ROOT .. "/sourcemap.json", ROOT)

local server = game:GetService("ServerScriptService"):FindFirstChild("Server")
local function req(path)
	local node = server
	for part in string.gmatch(path, "[^%.]+") do
		node = node:FindFirstChild(part)
	end
	return Loader.require("server", node)
end

local started = os.clock()
local WorldBuilder = req("World.WorldBuilder")
local thread = Engine.task.spawn(function()
	WorldBuilder.build()
end)
Engine.advance(3)
print(string.format("world build CPU time: %.2fs", os.clock() - started))

local tier = tonumber(process.args[1] or "1") or 1
local SanctuaryBuilder = req("World.SanctuaryBuilder")
local sanctuaries = Engine.workspace:FindFirstChild("Sanctuaries")
for i, model in sanctuaries:GetChildren() do
	-- Show the full tier progression around the island: plot i gets tier min(i, 5) when tier == 0.
	local t = if tier == 0 then math.min(((i - 1) % 5) + 1, 5) else tier
	SanctuaryBuilder.setTier(model, t)
	for _, pedestal in model.Pedestals:GetChildren() do
		local slot = pedestal:GetAttribute("Slot")
		if slot <= ({ 5, 7, 9, 11, 12 })[t] then
			for _, part in pedestal:GetChildren() do
				if part:IsA("BasePart") then
					part.Transparency = 0
				end
			end
		end
	end
end
Engine.advance(0.5)

local TerrainBuilder = req("World.TerrainBuilder")
local ZONE_MATERIAL = { basin = "Slate", rim = "Grass", meadow = "Grass", river = "Sand", outer = "Grass", edge = "Rock", crown = "Grass" }
local PATH_MATERIAL = { road = "Pavement", spoke = "Cobblestone", plaza = "Slate" }
local samples = {}
local step = 2
local EXTENT = 330
for z = -EXTENT, EXTENT - step, step do
	local row = {}
	for x = -EXTENT, EXTENT - step, step do
		local cx, cz = x + step / 2, z + step / 2
		local s = TerrainBuilder.sample(cx, cz)
		if s then
			local material
			if TerrainBuilder.materialAt then
				material = TerrainBuilder.materialAt(cx, cz).Name
			else
				material = PATH_MATERIAL[s.path or ""] or ZONE_MATERIAL[s.zone] or "Grass"
			end
			table.insert(row, { math.floor(s.height * 10) / 10, s.zone, s.path or "", material })
		else
			table.insert(row, false)
		end
	end
	table.insert(samples, row)
end

-- Terrain fill operations (rocks, islets, underside, carved caves).
local fills = {}
for _, op in Engine.terrainLog or {} do
	local cf = op.cf
	local look, right, up = cf.LookVector, cf.RightVector, cf.UpVector
	table.insert(fills, {
		op = op.op,
		p = { cf.Position.X, cf.Position.Y, cf.Position.Z },
		r = { right.X, right.Y, right.Z },
		u = { up.X, up.Y, up.Z },
		l = { look.X, look.Y, look.Z },
		s = { op.size.X, op.size.Y, op.size.Z },
		m = op.material,
	})
end

local parts = {}
for _, part in Engine.workspace:GetDescendants() do
	if part:IsA("BasePart") and part.Transparency < 0.95 then
		local cf = part.CFrame
		local look = cf.LookVector
		local right = cf.RightVector
		local up = cf.UpVector
		local c = part.Color
		local shape = "Block"
		if part:IsA("Part") then
			shape = part.Shape.Name
		end
		if part:FindFirstChildOfClass("SpecialMesh") then
			shape = "Ellipsoid"
		end
		table.insert(parts, {
			p = { cf.Position.X, cf.Position.Y, cf.Position.Z },
			r = { right.X, right.Y, right.Z },
			u = { up.X, up.Y, up.Z },
			l = { look.X, look.Y, look.Z },
			s = { part.Size.X, part.Size.Y, part.Size.Z },
			c = { math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255) },
			m = part.Material.Name,
			t = part.Transparency,
			shape = shape,
			n = part.Name,
		})
	end
end

-- Art direction palette (Phase 5.5): terrain colours, water and sky for the renderer.
local Palette = Loader.require("server", game:GetService("ReplicatedStorage"):FindFirstChild("Shared"):FindFirstChild("Config"):FindFirstChild("Palette"))
local function rgb(c)
	return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
end
local terrainColors = {}
for name, color in Palette.Terrain do
	terrainColors[name] = rgb(color)
end
local palette = {
	terrain = terrainColors,
	water = rgb(Palette.Water.Color),
	sky = rgb(Palette.Core.Sky),
	horizon = rgb(Palette.Atmosphere.Color),
	clock = Palette.Lighting.ClockTime,
}

local out = process.args[2] or (ROOT .. "/tools/.cache/world.json")
fs.writeFile(out, serde.encode("json", { step = step, origin = -EXTENT, samples = samples, parts = parts, fills = fills, palette = palette }))
print("exported", #parts, "parts")
local _ = thread
