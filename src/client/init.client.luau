--!strict
-- RIFT HEIST client bootstrap: loading screen -> controllers -> UI -> FX
-- routing -> reveal. Each controller owns one concern; this file only wires
-- them together.

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Events = require(Shared.Config.Events)
local Rarities = require(Shared.Config.Rarities)
local Mutations = require(Shared.Config.Mutations)
local Theme = require(Shared.Config.Theme)
local Locale = require(Shared.Locale)
local Layout = require(Shared.Layout)

local ClientNet = require(script.ClientNet)

local Controllers = script.Controllers
local Store = require(Controllers.Store)
local Settings = require(Controllers.Settings)
local Audio = require(Controllers.Audio)
local MusicDirector = require(Controllers.MusicDirector)
local CameraFX = require(Controllers.CameraFX)
local LightingFX = require(Controllers.LightingFX)
local RelicRenderer = require(Controllers.RelicRenderer)
local RiftFX = require(Controllers.RiftFX)
local SanctuaryFX = require(Controllers.SanctuaryFX)
local CharacterFX = require(Controllers.CharacterFX)
local Abilities = require(Controllers.Abilities)
local AbilityFX = require(Controllers.AbilityFX)
local GrappleTargeting = require(Controllers.GrappleTargeting)
local CosmeticRenderer = require(Controllers.CosmeticRenderer)
local Prompts = require(Controllers.Prompts)
local WorldFX = require(Controllers.WorldFX)
local Tutorial = require(Controllers.Tutorial)

local UI = require(script.UI)
local Kit = script.UI.Kit
local Button = require(Kit.Button)
local Text = require(Kit.Text)
local Juice = require(Kit.Juice)
local Screens = script.UI.Screens
local Loading = require(Screens.Loading)
local TopStack = require(Screens.TopStack)
local Hud = require(Screens.Hud)
local Notifications = require(Screens.Notifications)
local Announcer = require(Screens.Announcer)
local EventBanner = require(Screens.EventBanner)
local Shop = require(Screens.Shop)
local Dex = require(Screens.Dex)
local Inspect = require(Screens.Inspect)
local SettingsMenu = require(Screens.SettingsMenu)
local Discovery = require(Screens.Discovery)
local Loadout = require(Screens.Loadout)
local CosmeticsScreen = require(Screens.Cosmetics)

local localPlayer = Players.LocalPlayer

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

-- 1. Loading screen -------------------------------------------------------------
UI.init()
-- Reward confetti / floating text draw on the unscaled full-screen layer.
Juice.setLayer(UI.fullscreen)
ClientNet.init()
Store.init()
Settings.init()
Loading.show(UI.fullscreen)
Loading.setStatus("loading.building")
while workspace:GetAttribute("WorldReady") ~= true do
	workspace:GetAttributeChangedSignal("WorldReady"):Wait()
end
Loading.setStatus("loading.profile")

-- 2. Controllers ----------------------------------------------------------------
Audio.init()
Button.setSoundHandler(function(key)
	Audio.play(key)
end)
Notifications.setSoundHandler(function(key)
	Audio.play(key)
end)
CameraFX.init()
LightingFX.init()
RelicRenderer.init()
RiftFX.init()
SanctuaryFX.init()
CharacterFX.init()
AbilityFX.init()
GrappleTargeting.init()
CosmeticRenderer.init()
Abilities.init()
Prompts.init()
WorldFX.init()

-- 3. Interface --------------------------------------------------------------------
local stack = TopStack.get(UI.hud)
EventBanner.init(UI.hud)
Notifications.init(UI.hud)
Announcer.init(UI.overlay)
Hud.init(UI.hud, UI.fullscreen, { touch = UI.touch, open = UI.toggle })
UI.registerModal("Shop", Shop.init(UI.modal, UI.close))
UI.registerModal("Dex", Dex.init(UI.modal, UI.close))
UI.registerModal("Settings", SettingsMenu.init(UI.modal, UI.close))
UI.registerModal("Loadout", Loadout.init(UI.modal, UI.close))
UI.registerModal("Cosmetics", CosmeticsScreen.init(UI.modal, UI.close))

-- Abilities screen: L (keyboard) / D-pad up (controller) / HUD button (touch).
game:GetService("UserInputService").InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.L or input.KeyCode == Enum.KeyCode.DPadUp then
		UI.toggle("Loadout")
	elseif input.KeyCode == Enum.KeyCode.C or input.KeyCode == Enum.KeyCode.DPadDown then
		UI.toggle("Cosmetics")
	end
end)

-- Refused ability: one short explanation (no spam).
local lastRefusal = 0
Abilities.refused:Connect(function(abilityId: string, reason: string)
	local text = Abilities.reasonText(abilityId, reason)
	if text ~= "" and os.clock() - lastRefusal > 1.2 then
		lastRefusal = os.clock()
		Notifications.push(text, "warning", 2.2)
	end
end)
UI.registerModal("Inspect", Inspect.init(UI.modal, UI.close))
Discovery.init(UI.overlay, UI.fullscreen)
Tutorial.init({
	touch = UI.touch,
	stack = stack,
	fullscreen = UI.fullscreen,
	pushTip = function(text: string)
		Notifications.push(text, "info", 6.5)
	end,
	menuButton = Hud.menuButton,
})

Prompts.inspect:Connect(function(anchor: BasePart)
	Inspect.show(anchor)
	UI.open("Inspect")
end)

local function announce(main: string, sub: string?, color: Color3?, duration: number?)
	Announcer.show(main, sub, { color = color, duration = duration })
end

-- 4. Server messages ----------------------------------------------------------------
ClientNet.onNotify(function(key: string, args: { [string]: any }, style: string)
	Notifications.fromServer(key, args, style)
	if key == "n.stealAlert" or key == "n.stolen" then
		Hud.flashDanger(1.6)
		CameraFX.shake(0.2)
	end
	if key == "n.stolen" then
		Tutorial.onStolenFromMe()
	end
end)

local function isMe(userId: any): boolean
	return userId == localPlayer.UserId
end

ClientNet.on("RiftCharge", RiftFX.charge)

ClientNet.on("RelicEmerged", function(payload)
	local rarity = Rarities.byId[payload.rarity]
	if not rarity then
		return
	end
	local mutation = Mutations.get(payload.mutation)
	if rarity.order >= 5 then
		local main = Locale.t("ann.relic", { rarity = string.upper(Locale.rarity(rarity.id)) })
		local sub = Locale.t("ann.emerged")
		if mutation then
			sub = Locale.t("ann.mutation", { mutation = string.upper(Locale.mutation(mutation.id)) }) .. "  ·  " .. sub
		end
		announce(main, sub, rarity.color, 3)
	elseif mutation and mutation.order >= 4 then
		announce(Locale.t("ann.incredible"), Locale.t("ann.mutation", { mutation = string.upper(Locale.mutation(mutation.id)) }), mutation.color, 2.4)
	end
end)

ClientNet.on("Pickup", function(payload)
	RelicRenderer.onPickup(payload.uid, payload.userId)
end)

ClientNet.on("Deposit", function(payload)
	RelicRenderer.onDeposit(payload.uid, payload.from, payload.userId)
	if type(payload.plot) == "number" and type(payload.slot) == "number" then
		CosmeticRenderer.secured(payload.userId, Layout.relicPosition(payload.plot, payload.slot))
	end
	if isMe(payload.userId) then
		task.delay(0.6, function()
			CameraFX.shake(0.12)
		end)
	end
end)

ClientNet.on("Fuse", function(payload)
	RelicRenderer.onFuse(payload.uid, payload.target, payload.from, payload.level)
	CosmeticRenderer.secured(payload.userId, RelicRenderer.positionOf(payload.target))
	if isMe(payload.userId) then
		Tutorial.onFuse()
	end
end)

ClientNet.on("Discovery", function(payload)
	task.delay(0.7, function()
		Discovery.show({
			relicId = payload.relicId,
			mutation = payload.mutation,
			isNew = payload.isNew == true,
			isNewMutation = payload.isNewMutation == true,
			found = payload.found,
			total = payload.total,
		})
	end)
end)

ClientNet.on("Collect", function(payload)
	Hud.collect(tonumber(payload.amount) or 0)
end)

ClientNet.on("CoreBurst", function(payload)
	SanctuaryFX.coreBurst(payload.plot)
end)

ClientNet.on("Dropped", function(payload)
	Audio.playAt("Hit", payload.position, { pitch = 1.3 })
end)

ClientNet.on("ReturnHome", function(payload)
	RelicRenderer.onReturnHome(payload.uid)
end)

ClientNet.on("StealAttempt", function(payload)
	RelicRenderer.showSteal(payload.uid, payload.duration)
	CharacterFX.stealAttempt(payload.thiefId, payload.duration)
end)

ClientNet.on("StealCancel", function(payload)
	RelicRenderer.hideSteal(payload.uid)
	CharacterFX.stealEnded(payload.thiefId)
end)

ClientNet.on("Stolen", function(payload)
	RelicRenderer.hideSteal(payload.uid)
	RelicRenderer.onStolen(payload.uid)
	CharacterFX.stealEnded(payload.thiefId)
	if isMe(payload.thiefId) then
		CameraFX.shake(0.25)
		CameraFX.punch(6)
	elseif isMe(payload.victimId) then
		Hud.flashDanger(2.2)
		LightingFX.flash(Theme.Colors.Danger, 0.15, 0.8)
	end
end)

ClientNet.on("HeistSecured", function(payload)
	if isMe(payload.thiefId) then
		local victim = Players:GetPlayerByUserId(payload.victimId)
		announce(Locale.t("n.heistSecured"), Text.format("n.heistSecuredSub", { relic = payload.relicId, victim = if victim then victim.DisplayName else "?" }), Theme.Colors.Gold, 3)
		Audio.play("HeistSecured")
		CameraFX.shake(0.5)
		LightingFX.flash(Theme.Colors.Gold, 0.3, 0.9)
	end
end)

ClientNet.on("Dash", function(payload)
	if not isMe(payload.userId) then
		CharacterFX.dash(payload.userId)
	end
end)

ClientNet.on("Pulse", function(payload)
	if not isMe(payload.userId) then
		CharacterFX.pulse(payload.position, payload.userId)
	end
end)

ClientNet.on("Hit", function(payload)
	CharacterFX.hit(payload.userId)
	if isMe(payload.userId) then
		Hud.flashDanger(0.6)
	end
end)

ClientNet.on("Seal", function(payload)
	SanctuaryFX.seal(payload.plot, true)
end)

ClientNet.on("Unseal", function(payload)
	SanctuaryFX.seal(payload.plot, false)
end)

ClientNet.on("TierUp", function(payload)
	SanctuaryFX.tierUp(payload.plot, payload.tier, payload.userId)
	if isMe(payload.userId) then
		announce(Locale.t("tier." .. payload.tier), Locale.t("n.tierUp", { tier = Locale.t("tier." .. payload.tier) }), Theme.Colors.Gold, 3)
	end
end)

ClientNet.on("Dissolve", function(payload)
	if isMe(payload.userId) then
		Hud.pulseEssence()
		Audio.play("EssenceCollect", { pitch = 1.2 })
	end
end)

ClientNet.on("EventStart", function(payload)
	local def = Events.get(payload.id)
	if not def then
		return
	end
	announce(Locale.t("event." .. def.id .. ".name"), Locale.t("event." .. def.id .. ".desc"), def.color, 3.4)
	Audio.play("EventStart")
	CameraFX.shake(0.25)
	LightingFX.flash(def.color, 0.3, 1.6)
end)

-- 5. Reveal -------------------------------------------------------------------------
ClientNet.fire(Net.Events.ClientReady)
Store.waitReady()
if not localPlayer.Character then
	local deadline = os.clock() + 25
	while not localPlayer.Character and os.clock() < deadline do
		task.wait(0.1)
	end
end
task.wait(0.4)
Loading.hide()
Audio.startAmbience()
MusicDirector.start()
task.delay(1, function()
	Tutorial.playIntro(function(main: string, sub: string?)
		announce(main, sub, Theme.Colors.Essence, 3.6)
	end)
end)

