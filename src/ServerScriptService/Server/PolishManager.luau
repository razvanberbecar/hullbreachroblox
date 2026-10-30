--!strict
-- PolishManager.lua  →  ModuleScript in ServerScriptService/Server
-- =============================================================================
-- Phase 9: particle/visual decoration. Hooks CollectionService tag signals so it
-- re-applies automatically every time MapBuilder (re)builds the sub — including
-- after an ending soft-reset. Adds:
--   * water-spray particles on hull breaches
--   * spark bursts + a flash of light on the cut cable ends (DD_Sparker)
-- Lighting, atmosphere and post-FX are configured in LightingSetup; the main
-- light flicker is driven by PowerManager. PBR SurfaceAppearances need sourced
-- textures — left as a documented follow-up so the greybox stays asset-free.
-- =============================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SectionData = require(Shared:WaitForChild("SectionData"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Net = require(Shared:WaitForChild("Net"))

local serverFolder = ServerScriptService:WaitForChild("Server")

local PolishManager = {}
local started = false

local function makeEmitter(parent: BasePart, props: {[string]: any}): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	for k, v in pairs(props) do (e :: any)[k] = v end
	e.Parent = parent
	return e
end

local function decorateBreach(breach: Instance)
	if not breach:IsA("BasePart") then return end
	if breach:FindFirstChild("SprayFX") then return end
	local e = makeEmitter(breach, {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Rate = 26,
		Lifetime = NumberRange.new(0.6, 1.1),
		Speed = NumberRange.new(18, 30),
		SpreadAngle = Vector2.new(25, 25),
		Color = ColorSequence.new(Color3.fromRGB(170, 200, 210)),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Size = NumberSequence.new(0.6),
		Acceleration = Vector3.new(0, -20, 0),
	})
	e.Name = "SprayFX"
end

-- The cut cable ends MapBuilder hangs out of the cable trays (DD_Sparker): a burst of
-- sparks and a split-second flash of light on the walls around them.
local function decorateSpark(fixture: Instance)
	if not fixture:IsA("BasePart") then return end
	if fixture:FindFirstChild("SparkFX") then return end
	local flash = Instance.new("PointLight")
	flash.Name = "DD_SparkFlash"
	flash.Color = Color3.fromRGB(255, 196, 130)
	flash.Brightness = 5
	flash.Range = 13
	flash.Shadows = false
	flash.Enabled = false
	flash.Parent = fixture
	local e = makeEmitter(fixture, {
		Rate = 0,
		Lifetime = NumberRange.new(0.2, 0.5),
		Speed = NumberRange.new(6, 12),
		SpreadAngle = Vector2.new(40, 40),
		Color = ColorSequence.new(Color3.fromRGB(255, 220, 140)),
		Size = NumberSequence.new(0.15),
		Acceleration = Vector3.new(0, -30, 0),
	})
	e.Name = "SparkFX"
	task.spawn(function()
		while e.Parent do
			task.wait(3 + math.random() * 9)
			e:Emit(math.random(5, 12))
			Net.Event("SoundCue"):FireAllClients("electrical_spark", fixture.Position, 0.4)
			flash.Enabled = true
			task.wait(0.05 + math.random() * 0.06)
			flash.Enabled = false
			if math.random() < 0.4 then -- a stutter
				task.wait(0.05)
				flash.Enabled = true
				task.wait(0.04)
				flash.Enabled = false
			end
		end
	end)
end

local function hook(tag: string, fn: (Instance) -> ())
	for _, inst in ipairs(CollectionService:GetTagged(tag)) do fn(inst) end
	CollectionService:GetInstanceAddedSignal(tag):Connect(fn)
end

-- Random positional ambience: distant pipe hiss / structural groans everywhere,
-- plus a sonar ping from the sonar console once main power is on. Cues are
-- one-shots (AudioManager caps them ~5s), so long clips can't pile up.
local function getPower()
	local pm = serverFolder:FindFirstChild("PowerManager")
	if pm and pm:IsA("ModuleScript") then
		local ok, m = pcall(require, pm)
		if ok then return m end
	end
	return nil
end

local function startAmbientAudio()
	-- pipe hiss / structural groan from a random lit fixture
	task.spawn(function()
		while true do
			task.wait(7 + math.random() * 11)
			local fixtures = CollectionService:GetTagged("EmergencyLight")
			if #fixtures > 0 then
				local f = fixtures[math.random(1, #fixtures)]
				if f:IsA("BasePart") then
					local name = (math.random() < 0.65) and "pipe_hiss" or "structural_groan"
					Net.Event("SoundCue"):FireAllClients(name, f.Position)
				end
			end
		end
	end)
	-- sonar ping while main power is active
	task.spawn(function()
		while true do
			task.wait(5)
			local Power = getPower()
			if Power and Power.State and Power.State.mainPower then
				for _, c in ipairs(CollectionService:GetTagged("Interactable")) do
					if c:IsA("BasePart") and c:GetAttribute("Kind") == "sonar" then
						Net.Event("SoundCue"):FireAllClients("sonar_ping", c.Position)
						break
					end
				end
			end
		end
	end)
end

-- One-time scripted set-pieces (GDD section map): the galley's first big
-- structural groan, and the conning tower's unique sighting. Per life (reset on
-- respawn) so a fresh run replays them; positional one-shots via the SoundCue path.
local function startSetPieces()
	local Players = game:GetService("Players")
	local seen = {} -- [player] = {[section]=true}
	local nextSighting = 0
	-- lights drifting past the tower viewports (drawn on the client by WaterRenderer)
	local function sighting()
		for _, w in ipairs(CollectionService:GetTagged("DD_TowerWindow")) do
			w:SetAttribute("Sighting", os.clock())
		end
		nextSighting = os.clock() + 50 + math.random() * 70
	end
	local function reset(p) seen[p] = {} end
	local function watch(p) p.CharacterAdded:Connect(function() reset(p) end) end
	Players.PlayerRemoving:Connect(function(p) seen[p] = nil end)
	Players.PlayerAdded:Connect(watch)
	for _, p in ipairs(Players:GetPlayers()) do watch(p) end
	task.spawn(function()
		while true do
			task.wait(0.5)
			for _, p in ipairs(Players:GetPlayers()) do
				local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
				if hrp then
					local sec = SectionData.SectionAtPosition(hrp.Position)
					local s = seen[p]; if not s then s = {}; seen[p] = s end
					if not s[sec] then
						s[sec] = true
						if sec == 3 then
							Net.Event("SoundCue"):FireAllClients("structural_groan", hrp.Position)
							Net.Event("Notify"):FireClient(p, "A deep groan rolls through the hull — the whole submarine shifts around you.")
						elseif sec == 7 then
							Net.Event("SoundCue"):FireAllClients("creature_rumble", hrp.Position)
							Net.Event("Notify"):FireClient(p, "Far out in the black water, distant lights drift past the tower glass — vast and slow — then gone.")
							sighting()
						end
					elseif sec == 7 and os.clock() >= nextSighting then
						-- linger in the tower and they come back
						Net.Event("SoundCue"):FireAllClients("creature_rumble", hrp.Position, 0.22)
						sighting()
					end
				end
			end
		end
	end)
end

function PolishManager.Start()
	if started then return end
	started = true
	hook("HullBreach", decorateBreach)
	hook("DD_Sparker", decorateSpark)
	startAmbientAudio()
	startSetPieces()
	if GameConfig.Debug then
		print("[HullBreach] PolishManager started (particles online).")
	end
end

return PolishManager
