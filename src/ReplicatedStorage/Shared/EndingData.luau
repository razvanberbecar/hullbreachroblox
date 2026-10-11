--!strict
-- EndingData.lua  →  ModuleScript in ReplicatedStorage/Shared
-- =============================================================================
-- The 6 (+2 secret) endings, their categories, trigger conditions and the
-- cutscene title cards. EndingManager evaluates `condition` flags against a
-- per-player progress table. Conditions are declarative so they can be checked
-- centrally and also drive the menu's Endings Log.
-- =============================================================================

local EndingData = {}

EndingData.Category = {
	Good = "good",
	Bad = "bad",
	Secret = "secret",
}

-- Each ending:
--   id, name, category
--   title    : on-screen title card text
--   blurb    : short cinematic description (used by cutscene + endings log)
--   secret   : true if hidden in the endings log until discovered
EndingData.Endings = {
	-- GOOD ---------------------------------------------------------------
	escape_pod = {
		id = "escape_pod", name = "Escape Pod", category = "good",
		title = "ESCAPE",
		blurb = "The pod launches. You watch the submarine sink further into the dark as you ascend.",
		requires = "All 3 escape pod components + launch from forward torpedo room.",
	},
	sos_signal = {
		id = "sos_signal", name = "SOS Signal", category = "good",
		title = "RESCUE",
		blurb = "A rescue submarine breaches the gloom. Hands pull you to safety.",
		requires = "Restore main power, broadcast from radio room, survive 8 minutes.",
	},
	surface_manually = {
		id = "surface_manually", name = "Surface Manually", category = "good",
		title = "DAWN",
		blurb = "The boat shudders and rises. Dawn light filters down through the periscope.",
		requires = "Install fuse, complete the ballast valve sequence.",
	},

	-- BAD ----------------------------------------------------------------
	drowned = {
		id = "drowned", name = "Drowned", category = "bad",
		title = "SILENCE",
		blurb = "The water takes you. You sink into the cold and the dark.",
		requires = "Water reaches maximum, or oxygen depletes while submerged.",
	},
	taken = {
		id = "taken", name = "Taken", category = "bad",
		title = "...",
		blurb = "Darkness. A sound too close. Then nothing.",
		requires = "The creature reaches you.",
	},
	sealed_in = {
		id = "sealed_in", name = "Sealed In", category = "bad",
		title = "SAFE",
		blurb = "The choice to stay safe became the choice to never leave.",
		requires = "Seal yourself in with no exit; oxygen depletes.",
	},
	the_deep = {
		id = "the_deep", name = "The Deep Took You", category = "bad",
		title = "THE DEEP",
		blurb = "You force yourself out through the torn hull into the black water. The cold closes in. The pressure does the rest.",
		requires = "Swim out through the hull breach in the aft torpedo room.",
	},

	-- SECRET -------------------------------------------------------------
	the_truth = {
		id = "the_truth", name = "The Truth", category = "secret", secret = true,
		title = "RETURNED",
		blurb = "You give back what was taken. The creature stills, and returns to the deep, at peace.",
		requires = "All 6 journal pages + return the cargo in the aft exterior section.",
	},
	hubris = {
		id = "hubris", name = "Hubris", category = "secret", secret = true,
		title = "TAKEN HOME",
		blurb = "You escaped with the cargo. Whatever it is, it was not meant to surface.",
		requires = "All 6 journal pages + take the cargo + escape via any good route.",
	},
}

-- Ordered list for the endings log display.
EndingData.Order = {
	"escape_pod", "sos_signal", "surface_manually",
	"drowned", "taken", "sealed_in", "the_deep",
	"the_truth", "hubris",
}

-- Tunables referenced by EndingManager
EndingData.SOS_SURVIVE_SECONDS = 2 * 60   -- 2 real-time minutes (tuned down from 8)
EndingData.BALLAST_SEQUENCE = {3, 1, 4, 2, 5}  -- valve order puzzle (1-5)
EndingData.FLOOD_MAX_LEVEL = 100          -- Drowned when a section maxes with player in it

return EndingData
