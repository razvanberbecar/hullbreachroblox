--!strict
-- AudioManager.client.lua  →  LocalScript in StarterPlayerScripts/Client
-- =============================================================================
-- Phase 8: the most important system. Builds every Sound layer and drives its
-- volume/pitch from game state. Sound is both atmosphere AND the game's UI —
-- the player reads danger by ear. Asset IDs live in Shared/SoundData (default
-- silent); fill them in to bring the mix to life. The LOGIC here is complete:
--
--   Ambient   : hull groan (everywhere), water rushing (∝ local flood),
--               electrical sparks + pipe hiss (random, positional via emitters).
--   Breathing : calm -> fast (creature within 40) -> panicked (hunting);
--               replaced by heartbeat while hiding.
--   Creature  : 3-tier by distance (rumble / dragging / breathing) + the
--               hunting "2s silence then charge" sting.
-- =============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SectionData = require(Shared:WaitForChild("SectionData"))
local CreatureData = require(Shared:WaitForChild("CreatureData"))
local SoundData = require(Shared:WaitForChild("SoundData"))
local Net = require(Shared:WaitForChild("Net"))

local player = Players.LocalPlayer

-- Master group ---------------------------------------------------------------
local group = Instance.new("SoundGroup")  -- gameplay SFX
group.Name = "SFX"
group.Volume = 1
group.Parent = SoundService
local musicGroup = Instance.new("SoundGroup")  -- ambient / menu (Settings: Music)
musicGroup.Name = "Music"
musicGroup.Volume = 0.8
musicGroup.Parent = SoundService

local holder = Instance.new("Folder")
holder.Name = "DeepDescentAudio"
holder.Parent = player:WaitForChild("PlayerGui")

local function loop(name: string, volume: number): Sound
	local s = SoundData.Make(name, holder, { Looped = true, Volume = 0, SoundGroup = group })
	s.Volume = 0
	s:SetAttribute("hasAsset", SoundData.HasAsset(name))
	if SoundData.HasAsset(name) then s:Play() end
	s:SetAttribute("targetVolume", volume)
	return s
end

-- Looping layers (all start silent; play once an asset id is set) -------------
local hullGroan   = loop("hull_groan", 0.25)
local waterRush   = loop("water_rushing", 0.0)
local breathCalm  = loop("breathing_calm", 0.3)
local breathFast  = loop("breathing_fast", 0.0)
local breathPanic = loop("breathing_panic", 0.0)
local heartbeat   = loop("heartbeat", 0.0)
local crRumble    = loop("creature_rumble", 0.0)
local crDrag      = loop("creature_drag", 0.0)
local crBreath    = loop("creature_breath", 0.0)

local function ensurePlaying(s: Sound)
	if s:GetAttribute("hasAsset") and not s.IsPlaying then s:Play() end
end

-- State ----------------------------------------------------------------------
local levels: {[number]: number} = {}
local creatureState = CreatureData.State.Dormant
local creaturePos: Vector3? = nil
local prevCreatureState = creatureState

-- Player breathing windows: a waking-up gasp for the first 5s, then a 2s gasp
-- whenever the player has been submerged for more than 4s. Otherwise the heavy
-- breathing stays silent (creature-proximity fast/panic + hiding heartbeat are
-- handled separately below).
local breatheUntil = os.clock() + 5
local submergedStart: number? = nil
local gaspedThisDive = false

Net.Event("FloodUpdate").OnClientEvent:Connect(function(serverLevels)
	for s, l in pairs(serverLevels) do levels[s] = l end
end)

Net.Event("CreatureUpdate").OnClientEvent:Connect(function(info)
	creatureState = info.state
	creaturePos = info.position
end)

-- Hunting charge sting: 2s silence, then the charge.
local function onHunt()
	for _, s in ipairs({ hullGroan, waterRush, crRumble, crDrag, crBreath }) do
		s.Volume = 0
	end
	task.delay(CreatureData.ChargeSilenceSeconds, function()
		local charge = SoundData.Make("creature_charge", holder, { Volume = 1, SoundGroup = group })
		if SoundData.HasAsset("creature_charge") then charge:Play() end
	end)
end

-- Smoothly approach a target volume.
local function approach(s: Sound, target: number, dt: number, rate: number?)
	local r = rate or 3
	s.Volume += (target - s.Volume) * math.clamp(dt * r, 0, 1)
end

local function localLevel(): number
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return 0 end
	return levels[SectionData.SectionAtPosition(hrp.Position)] or 0
end

local function creatureDistance(): number
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp or not creaturePos then return math.huge end
	return (creaturePos - hrp.Position).Magnitude
end

RunService.Heartbeat:Connect(function(dt)
	for _, s in ipairs({ hullGroan, waterRush, breathCalm, breathFast, breathPanic, heartbeat, crRumble, crDrag, crBreath }) do
		ensurePlaying(s)
	end

	-- charge sting on entering hunting
	if creatureState ~= prevCreatureState then
		if creatureState == CreatureData.State.Hunting then onHunt() end
		prevCreatureState = creatureState
	end

	-- ambient
	approach(hullGroan, 0.25, dt)
	approach(waterRush, math.clamp(localLevel() / 100, 0, 1) * 0.6, dt)

	-- creature distance tiers — volume RISES as it gets closer so it's clearly
	-- announced by ear (distant rumble -> wet drag -> close breathing).
	local dist = creatureDistance()
	local hunting = creatureState == CreatureData.State.Hunting
	approach(crRumble, math.clamp((160 - dist) / 160, 0, 1) * 0.45, dt)
	approach(crDrag,   math.clamp((80 - dist) / 80, 0, 1) * 0.7, dt)
	approach(crBreath, math.clamp((32 - dist) / 32, 0, 1) * 1.0, dt, 4)

	-- breathing windows: spawn gasp (5s) + a 2s gasp after >4s submerged
	local nowC = os.clock()
	if player:GetAttribute("Submerged") == true then
		submergedStart = submergedStart or nowC
		if not gaspedThisDive and (nowC - submergedStart) > 4 then
			breatheUntil = nowC + 2
			gaspedThisDive = true
		end
	else
		submergedStart = nil
		gaspedThisDive = false
	end
	local breathing = nowC < breatheUntil

	-- breathing / heartbeat
	local hiding = player:GetAttribute("Hiding") == true
	if hiding then
		approach(heartbeat, 0.7, dt, 5)
		approach(breathCalm, 0, dt); approach(breathFast, 0, dt); approach(breathPanic, 0, dt)
	else
		approach(heartbeat, 0, dt, 5)
		local near = dist <= 40
		approach(breathPanic, hunting and 0.7 or 0, dt)
		approach(breathFast, (near and not hunting) and 0.5 or 0, dt)
		-- heavy/"calm" breathing only during the timed windows (not a constant loop)
		approach(breathCalm, (breathing and not near and not hunting) and 0.45 or 0, dt, 4)
	end
end)

-- Positional one-shots requested by the server (sparks, pipe hiss, etc.)
Net.Event("SoundCue").OnClientEvent:Connect(function(name: string, position: Vector3?, volume: number?)
	local parent = holder
	if position then
		local p = Instance.new("Part")
		p.Anchored = true; p.CanCollide = false; p.Transparency = 1
		p.CFrame = CFrame.new(position); p.Parent = workspace
		parent = p
		game:GetService("Debris"):AddItem(p, 5)
	end
	local s = SoundData.Make(name, parent, { Volume = volume or 0.5, SoundGroup = group })
	if SoundData.HasAsset(name) then s:Play() end
end)

print("[HullBreach] AudioManager ready (assign SoundData.Ids to hear it).")
