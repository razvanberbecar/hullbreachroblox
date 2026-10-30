--!strict
-- LightingSetup.server.lua  →  Script in ServerScriptService/Server
-- =============================================================================
-- Phase 1: establish the Future-lighting mood. Phase 9 refines particles and
-- post-processing. Lighting properties replicate to clients automatically.
-- =============================================================================

local Lighting = game:GetService("Lighting")

-- Core lighting technology + mood ------------------------------------------
-- As of 2025-01-21 Roblox replaced Lighting.Technology with LightingStyle
-- (Future -> Realistic) plus PrioritizeLightingQuality. These are place settings
-- and can be restricted at runtime, so they're also set in Studio (they persist);
-- the pcalls guard against a runtime denial aborting the rest of the mood setup.
pcall(function() Lighting.LightingStyle = Enum.LightingStyle.Realistic end)
pcall(function() Lighting.PrioritizeLightingQuality = true end)
Lighting.Ambient = Color3.fromRGB(10, 17, 28)         -- deep navy fill (= WaterRenderer's air grades)
Lighting.OutdoorAmbient = Color3.fromRGB(2, 4, 8)     -- near-black exterior
Lighting.Brightness = 0.6
Lighting.ClockTime = 0                                 -- midnight
Lighting.GeographicLatitude = 0
Lighting.EnvironmentDiffuseScale = 0.2
Lighting.EnvironmentSpecularScale = 0.2
Lighting.GlobalShadows = true
Lighting.FogEnd = 120
Lighting.FogStart = 10
Lighting.FogColor = Color3.fromRGB(6, 16, 22)

local function ensure(class: string, name: string): Instance
	local inst = Lighting:FindFirstChild(name)
	if not inst then
		inst = Instance.new(class)
		inst.Name = name
		inst.Parent = Lighting
	end
	return inst
end

-- Strip the place's starter Lighting effects. Studio's default Atmosphere, Bloom,
-- SunRays and DepthOfField were stacking on top of the Deep* set below (two
-- Atmospheres fighting, two Blooms adding up, sun rays on the sea floor). Only
-- these exact defaults go: UnderwaterBlur (WaterRenderer) and DD_BrightnessCC
-- (MenuUI) are client-made and must stay.
for _, spec in ipairs({
	{ "Atmosphere", "Atmosphere" },
	{ "BloomEffect", "Bloom" },
	{ "SunRaysEffect", "SunRays" },
	{ "DepthOfFieldEffect", "DepthOfField" },
}) do
	local inst = Lighting:FindFirstChild(spec[2])
	if inst and inst.ClassName == spec[1] then inst:Destroy() end
end

-- Underwater haze
local atmosphere = ensure("Atmosphere", "DeepAtmosphere") :: Atmosphere
atmosphere.Density = 0.42
atmosphere.Offset = 0.1
atmosphere.Color = Color3.fromRGB(20, 50, 60)
atmosphere.Decay = Color3.fromRGB(10, 20, 28)
atmosphere.Glare = 0.1
atmosphere.Haze = 2.4

-- Post-processing -------------------------------------------------------------
-- These are the boot values = the EMERGENCY grade. WaterRenderer (client) blends
-- each player between the emergency / main power / underwater grades from here.
local cc = ensure("ColorCorrectionEffect", "DeepColorCorrection") :: ColorCorrectionEffect
cc.Brightness = -0.04
cc.Contrast = 0.22
cc.Saturation = -0.28
cc.TintColor = Color3.fromRGB(222, 218, 234)

-- The only Bloom. Threshold sits just under the neon lenses / LEDs / creature lure
-- so light sources get a soft halo, while lit walls (incl. the flashlight hotspot)
-- stay below it and don't wash out.
local bloom = ensure("BloomEffect", "DeepBloom") :: BloomEffect
bloom.Intensity = 1.0
bloom.Size = 28
bloom.Threshold = 0.9

local dof = ensure("DepthOfFieldEffect", "DeepDOF") :: DepthOfFieldEffect
dof.FarIntensity = 0.35
dof.FocusDistance = 14
dof.InFocusRadius = 18
dof.NearIntensity = 0

print("[HullBreach] Lighting configured (Future mode).")
