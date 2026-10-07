--!nocheck
-- V2 phase 2 ("World V2") scenarios: budgets, route accessibility, caves,
-- bounce pads, landmarks, grapple anchors and non-regression of the V1 core
-- (Sanctuaries, Rift, spawn/tutorial anchors).
--
-- Route accessibility uses a geometric walker: it follows each route at
-- 1-stud steps over the terrain heightmap plus the top faces of every
-- collidable part, and requires (in both directions) that each step can be
-- climbed (<= 2.2 studs), that gaps are only crossed where the route is
-- declared "hop" (stepping stones, <= 6 studs) and that nothing collidable
-- occupies the character's body (1.5 to 4.6 studs above the feet).

local Vector3 = require("@lune/roblox").Vector3

local STEP_UP = 2.2
local HOP_GAP = 6
local BUCKET = 16

return function(ctx)
	local scenario, check, advance = ctx.scenario, ctx.check, ctx.advance
	local sreq, shared, Engine = ctx.sreq, ctx.shared, ctx.Engine
	local workspace = Engine.workspace

	local Layout = shared("Layout")
	local WorldFeatures = shared("WorldFeatures")
	local GameConfig = shared("Config.GameConfig")
	local TerrainBuilder = sreq("World.TerrainBuilder")

	--------------------------------------------------------------------------
	-- Solid geometry cache (plain numbers, bucketed in XZ)
	--------------------------------------------------------------------------

	local function excluded(part): boolean
		local node = part.Parent
		while node and node ~= workspace do
			if node.Name == "Relics" or node.Name == "Barrier" or node:FindFirstChildOfClass("Humanoid") then
				return true
			end
			node = node.Parent
		end
		return false
	end

	local solids = {}
	local buckets = {}
	local function bucketKey(ix, iz)
		return ix * 100000 + iz
	end
	for _, part in workspace:GetDescendants() do
		if part:IsA("BasePart") and part.CanCollide and not excluded(part) then
			local cf, size = part.CFrame, part.Size
			local shape = "Block"
			if part.ClassName == "Part" then
				shape = part.Shape.Name
			end
			if part:FindFirstChildOfClass("SpecialMesh") then
				shape = "Ellipsoid"
			end
			local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
			local s = {
				name = part.Name,
				cx = cf.Position.X, cy = cf.Position.Y, cz = cf.Position.Z,
				ax = { r.X, r.Y, r.Z }, ay = { u.X, u.Y, u.Z }, az = { -l.X, -l.Y, -l.Z },
				hx = size.X / 2, hy = size.Y / 2, hz = size.Z / 2,
				shape = shape,
			}
			table.insert(solids, s)
			local reach = math.sqrt(s.hx * s.hx + s.hy * s.hy + s.hz * s.hz)
			for ix = math.floor((s.cx - reach) / BUCKET), math.floor((s.cx + reach) / BUCKET) do
				for iz = math.floor((s.cz - reach) / BUCKET), math.floor((s.cz + reach) / BUCKET) do
					local key = bucketKey(ix, iz)
					buckets[key] = buckets[key] or {}
					table.insert(buckets[key], s)
				end
			end
		end
	end

	local function near(x, z)
		return buckets[bucketKey(math.floor(x / BUCKET), math.floor(z / BUCKET))] or {}
	end

	local function dot(a, x, y, z)
		return a[1] * x + a[2] * y + a[3] * z
	end

	local function contains(s, x, y, z): boolean
		local dx, dy, dz = x - s.cx, y - s.cy, z - s.cz
		local lx, ly, lz = dot(s.ax, dx, dy, dz), dot(s.ay, dx, dy, dz), dot(s.az, dx, dy, dz)
		if s.shape == "Ball" then
			return dx * dx + dy * dy + dz * dz < s.hx * s.hx * 0.97
		elseif s.shape == "Ellipsoid" then
			return (lx / s.hx) ^ 2 + (ly / s.hy) ^ 2 + (lz / s.hz) ^ 2 < 0.97
		elseif s.shape == "Cylinder" then
			local radius = math.min(s.hy, s.hz)
			return math.abs(lx) < s.hx - 0.05 and (ly * ly + lz * lz) < (radius - 0.05) ^ 2
		end
		return math.abs(lx) < s.hx - 0.05 and math.abs(ly) < s.hy - 0.05 and math.abs(lz) < s.hz - 0.05
	end

	-- Height of the walkable top of `s` at (x, z), or nil.
	local function topAt(s, x, z): number?
		local dx, dz = x - s.cx, z - s.cz
		if s.shape == "Ball" then
			local d2 = dx * dx + dz * dz
			if d2 <= s.hx * s.hx then
				return s.cy + math.sqrt(s.hx * s.hx - d2)
			end
			return nil
		elseif s.shape == "Ellipsoid" then
			local k = (dx / s.hx) ^ 2 + (dz / s.hz) ^ 2
			if k <= 1 then
				return s.cy + s.hy * math.sqrt(1 - k)
			end
			return nil
		elseif s.shape == "Cylinder" and math.abs(s.ax[2]) > 0.9 then
			local radius = math.min(s.hy, s.hz)
			if dx * dx + dz * dz <= radius * radius then
				return s.cy + s.hx
			end
			return nil
		end
		-- Box-like: the face whose normal points most upward.
		local axes = { { s.ax, s.hx }, { s.ay, s.hy }, { s.az, s.hz } }
		local best, bestY = 1, -1
		for i, a in axes do
			if math.abs(a[1][2]) > bestY then
				best, bestY = i, math.abs(a[1][2])
			end
		end
		if bestY < 0.45 then
			return nil
		end
		local up = axes[best]
		local sign = if up[1][2] >= 0 then 1 else -1
		local tx = s.cx + up[1][1] * up[2] * sign
		local ty = s.cy + up[1][2] * up[2] * sign
		local tz = s.cz + up[1][3] * up[2] * sign
		local others = {}
		for i, a in axes do
			if i ~= best then
				table.insert(others, a)
			end
		end
		local b1, b2 = others[1], others[2]
		local det = b1[1][1] * b2[1][3] - b2[1][1] * b1[1][3]
		if math.abs(det) < 1e-6 then
			return nil
		end
		local px, pz = x - tx, z - tz
		local a = (px * b2[1][3] - b2[1][1] * pz) / det
		local b = (b1[1][1] * pz - px * b1[1][3]) / det
		if math.abs(a) > b1[2] or math.abs(b) > b2[2] then
			return nil
		end
		return ty + a * b1[1][2] + b * b2[1][2]
	end

	local function surfaces(x, z, extra)
		local list = {}
		local sample = TerrainBuilder.sample(x, z)
		if sample then
			table.insert(list, sample.height)
			-- Rivers are swum at the surface, not walked on the bed.
			if sample.zone == "river" and sample.height < Layout.WaterY then
				table.insert(list, Layout.WaterY)
			end
		end
		for _, s in near(x, z) do
			local top = topAt(s, x, z)
			if top then
				table.insert(list, top)
			end
		end
		if extra then
			for _, y in extra(x, z) do
				table.insert(list, y)
			end
		end
		return list
	end

	local function bodyBlocked(x, y, z): string?
		for _, h in { 1.5, 3, 4.6 } do
			for _, s in near(x, z) do
				if contains(s, x, y + h, z) then
					return s.name
				end
			end
		end
		return nil
	end

	-- Walks `points` (XZ; Y ignored). Returns ok, reason.
	local TRACE = false
	local function walk(points, mode, extra): (boolean, string?)
		local path = {}
		for i = 1, #points - 1 do
			local a, b = points[i], points[i + 1]
			local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
			local n = math.max(1, math.ceil(flat.Magnitude))
			for k = 0, n - 1 do
				table.insert(path, Vector3.new(a.X, 0, a.Z) + flat * (k / n))
			end
		end
		local last = points[#points]
		table.insert(path, Vector3.new(last.X, 0, last.Z))

		local first = surfaces(path[1].X, path[1].Z, extra)
		local y = -math.huge
		for _, s in first do
			if s > y and not bodyBlocked(path[1].X, s, path[1].Z) then
				y = s
			end
		end
		if y == -math.huge then
			return false, "no ground at start"
		end
		local gap = 0
		for i = 2, #path do
			local p = path[i]
			local best = -math.huge
			for _, s in surfaces(p.X, p.Z, extra) do
				if s <= y + STEP_UP and s > best and s > y - 40 then
					best = s
				end
			end
			local supported = best > -math.huge and best > y - 6
			if TRACE then
				print(string.format("      step %d (%.1f, %.1f) y=%.2f best=%.2f", i, p.X, p.Z, y, best))
			end
			if not supported and mode == "hop" and gap < HOP_GAP then
				gap += 1
			elseif best == -math.huge then
				return false, string.format("no reachable ground at (%.0f, %.0f) from y=%.1f", p.X, p.Z, y)
			else
				gap = 0
				y = best
				local blocker = bodyBlocked(p.X, y, p.Z)
				if blocker then
					return false, string.format("blocked by %s at (%.0f, %.1f, %.0f)", blocker, p.X, y, p.Z)
				end
			end
		end
		return true, nil
	end

	local function reversed(list)
		local out = {}
		for i = #list, 1, -1 do
			table.insert(out, list[i])
		end
		return out
	end

	--------------------------------------------------------------------------
	scenario("V2 World: size, budgets and build", function()
		local parts, lights, emitters, beams = 0, 0, 0, 0
		for _, d in workspace:GetDescendants() do
			if d:IsA("BasePart") and not excluded(d) then
				parts += 1
			elseif d:IsA("PointLight") then
				lights += 1
			elseif d:IsA("ParticleEmitter") then
				emitters += 1
			elseif d:IsA("Beam") then
				beams += 1
			end
		end
		print(string.format("  world: %d parts, %d lights, %d emitters, %d beams", parts, lights, emitters, beams))
		check(parts <= GameConfig.World.PartBudget, string.format("part budget %d <= %d", parts, GameConfig.World.PartBudget))
		check(lights <= GameConfig.World.LightBudget, string.format("light budget %d <= %d", lights, GameConfig.World.LightBudget))
		check(emitters <= GameConfig.World.EmitterBudget, string.format("particle emitter budget %d <= %d", emitters, GameConfig.World.EmitterBudget))

		-- Usable area: ground samples inside the island, V1 radius 236 vs now.
		local inside = 0
		for x = -330, 330, 4 do
			for z = -330, 330, 4 do
				if TerrainBuilder.sample(x, z) then
					inside += 1
				end
			end
		end
		local v1 = math.pi * 236 * 236 / 16
		local growth = inside / v1 - 1
		check(growth >= 0.3 and growth <= 0.5, string.format("usable surface +%.0f%% (target +30..50%%)", growth * 100))
		check(Layout.PlotDistance == 172, "Sanctuaries stay at the V1 distance (trips not longer)")
		for _, name in { "Landmarks", "Outskirts", "GrapplePoints" } do
			check(workspace.World:FindFirstChild(name) ~= nil, name .. " built")
		end
	end)

	--------------------------------------------------------------------------
	scenario("V2 World: every main route is walkable both ways", function()
		local routes = table.clone(WorldFeatures.Routes)
		-- Sky Route: island tops + bridges + ledge landing.
		local sky = {}
		for _, island in WorldFeatures.SkyRoute.islands do
			table.insert(sky, island.position)
		end
		table.insert(sky, WorldFeatures.SkyRoute.landing)
		table.insert(routes, { name = "Sky Route (islands + rune bridges)", mode = "walk", points = sky })
		for _, route in routes do
			TRACE = ctx.traceRoute ~= nil and string.find(route.name, ctx.traceRoute, 1, true) ~= nil
			local ok, reason = walk(route.points, route.mode)
			TRACE = false
			local back, reasonBack = walk(reversed(route.points), route.mode)
			check(ok and back, route.name .. ": " .. (if ok and back then "ok" else (reason or reasonBack or "?")))
		end
	end)

	--------------------------------------------------------------------------
	scenario("V2 World: caves are carved, lit and walkable", function()
		local carves = {}
		for _, op in Engine.terrainLog do
			if op.material == "Air" and op.op == "Block" then
				table.insert(carves, op)
			end
		end
		check(#carves >= 8, "tunnels carved (" .. #carves .. " blocks)")
		local function insideCarve(p, clearance)
			for _, op in carves do
				local localP = op.cf:PointToObjectSpace(p)
				local localTop = op.cf:PointToObjectSpace(p + Vector3.new(0, clearance, 0))
				local h = op.size / 2
				if math.abs(localP.X) <= h.X and math.abs(localP.Y) <= h.Y + 0.6 and math.abs(localP.Z) <= h.Z
					and math.abs(localTop.Y) <= h.Y and math.abs(localTop.X) <= h.X and math.abs(localTop.Z) <= h.Z then
					return true
				end
			end
			return false
		end
		for _, cave in WorldFeatures.Caves do
			local okCovered, okOpen, okRoof, okSlope = true, true, true, true
			local maxSlope = 0
			local pts = cave.points
			for i = 1, #pts - 1 do
				local a, b = WorldFeatures.cavePoint(pts[i]), WorldFeatures.cavePoint(pts[i + 1])
				local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z).Magnitude
				local slope = math.abs(b.Y - a.Y) / flat
				maxSlope = math.max(maxSlope, slope)
				local n = math.ceil(flat)
				for k = 1, n - 1 do
					local p = a:Lerp(b, k / n)
					if pts[i].covered and pts[i + 1].covered then
						if not insideCarve(p + Vector3.new(0, 0.4, 0), 5.6) then
							okCovered = false
						end
						-- Roof under the river: at least 2.5 studs of rock below the bed.
						local sample = TerrainBuilder.sample(p.X, p.Z)
						if sample and sample.zone == "river" and sample.height - (p.Y + cave.height) < 2.5 then
							okRoof = false
						end
					else
						local sample = TerrainBuilder.sample(p.X, p.Z)
						if not sample or math.abs(sample.height - p.Y) > 1.6 then
							okOpen = false
							print(string.format("    %s ravine seg %d: terrain %.1f vs floor %.1f", cave.name, i, sample and sample.height or -1, p.Y))
						end
					end
				end
			end
			okSlope = maxSlope <= 0.75
			check(okCovered, cave.name .. ": tunnel carved with >= 5.6 studs headroom")
			check(okOpen, cave.name .. ": ravines follow the cave floor")
			check(okRoof, cave.name .. ": rock roof kept under the river")
			check(okSlope, string.format("%s: walkable slopes (max %.0f deg)", cave.name, math.deg(math.atan(maxSlope))))
			local folder = workspace.World.Outskirts:FindFirstChild(cave.name)
			local lights = 0
			for _, d in folder:GetDescendants() do
				if d:IsA("PointLight") then
					lights += 1
				end
			end
			check(lights >= 3, cave.name .. ": mouths and tunnel are lit (" .. lights .. " lights)")
			-- Open ends are walkable from the surface into the ravine.
			local entry = {}
			for i = 1, 3 do
				table.insert(entry, WorldFeatures.cavePoint(pts[i]))
			end
			local exit = {}
			for i = #pts - 1, #pts do
				table.insert(exit, WorldFeatures.cavePoint(pts[i]))
			end
			local okIn, whyIn = walk(entry, "walk")
			local okOut, whyOut = walk(exit, "walk")
			check(okIn and okOut, cave.name .. ": ravines walkable down to both mouths " .. tostring(whyIn or whyOut or ""))
		end
	end)

	--------------------------------------------------------------------------
	scenario("V2 World: bounce pads land where they should", function()
		local g = workspace.Gravity
		local pads = {}
		for _, d in workspace.World:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("Launch") then
				table.insert(pads, d)
			end
		end
		check(#pads >= 5, "bounce pads present (" .. #pads .. ")")
		for _, pad in pads do
			local v = pad:GetAttribute("Launch")
			local target = pad:GetAttribute("Target")
			local horizontal = Vector3.new(v.X, 0, v.Z).Magnitude
			check(horizontal < GameConfig.Security.MaxHorizontalSpeed, pad.Name .. ": launch below the movement guard limit")
			-- Integrate the jump until it comes back down to the destination height.
			local p = pad.Position + Vector3.new(0, 3, 0)
			local vel = v
			local landed = nil
			local clear = true
			for _ = 1, 600 do
				vel -= Vector3.new(0, g / 120, 0)
				p += vel / 120
				local ground = TerrainBuilder.heightAt(p.X, p.Z)
				local destY = if target then target.Y else -math.huge
				if vel.Y < 0 and p.Y <= destY + 0.5 then
					landed = p
					break
				end
				if ground and p.Y < ground - 1 and (target == nil or (Vector3.new(p.X, 0, p.Z) - Vector3.new(target.X, 0, target.Z)).Magnitude > 6) then
					clear = false
					break
				end
			end
			if target then
				local miss = if landed then (Vector3.new(landed.X, 0, landed.Z) - Vector3.new(target.X, 0, target.Z)).Magnitude else math.huge
				check(clear and miss < 3, string.format("%s: clears the terrain and lands on target (miss %.1f)", pad.Name, miss))
			end
		end
	end)

	--------------------------------------------------------------------------
	scenario("V2 World: landmarks, Observatory stair, grapple anchors", function()
		local landmarks = workspace.World.Landmarks
		local observatory = landmarks:FindFirstChild("Observatory")
		local arch = landmarks:FindFirstChild("BrokenArch")
		local boss = landmarks:FindFirstChild("BossPlateau")
		check(observatory and arch and boss, "3 landmarks built")
		local function topOf(model)
			local top = -math.huge
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					top = math.max(top, d.Position.Y + d.Size.Y / 2)
				end
			end
			return top
		end
		check(topOf(observatory) >= Layout.GroundY + 85, "Observatory visible from afar (top Y " .. math.floor(topOf(observatory)) .. ")")
		check(topOf(arch) >= Layout.GroundY + 40, "Broken Arch rises above the ledge")
		check(boss:GetAttribute("PortalState") == "Dormant", "boss portal built, dormant (no boss logic yet)")

		-- Observatory stair: each step reachable from the previous one.
		local steps = {}
		for _, d in observatory:GetChildren() do
			if d.Name == "ObservatoryStep" then
				table.insert(steps, d)
			end
		end
		table.sort(steps, function(a, b)
			return a.Position.Y < b.Position.Y
		end)
		local stairOk = #steps >= 20
		-- Vertical cylinders: height is Size.X.
		local plinth = observatory:FindFirstChild("PlinthTop")
		local prevTop = plinth.Position.Y + plinth.Size.X / 2
		local prevPos = nil
		for _, step in steps do
			local top = step.Position.Y + 0.5
			if top - prevTop > 1.6 then
				stairOk = false
			end
			if prevPos and (Vector3.new(step.Position.X, 0, step.Position.Z) - prevPos).Magnitude > 5.5 then
				stairOk = false
			end
			prevTop = top
			prevPos = Vector3.new(step.Position.X, 0, step.Position.Z)
		end
		local balcony = observatory:FindFirstChild("Balcony")
		local balconyTop = balcony.Position.Y + balcony.Size.X / 2
		check(stairOk and balconyTop - prevTop <= 1.6, "spiral stair climbs step by step to the balcony")
		local blocked = bodyBlocked(prevPos.X, balconyTop, prevPos.Z)
		local lastStep = steps[#steps]
		local towardCenter = (balcony.Position - lastStep.Position)
		local onBalcony = lastStep.Position + Vector3.new(towardCenter.X, 0, towardCenter.Z).Unit * 4
		check(bodyBlocked(onBalcony.X, balconyTop, onBalcony.Z) == nil and blocked == nil, "parapet opening where the stair arrives")

		-- Grapple anchors: present, tagged, in open air.
		local folder = workspace.World:FindFirstChild("GrapplePoints")
		local count, okAttrs, okAir = 0, true, true
		for _, anchor in folder:GetChildren() do
			count += 1
			if anchor:GetAttribute("GrapplePoint") ~= true or type(anchor:GetAttribute("Kind")) ~= "string" or anchor:GetAttribute("Range") ~= WorldFeatures.GrappleRange then
				okAttrs = false
			end
			if anchor.CanCollide or anchor.CanQuery then
				okAttrs = false
			end
			local p = anchor.Position
			for _, s in near(p.X, p.Z) do
				if contains(s, p.X, p.Y, p.Z) then
					okAir = false
					print("    grapple point inside geometry:", anchor.Name, s.name)
				end
			end
			local ground = TerrainBuilder.heightAt(p.X, p.Z)
			if ground and ground > p.Y - 1 then
				okAir = false
				print("    grapple point under terrain:", anchor.Name)
			end
		end
		check(count == #WorldFeatures.GrapplePoints and count >= 12, "grapple anchors placed (" .. count .. ")")
		check(okAttrs, "grapple anchors tagged (GrapplePoint, Kind, Range) and non-colliding")
		check(okAir, "grapple anchors in open air")
	end)

	--------------------------------------------------------------------------
	scenario("V2 World: V1 core untouched (Sanctuaries, Rift, spawns)", function()
		-- Ground under each Sanctuary platform is still flat at GroundY.
		local flat = true
		for i = 1, Layout.PlotCount do
			local c = Layout.plotCFrame(i).Position
			for _, offset in { Vector3.new(0, 0, 0), Vector3.new(30, 0, 0), Vector3.new(-30, 0, 0), Vector3.new(0, 0, 30), Vector3.new(0, 0, -30), Vector3.new(21, 0, 21) } do
				local h = TerrainBuilder.heightAt(c.X + offset.X, c.Z + offset.Z)
				if not h or math.abs(h - Layout.GroundY) > 0.05 then
					flat = false
				end
			end
		end
		check(flat, "terrain under every Sanctuary still flat at GroundY")
		-- No V2 geometry intrudes on a Sanctuary platform, its ramp or the Rift basin.
		local intrusions = {}
		for _, root in { workspace.World.Landmarks, workspace.World.Outskirts } do
			for _, d in root:GetDescendants() do
				if d:IsA("BasePart") then
					local p = d.Position
					local flatP = Vector3.new(p.X, 0, p.Z)
					if flatP.Magnitude < Layout.BasinRadius + 4 and d.CanCollide then
						table.insert(intrusions, d.Name .. " in Rift basin")
					end
					for i = 1, Layout.PlotCount do
						local c = Layout.plotCFrame(i).Position
						local foot = Layout.rampFoot(i)
						if (flatP - Vector3.new(c.X, 0, c.Z)).Magnitude < Layout.PlatformRadius + 3 then
							table.insert(intrusions, d.Name .. " on Sanctuary " .. i)
						end
						if (flatP - Vector3.new(foot.X, 0, foot.Z)).Magnitude < 12 then
							table.insert(intrusions, d.Name .. " on ramp " .. i)
						end
					end
				end
			end
		end
		check(#intrusions == 0, "no V2 geometry on Sanctuaries, ramps or the Rift basin (" .. table.concat(intrusions, ", ") .. ")")
		-- Rift spawn spots and the waiting spot keep their ground.
		local spotsOk = true
		for _, spot in Layout.Spots do
			if spot.kind == "Ring" then
				local h = TerrainBuilder.heightAt(spot.position.X, spot.position.Z)
				if not h or math.abs(h - Layout.BasinY) > 1 then
					spotsOk = false
				end
			end
		end
		check(spotsOk, "Rift spawn spots unchanged")
		local waitH = TerrainBuilder.heightAt(0, -Layout.RimRadius - 6)
		check(waitH and math.abs(waitH - Layout.GroundY) < 2, "no-Sanctuary waiting spot still on the meadow")
		-- Each Sanctuary gate reaches the Rift basin (tutorial path: plot -> Rift).
		local allOk, failures = true, {}
		for i = 1, Layout.PlotCount do
			local foot = Layout.rampFoot(i)
			local a = Layout.plotAngle(i)
			-- Nearest crossing (bridge or ford) is 22.5 degrees away.
			local crossing = math.deg(a) + 22.5
			local points = {
				foot,
				Vector3.new(math.cos(a) * 112, 0, math.sin(a) * 112),
				WorldFeatures.polar(crossing, 112, 0),
				WorldFeatures.polar(crossing, 30, 0),
			}
			-- "hop": half of the crossings are stepping-stone fords.
			local ok, reason = walk(points, "hop")
			if not ok then
				allOk = false
				table.insert(failures, "S" .. i .. ": " .. tostring(reason))
			end
		end
		check(allOk, "every Sanctuary reaches the Rift on foot (" .. table.concat(failures, "; ") .. ")")
	end)

	--------------------------------------------------------------------------
	if ctx.noClient then
		return -- signs are built by the client (covered by tests/run.luau)
	end
	scenario("V2 World: Sanctuary signs are compact and distance-limited", function()
		local signs = 0
		local okSize = true
		for _, d in workspace.Sanctuaries:GetDescendants() do
			if d:IsA("BillboardGui") and d.Name == "Sign" then
				signs += 1
				if d.Size.X.Offset ~= 0 or d.Size.X.Scale <= 0 or d.Size.X.Scale > 14 or d.MaxDistance > 160 then
					okSize = false
				end
			end
		end
		check(signs == Layout.PlotCount, "one sign per Sanctuary (" .. signs .. ")")
		check(okSize, "signs sized in studs (shrink with distance) and hidden beyond 160 studs")
		advance(0.5)
	end)
end
