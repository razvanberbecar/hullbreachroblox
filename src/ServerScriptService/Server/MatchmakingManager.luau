--!strict
-- MatchmakingManager.lua  →  ModuleScript in ServerScriptService/Server
-- =============================================================================
-- CO-OP HALF 2: the join / matchmaking layer. Keeps solo isolated and pairs
-- co-op players, all on ONE place using private (reserved) servers.
--
-- Server types (detected at boot):
--   * PUBLIC server  (game.PrivateServerId == "")  = the front-door "router":
--       shows the menu; nobody plays here. Play Solo / Invite / Quick Match all
--       reserve a private server and teleport the player(s) out. Also catches
--       invited friends arriving with LaunchData and forwards them.
--   * RESERVED server (PrivateServerId ~= "" and PrivateServerOwnerId == 0) =
--       the actual game. Reads each arrival's TeleportData; a "coop" server waits
--       for 2 (EndingManager.SetExpectedPlayers(2)); a lone co-op player falls
--       back to solo after a grace period so nobody is ever stuck.
--
-- IMPORTANT: TeleportService + MemoryStoreService do NOTHING in Studio — this
-- whole layer can only be validated on a PUBLISHED server with real clients.
-- Every external call is pcall-guarded so a Studio playtest still boots clean.
-- =============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local serverFolder = ServerScriptService:WaitForChild("Server")

local MatchmakingManager = {}

local PLACE_ID = game.PlaceId
local INVITE_MAP = "DDCoopInvites"     -- SortedMap: joinKey -> { code = reservedAccessCode }
local QUEUE_NAME = "DDQuickMatch"      -- Queue of { userId } waiting for a partner
local ASSIGN_MAP = "DDMatchAssign"     -- SortedMap: userId -> { code } once matched
local ENTRY_TTL = 120                  -- seconds a quick-match queue/assignment entry lives
local INVITE_TTL = 900                 -- seconds an invite mapping lives (15 min)
local SOLO_FALLBACK_SECONDS = 35       -- co-op: play alone if no partner arrives by now

local isReserved = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0

local function getManager(name: string)
	local mod = serverFolder:FindFirstChild(name)
	if mod and mod:IsA("ModuleScript") then
		local ok, m = pcall(require, mod)
		if ok then return m end
	end
	return nil
end

local function status(player: Player, state: string, text: string?, joinKey: string?)
	Net.Event("MatchmakingStatus"):FireClient(player, { state = state, text = text, joinKey = joinKey })
end

local function dbg(msg: string)
	if GameConfig.Debug then print("[HullBreach][MM] " .. msg) end
end

-- Reserve a fresh private server, returning its access code (or nil on failure).
local function reserve(): string?
	local code
	local ok, err = pcall(function() code = select(1, TeleportService:ReserveServer(PLACE_ID)) end)
	if not ok then dbg("ReserveServer failed: " .. tostring(err)); return nil end
	return code
end

-- Teleport players into a reserved server (by access code) carrying teleport data.
local function sendToReserved(players: {Player}, code: string, data: {[string]: any}): boolean
	local opts = Instance.new("TeleportOptions")
	opts.ReservedServerAccessCode = code
	opts:SetTeleportData(data)
	local ok, err = pcall(function() TeleportService:TeleportAsync(PLACE_ID, players, opts) end)
	if not ok then dbg("TeleportAsync failed: " .. tostring(err)) end
	return ok
end

-- ===========================================================================
-- RESERVED (gameplay) server: configure solo vs co-op from teleport data
-- ===========================================================================
local function startReserved()
	local coopServer = false
	local fallbackArmed = false

	local function armSoloFallback()
		if fallbackArmed then return end
		fallbackArmed = true
		task.delay(SOLO_FALLBACK_SECONDS, function()
			if #Players:GetPlayers() <= 1 then
				local EM = getManager("EndingManager")
				if EM and EM.SetExpectedPlayers then EM.SetExpectedPlayers(1) end
				for _, p in ipairs(Players:GetPlayers()) do
					Net.Event("Notify"):FireClient(p, "No partner joined — you descend alone.")
				end
				if EM and EM.TryStart then EM.TryStart() end
				dbg("solo fallback fired (no partner)")
			end
		end)
	end

	local function onJoin(player: Player)
		local jd = nil
		pcall(function() jd = player:GetJoinData() end)
		local td = jd and jd.TeleportData
		if type(td) == "table" and td.mode == "coop" then
			coopServer = true
			local EM = getManager("EndingManager")
			if EM and EM.SetExpectedPlayers then EM.SetExpectedPlayers(2) end
			-- host: prompt them (client-side) to invite a friend once they've loaded in
			if td.host and type(td.joinKey) == "string" then
				task.delay(2, function()
					status(player, "inviteReady", "Invite a friend to descend with you.", td.joinKey)
				end)
			end
			armSoloFallback()
			dbg("reserved co-op arrival: " .. player.Name .. (td.host and " (host)" or ""))
		else
			dbg("reserved solo arrival: " .. player.Name)
		end
	end

	Players.PlayerAdded:Connect(onJoin)
	for _, p in ipairs(Players:GetPlayers()) do onJoin(p) end

	-- If a co-op partner leaves, drop the requirement so the survivor isn't stuck
	-- waiting on a player who is gone.
	Players.PlayerRemoving:Connect(function()
		if not coopServer then return end
		task.defer(function()
			if #Players:GetPlayers() <= 1 then
				local EM = getManager("EndingManager")
				if EM and EM.SetExpectedPlayers then EM.SetExpectedPlayers(1) end
				if EM and EM.TryStart then EM.TryStart() end
			end
		end)
	end)
end

-- ===========================================================================
-- PUBLIC (router) server: mode selection + matchmaking
-- ===========================================================================
local searching: {[Player]: boolean} = {}

local function startPublic()
	local inviteMap = MemoryStoreService:GetSortedMap(INVITE_MAP)
	local queue = MemoryStoreService:GetQueue(QUEUE_NAME)
	local assignMap = MemoryStoreService:GetSortedMap(ASSIGN_MAP)

	-- ---- Play Solo: reserve a 1-player private server + teleport ----
	Net.Event("RequestSolo").OnServerEvent:Connect(function(player)
		status(player, "loading", "Preparing your dive…")
		local code = reserve()
		if not code then status(player, "error", "Couldn't start — please try again."); return end
		if not sendToReserved({ player }, code, { mode = "solo" }) then
			status(player, "error", "Teleport failed — please try again.")
		end
	end)

	-- ---- Invite a Friend: reserve a co-op server, stash the mapping, teleport host ----
	Net.Event("RequestCoopHost").OnServerEvent:Connect(function(player)
		status(player, "loading", "Setting up a private dive…")
		local code = reserve()
		if not code then status(player, "error", "Couldn't create a co-op server."); return end
		local joinKey = HttpService:GenerateGUID(false):gsub("-", ""):sub(1, 12)
		pcall(function() inviteMap:SetAsync(joinKey, { code = code }, INVITE_TTL) end)
		if not sendToReserved({ player }, code, { mode = "coop", host = true, joinKey = joinKey }) then
			status(player, "error", "Teleport failed — please try again.")
		end
		-- The host's client is told to prompt the Roblox invite once it loads into
		-- the reserved server (see startReserved -> inviteReady).
	end)

	-- ---- Quick Match: join the cross-server queue ----
	Net.Event("RequestQuickMatch").OnServerEvent:Connect(function(player)
		if searching[player] then return end
		searching[player] = true
		status(player, "searching", "Searching for a partner…")
		pcall(function() queue:AddAsync({ userId = player.UserId }, ENTRY_TTL, 0) end)
	end)
	Net.Event("CancelMatchmaking").OnServerEvent:Connect(function(player)
		searching[player] = nil
		status(player, "cancelled")
	end)

	Players.PlayerRemoving:Connect(function(p) searching[p] = nil end)

	-- ---- Invited friend arrives (LaunchData) -> forward into the reserved server ----
	local function onJoin(player: Player)
		local jd = nil
		pcall(function() jd = player:GetJoinData() end)
		local launch = jd and jd.LaunchData
		if type(launch) ~= "string" or launch == "" then return end
		task.spawn(function()
			local code = nil
			pcall(function()
				local entry = inviteMap:GetAsync(launch)
				if type(entry) == "table" then code = entry.code end
			end)
			if code then
				status(player, "found", "Joining your friend…")
				if not sendToReserved({ player }, code, { mode = "coop" }) then
					status(player, "error", "Couldn't join — the co-op server may be full.")
				end
			else
				status(player, "error", "That co-op invite has expired.")
			end
		end)
	end
	Players.PlayerAdded:Connect(onJoin)
	for _, p in ipairs(Players:GetPlayers()) do onJoin(p) end

	-- Studio has no live MemoryStore/Teleport, so the matchmaking loops would just
	-- churn errors — only run them on a real server.
	if RunService:IsStudio() then
		dbg("public router up (Studio: matchmaking loops disabled)")
		return
	end

	-- ---- Matcher loop: pull pairs off the global queue, reserve a server, assign ----
	task.spawn(function()
		while true do
			task.wait(3)
			pcall(function()
				local items, readId = queue:ReadAsync(2, true, 0)  -- a pair, or nothing
				if items and #items == 2 then
					local code = reserve()
					if code then
						for _, it in ipairs(items) do
							local uid = it.userId or (it.value and it.value.userId)
							if uid then
								pcall(function() assignMap:SetAsync(tostring(uid), { code = code }, ENTRY_TTL) end)
							end
						end
						pcall(function() queue:RemoveAsync(readId) end)  -- commit the pair as consumed
						dbg("matched a pair -> reserved server")
					end
					-- if reserve failed we DON'T RemoveAsync: the pair reappears after the
					-- read invisibility window and can be matched again later.
				end
			end)
		end
	end)

	-- ---- Assignment poll: teleport our local searchers once they've been matched ----
	task.spawn(function()
		while true do
			task.wait(2)
			for _, player in ipairs(Players:GetPlayers()) do
				if searching[player] then
					pcall(function()
						local entry = assignMap:GetAsync(tostring(player.UserId))
						if type(entry) == "table" and entry.code then
							pcall(function() assignMap:RemoveAsync(tostring(player.UserId)) end)
							searching[player] = nil
							status(player, "found", "Partner found — descending…")
							sendToReserved({ player }, entry.code, { mode = "coop" })
						end
					end)
				end
			end
		end
	end)

	dbg("public router up (matchmaking live)")
end

function MatchmakingManager.Start()
	-- Tell clients what kind of server this is. Client-side game.PrivateServerId is
	-- unreliable (it reads empty in reserved servers), which made the reserved server
	-- show the router menu -> a Play-Solo teleport loop. The SERVER's value is reliable.
	ReplicatedStorage:SetAttribute("DD_ServerKind", isReserved and "reserved" or "public")

	-- "Return to Lobby" (works from any server): teleport the player to a normal
	-- PUBLIC server of this place (no ReservedServerAccessCode) — that's the router,
	-- which shows the Solo / Co-op menu. No teleport data, so the client resolves to
	-- the public menu instead of auto-starting.
	Net.Event("RequestLobby").OnServerEvent:Connect(function(player)
		local opts = Instance.new("TeleportOptions")  -- public destination (no reserved code)
		local ok = pcall(function() TeleportService:TeleportAsync(PLACE_ID, { player }, opts) end)
		if not ok then Net.Event("Notify"):FireClient(player, "Couldn't return to the lobby — try again.") end
	end)

	if isReserved then
		dbg("reserved gameplay server")
		startReserved()
	else
		startPublic()
	end
end

return MatchmakingManager
