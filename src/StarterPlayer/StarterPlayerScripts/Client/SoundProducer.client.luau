--!strict
-- SoundProducer.client.lua  →  LocalScript in StarterPlayerScripts/Client
-- =============================================================================
-- Phase 5 (client): turns player actions into the sounds the creature hears, and
-- owns all movement-speed state so nothing fights over Humanoid.WalkSpeed.
--   * walk  — moving normally (medium range to creature)
--   * run   — holding Shift (high; triggers alerted/hunting)
--   * crouch— holding Ctrl (silent, safe; no sound emitted)
--   * splash— first step into swimmable water (high)
--   * heartbeat — while hiding in a locker, fast mouse movement betrays you
-- Speeds: crouch < walk < run, all scaled down while swimming. Zero while hiding.
-- =============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SectionData = require(Shared:WaitForChild("SectionData"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Net = require(Shared:WaitForChild("Net"))

local player = Players.LocalPlayer
local levels: {[number]: number} = {}
Net.Event("FloodUpdate").OnClientEvent:Connect(function(serverLevels)
	for s, l in pairs(serverLevels) do levels[s] = l end
end)

-- input state
local crouching = false
local running = false
local function isCrouchKey(kc: Enum.KeyCode): boolean
	return kc == Enum.KeyCode.LeftControl or kc == Enum.KeyCode.RightControl or kc == Enum.KeyCode.C
end
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if isCrouchKey(input.KeyCode) then
		crouching = true
	elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		running = true
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if isCrouchKey(input.KeyCode) then
		crouching = false
	elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		running = false
	end
end)

local function localLevel(): (number?, number)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil, 0 end
	local s = SectionData.SectionAtPosition(hrp.Position)
	return s, levels[s] or 0
end

local lastStep = 0
local lastCrouchSent = false
local wasSwimming = false
local heartbeatAccum = 0
local lastHeartbeat = 0

RunService.RenderStepped:Connect(function(dt)
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	if crouching ~= lastCrouchSent then
		lastCrouchSent = crouching
		Net.Event("SetCrouch"):FireServer(crouching)
	end
	local hiding = player:GetAttribute("Hiding") == true
	local _, level = localLevel()
	local swimming = level >= GameConfig.SwimLevelMin

	-- ---- Hiding: frozen, betrayed only by mouse movement ----
	if hiding then
		humanoid.WalkSpeed = 0
		local delta = UserInputService:GetMouseDelta()
		heartbeatAccum += delta.Magnitude
		if heartbeatAccum > 60 and (os.clock() - lastHeartbeat) > 0.6 then
			Net.Event("HeartbeatSound"):FireServer()
			lastHeartbeat = os.clock()
			heartbeatAccum = 0
		end
		heartbeatAccum = math.max(heartbeatAccum - dt * 30, 0) -- decay
		return
	end

	-- ---- Movement speed + visible crouch ----
	local base = GameConfig.WalkSpeed
	local camTarget = Vector3.zero
	if crouching then
		base = GameConfig.CrouchSpeed
		camTarget = Vector3.new(0, -1.8, 0)   -- dip the first-person view so crouch is unmistakable
	elseif running then
		base = GameConfig.RunSpeed
	end
	if swimming then base *= GameConfig.SwimSlowFactor end
	humanoid.WalkSpeed = base
	humanoid.CameraOffset = humanoid.CameraOffset:Lerp(camTarget, math.clamp(dt * 12, 0, 1))

	-- ---- Splash on entering water ----
	if swimming and not wasSwimming then
		Net.Event("SoundEvent"):FireServer("splash")
	end
	wasSwimming = swimming

	-- ---- Footstep / swimming sound emission ----
	local moving = humanoid.MoveDirection.Magnitude > 0.1
		and humanoid.FloorMaterial ~= Enum.Material.Air
	if moving and not crouching then
		if swimming then
			-- in water, footsteps are replaced by audible water-movement sounds (GDD 5.1)
			if (os.clock() - lastStep) >= GameConfig.SoundEventInterval * 1.3 then
				lastStep = os.clock()
				Net.Event("SoundEvent"):FireServer("swim")
			end
		else
			local interval = running and GameConfig.SoundEventInterval * 0.7 or GameConfig.SoundEventInterval
			if (os.clock() - lastStep) >= interval then
				lastStep = os.clock()
				Net.Event("SoundEvent"):FireServer(running and "run" or "walk")
			end
		end
	end
end)
