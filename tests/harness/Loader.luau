--!nocheck
-- Mirrors the Rojo tree (via sourcemap.json) into the fake DataModel and
-- implements Roblox-style `require` with one module cache per realm, so the
-- server and the client each get their own copies of shared modules.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")
local Engine = require("./Engine")

local Loader = {}

local caches = { server = {}, client = {} }
local loading = {}
-- Sources are read up-front from the main thread: Lune's fs calls are async
-- and cannot run inside the harness scheduler's coroutines.
local sources: { [string]: string } = {}

local function pathOf(inst)
	return rawget(inst, "__").props.__path
end

function Loader.mount(game, sourcemapPath: string, root: string)
	local map = serde.decode("json", fs.readFile(sourcemapPath))
	local function build(node, parent)
		local inst = parent:FindFirstChild(node.name)
		if not inst or (node.className ~= "Folder" and inst.ClassName ~= node.className) then
			inst = Engine.createInternal(node.className, node.name, parent)
		end
		for _, path in node.filePaths or {} do
			if string.sub(path, -5) == ".luau" or string.sub(path, -4) == ".lua" then
				local full = root .. "/" .. path
				rawget(inst, "__").props.__path = full
				sources[full] = fs.readFile(full)
			end
		end
		for _, child in node.children or {} do
			build(child, inst)
		end
	end
	for _, child in map.children or {} do
		local service = game:FindFirstChild(child.name)
		if service then
			for _, grandchild in child.children or {} do
				build(grandchild, service)
			end
		end
	end
end

function Loader.require(realm: string, moduleScript)
	assert(Engine.isInstance(moduleScript), "require expects a ModuleScript instance, got " .. Engine.typeof(moduleScript))
	assert(moduleScript.ClassName == "ModuleScript", "require expects a ModuleScript, got " .. moduleScript.ClassName)
	local cache = caches[realm]
	local cached = cache[moduleScript]
	if cached ~= nil then
		return cached.value
	end
	local key = realm .. ":" .. tostring(moduleScript)
	if loading[moduleScript] and loading[moduleScript][realm] then
		error("Requested module was required recursively: " .. moduleScript:GetFullName())
	end
	loading[moduleScript] = loading[moduleScript] or {}
	loading[moduleScript][realm] = true
	local path = pathOf(moduleScript)
	assert(path, "No source for " .. moduleScript:GetFullName() .. " " .. key)
	local env = Engine.environment(realm)
	env.script = moduleScript
	env.require = function(target)
		return Loader.require(realm, target)
	end
	local fn = luau.load(sources[path], { debugName = path, environment = env, injectGlobals = false })
	local packed = table.pack(pcall(fn))
	loading[moduleScript][realm] = nil
	if not packed[1] then
		error("Error loading " .. moduleScript:GetFullName() .. ": " .. tostring(packed[2]), 0)
	end
	local results = table.pack(table.unpack(packed, 2, packed.n))
	if results.n ~= 1 then
		error("Module code did not return exactly one value: " .. path)
	end
	cache[moduleScript] = { value = results[1] }
	return results[1]
end

function Loader.run(realm: string, scriptInstance)
	local path = pathOf(scriptInstance)
	assert(path, "No source for " .. scriptInstance:GetFullName())
	local env = Engine.environment(realm)
	env.script = scriptInstance
	env.require = function(target)
		return Loader.require(realm, target)
	end
	local fn = luau.load(sources[path], { debugName = path, environment = env, injectGlobals = false })
	return Engine.task.spawn(fn)
end

return Loader
