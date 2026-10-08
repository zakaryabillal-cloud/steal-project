--!strict
-- Grapple target selection (client side, display + request only).
--
-- While Grapple is equipped, picks the anchor the player most likely means:
-- within range, in line of sight, closest to where the camera looks (else the
-- nearest). The chosen anchor gets a marker (ring + key hint); out of
-- cooldown it is bright, on cooldown dimmed. The server re-checks range and
-- line of sight itself; the client only names an anchor index.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local WorldFeatures = require(Shared.WorldFeatures)
local GameConfig = require(Shared.Config.GameConfig)
local AbilityConfig = require(Shared.Config.Abilities)
local Bosses = require(Shared.Config.Bosses)

local Kit = script.Parent.Parent.UI.Kit
local Create = require(Kit.Create)
local Style = require(Kit.Style)

local Store = require(script.Parent.Store)

local GrappleTargeting = {}

local TUNING = GameConfig.Abilities.Grapple
local COLOR = Color3.fromRGB(110, 235, 255)

local localPlayer = Players.LocalPlayer
local current: number? = nil
local marker: BillboardGui
local markerPart: Part
local keyLabel: TextLabel
local ring: Frame

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.IgnoreWater = true
params.RespectCanCollide = true

local function refreshFilter()
	local filter: { Instance } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(filter, player.Character)
		end
	end
	for _, name in { "Relics", "Abilities", "AbilityFX", "CharacterFXWorld" } do
		local found = workspace:FindFirstChild(name)
		if found then
			table.insert(filter, found)
		end
	end
	local world = workspace:FindFirstChild("World")
	local anchors = world and world:FindFirstChild("GrapplePoints")
	if anchors then
		table.insert(filter, anchors)
	end
	params.FilterDescendantsInstances = filter
end

function GrappleTargeting.equipped(): boolean
	return table.find(Store.state.loadout, "grapple") ~= nil
end

-- Anchors usable right now: the world's, or (phase 6.5) the 4 floating
-- bubbles of the boss arena while fighting there.
function GrappleTargeting.anchors(): { { index: number, position: Vector3 } }
	local fightId = localPlayer:GetAttribute("BossFight")
	if type(fightId) == "string" and fightId ~= "" then
		return Bosses.arenaGrapplePoints()
	end
	local list = {}
	for index, spec in WorldFeatures.GrapplePoints do
		table.insert(list, { index = index, position = spec.position })
	end
	return list
end

local function anchorPosition(index: number): Vector3?
	for _, anchor in GrappleTargeting.anchors() do
		if anchor.index == index then
			return anchor.position
		end
	end
	return nil
end

-- Best anchor index for a head position and look direction, or nil.
function GrappleTargeting.pick(head: Vector3, look: Vector3): number?
	local best: number? = nil
	local bestScore = math.huge
	for _, anchor in GrappleTargeting.anchors() do
		local index = anchor.index
		local offset = anchor.position - head
		local distance = offset.Magnitude
		if distance > TUNING.Range or distance < TUNING.MinDistance then
			continue
		end
		local direction = offset.Unit
		if workspace:Raycast(head, direction * (distance - 1.2), params) ~= nil then
			continue
		end
		-- Prefer what the camera points at; distance breaks ties.
		local angle = math.acos(math.clamp(direction:Dot(look), -1, 1))
		local score = if angle < math.rad(40) then angle * 20 + distance * 0.1 else 100 + distance
		if score < bestScore then
			best, bestScore = index, score
		end
	end
	return best
end

function GrappleTargeting.current(): number?
	return current
end

local function keyText(): string
	local slot = AbilityConfig.Slots[1]
	if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "R1"
	end
	return slot.keyboard.Name
end

local function update()
	if not GrappleTargeting.equipped() then
		current = nil
		marker.Enabled = false
		return
	end
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	if not root or not root:IsA("BasePart") or not camera then
		current = nil
		marker.Enabled = false
		return
	end
	refreshFilter()
	current = GrappleTargeting.pick(root.Position + Vector3.new(0, 1.5, 0), camera.CFrame.LookVector)
	if current then
		local position = anchorPosition(current) :: Vector3
		markerPart.CFrame = CFrame.new(position)
		marker.Enabled = true
		local ready = Store.cooldownRemaining("grapple") <= 0
		ring.BackgroundTransparency = if ready then 0.35 else 0.8
		keyLabel.Text = keyText()
		keyLabel.TextTransparency = if ready then 0 else 0.6
	else
		marker.Enabled = false
	end
end

function GrappleTargeting.init()
	markerPart = Instance.new("Part")
	markerPart.Name = "GrappleTarget"
	markerPart.Size = Vector3.one * 0.2
	markerPart.Transparency = 1
	markerPart.Anchored = true
	markerPart.CanCollide = false
	markerPart.CanQuery = false
	markerPart.CanTouch = false
	markerPart.Parent = workspace:FindFirstChild("AbilityFX") or workspace
	marker = Create("BillboardGui", {
		Name = "GrappleMarker",
		Size = UDim2.fromOffset(64, 64),
		AlwaysOnTop = true,
		LightInfluence = 0,
		Enabled = false,
		Adornee = markerPart,
		Parent = localPlayer:WaitForChild("PlayerGui"),
	})
	ring = Create("Frame", {
		Size = UDim2.fromOffset(40, 40),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = COLOR,
		BackgroundTransparency = 0.35,
		Parent = marker,
	})
	Style.corner(ring, UDim.new(1, 0))
	Style.stroke(ring, Color3.new(1, 1, 1), 0, 2)
	keyLabel = Style.text({
		Size = UDim2.fromScale(1, 1),
		Text = keyText(),
		TextSize = 16,
		FontFace = Style.Fonts.Heavy,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.fromRGB(10, 20, 30),
		Parent = ring,
	})
	local timer = 0
	RunService.RenderStepped:Connect(function(dt)
		timer += dt
		if timer >= 0.1 then
			timer = 0
			update()
		end
	end)
end

return GrappleTargeting
