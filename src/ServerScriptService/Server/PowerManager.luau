--!strict
-- PowerManager.lua  →  ModuleScript in ServerScriptService/Server
-- =============================================================================
-- Phase 4: three independent power circuits.
--   Emergency — always on. Dim red PointLights. Creature dormant.
--   Main      — restored at the engine-room generator. Enables corridor lights,
--               sonar, radio room; starts the generator hum; ALERTS the creature;
--               nudges flooding. This is the big risk/reward beat.
--   Ballast   — fuse installed at the control-room panel. Enables the manual
--               surface ending's valve puzzle. Does NOT change the creature.
--
-- Registers its interaction handlers (generator, ballast) with InteractionManager
-- and broadcasts PowerUpdate on every state change.
-- =============================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local SoundData = require(Shared:WaitForChild("SoundData"))
local Net = require(Shared:WaitForChild("Net"))

local serverFolder = ServerScriptService:WaitForChild("Server")

local PowerManager = {}

PowerManager.State = {
	emergencyPower = true,
	mainPower = false,
	ballastPower = false,
}

local started = false
local startingGenerator = false

-- Lazy cross-manager helpers -------------------------------------------------
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

-- Lighting helpers -----------------------------------------------------------
local function setEmergencyLights(on: boolean)
	for _, fixture in ipairs(CollectionService:GetTagged("EmergencyLight")) do
		local light = fixture:FindFirstChildOfClass("PointLight")
		if light then light.Enabled = on end
	end
end

local function flickerLight(light: SpotLight)
	-- a SETTLED fluorescent: mostly steady, with the occasional brief subtle dip —
	-- deliberately calmer than the red emergency strobe.
	local base = light:GetAttribute("BaseBrightness") or light.Brightness
	task.spawn(function()
		while light.Parent and light.Enabled do
			task.wait(4 + math.random() * 7)         -- long steady stretches
			if not light.Enabled then break end
			for _ = 1, math.random(1, 2) do
				light.Brightness = base * (0.5 + math.random() * 0.25)
				task.wait(0.05 + math.random() * 0.06)
				light.Brightness = base
				task.wait(0.06)
			end
		end
	end)
end

local function setMainLights(on: boolean)
	for _, fixture in ipairs(CollectionService:GetTagged("MainLight")) do
		local light = fixture:FindFirstChildOfClass("SpotLight")
		if light then
			light.Enabled = on
			if on then
				-- dim, clean, mostly-steady work light (the "generator is on" glow) —
				-- a calm cool white, not the harsh red emergency flicker.
				light.Color = Color3.fromRGB(208, 222, 235)
				light.Brightness = 1.5
				light:SetAttribute("BaseBrightness", 1.5)
				flickerLight(light)
			else
				light.Brightness = 0
			end
		end
	end
end

-- A dim per-room work light that comes on with the generator so EVERY room is
-- faintly visible without the flashlight (the narrow MainLight spots weren't
-- enough). One soft white PointLight per section light fixture; shadows off to
-- stay in budget.
local function setMainGlow(on: boolean)
	for _, fixture in ipairs(CollectionService:GetTagged("EmergencyLight")) do
		if fixture:IsA("BasePart") then
			local glow = fixture:FindFirstChild("MainGlow")
			if not glow then
				glow = Instance.new("PointLight")
				glow.Name = "MainGlow"
				glow.Color = Color3.fromRGB(225, 232, 244)
				glow.Brightness = 2.0
				glow.Range = 30
				glow.Shadows = false
				glow.Parent = fixture
			end
			;(glow :: PointLight).Enabled = on
		end
	end
end

-- Emergency-light flicker: subtle + occasional (a runtime effect; not a strobe).
local emergencyFlickerStarted = false
local function startEmergencyFlicker()
	if emergencyFlickerStarted then return end
	emergencyFlickerStarted = true
	for _, fixture in ipairs(CollectionService:GetTagged("EmergencyLight")) do
		local light = fixture:FindFirstChildOfClass("PointLight")
		if light then
			if light:GetAttribute("BaseBrightness") == nil then
				light:SetAttribute("BaseBrightness", light.Brightness)
			end
			task.spawn(function()
				while light.Parent do
					task.wait(1.5 + math.random() * 3)        -- 1.5-4.5s of steady dim red glow
					if light.Enabled then
						local b = light:GetAttribute("BaseBrightness") or light.Brightness
						-- flicker burst: surge brighter (washes the room red) then stutter down,
						-- so the room visibly pulses red instead of only dimming.
						for _ = 1, math.random(2, 5) do
							light.Brightness = b * (1.3 + math.random() * 0.5)
							task.wait(0.03 + math.random() * 0.05)
							light.Brightness = b * (0.2 + math.random() * 0.3)
							task.wait(0.03 + math.random() * 0.06)
						end
						if math.random() < 0.25 then
							light.Brightness = b * 0.05
							task.wait(0.08 + math.random() * 0.12)
						end
						light.Brightness = b
					end
				end
			end)
		end
	end
end

-- Broadcast ------------------------------------------------------------------
local function broadcast()
	Net.Event("PowerUpdate"):FireAllClients(PowerManager.State)
end

function PowerManager.GetState()
	return PowerManager.State
end

-- Reset to a fresh run (called by EndingManager.ResetRun).
function PowerManager.Reset()
	startingGenerator = false
	PowerManager.State.mainPower = false
	PowerManager.State.ballastPower = false
	PowerManager.State.emergencyPower = true
	setEmergencyLights(true)
	setMainLights(false)
	setMainGlow(false)
	broadcast()
end

-- Main power restoration ---------------------------------------------------
local function startGenerator(player: Player, generatorPart: BasePart)
	if PowerManager.State.mainPower or startingGenerator then
		notify(player, "The generator is already running.")
		return
	end
	startingGenerator = true
	notify(player, "You prime the generator. It coughs, sputters...")

	-- 5-second startup sequence
	local startSnd = SoundData.Make("generator_start", generatorPart, { Volume = 1, RollOffMaxDistance = 120 })
	if SoundData.HasAsset("generator_start") then startSnd:Play() end
	task.wait(5)

	PowerManager.State.mainPower = true
	startingGenerator = false

	-- effects
	setMainLights(true)
	setMainGlow(true)   -- dim room fill so you can see a little, generator-wide
	Net.Event("SoundCue"):FireAllClients("power_surge", generatorPart.Position)
	local hum = SoundData.Make("generator_hum", generatorPart, {
		Looped = true, Volume = 0.6, RollOffMaxDistance = 160, RollOffMinDistance = 10,
	})
	if SoundData.HasAsset("generator_hum") then hum:Play() end
	generatorPart:SetAttribute("Running", true)

	-- unlock the radio room console
	for _, console in ipairs(CollectionService:GetTagged("Interactable")) do
		if console:GetAttribute("Kind") == "radio" then
			console:SetAttribute("Locked", false)
		end
	end

	-- consequences in other systems
	local FloodManager = getManager("FloodManager")
	if FloodManager and FloodManager.OnMainPower then FloodManager.OnMainPower() end
	local CreatureManager = getManager("CreatureManager")
	if CreatureManager and CreatureManager.SetState then
		CreatureManager.SetState("alerted")
	end

	notify(player, "Power surges through the boat. Lights flicker on — and something stirs.")
	broadcast()
end

-- Ballast circuit ----------------------------------------------------------
local function installFuse(player: Player, ballastPart: BasePart)
	if PowerManager.State.ballastPower then
		-- Fuse already installed: RE-OPEN the valve puzzle instead of dead-ending.
		-- Closing the puzzle UI with [Esc] would otherwise strand the surface-manually
		-- route for the run (the fuse is already spent). Reopening resets the input.
		local EndingManager = getManager("EndingManager")
		if EndingManager and EndingManager.BeginBallastPuzzle then
			EndingManager.BeginBallastPuzzle(player, ballastPart)
		else
			notify(player, "The ballast system is already powered.")
		end
		return
	end
	local Inventory = getManager("InventoryManager")
	if Inventory and Inventory.HasItem then
		if not Inventory.HasItem(player, "fuse") then
			notify(player, "The panel is dead. It needs a fuse.")
			return
		end
		Inventory.RemoveItem(player, "fuse")
	else
		-- before Phase 6: allow install so the circuit can be exercised
		notify(player, "(No inventory yet — installing fuse for testing.)")
	end

	PowerManager.State.ballastPower = true
	ballastPart:SetAttribute("FuseInstalled", true)
	notify(player, "The fuse seats with a clunk. The ballast panel lights up.")

	-- Hand the valve-sequence puzzle to EndingManager (Phase 7).
	local EndingManager = getManager("EndingManager")
	if EndingManager and EndingManager.BeginBallastPuzzle then
		EndingManager.BeginBallastPuzzle(player, ballastPart)
	end
	broadcast()
end

function PowerManager.Start()
	if started then return end
	started = true

	-- emergency lighting on, main off
	setEmergencyLights(true)
	setMainLights(false)
	startEmergencyFlicker()

	-- register interactions
	local Interaction = getManager("InteractionManager")
	if Interaction and Interaction.Register then
		Interaction.Register("generator", function(player, part)
			if part:IsA("BasePart") then startGenerator(player, part) end
		end)
		Interaction.Register("ballast", function(player, part)
			if part:IsA("BasePart") then installFuse(player, part) end
		end)
	end

	broadcast()
	if GameConfig.Debug then
		print("[HullBreach] PowerManager started (emergency power on).")
	end
end

return PowerManager
