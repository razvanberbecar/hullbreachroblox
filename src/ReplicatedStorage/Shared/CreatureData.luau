--!strict
-- CreatureData.lua  →  ModuleScript in ReplicatedStorage/Shared
-- =============================================================================
-- Tuning for the creature: per-state speed, sound detection radius, audio tiers
-- and the rules for where it can and cannot go. The creature is blind and hunts
-- purely by sound. Keep it never fully visible — this data drives behaviour, not
-- appearance.
-- =============================================================================

local CreatureData = {}

-- State machine identifiers (shared with CreatureUpdate remote payloads)
CreatureData.State = {
	Dormant = "dormant",
	Alerted = "alerted",
	Hunting = "hunting",
}

-- Per-state movement + perception ------------------------------------------
CreatureData.States = {
	dormant = {
		speed = 8,              -- studs/second
		detectionRadius = 40,   -- studs; sound within this -> hunting
		detectionSections = 1,  -- also reacts to sounds within N section hops
		patrol = "linear",      -- aft <-> bow predictable
		patrolRange = nil,      -- whole hull
	},
	alerted = {
		speed = 18,             -- main power makes it noticeably faster + hungrier
		detectionRadius = 95,
		detectionSections = 3,
		patrol = "semi_random",
		patrolRange = {5, 9},   -- anchored near the generator (sections 5-9)
		anchorSection = 8,      -- generator hum pulls it here
	},
	hunting = {
		speed = 24,
		detectionRadius = 60,
		searchSeconds = 15,     -- search last-known position before giving up
		hideLingerSeconds = 10, -- if player hides + stays silent, linger this long then leave
	},
}

-- Water level (0-100) at/above which the creature refuses to enter a section
-- and immediately drops out of hunting when crossing the threshold.
CreatureData.FloodAvoidLevel = 60

-- Water muffles what the creature hears: a sound made in a flooded section is
-- detected at a reduced effective radius, scaling to (radius * this) at full flood.
CreatureData.WaterMaskFactor = 0.55

-- Always-on close-range sensing: if a player MOVES within this many studs of the
-- creature it catches them even while crouching. Kept small so crouch-sneaking is
-- safe UNLESS you're right next to it (crouch emits no footstep sound otherwise).
CreatureData.CloseSenseRadius = 5

-- Sound intensities a player action produces. CreatureManager compares these
-- against the active state's detection rules.
CreatureData.SoundIntensity = {
	crouch   = 0,    -- effectively silent
	walk     = 1,    -- low
	interact = 2,    -- medium / directional
	heartbeat= 2,    -- medium; only while hiding with mouse movement
	run      = 3,    -- high; triggers alerted/hunting
	splash   = 3,    -- high; falling into water
	swim     = 2,    -- medium; wading/swimming through water (replaces footsteps)
}

-- Intensity threshold (>=) that forces a Hunting transition when in range.
CreatureData.HuntTriggerIntensity = {
	dormant = 1,   -- any audible sound in range while dormant -> investigate/hunt
	alerted = 1,
}

-- Three-tier distance audio (player -> creature distance, in studs)
CreatureData.AudioTiers = {
	{ maxDist = 200, layer = "rumble",    volume = 0.10 }, -- far: felt more than heard
	{ maxDist = 90,  layer = "dragging",  volume = 0.40 }, -- medium: wet dragging
	{ maxDist = 35,  layer = "breathing", volume = 0.80 }, -- close: rhythmic breathing
}

-- Hunting charge: 2s of dead silence, then an explosive charge sound.
CreatureData.ChargeSilenceSeconds = 2.0

-- Server update rate for creature position sync to clients.
CreatureData.SyncInterval = 0.1

return CreatureData
