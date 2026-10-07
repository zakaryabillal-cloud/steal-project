--!strict
-- Tracks resources (instances, connections, callbacks, threads) and releases
-- them together. Every controller that creates temporary state owns one.

type Cleanable = Instance | RBXScriptConnection | thread | () -> () | { Destroy: (any) -> () } | { Disconnect: (any) -> () }

export type Trove = {
	Add: <T>(self: Trove, item: T) -> T,
	Connect: (self: Trove, signal: RBXScriptSignal, fn: (...any) -> ()) -> RBXScriptConnection,
	Clean: (self: Trove) -> (),
	Destroy: (self: Trove) -> (),
	Extend: (self: Trove) -> Trove,
}

local Trove = {}
Trove.__index = Trove

function Trove.new(): Trove
	local self = setmetatable({ _items = {} :: { any } }, Trove)
	return (self :: any) :: Trove
end

local function release(item: any)
	local kind = typeof(item)
	if kind == "Instance" then
		item:Destroy()
	elseif kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif kind == "function" then
		item()
	elseif kind == "thread" then
		if coroutine.status(item) ~= "dead" then
			pcall(task.cancel, item)
		end
	elseif kind == "table" then
		if type(item.Destroy) == "function" then
			item:Destroy()
		elseif type(item.Disconnect) == "function" then
			item:Disconnect()
		end
	end
end

function Trove:Add(item: any): any
	table.insert(self._items, item)
	return item
end

function Trove:Connect(signal: RBXScriptSignal, fn: (...any) -> ()): RBXScriptConnection
	local connection = signal:Connect(fn)
	table.insert(self._items, connection)
	return connection
end

function Trove:Extend(): Trove
	local child = Trove.new()
	table.insert(self._items, child)
	return child
end

function Trove:Clean()
	local items = self._items
	self._items = {}
	for i = #items, 1, -1 do
		release(items[i])
	end
end

function Trove:Destroy()
	self:Clean()
end

return Trove
