--!strict
-- World layout shared by the world builder (server) and every client system
-- that needs to know where things are (tutorial beams, Rift FX, minimap math).
--
--   Top view (not to scale):
--
--          S1          The Rift sits in a terraced basin at the centre.
--      S8      S2      A river ring with 4 bridges + 4 stepping-stone fords
--    S7   RIFT   S3    separates the inner meadow from the outer ring road,
--      S6      S4      where the 8 Sanctuaries stand on raised foundations.
--          S5          Everything floats on an island in a cosmic sky.

local Layout = {}

Layout.GroundY = 20
Layout.BasinY = 6
Layout.BasinRadius = 40
Layout.RimRadius = 58
Layout.MeadowRadius = 84

Layout.RiverInner = 86
Layout.RiverOuter = 104
Layout.RiverCenter = 95
Layout.RiverBedY = 9
Layout.WaterY = 16.5

Layout.RingRoadRadius = 110
-- V2: 236 -> 276 (+37 % area). Sanctuaries keep PlotDistance, so trips are not longer:
-- the new space is the outer crown behind them (see Shared/WorldFeatures).
Layout.IslandRadius = 276

Layout.DaisRadius = 13
Layout.DaisTopY = 8
Layout.RiftCore = Vector3.new(0, 44, 0)
Layout.RiftHeight = 50

Layout.PlotCount = 8
Layout.PlotDistance = 172
Layout.PlatformRadius = 36
Layout.PlatformHeight = 10
Layout.RampLength = 20
Layout.GateWidth = 18

Layout.BridgeAngles = { 22.5, 112.5, 202.5, 292.5 }
Layout.FordAngles = { 67.5, 157.5, 247.5, 337.5 }

-- Pedestal ring inside a Sanctuary, angles measured from the back (+Z) toward
-- the sides; the 63 degree gap at the front is the entrance aisle.
Layout.SlotRadius = 19
Layout.SlotAngles = { -13.5, 13.5, -40.5, 40.5, -67.5, 67.5, -94.5, 94.5, -121.5, 121.5, -148.5, 148.5 }
Layout.PedestalHeight = 3.2
Layout.RelicHover = 3.6

function Layout.plotAngle(index: number): number
	return math.rad((index - 1) * 45 - 90)
end

-- Top-centre of the Sanctuary platform. LookVector (-Z) faces the Rift.
function Layout.plotCFrame(index: number): CFrame
	local angle = Layout.plotAngle(index)
	local top = Layout.GroundY + Layout.PlatformHeight
	local position = Vector3.new(math.cos(angle) * Layout.PlotDistance, top, math.sin(angle) * Layout.PlotDistance)
	return CFrame.lookAt(position, Vector3.new(0, top, 0))
end

function Layout.slotLocal(slot: number): CFrame
	local angle = math.rad(Layout.SlotAngles[slot])
	local position = Vector3.new(math.sin(angle) * Layout.SlotRadius, 0, math.cos(angle) * Layout.SlotRadius)
	-- Pedestals face the Sanctuary centre.
	return CFrame.lookAt(position, Vector3.new(0, 0, 0))
end

-- World position a relic hovers at above a pedestal.
function Layout.relicPosition(plot: number, slot: number): Vector3
	local cf = Layout.plotCFrame(plot) * Layout.slotLocal(slot)
	return cf.Position + Vector3.new(0, Layout.PedestalHeight + Layout.RelicHover, 0)
end

-- Gate centre on the platform edge, and the foot of the entrance ramp.
function Layout.gateCFrame(plot: number): CFrame
	return Layout.plotCFrame(plot) * CFrame.new(0, 0, -Layout.PlatformRadius)
end

function Layout.rampFoot(plot: number): Vector3
	return (Layout.plotCFrame(plot) * CFrame.new(0, -Layout.PlatformHeight, -(Layout.PlatformRadius + Layout.RampLength))).Position
end

function Layout.spawnCFrame(plot: number): CFrame
	return Layout.plotCFrame(plot) * CFrame.new(0, 3, -12)
end

function Layout.coreCFrame(plot: number): CFrame
	return Layout.plotCFrame(plot)
end

-- Relic spawn spots around the Rift. Spot 1 is the Apex (centre dais), used
-- by Legendary+ relics. Spots 10-11 sit on floating islands reached by
-- bounce pads.
export type Spot = { position: Vector3, kind: string }

local spots: { Spot } = {}
table.insert(spots, { position = Vector3.new(0, Layout.DaisTopY + 3.8, 0), kind = "Apex" })
for i = 0, 7 do
	local a = math.rad(22.5 + i * 45)
	table.insert(spots, { position = Vector3.new(math.cos(a) * 25, Layout.BasinY + 1 + 3.6, math.sin(a) * 25), kind = "Ring" })
end
Layout.FloatingIslands = {
	Vector3.new(31, 21, 0),
	Vector3.new(-31, 21, 0),
}
for _, island in Layout.FloatingIslands do
	table.insert(spots, { position = island + Vector3.new(0, 1 + 3.6, 0), kind = "High" })
end
Layout.Spots = spots

-- World structure colours: the cartoon palette (Config/Palette.World).
Layout.Colors = require(script.Parent.Config.Palette).World

return Layout
