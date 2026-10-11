--!strict
-- ItemData.lua  →  ModuleScript in ReplicatedStorage/Shared
-- =============================================================================
-- All item definitions: ids, display names, slot behaviour, spawn locations.
-- The inventory is exactly 4 slots (intentional — never increase). Items flagged
-- noSlot are tracked but do not occupy inventory (flashlight, journal pages).
-- =============================================================================

local ItemData = {}

ItemData.MAX_SLOTS = 4

-- category: "tool" | "key" | "consumable" | "lore"
-- stack:    how many can share one slot (1 = unique)
ItemData.Items = {
	flashlight = {
		id = "flashlight", name = "Flashlight", category = "tool",
		noSlot = true, -- always in hand, tracked by BatteryManager
		desc = "Always in hand. Battery drains slowly; flickers and dies if submerged too long.",
	},

	-- Key items (each takes one slot) ----------------------------------------
	keycard = {
		id = "keycard", name = "Keycard", category = "key", stack = 1,
		singleUse = true, spawnSection = 6,
		desc = "Opens the officers quarters. Found in the sonar room. Single use.",
	},
	fuse = {
		id = "fuse", name = "Ballast Fuse", category = "key", stack = 1,
		spawnSection = 4,
		desc = "Found in captain's quarters. Installed at the ballast panel (control room).",
	},
	pod_component = {
		id = "pod_component", name = "Escape Pod Component", category = "key", stack = 1,
		multi = 3, spawnSections = {1, 5, 8},
		desc = "Three are scattered across the sub. All three fill 3 of 4 slots.",
	},

	-- Consumables (take a slot) ----------------------------------------------
	battery = {
		id = "battery", name = "Battery", category = "consumable", stack = 1,
		charge = 50, spawnSections = {1, 3, 5, 8},
		desc = "Recharges the flashlight by 50%.",
	},
	glow_stick = {
		id = "glow_stick", name = "Glow Stick", category = "consumable", stack = 1,
		duration = 180, spawnSections = {2},
		desc = "Place on the ground to light a room for 3 minutes. Cannot be retrieved.",
	},
	oxygen_canister = {
		id = "oxygen_canister", name = "Oxygen Canister", category = "consumable", stack = 1,
		oxygenBonus = 30, spawnSections = {3, 9},
		desc = "Extends the breath timer in flooded sections by 30 seconds.",
	},

	-- Auto-collected lore (no slot) ------------------------------------------
	journal_page = {
		id = "journal_page", name = "Captain's Journal Page", category = "lore",
		noSlot = true, multi = 6, spawnSections = {1, 2, 3, 4, 4, 6},
		desc = "Auto-collected. Six pages reveal the truth and unlock the secret endings.",
	},
}

-- The six journal pages, in narrative order, with the section each is found in.
ItemData.JournalPages = {
	[1] = { section = 1, title = "Captain's Log — I. Departure",
		text = "0600. We slipped our moorings before dawn under orders I am forbidden to enter in the official log. Our heading is down — far below any depth this boat was built to survive. The crew believe it is a salvage run. I have read the true orders, and I have not slept since." },
	[2] = { section = 2, title = "Captain's Log — II. The Descent",
		text = "We have passed our rated depth and kept going. The hull groans as the pressure works it, a long iron moan in the dark, and every man aboard has fallen silent to listen to it. Whatever waits at the bottom, the Navy will spend us all to reach it. I no longer believe we will all come back up." },
	[3] = { section = 3, title = "Captain's Log — III. Contact",
		text = "Sonar found it resting on the floor of the trench. It is no wreck — the shape is too deliberate, and it does not drift with the current the way debris should. It was not lost down here. It was left. And the moment our lamps touched it, I knew it had been waiting a very long time for someone foolish enough to come." },
	[4] = { section = 4, title = "Captain's Log — IV. Retrieval",
		text = "We have it aboard. The cargo is sealed in the aft hold, and I have forbidden any man to open it, though I cannot say why the order frightens me so. The compasses will not settle near it. Two of the crew have stopped speaking altogether. God forgive me — I knew, even as I gave the order, that it was never ours to take." },
	[5] = { section = 4, title = "Captain's Log — V. It Followed",
		text = "Something came up out of the dark with us. It is inside the hull now — I hear it move between the bulkheads when the boat falls still, patient and enormous. It is blind, and yet it finds every sound we make. It struck us once and drove us to the seabed. It did not crash us to kill us. It crashed us to keep what we stole from ever rising." },
	[6] = { section = 6, title = "Captain's Log — VI. The Truth",
		text = "I understand it now. It does not hunt from hunger or from rage — it only wants back the thing we carried up from the deep, what was ours by theft and never by right. Take the cargo to the breach in the stern, give it to the water, and it will let the living pass. Whoever finds this: do not carry it home. Some things are drowned so that the world above can keep breathing." },
}

-- Battery / flashlight tuning (BatteryManager reads this)
ItemData.Flashlight = {
	maxCharge = 100,
	drainPerSecond = 1 / 8,          -- 1 charge each 8 seconds
	submergedExtraDrain = 1 / 4,     -- additional drain when submerged > threshold
	submergedSeconds = 10,           -- seconds underwater before extra drain begins
	flickerBelow = 20,               -- charge level where flicker starts
}

return ItemData
