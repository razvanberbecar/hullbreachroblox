--!strict
-- MapBuilder.lua  →  ModuleScript in ServerScriptService/Server
-- =============================================================================
-- Phase 2: procedurally builds the entire submarine greybox at server start.
-- Nine sections laid end-to-end on the X axis, connected by short corridors with
-- sealable bulkhead doors. Conning tower rises above the control room. Every
-- interactable / pickup / light / water plane is tagged + attributed so later
-- phase managers (Flood, Power, Creature, Inventory, Ending, Interaction) can
-- find and drive them generically without hard-coded references.
--
-- Tags used (CollectionService):
--   "Submarine"      — root folder marker
--   "WaterPlane"     — per-section water; attr Section
--   "EmergencyLight" — red dormant lighting; attr Section
--   "MainLight"      — bright flicker lighting (off until main power); attr Section
--   "BulkheadDoor"   — sealable door; attrs SectionA, SectionB, Sealed(false)
--   "Interactable"   — has ProximityPrompt; attr Kind (generator/ballast/radio/
--                      pod_panel/sonar/safe/exterior/ladder/locker/captain_door/valve)
--   "Pickup"         — collectible item; attr ItemId (+ Slot for pod index)
--   "Journal"        — journal page; attr PageIndex
--   "HidingSpot"     — locker/panel the player can hide in; attr Section
-- =============================================================================

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SectionData = require(Shared:WaitForChild("SectionData"))
local ItemData = require(Shared:WaitForChild("ItemData"))
local ItemModels = require(script.Parent:WaitForChild("ItemModels"))

local MapBuilder = {}

-- ----------------------------------------------------------------------------
-- Palette (greybox — Phase 9 replaces with PBR)
-- ----------------------------------------------------------------------------
local C = {
	hull      = Color3.fromRGB(54, 60, 66),
	hullDark  = Color3.fromRGB(38, 42, 47),
	floor     = Color3.fromRGB(46, 50, 54),
	door      = Color3.fromRGB(86, 70, 40),
	doorSeal  = Color3.fromRGB(120, 40, 30),
	prop      = Color3.fromRGB(70, 74, 80),
	pickup    = Color3.fromRGB(220, 200, 90),
	journal   = Color3.fromRGB(210, 200, 170),
	console   = Color3.fromRGB(40, 60, 70),
	water     = Color3.fromRGB(20, 55, 70),
	hideSpot  = Color3.fromRGB(60, 55, 50),
	breach    = Color3.fromRGB(20, 25, 28),
}

local IL = SectionData.INTERIOR_LENGTH
local IW = SectionData.INTERIOR_WIDTH
local IH = SectionData.INTERIOR_HEIGHT
local WT = SectionData.WALL_THICKNESS
local DW = SectionData.DOOR_WIDTH
local DH = SectionData.DOOR_HEIGHT
local SPACING = SectionData.SPACING

local root: Folder

-- 0-based hull slot per section (tower 7 excluded from the linear hull).
local hullSlot: {[number]: number} = {}
for slot, sec in ipairs(SectionData.HullOrder) do
	hullSlot[sec] = slot - 1
end
local LAST_SLOT = #SectionData.HullOrder - 1

-- ----------------------------------------------------------------------------
-- Low-level part helpers
-- ----------------------------------------------------------------------------
local function part(props: {[string]: any}): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.Metal
	p.Color = C.hull
	for k, v in pairs(props) do
		(p :: any)[k] = v
	end
	return p
end

local function box(name, size: Vector3, pos: Vector3, color: Color3?, parent: Instance): Part
	local p = part({ Name = name, Size = size, Color = color or C.hull })
	p.CFrame = CFrame.new(pos)
	p.Parent = parent
	return p
end

local function tag(inst: Instance, t: string)
	CollectionService:AddTag(inst, t)
end

local function label(parent: BasePart, text: string)
	local sg = Instance.new("BillboardGui")
	sg.Name = "Label"
	sg.Size = UDim2.fromOffset(220, 40)
	sg.StudsOffset = Vector3.new(0, 2, 0)
	sg.AlwaysOnTop = true
	sg.MaxDistance = 40
	sg.Parent = parent
	local tl = Instance.new("TextLabel")
	tl.BackgroundTransparency = 1
	tl.Size = UDim2.fromScale(1, 1)
	tl.Font = Enum.Font.Code
	tl.TextColor3 = Color3.fromRGB(200, 210, 220)
	tl.TextStrokeTransparency = 0.4
	tl.TextScaled = true
	tl.Text = text
	tl.Parent = sg
end

-- A wall on an end (X-facing) with a centered doorway opening.
local function endWallWithDoor(cx: number, faceX: number, parent: Instance)
	-- faceX is the world X of the wall plane. Build three panels around the door.
	local sideW = (IW - DW) / 2
	-- left (−Z) panel
	box("EndWallL", Vector3.new(WT, IH, sideW),
		Vector3.new(faceX, IH / 2, -(DW / 2) - sideW / 2), C.hull, parent)
	-- right (+Z) panel
	box("EndWallR", Vector3.new(WT, IH, sideW),
		Vector3.new(faceX, IH / 2, (DW / 2) + sideW / 2), C.hull, parent)
	-- header above the door
	box("EndWallTop", Vector3.new(WT, IH - DH, DW),
		Vector3.new(faceX, DH + (IH - DH) / 2, 0), C.hull, parent)
end

local function solidEndWall(faceX: number, parent: Instance, color: Color3?)
	box("EndWall", Vector3.new(WT, IH, IW), Vector3.new(faceX, IH / 2, 0), color or C.hull, parent)
end

-- ----------------------------------------------------------------------------
-- Interactable / pickup factories
-- ----------------------------------------------------------------------------
local function addPrompt(parent: BasePart, actionText: string, objectText: string): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = parent
	return prompt
end

local function makeInteractable(name, size, pos, color, kind, action, objectText, parent, attrs)
	local p = box(name, size, pos, color, parent)
	tag(p, "Interactable")
	p:SetAttribute("Kind", kind)
	if attrs then
		for k, v in pairs(attrs) do p:SetAttribute(k, v) end
	end
	addPrompt(p, action, objectText)
	return p
end

local function makePickup(itemId, pos, parent, attrs)
	local def = ItemData.Items[itemId]
	local name = def and def.name or itemId
	local root = ItemModels.BuildPickup(itemId, CFrame.new(pos))
	root.Name = "Pickup_" .. itemId
	root.Parent = parent
	tag(root, "Pickup")
	root:SetAttribute("ItemId", itemId)
	if attrs then for k, v in pairs(attrs) do root:SetAttribute(k, v) end end
	addPrompt(root, "Take", name)
	return root
end

local function makeJournal(pageIndex, pos, parent)
	local data = ItemData.JournalPages[pageIndex]
	local root = ItemModels.BuildJournal(pageIndex, CFrame.new(pos))
	root.Name = "Journal_" .. pageIndex
	root.Parent = parent
	tag(root, "Journal")
	root:SetAttribute("PageIndex", pageIndex)
	addPrompt(root, "Read", data and data.title or ("Journal Page " .. pageIndex))
	return root
end

local function makeHidingSpot(name, pos, sectionIndex, parent)
	-- a wooden locker/drawer cabinet, not bare metal
	local p = box(name, Vector3.new(3, 6, 2.5), pos, Color3.fromRGB(96, 68, 42), parent)
	p.Material = Enum.Material.WoodPlanks
	tag(p, "HidingSpot")
	tag(p, "Interactable")
	p:SetAttribute("Kind", "locker")
	p:SetAttribute("Section", sectionIndex)
	addPrompt(p, "Hide", "Locker")
	return p
end

-- ----------------------------------------------------------------------------
-- Lighting fixtures
-- ----------------------------------------------------------------------------
local function addEmergencyLight(cx, sectionIndex, parent)
	local fixture = box("EmergencyFixture", Vector3.new(2, 0.5, 2),
		Vector3.new(cx, IH - 0.6, 0), C.hullDark, parent)
	fixture.Material = Enum.Material.Neon
	fixture.Color = Color3.fromRGB(120, 20, 20)
	local pl = Instance.new("PointLight")
	pl.Color = Color3.fromRGB(255, 45, 28)
	pl.Brightness = 1.6
	pl.Range = 34
	pl:SetAttribute("BaseBrightness", 1.6)
	pl.Shadows = true
	pl.Parent = fixture
	tag(fixture, "EmergencyLight")
	fixture:SetAttribute("Section", sectionIndex)
	return fixture
end

local function addMainLight(cx, offsetZ, sectionIndex, parent)
	local fixture = box("MainFixture", Vector3.new(3, 0.4, 1),
		Vector3.new(cx, IH - 0.4, offsetZ), C.hullDark, parent)
	local sl = Instance.new("SpotLight")
	sl.Color = Color3.fromRGB(235, 240, 255)
	sl.Brightness = 0
	sl.Range = 30
	sl.Angle = 120
	sl.Face = Enum.NormalId.Bottom
	sl.Shadows = true
	sl.Enabled = false
	sl.Parent = fixture
	tag(fixture, "MainLight")
	fixture:SetAttribute("Section", sectionIndex)
	return fixture
end

-- ----------------------------------------------------------------------------
-- Section shell
-- ----------------------------------------------------------------------------
local function buildSectionShell(index: number): Model
	local data = SectionData.Sections[index]
	local center = SectionData.SectionCenter(index)
	local cx = center.X

	local model = Instance.new("Model")
	model.Name = ("Section_%d_%s"):format(index, data.id)
	model.Parent = root
	model:SetAttribute("Section", index)

	-- floor & ceiling
	box("Floor", Vector3.new(IL, WT, IW), Vector3.new(cx, -WT / 2, 0), C.floor, model)
	box("Ceiling", Vector3.new(IL, WT, IW), Vector3.new(cx, IH + WT / 2, 0), C.hullDark, model)
	-- side walls (Z+/-)
	box("WallZpos", Vector3.new(IL, IH, WT), Vector3.new(cx, IH / 2, IW / 2 + WT / 2), C.hull, model)
	box("WallZneg", Vector3.new(IL, IH, WT), Vector3.new(cx, IH / 2, -IW / 2 - WT / 2), C.hull, model)

	-- end walls: doorway toward a neighbor, solid otherwise
	local bowX = cx - IL / 2 - WT / 2   -- toward lower slot (bow side)
	local sternX = cx + IL / 2 + WT / 2 -- toward higher slot (stern side)
	local slot = hullSlot[index]
	local hasBow = slot > 0
	local hasStern = slot < LAST_SLOT

	if hasBow then
		endWallWithDoor(cx, bowX, model)
	else
		solidEndWall(bowX, model, C.hullDark) -- bow cap (section 1)
	end
	if hasStern then
		endWallWithDoor(cx, sternX, model)
	else
		-- stern cap (section 9) — leave a hull breach opening
		box("SternCapL", Vector3.new(WT, IH, IW / 2 - 2), Vector3.new(sternX, IH / 2, -(IW / 4) - 1), C.hullDark, model)
		box("SternCapTop", Vector3.new(WT, IH / 2, IW), Vector3.new(sternX, IH * 0.75, 0), C.hullDark, model)
	end

	-- water plane (FloodManager/WaterRenderer drive Y)
	local startLevel = data.startLevel or 0
	local waterY = SectionData.LevelToWaterY(startLevel)
	local water = box("Water", Vector3.new(IL, 1, IW), Vector3.new(cx, waterY, 0), C.water, model)
	water.Material = Enum.Material.Glass
	water.Transparency = 0.35
	water.CanCollide = false
	water.CastShadow = false
	tag(water, "WaterPlane")
	water:SetAttribute("Section", index)
	water:SetAttribute("Level", startLevel)

	-- lighting
	addEmergencyLight(cx, index, model)
	addMainLight(cx, IW / 4, index, model)
	addMainLight(cx, -IW / 4, index, model)

	return model
end

-- Short corridor + sealable bulkhead door between two adjacent hull sections.
local function buildConnector(secA: number, secB: number)
	local cA = SectionData.SectionCenter(secA).X
	local cB = SectionData.SectionCenter(secB).X
	local midX = (cA + cB) / 2
	local gap = (cB - cA) - IL  -- corridor length on X

	local model = Instance.new("Model")
	model.Name = ("Connector_%d_%d"):format(secA, secB)
	model.Parent = root

	-- corridor floor/ceiling/walls sized to the doorway width
	box("CorrFloor", Vector3.new(gap, WT, DW + 2), Vector3.new(midX, -WT / 2, 0), C.floor, model)
	box("CorrCeil", Vector3.new(gap, WT, DW + 2), Vector3.new(midX, DH + WT / 2, 0), C.hullDark, model)
	box("CorrWallZpos", Vector3.new(gap, DH, WT), Vector3.new(midX, DH / 2, DW / 2 + 1), C.hull, model)
	box("CorrWallZneg", Vector3.new(gap, DH, WT), Vector3.new(midX, DH / 2, -DW / 2 - 1), C.hull, model)

	-- the bulkhead door itself
	local door = box("BulkheadDoor", Vector3.new(1, DH, DW), Vector3.new(midX, DH / 2, 0), C.door, model)
	door.Material = Enum.Material.DiamondPlate
	tag(door, "BulkheadDoor")
	door:SetAttribute("SectionA", secA)
	door:SetAttribute("SectionB", secB)
	door:SetAttribute("Sealed", false)
	door:SetAttribute("Open", false)
	local prompt = addPrompt(door, "Open", "Bulkhead Door")
	prompt.Name = "DoorPrompt"
	-- a second prompt for sealing (InteractionManager decides which is active)
	local sealPrompt = addPrompt(door, "Seal (permanent)", "Bulkhead Door")
	sealPrompt.Name = "SealPrompt"
	sealPrompt.KeyboardKeyCode = Enum.KeyCode.F
	sealPrompt.UIOffset = Vector2.new(0, 40)
	-- Door number shown only on the close-up prompt (no always-on floating label).
	-- Sequential out of the total; the hull skips section 7 (tower) so raw secA/secB
	-- would read as a gap.
	local order = SectionData.HullOrder
	local doorNum, doorTotal = 0, #order - 1
	for i = 1, doorTotal do if order[i] == secA then doorNum = i break end end
	local objText = ("Door %d/%d"):format(doorNum, doorTotal)
	prompt.ObjectText = objText
	sealPrompt.ObjectText = objText
end

-- Conning tower: vertical shaft above the control room (section 5) with a ladder.
local function buildConningTower()
	local c5 = SectionData.SectionCenter(5)
	local cx = c5.X
	local baseY = IH + WT       -- sits on top of section 5 ceiling
	local towerH = 16
	local model = Instance.new("Model")
	model.Name = "Section_7_conning_tower"
	model.Parent = root
	model:SetAttribute("Section", 7)

	-- shaft walls (small square shaft)
	local s = 10
	box("TowerFloor", Vector3.new(s, WT, s), Vector3.new(cx, baseY, 0), C.floor, model)
	box("TowerCeil", Vector3.new(s, WT, s), Vector3.new(cx, baseY + towerH, 0), C.hullDark, model)
	box("TowerWallA", Vector3.new(WT, towerH, s), Vector3.new(cx + s / 2, baseY + towerH / 2, 0), C.hull, model)
	box("TowerWallB", Vector3.new(WT, towerH, s), Vector3.new(cx - s / 2, baseY + towerH / 2, 0), C.hull, model)
	box("TowerWallC", Vector3.new(s, towerH, WT), Vector3.new(cx, baseY + towerH / 2, s / 2), C.hull, model)
	box("TowerWallD", Vector3.new(s, towerH, WT), Vector3.new(cx, baseY + towerH / 2, -s / 2), C.hull, model)

	-- hole in section 5 ceiling is implied; add a TrussPart ladder from S5 floor up
	local ladder = Instance.new("TrussPart")
	ladder.Anchored = true
	ladder.Name = "TowerLadder"
	ladder.Size = Vector3.new(2, IH + towerH, 2)
	ladder.CFrame = CFrame.new(cx, (IH + towerH) / 2, s / 2 - 2)
	ladder.Color = C.prop
	ladder.Parent = model
	tag(ladder, "Interactable")
	ladder:SetAttribute("Kind", "ladder")

	addEmergencyLight(cx, 7, model)

	-- periscope (optional ambient trigger)
	makeInteractable("Periscope", Vector3.new(2, 6, 2), Vector3.new(cx, baseY + 3, -2), C.console,
		"periscope", "Look", "Periscope", model, { Section = 7 })
end

-- ----------------------------------------------------------------------------
-- Per-section props, pickups, interactables
-- ----------------------------------------------------------------------------
local function buildProps(index: number)
	local cx = SectionData.SectionCenter(index).X
	local model = root:FindFirstChild(("Section_%d_%s"):format(index, SectionData.Sections[index].id))
	if not model then return end

	if index == 1 then
		-- four torpedo tubes on the bow wall
		for t = 0, 3 do
			local z = -9 + t * 6
			local tube = box("TorpedoTube_" .. t, Vector3.new(4, 3, 3),
				Vector3.new(cx - IL / 2 + 3, 3, z), C.hullDark, model)
			tube.Shape = Enum.PartType.Cylinder
			tube.Orientation = Vector3.new(0, 0, 90)
		end
		-- crew bunks
		box("Bunk1", Vector3.new(6, 0.5, 3), Vector3.new(cx + 6, 2, IW / 2 - 3), C.prop, model)
		box("Bunk2", Vector3.new(6, 0.5, 3), Vector3.new(cx + 6, 5, IW / 2 - 3), C.prop, model)
		-- broken panel hiding spot
		makeHidingSpot("BrokenPanel", Vector3.new(cx + 14, 3, -IW / 2 + 2), 1, model)
		-- escape pod panel (Ending: Escape Pod) + first component
		local pod = makeInteractable("EscapePodPanel", Vector3.new(7, 7, 7), Vector3.new(cx - IL / 2 + 5, 3.5, IW / 2 - 4),
			Color3.fromRGB(235, 120, 35), "pod_panel", "Install / Launch", "Escape Pod", model, {})
		pod.Shape = Enum.PartType.Ball
		pod.Material = Enum.Material.Metal
		pod.Reflectance = 0.1
		local podWindow = box("PodWindow", Vector3.new(2.4, 2.4, 2.4), pod.Position, Color3.fromRGB(30, 45, 60), model)
		podWindow.Shape = Enum.PartType.Ball
		podWindow.Material = Enum.Material.Glass
		podWindow.Reflectance = 0.3
		podWindow.CanCollide = false
		podWindow.CFrame = pod.CFrame * CFrame.new(0, 0.6, -3.1)
		makePickup("pod_component", Vector3.new(cx + 14, 1.5, IW / 2 - 3), model, { Slot = 1 })
		makePickup("flashlight", Vector3.new(cx, 1.5, 0), model)
		makePickup("battery", Vector3.new(cx - 6, 1.5, -IW / 2 + 3), model)
		makeJournal(1, Vector3.new(cx + 16, 1.2, 0), model)

	elseif index == 2 then
		for b = 0, 2 do
			box("Bunk_" .. b, Vector3.new(6, 0.5, 3), Vector3.new(cx - 12 + b * 12, 2, IW / 2 - 3), C.prop, model)
		end
		makeHidingSpot("Locker2", Vector3.new(cx - 14, 3, -IW / 2 + 2), 2, model)
		makeHidingSpot("Locker2b", Vector3.new(cx + 14, 3, -IW / 2 + 2), 2, model)
		makePickup("glow_stick", Vector3.new(cx + 6, 1.5, IW / 2 - 4), model)
		makeJournal(2, Vector3.new(cx - 12, 2.8, IW / 2 - 3), model) -- inside a bunk

	elseif index == 3 then
		box("Counter", Vector3.new(IL - 12, 3, 3), Vector3.new(cx, 1.5, -IW / 2 + 3), C.prop, model)
		box("Table1", Vector3.new(5, 0.4, 3), Vector3.new(cx - 8, 2, 4), C.prop, model)
		box("Table2", Vector3.new(5, 0.4, 3), Vector3.new(cx + 8, 2, 4), C.prop, model)
		local nb = makeInteractable("NoticeBoard", Vector3.new(6, 4, 0.4), Vector3.new(cx + 6, 5, IW / 2 - 0.3),
			C.prop, "notice", "Inspect", "Notice Board", model, {})
		makePickup("oxygen_canister", Vector3.new(cx - 8, 2.5, 4), model)
		makeJournal(3, Vector3.new(cx + 6, 5, IW / 2 - 0.9), model) -- pinned to the notice board

	elseif index == 4 then
		-- Captain's quarters: a real enclosed room along the -Z wall. A partition
		-- at Z = -3 (with a doorway) walls it off; the locked door is the only way in.
		box("CaptainWallL", Vector3.new((IL - DW) / 2, IH, WT), Vector3.new(cx - 14, IH / 2, -3), C.hull, model)
		box("CaptainWallR", Vector3.new((IL - DW) / 2, IH, WT), Vector3.new(cx + 14, IH / 2, -3), C.hull, model)
		box("CaptainWallTop", Vector3.new(DW, IH - DH, WT), Vector3.new(cx, DH + (IH - DH) / 2, -3), C.hull, model)
		makeInteractable("CaptainDoor", Vector3.new(DW, DH, 0.5), Vector3.new(cx, DH / 2, -3),
			C.doorSeal, "captain_door", "Unlock (Keycard)", "Captain's Quarters", model, { Locked = true })
		-- emergency light inside the sealed room (the partition blocks the section lights)
		local capFix = box("CaptainLight", Vector3.new(2, 0.5, 2), Vector3.new(cx, IH - 0.6, -8), C.hullDark, model)
		capFix.Material = Enum.Material.Neon
		capFix.Color = Color3.fromRGB(120, 20, 20)
		local capLight = Instance.new("PointLight")
		capLight.Color = Color3.fromRGB(255, 45, 28)
		capLight.Brightness = 1.6
		capLight.Range = 34
		capLight:SetAttribute("BaseBrightness", 1.6)
		capLight.Shadows = true
		capLight.Parent = capFix
		tag(capFix, "EmergencyLight")
		capFix:SetAttribute("Section", 4)
		box("Desk", Vector3.new(6, 3, 3), Vector3.new(cx - 8, 1.5, -IW / 2 + 4), C.prop, model)
		makeInteractable("Safe", Vector3.new(3, 3, 3), Vector3.new(cx + 10, 1.5, -IW / 2 + 3),
			C.hullDark, "safe", "Enter Combination", "Wall Safe", model, { Locked = true })
		makePickup("fuse", Vector3.new(cx - 8, 3.3, -IW / 2 + 4), model)
		makeJournal(4, Vector3.new(cx - 8, 3.3, -IW / 2 + 2), model)
		makeJournal(5, Vector3.new(cx + 10, 3.3, -IW / 2 + 3), model)

	elseif index == 5 then
		box("Helm", Vector3.new(4, 3, 4), Vector3.new(cx, 1.5, 0), C.console, model)
		box("NavConsole", Vector3.new(8, 3, 2), Vector3.new(cx - 10, 1.5, IW / 2 - 3), C.console, model)
		makeInteractable("BallastPanel", Vector3.new(5, 4, 1), Vector3.new(cx + 12, 2.5, -IW / 2 + 2),
			C.console, "ballast", "Install Fuse / Operate", "Ballast Control", model, { FuseInstalled = false })
		-- environmental clue: the valve order engraved on a plate beside the panel
		-- (matches EndingData.BALLAST_SEQUENCE = {3,1,4,2,5})
		local ballastClue = box("BallastClue", Vector3.new(4, 2.4, 0.3), Vector3.new(cx + 17, 4.5, -IW / 2 + 0.7), C.prop, model)
		ballastClue.Material = Enum.Material.SmoothPlastic
		label(ballastClue, "VALVE ORDER 3-1-4-2-5")
		makePickup("pod_component", Vector3.new(cx - 10, 3.2, IW / 2 - 3), model, { Slot = 2 })
		-- ladder up to conning tower is part of the tower model

	elseif index == 6 then
		-- sonar room (keycard) + radio room (locked main power), two consoles
		makeInteractable("SonarConsole", Vector3.new(5, 4, 2), Vector3.new(cx - 12, 2, IW / 2 - 3),
			C.console, "sonar", "Use Sonar", "Sonar Console", model, {})
		makeInteractable("RadioConsole", Vector3.new(5, 4, 2), Vector3.new(cx + 12, 2, -IW / 2 + 3),
			C.console, "radio", "Broadcast SOS", "Radio Console", model, { Locked = true })
		makePickup("keycard", Vector3.new(cx - 12, 4.3, IW / 2 - 3), model)
		makeJournal(6, Vector3.new(cx + 12, 4.3, -IW / 2 + 3), model)

	elseif index == 8 then
		makeInteractable("Generator", Vector3.new(8, 8, 6), Vector3.new(cx, 4, IW / 2 - 4),
			C.hullDark, "generator", "Restore Main Power", "Main Generator", model, { Running = false })
		box("Walkway", Vector3.new(IL - 8, 0.4, 4), Vector3.new(cx, 0.2, -IW / 2 + 4), C.prop, model)
		makePickup("pod_component", Vector3.new(cx - 14, 1.5, -IW / 2 + 4), model, { Slot = 3 })
		makePickup("battery", Vector3.new(cx + 14, 1.5, -IW / 2 + 4), model)

	elseif index == 9 then
		-- hull breach with water particle anchor (Phase 9 adds particles)
		local breach = box("HullBreach", Vector3.new(2, 8, 10), Vector3.new(cx + IL / 2 - 1, 6, IW / 4),
			C.breach, model)
		breach.Transparency = 0.5
		breach.CanCollide = false
		tag(breach, "HullBreach")
		-- secret exterior passage (secret endings): two choices once you know the truth
		local ext = makeInteractable("ExteriorPassage", Vector3.new(4, 6, 4), Vector3.new(cx - IL / 2 + 4, 3, -IW / 2 + 3),
			C.hullDark, "exterior", "Return the cargo", "Hull Breach Passage", model, { Section = 9 })
		local takePrompt = addPrompt(ext, "Take the cargo", "Hull Breach Passage")
		takePrompt.Name = "TakePrompt"
		takePrompt.KeyboardKeyCode = Enum.KeyCode.T
		takePrompt.UIOffset = Vector2.new(0, 40)
		-- (default prompt added by makeInteractable returns/returns; named below)
		local def = ext:FindFirstChildOfClass("ProximityPrompt")
		if def then def.Name = "ReturnPrompt" end
		makePickup("oxygen_canister", Vector3.new(cx, 1.5, 0), model)
	end
end

-- ----------------------------------------------------------------------------
-- Spawn
-- ----------------------------------------------------------------------------
local function buildSpawn()
	local c1 = SectionData.SectionCenter(1).X
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "StartSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.CFrame = CFrame.new(c1 + 8, 1, -IW / 2 + 5)
	spawn.Neutral = true
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Parent = root
end

-- ----------------------------------------------------------------------------
-- Entry point
-- ----------------------------------------------------------------------------
function MapBuilder.Build()
	local existing = Workspace:FindFirstChild("Submarine")
	if existing and existing:GetAttribute("Baked") then
		-- A pre-baked static submarine is saved in the place: use it as-is instead
		-- of rebuilding at runtime, so hand-placed art/lighting survives. Delete the
		-- Submarine (or clear its "Baked" attribute) to force a fresh procedural build.
		root = existing
		print("[HullBreach] MapBuilder: using baked Submarine (runtime build skipped).")
		return
	end
	if existing then existing:Destroy() end

	root = Instance.new("Folder")
	root.Name = "Submarine"
	root.Parent = Workspace
	tag(root, "Submarine")

	for i = 1, SectionData.COUNT do
		if i ~= 7 then
			buildSectionShell(i)
		end
	end
	buildConningTower()

	-- connectors between consecutive hull sections (1-2,...,5-6,6-8,8-9)
	for slot = 1, #SectionData.HullOrder - 1 do
		buildConnector(SectionData.HullOrder[slot], SectionData.HullOrder[slot + 1])
	end

	for i = 1, SectionData.COUNT do
		if i ~= 7 then
			buildProps(i)
		end
	end

	buildSpawn()

	print(("[HullBreach] MapBuilder: built %d sections + tower + connectors."):format(SectionData.COUNT))
end

-- ============================================================================
-- Decorative dressing  (session 29)
-- Moved out of hand-baked Workspace instances into code so it regenerates every
-- server start (baked map OR procedural) and can never again be lost to an
-- unsaved Play session. Every decor instance is named "DD_*"; Dress() clears all
-- DD_* descendants before rebuilding, so it is fully idempotent.
-- ============================================================================
local DD = {
	pipe  = Color3.fromRGB(78, 84, 92),
	rust  = Color3.fromRGB(120, 70, 45),
	dark  = Color3.fromRGB(34, 38, 43),
	amber = Color3.fromRGB(255, 176, 52),
	wood  = Color3.fromRGB(96, 68, 42),
	cloth = Color3.fromRGB(70, 66, 58),
	glass = Color3.fromRGB(20, 40, 55),
}

local function ddPart(parent, name, size, pos, color, material, shape)
	local p = box(name, size, pos, color or DD.pipe, parent)
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = material or Enum.Material.Metal
	if shape then p.Shape = shape end
	return p
end

local function ddCyl(parent, name, length, diam, pos, axis, color, material)
	local p = ddPart(parent, name, Vector3.new(length, diam, diam), pos, color, material, Enum.PartType.Cylinder)
	if axis == "Z" then p.Orientation = Vector3.new(0, 90, 0)
	elseif axis == "Y" then p.Orientation = Vector3.new(0, 0, 90) end
	return p
end

local function ddNeon(parent, name, pos, color, size)
	return ddPart(parent, name, size or Vector3.new(0.4, 0.4, 0.3), pos, color, Enum.Material.Neon)
end

-- generic industrial dressing for a normal (non-tower) hull section
local function dressIndustrial(folder, cx)
	ddCyl(folder, "DD_CeilPipeA", IL - 4, 0.6, Vector3.new(cx, IH - 1, IW / 2 - 3), "X", DD.pipe)
	ddCyl(folder, "DD_CeilPipeB", IL - 4, 0.5, Vector3.new(cx, IH - 1.6, -IW / 2 + 3), "X", DD.rust)
	ddPart(folder, "DD_Conduit",  Vector3.new(IL - 6, 0.5, 0.5),  Vector3.new(cx, 1.7, -IW / 2 + 1), DD.dark)
	ddPart(folder, "DD_Conduit2", Vector3.new(IL - 6, 0.35, 0.35), Vector3.new(cx, 2.3, -IW / 2 + 1), DD.dark)
	for i, ox in ipairs({ -10, 10 }) do
		ddPart(folder, "DD_Ring" .. i .. "Top", Vector3.new(0.8, 0.8, IW - 1), Vector3.new(cx + ox, IH - 0.6, 0), DD.dark)
		ddPart(folder, "DD_Ring" .. i .. "L", Vector3.new(0.8, IH - 2, 0.8), Vector3.new(cx + ox, (IH - 2) / 2, IW / 2 - 1), DD.dark)
		ddPart(folder, "DD_Ring" .. i .. "R", Vector3.new(0.8, IH - 2, 0.8), Vector3.new(cx + ox, (IH - 2) / 2, -IW / 2 + 1), DD.dark)
	end
	ddPart(folder, "DD_Valve", Vector3.new(1.2, 1.2, 1), Vector3.new(cx - 6, 5, IW / 2 - 1.2), DD.rust)
	ddCyl(folder, "DD_ValveWheel", 0.3, 2.2, Vector3.new(cx - 6, 5, IW / 2 - 2.1), "Z", DD.dark)
	ddPart(folder, "DD_Gauge", Vector3.new(1.6, 1.6, 0.4), Vector3.new(cx + 6, 5.5, IW / 2 - 0.6), DD.dark)
	ddNeon(folder, "DD_GaugeLED", Vector3.new(cx + 6.6, 6.1, IW / 2 - 0.85), Color3.fromRGB(60, 220, 90))
end

local function dressConsole(folder, model, partName, ledColor)
	local p = model:FindFirstChild(partName)
	if not (p and p:IsA("BasePart")) then return end
	local sx = math.max(p.Size.X * 0.65, 1.5)
	local screen = ddPart(folder, "DD_Screen_" .. partName,
		Vector3.new(sx, p.Size.Y * 0.45, 0.12),
		p.Position + Vector3.new(0, p.Size.Y * 0.15, -p.Size.Z / 2 - 0.08),
		DD.glass, Enum.Material.Glass)
	screen.Reflectance = 0.2
	ddNeon(folder, "DD_ScreenLED_" .. partName,
		p.Position + Vector3.new(sx / 2 - 0.3, p.Size.Y * 0.42, -p.Size.Z / 2 - 0.12),
		ledColor or Color3.fromRGB(60, 180, 255), Vector3.new(0.3, 0.3, 0.2))
end

local function dressBerthing(folder, model, cx)
	ddPart(folder, "DD_Helmet", Vector3.new(1.2, 0.9, 1.2), Vector3.new(cx - 12, 2.7, IW / 2 - 3), Color3.fromRGB(60, 70, 55), Enum.Material.Metal, Enum.PartType.Ball)
	ddPart(folder, "DD_Duffel", Vector3.new(3, 1.2, 1.4), Vector3.new(cx - 6, 0.8, IW / 2 - 4), DD.cloth, Enum.Material.Fabric)
	ddPart(folder, "DD_BootL", Vector3.new(0.8, 0.8, 1.6), Vector3.new(cx + 2, 0.6, IW / 2 - 4), Color3.fromRGB(30, 28, 26), Enum.Material.SmoothPlastic)
	ddPart(folder, "DD_BootR", Vector3.new(0.8, 0.8, 1.6), Vector3.new(cx + 3, 0.6, IW / 2 - 4), Color3.fromRGB(30, 28, 26), Enum.Material.SmoothPlastic)
	ddPart(folder, "DD_Book2", Vector3.new(1, 0.3, 1.4), Vector3.new(cx - 12, 2.75, IW / 2 - 2.2), Color3.fromRGB(90, 40, 40), Enum.Material.SmoothPlastic)
end

local function dressGalley(folder, model, cx)
	local function setting(tagn, bx)
		ddCyl(folder, "DD_Plate" .. tagn, 0.15, 1.2, Vector3.new(bx, 2.3, 4), "Y", Color3.fromRGB(205, 205, 195), Enum.Material.SmoothPlastic)
		ddCyl(folder, "DD_Mug" .. tagn, 0.7, 0.5, Vector3.new(bx + 1.3, 2.55, 4.6), "Y", Color3.fromRGB(180, 170, 150), Enum.Material.SmoothPlastic)
		ddCyl(folder, "DD_Bowl" .. tagn, 0.4, 0.9, Vector3.new(bx - 1.2, 2.4, 3.3), "Y", Color3.fromRGB(150, 150, 140), Enum.Material.SmoothPlastic)
	end
	setting("A", cx - 8)
	setting("B", cx + 8)
	ddCyl(folder, "DD_Pot", 1.4, 1.6, Vector3.new(cx, 3.7, -IW / 2 + 3), "Y", DD.dark, Enum.Material.Metal)
	-- proper mess furniture: two dining tables with chairs, plus a sofa + coffee table
	local woodC = Color3.fromRGB(96, 70, 44)
	local metalC = Color3.fromRGB(70, 74, 80)
	for ti, tx in ipairs({ cx - 8, cx + 8 }) do
		for _, lc in ipairs({ {2, 1.2}, {2, -1.2}, {-2, 1.2}, {-2, -1.2} }) do
			ddPart(folder, "DD_GTLeg" .. ti, Vector3.new(0.3, 2, 0.3), Vector3.new(tx + lc[1], 1, 4 + lc[2]), metalC, Enum.Material.Metal)
		end
		for _, cz in ipairs({ 4 + 2.7, 4 - 2.7 }) do
			local outward = (cz > 4) and 1 or -1
			for _, ox in ipairs({ -1.4, 1.4 }) do
				local bx = tx + ox
				ddPart(folder, "DD_GChairSeat" .. ti, Vector3.new(1.2, 0.24, 1.2), Vector3.new(bx, 1.3, cz), woodC, Enum.Material.WoodPlanks)
				ddPart(folder, "DD_GChairBack" .. ti, Vector3.new(1.2, 1.4, 0.18), Vector3.new(bx, 2.05, cz + outward * 0.5), woodC, Enum.Material.WoodPlanks)
				ddPart(folder, "DD_GChairLegF" .. ti, Vector3.new(1.0, 1.3, 0.18), Vector3.new(bx, 0.65, cz - outward * 0.45), metalC, Enum.Material.Metal)
				ddPart(folder, "DD_GChairLegB" .. ti, Vector3.new(1.0, 1.3, 0.18), Vector3.new(bx, 0.65, cz + outward * 0.45), metalC, Enum.Material.Metal)
			end
		end
	end
	local sx, sz2 = cx + 15, 9.6
	local sofaC, cushC = Color3.fromRGB(74, 58, 50), Color3.fromRGB(92, 76, 64)
	ddPart(folder, "DD_GSofaBase", Vector3.new(6, 1, 2.4), Vector3.new(sx, 0.6, sz2), sofaC, Enum.Material.Fabric)
	ddPart(folder, "DD_GSofaBack", Vector3.new(6, 1.6, 0.5), Vector3.new(sx, 1.7, sz2 + 0.95), sofaC, Enum.Material.Fabric)
	ddPart(folder, "DD_GSofaArmL", Vector3.new(0.6, 1.4, 2.4), Vector3.new(sx - 3, 1.2, sz2), sofaC, Enum.Material.Fabric)
	ddPart(folder, "DD_GSofaArmR", Vector3.new(0.6, 1.4, 2.4), Vector3.new(sx + 3, 1.2, sz2), sofaC, Enum.Material.Fabric)
	for _, co in ipairs({ -1.8, 0, 1.8 }) do
		ddPart(folder, "DD_GSofaCush", Vector3.new(1.7, 0.45, 2.2), Vector3.new(sx + co, 1.3, sz2 - 0.1), cushC, Enum.Material.Fabric)
	end
	ddPart(folder, "DD_GCoffee", Vector3.new(3, 0.3, 1.4), Vector3.new(sx, 1.5, sz2 - 2.6), woodC, Enum.Material.WoodPlanks)
	for _, lc in ipairs({ {1.2, 0.5}, {1.2, -0.5}, {-1.2, 0.5}, {-1.2, -0.5} }) do
		ddPart(folder, "DD_GCoffeeLeg", Vector3.new(0.22, 1.4, 0.22), Vector3.new(sx + lc[1], 0.7, sz2 - 2.6 + lc[2]), metalC, Enum.Material.Metal)
	end
end

local function dressNotice(folder, model, cx)
	local nb = model:FindFirstChild("NoticeBoard")
	if not (nb and nb:IsA("BasePart")) then return end
	for _, c in ipairs(nb:GetChildren()) do if c.Name:sub(1, 3) == "DD_" then c:Destroy() end end
	nb.Color = Color3.fromRGB(92, 64, 40)
	nb.Material = Enum.Material.WoodPlanks
	-- pull it clearly off the +Z wall so it stops merging into it (stable absolute Z);
	-- nudged to cx+6 (viewer's right) so its edge clears the ring-frame rib at cx+10.
	nb.CFrame = CFrame.new(cx + 6, 5, IW / 2 - 1.1)
	local sz = nb.Size
	local fc = Color3.fromRGB(58, 40, 24)
	local fz = -(sz.Z / 2 + 0.06)
	ddPart(folder, "DD_NbFrameT", Vector3.new(sz.X + 0.5, 0.5, 0.2), nb.Position + Vector3.new(0, sz.Y / 2 + 0.1, fz), fc, Enum.Material.WoodPlanks)
	ddPart(folder, "DD_NbFrameB", Vector3.new(sz.X + 0.5, 0.5, 0.2), nb.Position + Vector3.new(0, -sz.Y / 2 - 0.1, fz), fc, Enum.Material.WoodPlanks)
	ddPart(folder, "DD_NbFrameL", Vector3.new(0.5, sz.Y + 1, 0.2), nb.Position + Vector3.new(-sz.X / 2 - 0.1, 0, fz), fc, Enum.Material.WoodPlanks)
	ddPart(folder, "DD_NbFrameR", Vector3.new(0.5, sz.Y + 1, 0.2), nb.Position + Vector3.new(sz.X / 2 + 0.1, 0, fz), fc, Enum.Material.WoodPlanks)
	local backZ = nb.Position.Z + sz.Z / 2
	local brDepth = (IW / 2) - backZ
	for _, oy in ipairs({ sz.Y / 2 - 0.6, -(sz.Y / 2 - 0.6) }) do
		ddPart(folder, "DD_NbBracket", Vector3.new(0.4, 0.4, brDepth), Vector3.new(nb.Position.X, nb.Position.Y + oy, backZ + brDepth / 2), Color3.fromRGB(60, 64, 70), Enum.Material.Metal)
	end
	local sg = Instance.new("SurfaceGui")
	sg.Name = "DD_Poster" ; sg.Face = Enum.NormalId.Front ; sg.LightInfluence = 0.15 ; sg.PixelsPerStud = 60 ; sg.Parent = nb
	local bg = Instance.new("Frame") ; bg.Size = UDim2.fromScale(1, 1) ; bg.BackgroundColor3 = Color3.fromRGB(58, 40, 24) ; bg.BorderSizePixel = 0 ; bg.Parent = sg
	local paper = Instance.new("Frame") ; paper.Size = UDim2.fromScale(0.82, 0.82) ; paper.Position = UDim2.fromScale(0.09, 0.09) ; paper.BackgroundColor3 = Color3.fromRGB(222, 214, 190) ; paper.BorderSizePixel = 0 ; paper.Parent = bg
	local hdr = Instance.new("TextLabel") ; hdr.BackgroundTransparency = 1 ; hdr.Size = UDim2.fromScale(0.92, 0.16) ; hdr.Position = UDim2.fromScale(0.04, 0.04) ; hdr.Font = Enum.Font.GothamBold ; hdr.Text = "MESS HALL - DAILY NOTICES" ; hdr.TextColor3 = Color3.fromRGB(40, 30, 20) ; hdr.TextScaled = true ; hdr.Parent = paper
	local body = Instance.new("TextLabel") ; body.BackgroundTransparency = 1 ; body.Size = UDim2.fromScale(0.9, 0.5) ; body.Position = UDim2.fromScale(0.05, 0.24) ; body.Font = Enum.Font.Merriweather ; body.TextXAlignment = Enum.TextXAlignment.Left ; body.TextYAlignment = Enum.TextYAlignment.Top ; body.Text = "- Water rationing in effect: 2 cups/man/day.\n- Galley duty: Petrov, Sokolov, Renn.\n- Depth alarm drills 0600.\n- Report flooding to the XO at once." ; body.TextColor3 = Color3.fromRGB(50, 40, 30) ; body.TextScaled = true ; body.Parent = paper
	local stamp = Instance.new("TextLabel") ; stamp.BackgroundTransparency = 1 ; stamp.Size = UDim2.fromScale(0.5, 0.16) ; stamp.Position = UDim2.fromScale(0.35, 0.74) ; stamp.Rotation = -12 ; stamp.Font = Enum.Font.GothamBlack ; stamp.Text = "CLASSIFIED" ; stamp.TextColor3 = Color3.fromRGB(170, 30, 25) ; stamp.TextTransparency = 0.15 ; stamp.TextScaled = true ; stamp.Parent = paper
	for i, p in ipairs({ {0.07,0.07}, {0.9,0.07}, {0.07,0.9}, {0.9,0.9} }) do
		local tack = Instance.new("Frame") ; tack.Size = UDim2.fromScale(0.05, 0.07) ; tack.Position = UDim2.fromScale(p[1], p[2]) ; tack.BackgroundColor3 = Color3.fromRGB(180, 40, 40) ; tack.BorderSizePixel = 0 ; tack.Parent = paper
		local r = Instance.new("UICorner") ; r.CornerRadius = UDim.new(1, 0) ; r.Parent = tack
	end
end

local function dressOfficers(folder, model, cx)
	-- Desk props: prefer mesh models cloned from ServerStorage.DeskProps; fall back to primitives.
	local _SS = game:GetService("ServerStorage")
	local _deskProps = _SS:FindFirstChild("DeskProps")
	local function _placeDeskModel(tmplName, ddName, x, z, yRot, scale)
		local tmpl = _deskProps and _deskProps:FindFirstChild(tmplName)
		if not tmpl then return nil end
		local m = tmpl:Clone()
		m.Name = ddName
		if scale and scale ~= 1 then
			if m:IsA("Model") then m:ScaleTo(m:GetScale() * scale)
			elseif m:IsA("BasePart") then m.Size = m.Size * scale end
		end
		if m:IsA("Model") then
			m:PivotTo(CFrame.new(x, 100, z) * CFrame.Angles(0, math.rad(yRot or 0), 0))
			local _cf, _sz = m:GetBoundingBox()
			m:PivotTo(m:GetPivot() + Vector3.new(0, 3.0 - (_cf.Position.Y - _sz.Y / 2), 0))
		elseif m:IsA("BasePart") then
			m.CFrame = CFrame.new(x, 3.0 + m.Size.Y / 2, z) * CFrame.Angles(0, math.rad(yRot or 0), 0)
		end
		for _, d in ipairs(m:GetDescendants()) do if d:IsA("BasePart") then d.Anchored = true end end
		if m:IsA("BasePart") then m.Anchored = true end
		m.Parent = folder
		return m
	end
	local _okL, _lamp = pcall(_placeDeskModel, "Lamp", "DD_OLamp", cx - 10, -IW / 2 + 3.5, 210, 0.9)
	if _okL and _lamp then
		for _, d in ipairs(_lamp:GetDescendants()) do if d:IsA("SpotLight") then d.Enabled = false end end
		local _bulb = _lamp:FindFirstChild("Bulb", true)
		local _lp = Instance.new("PointLight")
		_lp.Color = Color3.fromRGB(255, 200, 120) ; _lp.Brightness = 0.8 ; _lp.Range = 9 ; _lp.Shadows = false
		_lp.Parent = (_bulb and _bulb:IsA("BasePart")) and _bulb or _lamp:FindFirstChildWhichIsA("BasePart", true)
	else
		ddPart(folder, "DD_OLampBase", Vector3.new(0.6, 0.3, 0.6), Vector3.new(cx - 10, 3.15, -IW / 2 + 3.5), DD.dark, Enum.Material.Metal)
		local shade = ddPart(folder, "DD_OLampShade", Vector3.new(1.2, 1, 1.2), Vector3.new(cx - 10, 4.2, -IW / 2 + 3.5), DD.amber, Enum.Material.Neon)
		local lp = Instance.new("PointLight") ; lp.Color = Color3.fromRGB(255, 200, 120) ; lp.Brightness = 0.8 ; lp.Range = 9 ; lp.Shadows = false ; lp.Parent = shade
	end
	local _okM, _mug = pcall(_placeDeskModel, "Mug", "DD_OMug", cx - 7, -IW / 2 + 4.5, 30, 0.8)
	if not (_okM and _mug) then
		ddCyl(folder, "DD_OMug", 0.7, 0.5, Vector3.new(cx - 7, 3.35, -IW / 2 + 4.5), "Y", Color3.fromRGB(160, 150, 140), Enum.Material.SmoothPlastic)
	end
	do
		local _bx, _bz, _y = cx - 9, -IW / 2 + 4, 3.0
		local _cols = { Color3.fromRGB(74, 52, 40), Color3.fromRGB(92, 42, 36), Color3.fromRGB(56, 62, 46) }
		for _i = 1, 3 do
			local _h = 0.34
			local _b = ddPart(folder, "DD_OBooks", Vector3.new(1.9 - _i * 0.14, _h, 1.35 - _i * 0.09), Vector3.new(_bx, _y + _h / 2, _bz), _cols[_i], Enum.Material.SmoothPlastic)
			_b.CFrame = CFrame.new(_bx, _y + _h / 2, _bz) * CFrame.Angles(0, math.rad((_i % 2 == 0) and 10 or -7), 0)
			_y = _y + _h
		end
	end
	local _ph = ddPart(folder, "DD_OPhoto", Vector3.new(1.5, 1.2, 0.14), Vector3.new(cx - 6.5, 3.6, -IW / 2 + 3.2), DD.dark, Enum.Material.Wood)
	_ph.CFrame = CFrame.new(cx - 6.5, 3.6, -IW / 2 + 3.2) * CFrame.Angles(0, math.rad(-18), 0)
end

local function dressSonarRadio(folder, model, cx)
	local sideW = (IW - DW) / 2
	ddPart(folder, "DD_PartZneg", Vector3.new(0.6, IH - 0.5, sideW), Vector3.new(cx, (IH - 0.5) / 2, -(DW / 2) - sideW / 2), DD.dark, Enum.Material.CorrodedMetal)
	ddPart(folder, "DD_PartZpos", Vector3.new(0.6, IH - 0.5, sideW), Vector3.new(cx, (IH - 0.5) / 2, (DW / 2) + sideW / 2), DD.dark, Enum.Material.CorrodedMetal)
	ddPart(folder, "DD_PartTop", Vector3.new(0.6, IH - DH, DW), Vector3.new(cx, DH + (IH - DH) / 2, 0), DD.dark, Enum.Material.CorrodedMetal)
	local fix = ddPart(folder, "DD_RadioFixture", Vector3.new(2, 0.5, 2), Vector3.new(cx + 12, IH - 0.6, 0), Color3.fromRGB(120, 20, 20), Enum.Material.Neon)
	local pl = Instance.new("PointLight") ; pl.Color = Color3.fromRGB(255, 45, 28) ; pl.Brightness = 1.6 ; pl.Range = 34 ; pl:SetAttribute("BaseBrightness", 1.6) ; pl.Shadows = true ; pl.Parent = fix
	CollectionService:AddTag(fix, "EmergencyLight")
	fix:SetAttribute("Section", 6)
end

local function buildPanelGui(panel)
	local sg = Instance.new("SurfaceGui")
	sg.Name = "DD_PanelGui" ; sg.Face = Enum.NormalId.Front ; sg.LightInfluence = 0 ; sg.Brightness = 1.6 ; sg.PixelsPerStud = 80 ; sg.Parent = panel
	local bg = Instance.new("Frame") ; bg.Size = UDim2.fromScale(1, 1) ; bg.BackgroundColor3 = Color3.fromRGB(10, 12, 14) ; bg.BorderSizePixel = 0 ; bg.Parent = sg
	local title = Instance.new("TextLabel") ; title.BackgroundTransparency = 1 ; title.Size = UDim2.fromScale(0.95, 0.22) ; title.Position = UDim2.fromScale(0.025, 0.06) ; title.Font = Enum.Font.Code ; title.Text = "MAIN GENERATOR" ; title.TextColor3 = Color3.fromRGB(255, 176, 52) ; title.TextScaled = true ; title.Parent = bg
	local status = Instance.new("TextLabel") ; status.BackgroundTransparency = 1 ; status.Size = UDim2.fromScale(0.95, 0.16) ; status.Position = UDim2.fromScale(0.025, 0.30) ; status.Font = Enum.Font.Code ; status.Text = "OFFLINE - STANDBY" ; status.TextColor3 = Color3.fromRGB(200, 120, 40) ; status.TextScaled = true ; status.Parent = bg
	for i = 0, 1 do
		local g = Instance.new("Frame") ; g.Size = UDim2.fromScale(0.18, 0.24) ; g.Position = UDim2.fromScale(0.12 + i * 0.3, 0.52) ; g.BackgroundColor3 = Color3.fromRGB(20, 24, 28) ; g.BorderSizePixel = 0 ; g.Parent = bg
		local rr = Instance.new("UICorner") ; rr.CornerRadius = UDim.new(1, 0) ; rr.Parent = g
		local st = Instance.new("UIStroke") ; st.Color = Color3.fromRGB(90, 96, 104) ; st.Thickness = 2 ; st.Parent = g
		local needle = Instance.new("Frame") ; needle.Size = UDim2.fromScale(0.06, 0.42) ; needle.AnchorPoint = Vector2.new(0.5, 1) ; needle.Position = UDim2.fromScale(0.5, 0.5) ; needle.BackgroundColor3 = Color3.fromRGB(255, 90, 70) ; needle.BorderSizePixel = 0 ; needle.Rotation = (i == 0) and -40 or 25 ; needle.Parent = g
	end
	local leds = { {"G", Color3.fromRGB(60, 220, 90)}, {"A", Color3.fromRGB(255, 176, 52)}, {"R", Color3.fromRGB(230, 60, 50)} }
	for i, info in ipairs(leds) do
		local led = Instance.new("Frame") ; led.Size = UDim2.fromScale(0.085, 0.13) ; led.Position = UDim2.fromScale(0.7, 0.52 + (i - 1) * 0.155) ; led.BackgroundColor3 = info[2] ; led.BorderSizePixel = 0 ; led.Parent = bg
		local rr = Instance.new("UICorner") ; rr.CornerRadius = UDim.new(1, 0) ; rr.Parent = led
		local tl = Instance.new("TextLabel") ; tl.BackgroundTransparency = 1 ; tl.Size = UDim2.fromScale(0.6, 1) ; tl.Position = UDim2.fromScale(1.1, 0) ; tl.Font = Enum.Font.Code ; tl.Text = info[1] ; tl.TextColor3 = Color3.fromRGB(180, 186, 194) ; tl.TextScaled = true ; tl.TextXAlignment = Enum.TextXAlignment.Left ; tl.Parent = led
	end
end

local function dressGenerator(folder, model)
	local gen = model:FindFirstChild("Generator")
	if not (gen and gen:IsA("BasePart")) then return end
	for _, c in ipairs(gen:GetChildren()) do if c.Name:sub(1, 3) == "DD_" then c:Destroy() end end
	local g = gen.Position -- (336,4,8); size (8,8,6): X 332..340, Y 0..8, Z 5..11
	for i = 1, 5 do
		ddPart(folder, "DD_GVent" .. i, Vector3.new(0.25, 0.35, 5), g + Vector3.new(4.05, -2.2 + (i - 1) * 1.1, 0), DD.dark)
	end
	ddCyl(folder, "DD_GStack", 3, 1.5, g + Vector3.new(1.5, 5.4, 0), "Y", DD.dark, Enum.Material.Metal)
	ddPart(folder, "DD_GCeilPipe", Vector3.new(0.6, 0.6, 9), g + Vector3.new(1.5, 6.6, 0), DD.pipe, Enum.Material.Metal)
	ddCyl(folder, "DD_GCoolant1", 5.5, 0.5, g + Vector3.new(-4.05, 0, -2), "Y", Color3.fromRGB(120, 60, 40), Enum.Material.Metal)
	ddCyl(folder, "DD_GCoolant2", 5.5, 0.5, g + Vector3.new(-4.05, 0, 2), "Y", Color3.fromRGB(120, 60, 40), Enum.Material.Metal)
	ddPart(folder, "DD_GTrimZ1", Vector3.new(8.2, 1, 0.3), g + Vector3.new(0, -3.3, -3.06), DD.amber, Enum.Material.SmoothPlastic)
	ddPart(folder, "DD_GTrimZ2", Vector3.new(8.2, 1, 0.3), g + Vector3.new(0, -3.3, 3.06), DD.amber, Enum.Material.SmoothPlastic)
	ddPart(folder, "DD_GTrimX1", Vector3.new(0.3, 1, 6.2), g + Vector3.new(-4.06, -3.3, 0), DD.amber, Enum.Material.SmoothPlastic)
	ddPart(folder, "DD_GTrimX2", Vector3.new(0.3, 1, 6.2), g + Vector3.new(4.06, -3.3, 0), DD.amber, Enum.Material.SmoothPlastic)
	local panel = ddPart(folder, "DD_GPanel", Vector3.new(4.4, 3.2, 0.3), g + Vector3.new(0, 1, -3.1), Color3.fromRGB(24, 26, 30), Enum.Material.Metal)
	buildPanelGui(panel)
	local steam = Instance.new("ParticleEmitter")
	steam.Name = "DD_Steam" ; steam.Texture = "rbxasset://textures/particles/smoke_main.dds" ; steam.Color = ColorSequence.new(Color3.fromRGB(200, 200, 205)) ; steam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) }) ; steam.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 4) }) ; steam.Lifetime = NumberRange.new(1.5, 2.5) ; steam.Rate = 6 ; steam.Speed = NumberRange.new(2, 4) ; steam.SpreadAngle = Vector2.new(15, 15) ; steam.Acceleration = Vector3.new(0, 4, 0) ; steam.Parent = gen
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "DD_Sparks" ; sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds" ; sparks.Color = ColorSequence.new(Color3.fromRGB(255, 180, 90)) ; sparks.Size = NumberSequence.new(0.3) ; sparks.Lifetime = NumberRange.new(0.3, 0.6) ; sparks.Rate = 9 ; sparks.Speed = NumberRange.new(6, 10) ; sparks.SpreadAngle = Vector2.new(40, 40) ; sparks.Acceleration = Vector3.new(0, -20, 0) ; sparks.Parent = gen
end

local function dressBreach(folder, model, cx)
	local br = model:FindFirstChild("HullBreach")
	if not (br and br:IsA("BasePart")) then return end
	for _, c in ipairs(br:GetChildren()) do if c.Name:sub(1, 3) == "DD_" then c:Destroy() end end
	br.Material = Enum.Material.Glass
	br.Color = Color3.fromRGB(8, 14, 18)
	-- Make the breach BE the wall: a dark-water membrane spanning the stern-wall thickness,
	-- its room face flush with the wall's inner face, filling the stern-cap opening. wallX is
	-- derived from the section centre (STABLE) so re-running Dress never drifts it outward.
	local wallX = cx + IL / 2 + WT / 2   -- stern wall plane (417 for section 9)
	local innerX = wallX - WT / 2        -- room-facing wall face (416)
	br.Size = Vector3.new(WT, 7.4, 13.6)
	br.CFrame = CFrame.new(wallX, 4, 5)
	br.Transparency = 0.25
	br.CanCollide = false
	-- the_deep ending: swim out through the hull breach. The Interactable tag / Kind /
	-- BreachPrompt were lost from the baked map, so re-apply them here every server start
	-- (idempotent). InteractionManager routes Kind="breach" -> EndingManager.onBreach.
	CollectionService:AddTag(br, "Interactable")
	br:SetAttribute("Kind", "breach")
	if not br:FindFirstChild("BreachPrompt") then
		local bp = Instance.new("ProximityPrompt")
		bp.Name = "BreachPrompt"
		bp.ActionText = "Swim out"
		bp.ObjectText = "Hull Breach"
		bp.KeyboardKeyCode = Enum.KeyCode.E
		bp.HoldDuration = 1.2
		bp.MaxActivationDistance = 9
		bp.RequiresLineOfSight = false
		bp.Parent = br
	end
	local b = br.Position
	local halfY, halfZ = br.Size.Y / 2, br.Size.Z / 2
	-- near-black ocean just outboard so the hole shows only the deep, never the skybox
	ddPart(folder, "DD_VoidBack", Vector3.new(0.8, br.Size.Y + 5, br.Size.Z + 5), Vector3.new(wallX + WT / 2 + 0.6, b.Y, b.Z), Color3.fromRGB(1, 3, 6), Enum.Material.SmoothPlastic)
	-- jagged torn-metal teeth ringing the opening at the room face of the wall
	local rimX = innerX - 0.05
	local function tooth(name, pos, rot)
		local t = ddPart(folder, name, Vector3.new(0.7, 1.6, 0.9), pos, DD.dark, Enum.Material.CorrodedMetal)
		t.Orientation = rot
	end
	for i = 0, 4 do
		local z = b.Z - halfZ + (i / 4) * br.Size.Z
		tooth("DD_EdgeT" .. i, Vector3.new(rimX, b.Y + halfY, z), Vector3.new(0, 0, 30 + i * 14))
		tooth("DD_EdgeB" .. i, Vector3.new(rimX, b.Y - halfY, z), Vector3.new(0, 0, -30 - i * 14))
	end
	for i = 1, 3 do
		local y = b.Y - halfY + (i / 4) * br.Size.Y
		tooth("DD_EdgeL" .. i, Vector3.new(rimX, y, b.Z - halfZ), Vector3.new(40, 0, 0))
		tooth("DD_EdgeR" .. i, Vector3.new(rimX, y, b.Z + halfZ), Vector3.new(-40, 0, 0))
	end
	local la = ddPart(folder, "DD_BreachLightAnchor", Vector3.new(0.5, 0.5, 0.5), b + Vector3.new(-1.5, 0, 0), Color3.fromRGB(40, 80, 120), Enum.Material.Neon)
	local pl = Instance.new("PointLight") ; pl.Color = Color3.fromRGB(70, 120, 190) ; pl.Brightness = 1.5 ; pl.Range = 18 ; pl.Shadows = true ; pl.Parent = la
	local spray = Instance.new("ParticleEmitter")
	spray.Name = "DD_Spray" ; spray.Texture = "rbxasset://textures/particles/smoke_main.dds" ; spray.Color = ColorSequence.new(Color3.fromRGB(140, 170, 190)) ; spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) }) ; spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 3) }) ; spray.Lifetime = NumberRange.new(0.8, 1.4) ; spray.Rate = 14 ; spray.Speed = NumberRange.new(8, 14) ; spray.SpreadAngle = Vector2.new(25, 25) ; spray.Acceleration = Vector3.new(-12, -6, 0) ; spray.Parent = br
	local bub = Instance.new("ParticleEmitter")
	bub.Name = "DD_Bubbles" ; bub.Texture = "rbxasset://textures/particles/sparkles_main.dds" ; bub.Color = ColorSequence.new(Color3.fromRGB(180, 210, 230)) ; bub.Size = NumberSequence.new(0.4) ; bub.Lifetime = NumberRange.new(1, 2) ; bub.Rate = 10 ; bub.Speed = NumberRange.new(2, 4) ; bub.SpreadAngle = Vector2.new(30, 30) ; bub.Acceleration = Vector3.new(-3, 5, 0) ; bub.Parent = br
end

local function dressAft(folder, model, cx)
	-- two proper torpedoes on steel cradles along the -Z wall, noses toward the stern
	local function torpedo(tag, baseX)
		local len, diam = 7, 1.8
		local pos = Vector3.new(baseX, 3, -IW / 2 + 3)
		ddCyl(folder, "DD_Torp" .. tag .. "Body", len, diam, pos, "X", Color3.fromRGB(98, 92, 72), Enum.Material.Metal)
		ddPart(folder, "DD_Torp" .. tag .. "Nose", Vector3.new(diam, diam, diam), pos + Vector3.new(len / 2 + 0.1, 0, 0), Color3.fromRGB(74, 68, 54), Enum.Material.Metal, Enum.PartType.Ball)
		ddCyl(folder, "DD_Torp" .. tag .. "Band", 0.5, diam + 0.12, pos + Vector3.new(len / 2 - 1.2, 0, 0), "X", Color3.fromRGB(214, 172, 42), Enum.Material.SmoothPlastic)
		ddCyl(folder, "DD_Torp" .. tag .. "Stripe", 0.3, diam + 0.12, pos + Vector3.new(len / 2 - 2.1, 0, 0), "X", Color3.fromRGB(150, 42, 36), Enum.Material.SmoothPlastic)
		for f = 0, 3 do
			local ang = math.rad(f * 90)
			local fin = ddPart(folder, "DD_Torp" .. tag .. "Fin" .. f, Vector3.new(1.5, 1.6, 0.12), pos + Vector3.new(-len / 2 + 0.6, 0, 0), Color3.fromRGB(60, 56, 48), Enum.Material.Metal)
			fin.CFrame = CFrame.new(pos + Vector3.new(-len / 2 + 0.6, 0, 0)) * CFrame.Angles(ang, 0, 0) * CFrame.new(0, diam * 0.7 + 0.4, 0)
		end
		ddCyl(folder, "DD_Torp" .. tag .. "Prop", 0.5, 0.7, pos + Vector3.new(-len / 2 - 0.3, 0, 0), "X", Color3.fromRGB(140, 140, 130), Enum.Material.Metal)
		ddPart(folder, "DD_Torp" .. tag .. "Cradle1", Vector3.new(0.6, 2.8, 2.4), pos + Vector3.new(len * 0.25, -1.6, 0), DD.dark, Enum.Material.Metal)
		ddPart(folder, "DD_Torp" .. tag .. "Cradle2", Vector3.new(0.6, 2.8, 2.4), pos + Vector3.new(-len * 0.25, -1.6, 0), DD.dark, Enum.Material.Metal)
	end
	torpedo("A", cx - 7)
	torpedo("B", cx + 7)
	ddPart(folder, "DD_Debris1", Vector3.new(3, 0.5, 2), Vector3.new(cx - 4, 0.4, 2), DD.dark, Enum.Material.CorrodedMetal)
	ddPart(folder, "DD_Debris2", Vector3.new(2, 0.5, 3), Vector3.new(cx - 2, 0.4, -4), DD.dark, Enum.Material.CorrodedMetal)
	local hp = ddPart(folder, "DD_HangPanel", Vector3.new(4, 3, 0.3), Vector3.new(cx + 6, IH - 3, -IW / 2 + 2), DD.dark, Enum.Material.CorrodedMetal)
	hp.Orientation = Vector3.new(0, 0, 25)
end

local function dressPeriscope(folder, model)
	local p = model:FindFirstChild("Periscope")
	if not (p and p:IsA("BasePart")) then return end
	local pp = p.Position
	ddPart(folder, "DD_PEyepiece", Vector3.new(2, 0.6, 0.6), pp + Vector3.new(0, 2.6, 0.7), DD.dark, Enum.Material.Metal)
	ddCyl(folder, "DD_PShaft", 5, 0.8, pp + Vector3.new(0, 2.8, 0), "Y", DD.dark, Enum.Material.Metal)
	ddPart(folder, "DD_PConsole", Vector3.new(3, 2, 1.2), pp + Vector3.new(2.6, -1, 1.4), C.console, Enum.Material.Metal)
	local screen = ddPart(folder, "DD_PScreen", Vector3.new(2, 1.2, 0.1), pp + Vector3.new(2.6, -0.4, 0.78), DD.glass, Enum.Material.Glass)
	screen.Reflectance = 0.25
	ddNeon(folder, "DD_PLED", pp + Vector3.new(3.3, 0.1, 0.78), Color3.fromRGB(60, 200, 120), Vector3.new(0.3, 0.3, 0.2))
	ddPart(folder, "DD_PSeat", Vector3.new(1.6, 0.4, 1.6), pp + Vector3.new(2.6, -1.6, -1), DD.dark, Enum.Material.SmoothPlastic)
end

-- Dress the captain's-quarters door as a heavy cabin bulkhead door: riveted frame, a
-- porthole window, a spoke wheel handle, a (red, locked) keycard reader, a CAPTAIN plate.
local function dressCaptainDoor()
	local d
	for _, p in ipairs(CollectionService:GetTagged("Interactable")) do
		if p:IsA("BasePart") and p:GetAttribute("Kind") == "captain_door" then d = p ; break end
	end
	if not d then return end
	for _, c in ipairs(d:GetChildren()) do if c.Name:sub(1, 4) == "DD_C" then c:Destroy() end end
	d.Material = Enum.Material.Metal
	d.Color = Color3.fromRGB(58, 50, 42)
	d.Reflectance = 0.05
	local sz = d.Size
	local toRoom = (d.Position.Z < 0) and 1 or -1
	local function cp(name, size, ox, oy, oz, color, mat, shape)
		local p = box(name, size, Vector3.new(d.Position.X + ox, d.Position.Y + oy, d.Position.Z + oz), color, d)
		p.CanCollide = false ; p.CanQuery = false ; p.CastShadow = false
		p.Material = mat or Enum.Material.Metal
		if shape then p.Shape = shape end
		return p
	end
	local fz = toRoom * (sz.Z / 2 + 0.04)
	local frameC = Color3.fromRGB(44, 40, 34)
	cp("DD_CFrameT", Vector3.new(sz.X, 0.6, 0.25), 0, sz.Y / 2 - 0.3, fz, frameC)
	cp("DD_CFrameB", Vector3.new(sz.X, 0.6, 0.25), 0, -sz.Y / 2 + 0.3, fz, frameC)
	cp("DD_CFrameL", Vector3.new(0.6, sz.Y, 0.25), -sz.X / 2 + 0.3, 0, fz, frameC)
	cp("DD_CFrameR", Vector3.new(0.6, sz.Y, 0.25), sz.X / 2 - 0.3, 0, fz, frameC)
	for _, yy in ipairs({ -sz.Y / 2 + 0.6, 0, sz.Y / 2 - 0.6 }) do
		cp("DD_CRivetL", Vector3.new(0.2, 0.2, 0.2), -sz.X / 2 + 0.3, yy, toRoom * (sz.Z / 2 + 0.16), Color3.fromRGB(150, 150, 140), Enum.Material.Metal, Enum.PartType.Ball)
		cp("DD_CRivetR", Vector3.new(0.2, 0.2, 0.2), sz.X / 2 - 0.3, yy, toRoom * (sz.Z / 2 + 0.16), Color3.fromRGB(150, 150, 140), Enum.Material.Metal, Enum.PartType.Ball)
	end
	local ring = cp("DD_CPortRing", Vector3.new(0.4, 2.2, 2.2), 0, sz.Y / 4, toRoom * (sz.Z / 2 + 0.05), Color3.fromRGB(80, 84, 90), Enum.Material.Metal, Enum.PartType.Cylinder)
	ring.Orientation = Vector3.new(0, 90, 0)
	local glass = cp("DD_CPortGlass", Vector3.new(0.3, 1.7, 1.7), 0, sz.Y / 4, toRoom * (sz.Z / 2 + 0.02), Color3.fromRGB(20, 30, 38), Enum.Material.Glass, Enum.PartType.Cylinder)
	glass.Orientation = Vector3.new(0, 90, 0)
	glass.Reflectance = 0.3
	local hub = cp("DD_CWheelHub", Vector3.new(0.4, 0.5, 0.5), 0.6, -sz.Y / 8, toRoom * (sz.Z / 2 + 0.32), Color3.fromRGB(120, 124, 128), Enum.Material.Metal, Enum.PartType.Cylinder)
	hub.Orientation = Vector3.new(0, 90, 0)
	for s = 0, 3 do
		local ang = math.rad(s * 90 + 45)
		local spoke = cp("DD_CSpoke" .. s, Vector3.new(0.16, 1.5, 0.16), 0.6, -sz.Y / 8, toRoom * (sz.Z / 2 + 0.26), Color3.fromRGB(110, 114, 118), Enum.Material.Metal)
		spoke.CFrame = CFrame.new(d.Position.X + 0.6, d.Position.Y - sz.Y / 8, d.Position.Z + toRoom * (sz.Z / 2 + 0.26)) * CFrame.Angles(0, 0, ang)
	end
	cp("DD_CReaderBox", Vector3.new(0.8, 1.2, 0.2), sz.X / 2 - 1.0, -sz.Y / 6, toRoom * (sz.Z / 2 + 0.1), Color3.fromRGB(30, 32, 36))
	cp("DD_CReaderLED", Vector3.new(0.3, 0.3, 0.18), sz.X / 2 - 1.0, -sz.Y / 6 + 0.35, toRoom * (sz.Z / 2 + 0.22), Color3.fromRGB(220, 40, 30), Enum.Material.Neon)
	local plate = cp("DD_CPlate", Vector3.new(3, 0.8, 0.12), 0, -sz.Y / 2 + 1.4, toRoom * (sz.Z / 2 + 0.06), Color3.fromRGB(40, 36, 30))
	local sg = Instance.new("SurfaceGui")
	sg.Name = "DD_CPlateGui"
	sg.Face = (toRoom > 0) and Enum.NormalId.Back or Enum.NormalId.Front
	sg.LightInfluence = 0.3 ; sg.PixelsPerStud = 70 ; sg.Parent = plate
	local tl = Instance.new("TextLabel")
	tl.BackgroundTransparency = 1 ; tl.Size = UDim2.fromScale(1, 1) ; tl.Font = Enum.Font.GothamBold
	tl.Text = "CAPTAIN" ; tl.TextColor3 = Color3.fromRGB(196, 184, 150) ; tl.TextScaled = true ; tl.Parent = sg
end

-- Dress the aft ExteriorPassage as a sealed wooden cargo crate (steel banding, corner
-- brackets, rivets, a hasp + padlock, a CARGO/DO NOT OPEN stencil, and a faint sickly
-- glow leaking from the seam). Greeble named DD_X* (idempotent under Dress's DD_ clear).
local function dressExterior()
	local ex
	for _, p in ipairs(CollectionService:GetTagged("Interactable")) do
		if p:IsA("BasePart") and p:GetAttribute("Kind") == "exterior" then ex = p ; break end
	end
	if not ex then return end
	for _, c in ipairs(ex:GetChildren()) do if c.Name:sub(1, 4) == "DD_X" then c:Destroy() end end
	ex.Material = Enum.Material.WoodPlanks
	ex.Color = Color3.fromRGB(74, 56, 38)
	ex.Reflectance = 0
	local sz = ex.Size
	local hx, hy, hz = sz.X / 2, sz.Y / 2, sz.Z / 2
	local toRoom = (ex.Position.Z < 0) and 1 or -1
	local steel = Color3.fromRGB(66, 70, 76)
	local function xp(name, size, ox, oy, oz, color, mat, shape)
		local p = box(name, size, Vector3.new(ex.Position.X + ox, ex.Position.Y + oy, ex.Position.Z + oz), color, ex)
		p.CanCollide = false ; p.CanQuery = false ; p.CastShadow = false
		p.Material = mat or Enum.Material.Metal
		if shape then p.Shape = shape end
		return p
	end
	for i, yo in ipairs({ -hy * 0.5, hy * 0.5 }) do
		xp("DD_XBandH" .. i, Vector3.new(sz.X + 0.18, 0.5, sz.Z + 0.18), 0, yo, 0, steel)
	end
	local corners = { {hx, hz}, {hx, -hz}, {-hx, hz}, {-hx, -hz} }
	for i, c in ipairs(corners) do
		xp("DD_XCorner" .. i, Vector3.new(0.5, sz.Y + 0.18, 0.5), c[1], 0, c[2], steel)
		for r = -1, 1 do
			xp("DD_XRivet" .. i .. "_" .. (r + 1), Vector3.new(0.22, 0.22, 0.22), c[1], r * hy * 0.55, c[2], Color3.fromRGB(120, 126, 120), Enum.Material.Metal, Enum.PartType.Ball)
		end
	end
	local panel = xp("DD_XPanel", Vector3.new(sz.X - 1.0, sz.Y - 1.2, 0.1), 0, 0, toRoom * (hz + 0.03), Color3.fromRGB(60, 46, 32), Enum.Material.WoodPlanks)
	xp("DD_XHasp", Vector3.new(1.6, 0.5, 0.2), 0, 0, toRoom * (hz + 0.12), Color3.fromRGB(92, 96, 102), Enum.Material.Metal)
	xp("DD_XLock", Vector3.new(0.7, 0.9, 0.4), 0, -0.1, toRoom * (hz + 0.26), Color3.fromRGB(150, 150, 60), Enum.Material.Metal)
	local shackle = xp("DD_XShackle", Vector3.new(0.45, 0.45, 0.18), 0, 0.42, toRoom * (hz + 0.26), Color3.fromRGB(172, 176, 182), Enum.Material.Metal, Enum.PartType.Cylinder)
	shackle.Orientation = Vector3.new(0, 90, 0)
	local seam = xp("DD_XSeam", Vector3.new(sz.X - 1.4, 0.08, 0.05), 0, hy * 0.5, toRoom * (hz + 0.07), Color3.fromRGB(80, 200, 170), Enum.Material.Neon)
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(70, 200, 170) ; glow.Brightness = 0.6 ; glow.Range = 7 ; glow.Shadows = false ; glow.Parent = seam
	local sg = Instance.new("SurfaceGui")
	sg.Name = "DD_XStencil"
	sg.Face = (toRoom > 0) and Enum.NormalId.Back or Enum.NormalId.Front
	sg.LightInfluence = 0.4 ; sg.PixelsPerStud = 60 ; sg.Parent = panel
	local stripe = Instance.new("Frame")
	stripe.Size = UDim2.fromScale(1, 0.16) ; stripe.Position = UDim2.fromScale(0, 0.42)
	stripe.BackgroundColor3 = Color3.fromRGB(150, 40, 35) ; stripe.BackgroundTransparency = 0.1 ; stripe.BorderSizePixel = 0 ; stripe.Parent = sg
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1 ; lbl.Size = UDim2.fromScale(0.92, 0.22) ; lbl.Position = UDim2.fromScale(0.04, 0.12)
	lbl.Font = Enum.Font.GothamBlack ; lbl.Text = "CARGO" ; lbl.TextColor3 = Color3.fromRGB(220, 210, 180) ; lbl.TextScaled = true ; lbl.Parent = sg
	local lbl2 = Instance.new("TextLabel")
	lbl2.BackgroundTransparency = 1 ; lbl2.Size = UDim2.fromScale(0.92, 0.13) ; lbl2.Position = UDim2.fromScale(0.04, 0.7)
	lbl2.Font = Enum.Font.GothamBold ; lbl2.Text = "DO NOT OPEN" ; lbl2.TextColor3 = Color3.fromRGB(205, 85, 72) ; lbl2.TextScaled = true ; lbl2.Parent = sg
end

-- Dress the wall safe (Section 4) as a proper round-door vault: steel body, raised
-- door frame, circular vault door with a spoke wheel + combination dial, rim bolts
-- and hinges. Greeble named DD_Sf* (idempotent under Dress's DD_ clear).
local function dressSafe()
	local sf
	for _, p in ipairs(CollectionService:GetTagged("Interactable")) do
		if p:IsA("BasePart") and p:GetAttribute("Kind") == "safe" then sf = p ; break end
	end
	if not sf then return end
	for _, c in ipairs(sf:GetChildren()) do if c.Name:sub(1, 4) == "DD_S" then c:Destroy() end end
	sf.Material = Enum.Material.Metal
	sf.Color = Color3.fromRGB(48, 52, 58)
	sf.Reflectance = 0.08
	local sz = sf.Size
	local toRoom = (sf.Position.Z < 0) and 1 or -1
	local faceZ = sz.Z / 2
	local function sp(name, size, ox, oy, oz, color, mat, shape)
		local p = box(name, size, Vector3.new(sf.Position.X + ox, sf.Position.Y + oy, sf.Position.Z + oz), color, sf)
		p.CanCollide = false ; p.CanQuery = false ; p.CastShadow = false
		p.Material = mat or Enum.Material.Metal
		if shape then p.Shape = shape end
		return p
	end
	sp("DD_SfFrame", Vector3.new(sz.X * 0.96, sz.Y * 0.96, 0.2), 0, 0, toRoom * (faceZ + 0.04), Color3.fromRGB(36, 40, 46))
	local door = sp("DD_SfDoor", Vector3.new(0.45, sz.Y * 0.78, sz.Y * 0.78), 0, 0, toRoom * (faceZ + 0.16), Color3.fromRGB(64, 70, 78), Enum.Material.Metal, Enum.PartType.Cylinder)
	door.Orientation = Vector3.new(0, 90, 0)
	local hub = sp("DD_SfHub", Vector3.new(0.35, 0.5, 0.5), 0, 0, toRoom * (faceZ + 0.5), Color3.fromRGB(150, 156, 150), Enum.Material.Metal, Enum.PartType.Cylinder)
	hub.Orientation = Vector3.new(0, 90, 0)
	for s = 0, 3 do
		local ang = math.rad(s * 90 + 45)
		local spoke = sp("DD_SfSpoke" .. s, Vector3.new(0.18, 1.5, 0.18), 0, 0, toRoom * (faceZ + 0.42), Color3.fromRGB(140, 146, 140), Enum.Material.Metal)
		spoke.CFrame = CFrame.new(sf.Position.X, sf.Position.Y, sf.Position.Z + toRoom * (faceZ + 0.42)) * CFrame.Angles(0, 0, ang)
	end
	local dial = sp("DD_SfDial", Vector3.new(0.3, 0.8, 0.8), 0, -sz.Y * 0.28, toRoom * (faceZ + 0.22), Color3.fromRGB(28, 30, 34), Enum.Material.Metal, Enum.PartType.Cylinder)
	dial.Orientation = Vector3.new(0, 90, 0)
	sp("DD_SfDialKnob", Vector3.new(0.4, 0.18, 0.18), 0, -sz.Y * 0.28 + 0.3, toRoom * (faceZ + 0.34), Color3.fromRGB(182, 188, 182), Enum.Material.Metal)
	for s = 0, 5 do
		local ang = math.rad(s * 60)
		local r = sz.Y * 0.42
		sp("DD_SfBolt" .. s, Vector3.new(0.22, 0.22, 0.22), math.cos(ang) * r, math.sin(ang) * r, toRoom * (faceZ + 0.12), Color3.fromRGB(120, 126, 120), Enum.Material.Metal, Enum.PartType.Ball)
	end
	sp("DD_SfHingeT", Vector3.new(0.4, 0.5, 0.5), -sz.X * 0.45, sz.Y * 0.28, toRoom * (faceZ + 0.1), Color3.fromRGB(90, 96, 90), Enum.Material.Metal)
	sp("DD_SfHingeB", Vector3.new(0.4, 0.5, 0.5), -sz.X * 0.45, -sz.Y * 0.28, toRoom * (faceZ + 0.1), Color3.fromRGB(90, 96, 90), Enum.Material.Metal)
end

-- Re-skin the hiding-spot cabinets so they read as real steel lockers (door seam,
-- louvre vents, handle, latch, number plate). Greeble parents to the locker itself so
-- CreatureManager.toggleHide can fade it all translucent while a player hides inside.
local function dressLockers()
	for _, lk in ipairs(CollectionService:GetTagged("HidingSpot")) do
		if lk:IsA("BasePart") then
			for _, c in ipairs(lk:GetChildren()) do
				if c.Name:sub(1, 4) == "DD_L" then c:Destroy() end
			end
			lk.Material = Enum.Material.DiamondPlate
			lk.Color = Color3.fromRGB(84, 96, 88)
			lk.Reflectance = 0.04
			local sz = lk.Size
			local toRoom = (lk.Position.Z < 0) and 1 or -1
			local faceZ = sz.Z / 2
			local function fp(name, size, ox, oy, oz, color, mat)
				local p = box(name, size, Vector3.new(lk.Position.X + ox, lk.Position.Y + oy, lk.Position.Z + oz), color, lk)
				p.CanCollide = false ; p.CanQuery = false ; p.CastShadow = false
				p.Material = mat or Enum.Material.DiamondPlate
				return p
			end
			fp("DD_LkDoor", Vector3.new(sz.X - 0.5, sz.Y - 0.7, 0.12), 0, 0, toRoom * (faceZ + 0.02), Color3.fromRGB(70, 82, 76))
			for band = 0, 1 do
				for s = 0, 2 do
					fp("DD_LkVent" .. band .. s, Vector3.new(sz.X - 1.1, 0.12, 0.18),
						0, sz.Y / 2 - 0.9 - band * 1.0 - s * 0.28, toRoom * (faceZ + 0.09),
						Color3.fromRGB(38, 44, 41))
				end
			end
			fp("DD_LkHandle", Vector3.new(0.18, 1.6, 0.32), sz.X / 2 - 0.4, -0.4, toRoom * (faceZ + 0.14), Color3.fromRGB(150, 156, 150), Enum.Material.Metal)
			fp("DD_LkLatch", Vector3.new(0.5, 0.5, 0.32), sz.X / 2 - 0.4, 0.55, toRoom * (faceZ + 0.14), Color3.fromRGB(110, 116, 110), Enum.Material.Metal)
			local plate = fp("DD_LkNum", Vector3.new(0.95, 0.55, 0.1), -(sz.X / 2 - 0.85), sz.Y / 2 - 0.6, toRoom * (faceZ + 0.06), Color3.fromRGB(26, 30, 28))
			local sg = Instance.new("SurfaceGui")
			sg.Name = "DD_LkNumGui"
			sg.Face = (toRoom > 0) and Enum.NormalId.Back or Enum.NormalId.Front
			sg.LightInfluence = 0.2 ; sg.PixelsPerStud = 90 ; sg.Parent = plate
			local tl = Instance.new("TextLabel")
			tl.BackgroundTransparency = 1 ; tl.Size = UDim2.fromScale(1, 1)
			tl.Font = Enum.Font.GothamBold
			tl.Text = string.format("%02d", math.max(1, math.floor(lk.Position.X / 3)))
			tl.TextColor3 = Color3.fromRGB(205, 212, 202) ; tl.TextScaled = true ; tl.Parent = sg
		end
	end
end

-- Turn the thin wall 'Bunk' slabs into proper beds: padded mattress, pillow, rumpled
-- blanket, steel frame rails, and corner posts (stacked bunks post to the bed below).
local function dressBunks()
	for _, sec in ipairs(root:GetChildren()) do
		if sec:IsA("Model") then
			local bunks = {}
			for _, bk in ipairs(sec:GetChildren()) do
				if bk:IsA("BasePart") and bk.Name:match("^Bunk") then table.insert(bunks, bk) end
			end
			for _, bk in ipairs(bunks) do
				for _, c in ipairs(bk:GetChildren()) do if c.Name:sub(1, 4) == "DD_B" then c:Destroy() end end
				bk.Material = Enum.Material.Fabric
				bk.Color = Color3.fromRGB(128, 119, 104)
				local sz = bk.Size
				local px, py, pz = bk.Position.X, bk.Position.Y, bk.Position.Z
				local function bp(name, size, ox, oy, oz, color, mat)
					local p = box(name, size, Vector3.new(px + ox, py + oy, pz + oz), color, bk)
					p.CanCollide = false ; p.CanQuery = false ; p.CastShadow = false
					p.Material = mat or Enum.Material.Metal
					return p
				end
				local frameC = Color3.fromRGB(72, 76, 82)
				bp("DD_BMattress", Vector3.new(sz.X - 0.2, 0.5, sz.Z - 0.2), 0, 0.45, 0, Color3.fromRGB(150, 142, 128), Enum.Material.Fabric)
				bp("DD_BRailZ1", Vector3.new(sz.X + 0.3, 0.55, 0.3), 0, -0.05, sz.Z / 2, frameC)
				bp("DD_BRailZ2", Vector3.new(sz.X + 0.3, 0.55, 0.3), 0, -0.05, -sz.Z / 2, frameC)
				bp("DD_BRailX1", Vector3.new(0.3, 0.7, sz.Z + 0.3), sz.X / 2, -0.05, 0, frameC)
				bp("DD_BRailX2", Vector3.new(0.3, 0.7, sz.Z + 0.3), -sz.X / 2, -0.05, 0, frameC)
				bp("DD_BPillow", Vector3.new(1.5, 0.55, sz.Z - 0.7), -sz.X / 2 + 1.1, 0.72, 0, Color3.fromRGB(186, 182, 172), Enum.Material.Fabric)
				bp("DD_BBlanket", Vector3.new(sz.X * 0.5, 0.5, sz.Z + 0.12), sz.X * 0.2, 0.55, 0, Color3.fromRGB(74, 58, 52), Enum.Material.Fabric)
				local belowY
				for _, other in ipairs(bunks) do
					if other ~= bk and math.abs(other.Position.X - px) < 2 and math.abs(other.Position.Z - pz) < 2 and other.Position.Y < py - 0.5 then
						belowY = math.max(belowY or -1e9, other.Position.Y)
					end
				end
				local postH = math.max(py - (belowY or 0), 0.6)
				for _, cc in ipairs({ {sz.X / 2 - 0.4, sz.Z / 2 - 0.4}, {sz.X / 2 - 0.4, -(sz.Z / 2 - 0.4)}, {-(sz.X / 2 - 0.4), sz.Z / 2 - 0.4}, {-(sz.X / 2 - 0.4), -(sz.Z / 2 - 0.4)} }) do
					bp("DD_BPost", Vector3.new(0.32, postH, 0.32), cc[1], -postH / 2 - 0.2, cc[2], frameC)
				end
			end
		end
	end
end

-- Settle each floating journal page onto whatever is directly below it (table, console,
-- bunk, safe...). If it would lie on bare deck, drop a small worn crate under it so it
-- reads as resting ON something. Runs last so bunk bedding etc. already exists.
local function placeJournals()
	local baseExclude = {}
	for _, w in ipairs(CollectionService:GetTagged("WaterPlane")) do table.insert(baseExclude, w) end
	for _, hb in ipairs(CollectionService:GetTagged("HullBreach")) do table.insert(baseExclude, hb) end
	for _, j in ipairs(CollectionService:GetTagged("Journal")) do
		if j:IsA("BasePart") then
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			local filter = { j }
			for _, e in ipairs(baseExclude) do table.insert(filter, e) end
			params.FilterDescendantsInstances = filter
			local r = Workspace:Raycast(j.Position + Vector3.new(0, 0.4, 0), Vector3.new(0, -30, 0), params)
			if r then
				local surfaceY = r.Position.Y
				if r.Instance.Name:match("Floor") then
					local crateH = 0.8
					local crate = box("DD_JrRest_" .. j.Name, Vector3.new(1.8, crateH, 1.4), Vector3.new(j.Position.X, surfaceY + crateH / 2, j.Position.Z), Color3.fromRGB(78, 60, 40), j.Parent)
					crate.Material = Enum.Material.WoodPlanks
					crate.CanCollide = false ; crate.CanQuery = false ; crate.CastShadow = false
					j.Position = Vector3.new(j.Position.X, surfaceY + crateH + 0.08, j.Position.Z)
				else
					j.Position = Vector3.new(j.Position.X, surfaceY + 0.12, j.Position.Z)
				end
			end
			-- Keep the visible page parts on the (prompt-holding) root so the [E] Read
			-- prompt is always where the page is (fixes the detached galley journal).
			local kids, sum = {}, Vector3.zero
			for _, cp in ipairs(j:GetDescendants()) do
				if cp:IsA("BasePart") then kids[#kids + 1] = cp; sum += cp.Position end
			end
			if #kids > 0 then
				local delta = j.Position - (sum / #kids)
				if delta.Magnitude > 3 then
					for _, cp in ipairs(kids) do cp.Position += delta end
				end
			end
		end
	end
end

-- Survivors wall (Supporter Pass perk): a lit memorial plaque of supporter names,
-- mounted on the bow wall of the spawn room (Section 1), straight opposite the
-- aft door and facing into the room. MonetizationManager finds it by the
-- "SurvivorsWall" tag and fills the "Names" label. Named DD_* so Dress() rebuilds it.
local function dressSurvivorsWall()
	if not root then return end
	local model = root:FindFirstChild("Section_1_forward_torpedo")
	if not model then return end
	local wall = Instance.new("Part")
	wall.Name = "DD_SurvivorsWall"
	wall.Anchored = true; wall.CanCollide = false; wall.CastShadow = false
	wall.Size = Vector3.new(9, 5.5, 0.3)
	wall.CFrame = CFrame.new(-23.8, 8, 0) * CFrame.Angles(0, math.rad(-90), 0)   -- bow wall opposite the aft door (interior face x=-24), centered z=0 above the torpedo tubes; Front face -> +X into the room
	wall.Color = Color3.fromRGB(20, 24, 30); wall.Material = Enum.Material.Metal
	wall.Parent = model
	tag(wall, "SurvivorsWall")
	local board = Instance.new("SurfaceGui")
	board.Name = "Board"; board.Face = Enum.NormalId.Front   -- -Z face, toward the room
	board.CanvasSize = Vector2.new(720, 440); board.LightInfluence = 0; board.Parent = wall
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1); bg.BackgroundColor3 = Color3.fromRGB(20, 27, 34)
	bg.BackgroundTransparency = 0.05; bg.BorderSizePixel = 0; bg.Parent = board
	local stroke = Instance.new("UIStroke"); stroke.Color = Color3.fromRGB(120, 190, 220)
	stroke.Thickness = 4; stroke.Transparency = 0.15; stroke.Parent = bg
	local wtitle = Instance.new("TextLabel")
	wtitle.Position = UDim2.fromScale(0, 0.06); wtitle.Size = UDim2.new(1, 0, 0, 60)
	wtitle.BackgroundTransparency = 1; wtitle.Font = Enum.Font.GothamBold; wtitle.TextScaled = true
	wtitle.TextColor3 = Color3.fromRGB(150, 200, 220); wtitle.Text = "SUPPORTERS"; wtitle.Parent = bg
	local wsub = Instance.new("TextLabel")
	wsub.Position = UDim2.fromScale(0.06, 0.19); wsub.Size = UDim2.new(0.88, 0, 0, 26)
	wsub.BackgroundTransparency = 1; wsub.Font = Enum.Font.Merriweather; wsub.TextSize = 18
	wsub.TextColor3 = Color3.fromRGB(150, 160, 170)
	wsub.Text = "In gratitude to those who kept the lights on."; wsub.Parent = bg
	local names = Instance.new("TextLabel")
	names.Name = "Names"; names.Position = UDim2.fromScale(0.06, 0.29); names.Size = UDim2.fromScale(0.88, 0.66)
	names.BackgroundTransparency = 1; names.Font = Enum.Font.Gotham; names.TextSize = 26
	names.TextColor3 = Color3.fromRGB(220, 228, 235); names.TextWrapped = true
	names.TextXAlignment = Enum.TextXAlignment.Center; names.TextYAlignment = Enum.TextYAlignment.Top
	names.Text = "No supporters yet."; names.Parent = bg
	local lp = Instance.new("PointLight")
	lp.Color = Color3.fromRGB(150, 200, 220); lp.Range = 10; lp.Brightness = 0.8; lp.Shadows = false
	lp.Parent = wall
end

-- Entry point for the dressing pass (idempotent; safe to call standalone or after Build).
function MapBuilder.Dress()
	if not root then root = Workspace:FindFirstChild("Submarine") end
	if not root then warn("[HullBreach] MapBuilder.Dress: no Submarine root found") return end
	for _, d in ipairs(root:GetDescendants()) do
		if d.Name:sub(1, 3) == "DD_" then d:Destroy() end
	end
	local n = 0
	for i = 1, SectionData.COUNT do
		local data = SectionData.Sections[i]
		local model = root:FindFirstChild(("Section_%d_%s"):format(i, data.id))
		if model then
			local folder = Instance.new("Folder")
			folder.Name = "DD_Dressing"
			folder.Parent = model
			local cx = SectionData.SectionCenter(i).X
			if i == 7 then
				dressPeriscope(folder, model)
			else
				dressIndustrial(folder, cx)
				if i == 2 then dressBerthing(folder, model, cx)
				elseif i == 3 then dressGalley(folder, model, cx) ; dressNotice(folder, model, cx)
				elseif i == 4 then dressOfficers(folder, model, cx)
				elseif i == 5 then dressConsole(folder, model, "Helm") ; dressConsole(folder, model, "NavConsole") ; dressConsole(folder, model, "BallastPanel")
				elseif i == 6 then dressConsole(folder, model, "SonarConsole") ; dressConsole(folder, model, "RadioConsole") ; dressSonarRadio(folder, model, cx)
				elseif i == 8 then dressGenerator(folder, model)
				elseif i == 9 then dressBreach(folder, model, cx) ; dressAft(folder, model, cx)
				end
			end
			n += 1
		end
	end
	dressLockers()
	dressSafe()
	dressExterior()
	dressCaptainDoor()
	dressBunks()
	placeJournals()
	dressSurvivorsWall()
	print(("[HullBreach] MapBuilder: dressing applied to %d sections + lockers + vault + cargo + bunks/journals + survivors wall (code-driven, idempotent)."):format(n))
end

function MapBuilder.GetRoot(): Folder?
	return root
end

-- ----------------------------------------------------------------------------
-- Main-menu scene: a stylized exterior submarine resting in dark water far from
-- the playable hull (GDD 7.4). Built in code so it can't be lost; MenuUI parks
-- the menu camera on MenuScene.CameraAnchor and slowly drifts it.
-- ----------------------------------------------------------------------------
function MapBuilder.BuildMenuScene()
  local old = Workspace:FindFirstChild("MenuScene")
  if old then old:Destroy() end
  local scene = Instance.new("Model")
  scene.Name = "MenuScene"
  local origin = Vector3.new(0, -500, 0)  -- well clear of the playable sub
  local function piece(name, size, cf, color, mat, shape)
    local p = Instance.new("Part")
    p.Name = name; p.Anchored = true; p.CanCollide = false; p.CastShadow = false
    p.Size = size; p.CFrame = cf
    p.Color = color or Color3.fromRGB(40, 46, 52)
    p.Material = mat or Enum.Material.Metal
    if shape then p.Shape = shape end
    p.Parent = scene
    return p
  end
  local hullLen = 60
  -- hull body (cylinder axis runs along X by default)
  piece("Hull", Vector3.new(hullLen, 14, 14), CFrame.new(origin), Color3.fromRGB(38, 44, 50), Enum.Material.Metal, Enum.PartType.Cylinder)
  piece("Nose", Vector3.new(14, 14, 14), CFrame.new(origin + Vector3.new(hullLen/2, 0, 0)), Color3.fromRGB(38, 44, 50), Enum.Material.Metal, Enum.PartType.Ball)
  piece("Tail", Vector3.new(14, 14, 14), CFrame.new(origin + Vector3.new(-hullLen/2, 0, 0)), Color3.fromRGB(34, 40, 46), Enum.Material.Metal, Enum.PartType.Ball)
  piece("Tower", Vector3.new(10, 10, 7), CFrame.new(origin + Vector3.new(2, 9, 0)), Color3.fromRGB(34, 40, 46))
  piece("Periscope", Vector3.new(0.6, 5, 0.6), CFrame.new(origin + Vector3.new(2, 15, 0)), Color3.fromRGB(60, 66, 72))
  piece("FinV", Vector3.new(8, 7, 1), CFrame.new(origin + Vector3.new(-hullLen/2 + 4, 4, 0)))
  piece("FinH", Vector3.new(8, 1, 16), CFrame.new(origin + Vector3.new(-hullLen/2 + 4, 0, 0)))
  -- flickering portholes down the near side
  for i = 1, 7 do
    local x = origin.X + (i - 4) * 7
    local pw = piece("Porthole" .. i, Vector3.new(0.4, 2.4, 2.4), CFrame.new(x, origin.Y + 1.5, origin.Z + 7) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(255, 170, 90), Enum.Material.Neon, Enum.PartType.Cylinder)
    local lt = Instance.new("PointLight")
    lt.Color = Color3.fromRGB(255, 180, 110); lt.Range = 14; lt.Brightness = 2; lt.Shadows = false; lt.Parent = pw
    task.spawn(function()
      while pw.Parent do
        task.wait(0.05 + math.random() * 0.3)
        local on = math.random() > 0.16
        lt.Enabled = on
        pw.Material = on and Enum.Material.Neon or Enum.Material.Glass
      end
    end)
  end
  -- drifting marine snow / bubbles
  local fx = piece("FX", Vector3.new(hullLen + 40, 44, 44), CFrame.new(origin), Color3.new(0, 0, 0), Enum.Material.Plastic)
  fx.Transparency = 1
  local em = Instance.new("ParticleEmitter")
  em.Rate = 26; em.Lifetime = NumberRange.new(4, 8); em.Speed = NumberRange.new(1, 3)
  em.SpreadAngle = Vector2.new(45, 45); em.Acceleration = Vector3.new(0, 3, 0)
  em.Color = ColorSequence.new(Color3.fromRGB(180, 210, 220))
  em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
  em.Size = NumberSequence.new(0.2); em.Parent = fx
  -- faint cold key light so the silhouette reads
  local kp = piece("KeyLight", Vector3.new(1, 1, 1), CFrame.new(origin + Vector3.new(18, 20, 34)), Color3.new(0, 0, 0))
  kp.Transparency = 1
  local kl = Instance.new("PointLight"); kl.Color = Color3.fromRGB(120, 150, 180); kl.Range = 120; kl.Brightness = 1.1; kl.Shadows = false; kl.Parent = kp
  -- camera anchor: in front (+Z) and slightly above, looking at the hull centre
  local cam = piece("CameraAnchor", Vector3.new(1, 1, 1), CFrame.lookAt(origin + Vector3.new(9, 6, 46), origin), Color3.new(0, 0, 0))
  cam.Transparency = 1
  scene.Parent = Workspace
  return scene
end

function MapBuilder.Start()
	MapBuilder.Build()
	MapBuilder.Dress()
	MapBuilder.BuildMenuScene()
end

return MapBuilder
