--!strict
-- InventoryManager.lua  →  ModuleScript in ServerScriptService/Server
-- =============================================================================
-- Phase 6: the fixed 4-slot inventory. Slots are intentional pressure — never
-- expand them. Owns item pickups, journal collection (no slot), and item use.
-- Registers pickup/journal/captain_door/safe handlers with InteractionManager.
--
-- API used by other managers:
--   HasItem(player, id) / CountItem(player, id)
--   AddItem(player, id) -> bool        RemoveItem(player, id) -> bool
--   GetJournalCount(player) -> number  (secret endings need all 6)
-- =============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemData = require(Shared:WaitForChild("ItemData"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Net = require(Shared:WaitForChild("Net"))

local serverFolder = ServerScriptService:WaitForChild("Server")

local InventoryManager = {}

local inv: {[Player]: {any}} = {}        -- inv[player][slot] = {id=...} | nil
local journals: {[Player]: {[number]: boolean}} = {}
local started = false

local function getManager(name: string)
	local mod = serverFolder:FindFirstChild(name)
	if mod and mod:IsA("ModuleScript") then
		local ok, m = pcall(require, mod)
		if ok then return m end
	end
	return nil
end

local function notify(player: Player, text: string)
	Net.Event("Notify"):FireClient(player, text)
end

local function ensure(player: Player)
	if not inv[player] then inv[player] = {} end
	if not journals[player] then journals[player] = {} end
end

-- Sync ----------------------------------------------------------------------
local function pushInventory(player: Player)
	ensure(player)
	local slots = {}
	for i = 1, ItemData.MAX_SLOTS do
		local entry = inv[player][i]
		slots[i] = entry and { id = entry.id, name = ItemData.Items[entry.id] and ItemData.Items[entry.id].name or entry.id } or false
	end
	Net.Event("InventoryUpdate"):FireClient(player, slots)
end

local function pushJournal(player: Player)
	ensure(player)
	local count = 0
	local collected = {}
	for idx, has in pairs(journals[player]) do
		if has then count += 1; collected[idx] = true end
	end
	-- expose "any pages left?" to the client so the in-run Hint buy can grey out
	player:SetAttribute("JournalRemaining", #ItemData.JournalPages - count)
	Net.Event("JournalUpdate"):FireClient(player, { count = count, collected = collected })
end

-- Queries -------------------------------------------------------------------
function InventoryManager.CountItem(player: Player, id: string): number
	ensure(player)
	local n = 0
	for i = 1, ItemData.MAX_SLOTS do
		local e = inv[player][i]
		if e and e.id == id then n += 1 end
	end
	return n
end

function InventoryManager.HasItem(player: Player, id: string): boolean
	return InventoryManager.CountItem(player, id) > 0
end

function InventoryManager.FreeSlots(player: Player): number
	ensure(player)
	local n = 0
	for i = 1, ItemData.MAX_SLOTS do
		if not inv[player][i] then n += 1 end
	end
	return n
end

-- Mutations -----------------------------------------------------------------
function InventoryManager.AddItem(player: Player, id: string): boolean
	ensure(player)
	for i = 1, ItemData.MAX_SLOTS do
		if not inv[player][i] then
			inv[player][i] = { id = id }
			pushInventory(player)
			return true
		end
	end
	return false -- full
end

function InventoryManager.RemoveItem(player: Player, id: string): boolean
	ensure(player)
	for i = 1, ItemData.MAX_SLOTS do
		local e = inv[player][i]
		if e and e.id == id then
			inv[player][i] = nil
			pushInventory(player)
			return true
		end
	end
	return false
end

function InventoryManager.GetJournalCount(player: Player): number
	ensure(player)
	local n = 0
	for _, has in pairs(journals[player]) do if has then n += 1 end end
	return n
end

-- Lowest-numbered captain's-log page the player has NOT collected yet, in
-- narrative order (nil once all pages are found). Drives the Hint product.
function InventoryManager.GetNextJournalIndex(player: Player): number?
	ensure(player)
	for idx = 1, #ItemData.JournalPages do
		if not journals[player][idx] then return idx end
	end
	return nil
end

-- Reset a player's inventory + journals for a fresh run.
function InventoryManager.ResetPlayer(player: Player)
	inv[player] = {}
	journals[player] = {}
	pushInventory(player)
	pushJournal(player)
end

-- Item use ------------------------------------------------------------------
local function useSlot(player: Player, slot: number, action: string)
	ensure(player)
	local entry = inv[player][slot]
	if not entry then return end
	local def = ItemData.Items[entry.id]
	if not def then return end

	if action == "drop" then
		-- spawn a real, re-collectable pickup where the player is standing (was a
		-- bug: the item just vanished). Reuses the same model + tag/prompt that
		-- world pickups use, so InteractionManager's pickup handler picks it back up.
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local ItemModels = getManager("ItemModels")
		if hrp and ItemModels and ItemModels.BuildPickup then
			local dropCF = hrp.CFrame * CFrame.new(0, -1.5, -2) -- at their feet, just ahead
			local root = ItemModels.BuildPickup(entry.id, dropCF)
			root.Name = "Pickup_" .. entry.id
			root:SetAttribute("ItemId", entry.id)
			CollectionService:AddTag(root, "Pickup")
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Take"
			prompt.ObjectText = def.name
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.MaxActivationDistance = GameConfig.InteractDistance or 10
			prompt.RequiresLineOfSight = false
			prompt.Parent = root
			root.Parent = Workspace
		end
		inv[player][slot] = nil
		notify(player, "You drop the " .. def.name .. ".")
		pushInventory(player)
		return
	end

	-- "use"
	if entry.id == "battery" then
		local Battery = getManager("BatteryManager")
		if Battery and Battery.AddCharge then Battery.AddCharge(player, def.charge or 50) end
		inv[player][slot] = nil
		notify(player, "The flashlight brightens. Battery installed.")
	elseif entry.id == "oxygen_canister" then
		local Oxygen = getManager("OxygenManager")
		if Oxygen and Oxygen.AddOxygen then Oxygen.AddOxygen(player, def.oxygenBonus or 30) end
		inv[player][slot] = nil
		notify(player, "You crack the oxygen canister. Easier to breathe — for now.")
	elseif entry.id == "glow_stick" then
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local g = Instance.new("Part")
			g.Shape = Enum.PartType.Cylinder
			g.Size = Vector3.new(0.4, 1.5, 0.4)
			g.Color = Color3.fromRGB(120, 255, 140)
			g.Material = Enum.Material.Neon
			g.Anchored = true
			g.CanCollide = false
			g.CFrame = CFrame.new(hrp.Position - Vector3.new(0, 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(140, 255, 160)
			light.Range = 22
			light.Brightness = 2
			light.Parent = g
			g.Parent = workspace
			Debris:AddItem(g, def.duration or 180)
		end
		inv[player][slot] = nil
		notify(player, "You snap the glow stick and drop it. Green light pools on the deck.")
	else
		notify(player, "You can't use that here.")
		return
	end
	pushInventory(player)
end

-- Interaction handlers ------------------------------------------------------
local function onPickup(player: Player, part: Instance)
	local id = part:GetAttribute("ItemId")
	if not id then return end

	if id == "flashlight" then
		player:SetAttribute("HasFlashlight", true)
		local Battery = getManager("BatteryManager")
		if Battery and Battery.GrantFlashlight then Battery.GrantFlashlight(player) end
		notify(player, "You take the flashlight. Press F to switch it on.")
		part:Destroy()
		return
	end

	if InventoryManager.FreeSlots(player) <= 0 then
		notify(player, "Your hands are full. Something has to go.")
		return
	end
	if InventoryManager.AddItem(player, id) then
		local def = ItemData.Items[id]
		notify(player, "You take the " .. (def and def.name or id) .. ".")
		part:Destroy()
	end
end

local function onJournal(player: Player, part: Instance)
	local idx = part:GetAttribute("PageIndex")
	if not idx then return end
	ensure(player)
	local data = ItemData.JournalPages[idx]
	local firstRead = not journals[player][idx]
	if data then
		-- the full page shown in the reader panel, with the per-run ballast clue
		-- (EndingManager.RandomizeRun) appended so the randomized surface-manually
		-- valve order can be pieced together across the pages.
		local text = data.text
		local Ending = getManager("EndingManager")
		local clue = Ending and Ending.GetBallastClue and Ending.GetBallastClue(idx)
		if clue then text = text .. "\n\n" .. clue end
		notify(player, firstRead and "You find a page of the captain's log." or "You read the page again.")
		Net.Event("JournalRead"):FireClient(player, { title = data.title, text = text, index = idx })
	end
	-- Collect once (counts toward the 6 pages), but DON'T destroy the page: it stays
	-- in the world so the player can return and re-read the ballast-code clue.
	if firstRead then
		journals[player][idx] = true
		pushJournal(player)
	end
end

local function onCaptainDoor(player: Player, part: Instance)
	if not part:GetAttribute("Locked") then
		notify(player, "The door is already open.")
		return
	end
	if InventoryManager.HasItem(player, "keycard") then
		InventoryManager.RemoveItem(player, "keycard") -- single use
		part:SetAttribute("Locked", false)
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.Transparency = 0.7
		end
		notify(player, "The keycard clicks. The captain's door swings open.")
	else
		notify(player, "A keycard reader blinks red. Locked.")
	end
end

local function onSafe(player: Player, part: Instance)
	-- light puzzle: clues are environmental; accept interaction to reveal lore
	if part:GetAttribute("Locked") == false then
		notify(player, "The safe is already open.")
		return
	end
	part:SetAttribute("Locked", false)
	notify(player, "The combination from the photographs works. Inside: a worn wedding ring and a final letter.")
end

function InventoryManager.Start()
	if started then return end
	started = true

	local function init(p: Player)
		ensure(p)
		pushInventory(p)
		pushJournal(p)
	end
	Players.PlayerAdded:Connect(function(p)
		init(p)
		p.CharacterAdded:Connect(function() pushInventory(p) end)
	end)
	for _, p in ipairs(Players:GetPlayers()) do init(p) end
	Players.PlayerRemoving:Connect(function(p)
		inv[p] = nil; journals[p] = nil
	end)

	-- client use/drop requests
	Net.Event("UseItem").OnServerEvent:Connect(function(player, slot, action)
		if type(slot) == "number" and type(action) == "string" then
			useSlot(player, slot, action)
		end
	end)

	-- register interaction handlers (override fallbacks)
	local Interaction = getManager("InteractionManager")
	if Interaction and Interaction.Register then
		Interaction.Register("pickup", onPickup)
		Interaction.Register("journal", onJournal)
		Interaction.Register("captain_door", onCaptainDoor)
		Interaction.Register("safe", onSafe)
	end

	if GameConfig.Debug then
		print("[HullBreach] InventoryManager started.")
	end
end

return InventoryManager
