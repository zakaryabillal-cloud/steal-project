--!nocheck
-- Exports every relic (built by the real RelicFactory, faces included) lined
-- up in rows, as a world.json-like file for render_view.py.
--   lune run tools/render/export_relics.luau [out.json]
--   python3 tools/render/render_view.py tools/.cache/relics.json relics.png "0,9,-34" "0,5,0" 1100 520

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")

local Api = require("../../tests/harness/Api")
local Engine = require("../../tests/harness/Engine")
local Loader = require("../../tests/harness/Loader")

local ROOT = process.cwd
Api.load(ROOT .. "/tools/.cache/API-Dump.json")
local game = Engine.createGame()
Loader.mount(game, ROOT .. "/sourcemap.json", ROOT)

local shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
local Factory = Loader.require("client", shared:FindFirstChild("Relics"):FindFirstChild("RelicFactory"))
local Relics = Loader.require("client", shared:FindFirstChild("Config"):FindFirstChild("Relics"))
local Palette = Loader.require("client", shared:FindFirstChild("Config"):FindFirstChild("Palette"))
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

local parts = {}
local perRow = 10
for i, def in Relics.list do
	local visual = Factory.build(def.id, nil, { preview = true, scale = 1 })
	local row = math.floor((i - 1) / perRow)
	local col = (i - 1) % perRow
	local origin = CFrame.new((col - (perRow - 1) / 2) * 5.2, 8 - row * 5.6, row * 2)
	-- Face the camera (which looks toward +Z from -Z).
	visual.root.CFrame = origin
	for _, part in visual.parts do
		local weld = part:FindFirstChildOfClass("Weld")
		local cf = origin * (if weld then weld.C0 else CFrame.identity)
		local look, right, up = cf.LookVector, cf.RightVector, cf.UpVector
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
-- A ground strip so the lineup sits on something.
table.insert(parts, { p = { 0, -6.5, 4 }, r = { 1, 0, 0 }, u = { 0, 1, 0 }, l = { 0, 0, -1 }, s = { 60, 1, 30 }, c = { 98, 214, 92 }, m = "SmoothPlastic", t = 0, shape = "Block", n = "Ground" })

local function rgb(c)
	return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
end
local palette = { terrain = {}, water = rgb(Palette.Water.Color), sky = rgb(Palette.Core.Sky), horizon = rgb(Palette.Atmosphere.Color), clock = Palette.Lighting.ClockTime }
local out = process.args[1] or (ROOT .. "/tools/.cache/relics.json")
fs.writeFile(out, serde.encode("json", { step = 2, origin = 0, samples = {}, parts = parts, fills = {}, palette = palette }))
print("exported", #parts, "relic parts")
