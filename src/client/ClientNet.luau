--!strict
-- Client networking front-end: FX dispatch by kind, notifications, and
-- request helpers. Remotes are looked up once and cached.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Shared.Net)

local ClientNet = {}

type FxHandler = (payload: { [string]: any }) -> ()

local handlers: { [string]: { FxHandler } } = {}
local events: { [string]: RemoteEvent } = {}
local functions: { [string]: RemoteFunction } = {}

local function event(name: string): RemoteEvent
	local remote = events[name]
	if not remote then
		remote = Net.event(name)
		events[name] = remote
	end
	return remote
end

local function func(name: string): RemoteFunction
	local remote = functions[name]
	if not remote then
		remote = Net.func(name)
		functions[name] = remote
	end
	return remote
end

function ClientNet.init()
	event(Net.Events.FX).OnClientEvent:Connect(function(kind: string, payload: { [string]: any })
		local list = handlers[kind]
		if not list then
			return
		end
		for _, handler in list do
			task.spawn(handler, payload)
		end
	end)
end

function ClientNet.on(kind: string, handler: FxHandler)
	local list = handlers[kind]
	if not list then
		list = {}
		handlers[kind] = list
	end
	table.insert(list, handler)
end

function ClientNet.onNotify(handler: (key: string, args: { [string]: any }, style: string) -> ())
	event(Net.Events.Notify).OnClientEvent:Connect(handler)
end

function ClientNet.onSync(handler: (snapshot: { [string]: any }) -> ())
	event(Net.Events.Sync).OnClientEvent:Connect(handler)
end

function ClientNet.onKnockback(handler: (impulse: Vector3, stun: number) -> ())
	event(Net.Events.Knockback).OnClientEvent:Connect(handler)
end

function ClientNet.fire(name: string, ...: any)
	event(name):FireServer(...)
end

function ClientNet.invoke(name: string, ...: any): (boolean, string?)
	local ok, success, reason = pcall(function(...)
		return func(name):InvokeServer(...)
	end, ...)
	if not ok then
		return false, "error"
	end
	return success == true, reason
end

return ClientNet
