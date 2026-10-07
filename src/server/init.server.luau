--!strict
-- RIFT HEIST server bootstrap: builds the world, starts every service and owns
-- the player lifecycle (load -> assign Sanctuary -> restore collection ->
-- spawn; and on leave: resolve carried/stolen relics -> save -> free plot).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local GameConfig = require(Shared.Config.GameConfig)

local Core = script.Core
local Types = require(Core.Types)
local Sessions = require(Core.Sessions)
local Remotes = require(Core.Remotes)
local Snapshot = require(Core.Snapshot)
local DataSchema = require(Core.DataSchema)

local Services = script.Services
local DataService = require(Services.DataService)
local PlotService = require(Services.PlotService)
local RelicService = require(Services.RelicService)
local EconomyService = require(Services.EconomyService)
local CharacterService = require(Services.CharacterService)
local EventService = require(Services.EventService)
local RiftService = require(Services.RiftService)
local CarryService = require(Services.CarryService)
local StealService = require(Services.StealService)
local AbilityService = require(Services.AbilityService)
local UpgradeService = require(Services.UpgradeService)
local TutorialService = require(Services.TutorialService)
local MovementGuard = require(Services.MovementGuard)
local DevCommands = require(Services.DevCommands)

local WorldBuilder = require(script.World.WorldBuilder)

type Session = Types.Session

-- 1. Networking + world -------------------------------------------------------
Remotes.init()
WorldBuilder.build()

-- 2. Services -------------------------------------------------------------------
DataService.init()
PlotService.init()
RelicService.init()
EconomyService.start()
CharacterService.start()
EventService.start()
RiftService.start()
CarryService.start()
StealService.start()
AbilityService.start()
UpgradeService.start()
MovementGuard.start()
DevCommands.start()

-- 3. Small client requests -------------------------------------------------------
local ALLOWED_TIPS = { intro = true, steal = true, pulse = true, seal = true, fuse = true, dash = true, dex = true, shop = true }

Remotes.on(Net.Events.ClientReady, { rate = 1, burst = 3 }, function(player: Player)
	local session = Sessions.get(player)
	if session then
		session.dirty = true
	end
end)

Remotes.on(Net.Events.Settings, { rate = 4, burst = 10 }, function(player: Player, key: any, value: any)
	local session = Sessions.ready(player)
	if not session or type(key) ~= "string" then
		return
	end
	local settings = session.data.settings
	if (key == "sfx" or key == "music") and type(value) == "number" and value == value then
		settings[key] = math.clamp(value, 0, 1)
	elseif key == "quality" and (value == "Low" or value == "Medium" or value == "High") then
		settings.quality = value
	elseif key == "shake" and type(value) == "boolean" then
		settings.shake = value
	elseif key == "language" and (value == "en" or value == "fr") then
		settings.language = value
	else
		return
	end
	Sessions.markDirty(session)
end)

Remotes.on(Net.Events.TutorialSeen, { rate = 2, burst = 6 }, function(player: Player, tip: any)
	local session = Sessions.ready(player)
	if session and type(tip) == "string" and ALLOWED_TIPS[tip] then
		TutorialService.markTip(session, tip)
	end
end)

Remotes.on(Net.Events.DissolveCarried, { rate = 2, burst = 3 }, function(player: Player, uid: any)
	local session = Sessions.ready(player)
	if session and type(uid) == "string" and #uid <= 40 then
		Sessions.touch(session)
		local ok, amount = CarryService.dissolveCarried(session, uid)
		if ok then
			Remotes.notify(player, "n.dissolved", { amount = tonumber(amount) or 0 }, "success")
		end
	end
end)

Remotes.onInvoke(Net.Functions.Dissolve, { rate = 2, burst = 4 }, function(player: Player, uid: any)
	local session = Sessions.ready(player)
	if not session or type(uid) ~= "string" or #uid > 40 then
		return false, "invalid"
	end
	Sessions.touch(session)
	return CarryService.dissolvePlaced(session, uid)
end)

-- 4. Player lifecycle ------------------------------------------------------------
local activeSaves = 0

local function restoreCollection(session: Session)
	local plot = PlotService.of(session)
	if not plot then
		return
	end
	for _, saved in session.data.relics do
		local entity = RelicService.create({ id = saved.id, level = saved.level, mutation = saved.mutation, uid = saved.uid }, PlotService.slotPosition(plot.index, saved.slot))
		saved.uid = entity.uid
		RelicService.toPlaced(entity, session.userId, plot.index, saved.slot, PlotService.slotPosition(plot.index, saved.slot))
		PlotService.setSlot(plot, saved.slot, entity.uid, entity.rarity)
	end
	PlotService.refreshPedestals(plot)
end

local function makeLeaderstats(session: Session)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local essence = Instance.new("IntValue")
	essence.Name = "Essence"
	essence.Value = math.floor(session.data.essence)
	essence.Parent = folder
	local dex = Instance.new("IntValue")
	dex.Name = "RiftDex"
	local found = 0
	for _ in session.data.dex do
		found += 1
	end
	dex.Value = found
	dex.Parent = folder
	folder.Parent = session.player
	session.leaderstats = folder
end

local function onPlayerAdded(player: Player)
	local session = Sessions.create(player, DataSchema.default())
	player.CharacterAdded:Connect(function(character)
		CharacterService.onCharacter(session, character)
	end)

	local data, canSave, status = DataService.load(player)
	session.data = data
	session.canSave = canSave
	session.dataStatus = status
	if player.Parent == nil then
		-- Left while loading: release the lock we just took without changing data.
		if canSave then
			DataService.save(session, true)
		end
		Sessions.remove(player)
		return
	end

	makeLeaderstats(session)
	session.joinedAt = workspace:GetServerTimeNow()
	session.loaded = true

	local plotIndex = PlotService.assign(session)
	if plotIndex then
		restoreCollection(session)
	end
	EconomyService.recompute(session)
	if plotIndex then
		EconomyService.applyOffline(session)
	end
	CharacterService.spawn(session)

	if status == "studio" then
		Remotes.notify(player, "n.studioData", nil, "info")
	elseif status == "failed" or status == "unavailable" then
		Remotes.notify(player, "n.dataWarning", nil, "danger")
	elseif status == "loaded" and data.lastSeen > 0 then
		Remotes.notify(player, "n.welcomeBack", { name = player.DisplayName }, "info")
	end
	if not plotIndex then
		Remotes.notify(player, "n.waitingPlot", nil, "warning")
	end
	Sessions.markDirty(session)
end

local function onPlayerRemoving(player: Player)
	local session = Sessions.get(player)
	if not session then
		return
	end
	if not session.loaded then
		-- onPlayerAdded is still loading; it cleans up when the load returns.
		return
	end
	if session.released then
		return
	end
	session.released = true
	activeSaves += 1

	local ok, err = pcall(function()
		CarryService.onLeave(session)
	end)
	if not ok then
		warn("[RiftHeist] Leave cleanup failed for", player.Name, err)
	end
	session.data.playTime = Sessions.playTime(session)
	session.joinedAt = workspace:GetServerTimeNow()
	session.data.lastSeen = os.time()
	PlotService.release(session)
	EconomyService.forget(session)
	DataService.save(session, true)
	Sessions.remove(player)
	activeSaves -= 1
end

PlotService.plotFreed:Connect(function(session: Session)
	restoreCollection(session)
	EconomyService.recompute(session)
	CharacterService.refreshCollision(session)
	CharacterService.spawn(session)
	Sessions.markDirty(session)
end)

Players.PlayerAdded:Connect(function(player)
	onPlayerAdded(player)
end)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

-- 5. Sync, autosave, shutdown ------------------------------------------------------
local syncAccumulator = 0
RunService.Heartbeat:Connect(function(dt)
	syncAccumulator += dt
	if syncAccumulator < 0.1 then
		return
	end
	syncAccumulator = 0
	for _, session in Sessions.all() do
		if session.dirty then
			session.dirty = false
			Remotes.sync(session.player, Snapshot.build(session))
		end
	end
end)

task.spawn(function()
	while true do
		task.wait(GameConfig.Data.AutosaveInterval)
		local sessions = Sessions.all()
		local spacing = GameConfig.Data.AutosaveInterval / math.max(#sessions, 1) * 0.5
		for _, session in sessions do
			if not session.released and session.canSave then
				session.data.playTime = Sessions.playTime(session)
				session.joinedAt = workspace:GetServerTimeNow()
				session.data.lastSeen = os.time()
				DataService.save(session, false)
			end
			task.wait(math.min(spacing, 5))
		end
	end
end)

game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerRemoving, player)
	end
	local deadline = os.clock() + 25
	task.wait(0.1)
	while activeSaves > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end)

print(string.format("[RiftHeist] Server v%s ready", GameConfig.Version))
