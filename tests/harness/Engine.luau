--!nocheck
-- A small headless stand-in for the Roblox engine, good enough to execute
-- RIFT HEIST's real server and client code:
--   * virtual-time task scheduler (task.spawn/defer/delay/wait/cancel)
--   * deferred event dispatch (like SignalBehavior.Deferred)
--   * instances validated against the real API dump (unknown members,
--     wrong value types, read-only / non-scriptable writes all error)
--   * fake services: Players, DataStoreService, RunService, TweenService...
-- It is NOT a physics or rendering engine; tests move characters directly.

local roblox = require("@lune/roblox")
local Api = require("./Api")

local Engine = {}

Engine.now = 0
Engine.errors = {}
Engine.log = {}
Engine.verbose = false

local BASE_TIME = 1_750_000_000

----------------------------------------------------------------------------
-- Scheduler
----------------------------------------------------------------------------

local queue = {}
local sequence = 0
local cancelled = setmetatable({}, { __mode = "k" })
local threadNames = setmetatable({}, { __mode = "k" })

local function reportError(thread, err)
	local trace = debug.traceback(thread, tostring(err))
	table.insert(Engine.errors, trace)
	print("\27[31m[ERROR]\27[0m " .. trace)
end

local function resume(thread, ...)
	if cancelled[thread] or coroutine.status(thread) ~= "suspended" then
		return
	end
	local ok, err = coroutine.resume(thread, ...)
	if not ok then
		reportError(thread, err)
	end
end

local function schedule(time, thread, args)
	sequence += 1
	table.insert(queue, { time = time, seq = sequence, thread = thread, args = args })
end

local function toThread(fn)
	if type(fn) == "thread" then
		return fn
	end
	return coroutine.create(fn)
end

local task = {}

function task.spawn(fn, ...)
	local thread = toThread(fn)
	resume(thread, ...)
	return thread
end

function task.defer(fn, ...)
	local thread = toThread(fn)
	schedule(Engine.now, thread, table.pack(...))
	return thread
end

function task.delay(seconds, fn, ...)
	local thread = toThread(fn)
	schedule(Engine.now + math.max(seconds or 0, 0), thread, table.pack(...))
	return thread
end

function task.wait(seconds)
	local thread = coroutine.running()
	local start = Engine.now
	schedule(Engine.now + math.max(seconds or 0, 1 / 60), thread, table.pack())
	coroutine.yield()
	return Engine.now - start
end

function task.cancel(thread)
	cancelled[thread] = true
end

function task.synchronize() end
function task.desynchronize() end

Engine.task = task

-- Runs everything scheduled up to `untilTime` (virtual seconds).
function Engine.runUntil(untilTime: number)
	while true do
		local bestIndex, best = nil, nil
		for index, item in queue do
			if item.time <= untilTime and (best == nil or item.time < best.time or (item.time == best.time and item.seq < best.seq)) then
				bestIndex, best = index, item
			end
		end
		if not best then
			break
		end
		table.remove(queue, bestIndex)
		if best.time > Engine.now then
			Engine.now = best.time
		end
		resume(best.thread, table.unpack(best.args, 1, best.args.n))
	end
	if untilTime > Engine.now then
		Engine.now = untilTime
	end
end

----------------------------------------------------------------------------
-- Signals
----------------------------------------------------------------------------

local SignalMeta = {}
SignalMeta.__index = SignalMeta
local ConnectionMeta = {}
ConnectionMeta.__index = ConnectionMeta

local signalTag = setmetatable({}, { __mode = "k" })
local connectionTag = setmetatable({}, { __mode = "k" })

function Engine.newSignal(name)
	local signal = setmetatable({ _connections = {}, _name = name or "Signal" }, SignalMeta)
	signalTag[signal] = true
	return signal
end

function ConnectionMeta:Disconnect()
	self.Connected = false
	local list = self._signal._connections
	local index = table.find(list, self)
	if index then
		table.remove(list, index)
	end
end

function SignalMeta:Connect(fn)
	assert(type(fn) == "function", "Connect expects a function")
	local connection = setmetatable({ Connected = true, _signal = self, _fn = fn }, ConnectionMeta)
	connectionTag[connection] = true
	table.insert(self._connections, connection)
	return connection
end

function SignalMeta:Once(fn)
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		fn(...)
	end)
	return connection
end

function SignalMeta:Wait()
	local thread = coroutine.running()
	self:Once(function(...)
		resume(thread, ...)
	end)
	return coroutine.yield()
end

-- Deferred dispatch: handlers run on the next scheduler pass at the same time.
function SignalMeta:Fire(...)
	for _, connection in table.clone(self._connections) do
		if connection.Connected then
			task.defer(connection._fn, ...)
		end
	end
end

-- Immediate dispatch (used for RunService frame events).
function SignalMeta:FireNow(...)
	for _, connection in table.clone(self._connections) do
		if connection.Connected then
			task.spawn(connection._fn, ...)
		end
	end
end

----------------------------------------------------------------------------
-- Datatypes not provided by Lune
----------------------------------------------------------------------------

local RandomMeta = {}
RandomMeta.__index = RandomMeta
local randomTag = setmetatable({}, { __mode = "k" })

local function nextState(self)
	-- xorshift32
	local x = self._state
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	self._state = x
	return x / 4294967296
end

local RandomLib = {}
local seedCounter = 12345
function RandomLib.new(seed)
	seedCounter += 7919
	local state = math.floor(math.abs(seed or seedCounter)) % 4294967296
	if state == 0 then
		state = 2463534242
	end
	local self = setmetatable({ _state = state }, RandomMeta)
	randomTag[self] = true
	for _ = 1, 4 do
		nextState(self)
	end
	return self
end
function RandomMeta:NextNumber(min, max)
	local r = nextState(self)
	if min == nil then
		return r
	end
	return min + (max - min) * r
end
function RandomMeta:NextInteger(min, max)
	return math.floor(min + (max - min + 1) * nextState(self))
end

local TweenInfoLib = {}
function TweenInfoLib.new(time, style, direction, repeatCount, reverses, delayTime)
	return { Time = time or 1, EasingStyle = style, EasingDirection = direction, RepeatCount = repeatCount or 0, Reverses = reverses or false, DelayTime = delayTime or 0 }
end

-- Lune's CFrame.lookAt flips the Z axis and its two-colour ColorSequence
-- constructor drops the second colour; these wrappers restore Roblox semantics.
local function lookAt(at, target, up)
	local look = target - at
	if look.Magnitude < 1e-6 then
		return roblox.CFrame.new(at)
	end
	look = look.Unit
	up = up or roblox.Vector3.yAxis
	local right = look:Cross(up)
	if right.Magnitude < 1e-6 then
		right = look:Cross(roblox.Vector3.zAxis)
	end
	right = right.Unit
	local newUp = right:Cross(look).Unit
	return roblox.CFrame.fromMatrix(at, right, newUp, -look)
end
Engine.CFrame = setmetatable({ lookAt = lookAt }, { __index = roblox.CFrame })
Engine.ColorSequence = setmetatable({
	new = function(a, b)
		if b ~= nil and typeof(a) == "Color3" then
			return roblox.ColorSequence.new({ roblox.ColorSequenceKeypoint.new(0, a), roblox.ColorSequenceKeypoint.new(1, b) })
		end
		return roblox.ColorSequence.new(a)
	end,
}, { __index = roblox.ColorSequence })

----------------------------------------------------------------------------
-- Instances
----------------------------------------------------------------------------

local InstanceMeta = {}
local instanceTag = setmetatable({}, { __mode = "k" })
Engine.instanceTag = instanceTag

local function internal(inst)
	return rawget(inst, "__")
end

local function isInstance(value)
	return type(value) == "table" and instanceTag[value] == true
end
Engine.isInstance = isInstance

local function typeOf(value)
	if isInstance(value) then
		return "Instance"
	elseif type(value) == "table" and signalTag[value] then
		return "RBXScriptSignal"
	elseif type(value) == "table" and connectionTag[value] then
		return "RBXScriptConnection"
	elseif type(value) == "table" and randomTag[value] then
		return "Random"
	end
	return typeof(value)
end
Engine.typeof = typeOf

local DEFAULTS = {
	["Humanoid.Health"] = 100,
	["Humanoid.MaxHealth"] = 100,
	["Humanoid.WalkSpeed"] = 16,
	["Humanoid.JumpHeight"] = 7.2,
	["Humanoid.HipHeight"] = 2,
	["BasePart.Size"] = roblox.Vector3.new(4, 1, 2),
	["BasePart.CanCollide"] = true,
	["BasePart.CanQuery"] = true,
	["BasePart.CanTouch"] = true,
	["BasePart.CastShadow"] = true,
	["ProximityPrompt.Enabled"] = true,
	["ProximityPrompt.MaxActivationDistance"] = 10,
	["ProximityPrompt.KeyboardKeyCode"] = roblox.Enum.KeyCode.E,
	["ProximityPrompt.GamepadKeyCode"] = roblox.Enum.KeyCode.ButtonX,
	["ProximityPrompt.Style"] = roblox.Enum.ProximityPromptStyle.Default,
	["Light.Enabled"] = true,
	["Light.Brightness"] = 1,
	["PointLight.Range"] = 8,
	["ParticleEmitter.Enabled"] = true,
	["ParticleEmitter.Rate"] = 5,
	["Beam.Enabled"] = true,
	["Trail.Enabled"] = true,
	["Sound.Volume"] = 0.5,
	["Sound.PlaybackSpeed"] = 1,
	["GuiObject.Visible"] = true,
	["GuiObject.Size"] = roblox.UDim2.fromOffset(100, 100),
	["LayerCollector.Enabled"] = true,
	["LayerCollector.ResetOnSpawn"] = true,
	["SpawnLocation.Enabled"] = true,
	["Camera.FieldOfView"] = 70,
	["Camera.ViewportSize"] = roblox.Vector2.new(1280, 720),
	["Camera.CameraType"] = roblox.Enum.CameraType.Custom,
	["Workspace.Gravity"] = 196.2,
	["UIScale.Scale"] = 1,
	["UIStroke.Thickness"] = 1,
	["UIStroke.Color"] = roblox.Color3.new(0, 0, 0),
	["SoundGroup.Volume"] = 0.5,
	["Highlight.FillTransparency"] = 0.5,
	["BillboardGui.Size"] = roblox.UDim2.new(),
	["Attachment.CFrame"] = roblox.CFrame.new(),
	["UserInputService.KeyboardEnabled"] = true,
	["UserInputService.TouchEnabled"] = false,
	["TextLabel.TextSize"] = 14,
}

local enumCache = {}
local function enumDefault(name)
	if enumCache[name] == nil then
		local ok, items = pcall(function()
			return roblox.Enum[name]:GetEnumItems()
		end)
		enumCache[name] = if ok and items and items[1] then items[1] else false
	end
	return enumCache[name] or nil
end

local function typeDefault(valueType)
	if not valueType then
		return nil
	end
	local category, name = valueType.Category, valueType.Name
	if category == "Primitive" then
		if name == "bool" then
			return false
		elseif name == "string" then
			return ""
		else
			return 0
		end
	elseif category == "Enum" then
		return enumDefault(name)
	elseif category == "DataType" then
		local map = {
			Vector3 = roblox.Vector3.zero,
			Vector2 = roblox.Vector2.new(0, 0),
			CFrame = roblox.CFrame.new(),
			CoordinateFrame = roblox.CFrame.new(),
			Color3 = roblox.Color3.new(1, 1, 1),
			UDim2 = roblox.UDim2.new(),
			UDim = roblox.UDim.new(0, 0),
			NumberRange = roblox.NumberRange.new(0),
			NumberSequence = roblox.NumberSequence.new(0),
			ColorSequence = roblox.ColorSequence.new(roblox.Color3.new(1, 1, 1)),
			Content = "",
			ContentId = "",
			Font = roblox.Font.new("rbxasset://fonts/families/BuilderSans.json"),
			Rect = nil,
		}
		return map[name]
	end
	return nil
end

local function defaultFor(className, propName, member)
	local class = Api.class(className)
	while class do
		local value = DEFAULTS[class.name .. "." .. propName]
		if value ~= nil then
			return value
		end
		class = Api.class(class.superclass)
	end
	return typeDefault(member and member.valueType)
end

local DATATYPE_ALIASES = { CoordinateFrame = "CFrame", Content = "string", ContentId = "string", BinaryString = "string", ProtectedString = "string" }

local function checkValue(className, propName, member, value)
	local vt = member.valueType
	if value == nil or not vt then
		return
	end
	local category, name = vt.Category, vt.Name
	local actual = typeOf(value)
	local ok = true
	if category == "Primitive" then
		if name == "bool" then
			ok = actual == "boolean"
		elseif name == "string" then
			ok = actual == "string"
		else
			ok = actual == "number"
		end
	elseif category == "Enum" then
		ok = actual == "EnumItem" and string.find(tostring(value), "Enum." .. name .. ".", 1, true) ~= nil
	elseif category == "DataType" then
		local expected = DATATYPE_ALIASES[name] or name
		if name == "Content" or name == "ContentId" then
			ok = actual == "string" or actual == "Content"
		else
			ok = actual == expected
		end
	elseif category == "Class" then
		ok = actual == "Instance"
	end
	if not ok then
		error(string.format("Unable to assign property %s.%s. %s expected, got %s", className, propName, name, actual), 3)
	end
end

local GETTERS = {}
local SETTERS = {}
local METHODS = {}

local function fireAttr(inst, name)
	local data = internal(inst)
	local signal = data.attrSignals[name]
	if signal then
		signal:Fire()
	end
	if data.signals.AttributeChanged then
		data.signals.AttributeChanged:Fire(name)
	end
end

local function fireProp(inst, name)
	local data = internal(inst)
	local signal = data.propSignals[name]
	if signal then
		signal:Fire()
	end
	if data.signals.Changed then
		data.signals.Changed:Fire(name)
	end
end

local function getSignal(inst, name)
	local data = internal(inst)
	local signal = data.signals[name]
	if not signal then
		signal = Engine.newSignal(data.className .. "." .. name)
		data.signals[name] = signal
	end
	return signal
end
Engine.signal = getSignal

local function findMethod(className, name)
	local class = Api.class(className)
	while class do
		local fn = METHODS[class.name .. "." .. name]
		if fn then
			return fn
		end
		class = Api.class(class.superclass)
	end
	return nil
end

InstanceMeta.__index = function(inst, key)
	local data = internal(inst)
	if key == "ClassName" then
		return data.className
	elseif key == "Name" then
		return data.name
	elseif key == "Parent" then
		return data.parent
	end
	local member = Api.member(data.className, key)
	if member then
		if member.tags.NotScriptable then
			error(string.format("%s is not a valid member of %s (not scriptable)", key, data.className), 2)
		end
		if member.kind == "Property" then
			local getter = GETTERS[data.className .. "." .. key] or GETTERS["*." .. key]
			if getter then
				return getter(inst)
			end
			local value = data.props[key]
			if value == nil then
				return defaultFor(data.className, key, member)
			end
			return value
		elseif member.kind == "Event" then
			return getSignal(inst, key)
		elseif member.kind == "Function" or member.kind == "YieldFunction" then
			local fn = findMethod(data.className, key)
			if not fn then
				return function()
					error(string.format("[harness] %s:%s is not implemented", data.className, key), 2)
				end
			end
			return fn
		elseif member.kind == "Callback" then
			return data.props[key]
		end
	end
	for _, child in data.children do
		if internal(child).name == key then
			return child
		end
	end
	error(string.format("%s is not a valid member of %s \"%s\"", tostring(key), data.className, data.name), 2)
end

local reparent

InstanceMeta.__newindex = function(inst, key, value)
	local data = internal(inst)
	if key == "Parent" then
		reparent(inst, value)
		return
	elseif key == "Name" then
		data.name = tostring(value)
		fireProp(inst, "Name")
		return
	end
	local member = Api.member(data.className, key)
	if not member then
		error(string.format("%s is not a valid member of %s", tostring(key), data.className), 2)
	end
	if member.tags.NotScriptable then
		error(string.format("%s is not a valid member of %s (not scriptable)", key, data.className), 2)
	end
	if member.kind == "Callback" then
		data.props[key] = value
		return
	end
	if member.kind ~= "Property" then
		error(string.format("Cannot assign to %s.%s (%s)", data.className, key, member.kind), 2)
	end
	if member.tags.ReadOnly or (member.writeSecurity ~= "None" and member.writeSecurity ~= nil) then
		error(string.format("Unable to assign property %s. Property is read only", key), 2)
	end
	checkValue(data.className, key, member, value)
	local setter = SETTERS[data.className .. "." .. key] or SETTERS["*." .. key]
	if setter then
		setter(inst, value)
	else
		data.props[key] = value
	end
	fireProp(inst, key)
end

InstanceMeta.__tostring = function(inst)
	return internal(inst).name
end

local InstanceLib = {}

local function newInstance(className, internalCreate)
	if not internalCreate and not Api.creatable(className) then
		error("Unable to create an Instance of type \"" .. tostring(className) .. "\"", 2)
	end
	assert(Api.class(className), "Unknown class " .. tostring(className))
	local data = {
		className = className,
		name = className,
		parent = nil,
		children = {},
		props = {},
		attrs = {},
		signals = {},
		attrSignals = {},
		propSignals = {},
		destroyed = false,
	}
	local inst = setmetatable({ __ = data }, InstanceMeta)
	instanceTag[inst] = true
	return inst
end

function InstanceLib.new(className, parent)
	local inst = newInstance(className, false)
	if parent then
		inst.Parent = parent
	end
	return inst
end

Engine.createInternal = function(className, name, parent)
	local inst = newInstance(className, true)
	internal(inst).name = name or className
	if parent then
		reparent(inst, parent)
	end
	return inst
end

-- Bypasses read-only checks (engine-owned properties).
function Engine.set(inst, key, value)
	internal(inst).props[key] = value
	fireProp(inst, key)
end

local function descendants(inst, out)
	for _, child in internal(inst).children do
		table.insert(out, child)
		descendants(child, out)
	end
	return out
end

local function isDescendantOf(inst, ancestor)
	local parent = internal(inst).parent
	while parent do
		if parent == ancestor then
			return true
		end
		parent = internal(parent).parent
	end
	return false
end

reparent = function(inst, newParent)
	local data = internal(inst)
	if data.destroyed and newParent ~= nil then
		error("The Parent property of " .. data.name .. " is locked", 3)
	end
	if newParent ~= nil and not isInstance(newParent) then
		error("Parent must be an Instance", 3)
	end
	if newParent == inst or (newParent and isDescendantOf(newParent, inst)) then
		error("Attempt to set parent of " .. data.name .. " would result in circular reference", 3)
	end
	local old = data.parent
	if old == newParent then
		return
	end
	if old then
		local list = internal(old).children
		local index = table.find(list, inst)
		if index then
			table.remove(list, index)
		end
		getSignal(old, "ChildRemoved"):Fire(inst)
	end
	data.parent = newParent
	if newParent then
		table.insert(internal(newParent).children, inst)
		getSignal(newParent, "ChildAdded"):Fire(inst)
		local ancestor = newParent
		local added = descendants(inst, { inst })
		while ancestor do
			local signal = internal(ancestor).signals.DescendantAdded
			if signal then
				for _, d in added do
					signal:Fire(d)
				end
			end
			ancestor = internal(ancestor).parent
		end
	end
	local all = descendants(inst, { inst })
	for _, d in all do
		local signal = internal(d).signals.AncestryChanged
		if signal then
			signal:Fire(inst, newParent)
		end
	end
	fireProp(inst, "Parent")
end

----------------------------------------------------------------------------
-- Generic methods
----------------------------------------------------------------------------

METHODS["Instance.FindFirstChild"] = function(inst, name, recursive)
	for _, child in internal(inst).children do
		if internal(child).name == name then
			return child
		end
	end
	if recursive then
		for _, d in descendants(inst, {}) do
			if internal(d).name == name then
				return d
			end
		end
	end
	return nil
end

METHODS["Instance.FindFirstChildOfClass"] = function(inst, className)
	for _, child in internal(inst).children do
		if internal(child).className == className then
			return child
		end
	end
	return nil
end

METHODS["Instance.FindFirstChildWhichIsA"] = function(inst, className, recursive)
	local list = if recursive then descendants(inst, {}) else internal(inst).children
	for _, child in list do
		if Api.isA(internal(child).className, className) then
			return child
		end
	end
	return nil
end

METHODS["Instance.FindFirstAncestorOfClass"] = function(inst, className)
	local parent = internal(inst).parent
	while parent do
		if internal(parent).className == className then
			return parent
		end
		parent = internal(parent).parent
	end
	return nil
end

METHODS["Instance.WaitForChild"] = function(inst, name, timeout)
	local start = Engine.now
	local warned = false
	while true do
		local child = METHODS["Instance.FindFirstChild"](inst, name)
		if child then
			return child
		end
		if timeout and Engine.now - start >= timeout then
			return nil
		end
		if not warned and Engine.now - start > 10 then
			warned = true
			print("[harness] Infinite yield possible on " .. internal(inst).name .. ":WaitForChild(\"" .. name .. "\")")
		end
		task.wait(0.05)
	end
end

METHODS["Instance.GetChildren"] = function(inst)
	return table.clone(internal(inst).children)
end

METHODS["Instance.GetDescendants"] = function(inst)
	return descendants(inst, {})
end

METHODS["Instance.IsA"] = function(inst, className)
	return Api.isA(internal(inst).className, className)
end

METHODS["Instance.IsDescendantOf"] = function(inst, ancestor)
	return isDescendantOf(inst, ancestor)
end

METHODS["Instance.IsAncestorOf"] = function(inst, descendant)
	return isDescendantOf(descendant, inst)
end

METHODS["Instance.Destroy"] = function(inst)
	local data = internal(inst)
	if data.destroyed then
		return
	end
	if data.signals.Destroying then
		data.signals.Destroying:Fire()
	end
	for _, child in table.clone(data.children) do
		METHODS["Instance.Destroy"](child)
	end
	reparent(inst, nil)
	data.destroyed = true
	for _, signal in data.signals do
		-- Roblox disconnects everything on Destroy (after Destroying fired).
		task.defer(function()
			for _, connection in table.clone(signal._connections) do
				connection:Disconnect()
			end
		end)
	end
end

METHODS["Instance.ClearAllChildren"] = function(inst)
	for _, child in table.clone(internal(inst).children) do
		METHODS["Instance.Destroy"](child)
	end
end

METHODS["Instance.GetFullName"] = function(inst)
	local parts = {}
	local current = inst
	while current and internal(current).className ~= "DataModel" do
		table.insert(parts, 1, internal(current).name)
		current = internal(current).parent
	end
	return table.concat(parts, ".")
end

local ATTRIBUTE_TYPES = {
	string = true, boolean = true, number = true, UDim = true, UDim2 = true, BrickColor = true, Color3 = true,
	Vector2 = true, Vector3 = true, CFrame = true, NumberSequence = true, ColorSequence = true, NumberRange = true,
	Rect = true, Font = true, EnumItem = true,
}

METHODS["Instance.SetAttribute"] = function(inst, name, value)
	if type(name) ~= "string" then
		error("SetAttribute name must be a string", 2)
	end
	if value ~= nil and not ATTRIBUTE_TYPES[typeOf(value)] then
		error("SetAttribute: " .. typeOf(value) .. " is not a supported attribute type", 2)
	end
	if value ~= value then
		error("SetAttribute: NaN", 2)
	end
	local data = internal(inst)
	if data.attrs[name] == value then
		return
	end
	data.attrs[name] = value
	fireAttr(inst, name)
end

METHODS["Instance.GetAttribute"] = function(inst, name)
	return internal(inst).attrs[name]
end

METHODS["Instance.GetAttributes"] = function(inst)
	return table.clone(internal(inst).attrs)
end

METHODS["Instance.GetAttributeChangedSignal"] = function(inst, name)
	local data = internal(inst)
	local signal = data.attrSignals[name]
	if not signal then
		signal = Engine.newSignal("AttributeChanged:" .. name)
		data.attrSignals[name] = signal
	end
	return signal
end

METHODS["Instance.GetPropertyChangedSignal"] = function(inst, name)
	local data = internal(inst)
	if not Api.member(data.className, name) and name ~= "Parent" and name ~= "Name" then
		error(name .. " is not a valid property name.", 2)
	end
	local signal = data.propSignals[name]
	if not signal then
		signal = Engine.newSignal("PropertyChanged:" .. name)
		data.propSignals[name] = signal
	end
	return signal
end

METHODS["Instance.Clone"] = function(inst)
	local data = internal(inst)
	local copy = newInstance(data.className, true)
	local copyData = internal(copy)
	copyData.name = data.name
	copyData.props = table.clone(data.props)
	copyData.attrs = table.clone(data.attrs)
	for _, child in data.children do
		local childCopy = METHODS["Instance.Clone"](child)
		reparent(childCopy, copy)
	end
	return copy
end

-- Geometry helpers ----------------------------------------------------------

GETTERS["BasePart.Position"] = function(inst)
	local cf = internal(inst).props.CFrame or roblox.CFrame.new()
	return cf.Position
end
for _, class in { "Part", "WedgePart", "CornerWedgePart", "SpawnLocation", "MeshPart", "Terrain", "TrussPart", "Seat" } do
	GETTERS[class .. ".Position"] = GETTERS["BasePart.Position"]
end
SETTERS["*.Position"] = function(inst, value)
	local data = internal(inst)
	if Api.isA(data.className, "BasePart") then
		local cf = data.props.CFrame or roblox.CFrame.new()
		data.props.CFrame = roblox.CFrame.new(value) * cf.Rotation
		fireProp(inst, "CFrame")
	else
		data.props.Position = value
	end
end
GETTERS["Attachment.WorldPosition"] = function(inst)
	local data = internal(inst)
	local parent = data.parent
	local local_cf = data.props.CFrame or roblox.CFrame.new()
	if parent and Api.isA(internal(parent).className, "BasePart") then
		return ((internal(parent).props.CFrame or roblox.CFrame.new()) * local_cf).Position
	end
	return local_cf.Position
end
SETTERS["Attachment.WorldPosition"] = function(inst, value)
	local data = internal(inst)
	local parent = data.parent
	local parentCf = if parent and Api.isA(internal(parent).className, "BasePart") then (internal(parent).props.CFrame or roblox.CFrame.new()) else roblox.CFrame.new()
	local rotation = (data.props.CFrame or roblox.CFrame.new()).Rotation
	data.props.CFrame = roblox.CFrame.new(parentCf:PointToObjectSpace(value)) * rotation
end
GETTERS["Attachment.Position"] = function(inst)
	return (internal(inst).props.CFrame or roblox.CFrame.new()).Position
end
SETTERS["Attachment.Position"] = function(inst, value)
	local data = internal(inst)
	local rotation = (data.props.CFrame or roblox.CFrame.new()).Rotation
	data.props.CFrame = roblox.CFrame.new(value) * rotation
end
GETTERS["GuiBase2d.AbsoluteSize"] = function()
	return roblox.Vector2.new(100, 100)
end
GETTERS["GuiBase2d.AbsolutePosition"] = function()
	return roblox.Vector2.new(0, 0)
end
for _, class in { "Frame", "TextLabel", "TextButton", "ImageLabel", "ImageButton", "ViewportFrame", "ScrollingFrame", "CanvasGroup", "ScreenGui", "BillboardGui" } do
	GETTERS[class .. ".AbsoluteSize"] = GETTERS["GuiBase2d.AbsoluteSize"]
	GETTERS[class .. ".AbsolutePosition"] = GETTERS["GuiBase2d.AbsolutePosition"]
end

local function pivotOf(inst)
	local data = internal(inst)
	if Api.isA(data.className, "BasePart") then
		return data.props.CFrame or roblox.CFrame.new()
	end
	local primary = data.props.PrimaryPart
	if primary then
		return internal(primary).props.CFrame or roblox.CFrame.new()
	end
	for _, d in descendants(inst, {}) do
		if Api.isA(internal(d).className, "BasePart") then
			return internal(d).props.CFrame or roblox.CFrame.new()
		end
	end
	return roblox.CFrame.new()
end

METHODS["PVInstance.GetPivot"] = function(inst)
	return pivotOf(inst)
end

METHODS["PVInstance.PivotTo"] = function(inst, target)
	local data = internal(inst)
	if Api.isA(data.className, "BasePart") then
		inst.CFrame = target
		return
	end
	local delta = target * pivotOf(inst):Inverse()
	for _, d in descendants(inst, {}) do
		if Api.isA(internal(d).className, "BasePart") then
			local dd = internal(d)
			dd.props.CFrame = delta * (dd.props.CFrame or roblox.CFrame.new())
			fireProp(d, "CFrame")
		end
	end
end

----------------------------------------------------------------------------
-- Class-specific methods
----------------------------------------------------------------------------

SETTERS["Humanoid.Health"] = function(inst, value)
	local data = internal(inst)
	local before = data.props.Health or 100
	data.props.Health = math.clamp(value, 0, 100)
	if before > 0 and data.props.Health <= 0 then
		getSignal(inst, "Died"):Fire()
	end
end
METHODS["Humanoid.ChangeState"] = function() end
METHODS["Humanoid.TakeDamage"] = function(inst, amount)
	inst.Health = inst.Health - amount
end
GETTERS["Humanoid.MoveDirection"] = function()
	return roblox.Vector3.zero
end

METHODS["Sound.Play"] = function(inst)
	internal(inst).props.__playing = true
	task.delay(0.5, function()
		internal(inst).props.__playing = false
		getSignal(inst, "Ended"):Fire(inst.SoundId)
	end)
end
METHODS["Sound.Stop"] = function(inst)
	internal(inst).props.__playing = false
end
GETTERS["Sound.IsPlaying"] = function(inst)
	return internal(inst).props.__playing == true
end
METHODS["ParticleEmitter.Emit"] = function() end
METHODS["ParticleEmitter.Clear"] = function() end

METHODS["Workspace.GetServerTimeNow"] = function()
	return BASE_TIME + Engine.now
end
METHODS["Workspace.BulkMoveTo"] = function(_, parts, cframes)
	for i, part in parts do
		part.CFrame = cframes[i]
	end
end

local terrainOps = 0
for _, name in { "WriteVoxels", "FillBall", "FillCylinder", "FillBlock", "FillWedge", "Clear", "SetMaterialColor" } do
	METHODS["Terrain." .. name] = function(_, ...)
		terrainOps += 1
		if name == "WriteVoxels" then
			local region, resolution, materials, occupancy = ...
			assert(resolution == 4, "WriteVoxels resolution must be 4")
			assert(typeOf(region) == "Region3", "WriteVoxels expects Region3")
			local size = region.Size / 4
			assert(#materials == size.X and #materials[1] == size.Y and #materials[1][1] == size.Z, "WriteVoxels materials size mismatch")
			assert(#occupancy == size.X and #occupancy[1] == size.Y and #occupancy[1][1] == size.Z, "WriteVoxels occupancy size mismatch")
			for x = 1, size.X do
				for y = 1, size.Y do
					for z = 1, size.Z do
						local occ = occupancy[x][y][z]
						assert(type(occ) == "number" and occ >= 0 and occ <= 1, "bad occupancy")
						assert(typeOf(materials[x][y][z]) == "EnumItem", "bad material")
					end
				end
			end
		end
	end
end
Engine.terrainOps = function()
	return terrainOps
end

METHODS["HttpService.GenerateGUID"] = function(_, wrap)
	local hex = "0123456789ABCDEF"
	local function chunk(n)
		local s = {}
		for _ = 1, n do
			local i = math.random(1, 16)
			table.insert(s, string.sub(hex, i, i))
		end
		return table.concat(s)
	end
	local guid = chunk(8) .. "-" .. chunk(4) .. "-" .. chunk(4) .. "-" .. chunk(4) .. "-" .. chunk(12)
	return if wrap == false then guid else "{" .. guid .. "}"
end

METHODS["PhysicsService.RegisterCollisionGroup"] = function(inst, name)
	internal(inst).props["__group_" .. name] = true
end
METHODS["PhysicsService.IsCollisionGroupRegistered"] = function(inst, name)
	return internal(inst).props["__group_" .. name] == true or name == "Default"
end
METHODS["PhysicsService.CollisionGroupSetCollidable"] = function(inst, a, b)
	assert(METHODS["PhysicsService.IsCollisionGroupRegistered"](inst, a) and METHODS["PhysicsService.IsCollisionGroupRegistered"](inst, b), "collision group not registered")
end

METHODS["RunService.IsStudio"] = function()
	return true
end
METHODS["RunService.IsServer"] = function()
	return true
end
METHODS["RunService.IsClient"] = function()
	return true
end
METHODS["RunService.BindToRenderStep"] = function(inst, name, _priority, fn)
	local data = internal(inst)
	data.props["__bind_" .. name] = getSignal(inst, "RenderStepped"):Connect(fn)
end
METHODS["RunService.UnbindFromRenderStep"] = function(inst, name)
	local connection = internal(inst).props["__bind_" .. name]
	if connection then
		connection:Disconnect()
	end
end

METHODS["Players.GetPlayers"] = function(inst)
	local list = {}
	for _, child in internal(inst).children do
		if internal(child).className == "Player" then
			table.insert(list, child)
		end
	end
	return list
end
METHODS["Players.GetPlayerByUserId"] = function(inst, userId)
	for _, player in METHODS["Players.GetPlayers"](inst) do
		if player.UserId == userId then
			return player
		end
	end
	return nil
end
METHODS["Players.GetUserThumbnailAsync"] = function(_, userId)
	return "rbxthumb://type=AvatarHeadShot&id=" .. tostring(userId) .. "&w=100&h=100", true
end

METHODS["Player.Kick"] = function(inst, message)
	Engine.log[#Engine.log + 1] = "Kick " .. inst.Name .. ": " .. tostring(message)
	if Engine.onKick then
		Engine.onKick(inst)
	end
end
METHODS["Player.LoadCharacterAsync"] = function(inst)
	Engine.spawnCharacter(inst)
end
METHODS["Player.LoadCharacter"] = METHODS["Player.LoadCharacterAsync"]

METHODS["Camera.WorldToViewportPoint"] = function(_, position)
	return roblox.Vector3.new(640, 360, 10), true
end
METHODS["Camera.WorldToScreenPoint"] = METHODS["Camera.WorldToViewportPoint"]
METHODS["Camera.ViewportPointToRay"] = function()
	return roblox.Ray.new(roblox.Vector3.zero, roblox.Vector3.new(0, 0, -1))
end

METHODS["GuiService.GetGuiInset"] = function()
	return roblox.Vector2.new(0, 58), roblox.Vector2.new(0, 0)
end

METHODS["StarterGui.SetCoreGuiEnabled"] = function() end
METHODS["StarterGui.SetCore"] = function() end

METHODS["ProximityPrompt.InputHoldBegin"] = function(inst)
	getSignal(inst, "PromptButtonHoldBegan"):Fire(Engine.localPlayer)
end
METHODS["ProximityPrompt.InputHoldEnd"] = function(inst)
	getSignal(inst, "PromptButtonHoldEnded"):Fire(Engine.localPlayer)
end

-- TweenService: validates property names, applies the goal when finished.
METHODS["TweenService.Create"] = function(_, target, info, goal)
	assert(isInstance(target), "TweenService:Create target must be an Instance")
	for key, value in goal do
		local member = Api.member(target.ClassName, key)
		if not member or member.kind ~= "Property" then
			error("TweenService:Create no property named '" .. tostring(key) .. "' for " .. target.ClassName, 2)
		end
		checkValue(target.ClassName, key, member, value)
	end
	local tween = Engine.createInternal("Tween", "Tween")
	local tdata = internal(tween)
	tdata.props.__target = target
	tdata.props.__goal = goal
	tdata.props.__time = (info and info.Time or 1) + (info and info.DelayTime or 0)
	return tween
end
METHODS["TweenBase.Play"] = function(tween)
	local tdata = internal(tween)
	tdata.props.__token = (tdata.props.__token or 0) + 1
	local token = tdata.props.__token
	task.delay(tdata.props.__time, function()
		if tdata.props.__token ~= token then
			return
		end
		local target = tdata.props.__target
		if not internal(target).destroyed then
			for key, value in tdata.props.__goal do
				target[key] = value
			end
		end
		getSignal(tween, "Completed"):Fire(roblox.Enum.PlaybackState.Completed)
	end)
end
METHODS["TweenBase.Cancel"] = function(tween)
	internal(tween).props.__token = -1
end
METHODS["TweenBase.Pause"] = METHODS["TweenBase.Cancel"]

METHODS["LocalizationService.GetTranslatorForPlayerAsync"] = function()
	error("not supported")
end

----------------------------------------------------------------------------
-- DataStores
----------------------------------------------------------------------------

Engine.dataStoreFail = false
Engine.dataStoreData = {}

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value do
		out[k] = deepCopy(v)
	end
	return out
end

METHODS["DataStoreService.GetDataStore"] = function(_, name)
	local store = Engine.createInternal("DataStore", name)
	internal(store).props.__name = name
	return store
end

local function storeKey(store, key)
	return internal(store).props.__name .. "/" .. key
end

local function maybeFail()
	if Engine.dataStoreFail then
		error("502: API Services rejected request with error. HTTP 500 (Internal Server Error)")
	end
	task.wait(0.05)
end

METHODS["GlobalDataStore.GetAsync"] = function(store, key)
	maybeFail()
	return deepCopy(Engine.dataStoreData[storeKey(store, key)])
end
METHODS["GlobalDataStore.SetAsync"] = function(store, key, value)
	maybeFail()
	Engine.dataStoreData[storeKey(store, key)] = deepCopy(value)
end
METHODS["GlobalDataStore.UpdateAsync"] = function(store, key, transform)
	maybeFail()
	local current = deepCopy(Engine.dataStoreData[storeKey(store, key)])
	local result = transform(current)
	if result ~= nil then
		Engine.dataStoreData[storeKey(store, key)] = deepCopy(result)
	end
	return deepCopy(result)
end

----------------------------------------------------------------------------
-- Remotes
----------------------------------------------------------------------------

Engine.clientLog = {}

METHODS["RemoteEvent.FireClient"] = function(remote, player, ...)
	assert(isInstance(player) and player.ClassName == "Player", "FireClient expects a Player")
	local log = Engine.clientLog[player]
	if not log then
		log = {}
		Engine.clientLog[player] = log
	end
	table.insert(log, { remote = remote.Name, args = table.pack(...) })
	if player == Engine.localPlayer then
		getSignal(remote, "OnClientEvent"):Fire(...)
	end
end
METHODS["RemoteEvent.FireAllClients"] = function(remote, ...)
	local players = Engine.game:GetService("Players")
	for _, player in players:GetPlayers() do
		METHODS["RemoteEvent.FireClient"](remote, player, ...)
	end
end
METHODS["RemoteEvent.FireServer"] = function(remote, ...)
	getSignal(remote, "OnServerEvent"):Fire(Engine.localPlayer, ...)
end
METHODS["RemoteFunction.InvokeServer"] = function(remote, ...)
	local handler = internal(remote).props.OnServerInvoke
	assert(handler, "OnServerInvoke not set for " .. remote.Name)
	return handler(Engine.localPlayer, ...)
end

-- Simulates a remote call from any player (server-side entry point).
function Engine.fireServer(remote, player, ...)
	getSignal(remote, "OnServerEvent"):Fire(player, ...)
end
function Engine.invokeServer(remote, player, ...)
	local handler = internal(remote).props.OnServerInvoke
	assert(handler, "OnServerInvoke not set for " .. remote.Name)
	return handler(player, ...)
end

----------------------------------------------------------------------------
-- DataModel
----------------------------------------------------------------------------

local SERVICES = {
	"Workspace", "Players", "ReplicatedStorage", "ServerScriptService", "ServerStorage", "StarterPlayer", "StarterGui",
	"Lighting", "SoundService", "RunService", "HttpService", "DataStoreService", "PhysicsService", "TextChatService",
	"TweenService", "UserInputService", "GuiService", "LocalizationService", "ProximityPromptService", "ContextActionService",
	"CollectionService", "Debris", "ReplicatedFirst", "Teams", "MaterialService",
}

METHODS["ServiceProvider.GetService"] = function(gameInst, name)
	local found = METHODS["Instance.FindFirstChild"](gameInst, name)
	if found then
		return found
	end
	if name == "Workspace" then
		return gameInst.Workspace
	end
	error("[harness] Unknown service " .. tostring(name), 2)
end
METHODS["DataModel.BindToClose"] = function(gameInst, fn)
	table.insert(Engine.closeCallbacks, fn)
end
Engine.closeCallbacks = {}

function Engine.createGame()
	local game = Engine.createInternal("DataModel", "Game")
	for _, name in SERVICES do
		Engine.createInternal(name, name, game)
	end
	local workspace = game:FindFirstChild("Workspace")
	local terrain = Engine.createInternal("Terrain", "Terrain", workspace)
	Engine.set(workspace, "Terrain", terrain)
	local camera = Engine.createInternal("Camera", "Camera", workspace)
	Engine.set(workspace, "CurrentCamera", camera)
	Engine.set(camera, "CFrame", roblox.CFrame.new(0, 60, 120))
	Engine.createInternal("StarterPlayerScripts", "StarterPlayerScripts", game:FindFirstChild("StarterPlayer"))
	internal(game).props.JobId = "harness-job"
	internal(game).props.PlaceId = 0
	Engine.game = game
	Engine.workspace = workspace
	return game
end

-- RunService frame driving.
function Engine.advance(seconds: number, frameRate: number?)
	local runService = Engine.game:GetService("RunService")
	local dt = 1 / (frameRate or 20)
	local target = Engine.now + seconds
	while Engine.now < target - 1e-9 do
		local step = math.min(dt, target - Engine.now)
		Engine.runUntil(Engine.now + step)
		getSignal(runService, "Stepped"):FireNow(Engine.now, step)
		getSignal(runService, "RenderStepped"):FireNow(step)
		getSignal(runService, "Heartbeat"):FireNow(step)
		Engine.runUntil(Engine.now)
	end
end

----------------------------------------------------------------------------
-- Players & characters
----------------------------------------------------------------------------

local nextUserId = 1000

function Engine.addPlayer(name: string, userId: number?)
	nextUserId += 1
	local players = Engine.game:GetService("Players")
	local player = Engine.createInternal("Player", name)
	local data = internal(player)
	data.props.UserId = userId or nextUserId
	data.props.DisplayName = name
	data.props.LocaleId = "en-us"
	Engine.createInternal("PlayerGui", "PlayerGui", player)
	Engine.createInternal("Backpack", "Backpack", player)
	Engine.createInternal("PlayerScripts", "PlayerScripts", player)
	reparent(player, players)
	getSignal(players, "PlayerAdded"):Fire(player)
	return player
end

function Engine.removePlayer(player)
	local players = Engine.game:GetService("Players")
	getSignal(players, "PlayerRemoving"):Fire(player)
	Engine.runUntil(Engine.now)
	local character = player.Character
	if character then
		character:Destroy()
	end
	reparent(player, nil)
end

function Engine.spawnCharacter(player)
	local old = internal(player).props.Character
	if old then
		METHODS["Instance.Destroy"](old)
	end
	local workspace = Engine.workspace
	local spawnCf = roblox.CFrame.new(0, 60, 0)
	local spawn = internal(player).props.RespawnLocation
	if spawn then
		spawnCf = (internal(spawn).props.CFrame or spawnCf) + roblox.Vector3.new(0, 3, 0)
	end
	local model = Engine.createInternal("Model", player.Name)
	local root = Engine.createInternal("Part", "HumanoidRootPart", model)
	internal(root).props.CFrame = spawnCf
	internal(root).props.Size = roblox.Vector3.new(2, 2, 1)
	local head = Engine.createInternal("Part", "Head", model)
	internal(head).props.CFrame = spawnCf * roblox.CFrame.new(0, 1.5, 0)
	Engine.createInternal("Humanoid", "Humanoid", model)
	internal(model).props.PrimaryPart = root
	reparent(model, workspace)
	Engine.set(player, "Character", model)
	getSignal(player, "CharacterAdded"):Fire(model)
	return model
end

function Engine.moveTo(player, position)
	local character = player.Character
	assert(character, "no character for " .. player.Name)
	local root = character:FindFirstChild("HumanoidRootPart")
	local delta = roblox.CFrame.new(position) * internal(root).props.CFrame:Inverse()
	for _, part in descendants(character, {}) do
		if Api.isA(internal(part).className, "BasePart") then
			internal(part).props.CFrame = delta * (internal(part).props.CFrame or roblox.CFrame.new())
		end
	end
end

----------------------------------------------------------------------------
-- Script environment
----------------------------------------------------------------------------

function Engine.environment(realm: string)
	local env = {
		game = Engine.game,
		workspace = Engine.workspace,
		Workspace = Engine.workspace,
		task = task,
		Instance = InstanceLib,
		typeof = typeOf,
		Random = RandomLib,
		TweenInfo = TweenInfoLib,
		warn = function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				parts[i] = tostring(select(i, ...))
			end
			local line = "[" .. realm .. " warn] " .. table.concat(parts, " ")
			table.insert(Engine.log, line)
			if Engine.verbose then
				print("\27[33m" .. line .. "\27[0m")
			end
		end,
		print = function(...)
			if Engine.verbose then
				print("[" .. realm .. "]", ...)
			end
		end,
		os = {
			clock = function()
				return Engine.now
			end,
			time = function()
				return BASE_TIME + math.floor(Engine.now)
			end,
			date = os.date,
		},
		tick = function()
			return BASE_TIME + Engine.now
		end,
		time = function()
			return Engine.now
		end,
		elapsedTime = function()
			return Engine.now
		end,
		wait = task.wait,
		delay = task.delay,
		spawn = task.defer,
	}
	env.CFrame = Engine.CFrame
	env.ColorSequence = Engine.ColorSequence
	for _, name in {
		"Vector3", "Vector2", "Color3", "UDim", "UDim2", "Enum", "NumberSequence", "NumberSequenceKeypoint",
		"ColorSequenceKeypoint", "NumberRange", "Region3", "Rect", "Font", "BrickColor", "Ray",
		"PhysicalProperties", "Faces", "Axes", "Vector3int16", "Vector2int16", "Region3int16",
	} do
		env[name] = roblox[name]
	end
	env.string = string
	env.math = math
	env.table = table
	env.bit32 = bit32
	env.coroutine = coroutine
	env.utf8 = utf8
	env.debug = debug
	env.pcall = pcall
	env.xpcall = xpcall
	env.error = error
	env.assert = assert
	env.type = type
	env.tostring = tostring
	env.tonumber = tonumber
	env.ipairs = ipairs
	env.pairs = pairs
	env.next = next
	env.select = select
	env.setmetatable = setmetatable
	env.getmetatable = getmetatable
	env.rawget = rawget
	env.rawset = rawset
	env.rawequal = rawequal
	env.unpack = table.unpack
	return env
end

return Engine
