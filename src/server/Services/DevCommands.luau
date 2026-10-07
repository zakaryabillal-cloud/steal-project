--!strict
-- Studio-only test commands (never active in live servers). Type in chat:
--   /rh essence <amount>          add Essence
--   /rh spawn <rarity|relicId> [mutation]   force the next Rift spawn
--   /rh event <RiftOverload|VoidStorm|GoldenSurge|Eclipse>
--   /rh tier <1-5>                set Sanctuary tier
--   /rh pedestals <0-9>           set pedestal upgrade level
--   /rh core <amount>             fill the Core
--   /rh novice                    skip novice protection (to test thefts)
--   /rh reset                     wipe your temporary data

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Relics = require(Shared.Config.Relics)
local Rarities = require(Shared.Config.Rarities)
local Mutations = require(Shared.Config.Mutations)
local Upgrades = require(Shared.Config.Upgrades)
local GameConfig = require(Shared.Config.GameConfig)

local Core = script.Parent.Parent.Core
local Sessions = require(Core.Sessions)
local Remotes = require(Core.Remotes)
local DataSchema = require(Core.DataSchema)
local Rolls = require(Core.Rolls)
local EconomyService = require(script.Parent.EconomyService)
local PlotService = require(script.Parent.PlotService)
local RiftService = require(script.Parent.RiftService)
local EventService = require(script.Parent.EventService)

local DevCommands = {}

local recent: { [Player]: { text: string, at: number } } = {}

local function run(player: Player, text: string)
	local args = string.split(text, " ")
	if string.lower(args[1] or "") ~= "/rh" then
		return
	end
	local last = recent[player]
	if last and last.text == text and os.clock() - last.at < 0.5 then
		return
	end
	recent[player] = { text = text, at = os.clock() }

	local session = Sessions.ready(player)
	if not session then
		return
	end
	local command = string.lower(args[2] or "")
	if command == "essence" then
		EconomyService.addEssence(session, tonumber(args[3]) or 10000)
	elseif command == "core" then
		EconomyService.addToCore(session, tonumber(args[3]) or 5000)
	elseif command == "spawn" then
		local what = args[3] or "Legendary"
		local mutation: string? = args[4]
		if mutation and not Mutations.get(mutation) then
			mutation = nil
		end
		local rng = Random.new()
		local def = Relics.get(what)
		if not def and Rarities.byId[what] then
			def = Rolls.relic(rng, what, "Eclipse")
		end
		if def then
			RiftService.force({ relicId = def.id, rarity = def.rarity, mutation = mutation })
		end
	elseif command == "event" then
		EventService.trigger(args[3])
	elseif command == "tier" or command == "pedestals" then
		local id = if command == "tier" then "tier" else "pedestal"
		local def = Upgrades.get(id)
		local value = tonumber(args[3]) or 0
		if def then
			local level = math.clamp(math.floor(if id == "tier" then value - 1 else value), 0, def.maxLevel);
			(session.data.upgrades :: any)[id] = level
			local plot = PlotService.of(session)
			if plot then
				if id == "tier" then
					PlotService.setTier(plot, level + 1)
					Remotes.fx("TierUp", { plot = plot.index, tier = level + 1, userId = session.userId })
				else
					PlotService.refreshPedestals(plot)
				end
			end
			EconomyService.recompute(session)
		end
	elseif command == "novice" then
		session.data.playTime = GameConfig.Steal.NoviceSeconds + 1
	elseif command == "reset" then
		session.data = DataSchema.default()
		session.canSave = false
		player:Kick("Data reset (Studio). Press Play again.")
		return
	end
	Sessions.markCold(session)
end

function DevCommands.start()
	if not RunService:IsStudio() then
		return
	end
	local function hook(player: Player)
		player.Chatted:Connect(function(message)
			run(player, message)
		end)
	end
	for _, player in Players:GetPlayers() do
		hook(player)
	end
	Players.PlayerAdded:Connect(hook)
	Players.PlayerRemoving:Connect(function(player)
		recent[player] = nil
	end)

	local ok = pcall(function()
		local command = Instance.new("TextChatCommand")
		command.Name = "RiftHeistDev"
		command.PrimaryAlias = "/rh"
		command.Triggered:Connect(function(source: TextSource, text: string)
			local player = Players:GetPlayerByUserId(source.UserId)
			if player then
				run(player, text)
			end
		end)
		command.Parent = TextChatService
	end)
	if not ok then
		warn("[DevCommands] TextChatCommand unavailable; using Player.Chatted only")
	end
	print("[RiftHeist] Studio dev commands enabled: /rh essence|spawn|event|tier|pedestals|core|novice|reset")
end

return DevCommands
