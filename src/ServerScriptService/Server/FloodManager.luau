--!strict
-- FloodManager.lua  →  ModuleScript in ServerScriptService/Server
-- =============================================================================
-- Phase 3: authoritative flooding simulation. Tracks a 0-100 water level for
-- each of the 9 sections. Each section rises by a global baseline plus its own
-- breach rate; section 9 starts deep; section 8 escalates once a player enters
-- it. Bulkhead doors can be permanently sealed, isolating passage (and feeding
-- the "Sealed In" ending). Broadcasts FloodUpdate to all clients on an interval.
--
-- Other managers call into this module directly (require returns the cached
-- table): OxygenManager reads levels, CreatureManager reads flood-avoidance.
-- =============================================================================

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SectionData = require(Shared:WaitForChild("SectionData"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Net = require(Shared:WaitForChild("Net"))

local FloodManager = {}

-- State ----------------------------------------------------------------------
FloodManager.Levels = {}        -- [section] = 0..100
FloodManager.Discovered = {}    -- [section] = true once a player has entered
FloodManager.SealedDoors = {}   -- ["a-b"] = true (passage blocked)
FloodManager.MainPowerOn = false
FloodManager.RateMult = {}      -- [section] = multiplier on its flood rate (RandomizeRun); default 1

local started = false

-- Helpers --------------------------------------------------------------------
local function doorKey(a: number, b: number): string
	if a > b then a, b = b, a end
	return a .. "-" .. b
end

function FloodManager.GetLevel(section: number): number
	return FloodManager.Levels[section] or 0
end

-- Which section a player's character is currently in.
function FloodManager.GetPlayerSection(player: Player): number?
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end
	return SectionData.SectionAtPosition(hrp.Position)
end

function FloodManager.IsSealed(a: number, b: number): boolean
	return FloodManager.SealedDoors[doorKey(a, b)] == true
end

-- Called by PowerManager when the main generator comes online; sections flagged
-- floodsAfterMainPower begin filling, others get a nudge.
function FloodManager.OnMainPower()
	FloodManager.MainPowerOn = true
end

-- Seal a bulkhead door permanently. Returns success.
function FloodManager.SealDoor(a: number, b: number): boolean
	local key = doorKey(a, b)
	if FloodManager.SealedDoors[key] then return false end
	FloodManager.SealedDoors[key] = true

	-- find & solidify the physical door
	for _, door in ipairs(CollectionService:GetTagged("BulkheadDoor")) do
		local da, db = door:GetAttribute("SectionA"), door:GetAttribute("SectionB")
		if da and db and doorKey(da, db) == key then
			door:SetAttribute("Sealed", true)
			door:SetAttribute("Open", false)
			if door:IsA("BasePart") then
				door.CanCollide = true
				door.Transparency = 0
				door.Color = Color3.fromRGB(120, 40, 30)
				local open = door:FindFirstChild("DoorPrompt")
				local seal = door:FindFirstChild("SealPrompt")
				if open then (open :: ProximityPrompt).Enabled = false end
				if seal then (seal :: ProximityPrompt).Enabled = false end
			end
			break
		end
	end
	return true
end

-- Per-section flood rate this tick.
local function sectionRate(section: number): number
	local data = SectionData.Sections[section]
	if not data then return 0 end
	local rate = GameConfig.GlobalFloodRate + (data.floodRate or 0)
	if data.escalates and FloodManager.Discovered[section] then
		rate = GameConfig.GlobalFloodRate + (data.escalatedRate or data.floodRate)
	end
	if data.floodsAfterMainPower and not FloodManager.MainPowerOn then
		rate = GameConfig.GlobalFloodRate * 0.3 -- barely rises until main power
	end
	return rate * (FloodManager.RateMult[section] or 1)
end

-- Run randomization hook (EndingManager.RandomizeRun): scale each section's flood
-- rate so a different set of rooms breaches fast/slow every run. Bounded so no
-- section becomes instantly impassable (which could soft-lock a route).
function FloodManager.SetRateMultipliers(mults: {[number]: number})
	FloodManager.RateMult = mults or {}
end

-- Mark discovery as players move through the sub.
local function updateDiscovery()
	for _, player in ipairs(Players:GetPlayers()) do
		local sec = FloodManager.GetPlayerSection(player)
		if sec then
			FloodManager.Discovered[sec] = true
		end
	end
end

-- Simulation step
local EQUALIZE_RATE = 1.5  -- how fast water flows to level out through an open doorway

local function step(dt: number)
	-- The world is inert until a player has left the main menu (pressed Play).
	local anyActive = false
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("InMenu") == false then anyActive = true; break end
	end
	if not anyActive then return end
	updateDiscovery()
	for s = 1, SectionData.COUNT do
		local cur = FloodManager.Levels[s] or 0
		cur = math.clamp(cur + sectionRate(s) * dt, 0, 100)
		FloodManager.Levels[s] = cur
	end
	-- Water flows between rooms whose bulkhead door is OPEN (and not sealed): their
	-- levels equalise so an open doorway never shows two different water heights.
	local k = math.clamp(dt * EQUALIZE_RATE, 0, 1)
	for _, door in ipairs(CollectionService:GetTagged("BulkheadDoor")) do
		if door:GetAttribute("Open") and not door:GetAttribute("Sealed") then
			local a, b = door:GetAttribute("SectionA"), door:GetAttribute("SectionB")
			if a and b then
				local la, lb = FloodManager.Levels[a] or 0, FloodManager.Levels[b] or 0
				local mean = (la + lb) / 2
				FloodManager.Levels[a] = la + (mean - la) * k
				FloodManager.Levels[b] = lb + (mean - lb) * k
			end
		end
	end
end

-- Broadcast a snapshot of all section levels.
local function broadcast()
	Net.Event("FloodUpdate"):FireAllClients(FloodManager.Levels)
end

function FloodManager.Snapshot(): {[number]: number}
	return FloodManager.Levels
end

-- Reset to a fresh run (called by EndingManager.ResetRun).
function FloodManager.Reset()
	FloodManager.MainPowerOn = false
	FloodManager.SealedDoors = {}
	FloodManager.Discovered = {}
	for s = 1, SectionData.COUNT do
		FloodManager.Levels[s] = SectionData.Sections[s].startLevel or 0
	end
	broadcast()
end

function FloodManager.Start()
	if started then return end
	started = true

	-- initial levels from SectionData
	for s = 1, SectionData.COUNT do
		FloodManager.Levels[s] = SectionData.Sections[s].startLevel or 0
	end

	-- Sealing is server-authoritative: InteractionManager validates the SealPrompt
	-- by proximity, then calls FloodManager.SealDoor directly. There is deliberately
	-- NO client-facing SealDoor remote handler here — accepting arbitrary (a,b) from
	-- any client would let a player seal any bulkhead remotely (grief / self-trap).

	-- simulation loop
	task.spawn(function()
		while true do
			step(GameConfig.FloodTickInterval)
			task.wait(GameConfig.FloodTickInterval)
		end
	end)

	-- broadcast loop (GDD: every 2 seconds)
	task.spawn(function()
		while true do
			broadcast()
			task.wait(GameConfig.FloodSyncInterval)
		end
	end)

	if GameConfig.Debug then
		print("[HullBreach] FloodManager started.")
	end
end

return FloodManager
