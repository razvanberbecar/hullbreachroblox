--!strict
-- MonetizationData.lua  →  ModuleScript in ReplicatedStorage/Shared
-- =============================================================================
-- All monetization config in one place. Everything is cosmetic or content-
-- expanding — nothing pay-to-win (horror players punish immersion-breaking
-- monetization). Fill the `id` fields with the real IDs created in the Creator
-- Hub; 0 means "not yet created" and the system safely no-ops.
-- =============================================================================

local MonetizationData = {}

-- Game passes (one-time) -----------------------------------------------------
MonetizationData.Passes = {
	supporter = {
		key = "supporter", id = 1898226685, price = 299, name = "Supporter Pass",
		desc = "Lobby badge + name on the survivors wall. No gameplay impact.",
	},
	nightmare = {
		key = "nightmare", id = 1898220673, price = 499, name = "Extended Nightmare Mode",
		desc = "Harder difficulty after completing the game: faster creature, fewer items, less oxygen.",
	},
	commentary = {
		key = "commentary", id = 1899348664, price = 199, name = "Developer Commentary",
		desc = "Submit your run and ask a developer to rate how you solved the map.",
	},
}

-- Developer products (repeatable) --------------------------------------------
MonetizationData.Products = {
	hint = {
		key = "hint", id = 3607650035, price = 50, name = "Hint",
		desc = "A subtle environmental glow points toward your current objective.",
	},
	save_slot = {
		key = "save_slot", id = 3607650337, price = 99, name = "Extra Save Slot",
		desc = "An additional save slot for trying different endings.",
	},
}

-- Cosmetics (lobby) ----------------------------------------------------------
-- flashlight skins set the beam Color3; suit skins swap arm appearance.
MonetizationData.FlashlightSkins = {
	default = { key = "default", id = 0, price = 0,   color = Color3.fromRGB(255, 244, 214), name = "Standard Beam" },
	amber   = { key = "amber",   id = 3607650440, price = 99,  color = Color3.fromRGB(255, 190, 120), name = "Amber Beam" },
	cold    = { key = "cold",    id = 3607650551, price = 99,  color = Color3.fromRGB(180, 220, 255), name = "Cold Beam" },
	green   = { key = "green",   id = 3607650622, price = 99,  color = Color3.fromRGB(170, 255, 180), name = "Phosphor Beam" },
}

MonetizationData.SuitSkins = {
	default = { key = "default", id = 0, price = 0,   name = "Standard Diving Suit", color = Color3.fromRGB(180, 182, 188), material = Enum.Material.SmoothPlastic },
	rust    = { key = "rust",    id = 3607650765, price = 149, name = "Salvager Suit",        color = Color3.fromRGB(165, 96, 45),  material = Enum.Material.Fabric },
	deep    = { key = "deep",    id = 3607650902, price = 299, name = "Deep-Pressure Suit",   color = Color3.fromRGB(40, 55, 78),   material = Enum.Material.Metal },
}

MonetizationData.DeathAnimations = {
	default = { key = "default", id = 0, price = 0,   name = "Standard" },
	dragged = { key = "dragged", id = 3607651017, price = 149, name = "Dragged Under" },
}

-- Difficulty overrides applied when the Nightmare pass is owned + game beaten.
MonetizationData.Nightmare = {
	creatureSpeedMult = 1.25,
	detectionMult = 1.2,
	oxygenMult = 0.7,
	-- how many of each consumable to strip from the world in Nightmare (fewer items)
	removeConsumables = { battery = 1, oxygen_canister = 1, glow_stick = 1 },
}

-- Developer Commentary: the run-submission webhook is a SERVER-ONLY Roblox Secret
-- (key "dev_rating_webhook"), NOT stored here — this module replicates to clients, so a
-- URL here would leak. Set it in Creator Hub -> Secrets. See Server/MonetizationManager.

-- Public Discord invite shown to players after they submit a run (so they can find
-- the developer's reply). Leave blank to hide the invite line.
MonetizationData.DiscordInvite = ""

return MonetizationData
