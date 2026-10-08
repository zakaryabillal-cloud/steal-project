--!strict
-- Procedural strike animation (V2 phase 6.5). No Animation asset id: the
-- arms are posed by offsetting the C0 of the character's own Motor6D joints
-- for a few tenths of a second, on top of whatever the default Animate
-- script plays (it only writes Motor6D.Transform, never C0).
--
--   R15: UpperTorso.Waist, RightUpperArm.RightShoulder, LeftUpperArm.LeftShoulder,
--        RightLowerArm.RightElbow, LeftLowerArm.LeftElbow
--   R6 : Torso["Right Shoulder"], Torso["Left Shoulder"] (no elbows, no waist)
--   Anything else (custom rigs without these joints): no arm motion, the
--   swoosh / impact effects still play (documented limitation).
--
-- Styles (Config/Weapons): punch (jab, jab, uppercut; alternating arms),
-- smash (raise overhead, slam down), shoot (aim + recoil), zap (quick flick),
-- thrust (lunge forward). The finisher (combo step 3) is bigger and slower.
-- C0 changes are local: every client animates everyone it sees swing (the
-- server broadcasts the swings to the other fighters).

local RunService = game:GetService("RunService")

local Punch = {}

type Joint = {
	motor: Motor6D,
	base: CFrame,
	-- Axis used to swing the arm forward, in C0 space, and its sign.
	axis: string,
	sign: number,
}

type Rig = {
	character: Model,
	kind: string, -- "R15" | "R6" | "none"
	joints: { [string]: Joint },
}

type Swing = {
	rig: Rig,
	style: string,
	combo: number,
	finisher: boolean,
	startAt: number,
	duration: number,
}

local rigs: { [Model]: Rig } = {}
local swings: { [Model]: Swing } = {}
local connection: RBXScriptConnection? = nil

local function motor(parent: Instance?, name: string): Motor6D?
	local found = parent and parent:FindFirstChild(name)
	return if found and found:IsA("Motor6D") then found else nil
end

local function joint(m: Motor6D?, axis: string, sign: number): Joint?
	if not m then
		return nil
	end
	local base = m:GetAttribute("PunchBaseC0")
	if typeof(base) ~= "CFrame" then
		base = m.C0
		m:SetAttribute("PunchBaseC0", base)
	end
	return { motor = m, base = base :: CFrame, axis = axis, sign = sign }
end

-- Finds the joints of a character (cached until it is destroyed).
function Punch.rigOf(character: Model): Rig
	local cached = rigs[character]
	if cached and cached.character.Parent then
		return cached
	end
	local joints: { [string]: Joint } = {}
	local kind = "none"
	local rightShoulder = motor(character:FindFirstChild("RightUpperArm"), "RightShoulder")
	if rightShoulder then
		kind = "R15"
		joints.rightShoulder = joint(rightShoulder, "X", 1) :: Joint
		joints.leftShoulder = joint(motor(character:FindFirstChild("LeftUpperArm"), "LeftShoulder"), "X", 1) :: Joint
		joints.rightElbow = joint(motor(character:FindFirstChild("RightLowerArm"), "RightElbow"), "X", 1) :: Joint
		joints.leftElbow = joint(motor(character:FindFirstChild("LeftLowerArm"), "LeftElbow"), "X", 1) :: Joint
		joints.waist = joint(motor(character:FindFirstChild("UpperTorso"), "Waist"), "Y", 1) :: Joint
	else
		local torso = character:FindFirstChild("Torso")
		local r6Right = motor(torso, "Right Shoulder")
		if r6Right then
			kind = "R6"
			-- R6 shoulders swing around their C0 Z axis (left side mirrored).
			joints.rightShoulder = joint(r6Right, "Z", 1) :: Joint
			joints.leftShoulder = joint(motor(torso, "Left Shoulder"), "Z", -1) :: Joint
		end
	end
	local rig: Rig = { character = character, kind = kind, joints = joints }
	rigs[character] = rig
	return rig
end

local function rotation(j: Joint, angle: number): CFrame
	local a = angle * j.sign
	if j.axis == "X" then
		return CFrame.Angles(a, 0, 0)
	elseif j.axis == "Y" then
		return CFrame.Angles(0, a, 0)
	end
	return CFrame.Angles(0, 0, a)
end

local function set(rig: Rig, name: string, angle: number)
	local j = rig.joints[name]
	if j and j.motor.Parent then
		j.motor.C0 = j.base * rotation(j, angle)
	end
end

local function reset(rig: Rig)
	for _, j in rig.joints do
		if j.motor.Parent then
			j.motor.C0 = j.base
		end
	end
end

-- Envelope: 0 -> wind-up (-) -> strike (1) -> back to 0.
local function curve(k: number): (number, number)
	-- Returns (windup 0..1, strike 0..1).
	if k < 0.25 then
		return k / 0.25, 0
	elseif k < 0.55 then
		return 1 - (k - 0.25) / 0.3, (k - 0.25) / 0.3
	end
	return 0, 1 - (k - 0.55) / 0.45
end

local R = math.rad

local function pose(swing: Swing, k: number)
	local rig = swing.rig
	local windup, strike = curve(k)
	local big = if swing.finisher then 1.25 else 1
	local leftHand = swing.style == "punch" and swing.combo == 2
	local arm = if leftHand then "leftShoulder" else "rightShoulder"
	local elbow = if leftHand then "leftElbow" else "rightElbow"
	if swing.style == "punch" then
		if swing.finisher then
			-- Uppercut: low wind-up, arm sweeps up high.
			set(rig, arm, R(-30) * windup + R(150) * strike)
			set(rig, elbow, R(70) * windup + R(20) * strike)
		else
			set(rig, arm, R(-25) * windup + R(95) * strike)
			set(rig, elbow, R(80) * windup)
		end
		set(rig, "waist", (if leftHand then R(-25) else R(25)) * strike * big)
	elseif swing.style == "smash" then
		-- Raise over the head, then slam down in front.
		set(rig, "rightShoulder", R(170) * windup * big + R(60) * strike)
		set(rig, "leftShoulder", R(150) * windup * big + R(50) * strike)
		set(rig, "rightElbow", R(40) * windup)
		set(rig, "waist", R(10) * strike)
	elseif swing.style == "shoot" then
		-- Aim straight, short recoil.
		set(rig, "rightShoulder", R(90) - R(15) * strike * big)
		set(rig, "leftShoulder", R(70))
	elseif swing.style == "zap" then
		set(rig, "rightShoulder", R(60) * windup + R(120) * strike * big)
		set(rig, "rightElbow", R(50) * windup)
	else -- thrust
		set(rig, "rightShoulder", R(40) * windup + R(90) * strike)
		set(rig, "leftShoulder", R(30) * windup + R(80) * strike)
		set(rig, "waist", R(-15) * windup + R(15) * strike * big)
	end
end

local function step()
	local clock = os.clock()
	for character, swing in swings do
		if not character.Parent then
			swings[character] = nil
			continue
		end
		local k = (clock - swing.startAt) / swing.duration
		if k >= 1 then
			reset(swing.rig)
			swings[character] = nil
		else
			pose(swing, math.clamp(k, 0, 1))
		end
	end
	if next(swings) == nil and connection then
		connection:Disconnect()
		connection = nil
	end
end

-- Plays one swing on `character`. Returns the rig kind ("R15" | "R6" | "none").
function Punch.play(character: Model, style: string, combo: number, finisher: boolean, cooldown: number): string
	local rig = Punch.rigOf(character)
	local previous = swings[character]
	if previous then
		reset(previous.rig)
	end
	swings[character] = {
		rig = rig,
		style = style,
		combo = combo,
		finisher = finisher,
		startAt = os.clock(),
		-- Never longer than the weapon cooldown (a held button chains swings).
		duration = math.clamp(cooldown * (if finisher then 1.1 else 0.9), 0.22, 0.6),
	}
	if not connection then
		connection = RunService.RenderStepped:Connect(step)
	end
	return rig.kind
end

-- Tests / debug.
function Punch.active(): number
	local n = 0
	for _ in swings do
		n += 1
	end
	return n
end

function Punch.stepNow()
	step()
end

return Punch
