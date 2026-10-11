--!strict
-- BatteryManager.lua  →  ModuleScript in ServerScriptService/Server
-- =============================================================================
-- The flashlight is a dedicated tool (its OWN slot, not one of the 4 inventory
-- slots). It is granted on pickup but starts HOLSTERED; the player toggles it
-- on/off with F (the client fires FlashlightToggle). Charge 0-100 drains only
-- while it is on (1 per 8s, faster once submerged a while), flickers below 20,
-- dies at 0. Battery items refill it (+50). The client FlashlightController
-- renders the beam + in-hand model from BatteryUpdate:
--   (charge, maxCharge, on, flicker, hasLight, equipped)
-- =============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemData = require(Shared:WaitForChild("ItemData"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Net = require(Shared:WaitForChild("Net"))

local serverFolder = ServerScriptService:WaitForChild("Server")
local F = ItemData.Flashlight

local BatteryManager = {}

local charge: {[Player]: number} = {}
local hasLight: {[Player]: boolean} = {}
local equipped: {[Player]: boolean} = {}
local submergedTime: {[Player]: number} = {}
local started = false
local TICK = 0.5

local function getManager(name: string)
	local mod = serverFolder:FindFirstChild(name)
	if mod and mod:IsA("ModuleScript") then
		local ok, m = pcall(require, mod)
		if ok then return m end
	end
	return nil
end

function BatteryManager.GrantFlashlight(player: Player)
	hasLight[player] = true
	equipped[player] = false          -- starts holstered; player presses F to turn it on
	if charge[player] == nil then charge[player] = F.maxCharge end
	BatteryManager.push(player)
end

function BatteryManager.HasFlashlight(player: Player): boolean
	return hasLight[player] == true
end

-- Equip / holster (only if the player actually owns a flashlight).
function BatteryManager.SetEquipped(player: Player, want: boolean)
	if not hasLight[player] then return end
	equipped[player] = want and true or false
	BatteryManager.push(player)
end

function BatteryManager.ToggleEquip(player: Player)
	if not hasLight[player] then return end
	BatteryManager.SetEquipped(player, not equipped[player])
end

function BatteryManager.AddCharge(player: Player, amount: number)
	charge[player] = math.clamp((charge[player] or 0) + amount, 0, F.maxCharge)
	BatteryManager.push(player)
end

function BatteryManager.GetCharge(player: Player): number
	return charge[player] or 0
end

function BatteryManager.push(player: Player)
	local c = charge[player] or 0
	local has = hasLight[player] == true
	local eq = has and (equipped[player] == true)
	local on = eq and c > 0
	local flicker = on and c < F.flickerBelow
	Net.Event("BatteryUpdate"):FireClient(player, c, F.maxCharge, on, flicker, has, eq)
end

local function playerSubmerged(player: Player): boolean
	local Flood = getManager("FloodManager")
	if not Flood then return false end
	local section = Flood.GetPlayerSection and Flood.GetPlayerSection(player)
	if not section then return false end
	return Flood.GetLevel(section) >= GameConfig.SwimLevelMax
end

local function step(player: Player, dt: number)
	-- the flashlight only drains while it is on (equipped). Holstering saves it.
	if not hasLight[player] or not equipped[player] then return end
	local c = charge[player] or 0
	if c <= 0 then
		charge[player] = 0
		BatteryManager.push(player)
		return
	end

	local drain = F.drainPerSecond * dt
	if playerSubmerged(player) then
		submergedTime[player] = (submergedTime[player] or 0) + dt
		if submergedTime[player] >= F.submergedSeconds then
			drain += F.submergedExtraDrain * dt
		end
	else
		submergedTime[player] = 0
	end

	charge[player] = math.max(c - drain, 0)
	BatteryManager.push(player)
end

-- Reset the flashlight for a fresh run: the player no longer owns it (they must
-- re-collect it from the torpedo room) and the client hides the slot + beam.
function BatteryManager.ResetPlayer(player: Player)
	charge[player] = nil
	hasLight[player] = nil
	equipped[player] = nil
	submergedTime[player] = nil
	BatteryManager.push(player)
end


function BatteryManager.Start()
	if started then return end
	started = true

	Players.PlayerRemoving:Connect(function(p)
		charge[p] = nil; hasLight[p] = nil; equipped[p] = nil; submergedTime[p] = nil
	end)

	-- client requests to equip/holster the flashlight (F key)
	Net.Event("FlashlightToggle").OnServerEvent:Connect(function(player)
		BatteryManager.ToggleEquip(player)
	end)

	task.spawn(function()
		while true do
			for _, p in ipairs(Players:GetPlayers()) do
				step(p, TICK)
			end
			task.wait(TICK)
		end
	end)

	if GameConfig.Debug then
		print("[HullBreach] BatteryManager started.")
	end
end

return BatteryManager
