--!strict
-- Net.lua  →  ModuleScript in ReplicatedStorage/Shared
-- =============================================================================
-- Central registry + accessor for all RemoteEvents / RemoteFunctions.
-- Server creates them on first access; clients wait for them. Always route
-- client<->server traffic through here so the names stay consistent and the
-- "never trust the client" rule is enforced in one place (server validates).
-- =============================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

-- Declared remotes. Direction is documentation; Roblox remotes are bidirectional
-- but we use them one-way as noted.
Net.Events = {
	-- Server -> Client (state sync)
	FloodUpdate     = "S2C",  -- water levels per section
	PowerUpdate     = "S2C",  -- power circuit states
	CreatureUpdate  = "S2C",  -- creature state + position
	InventoryUpdate = "S2C",  -- inventory slots for owning client
	OxygenUpdate    = "S2C",  -- oxygen meter value
	BatteryUpdate   = "S2C",  -- flashlight charge + flicker flag
	JournalUpdate   = "S2C",  -- journal page collected / full text
	JournalRead     = "S2C",  -- show a collected journal page in the reader panel {title,text}
	PlayerDied      = "S2C",  -- death -> ending sequence
	EndingTrigger   = "S2C",  -- cutscene for a specific ending id
	SoundCue        = "S2C",  -- positional one-shot audio request
	Notify          = "S2C",  -- brief diegetic UI line / objective hint
	HintDirection   = "S2C",  -- Hint product: names the room of the next log page (banner above toolbar)
	BallastPuzzle   = "S2C",  -- open/close the valve-sequence puzzle UI
	SurvivalUpdate  = "S2C",  -- SOS countdown remaining seconds
	RunStarted      = "S2C",  -- co-op: the shared run has begun (all players ready) -> leave menu, play intro
	RunReset        = "S2C",  -- co-op: the shared run was reset -> dismiss the ending screen {toMenu=bool}
	MatchmakingStatus = "S2C", -- co-op join layer: lobby/matchmaking state {state,text,joinKey?}

	-- Client -> Server (requests; server authoritative)
	InteractRequest = "C2S",  -- player requests interaction with an object
	UseItem         = "C2S",  -- use/drop an inventory slot
	FlashlightToggle = "C2S", -- equip/holster the flashlight (F)
	SealDoor        = "C2S",  -- seal a bulkhead door (permanent)
	SoundEvent      = "C2S",  -- player produced a sound (walk/run/splash/interact)
	HeartbeatSound  = "C2S",  -- mouse-delta heartbeat while hiding
	ExitHide        = "C2S",  -- leave a hiding spot (client E while hiding)
	BallastInput    = "C2S",  -- valve sequence puzzle input
	Purchase        = "C2S",  -- request a purchase prompt {kind, key}
	CosmeticSelect  = "C2S",  -- equip an owned cosmetic {kind, key}
	RequestRestart  = "C2S",  -- player clicked Try Again on the ending screen
	RequestResetRun = "C2S",  -- player used the Reset Character button -> full restart
	StartRun        = "C2S",  -- player clicked Play on the main menu -> ready up for a fresh run
	CancelReady     = "C2S",  -- co-op: player backed out of the ready/lobby wait -> un-ready
	RequestSolo     = "C2S",  -- co-op join: Play Solo -> reserve a private 1-player server + teleport
	RequestCoopHost = "C2S",  -- co-op join: Invite a Friend -> reserve a private co-op server + teleport host
	RequestQuickMatch = "C2S",-- co-op join: Quick Match -> enter the cross-server matchmaking queue
	CancelMatchmaking = "C2S",-- co-op join: leave the quick-match queue
	RequestLobby    = "C2S",  -- co-op: leave a gameplay server back to the public lobby/router menu
	SaveSettings    = "C2S",  -- persist player settings {master,music,sfx,sensitivity,brightness}
	SetCrouch       = "C2S",  -- crouch state; server lowers the drown line by the camera dip
	ReturnToMenu    = "C2S",  -- death-screen Main Menu: fresh run + back to the main menu
	SelectSlot      = "C2S",  -- switch the active save slot (separate progress profiles)
	SubmitRun       = "C2S",  -- Developer Commentary: submit this run for a dev rating
}

Net.Functions = {
	GetGameState = "C2S",     -- client pulls a full state snapshot on spawn
	GetLeaderboards = "C2S",  -- client pulls the leaderboard top-10s for the menu panel
}

local FOLDER_NAME = "Remotes"

local function getFolder(): Folder
	if RunService:IsServer() then
		local f = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if not f then
			f = Instance.new("Folder")
			f.Name = FOLDER_NAME
			f.Parent = ReplicatedStorage
		end
		return f :: Folder
	else
		return ReplicatedStorage:WaitForChild(FOLDER_NAME, 30) :: Folder
	end
end

local function resolve(class: string, name: string): Instance
	local folder = getFolder()
	if RunService:IsServer() then
		local inst = folder:FindFirstChild(name)
		if not inst then
			inst = Instance.new(class)
			inst.Name = name
			inst.Parent = folder
		end
		return inst
	else
		return folder:WaitForChild(name, 30)
	end
end

-- Ensure every declared remote exists (call once on the server at boot).
function Net.Init()
	assert(RunService:IsServer(), "Net.Init must run on the server")
	for name in pairs(Net.Events) do
		resolve("RemoteEvent", name)
	end
	for name in pairs(Net.Functions) do
		resolve("RemoteFunction", name)
	end
end

-- Accessors -----------------------------------------------------------------
function Net.Event(name: string): RemoteEvent
	assert(Net.Events[name], "Unknown RemoteEvent: " .. tostring(name))
	return resolve("RemoteEvent", name) :: RemoteEvent
end

function Net.Func(name: string): RemoteFunction
	assert(Net.Functions[name], "Unknown RemoteFunction: " .. tostring(name))
	return resolve("RemoteFunction", name) :: RemoteFunction
end

return Net
