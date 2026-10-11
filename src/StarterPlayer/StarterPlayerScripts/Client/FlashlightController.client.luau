--!strict
-- FlashlightController.client.lua  →  LocalScript in StarterPlayerScripts/Client
-- =============================================================================
-- Renders the flashlight: a single focused circle of light cast from the camera,
-- plus a first-person in-hand model. Dedicated tool toggled with F
-- (InventoryUI -> FlashlightToggle -> BatteryManager). Server is authoritative;
-- BatteryUpdate(charge, max, on, flicker, hasLight, equipped):
--   on=beam lit (equipped AND charge>0); equipped=model in hand.
--
-- Design: ONE SpotLight at the camera -> a clean bright circle wherever you look.
-- The light is ALWAYS Enabled and we drive only its Brightness (0 = off). That
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

print("[HullBreach] FlashlightController loaded — single-circle build v7")

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

-- The single beam -> a clean circle. ALWAYS enabled; brightness drives on/off.
local spot = Instance.new("SpotLight")
spot.Face = Enum.NormalId.Front
spot.Angle = 30
spot.Range = 55
spot.Brightness = 0
spot.Color = Color3.fromRGB(255, 244, 214)
spot.Shadows = false
spot.Enabled = true        -- stays enabled forever; we only change Brightness
spot.Parent = lightPart

-- Dust motes drifting in the beam (subtle).
local dust = Instance.new("ParticleEmitter")
dust.Rate = 10
dust.Lifetime = NumberRange.new(2, 4)
dust.Speed = NumberRange.new(0.5, 1.5)
dust.SpreadAngle = Vector2.new(40, 40)
dust.Size = NumberSequence.new(0.06)
dust.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.6),
	NumberSequenceKeypoint.new(0.5, 0.85),
	NumberSequenceKeypoint.new(1, 1),
})
dust.Color = ColorSequence.new(Color3.fromRGB(220, 215, 200))
dust.Acceleration = Vector3.new(0, -0.4, 0)
dust.Enabled = false
dust.Parent = lightPart

-- First-person in-hand model (cosmetic), pivoted to a lower-LEFT camera offset so
-- the right hand stays free. Parts live in Workspace so first-person transparency
-- never hides them.
local VIEW_OFFSET = CFrame.new(-0.9, -0.8, -1.2) * CFrame.Angles(math.rad(-6), math.rad(-4), 0)
local COL = {
	metalDark = Color3.fromRGB(40, 44, 50),
	metal     = Color3.fromRGB(74, 80, 88),
	rubber    = Color3.fromRGB(22, 24, 28),
	lensWarm  = Color3.fromRGB(255, 244, 214),
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

vmCyl("Body", 1.0, 0.30, COL.metalDark, Enum.Material.Metal, Vector3.new(0, 0, 0.20))
vmCyl("Grip", 0.36, 0.33, COL.rubber, Enum.Material.Plastic, Vector3.new(0, 0, 0.42))
vmCyl("Head", 0.28, 0.46, COL.metal, Enum.Material.Metal, Vector3.new(0, 0, -0.40))
local lens = vmCyl("Lens", 0.05, 0.40, COL.lensWarm, Enum.Material.Glass, Vector3.new(0, 0, -0.54), 0.2)
vmPart("Switch", Vector3.new(0.08, 0.07, 0.14), COL.ledRed, Enum.Material.SmoothPlastic, CFrame.new(0, 0.14, 0.30))

viewModel.Parent = Workspace

local skin = player:GetAttribute("FlashlightColor")
if typeof(skin) == "Color3" then spot.Color = skin end

local state = { on = false, flicker = false, equipped = false, base = 5 }

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
	dust.Enabled = state.on
	setVisible(state.equipped)
	setLensGlow(state.on)
	local cam = Workspace.CurrentCamera
	if state.equipped and cam then
		viewModel:PivotTo(cam.CFrame * VIEW_OFFSET)
	end
end)

player:GetAttributeChangedSignal("FlashlightColor"):Connect(function()
	local c = player:GetAttribute("FlashlightColor")
	if typeof(c) == "Color3" then spot.Color = c end
end)

-- Track the camera AFTER it is positioned each frame, and drive brightness only.
RunService:BindToRenderStep("FlashlightTrack", Enum.RenderPriority.Camera.Value + 1, function()
	local cam = Workspace.CurrentCamera
	if not cam then return end
	lightPart.CFrame = cam.CFrame
	if state.equipped then
		viewModel:PivotTo(cam.CFrame * VIEW_OFFSET)
	end
	if state.on then
		spot.Brightness = state.flicker and ((math.random() < 0.25) and 0.6 or state.base) or state.base
	else
		-- pre-warm so the first real press is instant: a brief real kick at load
		-- (forces the lit-spotlight + PBR shader path to compile), then off.
		local since = os.clock() - loadClock
		if since < 0.45 then
			spot.Brightness = 2
		elseif since < 3 then
			spot.Brightness = 0.05
		else
			spot.Brightness = 0
		end
	end
end)
