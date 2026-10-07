--!nocheck
-- Fast world-only checks (no players): builds the world and runs the V2
-- world scenarios (budgets, routes, caves, pads, landmarks, V1 core).
--
--   lune run tests/world.luau

local process = require("@lune/process")

local Api = require("./harness/Api")
local Engine = require("./harness/Engine")
local Loader = require("./harness/Loader")

local ROOT = process.cwd
Api.load(ROOT .. "/tools/.cache/API-Dump.json")
local game = Engine.createGame()
Loader.mount(game, ROOT .. "/sourcemap.json", ROOT)

local results = { passed = 0, failed = 0, failures = {} }
local current = ""
local function check(condition, message)
	if condition then
		results.passed += 1
	else
		results.failed += 1
		table.insert(results.failures, current .. ": " .. message)
		print("  \27[31m✗ " .. message .. "\27[0m")
	end
end
local function scenario(name, fn)
	current = name
	print("\n\27[36m▶ " .. name .. "\27[0m")
	local ok, err = xpcall(fn, debug.traceback)
	if not ok then
		check(false, "scenario crashed: " .. tostring(err))
	end
end
local function node(root, path)
	for part in string.gmatch(path, "[^%.]+") do
		root = root:FindFirstChild(part)
	end
	return root
end
local function sreq(path)
	return Loader.require("server", node(game:GetService("ServerScriptService"):FindFirstChild("Server"), path))
end
local function shared(path)
	return Loader.require("server", node(game:GetService("ReplicatedStorage"):FindFirstChild("Shared"), path))
end

local WorldBuilder = sreq("World.WorldBuilder")
Engine.task.spawn(function()
	WorldBuilder.build()
end)
Engine.advance(3)

require("./scenarios/V2World")({
	scenario = scenario,
	check = check,
	advance = function(seconds)
		Engine.advance(seconds)
	end,
	sreq = sreq,
	shared = shared,
	Engine = Engine,
	alice = function()
		return nil
	end,
	noClient = true,
})

print(string.format("\n\27[1m%d passed, %d failed\27[0m", results.passed, results.failed))
for _, failure in results.failures do
	print("  - " .. failure)
end
process.exit(if results.failed == 0 then 0 else 1)
