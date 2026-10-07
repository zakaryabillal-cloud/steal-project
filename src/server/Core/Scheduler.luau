--!strict
-- Single server heartbeat for every periodic job.
--
-- Replaces the per-service `while true do task.wait(x) ... end` threads:
--   * one RunService.Heartbeat connection drives everything;
--   * each job runs in its own thread, so a job that yields (e.g. autosave
--     spacing) never delays the others, and is never re-entered while busy
--     (same semantics as the old loops);
--   * a job that errors is reported and keeps running on its next tick,
--     instead of silently killing its loop forever.
--
-- Jobs receive `dt`: seconds since their previous run (first run: interval).

local RunService = game:GetService("RunService")

local Scheduler = {}

export type JobOptions = {
	-- Seconds before the first run (default: one interval).
	delay: number?,
}

type Job = {
	name: string,
	interval: number,
	fn: (dt: number) -> (),
	nextAt: number,
	lastRun: number,
	busy: boolean,
	runs: number,
	errors: number,
}

local jobs: { Job } = {}
local byName: { [string]: Job } = {}
local clock = 0
local connection: RBXScriptConnection? = nil

local function run(job: Job, dt: number)
	job.busy = true
	job.runs += 1
	local ok: boolean, err: any = xpcall(job.fn :: any, debug.traceback, dt)
	job.busy = false
	if not ok then
		job.errors += 1
		warn(string.format("[Scheduler] job %s failed: %s", job.name, tostring(err)))
	end
end

local function step(dt: number)
	clock += dt
	for _, job in jobs do
		if job.busy or clock < job.nextAt then
			continue
		end
		local elapsed = clock - job.lastRun
		job.lastRun = clock
		-- Never try to "catch up" with a burst of runs after a stall.
		job.nextAt = math.max(job.nextAt + job.interval, clock + job.interval * 0.5)
		task.spawn(run, job, elapsed)
	end
end

-- Registers a periodic job. Names must be unique.
function Scheduler.every(name: string, interval: number, fn: (dt: number) -> (), options: JobOptions?)
	assert(byName[name] == nil, "Scheduler job already registered: " .. name)
	assert(interval > 0, "Scheduler interval must be > 0")
	local delay = if options and options.delay then options.delay else interval
	local job: Job = {
		name = name,
		interval = interval,
		fn = fn,
		nextAt = clock + delay,
		lastRun = clock + delay - interval,
		busy = false,
		runs = 0,
		errors = 0,
	}
	table.insert(jobs, job)
	byName[name] = job
	if connection == nil then
		connection = RunService.Heartbeat:Connect(step)
	end
end

-- Introspection for tests and diagnostics.
function Scheduler.stats(name: string): { runs: number, errors: number, busy: boolean }?
	local job = byName[name]
	if not job then
		return nil
	end
	return { runs = job.runs, errors = job.errors, busy = job.busy }
end

function Scheduler.names(): { string }
	local names = {}
	for _, job in jobs do
		table.insert(names, job.name)
	end
	return names
end

return Scheduler
