--!strict
-- OxygenManager.lua  →  ModuleScript in ServerScriptService/Server
-- =============================================================================
-- Phase 3: oxygen + drowning, plus the slow suffocation that drives the
-- "Sealed In" bad ending. Oxygen (seconds) drains when the player's section is
-- submerged past the drown threshold, or — more slowly — when the player is
-- trapped in a fully sealed-off section with no open exit. Refilled by oxygen
-- canisters (InventoryManager calls AddOxygen).
-- =============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SectionData = require(Shared:WaitForChild("SectionData"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Net = require(Shared:WaitForChild("Net"))

local serverFolder = ServerScriptService:WaitForChild("Server")
local FloodManager = require(serverFolder:WaitForChild("FloodManager"))

local OxygenManager = {}

local TICK = 0.5
local SEALED_DRAIN_FACTOR = 0.35   -- sealed-in suffocation is slower than drowning
local REGEN_PER_SEC = 6            -- oxygen recovery while safe/above water
local CROUCH_DIP = 1.8             -- crouch lowers the eye/camera ~1.8 studs; the drown line drops with it

local oxygen = {}   -- [player] = seconds remaining
local crouch = {}   -- [player] = true while crouching (from the client)
local dead = {}     -- [player] = true while in an ending sequence
local started = false

local oxyMult = 1  -- lowered by the Nightmare pass

function OxygenManager.SetDifficulty(mult: number)
	oxyMult = mult or 1
end

local function baseMax(): number
	return GameConfig.OxygenMaxSeconds * oxyMult
end

function OxygenManager.AddOxygen(player: Player, seconds: number)
	oxygen[player] = (oxygen[player] or baseMax()) + seconds
end

function OxygenManager.GetOxygen(player: Player): number
	return oxygen[player] or baseMax()
end

-- Is the player's section sealed off on every connection?
local function isSealedIn(section: number): boolean
	local neighbors = SectionData.Adjacency[section]
	if not neighbors or #neighbors == 0 then return false end
	for _, n in ipairs(neighbors) do
		if not FloodManager.IsSealed(section, n) then
			return false
		end
	end
	return true
end

-- Resolve the death cause to an ending and hand off to EndingManager if present.
local function triggerDeath(player: Player, endingId: string)
	if dead[player] then return end
	dead[player] = true
	local endingMod = serverFolder:FindFirstChild("EndingManager")
	if endingMod and endingMod:IsA("ModuleScript") then
		local ok, EndingManager = pcall(require, endingMod)
		if ok and type(EndingManager) == "table" and EndingManager.Trigger then
			EndingManager.Trigger(player, endingId)
			return
		end
	end
	-- fallback before Phase 7 exists
	Net.Event("PlayerDied"):FireClient(player, endingId)
end

local function stepPlayer(player: Player, dt: number)
	if dead[player] then return end
	if player:GetAttribute("InMenu") then return end
	local section = FloodManager.GetPlayerSection(player)
	if not section then return end

	local level = FloodManager.GetLevel(section)
	-- Submerged when the player's head is actually below the section's water
	-- surface (not only when the whole section is ~full). Intuitive, and makes
	-- the breath meter appear whenever you duck underwater.
	local waterY = SectionData.LevelToWaterY(level)
	local char = player.Character
	local head = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
	local dip = crouch[player] and CROUCH_DIP or 0  -- crouching ducks the view underwater sooner
	local submerged = head ~= nil and ((head :: BasePart).Position.Y - dip) <= waterY
	local sealed = isSealedIn(section)
	local cur = oxygen[player] or baseMax()
	local danger = false
	local cause = "drowned"

	if submerged then
		cur -= dt
		danger = true
		cause = "drowned"
	elseif sealed then
		cur -= dt * SEALED_DRAIN_FACTOR
		danger = true
		cause = "sealed_in"
	else
		cur = math.min(cur + REGEN_PER_SEC * dt, baseMax())
	end

	oxygen[player] = cur

	if cur <= 0 then
		oxygen[player] = 0
		triggerDeath(player, cause)
	end

	-- Tell the client (it shows the meter only when in danger).
	Net.Event("OxygenUpdate"):FireClient(player, math.max(cur, 0), baseMax(), danger)
end

-- Reset oxygen for a fresh run. CharacterAdded also refills on respawn, but this
-- clears the meter + death flag immediately when ResetRun runs.
function OxygenManager.ResetPlayer(player: Player)
	dead[player] = nil
	oxygen[player] = baseMax()
	Net.Event("OxygenUpdate"):FireClient(player, baseMax(), baseMax(), false)
end


function OxygenManager.Start()
	if started then return end
	started = true

	Players.PlayerAdded:Connect(function(p)
		oxygen[p] = baseMax()
	end)
	Players.PlayerRemoving:Connect(function(p)
		oxygen[p] = nil
		dead[p] = nil
		crouch[p] = nil
	end)
	Net.Event("SetCrouch").OnServerEvent:Connect(function(p, state)
		crouch[p] = state == true
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		oxygen[p] = baseMax()
	end

	task.spawn(function()
		while true do
			for _, p in ipairs(Players:GetPlayers()) do
				stepPlayer(p, TICK)
			end
			task.wait(TICK)
		end
	end)

	-- clear the dead flag when a character respawns (Endings phase respawns)
	Players.PlayerAdded:Connect(function(p)
		p.CharacterAdded:Connect(function()
			dead[p] = nil
			oxygen[p] = baseMax()
		end)
	end)

	if GameConfig.Debug then
		print("[HullBreach] OxygenManager started.")
	end
end

return OxygenManager
