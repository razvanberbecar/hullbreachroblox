--!strict
-- CreatureManager.lua  →  ModuleScript in ServerScriptService/Server
-- =============================================================================
-- Phase 5: the creature. Blind, hunts by sound, never fully shown. A single
-- server-driven NPC with a three-state machine (Dormant / Alerted / Hunting),
-- waypoint movement along the hull, sound detection, and the hiding mechanic.
--
-- Movement is deliberately waypoint/section based rather than full navmesh: the
-- greybox is a linear hull, and section-to-section stepping is robust, reads
-- exactly like the GDD's described patrol, and lets us enforce the "cannot enter
-- flooded / sealed / tower" rules cleanly. (PathfindingService is the production
-- upgrade for organic corridors.)
--
-- Other systems talk to it through:
--   CreatureManager.ReportSound(pos, soundType)   -- interactions/footsteps/splash
--   CreatureManager.SetState("alerted")           -- PowerManager on main power
-- =============================================================================

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SectionData = require(Shared:WaitForChild("SectionData"))
local CreatureData = require(Shared:WaitForChild("CreatureData"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Net = require(Shared:WaitForChild("Net"))

local serverFolder = ServerScriptService:WaitForChild("Server")

local CreatureManager = {}

-- Live state -----------------------------------------------------------------
local state = CreatureData.State.Dormant
local creature: Model? = nil
local root: BasePart? = nil

local patrolPos = 1            -- index into SectionData.PatrolOrder
local patrolDir = 1
local huntTarget: Vector3? = nil
local searchUntil = 0
local lingerUntil = 0
local peaceful = false
local started = false
local currentGoalSection: number? = nil
local startSection = 9         -- where the creature spawns; randomized per run (RandomizeRun)
local hideCounts: {[BasePart]: number} = {}  -- how often the player has used each locker (adaptive dread)
local goalLocker: BasePart? = nil            -- current "go check this remembered hiding spot" target

local KILL_RADIUS = 5
local ARRIVE_RADIUS = 6
local speedMult = 1      -- raised by the Nightmare pass
local detectMult = 1

-- Extended Nightmare Mode tuning hook (MonetizationManager).
function CreatureManager.SetDifficulty(sMult: number, dMult: number)
	speedMult = sMult or 1
	detectMult = dMult or 1
end

-- Run randomization hook (EndingManager.RandomizeRun): pick where it starts each
-- run. Repositions the live creature and aligns its patrol index so it prowls
-- outward from the new origin instead of walking back to the old one.
function CreatureManager.SetStartSection(sec: number)
	startSection = sec
	for i, s in ipairs(SectionData.PatrolOrder) do
		if s == sec then patrolPos = i; break end
	end
	if root then
		local c = SectionData.SectionCenter(sec)
		root.CFrame = CFrame.new(c.X, 4.5, 0)
	end
end

-- Player hiding state (set by the locker interaction)
local hiding: {[Player]: BasePart} = {}
local hideData: {[Player]: { restore: CFrame, walk: number, jump: number }} = {}
local lastToggle: {[Player]: number} = {}  -- debounce so the prompt + ExitHide can't double-toggle
local lastPlayerPos: {[Player]: Vector3} = {}  -- for close-range movement sensing
local caught: {[Player]: boolean} = {}  -- so the catch fires once per life (no jumpscare spam)

-- Lazy manager access --------------------------------------------------------
local function getManager(name: string)
	local mod = serverFolder:FindFirstChild(name)
	if mod and mod:IsA("ModuleScript") then
		local ok, m = pcall(require, mod)
		if ok then return m end
	end
	return nil
end

local function floodLevel(section: number): number
	local FloodManager = getManager("FloodManager")
	return (FloodManager and FloodManager.GetLevel and FloodManager.GetLevel(section)) or 0
end

local function isSealed(a: number, b: number): boolean
	local FloodManager = getManager("FloodManager")
	return FloodManager and FloodManager.IsSealed and FloodManager.IsSealed(a, b) or false
end

-- ----------------------------------------------------------------------------
-- Spawn the creature stand-in (kept dark / barely visible on purpose)
-- ----------------------------------------------------------------------------
local function spawnCreature()
	local existing = Workspace:FindFirstChild("Creature")
	if existing then existing:Destroy() end

	local model = Instance.new("Model")
	model.Name = "Creature"

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(4, 9, 4)
	body.Anchored = true
	body.CanCollide = false
	body.CastShadow = true
	body.Color = Color3.fromRGB(8, 8, 10)
	body.Material = Enum.Material.SmoothPlastic
	body.Transparency = 0.5  -- the core mass stays murky; the welded shape gives the silhouette
	body.Color = Color3.fromRGB(14, 18, 24)
	local startPos = SectionData.SectionCenter(startSection)
	body.CFrame = CFrame.new(startPos.X, 4.5, 0)
	body.Parent = model
	model.PrimaryPart = body

	-- ---- a strange deep-sea creature, welded to the body (-Z = front/face) ----
	local DARK = Color3.fromRGB(18, 22, 30)
	local function piece(name: string, size: Vector3, offset: CFrame, opts)
		opts = opts or {}
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = opts.color or DARK
		p.Material = opts.material or Enum.Material.SmoothPlastic
		p.Transparency = opts.transparency or 0.2
		p.Anchored = false
		p.CanCollide = false
		p.CastShadow = opts.castShadow == true
		if opts.shape then p.Shape = opts.shape end
		p.CFrame = body.CFrame * offset
		p.Parent = body
		local w = Instance.new("WeldConstraint")
		w.Part0 = body; w.Part1 = p; w.Parent = p
		return p
	end

	-- head + snout
	piece("DD_Head", Vector3.new(3.6, 3.2, 3.8), CFrame.new(0, 3, -0.6), { color = Color3.fromRGB(20, 24, 32), transparency = 0.12, shape = Enum.PartType.Ball, castShadow = true })
	piece("DD_Snout", Vector3.new(2.3, 1.9, 2.6), CFrame.new(0, 2.3, -2.2), { color = Color3.fromRGB(16, 20, 28), transparency = 0.12, shape = Enum.PartType.Ball })
	-- (gaping maw + ragged teeth removed by request — no mouth)
	-- anglerfish lure on a drooping stalk
	piece("DD_Stalk", Vector3.new(0.18, 0.18, 2.4), CFrame.new(0, 4.7, -2.0) * CFrame.Angles(math.rad(40), 0, 0), { color = Color3.fromRGB(12, 16, 22), transparency = 0.05, shape = Enum.PartType.Cylinder })
	local lure = piece("DD_Lure", Vector3.new(0.55, 0.55, 0.55), CFrame.new(0, 5.5, -3.5), { color = Color3.fromRGB(120, 230, 205), transparency = 0, shape = Enum.PartType.Ball, material = Enum.Material.Neon })
	local lglow = Instance.new("PointLight"); lglow.Color = Color3.fromRGB(90, 210, 185); lglow.Brightness = 0.8; lglow.Range = 9; lglow.Shadows = false; lglow.Parent = lure
	-- side gill-fins
	for _, sx in ipairs({ -1, 1 }) do
		piece("DD_Fin", Vector3.new(0.2, 2.8, 3.2), CFrame.new(sx * 2.1, 1.4, 0.6) * CFrame.Angles(0, math.rad(sx * 22), math.rad(sx * 14)), { transparency = 0.4 })
	end
	-- dorsal spines down the back (+Z)
	for i = 0, 4 do
		piece("DD_Spine", Vector3.new(0.18, 1.4 - i * 0.18, 0.7), CFrame.new(0, 3.6 - i * 1.3, 1.9) * CFrame.Angles(math.rad(18), 0, 0), { color = Color3.fromRGB(14, 18, 26), transparency = 0.05 })
	end
	-- splayed tentacles around the lower body
	local tent = {
		{ x = -1.4, z = -1.1, pitch = 18, roll = 24 },
		{ x = 1.4, z = -1.1, pitch = 18, roll = -24 },
		{ x = -1.7, z = 0.7, pitch = -8, roll = 32 },
		{ x = 1.7, z = 0.7, pitch = -8, roll = -32 },
		{ x = -0.6, z = 1.4, pitch = -20, roll = 8 },
		{ x = 0.7, z = 1.4, pitch = -20, roll = -10 },
	}
	for idx, t in ipairs(tent) do
		piece("DD_Tentacle" .. idx, Vector3.new(0.5, 3.6, 0.5), CFrame.new(t.x, -1.6, t.z) * CFrame.Angles(math.rad(t.pitch), 0, math.rad(t.roll)), { transparency = 0.18 })
	end

	-- (eyes + red eye-glow removed by request — the creature reads as a pure silhouette,
	--  its only glow being the anglerfish lure above)

	-- a soft point light-less marker; sound layers are on the client (Phase 8)
	model.Parent = Workspace
	creature = model
	root = body
end

-- ----------------------------------------------------------------------------
-- State control
-- ----------------------------------------------------------------------------
local function baseState(): string
	local PowerManager = getManager("PowerManager")
	if PowerManager and PowerManager.State and PowerManager.State.mainPower then
		return CreatureData.State.Alerted
	end
	return CreatureData.State.Dormant
end

local lastStartleCue = 0
function CreatureManager.SetState(newState: string)
	if peaceful and newState == CreatureData.State.Hunting then return end
	if state == newState then return end
	state = newState
	-- creepy screech the moment it's startled into a hunt (debounced)
	if newState == CreatureData.State.Hunting and root and (os.clock() - lastStartleCue) > 3 then
		lastStartleCue = os.clock()
		Net.Event("SoundCue"):FireAllClients("creature_startle", root.Position, 0.85)
	end
	if GameConfig.Debug then
		print("[HullBreach] Creature -> " .. newState)
	end
end

function CreatureManager.GetState(): string
	return state
end

-- Live creature position (OxygenManager reads this for composure/breathing panic).
function CreatureManager.GetPosition(): Vector3?
	return root and root.Position or nil
end

-- The Truth ending: creature ceases all aggression and retreats to the deep.
function CreatureManager.SetPeaceful()
	peaceful = true
	CreatureManager.SetState(CreatureData.State.Dormant)
	huntTarget = nil
end

-- Reset to a fresh run (called by EndingManager.ResetRun).
function CreatureManager.Reset()
	peaceful = false
	huntTarget = nil
	searchUntil = 0
	patrolPos = 1
	patrolDir = 1
	currentGoalSection = nil
	table.clear(hiding)
	table.clear(caught)
	table.clear(hideCounts)
	goalLocker = nil
	lingerUntil = 0
	state = CreatureData.State.Dormant
	spawnCreature()
end

-- ----------------------------------------------------------------------------
-- Sound detection
-- ----------------------------------------------------------------------------
function CreatureManager.ReportSound(pos: Vector3, soundType: string)
	if not root or peaceful then return end
	local intensity = CreatureData.SoundIntensity[soundType] or 0
	if intensity <= 0 then return end -- crouch / silent

	local cfg = CreatureData.States[state]
	local trigger = CreatureData.HuntTriggerIntensity[state]
	if not trigger then
		-- already hunting: update last known position for high-intensity sounds
		if state == CreatureData.State.Hunting and intensity >= 2 then
			huntTarget = pos
		end
		return
	end

	local dist = (pos - root.Position).Magnitude
	local soundSection = SectionData.SectionAtPosition(pos)
	local creatureSection = SectionData.SectionAtPosition(root.Position)
	local hops = SectionData.Distance(creatureSection, soundSection)

	-- Water masks sound: a sound made in a flooded section is heard at a reduced
	-- effective radius (and the cross-section hops check ignores flooded sources).
	local soundLevel = floodLevel(soundSection)
	local waterMask = 1 - (1 - CreatureData.WaterMaskFactor) * math.clamp(soundLevel / 100, 0, 1)
	local inRange = dist <= ((cfg.detectionRadius or 0) * detectMult * waterMask)
		or (hops <= (cfg.detectionSections or 0) and soundLevel < CreatureData.FloodAvoidLevel)

	if inRange and intensity >= trigger then
		huntTarget = pos
		searchUntil = 0
		CreatureManager.SetState(CreatureData.State.Hunting)
	end
end

-- ----------------------------------------------------------------------------
-- Movement
-- ----------------------------------------------------------------------------
-- A section is enterable if it isn't fully flooded and isn't the tower.
local function enterable(section: number): boolean
	if section == 7 then return false end
	if floodLevel(section) >= CreatureData.FloodAvoidLevel then return false end
	return true
end

-- Next hull section in patrol order, honouring seals/flood by reversing.
local function advancePatrol(): number
	local order = SectionData.PatrolOrder
	local cur = order[patrolPos]
	local nextIdx = patrolPos + patrolDir
	if nextIdx < 1 or nextIdx > #order then
		patrolDir = -patrolDir
		nextIdx = patrolPos + patrolDir
	end
	local nextSec = order[nextIdx]
	-- blocked by seal or flood? reverse.
	if isSealed(cur, nextSec) or not enterable(nextSec) then
		patrolDir = -patrolDir
		nextIdx = math.clamp(patrolPos + patrolDir, 1, #order)
		nextSec = order[nextIdx]
	end
	patrolPos = nextIdx
	return nextSec
end

-- Adaptive behaviour: the creature "remembers" which lockers the player leans on
-- (hideCounts, tallied on each hide) and, once alerted, sometimes detours to the
-- most-used one to check it — more often the more the player relies on it. Escalating
-- personal dread that reuses the existing goal machinery.
local function pickFavoriteLocker(): BasePart?
	local best, bestCount = nil, 0
	for locker, n in pairs(hideCounts) do
		if locker.Parent and enterable(SectionData.SectionAtPosition(locker.Position)) and n > bestCount then
			best, bestCount = locker, n
		end
	end
	if not best then return nil end
	local chance = math.min(0.25 + 0.12 * (bestCount - 1), 0.7)  -- escalates with reliance, capped 70%
	if math.random() < chance then return best end
	return nil
end

local function pickAlertedSection(): number
	local cfg = CreatureData.States.alerted
	local lo, hi = cfg.patrolRange[1], cfg.patrolRange[2]
	-- weight toward the generator anchor
	if math.random() < 0.45 then
		if enterable(cfg.anchorSection) then return cfg.anchorSection end
	end
	for _ = 1, 6 do
		local s = math.random(lo, hi)
		if s ~= 7 and enterable(s) then return s end
	end
	return cfg.anchorSection
end

-- Current movement goal as a world position.
local function resolveGoal(): Vector3?
	if state == CreatureData.State.Hunting then
		return huntTarget
	end
	if not currentGoalSection or not enterable(currentGoalSection) then
		goalLocker = nil
		if state == CreatureData.State.Alerted then
			local fav = pickFavoriteLocker()
			if fav then
				goalLocker = fav
				currentGoalSection = SectionData.SectionAtPosition(fav.Position)
			else
				currentGoalSection = pickAlertedSection()
			end
		else
			currentGoalSection = advancePatrol()
		end
	end
	-- head for the remembered locker's exact spot (they line the side walls, off-centre
	-- on Z) so the creature looms right at it, not just the room centre.
	if goalLocker and goalLocker.Parent and enterable(currentGoalSection) then
		return Vector3.new(goalLocker.Position.X, 4.5, goalLocker.Position.Z)
	end
	local c = SectionData.SectionCenter(currentGoalSection)
	return Vector3.new(c.X, 4.5, 0)
end

local function nearestPlayer(): (Player?, number)
	local best, bestD = nil, math.huge
	if not root then return nil, bestD end
	for _, p in ipairs(Players:GetPlayers()) do
		local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local d = (hrp.Position - root.Position).Magnitude
			if d < bestD then best, bestD = p, d end
		end
	end
	return best, bestD
end

local function killPlayer(player: Player)
	if caught[player] then return end
	caught[player] = true
	-- creepy catch sound at the victim, right before the death cutscene
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if hrp then Net.Event("SoundCue"):FireAllClients("creature_catch", hrp.Position, 1.0) end
	local EndingManager = getManager("EndingManager")
	if EndingManager and EndingManager.Trigger then
		EndingManager.Trigger(player, "taken")
	else
		Net.Event("PlayerDied"):FireClient(player, "taken")
	end
end

local function step(dt: number)
	if GameConfig.FreezeCreature then return end -- TEST: creature movement/kill frozen
	if not root then return end
	-- Stay inert until a player has left the main menu (pressed Play).
	do
		local anyActive = false
		for _, p in ipairs(Players:GetPlayers()) do
			if p:GetAttribute("InMenu") == false then anyActive = true; break end
		end
		if not anyActive then return end
	end

	-- Close-range sensing: if a player MOVES while right next to the creature it
	-- catches them even when crouched. Crouch only keeps you hidden at a distance;
	-- standing dead still (no position change) right beside it is still safe.
	if not peaceful then
		for _, p in ipairs(Players:GetPlayers()) do
			local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if hrp and not hiding[p] and not p:GetAttribute("InMenu") then
				local prev = lastPlayerPos[p]
				local moved = prev and (hrp.Position - prev).Magnitude or 0
				lastPlayerPos[p] = hrp.Position
				if moved > 0.06 and (hrp.Position - root.Position).Magnitude <= CreatureData.CloseSenseRadius then
					huntTarget = hrp.Position
					searchUntil = 0
					CreatureManager.SetState(CreatureData.State.Hunting)
				end
			end
		end
	end
	local cfg = CreatureData.States[state]
	local speed = (cfg.speed or 8) * speedMult

	-- If hunting led us into a flood threshold, drop out immediately.
	local curSection = SectionData.SectionAtPosition(root.Position)
	if state == CreatureData.State.Hunting and floodLevel(curSection) >= CreatureData.FloodAvoidLevel then
		CreatureManager.SetState(baseState())
		huntTarget = nil
	end

	local goal = resolveGoal()
	local blockedBySeal = false
	if goal then
		local toGoal = goal - root.Position
		local dist = toGoal.Magnitude
		if dist > 0.1 then
			local stepDist = math.min(speed * dt, dist)
			local newPos = root.Position + toGoal.Unit * stepDist
			-- Honour sealed bulkheads even while hunting: never slide across a
			-- sealed (or impassable) doorway. Clamp to just shy of the boundary.
			local curSec = SectionData.SectionAtPosition(root.Position)
			local nextSec = SectionData.SectionAtPosition(newPos)
			if nextSec ~= curSec and (isSealed(curSec, nextSec) or not enterable(nextSec)) then
				local cx = SectionData.SectionCenter(curSec).X
				local nx = SectionData.SectionCenter(nextSec).X
				local boundary = (cx + nx) / 2
				local eps = 2
				newPos = Vector3.new(boundary + (cx < nx and -eps or eps), newPos.Y, newPos.Z)
				blockedBySeal = true
			end
			-- face direction of travel
			root.CFrame = CFrame.lookAt(newPos, newPos + Vector3.new(toGoal.X, 0, toGoal.Z))
		end

		if dist <= ARRIVE_RADIUS or blockedBySeal then
			if state == CreatureData.State.Hunting then
				-- arrived at the last known sound (or a sealed bulkhead is in the way):
				-- is a reachable, exposed player here?
				local p, pd = nearestPlayer()
				if not blockedBySeal and p and pd <= ARRIVE_RADIUS and not hiding[p] then
					-- continue closing; kill handled below
				else
					-- search, then give up (longer if someone is hiding here)
					local anyHidingNear = false
					for hp, locker in pairs(hiding) do
						if (locker.Position - root.Position).Magnitude <= ARRIVE_RADIUS + 4 then
							anyHidingNear = true
						end
					end
					if searchUntil == 0 then
						searchUntil = os.clock() + (anyHidingNear
							and CreatureData.States.hunting.hideLingerSeconds
							or CreatureData.States.hunting.searchSeconds)
					elseif os.clock() >= searchUntil then
						searchUntil = 0
						huntTarget = nil
						currentGoalSection = nil
						CreatureManager.SetState(baseState())
					end
				end
			elseif goalLocker and goalLocker.Parent then
				-- reached a remembered hiding spot: loom over it and "check" it (a breath
				-- cue) before moving on. A player hiding here survives only by staying
				-- perfectly still + silent; any heartbeat/breath gives them away.
				if lingerUntil == 0 then
					lingerUntil = os.clock() + 2.5
					if root then Net.Event("SoundCue"):FireAllClients("creature_breath", goalLocker.Position, 0.7) end
				elseif os.clock() >= lingerUntil then
					lingerUntil = 0
					goalLocker = nil
					currentGoalSection = nil
				end
			else
				currentGoalSection = nil -- pick a new patrol goal next tick
			end
		end
	end

	-- Kill check: exposed player within reach while hunting.
	if state == CreatureData.State.Hunting then
		local p, pd = nearestPlayer()
		if p and pd <= KILL_RADIUS and not hiding[p] and not p:GetAttribute("InMenu") then
			killPlayer(p)
		end
	end
end

-- ----------------------------------------------------------------------------
-- Hiding mechanic (locker interaction)
-- ----------------------------------------------------------------------------
local function toggleHide(player: Player, locker: BasePart)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local now = os.clock()
	if lastToggle[player] and now - lastToggle[player] < 0.4 then return end
	lastToggle[player] = now
	if hiding[player] then
		-- step out: stand the player back where they were; restore the cabinet + movement
		hiding[player] = nil
		player:SetAttribute("Hiding", false)
		local data = hideData[player]
		hideData[player] = nil
		if hrp then hrp.Anchored = false end
		if hrp and data then hrp.CFrame = data.restore end
		if locker then
			locker.CanCollide = true
			if data and data.fade then
				for _, e in ipairs(data.fade) do e.part.Transparency = e.t end
			end
			local pr = locker:FindFirstChildOfClass("ProximityPrompt")
			if pr then pr.Enabled = true end
		end
		if hum and data then
			hum.WalkSpeed = data.walk
			hum.JumpHeight = data.jump
		end
		Net.Event("Notify"):FireClient(player, "You slip out of the locker.")
	else
		if not hrp then return end
		-- step in: remember the spot, make the cabinet non-solid so it can't eject the
		-- player, drop them inside and freeze movement. NOT anchored — anchoring blocked
		-- the exit prompt; press the same prompt again to climb out.
		hiding[player] = locker
		hideCounts[locker] = (hideCounts[locker] or 0) + 1  -- remember this hiding spot
		player:SetAttribute("Hiding", true)
		-- remember every painted surface (body + steel-locker greeble) so we can fade it
		-- translucent while hiding and restore it exactly on exit.
		local fade = {}
		for _, d in ipairs(locker:GetDescendants()) do
			if d:IsA("BasePart") then fade[#fade + 1] = { part = d, t = d.Transparency } end
		end
		fade[#fade + 1] = { part = locker, t = locker.Transparency }
		hideData[player] = {
			restore = hrp.CFrame,
			walk = (hum and hum.WalkSpeed) or 14,
			jump = (hum and hum.JumpHeight) or 7,
			fade = fade,
		}
		if hum then hum.WalkSpeed = 0; hum.JumpHeight = 0 end
		-- Climb INSIDE the cabinet (not standing in front of it) and turn it + its door
		-- translucent so the first-person camera sees OUT instead of going black. Lockers
		-- line the long side walls, so face toward the section centre on Z.
		locker.CanCollide = false
		for _, e in ipairs(fade) do e.part.Transparency = math.max(e.t, 0.7) end
		do
			local pr = locker:FindFirstChildOfClass("ProximityPrompt")
			if pr then pr.Enabled = false end
		end
		hrp.AssemblyLinearVelocity = Vector3.zero
		local toRoom = (locker.Position.Z < 0) and 1 or -1
		local insideZ = locker.Position.Z + toRoom * (locker.Size.Z / 2 - 0.5)
		hrp.CFrame = CFrame.lookAt(
			Vector3.new(locker.Position.X, locker.Position.Y, insideZ),
			Vector3.new(locker.Position.X, locker.Position.Y, insideZ + toRoom * 10)
		)
		hrp.Anchored = true
		Net.Event("Notify"):FireClient(player, "You pull the locker shut. Be still. Don't move the mouse.")
	end
end

-- ----------------------------------------------------------------------------
-- Sync to clients (state + position) for audio tiers (Phase 8)
-- ----------------------------------------------------------------------------
local function sync()
	if not root then return end
	Net.Event("CreatureUpdate"):FireAllClients({
		state = state,
		position = root.Position,
	})
end

function CreatureManager.Start()
	if started then return end
	started = true

	spawnCreature()
	state = CreatureData.State.Dormant

	-- player sound events from the client (walk/run/splash)
	Net.Event("SoundEvent").OnServerEvent:Connect(function(player, soundType)
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if hrp and type(soundType) == "string" then
			if hiding[player] then return end -- silent in locker (except heartbeat)
			CreatureManager.ReportSound(hrp.Position, soundType)
			-- audible water sounds for everyone (footsteps stay silent — no asset, too noisy)
			if soundType == "splash" or soundType == "swim" then
				Net.Event("SoundCue"):FireAllClients(soundType, hrp.Position)
			end
		end
	end)

	-- heartbeat while hiding (mouse movement) — medium intensity
	Net.Event("HeartbeatSound").OnServerEvent:Connect(function(player)
		local locker = hiding[player]
		if locker then
			CreatureManager.ReportSound(locker.Position, "heartbeat")
		end
	end)

	-- explicit "leave the locker" request: the in-locker prompt is unreliable once
	-- the player is teleported inside the (non-collidable) part, so the client fires
	-- this on E while hiding. Debounced in toggleHide so it can't double-toggle.
	Net.Event("ExitHide").OnServerEvent:Connect(function(player)
		local locker = hiding[player]
		if locker then toggleHide(player, locker) end
	end)

	-- locker interaction
	local Interaction = getManager("InteractionManager")
	if Interaction and Interaction.Register then
		Interaction.Register("locker", function(player, part)
			if part:IsA("BasePart") then toggleHide(player, part) end
		end)
	end

	Players.PlayerRemoving:Connect(function(p) hiding[p] = nil; hideData[p] = nil; lastToggle[p] = nil; lastPlayerPos[p] = nil; caught[p] = nil end)

	-- movement loop
	task.spawn(function()
		local last = os.clock()
		while true do
			local now = os.clock()
			local dt = now - last
			last = now
			pcall(step, dt)
			task.wait(CreatureData.SyncInterval)
		end
	end)

	-- sync loop
	task.spawn(function()
		while true do
			sync()
			task.wait(CreatureData.SyncInterval)
		end
	end)

	if GameConfig.Debug then
		print("[HullBreach] CreatureManager started (dormant).")
	end
end

return CreatureManager
