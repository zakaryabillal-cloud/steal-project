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
local Landmarks = require(script.Parent.Landmarks)
local Outskirts = require(script.Parent.Outskirts)

local WorldBuilder = {}

local function register(name: string)
	if not PhysicsService:IsCollisionGroupRegistered(name) then
		PhysicsService:RegisterCollisionGroup(name)
	end
end

-- Each Sanctuary barrier only blocks non-owners: owners' characters are moved
-- to "Owner<i>", which does not collide with "Barrier<i>". Players without a
-- Sanctuary yet are in "Wanderer".
-- Spectral Phase (V2 phase 4): a phasing player is moved to "Phase<i>" (i = 0
-- without a Sanctuary), which passes through every player group but still
-- collides with the world and with the other Sanctuaries' barriers.
-- 8 Barrier + 8 Owner + Wanderer + 9 Phase + Default = 27 groups (limit 32).
local function registerCollisionGroups()
	register("Wanderer")
	local players: { string } = { "Wanderer" }
	for i = 1, Layout.PlotCount do
		local barrier = "Barrier" .. i
		local owner = "Owner" .. i
		register(barrier)
		register(owner)
		PhysicsService:CollisionGroupSetCollidable(barrier, owner, false)
		table.insert(players, owner)
	end
	local phases: { string } = {}
	for i = 0, Layout.PlotCount do
		local phase = "Phase" .. i
		register(phase)
		table.insert(phases, phase)
		if i > 0 then
			PhysicsService:CollisionGroupSetCollidable(phase, "Barrier" .. i, false)
		end
	end
	for _, phase in phases do
		for _, other in players do
			PhysicsService:CollisionGroupSetCollidable(phase, other, false)
		end
		for _, other in phases do
			PhysicsService:CollisionGroupSetCollidable(phase, other, false)
		end
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
	-- V2 world: landmarks and level-design features of the outer crown.
	Landmarks.build(world)
	Outskirts.build(world)

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
