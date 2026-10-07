--!nocheck
-- Exports the generated world (terrain samples + part footprints) to JSON so
-- tools/render/render_map.py can draw a top-down overview image.
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
local samples = {}
local step = 2
for z = -260, 260 - step, step do
	local row = {}
	for x = -260, 260 - step, step do
		local s = TerrainBuilder.sample(x + step / 2, z + step / 2)
		if s then
			table.insert(row, { math.floor(s.height * 10) / 10, s.zone, s.path or "" })
		else
			table.insert(row, false)
		end
	end
	table.insert(samples, row)
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

fs.writeFile(ROOT .. "/tools/.cache/world.json", serde.encode("json", { step = step, origin = -260, samples = samples, parts = parts }))
print("exported", #parts, "parts")
local _ = thread
