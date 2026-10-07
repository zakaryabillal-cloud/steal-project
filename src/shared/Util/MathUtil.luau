--!strict
local MathUtil = {}

function MathUtil.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function MathUtil.clamp01(t: number): number
	return math.clamp(t, 0, 1)
end

function MathUtil.smoothstep(edge0: number, edge1: number, x: number): number
	local t = math.clamp((x - edge0) / (edge1 - edge0), 0, 1)
	return t * t * (3 - 2 * t)
end

-- Frame-rate independent exponential smoothing factor.
function MathUtil.damp(sharpness: number, dt: number): number
	return 1 - math.exp(-sharpness * dt)
end

function MathUtil.easeOutBack(t: number): number
	local c1 = 1.70158
	local c3 = c1 + 1
	return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

function MathUtil.easeOutCubic(t: number): number
	return 1 - (1 - t) ^ 3
end

function MathUtil.easeInOutSine(t: number): number
	return -(math.cos(math.pi * t) - 1) / 2
end

-- Point on a quadratic bezier.
function MathUtil.bezier(p0: Vector3, p1: Vector3, p2: Vector3, t: number): Vector3
	local u = 1 - t
	return p0 * (u * u) + p1 * (2 * u * t) + p2 * (t * t)
end

function MathUtil.flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function MathUtil.flatDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- Deterministic 2D value noise (smooth), returns roughly [-1, 1].
local function hash(ix: number, iz: number, seed: number): number
	-- xorshift mixing kept inside 32-bit integer range so results are exact.
	local n = (ix * 1619 + iz * 31337 + seed * 6971 + 1013904223) % 4294967296
	for _ = 1, 2 do
		n = bit32.bxor(n, bit32.lshift(n, 13))
		n = bit32.bxor(n, bit32.rshift(n, 17))
		n = bit32.bxor(n, bit32.lshift(n, 5))
	end
	return (n / 4294967296) * 2 - 1
end

function MathUtil.noise2(x: number, z: number, seed: number): number
	local ix, iz = math.floor(x), math.floor(z)
	local fx, fz = x - ix, z - iz
	local ux = fx * fx * (3 - 2 * fx)
	local uz = fz * fz * (3 - 2 * fz)
	local a = hash(ix, iz, seed)
	local b = hash(ix + 1, iz, seed)
	local c = hash(ix, iz + 1, seed)
	local d = hash(ix + 1, iz + 1, seed)
	return (a + (b - a) * ux) + ((c + (d - c) * ux) - (a + (b - a) * ux)) * uz
end

function MathUtil.fbm(x: number, z: number, seed: number, octaves: number): number
	local total, amplitude, frequency, norm = 0, 1, 1, 0
	for i = 1, octaves do
		total += MathUtil.noise2(x * frequency, z * frequency, seed + i * 31) * amplitude
		norm += amplitude
		amplitude *= 0.5
		frequency *= 2
	end
	return total / norm
end

-- Smallest signed difference between two angles (radians).
function MathUtil.angleDelta(a: number, b: number): number
	local d = (b - a) % (2 * math.pi)
	if d > math.pi then
		d -= 2 * math.pi
	end
	return d
end

return MathUtil
