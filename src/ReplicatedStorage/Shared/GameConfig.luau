--!strict
-- GameConfig.lua  →  ModuleScript in ReplicatedStorage/Shared
-- =============================================================================
-- Cross-cutting tunables that aren't specific to one data table. Edit here to
-- tune feel without touching logic. Section/item/creature/ending specifics live
-- in their own modules.
-- =============================================================================

local GameConfig = {}

-- Flooding -------------------------------------------------------------------
GameConfig.GlobalFloodRate   = 0.02   -- baseline level/sec added to every section
GameConfig.FloodTickInterval = 0.5    -- server flood simulation step
GameConfig.FloodSyncInterval = 2.0    -- how often FloodUpdate is broadcast (GDD: every 2s)
GameConfig.DrownLevel        = 80     -- water level in player's section that starts oxygen drain
GameConfig.SwimLevelMin      = 40     -- between these the player is "swimming" (slowed)
GameConfig.SwimLevelMax      = 80
GameConfig.SwimSlowFactor    = 0.60   -- movement multiplier while swimming (40% slower)

-- Oxygen ---------------------------------------------------------------------
GameConfig.OxygenMaxSeconds  = 30     -- base breath when fully submerged

-- Movement / sound -----------------------------------------------------------
GameConfig.WalkSpeed   = 14
GameConfig.CrouchSpeed = 7
GameConfig.RunSpeed    = 22
GameConfig.SoundEventInterval = 0.35  -- min seconds between footstep sound events

-- First-person -----------------------------------------------------------
GameConfig.ForceFirstPerson = true

-- Interaction ----------------------------------------------------------------
GameConfig.InteractDistance = 10      -- ProximityPrompt MaxActivationDistance default

-- Testing ---------------------------------------------------------------------
-- TEST AID: when true, the creature spawns but never moves, hunts, or kills.
-- Set back to false to restore normal creature behaviour.
GameConfig.FreezeCreature = false

-- Debug ----------------------------------------------------------------------
GameConfig.Debug = false              -- prints diagnostics; turn off for launch

return GameConfig
