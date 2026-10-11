--!strict
-- InteractionManager.lua  →  ModuleScript in ServerScriptService/Server
-- =============================================================================
-- Central router for every ProximityPrompt in the submarine. Connects all
-- prompts (current and future), and dispatches on the part's tags / Kind:
--   * BulkheadDoor  — open/close, and permanent seal (-> FloodManager.SealDoor)
--   * Pickup        — item pickups (Phase 6 registers the real handler)
--   * Journal       — journal pages (Phase 7/6 register)
--   * Interactable  — dispatch by Kind to a handler registered by later phases
--
-- Later managers extend behaviour with InteractionManager.Register(kind, fn).
-- The server stays authoritative: prompts fire on the server, we validate here.
-- =============================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Net = require(Shared:WaitForChild("Net"))

local serverFolder = ServerScriptService:WaitForChild("Server")

local InteractionManager = {}
InteractionManager.Handlers = {}   -- [kind] = function(player, part, prompt)

local started = false

function InteractionManager.Register(kind: string, fn: (Player, Instance, ProximityPrompt) -> ())
	InteractionManager.Handlers[kind] = fn
end

local function notify(player: Player, text: string)
	Net.Event("Notify"):FireClient(player, text)
end
InteractionManager.Notify = notify

-- Door handling --------------------------------------------------------------
local function setDoorOpen(door: BasePart, open: boolean)
	door:SetAttribute("Open", open)
	door.CanCollide = not open
	door.Transparency = open and 0.7 or 0
	local prompt = door:FindFirstChild("DoorPrompt") :: ProximityPrompt?
	if prompt then
		prompt.ActionText = open and "Close" or "Open"
	end
end

local function handleDoor(player: Player, door: BasePart, prompt: ProximityPrompt)
	if door:GetAttribute("Sealed") then
		notify(player, "The bulkhead is sealed shut.")
		return
	end
	if prompt.Name == "SealPrompt" then
		local a, b = door:GetAttribute("SectionA"), door:GetAttribute("SectionB")
		local FloodManager = require(serverFolder:WaitForChild("FloodManager"))
		if FloodManager.SealDoor(a, b) then
			notify(player, "You seal the bulkhead. There is no reopening it.")
		end
		return
	end
	-- toggle open/close
	setDoorOpen(door, not door:GetAttribute("Open"))
	-- heavy metal door clang for every nearby client
	Net.Event("SoundCue"):FireAllClients("door_metal", door.Position)
	-- the door sound is audible to the creature (Phase 5 consumes ReportSound)
	local cmMod = serverFolder:FindFirstChild("CreatureManager")
	if cmMod and cmMod:IsA("ModuleScript") then
		local ok, CM = pcall(require, cmMod)
		if ok and type(CM) == "table" and CM.ReportSound then
			CM.ReportSound(door.Position, "interact")
		end
	end
end

-- Fallback pickup (until Phase 6 registers the inventory-aware handler) -------
local function fallbackPickup(player: Player, part: Instance, _prompt: ProximityPrompt)
	local itemId = part:GetAttribute("ItemId")
	notify(player, "Picked up " .. tostring(itemId) .. " (inventory comes online in Phase 6).")
	part:Destroy()
end

local function fallbackJournal(player: Player, part: Instance, _prompt: ProximityPrompt)
	local idx = part:GetAttribute("PageIndex")
	notify(player, "Read journal page " .. tostring(idx) .. ".")
	part:Destroy()
end

-- Dispatch -------------------------------------------------------------------
local function onTriggered(prompt: ProximityPrompt, player: Player)
	local part = prompt.Parent
	if not part or not part:IsA("BasePart") then return end

	if CollectionService:HasTag(part, "BulkheadDoor") then
		handleDoor(player, part, prompt)
		return
	end
	if CollectionService:HasTag(part, "Pickup") then
		local h = InteractionManager.Handlers["pickup"] or fallbackPickup
		h(player, part, prompt)
		return
	end
	if CollectionService:HasTag(part, "Journal") then
		local h = InteractionManager.Handlers["journal"] or fallbackJournal
		h(player, part, prompt)
		return
	end
	if CollectionService:HasTag(part, "Interactable") then
		local kind = part:GetAttribute("Kind")
		local h = kind and InteractionManager.Handlers[kind]
		if h then
			h(player, part, prompt)
		else
			notify(player, "You examine it, but there's nothing useful here.")
		end
		return
	end
end

local function connectPrompt(prompt: Instance)
	if prompt:IsA("ProximityPrompt") then
		prompt.Triggered:Connect(function(player)
			onTriggered(prompt, player)
		end)
	end
end

-- Built-in handlers for the static consoles (notice/periscope/sonar/ladder) so
-- they give real feedback instead of the old dev placeholder.
local function getMgr(name: string)
	local mod = serverFolder:FindFirstChild(name)
	if mod and mod:IsA("ModuleScript") then
		local ok, m = pcall(require, mod)
		if ok then return m end
	end
	return nil
end

local function onNotice(player: Player)
	notify(player, "Duty rosters, rationing orders, a faded safety notice. Routine — nothing about what came aboard.")
end

local function onPeriscope(player: Player)
	notify(player, "You press your eyes to the periscope. Black water — and far off, pale lights drift against the current. Too large. Too deep.")
end

local function onSonar(player: Player)
	-- Sonar tracking runs on the emergency circuit (always on) per GDD; only the
	-- radio (SOS) needs main power, so there is no main-power gate here.
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local creature = Workspace:FindFirstChild("Creature")
	local cpos = creature and creature.PrimaryPart and creature.PrimaryPart.Position
	if not (hrp and cpos) then
		notify(player, "The sonar sweeps — empty water, for now.")
		return
	end
	local d = math.floor((cpos - hrp.Position).Magnitude)
	local bearing = (cpos.X > hrp.Position.X) and "aft, toward the stern" or "forward, toward the bow"
	notify(player, "Sonar contact: roughly " .. d .. " studs " .. bearing .. ".")
end

local function onLadder(player: Player, part: Instance)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (hrp and part:IsA("BasePart")) then return end
	if hrp.Position.Y < 14 then
		hrp.CFrame = CFrame.new(part.Position.X, 20.5, 0)   -- up onto the conning-tower floor
		notify(player, "You haul yourself up the ladder into the conning tower.")
	else
		hrp.CFrame = CFrame.new(part.Position.X, 3, part.Position.Z + 4) -- back down to control room
		notify(player, "You climb back down into the control room.")
	end
end

function InteractionManager.Start()
	if started then return end
	started = true

	InteractionManager.Handlers["notice"] = onNotice
	InteractionManager.Handlers["periscope"] = onPeriscope
	InteractionManager.Handlers["sonar"] = onSonar
	InteractionManager.Handlers["ladder"] = onLadder

	-- connect existing + future prompts under the submarine
	for _, d in ipairs(Workspace:GetDescendants()) do
		connectPrompt(d)
	end
	Workspace.DescendantAdded:Connect(connectPrompt)

	if GameConfig.Debug then
		print("[HullBreach] InteractionManager started.")
	end
end

return InteractionManager
