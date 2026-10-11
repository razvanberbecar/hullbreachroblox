--!strict
-- EndingManager.lua  →  ModuleScript in ServerScriptService/Server
-- =============================================================================
-- Phase 7: evaluates and triggers all 9 endings, plays the cutscene (client),
-- records discovery (DataManager, Phase 10), and soft-resets the run.
--
--   Good:   escape_pod, sos_signal, surface_manually
--   Bad:    drowned, taken, sealed_in (Oxygen/Creature) + the_deep (hull breach)
--   Secret: the_truth, hubris                (6 journals + exterior cargo choice)
--
-- Hubris rule: if the player TOOK the cargo (and has all 6 pages), any good
-- ending they then complete is upgraded to the secret "hubris" ending.
--
-- CO-OP (2 players, shared): the run is a single shared lifecycle. It begins only
-- once every present player has pressed Play (ready-gate), and it ends for
-- EVERYONE at once (shared fate on any death, shared win on any good ending). Key
-- items are pooled across the crew (escape pod + the Truth gate count both
-- inventories together). A solo server is simply the one-player case of all this.
-- =============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EndingData = require(Shared:WaitForChild("EndingData"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Net = require(Shared:WaitForChild("Net"))

local serverFolder = ServerScriptService:WaitForChild("Server")

local EndingManager = {}

local flags: {[Player]: {[string]: any}} = {}
local ended: {[Player]: boolean} = {}
local sosThread: thread? = nil            -- co-op: ONE shared SOS survival countdown for the whole server
local ballastProgress: {[Player]: number} = {}
local ballastActive: {[Player]: boolean} = {}
local lastReset: {[Player]: number} = {}  -- (legacy per-player field; restart debounce is now global, see lastGlobalReset)
local runStart: {[Player]: number} = {}   -- os.clock() when this player's run began (leaderboard timer)
local activeBallast = table.clone(EndingData.BALLAST_SEQUENCE)  -- randomized per run (RandomizeRun)
local ballastClues: {[number]: string} = {}                    -- [journalPageIndex] = diegetic clue line
local started = false

-- Co-op shared-run state -----------------------------------------------------
local runActive = false                       -- the shared run is live (world un-paused)
local runEnded = false                        -- an ending has fired; ignore further triggers until reset
local readyPlayers: {[Player]: boolean} = {}  -- who has pressed Play and is waiting in the lobby
local expectedPlayers: number? = nil          -- Half 2 (co-op server) sets this to 2 so we wait for the partner
local lastGlobalReset = -math.huge            -- debounce: one shared reset even if both players click at once (first reset always allowed)

local GOOD = {} for _, id in ipairs({"escape_pod","sos_signal","surface_manually"}) do GOOD[id] = true end

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

local function ensure(p: Player)
	if not flags[p] then flags[p] = { cargoTaken = false } end
end

-- Co-op combined tallies: key items are shared objectives, so the escape pod and
-- the Truth gate count BOTH players' inventories together (split the carry). In a
-- solo server these just sum over the one player, i.e. the original behaviour.
local function combinedItemCount(itemId: string): number
	local Inventory = getManager("InventoryManager")
	if not (Inventory and Inventory.CountItem) then return 0 end
	local total = 0
	for _, p in ipairs(Players:GetPlayers()) do
		total += (Inventory.CountItem(p, itemId) or 0)
	end
	return total
end

local function combinedJournalCount(): number
	local Inventory = getManager("InventoryManager")
	if not (Inventory and Inventory.GetJournalCount) then return 0 end
	local total = 0
	for _, p in ipairs(Players:GetPlayers()) do
		total += (Inventory.GetJournalCount(p) or 0)
	end
	return total
end

local function anyCargoTaken(): boolean
	for _, p in ipairs(Players:GetPlayers()) do
		if flags[p] and flags[p].cargoTaken then return true end
	end
	return false
end

-- Half 2 hook: a co-op reserved server calls this with 2 so the ready-gate waits
-- for the partner to finish teleporting in before the run can start.
function EndingManager.SetExpectedPlayers(n: number?)
	expectedPlayers = n
end

-- ---------------------------------------------------------------------------
-- Trigger an ending  (co-op: shared — ends the run for EVERYONE at once)
-- ---------------------------------------------------------------------------
function EndingManager.Trigger(triggerPlayer: Player, endingId: string)
	if runEnded then return end

	-- hubris upgrade: a greedy escape with the cargo + the full truth. Team-wide —
	-- if either player took the cargo and the crew holds all 6 pages between them.
	if GOOD[endingId] and anyCargoTaken() and combinedJournalCount() >= 6 then
		endingId = "hubris"
	end

	local data = EndingData.Endings[endingId]
	if not data then return end
	runEnded = true
	runActive = false

	-- cancel the shared SOS survival (and hide the client rescue countdown)
	if sosThread then
		task.cancel(sosThread)
		sosThread = nil
	end
	Net.Event("SurvivalUpdate"):FireAllClients(0)

	-- record discovery + leaderboard result for EVERY player in the server: the
	-- outcome is shared, so both get the ending in their log + a run result
	-- (elapsed run time -> fastest-escape / longest-survival / most-endings boards).
	local Data = getManager("DataManager")
	for _, p in ipairs(Players:GetPlayers()) do
		ended[p] = true
		if Data and Data.RecordEnding then Data.RecordEnding(p, endingId) end
		local elapsed = runStart[p] and (os.clock() - runStart[p]) or nil
		if Data and Data.RecordRunResult then Data.RecordRunResult(p, endingId, elapsed) end
	end

	-- cutscene for everyone
	Net.Event("EndingTrigger"):FireAllClients({
		id = endingId, name = data.name, title = data.title,
		blurb = data.blurb, category = data.category,
	})

	if GameConfig.Debug then
		print(("[HullBreach] Shared ending (%s triggered): %s"):format(
			triggerPlayer and triggerPlayer.Name or "?", endingId))
	end

	-- NOTE: no auto-respawn. The run stays ended (screen held by the cutscene) until
	-- a player clicks Try Again / Main Menu, which fires RequestRestart / ReturnToMenu.
end

-- ---------------------------------------------------------------------------
-- Good-ending interaction handlers
-- ---------------------------------------------------------------------------
local function onEscapePod(player: Player)
	local count = combinedItemCount("pod_component")   -- co-op: components pooled across the crew
	if count >= 3 then
		notify(player, "You seat the final component. The pod hisses, seals, and blows its bolts.")
		task.wait(1.5)
		EndingManager.Trigger(player, "escape_pod")
	else
		notify(player, ("The escape pod needs %d more component(s)."):format(3 - count))
	end
end

local function onRadio(player: Player, part: Instance)
	if part:GetAttribute("Locked") then
		notify(player, "The radio is dead. It needs main power.")
		return
	end
	local Power = getManager("PowerManager")
	if not (Power and Power.State and Power.State.mainPower) then
		notify(player, "No carrier signal. Restore main power first.")
		return
	end
	if sosThread then
		notify(player, "Your distress call is already broadcasting. Stay alive.")
		return
	end
	notify(player, "You broadcast the SOS. Now survive until they reach you — 2 minutes.")
	local remaining = EndingData.SOS_SURVIVE_SECONDS
	sosThread = task.spawn(function()
		while remaining > 0 do
			Net.Event("SurvivalUpdate"):FireAllClients(remaining)   -- the whole crew sees the countdown
			task.wait(1)
			remaining -= 1
		end
		sosThread = nil
		EndingManager.Trigger(player, "sos_signal")
	end)
end

local function onExterior(player: Player, part: Instance, prompt: ProximityPrompt)
	ensure(player)
	local pages = combinedJournalCount()   -- co-op: the crew's pages count together
	if pages < 6 then
		notify(player, "There is something here, sealed away — but you do not yet understand it.")
		return
	end
	if prompt and prompt.Name == "TakePrompt" then
		flags[player].cargoTaken = true
		notify(player, "You take the cargo — cold, heavy, wrong. Now get out: launch the escape pod, send the SOS, or surface the boat.")
	else
		-- return it: the secret good ending
		local Creature = getManager("CreatureManager")
		if Creature and Creature.SetPeaceful then Creature.SetPeaceful() end
		notify(player, "You return what was taken. The hunting stops. The water seems to still.")
		task.wait(2)
		EndingManager.Trigger(player, "the_truth")
	end
end

-- ---------------------------------------------------------------------------
-- Swim out through the hull breach (a grim death — no surviving crush depth)
-- ---------------------------------------------------------------------------
local function onBreach(player: Player)
	if runEnded then return end
	notify(player, "You squeeze out through the torn hull into the black water...")
	task.wait(2)
	EndingManager.Trigger(player, "the_deep")
end

-- ---------------------------------------------------------------------------
-- Ballast valve-sequence puzzle (Surface Manually)
-- ---------------------------------------------------------------------------
function EndingManager.BeginBallastPuzzle(player: Player, _part: Instance)
	ballastProgress[player] = 0
	ballastActive[player] = true
	Net.Event("BallastPuzzle"):FireClient(player, {
		open = true, length = #activeBallast,
	})
	notify(player, "The ballast valves must be opened in the correct order.")
end

local function onBallastInput(player: Player, value: number)
	if not ballastActive[player] then return end  -- only count input while the puzzle is open
	local seq = activeBallast
	local prog = (ballastProgress[player] or 0) + 1
	if GameConfig.Debug then
		print("[HullBreach] Ballast input " .. value .. " at step " .. prog
			.. " (need " .. tostring(seq[prog]) .. ") for " .. player.Name)
	end
	if seq[prog] == value then
		ballastProgress[player] = prog
		if prog >= #seq then
			ballastActive[player] = false
			Net.Event("BallastPuzzle"):FireClient(player, { open = false })
			notify(player, "The tanks blow. The boat groans and begins to rise.")
			task.wait(1.5)
			EndingManager.Trigger(player, "surface_manually")
		end
	else
		ballastProgress[player] = 0
		Net.Event("BallastPuzzle"):FireClient(player, { open = true, reset = true, length = #seq })
		notify(player, "A valve shrieks — wrong order. The sequence resets.")
	end
end

-- ---------------------------------------------------------------------------
-- World snapshot / restore  (powers the true "Try Again" / Reset fresh run)
-- ---------------------------------------------------------------------------
-- Snapshotted once at boot (Start), restored on every ResetRun: respawns every
-- collected Pickup/Journal and re-closes/un-seals the bulkhead doors + re-locks
-- the captain door & safe. Kept in THIS existing module on purpose — a freshly
-- created ModuleScript that isn't saved can be dropped by Team Create, which
-- silently broke item respawn (a collected flashlight/item stayed gone after a death).
local SNAP_FOLDER = "__RunResetTemplates"
local itemTemplates: { { template: Instance, parent: Instance } } = {}
local doorStates: { [BasePart]: any } = {}
local lockStates: { [BasePart]: any } = {}
local snapped = false

local function snapshotWorld()
	if snapped then return end
	snapped = true
	local existing = ServerStorage:FindFirstChild(SNAP_FOLDER)
	if existing then existing:Destroy() end
	local folder = Instance.new("Folder")
	folder.Name = SNAP_FOLDER
	folder.Parent = ServerStorage
	-- pristine clones of every collectible (tags + attributes + child prompts are
	-- preserved by Clone(); InteractionManager re-binds the prompt via its
	-- Workspace.DescendantAdded hook when a fresh copy is parented back)
	for _, tagName in ipairs({ "Pickup", "Journal" }) do
		for _, inst in ipairs(CollectionService:GetTagged(tagName)) do
			if inst:IsDescendantOf(Workspace) and inst.Parent then
				local tpl = inst:Clone()
				tpl.Parent = folder
				table.insert(itemTemplates, { template = tpl, parent = inst.Parent })
			end
		end
	end
	for _, door in ipairs(CollectionService:GetTagged("BulkheadDoor")) do
		if door:IsA("BasePart") then
			local dp = door:FindFirstChild("DoorPrompt")
			local sp = door:FindFirstChild("SealPrompt")
			doorStates[door] = {
				open = door:GetAttribute("Open"), sealed = door:GetAttribute("Sealed"),
				canCollide = door.CanCollide, transparency = door.Transparency, color = door.Color,
				doorEnabled = dp and (dp :: ProximityPrompt).Enabled,
				doorAction = dp and (dp :: ProximityPrompt).ActionText,
				sealEnabled = sp and (sp :: ProximityPrompt).Enabled,
			}
		end
	end
	for _, part in ipairs(CollectionService:GetTagged("Interactable")) do
		if part:IsA("BasePart") then
			local kind = part:GetAttribute("Kind")
			if kind == "captain_door" or kind == "safe" then
				lockStates[part] = {
					locked = part:GetAttribute("Locked"),
					canCollide = part.CanCollide, transparency = part.Transparency,
				}
			end
		end
	end
	if GameConfig.Debug then
		print(("[HullBreach] World snapshot taken: %d collectibles"):format(#itemTemplates))
	end
end

local function restoreWorld()
	if not snapped then return end
	-- collectibles: clear all current (uncollected + dropped — both tagged), then
	-- re-clone the pristine boot set into their original parents.
	for _, tagName in ipairs({ "Pickup", "Journal" }) do
		for _, inst in ipairs(CollectionService:GetTagged(tagName)) do
			if inst:IsDescendantOf(Workspace) then inst:Destroy() end
		end
	end
	for _, rec in ipairs(itemTemplates) do
		if rec.parent and rec.parent.Parent then
			rec.template:Clone().Parent = rec.parent
		end
	end
	-- doors back to their boot state
	for door, st in pairs(doorStates) do
		if door and door.Parent and door:IsA("BasePart") then
			door:SetAttribute("Open", st.open)
			door:SetAttribute("Sealed", st.sealed)
			door.CanCollide = st.canCollide
			door.Transparency = st.transparency
			door.Color = st.color
			local dp = door:FindFirstChild("DoorPrompt")
			local sp = door:FindFirstChild("SealPrompt")
			if dp and dp:IsA("ProximityPrompt") then
				dp.Enabled = st.doorEnabled ~= false
				dp.ActionText = st.doorAction or "Open"
			end
			if sp and sp:IsA("ProximityPrompt") then
				sp.Enabled = st.sealEnabled ~= false
			end
		end
	end
	-- captain door + safe re-locked
	for part, st in pairs(lockStates) do
		if part and part.Parent and part:IsA("BasePart") then
			part:SetAttribute("Locked", st.locked)
			part.CanCollide = st.canCollide
			part.Transparency = st.transparency
		end
	end
end

-- ---------------------------------------------------------------------------
-- Run randomization  ("same sub, different nightmare each time")
-- ---------------------------------------------------------------------------
-- Runs once at boot (first run of the server) and again on every ResetRun. The
-- world is shared, so a reset re-rolls the layout for everyone in the server
-- (consistent with restoreWorld, which already respawns the shared collectibles).
local FIXED_ITEMS = { flashlight = true, keycard = true, fuse = true }

-- Diegetic ballast clues, one per valve position, seeded onto journal pages 1-5.
-- %d is filled with the valve number that belongs in that position this run.
local BALLAST_CLUES = {
	"A grease-pencil scrawl survives in the page's margin: \"To surface her by hand — crack valve %d first.\"",
	"Lower down, in the same hand: \"...then the number %d valve.\"",
	"\"...third, always the %d.\"",
	"\"...fourth, valve %d.\"",
	"\"...and last of all, valve %d. Open them in any other order and she broaches. Never any other order.\"",
}

function EndingManager.GetBallastClue(pageIndex: number): string?
	return ballastClues[pageIndex]
end

-- Permute the pivots of a set of instances among themselves. Every target is an
-- existing valid spot, so a page can't end up floating and no route soft-locks.
local function shufflePivots(insts: {PVInstance})
	local n = #insts
	if n < 2 then return end
	local pivots = {}
	for i, inst in ipairs(insts) do pivots[i] = inst:GetPivot() end
	for i = n, 2, -1 do
		local j = math.random(i)
		pivots[i], pivots[j] = pivots[j], pivots[i]
	end
	for i, inst in ipairs(insts) do
		pcall(function() inst:PivotTo(pivots[i]) end)
	end
end

local function randomizeRun()
	-- 1. Items + journals: shuffle positions within each pool. Flashlight stays at
	-- its fixed spot; keycard->fuse gate stays intact.
	local pickups = {}
	for _, p in ipairs(CollectionService:GetTagged("Pickup")) do
		if p:IsDescendantOf(Workspace) and not FIXED_ITEMS[p:GetAttribute("ItemId")] then
			table.insert(pickups, p)
		end
	end
	shufflePivots(pickups)
	local journals = {}
	for _, j in ipairs(CollectionService:GetTagged("Journal")) do
		if j:IsDescendantOf(Workspace) then table.insert(journals, j) end
	end
	shufflePivots(journals)

	-- 2. Creature start: a hull section it may enter, never the spawn room (1).
	local starts = {3, 4, 5, 6, 8, 9}
	local Creature = getManager("CreatureManager")
	if Creature and Creature.SetStartSection then
		Creature.SetStartSection(starts[math.random(#starts)])
	end

	-- 3. Breach order: bounded random flood-rate multiplier per section; the spawn
	-- room is never accelerated so the player isn't drowned on wake.
	local Flood = getManager("FloodManager")
	if Flood and Flood.SetRateMultipliers then
		local mults = {}
		for s = 1, 9 do mults[s] = 0.6 + math.random() * 1.9 end  -- 0.6x .. 2.5x
		mults[1] = math.min(mults[1], 1)
		Flood.SetRateMultipliers(mults)
	end

	-- 4. Ballast valve order: shuffle 1..5 and rebuild the journal-page clues.
	local seq = {1, 2, 3, 4, 5}
	for i = #seq, 2, -1 do
		local j = math.random(i)
		seq[i], seq[j] = seq[j], seq[i]
	end
	activeBallast = seq
	ballastClues = {}
	for pos = 1, #seq do
		if BALLAST_CLUES[pos] then ballastClues[pos] = string.format(BALLAST_CLUES[pos], seq[pos]) end
	end

	if GameConfig.Debug then
		print(("[HullBreach] RandomizeRun: %d items + %d journals shuffled; creature start set; ballast %s"):format(#pickups, #journals, table.concat(seq, "-")))
	end
end

-- ---------------------------------------------------------------------------
-- Co-op ready-gate: the shared run stays inert until everyone has pressed Play
-- ---------------------------------------------------------------------------
-- Flood / oxygen / creature all already idle while a player's InMenu attribute is
-- true, so beginRun just flips InMenu=false for the whole crew at once — the world
-- un-pauses only when every present player is ready.
local function requiredCount(): number
	if expectedPlayers then return math.max(expectedPlayers, 1) end
	return math.max(#Players:GetPlayers(), 1)
end

local function allReady(): boolean
	local players = Players:GetPlayers()
	if #players == 0 or #players < requiredCount() then return false end
	for _, p in ipairs(players) do
		if not readyPlayers[p] then return false end
	end
	return true
end

local function beginRun()
	if runActive then return end
	runActive = true
	runEnded = false
	for _, p in ipairs(Players:GetPlayers()) do
		p:SetAttribute("InMenu", false)   -- un-pauses flood / oxygen / creature for this player
		runStart[p] = os.clock()          -- start the leaderboard run timer
	end
	Net.Event("RunStarted"):FireAllClients()
	if GameConfig.Debug then print("[HullBreach] Shared run started.") end
end

-- Public re-check hook (MatchmakingManager): after the expected-player count changes
-- (e.g. the co-op solo-fallback drops it to 1, or a partner leaves), start the run if
-- everyone currently present has already readied and is waiting in the lobby.
function EndingManager.TryStart()
	if not runActive and not runEnded and allReady() then
		beginRun()
	end
end

-- ---------------------------------------------------------------------------
-- Soft reset to a fresh run  (co-op: ONE shared reset for the whole server)
-- ---------------------------------------------------------------------------
-- triggerPlayer is only for logging; the reset always rebuilds the shared world
-- and resets EVERY player. returnToMenu=true drops the crew back to the main menu
-- (Main Menu button); false begins a fresh run immediately (Try Again).
function EndingManager.ResetRun(triggerPlayer: Player?, returnToMenu: boolean?)
	-- Debounced so two players clicking Try Again / Main Menu at the same instant
	-- can't rebuild the shared world twice.
	if os.clock() - lastGlobalReset < 2 then return end
	lastGlobalReset = os.clock()

	runEnded = false
	runActive = false
	table.clear(readyPlayers)

	-- Run each step guarded so a single failure can never strand a player mid-reset
	-- (e.g. still holding their old inventory). Logged in Debug.
	local function guard(label: string, fn: () -> ())
		local ok, err = pcall(fn)
		if not ok and GameConfig.Debug then
			warn(("[HullBreach] ResetRun '%s' failed: %s"):format(label, tostring(err)))
		end
	end

	-- Shared WORLD (once): respawn every collected item + journal, re-close/un-seal
	-- the bulkhead doors, re-lock the captain door + safe, then reset the sims.
	guard("RestoreWorld", restoreWorld)
	for _, name in ipairs({ "FloodManager", "PowerManager", "CreatureManager" }) do
		guard(name, function()
			local m = getManager(name)
			if m and m.Reset then m.Reset() end
		end)
	end

	-- Per-player: inventory + journals, flashlight/battery, oxygen — for EVERYONE.
	for _, player in ipairs(Players:GetPlayers()) do
		ended[player] = nil
		flags[player] = { cargoTaken = false }
		ballastProgress[player] = nil
		ballastActive[player] = nil
		guard("InventoryManager", function()
			local Inventory = getManager("InventoryManager")
			if Inventory and Inventory.ResetPlayer then Inventory.ResetPlayer(player) end
		end)
		guard("BatteryManager", function()
			local Battery = getManager("BatteryManager")
			if Battery and Battery.ResetPlayer then Battery.ResetPlayer(player) end
		end)
		guard("OxygenManager", function()
			local Oxygen = getManager("OxygenManager")
			if Oxygen and Oxygen.ResetPlayer then Oxygen.ResetPlayer(player) end
		end)
		guard("Nightmare", function()
			local Mon = getManager("MonetizationManager")
			if Mon and Mon.ApplyNightmare then Mon.ApplyNightmare(player) end  -- re-apply difficulty + fewer-items
		end)
		-- Clear transient per-player attributes the run may have set.
		player:SetAttribute("HasFlashlight", false)
		player:SetAttribute("Hiding", false)
		player:LoadCharacter()
	end

	-- Clear any lingering SOS rescue countdown for the whole server.
	guard("SurvivalClear", function()
		if sosThread then task.cancel(sosThread); sosThread = nil end
		Net.Event("SurvivalUpdate"):FireAllClients(0)
	end)

	-- Re-roll the shared world layout for the fresh run (runs after restoreWorld +
	-- the manager resets above, so it overrides their pristine positions/spawn).
	guard("RandomizeRun", randomizeRun)

	-- Tell every client to drop the ending screen (toMenu decides where they land).
	Net.Event("RunReset"):FireAllClients({ toMenu = returnToMenu == true })

	if returnToMenu then
		for _, player in ipairs(Players:GetPlayers()) do
			player:SetAttribute("InMenu", true)   -- MenuUI re-enters the main menu
		end
	else
		-- Try Again: begin a fresh shared run immediately (no menu, no intro replay).
		runActive = true
		for _, player in ipairs(Players:GetPlayers()) do
			runStart[player] = os.clock()
			player:SetAttribute("InMenu", false)
		end
	end

	if GameConfig.Debug then
		print(("[HullBreach] Shared reset (%s), returnToMenu=%s"):format(
			triggerPlayer and triggerPlayer.Name or "?", tostring(returnToMenu == true)))
	end
end

function EndingManager.Start()
	if started then return end
	started = true
	snapshotWorld()  -- one-time snapshot of the pristine world, for ResetRun
	randomizeRun()   -- first-run layout: each server boots a different nightmare

	Players.PlayerAdded:Connect(ensure)
	for _, p in ipairs(Players:GetPlayers()) do ensure(p) end
	-- Players begin on the main menu; the run is inert until they press Play.
	local function enterMenu(p) p:SetAttribute("InMenu", true) end
	Players.PlayerAdded:Connect(enterMenu)
	for _, p in ipairs(Players:GetPlayers()) do enterMenu(p) end
	Players.PlayerRemoving:Connect(function(p)
		flags[p] = nil; ended[p] = nil
		lastReset[p] = nil; runStart[p] = nil
		readyPlayers[p] = nil
	end)

	Net.Event("BallastInput").OnServerEvent:Connect(function(player, value)
		if type(value) == "number" then onBallastInput(player, value) end
	end)

	-- "Try Again" from the ending screen restarts the whole (shared) run.
	Net.Event("RequestRestart").OnServerEvent:Connect(function(player)
		if runEnded then EndingManager.ResetRun(player, false) end
	end)

	-- The in-experience Reset Character button (intercepted on the client) routes
	-- here: a mid-run restart. With shared fate this resets the run for the whole
	-- crew (debounced inside ResetRun so it can't be spammed).
	Net.Event("RequestResetRun").OnServerEvent:Connect(function(player)
		EndingManager.ResetRun(player, false)
	end)

	-- "Play" on the main menu = ready up. The shared run starts only once everyone
	-- present is ready (solo = just this player, so it starts immediately). The
	-- player stays frozen on the menu (nothing collected, flood/creature inert)
	-- until beginRun un-pauses the world for the whole crew at once.
	Net.Event("StartRun").OnServerEvent:Connect(function(player)
		if player:GetAttribute("InMenu") == false then return end  -- already in a run
		readyPlayers[player] = true
		if runActive then
			-- run already live (e.g. a rejoin): drop this player straight in rather
			-- than stranding them on the menu.
			player:SetAttribute("InMenu", false)
			runStart[player] = os.clock()
			Net.Event("RunStarted"):FireClient(player)
		elseif allReady() then
			beginRun()
		end
		-- otherwise: wait — the client shows "Waiting for your partner…".
	end)

	-- Co-op: back out of the ready/lobby wait.
	Net.Event("CancelReady").OnServerEvent:Connect(function(player)
		readyPlayers[player] = nil
	end)

	-- Death/ending screen "Main Menu": rebuild a fresh run and drop back to the menu.
	Net.Event("ReturnToMenu").OnServerEvent:Connect(function(player)
		EndingManager.ResetRun(player, true)
	end)

	local Interaction = getManager("InteractionManager")
	if Interaction and Interaction.Register then
		Interaction.Register("pod_panel", function(player) onEscapePod(player) end)
		Interaction.Register("radio", onRadio)
		Interaction.Register("exterior", onExterior)
		Interaction.Register("breach", onBreach)
	end

	if GameConfig.Debug then
		print("[HullBreach] EndingManager started.")
	end
end

return EndingManager
