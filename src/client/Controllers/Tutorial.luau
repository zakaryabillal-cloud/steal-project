--!strict
-- Onboarding that teaches by playing:
--   intro    camera sweep toward the Rift: "A Rift has opened."
--   step 0   grab a relic (waypoint to the nearest one)
--   step 1   bring it home (waypoint to your gate)
--   step 2   collect Essence at your Core
--   step 3   buy an upgrade (the Upgrades button pulses)
-- Afterwards, one-time contextual tips introduce stealing, Pulse, Seal, Dash
-- and fusion when they become relevant.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Layout = require(Shared.Layout)
local Locale = require(Shared.Locale)
local Net = require(Shared.Net)
local Theme = require(Shared.Config.Theme)
local Emoji = require(Shared.Config.Emoji)

local UIRoot = script.Parent.Parent.UI
local Kit = UIRoot.Kit
local Create = require(Kit.Create)
local Style = require(Kit.Style)
local Tween = require(Kit.Tween)
local Icons = require(Kit.Icons)

local ClientNet = require(script.Parent.Parent.ClientNet)
local Store = require(script.Parent.Store)
local RelicRenderer = require(script.Parent.RelicRenderer)
local SanctuaryFX = require(script.Parent.SanctuaryFX)
local Audio = require(script.Parent.Audio)

local Tutorial = {}

local localPlayer = Players.LocalPlayer
local touch = false
local pushTip: (string) -> () = function(_text: string) end
local menuButton: (string) -> GuiObject? = function(_name: string)
	return nil
end

-- Objective pill
local objective: Frame
local objectiveText: TextLabel
local objectiveScale: UIScale
local currentText = ""

-- Waypoint
local markerPart: Part
local marker: BillboardGui
local markerDistance: TextLabel
local edgeArrow: Frame
local fullscreen: Frame
local target: Vector3? = nil

-- Upgrades button pointer
local pointer: Frame
local pointerTarget: GuiObject? = nil

local shownTips: { [string]: boolean } = {}

local function rootPart(): BasePart?
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

----------------------------------------------------------------------------
-- UI pieces
----------------------------------------------------------------------------

local function buildObjective(stack: Instance)
	objective = Style.panel({
		Name = "Objective",
		Size = UDim2.fromOffset(0, 46),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 20,
		Visible = false,
		Parent = stack,
	})
	Style.corner(objective, UDim.new(1, 0))
	objective.BackgroundColor3 = Theme.Buttons.yellow.face
	objectiveScale = Create("UIScale", { Parent = objective })
	Style.padding(objective, 0, 18)
	Style.list(objective, 10, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	local tag = Create("Frame", { Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Theme.Buttons.orange.face, LayoutOrder = 1, Parent = objective })
	Style.corner(tag, UDim.new(1, 0))
	Style.stroke(tag, Theme.Colors.Ink, 0, 2)
	Style.padding(tag, 0, 10)
	local tagLabel = Style.text({ Name = "Tag", Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, Text = Emoji.label("goal", Locale.t("tut.objective")), TextSize = 13, FontFace = Theme.Fonts.Heavy, Parent = tag })
	Style.ink(tagLabel, 1.5)
	objectiveText = Style.text({ Size = UDim2.fromOffset(0, 46), AutomaticSize = Enum.AutomaticSize.X, TextSize = 20, FontFace = Theme.Fonts.Display, LayoutOrder = 2, Parent = objective })
	Style.ink(objectiveText, 2)
end

local function buildWaypoint()
	markerPart = Instance.new("Part")
	markerPart.Name = "TutorialTarget"
	markerPart.Size = Vector3.one
	markerPart.Transparency = 1
	markerPart.Anchored = true
	markerPart.CanCollide = false
	markerPart.CanQuery = false
	markerPart.CanTouch = false
	markerPart.Parent = workspace
	-- Soft sky beam over the target.
	local bottom = Instance.new("Attachment")
	bottom.Parent = markerPart
	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, 90, 0)
	top.Parent = markerPart
	local beam = Instance.new("Beam")
	beam.Attachment0 = bottom
	beam.Attachment1 = top
	beam.Width0 = 2.4
	beam.Width1 = 0.4
	beam.Color = ColorSequence.new(Theme.Colors.Gold)
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Parent = markerPart

	marker = Create("BillboardGui", {
		Name = "TutorialMarker",
		Size = UDim2.fromOffset(90, 70),
		StudsOffsetWorldSpace = Vector3.new(0, 7, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		ResetOnSpawn = false,
		Adornee = markerPart,
		Enabled = false,
		Parent = localPlayer:WaitForChild("PlayerGui"),
	})
	local diamond = Create("Frame", {
		Size = UDim2.fromOffset(30, 30),
		Position = UDim2.new(0.5, 0, 0, 6),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Parent = marker,
	})
	Icons.essence(diamond)
	markerDistance = Style.text({ Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 40), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 16, FontFace = Theme.Fonts.Heavy, Parent = marker })
	Style.ink(markerDistance, 2.5)
	markerDistance.FontFace = Theme.Fonts.Display

	edgeArrow = Create("Frame", {
		Name = "EdgeArrow",
		Size = UDim2.fromOffset(46, 46),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Theme.Buttons.yellow.face,
		Visible = false,
		Parent = fullscreen,
	})
	Style.corner(edgeArrow, UDim.new(1, 0))
	Style.stroke(edgeArrow, Theme.Colors.Ink, 0, 3)
	local arrowHolder = Create("Frame", { Name = "Arrow", Size = UDim2.fromScale(0.6, 0.6), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Parent = edgeArrow })
	Icons.arrow(arrowHolder, Theme.Colors.Ink)
end

local function buildPointer()
	pointer = Create("Frame", {
		Name = "Pointer",
		Size = UDim2.fromOffset(40, 40),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = fullscreen,
	})
	local holder = Create("Frame", { Size = UDim2.fromScale(1, 1), Rotation = 90, BackgroundTransparency = 1, Parent = pointer })
	Icons.arrow(holder, Theme.Colors.Gold)
end

local function setObjective(text: string?)
	if text == nil then
		if objective.Visible then
			Tween.play(objectiveScale, 0.2, { Scale = 0.6 })
			task.delay(0.2, function()
				if currentText == "" then
					objective.Visible = false
				end
			end)
		end
		currentText = ""
		return
	end
	if text == currentText then
		return
	end
	currentText = text
	objectiveText.Text = text
	objective.Visible = true
	objectiveScale.Scale = 0.5
	Tween.play(objectiveScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
	Tween.wiggle(objective, 5)
	Audio.play("Notify", { pitch = 1.2 })
end

----------------------------------------------------------------------------
-- Logic
----------------------------------------------------------------------------

local function nearestRiftRelic(from: Vector3): Vector3?
	local best: Vector3? = nil
	local bestDistance = math.huge
	for _, record in RelicRenderer.records do
		if record.state == "Rift" and record.vanishStart == nil then
			local distance = (record.anchor.Position - from).Magnitude
			if distance < bestDistance then
				bestDistance = distance
				best = record.anchor.Position
			end
		end
	end
	return best
end

local function evaluate()
	local state = Store.state
	local step = state.tutorial
	local root = rootPart()
	target = nil
	pointerTarget = nil
	if step >= 4 or not Store.ready then
		setObjective(nil)
		return
	end
	if step <= 1 and #state.carrying == 0 then
		setObjective(Locale.t("tut.claim"))
		target = if root then nearestRiftRelic(root.Position) else nil
		target = target or Layout.RiftCore - Vector3.new(0, 30, 0)
	elseif step <= 1 then
		setObjective(Locale.t("tut.return"))
		if state.plot ~= 0 then
			target = Layout.plotCFrame(state.plot).Position
		end
	elseif step == 2 then
		setObjective(Locale.t("tut.collect"))
		if state.plot ~= 0 then
			target = SanctuaryFX.corePosition(state.plot) or Layout.plotCFrame(state.plot).Position
		end
	elseif step == 3 then
		setObjective(Locale.t("tut.upgrade"))
		pointerTarget = menuButton("Shop")
	end
end

local function keyFor(action: string): string
	if touch then
		return Locale.t("ability." .. action)
	end
	local keys = { steal = "E", pulse = "F", dash = "Q", seal = "G" }
	return keys[action] or "E"
end

local function tip(name: string)
	if shownTips[name] or Store.state.tips[name] then
		return
	end
	shownTips[name] = true
	ClientNet.fire(Net.Events.TutorialSeen, name)
	pushTip(Locale.t("tip." .. name, { key = keyFor(name) }))
end

local function updateTips(elapsed: number)
	local state = Store.state
	if state.tutorial < 4 then
		return
	end
	if elapsed > 25 then
		tip("dash")
	end
	if elapsed > 70 then
		-- Stealing becomes interesting once a neighbour has something to take.
		local folder = workspace:FindFirstChild("Sanctuaries")
		if folder then
			for _, model in folder:GetChildren() do
				local owner = model:GetAttribute("OwnerId")
				local placed = model:GetAttribute("PlacedCount")
				if type(owner) == "number" and owner ~= 0 and owner ~= localPlayer.UserId and type(placed) == "number" and placed >= 3 then
					tip("steal")
					break
				end
			end
		end
	end
	if elapsed > 200 then
		tip("pulse")
	end
	-- Leaving home with a collection worth protecting.
	local root = rootPart()
	local plot = state.plot
	if root and plot ~= 0 then
		local home = Layout.plotCFrame(plot).Position
		local model = Store.plotModel()
		local placed = if model then model:GetAttribute("PlacedCount") else 0
		if type(placed) == "number" and placed >= 3 and (root.Position - home).Magnitude > 70 then
			tip("seal")
		end
	end
end

function Tutorial.onFuse()
	tip("fuse")
end

function Tutorial.onStolenFromMe()
	tip("pulse")
end

-- First-join camera sweep toward the Rift.
function Tutorial.playIntro(announce: (string, string?) -> ())
	if Store.state.tutorial > 0 or Store.state.tips.intro then
		return
	end
	ClientNet.fire(Net.Events.TutorialSeen, "intro")
	local camera = workspace.CurrentCamera
	local plot = Store.state.plot
	if not camera or plot == 0 then
		announce(Locale.t("tut.intro"), Locale.t("tut.introSub"))
		return
	end
	local home = Layout.plotCFrame(plot)
	local startCf = CFrame.lookAt((home * CFrame.new(0, 45, 60)).Position, Layout.RiftCore)
	local endCf = CFrame.lookAt((home * CFrame.new(0, 26, -60)).Position, Layout.RiftCore + Vector3.new(0, -6, 0))
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = startCf
	announce(Locale.t("tut.intro"), Locale.t("tut.introSub"))
	Audio.play("RareEmerge", { volume = 0.5, pitch = 1.1 })
	local tween = Tween.play(camera, 3.4, { CFrame = endCf }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	tween.Completed:Wait()
	task.wait(0.4)
	camera.CameraType = Enum.CameraType.Custom
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

export type Options = {
	touch: boolean,
	stack: Instance,
	fullscreen: Frame,
	pushTip: (string) -> (),
	menuButton: (string) -> GuiObject?,
}

function Tutorial.init(options: Options)
	touch = options.touch
	pushTip = options.pushTip
	menuButton = options.menuButton
	fullscreen = options.fullscreen
	buildObjective(options.stack)
	buildWaypoint()
	buildPointer()

	local previousStep = Store.state.tutorial
	Store.changed:Connect(function(state)
		if previousStep < 4 and state.tutorial >= 4 and Store.ready then
			pushTip(Locale.t("tut.done"))
			Audio.play("TierUp", { volume = 0.5, pitch = 1.3 })
		end
		previousStep = state.tutorial
		evaluate()
	end)
	Locale.changed:Connect(function()
		currentText = ""
		local tag = objective:FindFirstChild("Tag", true) :: TextLabel?
		if tag then
			tag.Text = Locale.t("tut.objective")
		end
		evaluate()
	end)

	local started = os.clock()
	local evalTimer = 0
	local tipTimer = 0
	RunService.RenderStepped:Connect(function(dt)
		evalTimer += dt
		tipTimer += dt
		if evalTimer > 0.5 then
			evalTimer = 0
			evaluate()
		end
		if tipTimer > 2 then
			tipTimer = 0
			updateTips(os.clock() - started)
		end

		local camera = workspace.CurrentCamera
		local root = rootPart()
		if target and camera and root then
			markerPart.CFrame = CFrame.new(target)
			marker.Enabled = true
			local distance = (target - root.Position).Magnitude
			markerDistance.Text = string.format("%dm", math.floor(distance))
			local screen, onScreen = camera:WorldToViewportPoint(target + Vector3.new(0, 6, 0))
			if onScreen and screen.Z > 0 then
				edgeArrow.Visible = false
			else
				local viewport = camera.ViewportSize
				local center = viewport / 2
				local direction = Vector2.new(screen.X, screen.Y) - center
				if screen.Z < 0 then
					direction = -direction
				end
				if direction.Magnitude < 1 then
					direction = Vector2.new(0, 1)
				end
				local unit = direction.Unit
				local margin = 60
				local scaleX = (center.X - margin) / math.max(math.abs(unit.X), 0.001)
				local scaleY = (center.Y - margin) / math.max(math.abs(unit.Y), 0.001)
				local edge = center + unit * math.min(scaleX, scaleY)
				edgeArrow.Position = UDim2.fromOffset(edge.X, edge.Y)
				local arrow = edgeArrow:FindFirstChild("Arrow") :: Frame?
				if arrow then
					arrow.Rotation = math.deg(math.atan2(unit.Y, unit.X)) - 90
				end
				edgeArrow.Visible = true
			end
		else
			marker.Enabled = false
			edgeArrow.Visible = false
			markerPart.CFrame = CFrame.new(0, -500, 0)
		end

		if pointerTarget and pointerTarget.Parent then
			local inset = GuiService:GetGuiInset()
			local position = pointerTarget.AbsolutePosition + inset
			local size = pointerTarget.AbsoluteSize
			local bounce = math.sin(os.clock() * 6) * 8
			pointer.Position = UDim2.fromOffset(position.X + size.X + 10 + bounce, position.Y + size.Y / 2)
			pointer.Visible = true
		else
			pointer.Visible = false
		end
	end)
	evaluate()
end

return Tutorial
