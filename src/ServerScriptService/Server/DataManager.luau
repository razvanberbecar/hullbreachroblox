--!strict
-- DataManager.lua  →  ModuleScript in ServerScriptService/Server
-- =============================================================================
-- Persistent per-player data via DataStoreService, now split into:
--   * META (account-wide): unlocked/selected save slot, owned passes, owned +
--     equipped cosmetics, and settings. These follow the ACCOUNT, not the slot.
--   * SLOT (per save slot): endings discovered + completion. Extra Save Slots
--     let a player keep separate ending/discovery progress ("try different
--     endings"). Default 1 slot, up to MAX_SLOTS via the Extra Save Slot product.
-- Falls back to in-memory when the DataStore is unavailable (Studio without API).
-- =============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
-- In Studio the DataStore API is off (GetAsync throws), so there's nothing real to
-- protect: treat reads as clean-empty (fast, in-memory) instead of retrying + flagging
-- the session read-only. The retry/guard below is for the LIVE game only.
local IN_STUDIO = RunService:IsStudio()

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Net = require(Shared:WaitForChild("Net"))

local DataManager = {}
local MAX_SLOTS = 3

local STORE_NAME = "DeepDescent_PlayerData_v2"
local store: DataStore? = nil
local ok = pcall(function() store = DataStoreService:GetDataStore(STORE_NAME) end)
if not ok then store = nil end

-- Dedicated store for de-duplicating developer-product receipts (ProcessReceipt
-- can fire more than once for the same purchase). Persisted so a retry never
-- double-grants (e.g. an Extra Save Slot counted twice).
local receiptStore: DataStore? = nil
pcall(function() receiptStore = DataStoreService:GetDataStore("DD_Receipts_v1") end)

-- Leaderboards (OrderedDataStores). Populate only in the PUBLISHED game; Studio
-- has no API access, so these stay nil and every call below is pcall-guarded.
local ESCAPE_IDS = { "escape_pod", "sos_signal", "surface_manually", "the_truth", "hubris" }
local endingsStore, survivalStore
local escapeStores: {[string]: any} = {}
pcall(function()
	endingsStore = DataStoreService:GetOrderedDataStore("DD_LB_Endings_v1")
	survivalStore = DataStoreService:GetOrderedDataStore("DD_LB_Survival_v1")
	for _, id in ipairs(ESCAPE_IDS) do
		escapeStores[id] = DataStoreService:GetOrderedDataStore("DD_LB_Escape_" .. id .. "_v1")
	end
end)

local meta: {[Player]: any} = {}      -- account-wide
local profiles: {[Player]: any} = {}  -- the CURRENTLY selected slot's progress
local started = false

local function defaultMeta()
	return {
		slot = 1,
		slots = 1,
		passes = {},           -- [passKey] = true
		owned = {},            -- [cosmeticKey] = true
		cosmetics = { flashlight = "default", suit = "default", death = "default" },
		settings = { master = 1, music = 0.8, sfx = 1, sensitivity = 1, brightness = 0 },
		records = { bestSurvival = 0, bestEscape = {}, mostEndings = 0 },
	}
end
local function defaultSlot()
	return { endings = {}, completed = false }
end

local function metaKey(p: Player) return "p_" .. p.UserId .. "_meta" end
local function slotKey(p: Player, n: number) return "p_" .. p.UserId .. "_slot" .. n end

-- Returns (data, ok). ok=false ONLY when the read genuinely FAILED (throttle/
-- outage) — NOT when it succeeded with no data (a new player). Callers use ok to
-- avoid overwriting real saved data with defaults after a failed load.
local function getAsync(k: string): (any, boolean)
	if not store or IN_STUDIO then return nil, true end  -- no DataStore / Studio; saves no-op anyway
	local lastErr
	for attempt = 1, 3 do
		local success, data = pcall(function() return store:GetAsync(k) end)
		if success then
			if data == nil or type(data) == "table" then return data, true end
			return nil, true  -- present but not a table: treat as empty, read still succeeded
		end
		lastErr = data
		task.wait(attempt)  -- brief backoff, then retry
	end
	if GameConfig.Debug then warn("[HullBreach] DataStore read failed for " .. k .. ": " .. tostring(lastErr)) end
	return nil, false
end
local function setAsync(k: string, v: any)
	if not store then return end
	pcall(function() store:SetAsync(k, v) end)
end

local function loadSlot(p: Player, n: number): (any, boolean)
	local d = defaultSlot()
	local saved, ok = getAsync(slotKey(p, n))
	if saved then for k, v in pairs(saved) do d[k] = v end end
	return d, ok
end

-- Combined read-only view used by clients (GetGameState) + other managers.
local function combined(p: Player)
	local m, prof = meta[p], profiles[p]
	if not (m and prof) then return nil end
	return {
		endings = prof.endings, completed = prof.completed,
		passes = m.passes, owned = m.owned, cosmetics = m.cosmetics,
		settings = m.settings, slot = m.slot, slots = m.slots, maxSlots = MAX_SLOTS,
	}
end

function DataManager.GetProfile(player: Player)
	return combined(player)
end

-- Sessions whose load FAILED (read error, not an empty new profile) are flagged
-- read-only so leaving can never overwrite the player's real saved data with defaults.
local loadFailed: {[Player]: boolean} = {}
local function saveMeta(p: Player) if meta[p] and not loadFailed[p] then setAsync(metaKey(p), meta[p]) end end
local function saveSlot(p: Player) if meta[p] and profiles[p] and not loadFailed[p] then setAsync(slotKey(p, meta[p].slot), profiles[p]) end end
local function saveAll(p: Player) saveMeta(p); saveSlot(p) end

local function load(player: Player)
	local m = defaultMeta()
	local savedMeta, metaOk = getAsync(metaKey(player))
	if savedMeta then for k, v in pairs(savedMeta) do m[k] = v end end
	m.slots = math.clamp(m.slots or 1, 1, MAX_SLOTS)
	m.slot = math.clamp(m.slot or 1, 1, m.slots)
	m.cosmetics = m.cosmetics or { flashlight = "default", suit = "default", death = "default" }
	m.records = m.records or { bestSurvival = 0, bestEscape = {}, mostEndings = 0 }
	meta[player] = m
	local slot, slotOk = loadSlot(player, m.slot)
	profiles[player] = slot
	-- If EITHER read failed, run this session read-only so leaving can't wipe saved data.
	if not (metaOk and slotOk) then
		loadFailed[player] = true
		warn(("[HullBreach] Load failed for %s — session is READ-ONLY to protect saved data."):format(player.Name))
	end
	DataManager.ApplyCosmetics(player)
end

-- Progress (per slot) ---------------------------------------------------------
function DataManager.RecordEnding(player: Player, endingId: string)
	local prof = profiles[player]
	if not prof then return end
	prof.endings[endingId] = true
	if endingId == "escape_pod" or endingId == "sos_signal"
		or endingId == "surface_manually" or endingId == "the_truth" or endingId == "hubris" then
		prof.completed = true
	end
	saveSlot(player)
end

-- Leaderboards ----------------------------------------------------------------
local function orderedSet(s: any, userId: number, value: number)
	if not s then return end
	pcall(function() s:SetAsync(tostring(userId), value) end)
end

-- Called by EndingManager when a run ends (win OR lose). elapsed = run seconds.
-- Updates the account-wide best records and pushes improvements to the boards.
function DataManager.RecordRunResult(player: Player, endingId: string, elapsed: number?)
	local m, prof = meta[player], profiles[player]
	if not (m and prof) then return end
	m.records = m.records or { bestSurvival = 0, bestEscape = {}, mostEndings = 0 }
	local rec = m.records

	-- most endings unlocked (max over the active slot's discovery set)
	local count = 0
	for _ in pairs(prof.endings) do count += 1 end
	if count > (rec.mostEndings or 0) then
		rec.mostEndings = count
		orderedSet(endingsStore, player.UserId, count)
	end

	if type(elapsed) == "number" and elapsed > 0 then
		local secs = math.floor(elapsed)
		-- longest survival, any run (higher is better)
		if secs > (rec.bestSurvival or 0) then
			rec.bestSurvival = secs
			orderedSet(survivalStore, player.UserId, secs)
		end
		-- fastest escape, per completing ending (lower is better)
		if table.find(ESCAPE_IDS, endingId) then
			rec.bestEscape = rec.bestEscape or {}
			local prev = rec.bestEscape[endingId]
			if not prev or secs < prev then
				rec.bestEscape[endingId] = secs
				orderedSet(escapeStores[endingId], player.UserId, secs)
			end
		end
	end
	saveMeta(player)
end

local nameCache: {[number]: string} = {}
local function resolveName(userId: number): string
	if nameCache[userId] then return nameCache[userId] end
	local okn, name = pcall(function() return Players:GetNameFromUserIdAsync(userId) end)
	local n = (okn and name) or ("Player " .. userId)
	nameCache[userId] = n
	return n
end
local function topOf(s: any, ascending: boolean, limit: number)
	local out = {}
	if not s then return out end
	local oks, pages = pcall(function() return s:GetSortedAsync(ascending, limit) end)
	if not oks or not pages then return out end
	local okp, page = pcall(function() return pages:GetCurrentPage() end)
	if not okp or not page then return out end
	for _, entry in ipairs(page) do
		local uid = tonumber(entry.key)
		out[#out + 1] = { name = uid and resolveName(uid) or tostring(entry.key), value = entry.value }
	end
	return out
end

local lbCache: any = nil
local lbCacheAt = 0
-- Top-10 of every board. Cached 30s to respect DataStore quotas.
function DataManager.GetLeaderboards()
	if lbCache and (os.clock() - lbCacheAt) < 30 then return lbCache end
	local res = {
		endings = topOf(endingsStore, false, 10),
		survival = topOf(survivalStore, false, 10),
		escape = {},
		escapeIds = ESCAPE_IDS,
	}
	for _, id in ipairs(ESCAPE_IDS) do
		res.escape[id] = topOf(escapeStores[id], true, 10)
	end
	lbCache = res
	lbCacheAt = os.clock()
	return res
end

-- Purchases + preferences (account-wide) --------------------------------------
function DataManager.GrantPass(player: Player, passKey: string)
	local m = meta[player]; if m then m.passes[passKey] = true; saveMeta(player) end
end
function DataManager.GrantCosmetic(player: Player, cosmeticKey: string)
	local m = meta[player]; if m then m.owned[cosmeticKey] = true; saveMeta(player) end
end
function DataManager.AddSaveSlot(player: Player)
	local m = meta[player]; if m then m.slots = math.min(m.slots + 1, MAX_SLOTS); saveMeta(player) end
end

-- Receipt de-dup (developer products). WasReceiptProcessed is checked BEFORE granting,
-- MarkReceiptProcessed is written AFTER, both persisted in a dedicated store.
function DataManager.WasReceiptProcessed(player: Player, purchaseId: string?): boolean
	if not (receiptStore and purchaseId) then return false end
	local key = tostring(player.UserId) .. "_" .. tostring(purchaseId)
	local okc, val = pcall(function() return receiptStore:GetAsync(key) end)
	return okc == true and val == true
end
function DataManager.MarkReceiptProcessed(player: Player, purchaseId: string?): boolean
	if not receiptStore then return true end   -- Studio/no-API: nothing to persist against
	if not purchaseId then return false end
	local key = tostring(player.UserId) .. "_" .. tostring(purchaseId)
	local okc = pcall(function() receiptStore:SetAsync(key, true) end)
	return okc == true
end
function DataManager.SelectCosmetic(player: Player, kind: string, cosmeticKey: string)
	local m = meta[player]; if not m then return end
	m.cosmetics[kind] = cosmeticKey
	DataManager.ApplyCosmetics(player)
	saveMeta(player)
end
function DataManager.SaveSettings(player: Player, s)
	local m = meta[player]
	if not (m and type(s) == "table") then return end
	m.settings = m.settings or {}
	for _, k in ipairs({ "master", "music", "sfx", "sensitivity", "brightness" }) do
		if type(s[k]) == "number" then
			local lo = (k == "brightness") and -1 or 0
			local hi = (k == "sensitivity") and 3 or 1
			m.settings[k] = math.clamp(s[k], lo, hi)
		end
	end
	saveMeta(player)
end

-- Switch the active save slot (separate progress). Saves the current slot first.
function DataManager.SelectSlot(player: Player, n: number)
	local m = meta[player]
	if not m or type(n) ~= "number" then return end
	n = math.floor(n)
	if n < 1 or n > m.slots or n == m.slot then return end
	local newSlot, ok = loadSlot(player, n)
	if not ok then return end  -- read failed: don't switch (avoid saving defaults over a real slot)
	saveSlot(player)          -- persist the slot we're leaving
	m.slot = n
	profiles[player] = newSlot
	saveMeta(player)
	DataManager.ApplyCosmetics(player)
end

-- Apply equipped cosmetics to attributes the client reads.
function DataManager.ApplyCosmetics(player: Player)
	local m = meta[player]; if not m then return end
	local Monetization = require(Shared:WaitForChild("MonetizationData"))
	local fl = Monetization.FlashlightSkins[m.cosmetics.flashlight or "default"]
	if fl then player:SetAttribute("FlashlightColor", fl.color) end
	player:SetAttribute("SuitSkin", m.cosmetics.suit or "default")
	player:SetAttribute("DeathAnim", m.cosmetics.death or "default")
end

function DataManager.Start()
	if started then return end
	started = true

	Players.PlayerAdded:Connect(load)
	for _, p in ipairs(Players:GetPlayers()) do load(p) end
	Players.PlayerRemoving:Connect(function(p)
		saveAll(p); meta[p] = nil; profiles[p] = nil; loadFailed[p] = nil
	end)
	game:BindToClose(function()
		for _, p in ipairs(Players:GetPlayers()) do saveAll(p) end
	end)

	Net.Event("SaveSettings").OnServerEvent:Connect(function(player, s)
		DataManager.SaveSettings(player, s)
	end)
	Net.Event("SelectSlot").OnServerEvent:Connect(function(player, n)
		DataManager.SelectSlot(player, n)
	end)

	Net.Func("GetGameState").OnServerInvoke = function(player)
		return combined(player) or {}
	end

	Net.Func("GetLeaderboards").OnServerInvoke = function(_player)
		return DataManager.GetLeaderboards()
	end

	if GameConfig.Debug then
		print("[HullBreach] DataManager started" .. (store and "" or " (no DataStore — in-memory)") .. ".")
	end
end

return DataManager
