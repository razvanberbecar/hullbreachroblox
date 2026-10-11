--!strict
-- PolishManager.lua  →  ModuleScript in ServerScriptService/Server
-- =============================================================================
-- Phase 9: particle/visual decoration. Hooks CollectionService tag signals so it
-- re-applies automatically every time MapBuilder (re)builds the sub — including
-- after an ending soft-reset. Adds:
--   * water-spray particles on hull breaches
--   * rising bubble emitters on each section's water plane (floor vents)
--   * spark bursts on a subset of emergency fixtures
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
		Rate = 80,
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

local function decorateWaterVents(water: Instance)
	if not water:IsA("BasePart") then return end
	if water:FindFirstChild("BubbleFX") then return end
	local e = makeEmitter(water, {
		Rate = 6,
		Lifetime = NumberRange.new(2, 3.5),
		Speed = NumberRange.new(2, 4),
		SpreadAngle = Vector2.new(8, 8),
		Color = ColorSequence.new(Color3.fromRGB(200, 230, 240)),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.4),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Size = NumberSequence.new(0.25),
		Acceleration = Vector3.new(0, 6, 0),
		EmissionDirection = Enum.NormalId.Top,
	})
	e.Name = "BubbleFX"
end

local function decorateSpark(fixture: Instance)
	if not fixture:IsA("BasePart") then return end
	if fixture:FindFirstChild("SparkFX") then return end
	-- only ~1 in 4 fixtures sparks, for variety
	if (fixture:GetAttribute("Section") or 0) % 4 ~= 0 then return end
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
			task.wait(2 + math.random() * 6)
			e:Emit(math.random(4, 10))
			Net.Event("SoundCue"):FireAllClients("electrical_spark", fixture.Position)
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
						end
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
	hook("WaterPlane", decorateWaterVents)
	hook("EmergencyLight", decorateSpark)
	startAmbientAudio()
	startSetPieces()
	if GameConfig.Debug then
		print("[HullBreach] PolishManager started (particles online).")
	end
end

return PolishManager
