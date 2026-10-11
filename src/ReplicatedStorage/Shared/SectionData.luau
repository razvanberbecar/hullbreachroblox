--!strict
-- SectionData.lua  →  ModuleScript in ReplicatedStorage/Shared
-- =============================================================================
-- HULL BREACH — Single source of truth for the 9 submarine sections.
-- Geometry, flood behaviour, locks and adjacency live here so that the
-- MapBuilder, FloodManager, WaterRenderer and CreatureManager all agree on the
-- same physical layout. Coordinates are in studs, interior floor at Y = 0.
-- =============================================================================

local SectionData = {}

-- ----------------------------------------------------------------------------
-- Global layout constants (shared geometry contract)
-- ----------------------------------------------------------------------------
SectionData.INTERIOR_LENGTH = 48   -- along the X axis (bow -> stern)
SectionData.INTERIOR_WIDTH  = 24   -- along the Z axis
SectionData.INTERIOR_HEIGHT = 16   -- floor (Y=0) to ceiling (Y=16)
SectionData.WALL_THICKNESS  = 2
SectionData.SPACING         = 56   -- distance between section centres on X
SectionData.FLOOR_Y         = 0    -- interior floor world Y
SectionData.DOOR_WIDTH      = 8
SectionData.DOOR_HEIGHT     = 10

-- Water level (0-100) maps linearly from floor to ceiling.
function SectionData.LevelToWaterY(level: number): number
	local h = SectionData.INTERIOR_HEIGHT
	return SectionData.FLOOR_Y + (math.clamp(level, 0, 100) / 100) * h
end

-- Linear hull order along +X. The conning tower (7) is NOT in the hull line —
-- it sits vertically above the control room (5), so the hull is contiguous.
SectionData.HullOrder = {1, 2, 3, 4, 5, 6, 8, 9}

local hullSlot: {[number]: number} = {}
for slot, sec in ipairs(SectionData.HullOrder) do
	hullSlot[sec] = slot - 1 -- 0-based slot index on the X axis
end

-- Centre position of section `index`. Hull sections are spaced along +X by slot;
-- the conning tower (7) is placed above the control room (5), elevated.
function SectionData.SectionCenter(index: number): Vector3
	if index == 7 then
		local c5x = hullSlot[5] * SectionData.SPACING
		-- elevated above section 5's ceiling (matches MapBuilder tower base)
		return Vector3.new(c5x, SectionData.INTERIOR_HEIGHT + SectionData.WALL_THICKNESS + 8, 0)
	end
	local slot = hullSlot[index] or (index - 1)
	return Vector3.new(slot * SectionData.SPACING, SectionData.INTERIOR_HEIGHT / 2, 0)
end

-- ----------------------------------------------------------------------------
-- Per-section definitions
--   floodRate   : water units gained per second under normal global flooding
--   startLevel  : water level (0-100) at game start
--   discovered  : whether the section escalates its flood rate once entered
--   lock        : nil | "keycard" | "mainPower"  (gate to enter / use)
--   refuge      : "vertical" = creature cannot reach (conning tower)
--   floodSafe   : creature exits hunting at this water threshold (see CreatureData)
-- ----------------------------------------------------------------------------
SectionData.Sections = {
	[1] = {
		id = "forward_torpedo", name = "Forward Torpedo Room", index = 1,
		floodRate = 0.04, startLevel = 12, escalates = false, lock = nil,
		creatureCanEnter = false, -- creature never starts/patrols into the bow until alerted
		isStart = true,
		desc = "Four torpedo tubes, crew bunks. Player wakes here, ankle-deep water.",
	},
	[2] = {
		id = "crew_berthing", name = "Crew Berthing", index = 2,
		floodRate = 0.05, startLevel = 4, escalates = false, lock = nil,
		floodsAfterMainPower = true,
		creatureCanEnter = true,
		desc = "Rows of bunks and lockers. First hiding locker here.",
	},
	[3] = {
		id = "galley", name = "Galley & Mess Hall", index = 3,
		floodRate = 0.05, startLevel = 6, escalates = false, lock = nil,
		creatureCanEnter = true,
		desc = "Kitchen and dining area. First major sound event triggers here.",
	},
	[4] = {
		id = "officers_quarters", name = "Officers Quarters", index = 4,
		floodRate = 0.05, startLevel = 5, escalates = false, lock = "keycard",
		creatureCanEnter = true,
		desc = "Captain's room, locked until keycard found in sonar room. Holds the fuse.",
	},
	[5] = {
		id = "control_room", name = "Control Room", index = 5,
		floodRate = 0.03, startLevel = 8, escalates = false, lock = nil,
		creatureCanEnter = true, isHub = true,
		desc = "Largest open space. Ballast panel, sonar console, central junction.",
	},
	[6] = {
		id = "sonar_radio", name = "Sonar & Radio Rooms", index = 6,
		floodRate = 0.04, startLevel = 7, escalates = false, lock = nil,
		radioLock = "mainPower", -- radio room sub-area unlocks with main power
		creatureCanEnter = true,
		desc = "Sonar room holds the keycard. Radio room (SOS) unlocks with main power.",
	},
	[7] = {
		id = "conning_tower", name = "Conning Tower", index = 7,
		floodRate = 0.04, startLevel = 0, escalates = false, lock = nil,
		creatureCanEnter = false, refuge = "vertical", optional = true,
		aboveSection = 5, -- vertically above the control room
		desc = "Vertical ladder refuge above control room. Creature cannot climb.",
	},
	[8] = {
		id = "engine_room", name = "Engine Room", index = 8,
		floodRate = 0.06, startLevel = 6, escalates = true, escalatedRate = 0.5,
		lock = nil, creatureCanEnter = true, hasGenerator = true,
		desc = "Darkest section. Generator restores main power. Floods rapidly once discovered.",
	},
	[9] = {
		id = "aft_torpedo", name = "Aft Torpedo Room", index = 9,
		floodRate = 0.10, startLevel = 40, escalates = false, lock = nil,
		creatureCanEnter = true, creatureOrigin = true, hasExteriorPassage = true,
		desc = "Most flooded (waist-deep at start). Creature patrols originate here.",
	},
}

SectionData.COUNT = 9

-- ----------------------------------------------------------------------------
-- Adjacency graph. Sections 1..9 are linear along the hull; the conning tower
-- (7) connects vertically to the control room (5). This is used for sound
-- propagation ("two sections away") and creature pathing fallbacks.
-- ----------------------------------------------------------------------------
SectionData.Adjacency = {
	[1] = {2},
	[2] = {1, 3},
	[3] = {2, 4},
	[4] = {3, 5},
	[5] = {4, 6, 7},
	[6] = {5, 8},
	[7] = {5},
	[8] = {6, 9},
	[9] = {8},
}

-- Linear hull order the creature patrols along (aft -> bow). Excludes tower.
SectionData.PatrolOrder = {9, 8, 6, 5, 4, 3, 2, 1}

-- Number of "section hops" between two sections (BFS over Adjacency).
function SectionData.Distance(a: number, b: number): number
	if a == b then return 0 end
	local visited = { [a] = true }
	local frontier = { a }
	local depth = 0
	while #frontier > 0 do
		depth += 1
		local next = {}
		for _, node in ipairs(frontier) do
			for _, n in ipairs(SectionData.Adjacency[node] or {}) do
				if n == b then return depth end
				if not visited[n] then
					visited[n] = true
					table.insert(next, n)
				end
			end
		end
		frontier = next
	end
	return math.huge
end

-- Which section index contains a world position (nearest centre on X).
function SectionData.SectionAtPosition(pos: Vector3): number
	local best, bestDist = 1, math.huge
	for i = 1, SectionData.COUNT do
		if i ~= 7 then -- tower handled separately by height
			local c = SectionData.SectionCenter(i)
			local d = math.abs(pos.X - c.X)
			if d < bestDist then best, bestDist = i, d end
		end
	end
	-- conning tower if high above the control room
	if pos.Y > SectionData.INTERIOR_HEIGHT + 4 then
		local c5 = SectionData.SectionCenter(5)
		if math.abs(pos.X - c5.X) < SectionData.SPACING then
			return 7
		end
	end
	return best
end

return SectionData
