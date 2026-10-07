--!strict
-- Server-side networking helpers: guarded handlers (rate limit + pcall) and
-- typed senders for notifications and FX broadcasts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Net = require(ReplicatedStorage.Shared.Net)
local RateLimiter = require(ReplicatedStorage.Shared.Util.RateLimiter)

local Remotes = {}

local folder: Folder? = nil

local function event(name: string): RemoteEvent
	assert(folder, "Remotes.init must run first")
	return folder:FindFirstChild(name) :: RemoteEvent
end

local function func(name: string): RemoteFunction
	assert(folder, "Remotes.init must run first")
	return folder:FindFirstChild(name) :: RemoteFunction
end

function Remotes.init()
	folder = Net.setupServer()
end

export type Limits = { rate: number, burst: number }

local limiters: { RateLimiter.RateLimiter } = {}

Players.PlayerRemoving:Connect(function(player)
	for _, limiter in limiters do
		limiter:forget(player)
	end
end)

-- Connects a client -> server RemoteEvent. Excess calls are dropped silently;
-- handler errors are contained so a bad payload can never break the server.
function Remotes.on(name: string, limits: Limits, handler: (Player, ...any) -> ...any)
	local limiter = RateLimiter.new(limits.rate, limits.burst)
	table.insert(limiters, limiter)
	event(name).OnServerEvent:Connect(function(player: Player, ...)
		if not limiter:check(player) then
			return
		end
		local ok, err = pcall(handler, player, ...)
		if not ok then
			warn(string.format("[Remotes] %s handler error for %s: %s", name, player.Name, tostring(err)))
		end
	end)
end

-- Connects a RemoteFunction. Rate-limited calls return (false, "rate").
function Remotes.onInvoke(name: string, limits: Limits, handler: (Player, ...any) -> (boolean, string?))
	local limiter = RateLimiter.new(limits.rate, limits.burst)
	table.insert(limiters, limiter)
	local remote: any = func(name)
	remote.OnServerInvoke = function(player: Player, ...): (boolean, string?)
		if not limiter:check(player) then
			return false, "rate"
		end
		local ok, success, reason = pcall(handler, player, ...)
		if not ok then
			warn(string.format("[Remotes] %s invoke error for %s: %s", name, player.Name, tostring(success)))
			return false, "error"
		end
		return success == true, reason
	end
end

-- style: "info" | "success" | "warning" | "danger" | "rare"
function Remotes.notify(player: Player, key: string, args: { [string]: any }?, style: string?)
	event(Net.Events.Notify):FireClient(player, key, args or {}, style or "info")
end

function Remotes.notifyAll(key: string, args: { [string]: any }?, style: string?, except: Player?)
	local remote = event(Net.Events.Notify)
	for _, player in Players:GetPlayers() do
		if player ~= except then
			remote:FireClient(player, key, args or {}, style or "info")
		end
	end
end

function Remotes.fx(kind: string, payload: { [string]: any })
	event(Net.Events.FX):FireAllClients(kind, payload)
end

function Remotes.fxTo(player: Player, kind: string, payload: { [string]: any })
	event(Net.Events.FX):FireClient(player, kind, payload)
end

function Remotes.sync(player: Player, snapshot: { [string]: any })
	event(Net.Events.Sync):FireClient(player, snapshot)
end

function Remotes.knockback(player: Player, impulse: Vector3, stun: number)
	event(Net.Events.Knockback):FireClient(player, impulse, stun)
end

return Remotes
