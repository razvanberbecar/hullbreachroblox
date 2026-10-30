--!strict
-- WaterRenderer.client.lua  →  LocalScript in StarterPlayerScripts/Client
-- =============================================================================
-- Phase 3 (client): renders the flood. Receives FloodUpdate, grows each
-- section's water volume from the floor to the current level, and gives it a
-- dark, non-reflective look:
--   * volume + surface use a flat dark material (NOT Glass) with zero
--     reflectance, so the flashlight does not reflect/refract off the water,
--   * a faint surface "skin" sits at the waterline and gently bobs, with a foam line
--     along the walls, floating debris and ripple rings where the drips land,
--   * shallow water is clear enough to see the deck through; deep water goes black,
--   * bubbles rise inside flooded volumes,
--   * the colour grade blends between emergency / main power / underwater looks;
--     going under adds short-visibility haze, blur, a vignette + underwater reverb.
-- All visuals are client-side; FloodManager only sends levels.
-- =============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

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
type Debris = { part: BasePart, x: number, z: number, h: number, yaw: number, phase: number }
type Decor = {
	surface: BasePart, bubbles: ParticleEmitter, cx: number, surfaceY: number, level: number,
	foam: { { part: BasePart, x: number, z: number } }, debris: { Debris }, ripples: { ParticleEmitter },
}
local decor: {[number]: Decor} = {}

local SOFT_DOT = "rbxasset://textures/particles/smoke_main.dds"
local RING_TEX = "rbxasset://textures/particles/explosion01_shockwave_main.dds"

local function decorPart(name: string, size: Vector3, color: Color3, material: Enum.Material, transparency: number, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = material
	p.Transparency = transparency
	p.Parent = parent
	return p
end

-- things that float: planks, a lid, sodden paper, rags, a tin
local DEBRIS_KINDS = {
	{ size = Vector3.new(2.3, 0.16, 0.5), color = Color3.fromRGB(84, 62, 42), material = Enum.Material.WoodPlanks },
	{ size = Vector3.new(1.3, 0.12, 1.1), color = Color3.fromRGB(96, 74, 50), material = Enum.Material.Wood },
	{ size = Vector3.new(0.8, 0.03, 1.05), color = Color3.fromRGB(150, 146, 124), material = Enum.Material.SmoothPlastic },
	{ size = Vector3.new(1.3, 0.07, 1), color = Color3.fromRGB(58, 60, 50), material = Enum.Material.Fabric },
	{ size = Vector3.new(0.75, 0.44, 0.44), color = Color3.fromRGB(110, 104, 90), material = Enum.Material.Metal, shape = Enum.PartType.Cylinder },
	{ size = Vector3.new(1.7, 0.14, 0.4), color = Color3.fromRGB(70, 52, 36), material = Enum.Material.WoodPlanks },
}

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
	surf.Color = Color3.fromRGB(58, 96, 106)
	surf.Transparency = 0.78
	surf.Reflectance = 0
	surf.Size = Vector3.new(IL, SURFACE_THICK, IW)
	surf.Parent = volume

	-- bubbles drifting up through the flooded volume
	local bub = Instance.new("ParticleEmitter")
	bub.Texture = SOFT_DOT
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

	-- foam + scum line where the water meets the walls
	local foam = {}
	local FOAM_C = Color3.fromRGB(150, 168, 164)
	for _, s in ipairs({ -1, 1 }) do
		table.insert(foam, { part = decorPart("WaterFoam", Vector3.new(IL, 0.05, 0.55), FOAM_C, WATER_MATERIAL, 0.74, volume), x = 0, z = s * (IW / 2 - 0.27) })
		table.insert(foam, { part = decorPart("WaterFoam", Vector3.new(0.55, 0.05, IW), FOAM_C, WATER_MATERIAL, 0.74, volume), x = s * (IL / 2 - 0.27), z = 0 })
	end

	-- floating debris, the same each run (a fixed seed per room)
	local rng = Random.new(700 + section)
	local debris = {}
	for _ = 1, 7 do
		local k = DEBRIS_KINDS[rng:NextInteger(1, #DEBRIS_KINDS)]
		local p = decorPart("WaterDebris", k.size, k.color, k.material, 1, volume)
		if k.shape then p.Shape = k.shape end
		table.insert(debris, {
			part = p, x = center.X + rng:NextNumber(-19, 19), z = rng:NextNumber(-8.5, 8.5),
			h = k.size.Y, yaw = rng:NextNumber(0, math.pi * 2), phase = rng:NextNumber(0, 10),
		})
	end

	-- a flat ring spreading where each overhead drip lands
	local ripples = {}
	for _, drip in ipairs(CollectionService:GetTagged("DD_Drip")) do
		if drip:GetAttribute("Section") == section and drip:IsA("BasePart") then
			local a = Instance.new("Attachment")
			a.Name = "RippleAt"
			a.Position = Vector3.new(drip.Position.X - center.X, SURFACE_THICK / 2 + 0.03, drip.Position.Z)
			a.Parent = surf
			local e = Instance.new("ParticleEmitter")
			e.Texture = RING_TEX
			e.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
			e.EmissionDirection = Enum.NormalId.Top
			e.Speed = NumberRange.new(0.02)
			e.SpreadAngle = Vector2.new(0, 0)
			e.Lifetime = NumberRange.new(0.9, 1.2)
			e.Rate = drip:GetAttribute("Rate") or 0.5
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 2.4) })
			e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
			e.Color = ColorSequence.new(Color3.fromRGB(190, 210, 214))
			e.LightInfluence = 0.85
			e.Brightness = 2
			e.Parent = a
			table.insert(ripples, e)
		end
	end

	d = {
		surface = surf, bubbles = bub, cx = center.X, surfaceY = SectionData.FLOOR_Y, level = 0,
		foam = foam, debris = debris, ripples = ripples,
	}
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
	-- clear at ankle depth (the deck plates and the torchlight show through), closing
	-- to a near-opaque black-teal as it deepens
	local depth = math.clamp(level / 45, 0, 1)
	w.Transparency = dry and 1 or (0.78 - 0.5 * depth)
	w.Color = Color3.fromRGB(26, 60, 66):Lerp(Color3.fromRGB(4, 16, 24), depth)

	local d = ensureDecor(section, w)
	d.cx = center.X
	d.surfaceY = surfaceY
	d.level = level
	d.surface.Size = Vector3.new(IL, SURFACE_THICK, IW)
	d.surface.Transparency = dry and 1 or (0.84 - 0.14 * depth)
	d.bubbles.Enabled = not dry
	d.bubbles.Rate = dry and 0 or (3 + 7 * t)
	-- bubbles fade out by about the time they reach the surface
	local rise = math.clamp(math.sqrt(math.max(height, 0.5) / 1.1), 0.5, 5)
	d.bubbles.Lifetime = NumberRange.new(rise * 0.4, rise)
	local floating = level >= 3 and level <= 96
	for _, f in ipairs(d.foam) do f.part.Transparency = dry and 1 or 0.74 end
	for _, b in ipairs(d.debris) do b.part.Transparency = floating and 0 or 1 end
	for _, e in ipairs(d.ripples) do e.Enabled = not dry end
end

Net.Event("FloodUpdate").OnClientEvent:Connect(function(serverLevels)
	for section, level in pairs(serverLevels) do
		levels[section] = level
		renderSection(section, level)
	end
end)

-- ---------------------------------------------------------------------------
-- Colour grade (visual batch 1d): one look per state, blended with tweens.
--   emergency  -- rich red, deep blacks, navy shadows
--   main       -- warm tungsten highlights over the same navy shadows
--   underwater -- cold teal, desaturated, short visibility (atmosphere haze),
--                 soft blur + a dark vignette drawn below the HUD
-- Drives the server-made Deep* effects locally (LightingSetup only sets them once
-- at boot). Underwater wins over the power state; surfacing blends back to
-- whichever power look is live (PowerUpdate.mainPower).
-- ---------------------------------------------------------------------------
type Grade = {
	cc: { [string]: any }, bloom: { [string]: any }, atmo: { [string]: any },
	ambient: Color3, blur: number, water: boolean,
}
local NAVY_SHADOW = Color3.fromRGB(10, 17, 28)
local AIR_ATMO = { Density = 0.42, Haze = 2.4, Offset = 0.1, Color = Color3.fromRGB(20, 50, 60), Decay = Color3.fromRGB(10, 20, 28) }
local GRADES: { [string]: Grade } = {
	emergency = {
		cc = { Brightness = -0.04, Contrast = 0.22, Saturation = -0.28, TintColor = Color3.fromRGB(222, 218, 234) },
		bloom = { Intensity = 1.0, Threshold = 0.9 },
		atmo = AIR_ATMO, ambient = NAVY_SHADOW, blur = 0, water = false,
	},
	main = {
		cc = { Brightness = 0, Contrast = 0.18, Saturation = -0.12, TintColor = Color3.fromRGB(255, 236, 212) },
		bloom = { Intensity = 0.9, Threshold = 1.0 },
		atmo = AIR_ATMO, ambient = NAVY_SHADOW, blur = 0, water = false,
	},
	underwater = {
		cc = { Brightness = -0.03, Contrast = 0.08, Saturation = -0.3, TintColor = Color3.fromRGB(95, 190, 205) },
		bloom = { Intensity = 1.3, Threshold = 0.75 },
		atmo = { Density = 0.9, Haze = 4, Offset = 0.2, Color = Color3.fromRGB(25, 90, 105), Decay = Color3.fromRGB(8, 36, 46) },
		ambient = Color3.fromRGB(8, 22, 30), blur = 3, water = true,
	},
}
-- in-water transparency of the overlay pieces (1 = hidden above water)
local WATER_BODY = 0.85
local WATER_EDGE = 0.1

-- underwater camera blur (0 above water)
local underwaterBlur = Instance.new("BlurEffect")
underwaterBlur.Name = "UnderwaterBlur"
underwaterBlur.Size = 0
underwaterBlur.Enabled = true
underwaterBlur.Parent = Lighting

-- water overlay: a faint teal body + four dark edge gradients (a vignette). It
-- replaces the old flat 38% teal frame and sits BELOW the HUD (DisplayOrder -1).
local overlayParts: { { frame: Frame, shown: number } } = {}
do
	local gui = Instance.new("ScreenGui")
	gui.Name = "SubmergedOverlay"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = -1
	gui.Parent = player:WaitForChild("PlayerGui")
	local body = Instance.new("Frame")
	body.Size = UDim2.fromScale(1, 1)
	body.BackgroundColor3 = Color3.fromRGB(10, 60, 72)
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Parent = gui
	table.insert(overlayParts, { frame = body, shown = WATER_BODY })
	local function edge(size: UDim2, pos: UDim2, rotation: number)
		local f = Instance.new("Frame")
		f.Size = size
		f.Position = pos
		f.BackgroundColor3 = Color3.fromRGB(2, 16, 22)
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.Parent = gui
		local g = Instance.new("UIGradient")
		g.Rotation = rotation
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
		g.Parent = f
		table.insert(overlayParts, { frame = f, shown = WATER_EDGE })
	end
	edge(UDim2.fromScale(1, 0.32), UDim2.fromScale(0, 0), 90)      -- top
	edge(UDim2.fromScale(1, 0.32), UDim2.fromScale(0, 0.68), -90)  -- bottom
	edge(UDim2.fromScale(0.22, 1), UDim2.fromScale(0, 0), 0)       -- left
	edge(UDim2.fromScale(0.22, 1), UDim2.fromScale(0.78, 0), 180)  -- right
end

local deepCC = Lighting:WaitForChild("DeepColorCorrection", 10)
local deepBloom = Lighting:WaitForChild("DeepBloom", 10)
local deepAtmo = Lighting:WaitForChild("DeepAtmosphere", 10)

local function applyGrade(g: Grade, seconds: number, delaySeconds: number?)
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 0, false, delaySeconds or 0)
	local function tween(inst: Instance?, goal: { [string]: any })
		if inst then TweenService:Create(inst, info, goal):Play() end
	end
	tween(deepCC, g.cc)
	tween(deepBloom, g.bloom)
	tween(deepAtmo, g.atmo)
	tween(Lighting, { Ambient = g.ambient })
	tween(underwaterBlur, { Size = g.blur })
	for _, p in ipairs(overlayParts) do
		tween(p.frame, { BackgroundTransparency = g.water and p.shown or 1 })
	end
end

local mainPowerOn = false
local submergedNow = false
local currentGrade = ""
local function refreshGrade(seconds: number, delaySeconds: number?)
	local name = submergedNow and "underwater" or (mainPowerOn and "main" or "emergency")
	if name == currentGrade then return end
	currentGrade = name
	applyGrade(GRADES[name], seconds, delaySeconds)
end
refreshGrade(0)

Net.Event("PowerUpdate").OnClientEvent:Connect(function(state)
	if type(state) ~= "table" then return end
	local on = state.mainPower == true
	if on == mainPowerOn then return end
	mainPowerOn = on
	-- the work lamps strike outward from the engine room over ~3 s: warm up with them
	if on then refreshGrade(2.6, 0.4) else refreshGrade(0.6) end
end)

-- ---------------------------------------------------------------------------
-- World animation (client-only visuals on server-built parts)
--   * bulkhead doors slide into the corridor wall on the Open attribute
--   * the generator flywheel spins up while Running
--   * instrument LEDs blink and sonar scopes sweep
-- ---------------------------------------------------------------------------
local DOOR_SLIDE = 7.5
local function bindDoor(door: Instance)
	if not door:IsA("BasePart") then return end
	task.spawn(function()
		local leaf = door:WaitForChild("DD_DoorLeaf", 20)
		if not (leaf and leaf:IsA("BasePart")) then return end
		local closed = leaf.CFrame
		local open = closed + Vector3.new(0, 0, DOOR_SLIDE)
		local function apply(seconds: number)
			local goal = (door:GetAttribute("Open") == true) and open or closed
			if seconds <= 0 then
				leaf.CFrame = goal
			else
				TweenService:Create(leaf, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { CFrame = goal }):Play()
			end
		end
		apply(0)
		door:GetAttributeChangedSignal("Open"):Connect(function() apply(0.85) end)
	end)
end
for _, door in ipairs(CollectionService:GetTagged("BulkheadDoor")) do bindDoor(door) end
CollectionService:GetInstanceAddedSignal("BulkheadDoor"):Connect(bindDoor)

local generatorPart: BasePart? = nil
local flywheel: BasePart? = nil
local flySpeed = 0
local blinkNext: { [Instance]: number } = {}
local function addBlink(led: Instance) blinkNext[led] = os.clock() + math.random() * 3 end
for _, led in ipairs(CollectionService:GetTagged("DD_Blink")) do addBlink(led) end
CollectionService:GetInstanceAddedSignal("DD_Blink"):Connect(addBlink)
CollectionService:GetInstanceRemovedSignal("DD_Blink"):Connect(function(led) blinkNext[led] = nil end)
local blinkTimer = 0

-- tower viewports: on Sighting, a black mass eclipses the glass with faint lights on its flank
local function bindTowerWindow(view: Instance)
	view:GetAttributeChangedSignal("Sighting"):Connect(function()
		local lights = {}
		local band: UIGradient?
		for _, d in ipairs(view:GetDescendants()) do
			if d.Name == "DD_SightLight" and d:IsA("GuiObject") then table.insert(lights, d) end
			if d.Name == "Band" and d:IsA("UIGradient") then band = d end
		end
		local DURATION = 18
		local t0 = os.clock()
		local conn: RBXScriptConnection
		conn = RunService.Heartbeat:Connect(function()
			local u = (os.clock() - t0) / DURATION
			if u >= 1 then
				conn:Disconnect()
				for _, l in ipairs(lights) do l.BackgroundTransparency = 1 end
				if band then band.Offset = Vector2.new(-1, 0) end
				return
			end
			local centre = 2 * u - 1
			if band then band.Offset = Vector2.new(centre, 0) end
			for _, l in ipairs(lights) do
				local i = l:GetAttribute("Index") or 1
				local x = 0.5 + centre + (i - 3) * 0.06
				local y = 0.5 + math.sin(u * 3 + i) * 0.04 + (i - 3) * 0.05
				l.Position = UDim2.fromScale(x, y)
				-- fade out before the round rim, since a gui frame isn't clipped by it
				local edge = math.clamp((0.46 - math.sqrt((x - 0.5) ^ 2 + (y - 0.5) ^ 2)) / 0.1, 0, 1)
				l.BackgroundTransparency = 1 - 0.62 * edge * (0.75 + math.sin(os.clock() * 1.4 + i) * 0.25)
			end
		end)
	end)
end
for _, v in ipairs(CollectionService:GetTagged("DD_TowerWindow")) do bindTowerWindow(v) end
CollectionService:GetInstanceAddedSignal("DD_TowerWindow"):Connect(bindTowerWindow)

-- the creature's limbs writhe; its lure breathes slowly, and quickens when it hunts
local creatureModel: Instance? = nil
local creatureStrands: { Beam } = {}
local lureGlow: PointLight? = nil
local function animateCreature(now: number)
	local model = Workspace:FindFirstChild("Creature")
	if model ~= creatureModel then
		creatureModel = model
		creatureStrands = {}
		lureGlow = nil
	end
	if not (model and model:IsA("Model")) then return end
	local body = model.PrimaryPart
	if not body then return end
	if #creatureStrands == 0 then
		for _, c in ipairs(body:GetChildren()) do
			if c:IsA("Beam") and c:GetAttribute("Sway") then table.insert(creatureStrands, c) end
		end
		local lure = body:FindFirstChild("DD_Lure")
		local g = lure and lure:FindFirstChild("DD_LureGlow")
		if g and g:IsA("PointLight") then lureGlow = g end
	end
	local cam = Workspace.CurrentCamera
	if not cam or (cam.CFrame.Position - body.Position).Magnitude > 110 then return end
	for _, b in ipairs(creatureStrands) do
		local sway = b:GetAttribute("Sway") or 0
		local phase = b:GetAttribute("Phase") or 0
		b.CurveSize0 = (b:GetAttribute("C0") or 0) + math.sin(now * 1.3 + phase) * sway
		b.CurveSize1 = (b:GetAttribute("C1") or 0) + math.cos(now * 0.9 + phase * 1.7) * sway * 0.8
	end
	if lureGlow then
		local hunting = model:GetAttribute("State") == "hunting"
		lureGlow.Brightness = hunting and (1.7 + math.sin(now * 9) * 0.9) or (1.2 + math.sin(now * 1.2) * 0.5)
	end
end

RunService.Heartbeat:Connect(function(dt: number)
	animateCreature(os.clock())
	blinkTimer += dt
	if not flywheel and blinkTimer >= 0.2 then
		for _, p in ipairs(CollectionService:GetTagged("Interactable")) do
			if p:GetAttribute("Kind") == "generator" and p:IsA("BasePart") then
				local f = p.Parent and p.Parent:FindFirstChild("DD_Dressing")
				local w = f and f:FindFirstChild("DD_GFlywheel")
				if w and w:IsA("BasePart") then flywheel = w ; generatorPart = p end
				break
			end
		end
	end
	if flywheel and generatorPart then
		local target = (generatorPart:GetAttribute("Running") == true) and 7 or 0
		flySpeed += (target - flySpeed) * math.clamp(dt * 0.6, 0, 1)
		if flySpeed > 0.02 then
			flywheel.CFrame *= CFrame.Angles(flySpeed * dt, 0, 0)
		end
	end
	local cam = Workspace.CurrentCamera
	for _, sweep in ipairs(CollectionService:GetTagged("DD_SonarSweep")) do
		if sweep:IsA("GuiObject") then sweep.Rotation = (sweep.Rotation + dt * 80) % 360 end
	end
	if blinkTimer >= 0.2 and cam then
		blinkTimer = 0
		local now = os.clock()
		for led, nextAt in pairs(blinkNext) do
			if now >= nextAt and led:IsA("GuiObject") then
				led.BackgroundTransparency = (led.BackgroundTransparency < 0.5) and 0.85 or 0
				blinkNext[led] = now + 0.4 + math.random() * 2.6
			end
		end
	end
end)

local function localSectionAndLevel(): (number?, number)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil, 0 end
	local section = SectionData.SectionAtPosition(hrp.Position)
	return section, levels[section] or 0
end

-- Under the surface: motes hanging in the water around the camera + a breath of
-- bubbles every few seconds. Both are off above water.
local moteVolume = decorPart("UnderwaterMotes", Vector3.new(18, 10, 22), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic, 1, Workspace)
local motes = Instance.new("ParticleEmitter")
motes.Texture = SOFT_DOT
motes.Shape = Enum.ParticleEmitterShape.Box
motes.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
motes.Rate = 34
motes.Lifetime = NumberRange.new(3, 6)
motes.Speed = NumberRange.new(0.05, 0.25)
motes.SpreadAngle = Vector2.new(180, 180)
motes.Drag = 0.5
motes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.2, 0.09), NumberSequenceKeypoint.new(0.8, 0.09), NumberSequenceKeypoint.new(1, 0) })
motes.Transparency = NumberSequence.new(0.3)
motes.Color = ColorSequence.new(Color3.fromRGB(170, 215, 220))
motes.LightInfluence = 0.55
motes.Enabled = false
motes.Parent = moteVolume

local breath = Instance.new("ParticleEmitter")
breath.Texture = SOFT_DOT
breath.Rate = 0
breath.Lifetime = NumberRange.new(1.2, 2.2)
breath.Speed = NumberRange.new(1.2, 2.6)
breath.SpreadAngle = Vector2.new(24, 24)
breath.EmissionDirection = Enum.NormalId.Top
breath.Acceleration = Vector3.new(0, 3, 0)
breath.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 0.2) })
breath.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0.9) })
breath.Color = ColorSequence.new(Color3.fromRGB(205, 228, 232))
breath.LightInfluence = 0.4
local mouth = Instance.new("Attachment") -- just under the camera (the volume sits 5 studs ahead of it)
mouth.Name = "MouthAt"
mouth.Position = Vector3.new(0, 0.1, 4.2)
mouth.Parent = moteVolume
breath.Parent = mouth
local nextBreath = 0

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	local camera = Workspace.CurrentCamera
	local camX = camera and camera.CFrame.Position.X or 0

	-- animate the water near the camera: a gentle bob, the foam riding it, debris drifting
	for section, d in pairs(decor) do
		if d.level >= 1 and math.abs(d.cx - camX) < 75 then
			local bob = math.sin(now * 1.3 + section) * 0.07
			local y = d.surfaceY + bob
			d.surface.CFrame = CFrame.new(d.cx, y, 0)
			for _, f in ipairs(d.foam) do
				f.part.CFrame = CFrame.new(d.cx + f.x, y + 0.17, f.z)
			end
			if d.level >= 3 and d.level <= 96 then
				for _, b in ipairs(d.debris) do
					b.part.CFrame = CFrame.new(
						b.x + math.sin(now * 0.07 + b.phase) * 1.3,
						y + 0.15 + b.h * 0.2,
						b.z + math.cos(now * 0.05 + b.phase) * 1.1
					) * CFrame.Angles(math.sin(now * 0.7 + b.phase) * 0.05, b.yaw + now * 0.015, math.cos(now * 0.6 + b.phase) * 0.05)
				end
			end
		end
	end

	-- submerged: head below the water surface of the player's section
	local submerged = false
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local section, level = localSectionAndLevel()
		if section then
			submerged = head.Position.Y < SectionData.LevelToWaterY(level)
		end
	end
	player:SetAttribute("Submerged", submerged)  -- read by AudioManager for breathing
	if submerged ~= submergedNow then
		submergedNow = submerged
		SoundService.AmbientReverb = submerged and Enum.ReverbType.UnderWater or Enum.ReverbType.NoReverb
		refreshGrade(submerged and 0.25 or 0.9)  -- snap under, surface slowly
		motes.Enabled = submerged
		if submerged then
			breath:Emit(14) -- the gasp going under
			nextBreath = now + 2.5
		end
	end
	if submerged and camera then
		moteVolume.CFrame = camera.CFrame * CFrame.new(0, -0.6, -5)
		if now >= nextBreath then
			breath:Emit(5 + math.random(0, 5))
			nextBreath = now + 2.6 + math.random() * 2.4
		end
	end
end)
