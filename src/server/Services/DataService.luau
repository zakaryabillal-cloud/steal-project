--!strict
-- Player persistence with UpdateAsync, retries with backoff and a light
-- session lock that prevents two servers from writing the same profile
-- (e.g. during a quick server hop) and so blocks item duplication.
--
-- When DataStores are unreachable (Studio without API access, outage) the
-- player gets temporary data and `canSave = false`, so a bad load can never
-- overwrite a good save.
--
-- Forward compatibility: a record whose `schema` is NEWER than this build's
-- (written by a more recent version of the game) is never locked, normalised
-- or overwritten here. The player gets temporary data (status "newer"), and
-- every save transform re-checks the stored schema before writing.

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Core = script.Parent.Parent.Core
local DataSchema = require(Core.DataSchema)
local Types = require(Core.Types)
local Sessions = require(Core.Sessions)

type SaveData = Types.SaveData
type Session = Types.Session

local DataService = {}

local CONFIG = GameConfig.Data
local store: DataStore? = nil

DataService.available = false

local function jobId(): string
	return if game.JobId ~= "" then game.JobId else "studio-" .. tostring(game.PlaceId)
end

local function keyFor(userId: number): string
	return "u_" .. tostring(userId)
end

function DataService.init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(CONFIG.StoreName)
	end)
	if not ok then
		warn("[DataService] DataStore unavailable:", result)
		return
	end
	store = result
	-- GetDataStore succeeds in Studio even without API access; probe for real.
	local probeOk, probeErr = pcall(function()
		return (result :: DataStore):GetAsync("__probe")
	end)
	DataService.available = probeOk
	if not probeOk then
		warn("[DataService] DataStore requests failing, using temporary data:", probeErr)
	end
end

-- Returns (data, canSave, status).
-- status: "new" | "loaded" | "studio" | "unavailable" | "failed" | "left" | "newer"
function DataService.load(player: Player): (SaveData, boolean, string)
	local activeStore = store
	if activeStore == nil or not DataService.available then
		return DataSchema.default(), false, if RunService:IsStudio() then "studio" else "unavailable"
	end

	local key = keyFor(player.UserId)
	local job = jobId()
	for attempt = 1, CONFIG.MaxRetries do
		local force = attempt == CONFIG.MaxRetries
		local loaded: any = nil
		local existed = false
		local newer = false
		local ok, err = pcall(function()
			activeStore:UpdateAsync(key, function(old: any)
				loaded = nil
				newer = false
				if DataSchema.isNewer(old) then
					-- Written by a newer build: do not lock, do not touch.
					newer = true
					return nil
				end
				if type(old) == "table" and type(old.lock) == "table" and not force then
					local lockJob = old.lock.job
					local lockTime = tonumber(old.lock.time) or 0
					if lockJob ~= job and os.time() - lockTime < CONFIG.LockTimeout then
						-- Another server still owns this profile; wait for it to release.
						return nil
					end
				end
				existed = type(old) == "table"
				local record = if type(old) == "table" then old else {}
				record.lock = { job = job, time = os.time() }
				loaded = record
				return record
			end)
		end)
		if ok and newer then
			warn(string.format("[DataService] Profile %d uses a newer schema than v%d; playing with temporary data", player.UserId, DataSchema.Version))
			return DataSchema.default(), false, "newer"
		end
		if ok and loaded ~= nil then
			return DataSchema.normalize(loaded), true, if existed then "loaded" else "new"
		end
		if not ok then
			warn(string.format("[DataService] Load attempt %d for %d failed: %s", attempt, player.UserId, tostring(err)))
		end
		if player.Parent == nil then
			return DataSchema.default(), false, "left"
		end
		task.wait(math.min(2 ^ attempt, 8))
	end
	return DataSchema.default(), false, "failed"
end

-- Writes the session's data. `release` clears the session lock (on leave).
function DataService.save(session: Session, release: boolean): boolean
	local activeStore = store
	if not session.canSave or activeStore == nil then
		return false
	end
	local payload = DataSchema.serialize(session.data)
	local job = jobId()
	payload.lock = if release then nil else { job = job, time = os.time() }
	local key = keyFor(session.userId)

	for attempt = 1, CONFIG.MaxRetries do
		local stolen = false
		local newer = false
		local ok, err = pcall(function()
			activeStore:UpdateAsync(key, function(old: any)
				stolen = false
				newer = false
				if DataSchema.isNewer(old) then
					-- A newer build wrote this profile since we loaded it: never downgrade it.
					newer = true
					return nil
				end
				if type(old) == "table" and type(old.lock) == "table" and old.lock.job ~= job then
					-- Another server force-took this profile: never overwrite it.
					stolen = true
					return nil
				end
				return payload
			end)
		end)
		if ok then
			if newer then
				warn("[DataService] Profile", session.userId, "was written by a newer schema; save refused")
				session.canSave = false
				Sessions.markCold(session)
				return false
			end
			if stolen then
				warn("[DataService] Profile", session.userId, "is owned by another server; save skipped")
				return false
			end
			return true
		end
		warn(string.format("[DataService] Save attempt %d for %d failed: %s", attempt, session.userId, tostring(err)))
		task.wait(math.min(2 ^ attempt, 6))
	end
	return false
end

return DataService
