--!strict
-- Bootstrap.server.lua  →  Script in ServerScriptService/Server
-- =============================================================================
-- Single server entry point. Initialises networking, then requires and starts
-- each manager ModuleScript in a deterministic order. Managers are added as
-- later phases land; missing ones are skipped so the project always boots.
--
-- Each manager module is expected to expose an optional `Start()` function.
-- =============================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))

-- Create all RemoteEvents/Functions up front.
Net.Init()

local serverFolder = ServerScriptService:WaitForChild("Server")

-- Ordered manager startup. Built out phase by phase.
local MANAGER_ORDER = {
	"MapBuilder",        -- Phase 2: builds the greybox submarine
	"InteractionManager",-- Phase 2/6: routes ProximityPrompt interactions
	"FloodManager",      -- Phase 3
	"OxygenManager",     -- Phase 3
	"PowerManager",      -- Phase 4
	"CreatureManager",   -- Phase 5
	"InventoryManager",  -- Phase 6
	"BatteryManager",    -- Phase 6
	"EndingManager",     -- Phase 7
	"MatchmakingManager",-- Co-op Half 2: private-server join / matchmaking router
	"PolishManager",     -- Phase 9
	"DataManager",       -- Phase 10
	"MonetizationManager",-- Phase 10
}

local started = {}

local function startManager(name: string)
	local mod = serverFolder:FindFirstChild(name)
	if not mod or not mod:IsA("ModuleScript") then
		if GameConfig.Debug then
			warn(("[HullBreach] Manager '%s' not present yet — skipping."):format(name))
		end
		return
	end
	local ok, mgr = pcall(require, mod)
	if not ok then
		warn(("[HullBreach] Failed to require %s: %s"):format(name, tostring(mgr)))
		return
	end
	if type(mgr) == "table" and type(mgr.Start) == "function" then
		local sok, err = pcall(mgr.Start)
		if not sok then
			warn(("[HullBreach] %s.Start() error: %s"):format(name, tostring(err)))
			return
		end
	end
	started[name] = mgr
	if GameConfig.Debug then
		print(("[HullBreach] Started %s"):format(name))
	end
end

for _, name in ipairs(MANAGER_ORDER) do
	startManager(name)
end

-- Expose started managers to other server modules that need cross-references.
_G.DeepDescent = { Managers = started }

print("[HullBreach] Server bootstrap complete.")
