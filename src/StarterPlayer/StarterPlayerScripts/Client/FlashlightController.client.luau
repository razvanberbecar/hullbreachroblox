--!strict
-- FlashlightController.client.lua  →  LocalScript in StarterPlayerScripts/Client
-- =============================================================================
-- Renders the flashlight: a single focused circle of light cast from the camera,
-- plus a first-person in-hand model. Dedicated tool toggled with F
-- (InventoryUI -> FlashlightToggle -> BatteryManager). Server is authoritative;
-- BatteryUpdate(charge, max, on, flicker, hasLight, equipped):
--   on=beam lit (equipped AND charge>0); equipped=model in hand.
--
-- Design: two SpotLights at the camera -- a bright core hotspot and a wide, dimmer
-- spill -- plus light-only dust motes. The lights are ALWAYS Enabled and we drive
-- only their Brightness (0 = off). That
-- avoids Future lighting's "first-use hitch": toggling a light's Enabled makes the
-- engine spin up its pipeline the first time, leaving walls dark on the first
-- press. Always-enabled + a brief warm-up contribution = instant on, every time.
-- Origin is exactly at the camera (no forward offset) so it never lands inside a
-- wall/door up close. Shadows OFF so the player's own body can't black out the beam.
-- =============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))

local player = Players.LocalPlayer

print("[HullBreach] FlashlightController loaded — core+spill build v8")

-- Light source: an invisible part pinned to the camera each frame.
local lightPart = Instance.new("Part")
lightPart.Name = "FlashlightBeam"
lightPart.Size = Vector3.new(0.2, 0.2, 0.2)
lightPart.Transparency = 1
lightPart.CanCollide = false
lightPart.CanQuery = false
lightPart.CanTouch = false
lightPart.Anchored = true
lightPart.CastShadow = false
lightPart.Parent = Workspace

-- Two cones, both ALWAYS enabled (brightness drives on/off):
--   core  -- the bright hotspot
--   spill -- a wide, dimmer halo so walls and props read at the edge of the beam
--            (a lone 30-degree cone was a hard circle on black once every room got
--            its own lighting)
local CORE_BRIGHTNESS = 14
local SPILL_RATIO = 0.43
local spot = Instance.new("SpotLight")
spot.Name = "Core"
spot.Face = Enum.NormalId.Front
spot.Angle = 26
spot.Range = 60
spot.Brightness = 0
spot.Color = Color3.fromRGB(255, 244, 222)
spot.Shadows = false
spot.Enabled = true        -- stays enabled forever; we only change Brightness
spot.Parent = lightPart

local spill = Instance.new("SpotLight")
spill.Name = "Spill"
spill.Face = Enum.NormalId.Front
spill.Angle = 75
spill.Range = 32
spill.Brightness = 0
spill.Color = Color3.fromRGB(255, 230, 194)
spill.Shadows = false
spill.Enabled = true
-- on its own attachment a touch below the eye, like a torch held at chest height
local spillAtt = Instance.new("Attachment")
spillAtt.Name = "SpillOrigin"
spillAtt.Position = Vector3.new(0, -0.35, 0.3)
spillAtt.Parent = lightPart
spill.Parent = spillAtt

-- Dust hanging in the air: a volume of slow motes kept just ahead of the camera.
-- LightInfluence 1 = a mote only shows where light falls on it, so dust sparkles in
-- the beam (and glows faintly red by the emergency lanterns) instead of floating as
-- flat dots over everything.
local dustVolume = Instance.new("Part")
dustVolume.Name = "FlashlightDust"
dustVolume.Size = Vector3.new(10, 7, 16)
dustVolume.Transparency = 1
dustVolume.Anchored = true
dustVolume.CanCollide = false
dustVolume.CanQuery = false
dustVolume.CanTouch = false
dustVolume.CastShadow = false
dustVolume.Parent = Workspace

local dust = Instance.new("ParticleEmitter")
dust.Texture = "rbxasset://textures/particles/smoke_main.dds" -- a soft dot (the default texture is a star)
dust.Shape = Enum.ParticleEmitterShape.Box
dust.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
dust.Rate = 30
dust.Lifetime = NumberRange.new(4, 7)
dust.Speed = NumberRange.new(0.05, 0.3)
dust.SpreadAngle = Vector2.new(180, 180)
dust.Acceleration = Vector3.new(0, -0.06, 0)
dust.Drag = 0.6
dust.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.15, 0.045),
	NumberSequenceKeypoint.new(0.85, 0.045),
	NumberSequenceKeypoint.new(1, 0),
})
dust.Transparency = NumberSequence.new(0.35)
dust.LightInfluence = 1
dust.LightEmission = 0
dust.Brightness = 1.4
dust.Color = ColorSequence.new(Color3.fromRGB(255, 245, 230))
dust.Parent = dustVolume

-- First-person in-hand model (cosmetic), pivoted to a lower-LEFT camera offset so
-- the right hand stays free. Parts live in Workspace so first-person transparency
-- never hides them.
local VIEW_OFFSET = CFrame.new(-0.9, -0.8, -1.2) * CFrame.Angles(math.rad(-6), math.rad(-4), 0)
local COL = {
	metalDark = Color3.fromRGB(34, 37, 42),
	metal     = Color3.fromRGB(74, 80, 88),
	bezel     = Color3.fromRGB(120, 124, 130),
	rubber    = Color3.fromRGB(20, 22, 25),
	lensWarm  = Color3.fromRGB(255, 240, 210),
	ledRed    = Color3.fromRGB(220, 70, 60),
}

local viewModel = Instance.new("Model")
viewModel.Name = "FlashlightViewModel"

local root = Instance.new("Part")
root.Name = "Root"
root.Size = Vector3.new(0.2, 0.2, 0.2)
root.Transparency = 1
root.Anchored = true
root.CanCollide = false
root.CanQuery = false
root.CanTouch = false
root.CastShadow = false
root.Parent = viewModel
viewModel.PrimaryPart = root

local visParts: { {part: BasePart, vis: number} } = {}

local function vmPart(name: string, size: Vector3, color: Color3, material: Enum.Material, offset: CFrame, shape: Enum.PartType?, transparency: number?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	if shape then p.Shape = shape end
	p.Transparency = transparency or 0
	p.CFrame = root.CFrame * offset
	p.Parent = viewModel
	table.insert(visParts, { part = p, vis = transparency or 0 })
	return p
end

local function vmCyl(name: string, length: number, diameter: number, color: Color3, material: Enum.Material, pos: Vector3, transparency: number?): Part
	return vmPart(name, Vector3.new(length, diameter, diameter), color, material, CFrame.new(pos) * CFrame.Angles(0, math.rad(90), 0), Enum.PartType.Cylinder, transparency)
end

-- a proper torch: knurled rubber grip rings, a tapered neck into a flared head with
-- a bright bezel, a tail cap and a pocket clip
vmCyl("Body", 1.0, 0.30, COL.metalDark, Enum.Material.Metal, Vector3.new(0, 0, 0.20))
for i = 0, 4 do
	vmCyl("Knurl" .. i, 0.05, 0.33, COL.rubber, Enum.Material.Rubber, Vector3.new(0, 0, 0.30 + i * 0.08))
end
vmCyl("TailCap", 0.12, 0.33, COL.metal, Enum.Material.Metal, Vector3.new(0, 0, 0.74))
vmCyl("Neck", 0.12, 0.36, COL.metalDark, Enum.Material.Metal, Vector3.new(0, 0, -0.33))
vmCyl("Head", 0.26, 0.46, COL.metal, Enum.Material.Metal, Vector3.new(0, 0, -0.46))
vmCyl("Bezel", 0.05, 0.50, COL.bezel, Enum.Material.Metal, Vector3.new(0, 0, -0.60))
local lens = vmCyl("Lens", 0.04, 0.40, COL.lensWarm, Enum.Material.Glass, Vector3.new(0, 0, -0.615), 0.2)
vmPart("Clip", Vector3.new(0.05, 0.05, 0.55), COL.bezel, Enum.Material.Metal, CFrame.new(0.17, 0.02, 0.25))
vmPart("Switch", Vector3.new(0.08, 0.07, 0.14), COL.ledRed, Enum.Material.SmoothPlastic, CFrame.new(0, 0.14, 0.30))

viewModel.Parent = Workspace

local skin = player:GetAttribute("FlashlightColor")
if typeof(skin) == "Color3" then spot.Color = skin ; spill.Color = skin end

local state = { on = false, flicker = false, equipped = false, base = CORE_BRIGHTNESS }

-- Warm-up: briefly drive the beam at load so the Future-lighting + PBR shader
-- path compiles up front. Otherwise the FIRST real activation hitches for a
-- while. loadClock drives a short real-brightness kick, then it fades to nothing.
local loadClock = os.clock()

local function setVisible(visible: boolean)
	for _, e in ipairs(visParts) do
		e.part.Transparency = visible and e.vis or 1
	end
end
setVisible(false)

local function setLensGlow(lit: boolean)
	lens.Material = lit and Enum.Material.Neon or Enum.Material.Glass
end

Net.Event("BatteryUpdate").OnClientEvent:Connect(function(_charge, _max, on, flicker, _hasLight, equipped)
	state.on = on == true
	state.flicker = flicker == true
	state.equipped = equipped == true
	setVisible(state.equipped)
	setLensGlow(state.on)
	local cam = Workspace.CurrentCamera
	if state.equipped and cam then
		viewModel:PivotTo(cam.CFrame * VIEW_OFFSET)
	end
end)

player:GetAttributeChangedSignal("FlashlightColor"):Connect(function()
	local c = player:GetAttribute("FlashlightColor")
	if typeof(c) == "Color3" then spot.Color = c ; spill.Color = c end
end)

-- Track the camera AFTER it is positioned each frame, and drive brightness only.
-- The torch is in a hand, not on your eyes: its aim trails quick turns slightly
-- (~60 ms) and the model bobs with walking speed.
local lagRot: CFrame? = nil
local bobT = 0
-- near a surface the beam dims (up to ~65%) so a wall or a glossy screen at point
-- blank doesn't blow out into a white disc
local nearParams = RaycastParams.new()
nearParams.FilterType = Enum.RaycastFilterType.Exclude
nearParams.IgnoreWater = true
local NEAR_DIST = 6
RunService:BindToRenderStep("FlashlightTrack", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
	local cam = Workspace.CurrentCamera
	if not cam then return end
	local camCF = cam.CFrame
	local rot = camCF - camCF.Position
	lagRot = if lagRot then lagRot:Lerp(rot, math.clamp(dt * 16, 0, 1)) else rot
	local aim = CFrame.new(camCF.Position) * (lagRot :: CFrame)
	lightPart.CFrame = aim
	dustVolume.CFrame = camCF * CFrame.new(0, -0.5, -9)
	if state.equipped then
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local speed = (hrp and hrp:IsA("BasePart")) and hrp.AssemblyLinearVelocity.Magnitude or 0
		bobT += dt * math.clamp(speed, 0, 22) * 0.55
		local amp = math.clamp(speed / 14, 0, 1.4)
		local bob = CFrame.new(math.sin(bobT) * 0.025 * amp, -math.abs(math.cos(bobT)) * 0.03 * amp, 0)
		viewModel:PivotTo(aim * VIEW_OFFSET * bob)
	end
	local b: number
	if state.on then
		b = state.flicker and ((math.random() < 0.25) and 0.6 or state.base) or state.base
	else
		-- pre-warm so the first real press is instant: a brief real kick at load
		-- (forces the lit-spotlight + PBR shader path to compile), then off.
		local since = os.clock() - loadClock
		if since < 0.45 then
			b = 2
		elseif since < 3 then
			b = 0.05
		else
			b = 0
		end
	end
	if b > 0.1 then
		local ignore: { Instance } = { viewModel, lightPart, dustVolume }
		if player.Character then table.insert(ignore, player.Character) end
		nearParams.FilterDescendantsInstances = ignore
		local hit = Workspace:Raycast(aim.Position, aim.LookVector * NEAR_DIST, nearParams)
		if hit then
			b *= math.clamp(0.35 + 0.65 * (hit.Distance / NEAR_DIST), 0.35, 1)
		end
	end
	spot.Brightness = b
	spill.Brightness = b * SPILL_RATIO
end)
