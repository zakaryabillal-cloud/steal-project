--!strict
-- Shows a relic model inside a ViewportFrame (HUD icons, RiftDex, reveal
-- cards). Unknown relics render as black silhouettes. Spinning viewports
-- share one render loop and skip work while hidden.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Factory = require(ReplicatedStorage.Shared.Relics.RelicFactory)
local Create = require(script.Parent.Create)

local RelicViewport = {}

export type Viewport = {
	frame: ViewportFrame,
	camera: Camera,
	visual: Factory.Visual?,
	spin: boolean,
	angle: number,
	distance: number,
	set: (self: Viewport, relicId: string?, mutation: string?, silhouette: boolean?) -> (),
	destroy: (self: Viewport) -> (),
}

local spinning: { [Viewport]: boolean } = {}
local loopStarted = false

local function frameCamera(viewport: Viewport)
	local height = viewport.distance * 0.18
	viewport.camera.CFrame = CFrame.lookAt(
		Vector3.new(math.sin(viewport.angle) * viewport.distance, height, math.cos(viewport.angle) * viewport.distance),
		Vector3.zero
	)
end

local function ensureLoop()
	if loopStarted then
		return
	end
	loopStarted = true
	RunService.RenderStepped:Connect(function(dt: number)
		for viewport in spinning do
			local frame = viewport.frame
			if frame.Parent == nil then
				spinning[viewport] = nil
			elseif frame.Visible and frame.AbsoluteSize.X > 0 then
				viewport.angle += dt * 0.8
				frameCamera(viewport)
			end
		end
	end)
end

local methods = {}
methods.__index = methods

function methods.set(self: Viewport, relicId: string?, mutation: string?, silhouette: boolean?)
	if self.visual then
		Factory.destroy(self.visual)
		self.visual = nil
	end
	if not relicId then
		return
	end
	local visual = Factory.build(relicId, mutation, { preview = true })
	if not visual then
		return
	end
	visual.root.CFrame = CFrame.identity
	for _, part in visual.parts do
		local weld = part:FindFirstChildOfClass("Weld")
		if weld then
			part.CFrame = weld.C0
		end
	end
	visual.model.Parent = self.frame
	self.visual = visual
	self.distance = visual.scale * 6.2
	self.frame.ImageColor3 = if silhouette then Color3.new(0, 0, 0) else Color3.new(1, 1, 1)
	self.frame.ImageTransparency = if silhouette then 0.15 else 0
	frameCamera(self)
end

function methods.destroy(self: Viewport)
	spinning[self] = nil
	if self.visual then
		Factory.destroy(self.visual)
	end
	self.frame:Destroy()
end

export type Props = {
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	parent: Instance?,
	spin: boolean?,
	zIndex: number?,
}

function RelicViewport.new(props: Props): Viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = 34
	local frame: ViewportFrame = Create("ViewportFrame", {
		Size = props.size,
		Position = props.position or UDim2.new(),
		AnchorPoint = props.anchor or Vector2.zero,
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(150, 140, 185),
		LightColor = Color3.fromRGB(255, 248, 235),
		LightDirection = Vector3.new(-1, -1.2, -0.6),
		CurrentCamera = camera,
		ZIndex = props.zIndex or 1,
	})
	camera.Parent = frame
	local viewport: Viewport = setmetatable({
		frame = frame,
		camera = camera,
		visual = nil,
		spin = props.spin ~= false,
		-- Look at the front (-Z) of the relic, where faces are (Phase 5.5).
		angle = math.pi + 0.5,
		distance = 6,
	}, methods) :: any
	if viewport.spin then
		ensureLoop()
		spinning[viewport] = true
	end
	if props.parent then
		frame.Parent = props.parent
	end
	return viewport
end

return RelicViewport
