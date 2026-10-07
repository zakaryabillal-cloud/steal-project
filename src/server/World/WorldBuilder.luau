--!strict
-- Orchestrates world generation at server start. Clients wait for the
-- workspace "WorldReady" attribute before revealing the game.

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Layout = require(ReplicatedStorage.Shared.Layout)
local Parts = require(script.Parent.Parts)
local TerrainBuilder = require(script.Parent.TerrainBuilder)
local RiftBuilder = require(script.Parent.RiftBuilder)
local Props = require(script.Parent.Props)
local SanctuaryBuilder = require(script.Parent.SanctuaryBuilder)

local WorldBuilder = {}

-- Each Sanctuary barrier only blocks non-owners: owners' characters are moved
-- to "Owner<i>", which does not collide with "Barrier<i>".
local function registerCollisionGroups()
	for i = 1, Layout.PlotCount do
		local barrier = "Barrier" .. i
		local owner = "Owner" .. i
		if not PhysicsService:IsCollisionGroupRegistered(barrier) then
			PhysicsService:RegisterCollisionGroup(barrier)
		end
		if not PhysicsService:IsCollisionGroupRegistered(owner) then
			PhysicsService:RegisterCollisionGroup(owner)
		end
		PhysicsService:CollisionGroupSetCollidable(barrier, owner, false)
	end
end

function WorldBuilder.build()
	local started = os.clock()
	workspace:SetAttribute("WorldReady", false)
	registerCollisionGroups()

	local isletTops = TerrainBuilder.build()
	local world = Parts.folder("World", workspace)
	RiftBuilder.build(world)
	Props.build(world, isletTops)

	local clouds = Instance.new("Clouds")
	clouds.Cover = 0.42
	clouds.Density = 0.22
	clouds.Color = Color3.fromRGB(180, 160, 230)
	clouds.Parent = workspace.Terrain

	local sanctuaries = Parts.folder("Sanctuaries", workspace)
	for i = 1, Layout.PlotCount do
		SanctuaryBuilder.create(i, sanctuaries)
	end

	Parts.folder("Relics", workspace)
	workspace:SetAttribute("WorldReady", true)
	print(string.format("[RiftHeist] World built in %.2fs", os.clock() - started))
end

return WorldBuilder
