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
local SectionData = require(Shared:WaitForChild("SectionData"))
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

-- Main power = warm tungsten work lamps. MapBuilder dresses every MainLight fixture
-- as a caged pendant with a DD_Bulb; one lamp per room carries the MainShadows attr
-- and a DD_MainFillAtt ceiling-bounce light. When the generator catches, the lamps
-- strike room by room outward from the engine room, and each room's red emergency
-- lantern drops to a faint glow and hands its shadows to the work lamp (so the
-- shadow-casting budget stays ~9 whichever circuit is live).
local TUNGSTEN = Color3.fromRGB(255, 196, 140)      -- ~3000K work lamp
local FILAMENT_COLD = Color3.fromRGB(255, 110, 40)  -- filament still warming up / sagging
local BULB_ON = Color3.fromRGB(255, 205, 150)
local BULB_OFF = Color3.fromRGB(58, 50, 42)
local MAIN_BRIGHTNESS = 4.5
local MAIN_FILL = 1.2
local EMERGENCY_UNDER_MAIN = 0.3   -- red lanterns stay faintly on once the generator runs
local STRIKE_HOP_DELAY = 0.45      -- seconds per section away from the engine room
local LENS_DARK = Color3.fromRGB(60, 10, 6)
local mainGeneration = 0           -- bumped on every on/off so stale strike/sag threads stop

-- A lantern's lens + light cone at a fraction of full output.
local function paintLantern(fixture: Instance, frac: number)
	local lensOn = fixture:GetAttribute("LensColor")
	if typeof(lensOn) == "Color3" and fixture:IsA("BasePart") then
		(fixture :: BasePart).Color = LENS_DARK:Lerp(lensOn, math.clamp(frac, 0, 1))
	end
	local cone = fixture:FindFirstChild("DD_LightCone")
	if cone and cone:IsA("Beam") then (cone :: Beam).Brightness = math.clamp(frac, 0, 1.3) end
end

-- Scale an emergency lantern (light, bounce fill, lens) to `scale` of its full output.
-- Full output and whether it casts shadows are recorded the first time.
local function emergencyLevel(fixture: Instance, scale: number, shadows: boolean)
	local light = fixture:FindFirstChildOfClass("PointLight")
	if not light then return end
	local full = light:GetAttribute("FullBrightness")
	if full == nil then
		full = light:GetAttribute("BaseBrightness") or light.Brightness
		light:SetAttribute("FullBrightness", full)
		light:SetAttribute("CastsShadows", light.Shadows)
	end
	light:SetAttribute("BaseBrightness", full * scale)
	light.Brightness = full * scale
	light.Shadows = shadows and light:GetAttribute("CastsShadows") == true
	local att = fixture:FindFirstChild("DD_BounceAtt")
	local bounce = att and att:FindFirstChildOfClass("PointLight")
	if bounce then
		local bfull = bounce:GetAttribute("FullBrightness")
		if bfull == nil then
			bfull = bounce:GetAttribute("BaseBrightness") or bounce.Brightness
			bounce:SetAttribute("FullBrightness", bfull)
		end
		bounce:SetAttribute("BaseBrightness", bfull * scale)
		bounce.Brightness = bfull * scale
		bounce.Enabled = scale > 0.5   -- a faint lantern needs no bounce fill
	end
	paintLantern(fixture, scale)
end

-- One work lamp at level k (0 = off .. 1 = full), optionally tinted.
local function setLamp(fixture: Instance, k: number, color: Color3?)
	local c = color or TUNGSTEN
	local light = fixture:FindFirstChildOfClass("SpotLight")
	if light then
		light.Enabled = k > 0
		light.Brightness = MAIN_BRIGHTNESS * k
		light.Color = c
	end
	local fillAtt = fixture:FindFirstChild("DD_MainFillAtt")
	local fill = fillAtt and fillAtt:FindFirstChildOfClass("PointLight")
	if fill then
		fill.Enabled = k > 0
		fill.Brightness = MAIN_FILL * k
		fill.Color = c
	end
	local bulb = fixture:FindFirstChild("DD_Bulb")
	if bulb and bulb:IsA("BasePart") then
		if k <= 0.02 then
			bulb.Material = Enum.Material.Glass
			bulb.Color = BULB_OFF
		else
			bulb.Material = Enum.Material.Neon
			bulb.Color = BULB_OFF:Lerp(color and BULB_ON:Lerp(color, 0.5) or BULB_ON, math.clamp(k, 0, 1))
		end
	end
end

-- Running lamps in a room sag together now and then (generator load), warming in
-- colour as they dim: a tungsten brown-out, calmer than the red emergency stutter.
local function startMainSag(lamps: { Instance }, gen: number)
	task.spawn(function()
		while mainGeneration == gen do
			task.wait(5 + math.random() * 9)
			if mainGeneration ~= gen then break end
			local depth = 0.45 + math.random() * 0.3
			for _, f in ipairs(lamps) do setLamp(f, depth, FILAMENT_COLD:Lerp(TUNGSTEN, depth)) end
			task.wait(0.12 + math.random() * 0.35)
			if mainGeneration ~= gen then break end
			for _, f in ipairs(lamps) do setLamp(f, 1) end
		end
	end)
end

-- One room's lamps catching: a few failed strikes and a spark, the red lantern hands
-- over, then the filaments warm from deep orange to tungsten.
local function strikeRoom(lamps: { Instance }, lanterns: { Instance }, gen: number)
	for _ = 1, math.random(2, 3) do
		if mainGeneration ~= gen then return end
		for _, f in ipairs(lamps) do setLamp(f, 0.6 + math.random() * 0.4) end
		task.wait(0.04 + math.random() * 0.05)
		for _, f in ipairs(lamps) do setLamp(f, 0) end
		task.wait(0.07 + math.random() * 0.14)
	end
	if mainGeneration ~= gen then return end
	local first = lamps[1]
	if first and first:IsA("BasePart") then
		Net.Event("SoundCue"):FireAllClients("electrical_spark", (first :: BasePart).Position, 0.35)
	end
	for _, lf in ipairs(lanterns) do emergencyLevel(lf, EMERGENCY_UNDER_MAIN, false) end
	for _, f in ipairs(lamps) do
		local light = f:FindFirstChildOfClass("SpotLight")
		if light then light.Shadows = f:GetAttribute("MainShadows") == true end
	end
	local steps = 8
	for s = 1, steps do
		if mainGeneration ~= gen then return end
		local t = s / steps
		for _, f in ipairs(lamps) do setLamp(f, 0.25 + 0.75 * t, FILAMENT_COLD:Lerp(TUNGSTEN, t)) end
		task.wait(0.09)
	end
	startMainSag(lamps, gen)
end

-- on = the staged switch-on (rooms strike outward from the engine room);
-- off = every work lamp dark at once and every emergency lantern back to full.
local function setMainLights(on: boolean)
	mainGeneration += 1
	local gen = mainGeneration
	local rooms: { [number]: { Instance } } = {}
	for _, f in ipairs(CollectionService:GetTagged("MainLight")) do
		local s = f:GetAttribute("Section") or 0
		if not rooms[s] then rooms[s] = {} end
		table.insert(rooms[s], f)
	end
	local lanternsBySection: { [number]: { Instance } } = {}
	for _, lf in ipairs(CollectionService:GetTagged("EmergencyLight")) do
		local s = lf:GetAttribute("Section") or 0
		if not lanternsBySection[s] then lanternsBySection[s] = {} end
		table.insert(lanternsBySection[s], lf)
	end
	if not on then
		for _, lamps in pairs(rooms) do
			for _, f in ipairs(lamps) do
				setLamp(f, 0)
				local light = f:FindFirstChildOfClass("SpotLight")
				if light then light.Shadows = false end
			end
		end
		for _, lf in ipairs(CollectionService:GetTagged("EmergencyLight")) do emergencyLevel(lf, 1, true) end
		return
	end
	-- rooms without work lamps (the conning tower) keep their lantern at full
	for s, lamps in pairs(rooms) do
		local hops = SectionData.Distance(8, s)
		if hops == math.huge then hops = 0 end
		task.delay(hops * STRIKE_HOP_DELAY + math.random() * 0.15, function()
			if mainGeneration == gen then strikeRoom(lamps, lanternsBySection[s] or {}, gen) end
		end)
	end
end

-- Emergency-light flicker: subtle + occasional (a runtime effect; not a strobe).
-- The wall lanterns MapBuilder builds (LensColor attr, DD_LightCone beam, DD_Bounce
-- fill) dim WITH the bulb, so the flicker reads on the source itself, and each lamp's
-- FlickerCalm attr (>1 steadier, <1 twitchier) gives it its own temperament.
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
			local bounceAtt = fixture:FindFirstChild("DD_BounceAtt")
			local bounce = bounceAtt and bounceAtt:FindFirstChildOfClass("PointLight")
			local function level(k: number)
				local b = light:GetAttribute("BaseBrightness") or light.Brightness
				local full = light:GetAttribute("FullBrightness") or b
				light.Brightness = b * k
				if bounce then bounce.Brightness = (bounce:GetAttribute("BaseBrightness") or 0.6) * k end
				paintLantern(fixture, k * (if full > 0 then b / full else 1))
			end
			task.spawn(function()
				while light.Parent do
					local calm = fixture:GetAttribute("FlickerCalm") or 1
					task.wait((1.5 + math.random() * 3) * calm)  -- 1.5-4.5s of steady dim red glow (x calm)
					if light.Enabled then
						-- flicker burst: surge brighter (washes the room red) then stutter down,
						-- so the room visibly pulses red instead of only dimming.
						for _ = 1, math.random(2, 5) do
							level(1.3 + math.random() * 0.5)
							task.wait(0.03 + math.random() * 0.05)
							level(0.2 + math.random() * 0.3)
							task.wait(0.03 + math.random() * 0.06)
						end
						if math.random() < 0.25 then
							level(0.05)
							task.wait(0.08 + math.random() * 0.12)
						end
						level(1)
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
	-- a fresh run: generator stopped, radio dead again, fuse bay empty
	for _, part in ipairs(CollectionService:GetTagged("Interactable")) do
		local kind = part:GetAttribute("Kind")
		if kind == "generator" then
			part:SetAttribute("Running", false)
			local hum = part:FindFirstChild("Snd_generator_hum")
			if hum and hum:IsA("Sound") then hum:Stop() end
		elseif kind == "radio" then
			part:SetAttribute("Locked", true)
		elseif kind == "ballast" then
			part:SetAttribute("FuseInstalled", false)
		end
	end
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

	-- effects: the work lamps strike room by room, outward from the engine room
	setMainLights(true)
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
