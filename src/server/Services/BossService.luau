--!strict
-- Boss expeditions (V2 phase 6). Server authority for everything that
-- matters: portal timing, who may enter, arena positions, boss Health,
-- attacks and hits, hearts, KOs, strikes, phases, the end of the fight,
-- rewards (individual, once per fight), the Codex and every cleanup.
--
-- Lifecycle (one expedition at a time per server):
--   Dormant --(timer)--> Open (60 s, join from the Boss Plateau portal; the
--   arena is built; "Ready" from everyone starts early) --> Intro (boss
--   entrance, invulnerable) --> Fight (3 min 30 max) --> Victory | Defeat
--   (show) --> everyone back on the plateau, arena destroyed --> Dormant.
--
-- Clients never send a position or a damage value: "Strike" carries nothing,
-- the server checks the fighter's own character against the boss. Attacks
-- are planned by Server/Bosses/<Id> (generic shapes) and resolved here
-- against the server's view of the fighters; one FX message per attack
-- carries what clients need to draw the telegraph.
--
-- Safety nets: entry refused while carrying relics (nothing can be lost or
-- duplicated), PvP isolation + "Expedition" Sanctuary protection only while
-- participating (Core/Expeditions), out-of-bounds pull-back, teleport
-- exploit removal, intruder ejection, AFK removal, rewards only for eligible
-- participants (minimum contribution), anti-replay fight id in the save,
-- MovementGuard told about every server teleport, and a full cleanup on every
-- exit path (exit, KO, death, disconnect, timeout, victory).

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Bosses = require(Shared.Config.Bosses)
local Materials = require(Shared.Config.Materials)
local WorldFeatures = require(Shared.WorldFeatures)

local Core = script.Parent.Parent.Core
local Types = require(Core.Types)
local Sessions = require(Core.Sessions)
local Remotes = require(Core.Remotes)
local Scheduler = require(Core.Scheduler)
local Expeditions = require(Core.Expeditions)
local DataSchema = require(Core.DataSchema)
local CharacterService = require(script.Parent.CharacterService)
local MovementGuard = require(script.Parent.MovementGuard)
local StatusService = require(script.Parent.StatusService)
local AbilityService = require(script.Parent.AbilityService)
local EconomyService = require(script.Parent.EconomyService)
local CosmeticService = require(script.Parent.CosmeticService)
local TrophyService = require(script.Parent.TrophyService)
local DexService = require(script.Parent.DexService)
local DataService = require(script.Parent.DataService)
local ArenaBuilder = require(script.Parent.Parent.World.ArenaBuilder)
local BossTypes = require(script.Parent.Parent.Bosses.BossTypes)

type Session = Types.Session
type Plan = BossTypes.Plan
type Shape = BossTypes.Shape

local BossService = {}

local PORTAL = Bosses.Portal
local ARENA = Bosses.Arena
local COMBAT = Bosses.Combat
local STRIKE = Bosses.Strike

-- Behaviour modules (Server/Bosses/<module>).
local modules: { [string]: BossTypes.BossModule } = {}
for _, def in Bosses.list do
	local moduleScript = script.Parent.Parent.Bosses:FindFirstChild(def.module)
	assert(moduleScript and moduleScript:IsA("ModuleScript"), "missing boss module " .. def.module)
	modules[def.id] = (require :: any)(moduleScript)
end

export type Participant = {
	session: Session,
	userId: number,
	-- waiting | fighting | ko | dead | left | afk | exploit | gone
	status: string,
	hearts: number,
	invulnerableUntil: number,
	damage: number,
	hits: number,
	hitsTaken: number,
	ready: boolean,
	lastActive: number,
	lastSample: Vector3?,
	sampleAt: number,
	-- Pending exit (KO show) and whether the character is still in the arena.
	leaveAt: number?,
	inArena: boolean,
	pullBacks: number,
	-- Reward outcome (set at the end): "rewarded" | reason it was not.
	outcome: string?,
}

export type Fight = {
	id: string,
	index: number,
	boss: Bosses.BossDef,
	module: BossTypes.BossModule,
	-- Open | Intro | Fight | Victory | Defeat
	state: string,
	arena: ArenaBuilder.Arena,
	anchor: Part,
	participants: { Participant },
	bySession: { [Session]: Participant },
	openedAt: number,
	closesAt: number,
	startedAt: number,
	endsAt: number,
	startCount: number,
	maxHp: number,
	hp: number,
	phase: number,
	bossInvulnerableUntil: number,
	dizzyFrom: number,
	dizzyUntil: number,
	plan: Plan?,
	shapes: { Shape },
	motion: BossTypes.Motion?,
	nextAttackAt: number,
	attacksInPhase: number,
	specialDue: boolean,
	lastAttack: string?,
	lastFacing: number,
	intruderCheck: number,
	rng: Random,
	result: string?,
	reason: string?,
	duration: number,
	outroUntil: number,
}

local fight: Fight? = nil
local openings = 0
local nextOpenAt = 0
local announced = false
local plateau: Model? = nil
local portalPart: BasePart? = nil

-- Random source for rewards (tests replace it to force drops).
local randomFactory: () -> Random = function()
	return Random.new()
end

local function now(): number
	return workspace:GetServerTimeNow()
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

----------------------------------------------------------------------------
-- Portal & published state
----------------------------------------------------------------------------

local function portalPosition(): Vector3
	local spec = WorldFeatures.BossPlateau
	return WorldFeatures.polar(spec.deg, spec.portalR, spec.top)
end
BossService.portalPosition = portalPosition

-- Where fighters come back: the plateau plaza (in front of the portal),
-- side by side within a few studs, facing the Rift.
local function returnCFrame(k: number): CFrame
	local spec = WorldFeatures.BossPlateau
	local center = WorldFeatures.polar(spec.deg, spec.center, spec.top + 3)
	local outward = Vector3.new(center.X, 0, center.Z).Unit
	local side = Vector3.new(-outward.Z, 0, outward.X)
	local p = center + side * (((k - 1) % 8) - 3.5) * 2.5
	return CFrame.lookAt(p, Vector3.new(0, p.Y, 0))
end
BossService.returnCFrame = returnCFrame

local function activeCount(f: Fight, waitingToo: boolean?): number
	local n = 0
	for _, p in f.participants do
		if p.status == "fighting" or (waitingToo and p.status == "waiting") then
			n += 1
		end
	end
	return n
end

local function readyCount(f: Fight): number
	local n = 0
	for _, p in f.participants do
		if p.status == "waiting" and p.ready then
			n += 1
		end
	end
	return n
end

local function publishPortal()
	local model = plateau
	if not model then
		return
	end
	local f = fight
	local state = "Dormant"
	if f then
		state = if f.state == "Open" then "Open" else "Fight"
	end
	model:SetAttribute("PortalState", state)
	model:SetAttribute("PortalBoss", if f then f.boss.id else Bosses.forOpening(openings + 1).id)
	model:SetAttribute("PortalOpensAt", nextOpenAt)
	model:SetAttribute("PortalClosesAt", if f and f.state == "Open" then f.closesAt else 0)
	model:SetAttribute("PortalCount", if f then activeCount(f, true) else 0)
end

local function publishArena(f: Fight)
	local model = f.arena.model
	model:SetAttribute("FightId", f.id)
	model:SetAttribute("BossId", f.boss.id)
	model:SetAttribute("State", f.state)
	model:SetAttribute("HP", math.max(0, math.ceil(f.hp)))
	model:SetAttribute("MaxHP", f.maxHp)
	model:SetAttribute("Phase", f.phase)
	model:SetAttribute("ClosesAt", f.closesAt)
	model:SetAttribute("StartsAt", f.startedAt)
	model:SetAttribute("EndsAt", f.endsAt)
	model:SetAttribute("Participants", activeCount(f, true))
	model:SetAttribute("Ready", readyCount(f))
	model:SetAttribute("DizzyUntil", f.dizzyUntil)
	model:SetAttribute("InvulnerableUntil", f.bossInvulnerableUntil)
	publishPortal()
end

local function setAction(f: Fight, action: string, mood: string?)
	f.anchor:SetAttribute("Action", action)
	f.anchor:SetAttribute("ActionAt", now())
	if mood then
		f.anchor:SetAttribute("Mood", mood)
	end
end

-- FX to everyone still in the arena (or every participant still in the server).
local function sendFight(f: Fight, kind: string, payload: { [string]: any }, everyone: boolean?)
	payload.fight = f.id
	for _, p in f.participants do
		if not p.session.released and p.session.player.Parent ~= nil and (everyone or p.inArena) then
			Remotes.fxTo(p.session.player, kind, payload)
		end
	end
end

----------------------------------------------------------------------------
-- Players in and out
----------------------------------------------------------------------------

local function clearAttributes(session: Session)
	local player = session.player
	player:SetAttribute("BossFight", nil)
	player:SetAttribute("BossHearts", nil)
	player:SetAttribute("MusicBoss", nil)
	player:SetAttribute("MusicBossPhase", nil)
end

-- Server-made move: the movement guard is told, never fooled.
local function moveCharacter(session: Session, cf: CFrame)
	local character = session.player.Character
	local _, _, root = Sessions.character(session)
	if not character or not root then
		return
	end
	session.teleportGraceUntil = now() + 2
	character:PivotTo(cf)
	MovementGuard.teleported(session, cf.Position)
	session.lastPosition = cf.Position
end

local function teleportOut(f: Fight, p: Participant)
	Expeditions.leave(p.session)
	StatusService.clearSlow(p.session, "goo")
	clearAttributes(p.session)
	if p.inArena then
		p.inArena = false
		local _, _, root = Sessions.character(p.session)
		if root and ArenaBuilder.inside(root.Position, 40) then
			moveCharacter(p.session, returnCFrame(table.find(f.participants, p) or 1))
		end
	end
end

local function codex(session: Session, bossId: string): Types.BossRecord
	local record = session.data.bosses[bossId]
	if not record then
		record = DataSchema.newBossRecord()
		session.data.bosses[bossId] = record
	end
	return record
end
BossService.codex = codex

local function setMusic(f: Fight, p: Participant)
	local player = p.session.player
	player:SetAttribute("MusicBoss", f.boss.id)
	player:SetAttribute("MusicBossPhase", f.phase)
end

-- Returns (ok, reason?). reason: invalid | closed | fighting | already |
-- power | carrying | noCharacter | far | full
function BossService.join(player: Player): (boolean, string?)
	local session = Sessions.ready(player)
	if not session then
		return false, "invalid"
	end
	local f = fight
	if not f then
		return false, "closed"
	end
	if f.state ~= "Open" then
		return false, "fighting"
	end
	local existing = f.bySession[session]
	if existing and existing.status == "waiting" then
		return false, "already"
	end
	if not Bosses.canEnter(f.boss, session.data.power.peak) then
		return false, "power"
	end
	-- Safest rule: relics in hand never enter (nothing lost, nothing duplicated).
	if #session.carrying > 0 then
		return false, "carrying"
	end
	local _, _, root = Sessions.character(session)
	if not root then
		return false, "noCharacter"
	end
	if flat(root.Position - portalPosition()).Magnitude > PORTAL.JoinRadius then
		return false, "far"
	end
	if activeCount(f, true) >= 12 then
		return false, "full"
	end
	local t = now()
	local p: Participant = existing
		or {
			session = session,
			userId = session.userId,
			status = "waiting",
			hearts = COMBAT.Hearts,
			invulnerableUntil = 0,
			damage = 0,
			hits = 0,
			hitsTaken = 0,
			ready = false,
			lastActive = t,
			lastSample = nil,
			sampleAt = 0,
			leaveAt = nil,
			inArena = false,
			pullBacks = 0,
			outcome = nil,
		}
	p.status = "waiting"
	p.ready = false
	p.hearts = COMBAT.Hearts
	p.lastActive = t
	if not existing then
		table.insert(f.participants, p)
		f.bySession[session] = p
	end
	Expeditions.join(session, f.id)
	-- Nothing of theirs stays active on the island (traps, decoys, flights).
	AbilityService.cleanup(session, "expedition")
	session.stealHold = nil
	p.inArena = true
	moveCharacter(session, f.arena.spawns[((#f.participants - 1) % #f.arena.spawns) + 1])
	player:SetAttribute("BossFight", f.id)
	player:SetAttribute("BossHearts", p.hearts)
	local record = codex(session, f.boss.id)
	if not record.discovered then
		record.discovered = true
	end
	Sessions.markCold(session)
	Sessions.touch(session)
	publishArena(f)
	Remotes.fxTo(player, "BossJoined", { fight = f.id, boss = f.boss.id, closesAt = f.closesAt })
	return true, nil
end

-- "Ready" in the waiting room: when everyone is ready, start soon.
function BossService.ready(player: Player): boolean
	local session = Sessions.ready(player)
	local f = fight
	if not session or not f or f.state ~= "Open" then
		return false
	end
	local p = f.bySession[session]
	if not p or p.status ~= "waiting" then
		return false
	end
	p.ready = true
	if readyCount(f) == activeCount(f, true) then
		f.closesAt = math.min(f.closesAt, now() + PORTAL.ReadyCountdown)
	end
	publishArena(f)
	return true
end

-- Voluntary exit. During the fight it is an abandon (no reward).
function BossService.leave(player: Player): boolean
	local session = Sessions.get(player)
	local f = fight
	if not session or not f then
		return false
	end
	local p = f.bySession[session]
	if not p or not p.inArena then
		return false
	end
	if f.state == "Open" then
		p.status = "left"
	elseif p.status == "fighting" then
		p.status = "left"
		Remotes.notify(player, "n.bossAbandon", nil, "warning")
	end
	teleportOut(f, p)
	publishArena(f)
	return true
end

----------------------------------------------------------------------------
-- Opening, start and end
----------------------------------------------------------------------------

local function newAnchor(f: Fight)
	local def = f.boss
	local anchor = Instance.new("Part")
	anchor.Name = "Boss"
	anchor.Size = Vector3.one * def.radius * 2
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Locked = true
	local c = f.arena.center
	local p = Vector3.new(c.X, f.arena.floorY + def.height, c.Z + 18)
	anchor.CFrame = CFrame.lookAt(p, Vector3.new(c.X, p.Y, c.Z - 40))
	anchor:SetAttribute("BossId", def.id)
	anchor.Parent = f.arena.model
	f.anchor = anchor
end

function BossService.open(): Fight?
	if fight then
		return nil
	end
	local t = now()
	openings += 1
	local def = Bosses.forOpening(openings)
	local arena = ArenaBuilder.build(workspace, def.id)
	local f: Fight = {
		id = HttpService:GenerateGUID(false),
		index = openings,
		boss = def,
		module = modules[def.id],
		state = "Open",
		arena = arena,
		anchor = nil :: any,
		participants = {},
		bySession = {},
		openedAt = t,
		closesAt = t + PORTAL.OpenDuration,
		startedAt = 0,
		endsAt = 0,
		startCount = 0,
		maxHp = Bosses.maxHealth(def, 1),
		hp = Bosses.maxHealth(def, 1),
		phase = 1,
		bossInvulnerableUntil = math.huge,
		dizzyFrom = 0,
		dizzyUntil = 0,
		plan = nil,
		shapes = {},
		motion = nil,
		nextAttackAt = math.huge,
		attacksInPhase = 0,
		specialDue = false,
		lastAttack = nil,
		lastFacing = 0,
		intruderCheck = 0,
		rng = Random.new(),
		result = nil,
		reason = nil,
		duration = 0,
		outroUntil = 0,
	}
	newAnchor(f)
	fight = f
	nextOpenAt = t + PORTAL.Interval
	announced = false
	setAction(f, "Sleep", "sleepy")
	publishArena(f)
	Remotes.notifyAll("n.bossOpen", { boss = def.id }, "rare")
	Remotes.fx("BossPortal", { state = "Open", boss = def.id, closesAt = f.closesAt })
	return f
end

local function destroyArena(f: Fight)
	for _, p in f.participants do
		if p.inArena or Expeditions.of(p.session) == f.id then
			teleportOut(f, p)
		end
	end
	f.arena.model:Destroy()
	if fight == f then
		fight = nil
	end
	publishPortal()
	Remotes.fx("BossPortal", { state = "Dormant", opensAt = nextOpenAt })
end

local function startFight(f: Fight, t: number)
	local fighters: { Participant } = {}
	for _, p in f.participants do
		if p.status == "waiting" and p.inArena then
			table.insert(fighters, p)
		end
	end
	if #fighters == 0 then
		destroyArena(f)
		return
	end
	local def = f.boss
	f.state = "Intro"
	f.startCount = #fighters
	f.maxHp = Bosses.maxHealth(def, #fighters)
	f.hp = f.maxHp
	f.phase = 1
	f.startedAt = t + COMBAT.Intro
	f.endsAt = f.startedAt + COMBAT.Duration
	f.bossInvulnerableUntil = f.startedAt
	f.nextAttackAt = f.startedAt + 1
	f.attacksInPhase = 0
	f.specialDue = def.phases[1].special ~= nil
	for _, p in fighters do
		p.status = "fighting"
		p.hearts = COMBAT.Hearts
		p.invulnerableUntil = f.startedAt
		p.lastActive = f.startedAt
		p.session.player:SetAttribute("BossHearts", p.hearts)
		setMusic(f, p)
		local record = codex(p.session, def.id)
		record.discovered = true
		record.attempts += 1
		Sessions.markCold(p.session)
	end
	-- Anyone who left during the opening is forgotten.
	for i = #f.participants, 1, -1 do
		local p = f.participants[i]
		if p.status ~= "fighting" then
			table.remove(f.participants, i)
			f.bySession[p.session] = nil
		end
	end
	setAction(f, "Intro", def.phases[1].mood)
	publishArena(f)
	sendFight(f, "BossStart", { boss = def.id, startsAt = f.startedAt, endsAt = f.endsAt, maxHp = f.maxHp, count = #fighters })
end

-- Grants one loot entry. Returns the reward line shown on the results card.
local function grantEntry(session: Session, entry: Bosses.LootEntry, rng: Random): { [string]: any }
	local line: { [string]: any } = { id = entry.id, kind = entry.kind, ref = entry.ref, rare = entry.rare == true }
	local function addMaterial(materialId: string, amount: number)
		local def = Materials.get(materialId)
		if not def then
			return
		end
		local materials = session.data.materials
		materials[materialId] = math.min(def.max, (materials[materialId] or 0) + amount)
	end
	if entry.kind == "essence" then
		local amount = Bosses.essenceReward(entry, session.rate)
		EconomyService.addEssence(session, amount)
		line.amount = amount
	elseif entry.kind == "material" then
		local amount = rng:NextInteger(entry.min or 1, entry.max or 1)
		addMaterial(entry.ref :: string, amount)
		line.amount = amount
	elseif entry.kind == "relic" then
		local result = TrophyService.award(session, entry.ref :: string)
		line.result = result
		if result == "placed" or result == "levelUp" then
			DexService.register(session, entry.ref :: string, nil)
		elseif entry.fallback then
			addMaterial(entry.fallback.material, entry.fallback.amount)
			line.fallback = entry.fallback.material
			line.amount = entry.fallback.amount
		end
	elseif entry.kind == "cosmetic" then
		local ok = CosmeticService.grant(session, entry.ref, "boss")
		line.result = if ok then "unlocked" else "owned"
		if not ok and entry.fallback then
			addMaterial(entry.fallback.material, entry.fallback.amount)
			line.fallback = entry.fallback.material
			line.amount = entry.fallback.amount
		end
	end
	return line
end

-- Rewards for one participant (individual rolls). Returns (lines?, outcome).
local function reward(f: Fight, p: Participant): ({ { [string]: any } }?, string)
	local session = p.session
	if session.released or Sessions.get(session.player) ~= session then
		return nil, "gone"
	end
	if p.status ~= "fighting" and p.status ~= "ko" and p.status ~= "dead" then
		return nil, p.status
	end
	if p.damage < Bosses.eligibleDamage(f.maxHp, f.startCount) then
		return nil, "contribution"
	end
	local def = f.boss
	local record = codex(session, def.id)
	if record.lastFight == f.id then
		return nil, "already"
	end
	record.lastFight = f.id
	record.wins += 1
	if record.bestTime <= 0 or f.duration < record.bestTime then
		record.bestTime = math.floor(f.duration * 10 + 0.5) / 10
	end
	local rng = randomFactory()
	local lines = {}
	for _, entry in def.loot do
		if rng:NextNumber() < entry.chance then
			table.insert(lines, grantEntry(session, entry, rng))
			if entry.rare then
				record.rare[entry.id] = (record.rare[entry.id] or 0) + 1
			end
		end
	end
	Sessions.markCold(session)
	EconomyService.recompute(session)
	-- Persist right away: a crash or disconnect right after cannot lose it,
	-- and the fight id stored above makes a replay impossible.
	if session.canSave then
		task.spawn(DataService.save, session, false)
	end
	return lines, "rewarded"
end

local function endFight(f: Fight, t: number, result: string, reason: string)
	if f.state ~= "Intro" and f.state ~= "Fight" then
		return
	end
	f.state = result
	f.result = result
	f.reason = reason
	f.plan = nil
	f.motion = nil
	table.clear(f.shapes)
	f.duration = math.clamp(t - f.startedAt, 0, COMBAT.Duration)
	f.outroUntil = t + COMBAT.Outro
	f.bossInvulnerableUntil = math.huge
	if result == "Victory" then
		setAction(f, "Defeated", "dizzy")
	else
		setAction(f, "Gloat", "smug")
	end
	publishArena(f)
	for _, p in f.participants do
		StatusService.clearSlow(p.session, "goo")
		local lines: { { [string]: any } }? = nil
		local outcome = if result == "Victory" then "pending" else reason
		if result == "Victory" then
			lines, outcome = reward(f, p)
		end
		p.outcome = outcome
		if not p.session.released and p.session.player.Parent ~= nil then
			p.session.player:SetAttribute("MusicBoss", nil)
			p.session.player:SetAttribute("MusicBossPhase", nil)
			Remotes.fxTo(p.session.player, "BossEnd", {
				fight = f.id,
				boss = f.boss.id,
				result = result,
				reason = reason,
				time = f.duration,
				outcome = outcome,
				rewards = lines or {},
				damage = math.floor(p.damage),
				hits = p.hits,
				needed = math.ceil(Bosses.eligibleDamage(f.maxHp, f.startCount)),
			})
		end
	end
	if result == "Victory" then
		Remotes.notifyAll("n.bossDefeated", { boss = f.boss.id }, "rare")
	end
end

----------------------------------------------------------------------------
-- Combat
----------------------------------------------------------------------------

local function ko(f: Fight, p: Participant, t: number)
	p.status = "ko"
	p.leaveAt = t + 1.4
	-- Protection ends with the KO (the character leaves right after the show).
	Expeditions.leave(p.session)
	sendFight(f, "BossKO", { userId = p.userId })
end

local function hit(f: Fight, p: Participant, from: Vector3, t: number)
	if p.status ~= "fighting" or t < p.invulnerableUntil then
		return
	end
	local _, _, root = Sessions.character(p.session)
	if not root then
		return
	end
	p.hearts -= 1
	p.hitsTaken += 1
	p.invulnerableUntil = t + COMBAT.HitInvulnerability
	p.session.player:SetAttribute("BossHearts", math.max(0, p.hearts))
	local away = flat(root.Position - from)
	away = if away.Magnitude > 0.1 then away.Unit else Vector3.new(0, 0, -1)
	MovementGuard.allow(p.session, COMBAT.Knockback * 1.6, 1)
	Remotes.knockback(p.session.player, away * COMBAT.Knockback + Vector3.new(0, 26, 0), COMBAT.KnockStun)
	sendFight(f, "BossHit", { userId = p.userId, hearts = math.max(0, p.hearts), position = root.Position })
	if p.hearts <= 0 then
		ko(f, p, t)
	end
end

local function grounded(f: Fight, root: BasePart): boolean
	return root.Position.Y - f.arena.floorY < COMBAT.RootHeight + COMBAT.JumpClear
end

local function fighters(f: Fight): { { p: Participant, root: BasePart } }
	local list = {}
	for _, p in f.participants do
		if p.status == "fighting" then
			local _, _, root = Sessions.character(p.session)
			if root then
				table.insert(list, { p = p, root = root })
			end
		end
	end
	return list
end

local function resolveShapes(f: Fight, t: number)
	local list = fighters(f)
	for i = #f.shapes, 1, -1 do
		local shape = f.shapes[i]
		local remove = false
		if shape.kind == "ring" then
			local speed = shape.speed or 30
			local band = shape.band or 3
			local front = (t - shape.at) * speed
			if front >= 0 then
				local resolved = shape.resolved :: { [any]: boolean }
				for _, entry in list do
					if not resolved[entry.p] then
						local d = flat(entry.root.Position - shape.center).Magnitude
						if d > shape.radius then
							resolved[entry.p] = true
						elseif front >= d - band / 2 then
							resolved[entry.p] = true
							if front <= d + band / 2 + speed * 0.15 and grounded(f, entry.root) then
								hit(f, entry.p, shape.center, t)
							end
						end
					end
				end
				remove = front > shape.radius + band
			end
		elseif shape.kind == "circle" then
			if t >= shape.at then
				for _, entry in list do
					local offset = entry.root.Position - shape.center
					if flat(offset).Magnitude <= shape.radius + 1 and offset.Y < COMBAT.RootHeight + 6 then
						hit(f, entry.p, shape.center, t)
					end
				end
				remove = true
			end
		elseif shape.kind == "sector" then
			if t >= shape.at then
				local half = (shape.safeWidth or math.pi / 2) / 2
				for _, entry in list do
					local offset = flat(entry.root.Position - shape.center)
					local angle = math.atan2(offset.Z, offset.X)
					local diff = math.abs(((angle - (shape.safeAngle or 0) + math.pi) % (math.pi * 2)) - math.pi)
					if diff > half and offset.Magnitude <= shape.radius then
						hit(f, entry.p, shape.center, t)
					end
				end
				remove = true
			end
		elseif shape.kind == "zone" then
			if t >= (shape.untilTime or 0) then
				remove = true
			elseif t >= shape.at then
				for _, entry in list do
					local offset = entry.root.Position - shape.center
					if flat(offset).Magnitude <= shape.radius and grounded(f, entry.root) then
						StatusService.applySelfSlow(entry.p.session, "goo", shape.slow or 0.4, 0.4)
					end
				end
			end
		else
			remove = true
		end
		if remove then
			table.remove(f.shapes, i)
		end
	end
end

local function bossAirborne(f: Fight, t: number): boolean
	local motion = f.motion
	return motion ~= nil and t >= motion.startAt and t < motion.endAt
end

local function updateMotion(f: Fight, t: number)
	local motion = f.motion
	local anchor = f.anchor
	if motion then
		if t < motion.startAt then
			return
		end
		local span = math.max(0.05, motion.endAt - motion.startAt)
		local k = math.clamp((t - motion.startAt) / span, 0, 1)
		local p = motion.from:Lerp(motion.to, k) + Vector3.new(0, motion.height * 4 * k * (1 - k), 0)
		anchor.CFrame = CFrame.new(p) * anchor.CFrame.Rotation
		if k >= 1 then
			f.motion = nil
		end
		return
	end
	-- Face the nearest fighter (a few times per second is plenty).
	if t - f.lastFacing < 0.25 then
		return
	end
	f.lastFacing = t
	local best: Vector3? = nil
	local bestDistance = math.huge
	for _, entry in fighters(f) do
		local d = (entry.root.Position - anchor.Position).Magnitude
		if d < bestDistance then
			best, bestDistance = entry.root.Position, d
		end
	end
	if best then
		local p = anchor.Position
		local look = Vector3.new(best.X, p.Y, best.Z)
		if (look - p).Magnitude > 0.5 then
			anchor.CFrame = CFrame.lookAt(p, look)
		end
	end
end

local function chooseAttack(f: Fight): string
	local phaseDef = f.boss.phases[f.phase]
	local special = phaseDef.special
	if special and (f.specialDue or (phaseDef.specialEvery and f.attacksInPhase > 0 and f.attacksInPhase % phaseDef.specialEvery == 0)) then
		f.specialDue = false
		return special
	end
	local pool = {}
	for _, attackId in phaseDef.attacks do
		if attackId ~= f.lastAttack then
			table.insert(pool, attackId)
		end
	end
	if #pool == 0 then
		pool = table.clone(phaseDef.attacks)
	end
	return pool[f.rng:NextInteger(1, #pool)]
end

local function planNext(f: Fight, t: number)
	local targets = {}
	for _, entry in fighters(f) do
		table.insert(targets, Vector3.new(entry.root.Position.X, f.arena.floorY, entry.root.Position.Z))
	end
	local view: BossTypes.FightView = {
		boss = f.boss,
		phase = f.phase,
		participants = f.startCount,
		center = f.arena.center,
		floorY = f.arena.floorY,
		radius = ARENA.Radius,
		bossPosition = f.anchor.Position,
		targets = targets,
		rng = f.rng,
	}
	local attackId = chooseAttack(f)
	local plan = f.module.plan(view, attackId, t)
	f.plan = plan
	f.lastAttack = plan.id
	f.attacksInPhase += 1
	for _, shape in plan.shapes do
		shape.resolved = {}
		shape.done = false
		table.insert(f.shapes, shape)
	end
	f.motion = plan.motion
	if plan.dizzyAt and plan.dizzyFor then
		f.dizzyFrom = plan.dizzyAt
		f.dizzyUntil = plan.dizzyAt + plan.dizzyFor
	end
	f.anchor:SetAttribute("Attack", plan.id)
	setAction(f, plan.action, nil)
	publishArena(f)
	sendFight(f, "BossAttack", {
		attack = plan.id,
		action = plan.action,
		telegraphAt = plan.telegraphAt,
		hitAt = plan.hitAt,
		endsAt = plan.endsAt,
		phase = f.phase,
		data = plan.payload,
	})
end

local function enterPhase(f: Fight, phase: number, t: number)
	f.phase = phase
	f.attacksInPhase = 0
	local phaseDef = f.boss.phases[phase]
	f.specialDue = phaseDef.special ~= nil
	f.bossInvulnerableUntil = t + COMBAT.PhaseShow
	f.nextAttackAt = math.max(f.nextAttackAt, t + COMBAT.PhaseShow)
	setAction(f, "PhaseChange", phaseDef.mood)
	for _, p in f.participants do
		if p.status == "fighting" then
			p.session.player:SetAttribute("MusicBossPhase", phase)
		end
	end
	publishArena(f)
	sendFight(f, "BossPhase", { phase = phase, mood = phaseDef.mood })
end

-- Returns (ok, reason?). reason: invalid | arena | notYet | cooldown |
-- noCharacter | shield | air | range
function BossService.strike(player: Player): (boolean, string?)
	local session = Sessions.ready(player)
	if not session then
		return false, "invalid"
	end
	local f = fight
	local p = if f then f.bySession[session] else nil
	if not f or not p or p.status ~= "fighting" then
		-- Strike only exists inside the arena.
		return false, "arena"
	end
	local t = now()
	if f.state ~= "Fight" then
		return false, "notYet"
	end
	if not Sessions.cooldownReady(session, "bossStrike") then
		return false, "cooldown"
	end
	local _, _, root = Sessions.character(session)
	if not root then
		return false, "noCharacter"
	end
	if t < f.bossInvulnerableUntil then
		return false, "shield"
	end
	if bossAirborne(f, t) then
		return false, "air"
	end
	local def = f.boss
	local offset = root.Position - f.anchor.Position
	if flat(offset).Magnitude > def.radius + STRIKE.Reach or math.abs(offset.Y) > STRIKE.Height then
		return false, "range"
	end
	Sessions.setCooldown(session, "bossStrike", STRIKE.Cooldown * 0.9)
	Sessions.touch(session)
	local dizzy = t >= f.dizzyFrom and t < f.dizzyUntil
	local damage = Bosses.strikeDamage(session.power, dizzy)
	p.damage += damage
	p.hits += 1
	p.lastActive = t
	f.hp = math.max(0, f.hp - damage)
	publishArena(f)
	Remotes.fxTo(player, "BossStruck", { fight = f.id, amount = damage, dizzy = dizzy, hp = f.hp })
	if f.hp <= 0 then
		endFight(f, t, "Victory", "defeated")
		return true, nil
	end
	local phase = Bosses.phaseAt(def, f.hp / f.maxHp)
	if phase > f.phase then
		enterPhase(f, phase, t)
	end
	return true, nil
end

----------------------------------------------------------------------------
-- Ticks
----------------------------------------------------------------------------

local function stepParticipants(f: Fight, t: number)
	local fightOn = f.state == "Intro" or f.state == "Fight"
	for _, p in f.participants do
		local session = p.session
		if session.released or session.player.Parent == nil then
			if p.status == "waiting" or p.status == "fighting" then
				p.status = "gone"
			end
			p.inArena = false
			Expeditions.leave(session)
			continue
		end
		if p.leaveAt and t >= p.leaveAt then
			p.leaveAt = nil
			teleportOut(f, p)
		end
		if p.status ~= "waiting" and p.status ~= "fighting" then
			continue
		end
		local _, _, root = Sessions.character(session)
		if not root then
			continue
		end
		local position = root.Position
		if not ArenaBuilder.inside(position) then
			if (position - f.arena.center).Magnitude > ARENA.ExploitDistance then
				-- Nobody walks 200+ studs out of a walled arena: teleport exploit.
				warn(string.format("[BossService] %s left the arena by teleport; removed from the expedition", session.player.Name))
				p.status = "exploit"
				p.inArena = false
				Expeditions.leave(session)
				clearAttributes(session)
				continue
			end
			p.pullBacks += 1
			moveCharacter(session, f.arena.spawns[1])
			continue
		end
		if fightOn and p.status == "fighting" then
			if t - p.sampleAt >= 0.5 then
				p.sampleAt = t
				local last = p.lastSample
				if last and flat(position - last).Magnitude > 1.5 then
					p.lastActive = math.max(p.lastActive, t)
				end
				p.lastSample = position
			end
			if f.state == "Fight" and t - p.lastActive > COMBAT.AfkSeconds then
				p.status = "afk"
				Remotes.notify(session.player, "n.bossAfk", nil, "warning")
				teleportOut(f, p)
			end
		end
	end
	-- Intruders (exploit teleports into the arena): sent back to the plateau.
	if t - f.intruderCheck >= 0.5 then
		f.intruderCheck = t
		for _, session in Sessions.all() do
			local p = f.bySession[session]
			if p and p.inArena then
				continue
			end
			local _, _, root = Sessions.character(session)
			if root and ArenaBuilder.inside(root.Position, 30) then
				warn(string.format("[BossService] %s is in the arena without being a participant; ejected", session.player.Name))
				moveCharacter(session, returnCFrame(1))
			end
		end
	end
end

local function step(t: number)
	local f = fight
	if not f then
		if not announced and t >= nextOpenAt - PORTAL.AnnounceBefore then
			announced = true
			Remotes.notifyAll("n.bossSoon", { boss = Bosses.forOpening(openings + 1).id }, "info")
		end
		if t >= nextOpenAt then
			BossService.open()
		end
		return
	end
	stepParticipants(f, t)
	if f.state == "Open" then
		if t >= f.closesAt then
			startFight(f, t)
		end
		return
	end
	if f.state == "Intro" or f.state == "Fight" then
		if f.state == "Intro" and t >= f.startedAt then
			f.state = "Fight"
			setAction(f, "Idle", nil)
			publishArena(f)
		end
		if f.state == "Fight" then
			updateMotion(f, t)
			resolveShapes(f, t)
			if f.dizzyUntil > 0 and t >= f.dizzyFrom and t < f.dizzyUntil and f.anchor:GetAttribute("Action") ~= "Dizzy" then
				setAction(f, "Dizzy", nil)
			end
			local plan = f.plan
			if plan and t >= plan.endsAt then
				f.plan = nil
				f.nextAttackAt = math.max(f.nextAttackAt, plan.endsAt + f.boss.phases[f.phase].gap)
				setAction(f, "Idle", nil)
			end
			if f.plan == nil and t >= f.nextAttackAt and t >= f.bossInvulnerableUntil then
				planNext(f, t)
			end
		end
		if activeCount(f) == 0 then
			local anyKo = false
			for _, p in f.participants do
				if p.status == "ko" or p.status == "dead" then
					anyKo = true
				end
			end
			endFight(f, t, "Defeat", if anyKo then "wiped" else "abandoned")
		elseif t >= f.endsAt then
			endFight(f, t, "Defeat", "timeout")
		end
		return
	end
	-- Victory / Defeat show, then everyone goes back.
	if t >= f.outroUntil then
		destroyArena(f)
	end
end

----------------------------------------------------------------------------
-- Player lifecycle hooks
----------------------------------------------------------------------------

-- Disconnect: nothing is granted to someone who is gone; the fight goes on.
function BossService.onLeave(session: Session)
	local f = fight
	local p = if f then f.bySession[session] else nil
	Expeditions.leave(session)
	if not f or not p then
		return
	end
	if p.status == "waiting" or p.status == "fighting" then
		p.status = "gone"
	end
	p.inArena = false
	p.leaveAt = nil
	publishArena(f)
end

local function onDied(session: Session)
	local f = fight
	local p = if f then f.bySession[session] else nil
	if not f or not p then
		return
	end
	if p.status == "waiting" then
		p.status = "left"
	elseif p.status == "fighting" then
		-- A death counts like a KO (they respawn at home).
		p.status = "dead"
	end
	p.inArena = false
	p.leaveAt = nil
	Expeditions.leave(session)
	clearAttributes(session)
	publishArena(f)
end

----------------------------------------------------------------------------
-- Studio / tests
----------------------------------------------------------------------------

function BossService.state(): Fight?
	return fight
end

function BossService.nextOpenAt(): number
	return nextOpenAt
end

function BossService.setRandom(factory: (() -> Random)?)
	randomFactory = factory or function()
		return Random.new()
	end
end

-- Studio: open now / start now / set Health.
function BossService.devStart()
	local f = fight
	if f and f.state == "Open" then
		f.closesAt = now()
	end
end

function BossService.devSetHealth(fraction: number)
	local f = fight
	if f and f.state == "Fight" then
		f.hp = math.clamp(fraction, 0.001, 1) * f.maxHp
		local phase = Bosses.phaseAt(f.boss, f.hp / f.maxHp)
		if phase > f.phase then
			enterPhase(f, phase, now())
		end
		publishArena(f)
	end
end

-- Studio / tests: ends any expedition now (everyone back on the plateau).
function BossService.devReset()
	local f = fight
	if f then
		destroyArena(f)
	end
end

-- Studio / tests: when the portal opens next.
function BossService.setNextOpen(at: number)
	nextOpenAt = at
	announced = false
	publishPortal()
end

function BossService.participant(player: Player): Participant?
	local f = fight
	local session = Sessions.get(player)
	if not f or not session then
		return nil
	end
	return f.bySession[session]
end

-- Tests: tries to pay a participant of the current fight again (must refuse).
function BossService.debugReward(player: Player): ({ { [string]: any } }?, string)
	local f = fight
	local p = BossService.participant(player)
	if not f or not p then
		return nil, "none"
	end
	return reward(f, p)
end

function BossService.step(t: number?)
	step(t or now())
end

function BossService.start()
	local landmarks = workspace:FindFirstChild("World") and (workspace :: any).World:FindFirstChild("Landmarks")
	plateau = if landmarks then landmarks:FindFirstChild("BossPlateau") :: Model? else nil
	nextOpenAt = now() + PORTAL.FirstOpenDelay
	if plateau then
		-- Portal prompt: opens the boss card (the card's button joins).
		local part = Instance.new("Part")
		part.Name = "PortalPrompt"
		part.Size = Vector3.new(6, 6, 6)
		part.Transparency = 1
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.CFrame = CFrame.new(portalPosition() + Vector3.new(0, 4, 0))
		part.Parent = plateau
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "Boss"
		prompt.ActionText = "Boss"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 22
		prompt.RequiresLineOfSight = false
		prompt.Style = Enum.ProximityPromptStyle.Custom
		prompt:SetAttribute("Action", "Boss")
		prompt.Parent = part
		prompt.Triggered:Connect(function(player: Player)
			if Sessions.ready(player) then
				Remotes.fxTo(player, "BossMenu", {})
			end
		end)
		portalPart = part
	end
	publishPortal()

	Remotes.onInvoke(Net.Functions.BossJoin, { rate = 1, burst = 3 }, BossService.join)
	Remotes.on(Net.Events.BossStrike, { rate = 5, burst = 6 }, function(player: Player)
		local ok, reason = BossService.strike(player)
		if not ok and reason and reason ~= "cooldown" and reason ~= "invalid" then
			local session = Sessions.get(player)
			if session and Sessions.allowNotice(session, "bossStrike:" .. reason, 0.4) then
				Remotes.fxTo(player, "BossStrikeDenied", { reason = reason })
			end
		end
	end)
	Remotes.on(Net.Events.BossLeave, { rate = 1, burst = 2 }, function(player: Player)
		BossService.leave(player)
	end)
	Remotes.on(Net.Events.BossReady, { rate = 1, burst = 2 }, function(player: Player)
		BossService.ready(player)
	end)
	CharacterService.died:Connect(onDied)
	EconomyService.peakRaised:Connect(function(session: Session)
		TrophyService.onPeakRaised(session)
	end)
	Scheduler.every("Boss.tick", 0.05, function()
		step(now())
	end)
end

BossService.portalPart = function(): BasePart?
	return portalPart
end

return BossService
