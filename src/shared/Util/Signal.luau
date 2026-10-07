--!strict
-- Minimal synchronous signal. Handlers run in order; errors in one handler
-- never break the others (each runs through task.spawn).

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	Wait: (self: Signal<T...>) -> T...,
	DisconnectAll: (self: Signal<T...>) -> (),
}

type Node = {
	fn: (...any) -> (),
	connected: boolean,
}

local Signal = {}
Signal.__index = Signal

function Signal.new<T...>(): Signal<T...>
	local self = setmetatable({ _nodes = {} :: { Node } }, Signal)
	return (self :: any) :: Signal<T...>
end

function Signal:Connect(fn: (...any) -> ()): Connection
	local node: Node = { fn = fn, connected = true }
	table.insert(self._nodes, node)
	local nodes = self._nodes
	local connection = {
		Connected = true,
	}
	function connection.Disconnect(c: any)
		if not node.connected then
			return
		end
		node.connected = false
		c.Connected = false
		local index = table.find(nodes, node)
		if index then
			table.remove(nodes, index)
		end
	end
	return (connection :: any) :: Connection
end

function Signal:Once(fn: (...any) -> ()): Connection
	local connection: Connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		fn(...)
	end)
	return connection
end

function Signal:Fire(...: any)
	-- Copy so handlers may disconnect while iterating.
	local snapshot: { Node } = table.clone(self._nodes)
	for _, node in snapshot do
		if node.connected then
			task.spawn(node.fn, ...)
		end
	end
end

function Signal:Wait(): ...any
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:DisconnectAll()
	local nodes: { Node } = self._nodes
	for _, node in nodes do
		node.connected = false
	end
	table.clear(self._nodes)
end

return Signal
