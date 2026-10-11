--!strict
-- MonetizationManager.lua  →  ModuleScript in ServerScriptService/Server
-- =============================================================================
-- Phase 10: MarketplaceService integration — game passes, developer products,
-- cosmetics, and the Hint developer product. All IDs come from MonetizationData
-- (0 = not created yet, safely ignored). Ownership is mirrored into the player's
-- profile via DataManager. Nothing here affects core difficulty except the
-- opt-in Nightmare pass.
-- =============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local MarketplaceService = game:GetService("MarketplaceService")
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Monetization = require(Shared:WaitForChild("MonetizationData"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Net = require(Shared:WaitForChild("Net"))
local SectionData = require(Shared:WaitForChild("SectionData"))

local serverFolder = ServerScriptService:WaitForChild("Server")
local MonetizationManager = {}
local started = false

-- Survivors wall (Supporter Pass perk) --------------------------------------
local DataStoreService = game:GetService("DataStoreService")
local SURVIVORS_KEY = "SurvivorsWall_v1"
local survivors: {string} = {}          -- ordered, unique supporter names
local survivorSet: {[string]: boolean} = {}
local WALL_PAGE_SIZE = 8            -- supporter names shown per page
local wallPage = 0                  -- current page (0-based); auto-cycled
local function renderSurvivorsWall()
	local wall = CollectionService:GetTagged("SurvivorsWall")[1]
	local label = wall and wall:FindFirstChild("Names", true)
	if not (label and label:IsA("TextLabel")) then return end
	if #survivors == 0 then
		wallPage = 0
		label.Text = "No supporters yet.\nBe the first to keep the lights on."
		return
	end
	local pageCount = math.max(1, math.ceil(#survivors / WALL_PAGE_SIZE))
	if wallPage >= pageCount then wallPage = 0 end
	local first = wallPage * WALL_PAGE_SIZE
	local page = {}
	for i = first + 1, math.min(first + WALL_PAGE_SIZE, #survivors) do
		table.insert(page, survivors[i])
	end
	local text = table.concat(page, "\n")
	if pageCount > 1 then
		text ..= ("\n\n·  %d / %d  ·"):format(wallPage + 1, pageCount)
	end
	label.Text = text
end
local function addSurvivor(name: string)
	if not name or survivorSet[name] then return end
	survivorSet[name] = true
	table.insert(survivors, name)
	renderSurvivorsWall()
	-- persist (best-effort; DataStore is unavailable in Studio without API access)
	task.spawn(function()
		pcall(function()
			DataStoreService:GetDataStore(SURVIVORS_KEY):UpdateAsync("names", function(old)
				old = old or {}
				for _, n in ipairs(old) do if n == name then return old end end
				table.insert(old, name)
				return old
			end)
		end)
	end)
end
local function loadSurvivors()
	local ok, data = pcall(function()
		return DataStoreService:GetDataStore(SURVIVORS_KEY):GetAsync("names")
	end)
	if ok and type(data) == "table" then
		for _, n in ipairs(data) do
			if type(n) == "string" and not survivorSet[n] then
				survivorSet[n] = true; table.insert(survivors, n)
			end
		end
	end
end

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

-- Lookup helpers -------------------------------------------------------------
local function passById(id: number)
	for _, p in pairs(Monetization.Passes) do if p.id == id and id ~= 0 then return p end end
	return nil
end
local function productById(id: number)
	for _, p in pairs(Monetization.Products) do if p.id == id and id ~= 0 then return p end end
	for _, list in ipairs({ Monetization.FlashlightSkins, Monetization.SuitSkins, Monetization.DeathAnimations }) do
		for _, p in pairs(list) do if p.id == id and id ~= 0 then return p end end
	end
	return nil
end

-- Passes ---------------------------------------------------------------------
local function checkPasses(player: Player)
	local Data = getManager("DataManager")
	for _, pass in pairs(Monetization.Passes) do
		if pass.id ~= 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.id)
			end)
			if ok and owns and Data and Data.GrantPass then
				Data.GrantPass(player, pass.key)
				if pass.key == "supporter" then addSurvivor(player.Name) end
			end
		end
	end
	MonetizationManager.ApplyNightmare(player)
end

-- The Hint developer product: reveal where the NEXT captain's-log page is.
-- Highlights the world Journal part whose PageIndex is the lowest the player
-- hasn't collected yet (collecting a page Destroys its part, so uncollected
-- pages are exactly the Journal-tagged parts still in the world).
local function giveHint(player: Player)
	local Inventory = getManager("InventoryManager")
	local nextIdx = Inventory and Inventory.GetNextJournalIndex and Inventory.GetNextJournalIndex(player)
	if not nextIdx then
		notify(player, "You already hold every page of the captain's log. There is nothing left to find.")
		return
	end
	local target
	for _, inst in ipairs(CollectionService:GetTagged("Journal")) do
		if inst:IsA("BasePart") and inst:IsDescendantOf(Workspace) and inst:GetAttribute("PageIndex") == nextIdx then
			target = inst
			break
		end
	end
	if not target then
		notify(player, "The next page calls, but you cannot sense it from where you stand.")
		return
	end
	-- A bright, pulsing beacon at the page. Built as its own ANCHORED neon part (not a
	-- highlight on the tiny page mesh) so it reads from across the sub and can't be hidden
	-- or cut short by the water plane or props. The AlwaysOnTop Highlight + PointLight make
	-- it visible THROUGH water and walls, in or out of the flood, for the full duration.
	local DURATION = 15
	local pos = target:GetPivot().Position
	local beacon = Instance.new("Part")
	beacon.Name = "DD_HintBeacon"
	beacon.Shape = Enum.PartType.Ball
	beacon.Size = Vector3.new(1, 1, 1)
	beacon.Anchored = true; beacon.CanCollide = false; beacon.CanQuery = false; beacon.CastShadow = false
	beacon.Material = Enum.Material.Neon
	beacon.Color = Color3.fromRGB(240, 226, 180)
	beacon.Transparency = 0.1
	beacon.CFrame = CFrame.new(pos + Vector3.new(0, 1.2, 0))
	beacon.Parent = Workspace
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(245, 228, 175); light.Brightness = 4; light.Range = 30; light.Shadows = false
	light.Parent = beacon
	local hl = Instance.new("Highlight")
	hl.FillColor = Color3.fromRGB(240, 226, 180); hl.FillTransparency = 0.3
	hl.OutlineColor = Color3.fromRGB(255, 245, 210); hl.OutlineTransparency = 0
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop  -- seen through water, walls, the dark
	hl.Adornee = beacon; hl.Parent = beacon
	-- gentle pulse so it breathes instead of sitting flat
	task.spawn(function()
		local t0 = os.clock()
		while beacon.Parent and (os.clock() - t0) < DURATION do
			local k = (math.sin((os.clock() - t0) * 4) + 1) / 2
			light.Brightness = 2.5 + k * 3
			beacon.Transparency = 0.08 + k * 0.22
			hl.FillTransparency = 0.25 + k * 0.35
			task.wait(0.05)
		end
	end)
	game:GetService("Debris"):AddItem(beacon, DURATION)
	notify(player, ("Page %d of the captain's log glows through the dark. Follow the light."):format(nextIdx))
	-- Name the room the page is in, shown as a banner above the toolbar (complements
	-- the world beacon with a plain "which room" pointer).
	local secIdx = SectionData.SectionAtPosition(pos)
	local sec = SectionData.Sections[secIdx]
	Net.Event("HintDirection"):FireClient(player, (sec and sec.name) or "the boat")
end

-- Developer products: ProcessReceipt -----------------------------------------
local function processReceipt(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local Data = getManager("DataManager")

	-- De-dup: ProcessReceipt can fire more than once for the SAME purchase (retries /
	-- a slow first call). If we've already granted this exact receipt, ack it again
	-- WITHOUT re-granting (otherwise e.g. an Extra Save Slot double-counts).
	if Data and Data.WasReceiptProcessed and Data.WasReceiptProcessed(player, receiptInfo.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local product = productById(receiptInfo.ProductId)
	if product then
		if product.key == "hint" then
			giveHint(player)
		elseif product.key == "save_slot" then
			if Data and Data.AddSaveSlot then Data.AddSaveSlot(player) end
			notify(player, "An extra save slot is yours.")
		else
			-- a cosmetic bought as a product: grant + equip
			if Data and Data.GrantCosmetic then Data.GrantCosmetic(player, product.key) end
		end
	end

	-- Record this receipt as granted so any later retry hits the de-dup above.
	if Data and Data.MarkReceiptProcessed then
		Data.MarkReceiptProcessed(player, receiptInfo.PurchaseId)
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Purchase / cosmetic requests from the client -------------------------------
local function onPurchase(player: Player, kind: string, keyName: string)
	if kind == "pass" then
		local pass = Monetization.Passes[keyName]
		if pass and pass.id ~= 0 then
			MarketplaceService:PromptGamePassPurchase(player, pass.id)
		else
			notify(player, "That pass isn't available yet.")
		end
	elseif kind == "product" then
		local prod = Monetization.Products[keyName]
		if prod and prod.id ~= 0 then
			if keyName == "hint" then
				-- never charge for a Hint when there is no page left to point to
				local Inventory = getManager("InventoryManager")
				local nextIdx = Inventory and Inventory.GetNextJournalIndex and Inventory.GetNextJournalIndex(player)
				if not nextIdx then
					notify(player, "You already hold every page of the captain's log \u{2014} nothing to reveal.")
					return
				end
			end
			MarketplaceService:PromptProductPurchase(player, prod.id)
		else
			notify(player, "That product isn't available yet.")
		end
	elseif kind == "flashlight" or kind == "suit" or kind == "death" then
		local lists = { flashlight = Monetization.FlashlightSkins, suit = Monetization.SuitSkins, death = Monetization.DeathAnimations }
		local list = lists[kind]
		local item = list and list[keyName]
		if item and item.id ~= 0 and item.price > 0 then
			MarketplaceService:PromptProductPurchase(player, item.id)
		end
	end
end

local function onCosmeticSelect(player: Player, kind: string, keyName: string)
	local Data = getManager("DataManager")
	if not Data then return end
	local profile = Data.GetProfile and Data.GetProfile(player)
	-- free defaults are always selectable; otherwise must be owned
	local isDefault = (keyName == "default")
	if isDefault or (profile and profile.owned[keyName]) then
		Data.SelectCosmetic(player, kind, keyName)
		notify(player, "Equipped.")
	else
		notify(player, "You don't own that yet.")
	end
end

-- Developer Commentary: submit a run to a developer (Discord webhook) for a rating.
-- The webhook URL is a SERVER-ONLY Roblox Secret so it never replicates to clients.
-- Create it in Creator Hub -> your experience -> Secrets: key "dev_rating_webhook",
-- value = the full Discord webhook URL. (Also enable HTTP requests in Game Settings.)
local DEV_RATING_SECRET = "dev_rating_webhook"

local function postRating(body: string): boolean
	local okSecret, secret = pcall(function()
		return HttpService:GetSecret(DEV_RATING_SECRET)
	end)
	if not okSecret or secret == nil then
		return false
	end
	local okPost, resp = pcall(function()
		return HttpService:RequestAsync({
			Url = secret :: any,
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = body,
		})
	end)
	return okPost and resp ~= nil and (resp :: any).Success == true
end

local lastSubmit: {[Player]: number} = {}
local function onSubmitRun(player: Player, summary)
	local Data = getManager("DataManager")
	local profile = Data and Data.GetProfile and Data.GetProfile(player)
	if not (profile and profile.passes and profile.passes.commentary) then
		notify(player, "You need Developer Commentary to request a rating.")
		return
	end
	local now = os.clock()
	if lastSubmit[player] and now - lastSubmit[player] < 30 then
		notify(player, "You just sent a run — give them a moment.")
		return
	end
	lastSubmit[player] = now
	summary = (type(summary) == "table") and summary or {}
	local ending = (type(summary.ending) == "string") and string.sub(summary.ending, 1, 80) or "unknown"
	local outcome = (summary.category == "good") and "Win" or (summary.category == "bad") and "Loss" or "Unknown"
	local notes = (type(summary.notes) == "string") and string.sub(summary.notes, 1, 500) or ""
	local Inventory = getManager("InventoryManager")
	local journals = (Inventory and Inventory.GetJournalCount and Inventory.GetJournalCount(player)) or 0
	local lines = {
		"**Hull Breach — run submitted for rating**",
		("Player: %s (%d)"):format(player.Name, player.UserId),
		("Outcome: %s — %s"):format(outcome, ending),
		("Journal pages: %d/6"):format(journals),
	}
	if notes ~= "" then table.insert(lines, "Notes: " .. notes) end
	local body = HttpService:JSONEncode({ content = table.concat(lines, "\n") })
	if postRating(body) then
		notify(player, "Your run was sent to the developers for review. Thank you.")
	else
		lastSubmit[player] = nil   -- not configured / send failed; let them retry
		warn("[HullBreach] Dev rating not sent — secret '" .. DEV_RATING_SECRET .. "' missing or request failed.")
		notify(player, "Couldn't reach the developers just now — try again shortly.")
	end
end

-- Nightmare difficulty (opt-in, after completion) ----------------------------
function MonetizationManager.IsNightmare(player: Player): boolean
	local Data = getManager("DataManager")
	local profile = Data and Data.GetProfile and Data.GetProfile(player)
	return profile ~= nil and profile.passes.nightmare == true and profile.completed == true
end

-- Nightmare strips some consumables from the world (GDD "fewer items"). Solo-oriented.
local function pruneNightmareItems(player: Player)
	local remove = Monetization.Nightmare.removeConsumables
	if not remove then return end
	local byId = {}
	for _, p in ipairs(CollectionService:GetTagged("Pickup")) do
		if p:IsDescendantOf(Workspace) then
			local id = p:GetAttribute("ItemId")
			if id and remove[id] then byId[id] = byId[id] or {}; table.insert(byId[id], p) end
		end
	end
	for id, count in pairs(remove) do
		local list = byId[id] or {}
		for i = 1, math.min(count, #list) do list[i]:Destroy() end
	end
end

-- Apply the Nightmare difficulty overrides to the live managers.
function MonetizationManager.ApplyNightmare(player: Player)
	if not MonetizationManager.IsNightmare(player) then return end
	local n = Monetization.Nightmare
	local Creature = getManager("CreatureManager")
	if Creature and Creature.SetDifficulty then
		Creature.SetDifficulty(n.creatureSpeedMult, n.detectionMult)
	end
	local Oxygen = getManager("OxygenManager")
	if Oxygen and Oxygen.SetDifficulty then
		Oxygen.SetDifficulty(n.oxygenMult)
	end
	pruneNightmareItems(player)
	notify(player, "Extended Nightmare Mode is active. It is faster now. Hungrier.")
end

function MonetizationManager.Start()
	if started then return end
	started = true

	MarketplaceService.ProcessReceipt = processReceipt

	loadSurvivors()
	task.spawn(function()
		for _ = 1, 200 do
			if CollectionService:GetTagged("SurvivorsWall")[1] then break end
			task.wait(0.1)
		end
		renderSurvivorsWall()
		-- auto-cycle the wall through pages of names (first-person friendly; no clicking a wall)
		while true do
			task.wait(6)
			if #survivors > WALL_PAGE_SIZE then
				wallPage += 1
				renderSurvivorsWall()
			end
		end
	end)

	Players.PlayerAdded:Connect(function(p)
		task.defer(checkPasses, p)
	end)
	for _, p in ipairs(Players:GetPlayers()) do task.defer(checkPasses, p) end

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then return end
		local pass = passById(passId)
		local Data = getManager("DataManager")
		if pass and Data and Data.GrantPass then
			Data.GrantPass(player, pass.key)
			notify(player, "Thank you — " .. pass.name .. " unlocked.")
			if pass.key == "supporter" then addSurvivor(player.Name) end
		end
	end)

	Net.Event("Purchase").OnServerEvent:Connect(function(player, kind, keyName)
		if type(kind) == "string" and type(keyName) == "string" then
			onPurchase(player, kind, keyName)
		end
	end)
	Net.Event("CosmeticSelect").OnServerEvent:Connect(function(player, kind, keyName)
		if type(kind) == "string" and type(keyName) == "string" then
			onCosmeticSelect(player, kind, keyName)
		end
	end)
	Net.Event("SubmitRun").OnServerEvent:Connect(function(player, s) onSubmitRun(player, s) end)

	if GameConfig.Debug then
		print("[HullBreach] MonetizationManager started.")
	end
end

return MonetizationManager
