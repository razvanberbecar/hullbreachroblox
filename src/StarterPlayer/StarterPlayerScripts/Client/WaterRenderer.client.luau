--!strict
-- WaterRenderer.client.lua  →  LocalScript in StarterPlayerScripts/Client
-- =============================================================================
-- Phase 3 (client): renders the flood. Receives FloodUpdate, grows each
-- section's water volume from the floor to the current level, and gives it a
-- dark, non-reflective look:
--   * volume + surface use a flat dark material (NOT Glass) with zero
--     reflectance, so the flashlight does not reflect/refract off the water,
--   * a faint surface "skin" sits at the waterline and gently bobs,
--   * bubbles rise inside flooded volumes,
--   * going under triggers a blue overlay + blur + underwater reverb.
-- All visuals are client-side; FloodManager only sends levels.
-- =============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SectionData = require(Shared:WaitForChild("SectionData"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Net = require(Shared:WaitForChild("Net"))

local player = Players.LocalPlayer
local IL = SectionData.INTERIOR_LENGTH
local IW = SectionData.INTERIOR_WIDTH
local SURFACE_THICK = 0.3

-- Water material: a flat, non-reflective surface. Glass refracts/reflects the
-- flashlight (the player did not want that); SmoothPlastic + Reflectance 0 + a
-- dark colour keeps the beam from registering on the water.
local WATER_MATERIAL = Enum.Material.SmoothPlastic

local levels: {[number]: number} = {}

-- Cache water parts by section ---------------------------------------------
local waterBySection: {[number]: BasePart} = {}
local function indexWater()
	for _, w in ipairs(CollectionService:GetTagged("WaterPlane")) do
		local s = w:GetAttribute("Section")
		if s and w:IsA("BasePart") then
			waterBySection[s] = w
		end
	end
end
CollectionService:GetInstanceAddedSignal("WaterPlane"):Connect(indexWater)
task.defer(indexWater)

-- Per-section cosmetic decor (surface skin + bubbles), created lazily ---------
type Decor = { surface: BasePart, bubbles: ParticleEmitter, cx: number, surfaceY: number, level: number }
local decor: {[number]: Decor} = {}

local function ensureDecor(section: number, volume: BasePart): Decor
	local d = decor[section]
	if d then return d end
	local center = SectionData.SectionCenter(section)

	-- faint, dark, non-reflective skin at the top of the volume = the waterline
	local surf = Instance.new("Part")
	surf.Name = "WaterSurface"
	surf.Anchored = true
	surf.CanCollide = false
	surf.CanQuery = false
	surf.CanTouch = false
	surf.CastShadow = false
	surf.Material = WATER_MATERIAL
	surf.Color = Color3.fromRGB(20, 46, 58)
	surf.Transparency = 0.4
	surf.Reflectance = 0
	surf.Size = Vector3.new(IL, SURFACE_THICK, IW)
	surf.Parent = volume

	-- bubbles drifting up through the flooded volume
	local bub = Instance.new("ParticleEmitter")
	bub.Rate = 0
	bub.Lifetime = NumberRange.new(2.5, 5)
	bub.Speed = NumberRange.new(0.3, 1)
	bub.Acceleration = Vector3.new(0, 1.6, 0)
	bub.EmissionDirection = Enum.NormalId.Top
	bub.SpreadAngle = Vector2.new(18, 18)
	bub.Size = NumberSequence.new(0.08)
	bub.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	bub.Color = ColorSequence.new(Color3.fromRGB(160, 195, 205))
	bub.LightEmission = 0.1
	bub.Enabled = false
	bub.Parent = volume

	d = { surface = surf, bubbles = bub, cx = center.X, surfaceY = SectionData.FLOOR_Y, level = 0 }
	decor[section] = d
	return d
end

-- Grow a section's water from the floor to the level surface, and style it.
local function renderSection(section: number, level: number)
	local w = waterBySection[section]
	if not w then return end

	-- one-time durable look for the volume (cheap to re-assert)
	if w.Material ~= WATER_MATERIAL then
		w.Material = WATER_MATERIAL
		w.Reflectance = 0
		w.CastShadow = false
	end

	local surfaceY = SectionData.LevelToWaterY(level)
	-- Sink the volume's bottom a little BELOW the floor so its bottom face is buried
	-- inside the (opaque) floor part instead of sitting exactly on the floor top. Both
	-- were at FLOOR_Y (=0) = the floor's top surface, so the coincident faces z-fought
	-- ("two textures flickering on the floor as the camera moves"). The buried strip is
	-- hidden by the floor; the water still visually fills from the floor up.
	local BOTTOM_SINK = 0.6
	local bottomY = SectionData.FLOOR_Y - BOTTOM_SINK
	local height = math.max(surfaceY - bottomY, 0.05)
	local center = SectionData.SectionCenter(section)
	local t = math.clamp(level / 100, 0, 1)
	local dry = level < 1

	w.Size = Vector3.new(IL, height, IW)
	w.CFrame = CFrame.new(center.X, bottomY + height / 2, 0)
	-- dark teal that gets darker with depth, so the flashlight barely lifts it
	w.Transparency = dry and 1 or (0.36 - 0.12 * t)
	w.Color = Color3.fromRGB(12, 36, 48):Lerp(Color3.fromRGB(3, 12, 20), t)

	local d = ensureDecor(section, w)
	d.cx = center.X
	d.surfaceY = surfaceY
	d.level = level
	d.surface.Size = Vector3.new(IL, SURFACE_THICK, IW)
	d.surface.Transparency = dry and 1 or 0.4
	d.bubbles.Enabled = not dry
	d.bubbles.Rate = dry and 0 or (6 + 10 * t)
end

Net.Event("FloodUpdate").OnClientEvent:Connect(function(serverLevels)
	for section, level in pairs(serverLevels) do
		levels[section] = level
		renderSection(section, level)
	end
end)

-- ---------------------------------------------------------------------------
-- Local swimming / submerged feel
-- ---------------------------------------------------------------------------
local submergedOverlay: Frame? = nil
local function ensureOverlay(): Frame
	if submergedOverlay then return submergedOverlay end
	local gui = Instance.new("ScreenGui")
	gui.Name = "SubmergedOverlay"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = Color3.fromRGB(12, 46, 64)
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Parent = gui
	submergedOverlay = f
	return f
end

-- underwater camera blur (off until the head goes under)
local underwaterBlur = Instance.new("BlurEffect")
underwaterBlur.Name = "UnderwaterBlur"
underwaterBlur.Size = 0
underwaterBlur.Enabled = true
underwaterBlur.Parent = Lighting

local function localSectionAndLevel(): (number?, number)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil, 0 end
	local section = SectionData.SectionAtPosition(hrp.Position)
	return section, levels[section] or 0
end

RunService.RenderStepped:Connect(function()
	local now = os.clock()

	-- animate each water surface: a gentle vertical bob
	for section, d in pairs(decor) do
		if d.level >= 1 then
			local bob = math.sin(now * 1.3 + section) * 0.1
			d.surface.CFrame = CFrame.new(d.cx, d.surfaceY + bob, 0)
		end
	end

	-- submerged: head below the water surface of the player's section
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	if not head then player:SetAttribute("Submerged", false); return end
	local section, level = localSectionAndLevel()
	if not section then player:SetAttribute("Submerged", false); return end

	local surfaceY = SectionData.LevelToWaterY(level)
	local submerged = (head.Position.Y < surfaceY)
	player:SetAttribute("Submerged", submerged)  -- read by AudioManager for breathing
	local overlay = ensureOverlay()
	overlay.BackgroundTransparency = submerged and 0.38 or 1
	underwaterBlur.Size = submerged and 8 or 0
	SoundService.AmbientReverb = submerged and Enum.ReverbType.UnderWater or Enum.ReverbType.NoReverb
end)
