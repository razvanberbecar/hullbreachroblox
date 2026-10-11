--!strict
-- SoundData.lua  →  ModuleScript in ReplicatedStorage/Shared
-- =============================================================================
-- Named sound asset registry. IDs default to 0 (silent) so the game runs before
-- audio is sourced; Phase 8 fills these in with real rbxassetid:// values and
-- the AudioManager wires them to game state. Keeping them here means no logic
-- script hard-codes an asset id.
-- =============================================================================

local SoundData = {}

-- Fill these with "rbxassetid://<id>" during Phase 8 audio sourcing.
SoundData.Ids = {
	-- ambient
	hull_groan       = "rbxassetid://9126148927",     -- underwater sheet-metal creak (ProSoundEffects)
	water_rushing    = "rbxassetid://70460456004311", -- deep water rush
	electrical_spark = "rbxassetid://9116275998",     -- electrical burst/zap (ProSoundEffects)
	pipe_hiss        = "rbxassetid://117580991143452",-- pressurised air/steam hiss
	generator_hum    = "rbxassetid://83031465221433", -- engine/generator loop
	-- player
	breathing_calm   = "rbxassetid://139784298444442",-- slow tired breathing
	breathing_fast   = "rbxassetid://94952921557556", -- fast breathing
	breathing_panic  = "rbxassetid://100147087354736",-- shortness of breath / panic
	heartbeat        = "rbxassetid://5948090748",     -- heartbeat
	-- creature
	creature_rumble  = "rbxassetid://9116329971",     -- low tonal throb/rumble (ProSoundEffects)
	creature_drag    = "rbxassetid://9116830533",     -- metal screech/drag (ProSoundEffects)
	creature_breath  = "rbxassetid://9113586909",     -- eerie hollow breathing (ProSoundEffects)
	creature_charge  = "rbxassetid://9114630281",     -- deep growl/roar (ProSoundEffects)
	creature_startle = "rbxassetid://101811801256880",-- monster screech when it starts hunting (free Creator Store)
	creature_catch   = "rbxassetid://130990524400761",-- jumpscare when it catches you (free Creator Store)
	-- events
	splash           = "rbxassetid://110579558511983",-- water splash
	swim             = "rbxassetid://110579558511983",-- water movement while swimming (reuses splash)
	door_metal       = "rbxassetid://3908308607",     -- metal door slam
	generator_start  = "rbxassetid://1744635133",     -- machine startup
	sonar_ping       = "rbxassetid://135494291088230",-- sonar ping
	power_surge      = "rbxassetid://9116277954",     -- electrical surge (ProSoundEffects)
	structural_groan = "rbxassetid://9116829665",     -- large metal groan (ProSoundEffects)
}

-- Whether a named sound has a real (non-placeholder) asset assigned.
function SoundData.HasAsset(name: string): boolean
	local id = SoundData.Ids[name]
	return id ~= nil and id ~= "" and id ~= "rbxassetid://0"
end

-- Create (or reuse) a Sound under `parent` for a named id.
function SoundData.Make(name: string, parent: Instance, props: {[string]: any}?): Sound
	local existing = parent:FindFirstChild("Snd_" .. name)
	if existing and existing:IsA("Sound") then return existing end
	local s = Instance.new("Sound")
	s.Name = "Snd_" .. name
	-- Only assign a real asset id; leaving it blank avoids 404 spam while the
	-- sound library is still placeholder (rbxassetid://0).
	local id = SoundData.Ids[name]
	if id and id ~= "rbxassetid://0" then
		s.SoundId = id
	end
	if props then
		for k, v in pairs(props) do (s :: any)[k] = v end
	end
	s.Parent = parent
	return s
end

return SoundData
