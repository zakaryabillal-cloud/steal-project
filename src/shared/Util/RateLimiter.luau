--!strict
-- Token bucket keyed by an arbitrary value (usually a Player). Used to throttle
-- every client -> server remote.

export type RateLimiter = {
	check: (self: RateLimiter, key: any, now: number?) -> boolean,
	forget: (self: RateLimiter, key: any) -> (),
}

type Bucket = { tokens: number, last: number }

local RateLimiter = {}
RateLimiter.__index = RateLimiter

-- `rate` tokens are refilled per second, up to `burst`.
function RateLimiter.new(rate: number, burst: number): RateLimiter
	local self = setmetatable({
		_rate = rate,
		_burst = burst,
		_buckets = {} :: { [any]: Bucket },
	}, RateLimiter)
	return (self :: any) :: RateLimiter
end

function RateLimiter:check(key: any, now: number?): boolean
	local t = now or os.clock()
	local bucket = self._buckets[key]
	if not bucket then
		bucket = { tokens = self._burst, last = t }
		self._buckets[key] = bucket
	end
	bucket.tokens = math.min(self._burst, bucket.tokens + (t - bucket.last) * self._rate)
	bucket.last = t
	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end
	return false
end

function RateLimiter:forget(key: any)
	self._buckets[key] = nil
end

return RateLimiter
