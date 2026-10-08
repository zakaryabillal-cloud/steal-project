--!strict
-- Boss weapon models (V2 phase 6.5), built from native parts only (no mesh,
-- no asset id). Shared by the server (the weapon held in the hand(s) of a
-- fighter, replicated to everyone) and the client (shop preview).
--
-- Every piece is described in "grip space": the origin is the fist, the
-- weapon extends along -Y (down the hanging arm; forward when the arm is
-- raised in a strike). Gloves have one piece per hand.

local WeaponsConfig = require(script.Parent.Parent.Config.Weapons)

local WeaponModels = {}

export type Piece = {
	part: BasePart,
	-- Grip-space CFrame of the piece.
	offset: CFrame,
	-- "right" | "left"
	hand: string,
}

export type Built = {
	model: Model,
	pieces: { Piece },
}

local WHITE = Color3.new(1, 1, 1)
local INK = Color3.fromRGB(30, 27, 75)

local function newPart(kind: string, size: Vector3, color: Color3, material: Enum.Material?): BasePart
	local part: BasePart
	if kind == "Ball" then
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Ball
		part = p
	elseif kind == "Cylinder" then
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Cylinder
		part = p
	elseif kind == "Ellipsoid" then
		local p = Instance.new("Part")
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
		part = p
	else
		part = Instance.new("Part")
	end
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

-- Vertical (grip-axis) cylinder: diameter d, length l, centred at y.
local function stick(pieces: { Piece }, d: number, l: number, y: number, color: Color3, hand: string?, material: Enum.Material?)
	local part = newPart("Cylinder", Vector3.new(l, d, d), color, material)
	table.insert(pieces, { part = part, offset = CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.pi / 2), hand = hand or "right" })
end

local function piece(pieces: { Piece }, part: BasePart, offset: CFrame, hand: string?)
	table.insert(pieces, { part = part, offset = offset, hand = hand or "right" })
end

local BUILDERS: { [string]: (WeaponsConfig.WeaponDef, { Piece }) -> () } = {
	gloves = function(def, pieces)
		local v = def.visual
		for _, hand in { "right", "left" } do
			piece(pieces, newPart("Ball", Vector3.one * 1.7, v.color), CFrame.new(0, -0.55, 0), hand)
			piece(pieces, newPart("Ball", Vector3.one * 0.7, v.color), CFrame.new(if hand == "right" then -0.7 else 0.7, -0.3, -0.35), hand)
			piece(pieces, newPart("Cylinder", Vector3.new(0.5, 1.2, 1.2), v.cuff), CFrame.new(0, 0.35, 0) * CFrame.Angles(0, 0, math.pi / 2), hand)
		end
	end,
	mallet = function(def, pieces)
		local v = def.visual
		stick(pieces, 0.35, 3.2, -1.2, v.handle)
		piece(pieces, newPart("Cylinder", Vector3.new(2.4, 1.5, 1.5), v.head), CFrame.new(0, -3, 0))
		for _, x in { -0.75, 0.75 } do
			piece(pieces, newPart("Cylinder", Vector3.new(0.22, 1.6, 1.6), v.band), CFrame.new(x, -3, 0))
		end
	end,
	blaster = function(def, pieces)
		local v = def.visual
		piece(pieces, newPart("Block", Vector3.new(0.9, 2, 1), v.body), CFrame.new(0, -1, 0))
		piece(pieces, newPart("Ball", Vector3.one * 1.1, v.tank, Enum.Material.Glass), CFrame.new(0, -0.7, 0.85))
		stick(pieces, 0.45, 1.2, -2.5, v.barrel)
		stick(pieces, 0.7, 0.25, -3.1, WHITE)
	end,
	wand = function(def, pieces)
		local v = def.visual
		stick(pieces, 0.25, 2.6, -1.1, v.stick)
		piece(pieces, newPart("Ball", Vector3.one * 0.95, v.star, Enum.Material.Neon), CFrame.new(0, -2.7, 0))
		for k = 0, 4 do
			local a = k * math.pi * 2 / 5
			piece(pieces, newPart("Block", Vector3.new(0.3, 0.75, 0.3), v.star, Enum.Material.Neon), CFrame.new(0, -2.7, 0) * CFrame.Angles(0, 0, a) * CFrame.new(0, 0.7, 0))
		end
	end,
	plunger = function(def, pieces)
		local v = def.visual
		stick(pieces, 0.35, 3, -1.2, v.stick)
		piece(pieces, newPart("Ellipsoid", Vector3.new(1.9, 1.1, 1.9), v.cup), CFrame.new(0, -3.1, 0))
		stick(pieces, 1.9, 0.18, -3.55, INK)
	end,
	hammer = function(def, pieces)
		local v = def.visual
		stick(pieces, 0.4, 3.2, -1.3, v.handle)
		for i, color in v.colors :: { Color3 } do
			piece(pieces, newPart("Cylinder", Vector3.new(0.85, 1.7, 1.7), color), CFrame.new((i - 2) * 0.85, -3.2, 0))
		end
	end,
}

-- Builds the weapon in grip space (parts unanchored, not yet placed).
function WeaponModels.build(def: WeaponsConfig.WeaponDef): Built
	local model = Instance.new("Model")
	model.Name = "Weapon_" .. def.id
	model:SetAttribute("WeaponId", def.id)
	local pieces: { Piece } = {}
	local builder = BUILDERS[def.visual.kind] or BUILDERS.gloves
	builder(def, pieces)
	for index, p in pieces do
		p.part.Name = def.id .. "_" .. index
		p.part.Parent = model
	end
	return { model = model, pieces = pieces }
end

-- Static layout around `origin` (shop preview, Studio checks): the right-
-- hand pieces at origin, left-hand pieces 2.5 studs to the left.
function WeaponModels.place(built: Built, origin: CFrame)
	for _, p in built.pieces do
		local base = if p.hand == "left" then origin * CFrame.new(-2.5, 0, 0) else origin
		p.part.Anchored = true
		p.part.CFrame = base * p.offset
	end
end

function WeaponModels.kinds(): { string }
	local list = {}
	for kind in BUILDERS do
		table.insert(list, kind)
	end
	table.sort(list)
	return list
end

return WeaponModels
