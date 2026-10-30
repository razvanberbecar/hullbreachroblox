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
	p.CanTouch = false
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

-- ----------------------------------------------------------------------------
-- Pressure-hull structure (visual batches 3a/3b). The rooms are boxes, so this
-- builds what makes them read as the inside of a hull: an arched cross-section
-- (faceted plates rounding every wall/ceiling and wall/floor corner), a heavy
-- frame every 6 studs following that arch, pipe bundles with flanges, hangers and
-- paint bands, cable trays with sagging cables, and valves teed off the pipes.
-- All of it is visual only (CanCollide/CanQuery/CanTouch off), so it can never
-- block movement, prompts or the creature.
-- ----------------------------------------------------------------------------
local HULL = {
	frame = Color3.fromRGB(58, 60, 64),
	plate = Color3.fromRGB(62, 62, 64),
	pipeSteel = Color3.fromRGB(84, 88, 92),
	pipeRust = Color3.fromRGB(112, 72, 50),
	pipeNavy = Color3.fromRGB(44, 60, 78),
	pipeCopper = Color3.fromRGB(128, 88, 58),
	tray = Color3.fromRGB(46, 48, 52),
	cable = Color3.fromRGB(16, 16, 18),
	bandRed = Color3.fromRGB(150, 44, 34),
	bandYellow = Color3.fromRGB(176, 136, 44),
	bandBlue = Color3.fromRGB(44, 86, 124),
}
local FRAME_OFFSETS = { -21, -15, -9, -3, 3, 9, 15, 21 }
local ARCH_R = 3.4          -- radius of the upper corner arch
local ARCH_Y = IH - ARCH_R  -- where the arch springs from the wall
local ARCH_Z = IW / 2 - ARCH_R

-- a box spanning two points in the Y/Z cross-section, running `len` along X
local function crossBeam(parent, name, x, len, thick, y0, z0, y1, z1, color, material, variant)
	local a, b = Vector3.new(x, y0, z0), Vector3.new(x, y1, z1)
	local span = (b - a).Magnitude
	local p = ddPart(parent, name, Vector3.new(len, thick, span + 0.06), (a + b) / 2, color, material)
	-- part Z runs along the span; part Y is the plate's normal in the cross-section
	p.CFrame = CFrame.lookAt((a + b) / 2, b, Vector3.new(1, 0, 0)) * CFrame.Angles(0, 0, math.rad(90))
	if variant then p.MaterialVariant = variant end
	return p
end

-- arc point at angle `deg` (0 = on the wall, 90 = on the ceiling) on side s (+1/-1)
local function archPoint(deg: number, s: number, inset: number)
	local r = ARCH_R - inset
	return ARCH_Y + r * math.sin(math.rad(deg)), s * (ARCH_Z + r * math.cos(math.rad(deg)))
end

local function dressArch(folder, cx, ceilingVariant)
	for _, s in ipairs({ -1, 1 }) do
		-- upper corners: three plates rounding the wall into the ceiling
		for seg = 0, 2 do
			local y0, z0 = archPoint(seg * 30, s, 0.05)
			local y1, z1 = archPoint((seg + 1) * 30, s, 0.05)
			crossBeam(folder, "DD_ArchPlate", cx, IL, 0.3, y0, z0, y1, z1, HULL.plate, Enum.Material.Metal, ceilingVariant)
		end
		-- lower corners: a shallow bilge chamfer
		crossBeam(folder, "DD_BilgePlate", cx, IL, 0.3, 1.5, s * (IW / 2 - 0.05), 0.02, s * (IW / 2 - 1.5), HULL.plate, Enum.Material.Metal, ceilingVariant)
	end
end

local function dressFrames(folder, cx)
	local D = 0.85 -- how far a frame stands proud of the plating
	for _, ox in ipairs(FRAME_OFFSETS) do
		local x = cx + ox
		local function frame(name, y0, z0, y1, z1)
			local f = crossBeam(folder, name, x, 0.75, D, y0, z0, y1, z1, HULL.frame, Enum.Material.Metal, "MG-Rust 24")
			f.CastShadow = true -- the lantern throws the frames' shadows down the room
			return f
		end
		frame("DD_FrameTop", IH - D / 2, -ARCH_Z, IH - D / 2, ARCH_Z)
		for _, s in ipairs({ -1, 1 }) do
			local wz = s * (IW / 2 - D / 2)
			frame("DD_FrameSide", 1.6, wz, ARCH_Y, wz)
			for seg = 0, 2 do
				local y0, z0 = archPoint(seg * 30, s, D / 2)
				local y1, z1 = archPoint((seg + 1) * 30, s, D / 2)
				frame("DD_FrameArch", y0, z0, y1, z1)
			end
			frame("DD_FrameFoot", 1.6, wz, 0.1, s * (IW / 2 - 1.5))
		end
	end
	-- longitudinal stringers tying the frames together
	for _, s in ipairs({ -1, 1 }) do
		for _, y in ipairs({ 4.2, 8.6 }) do
			ddPart(folder, "DD_Stringer", Vector3.new(IL, 0.35, 0.3), Vector3.new(cx, y, s * (IW / 2 - 0.15)), HULL.frame, Enum.Material.Metal).MaterialVariant = "MG-Rust 24"
		end
	end
end

-- one pipe running along X with bolted flanges at the given offsets
local function pipeRun(folder, name, cx, y, z, diam, color, variant, flangeAt)
	local p = ddCyl(folder, name, IL, diam, Vector3.new(cx, y, z), "X", color, Enum.Material.Metal)
	p.CastShadow = true
	if variant then p.MaterialVariant = variant end
	for _, ox in ipairs(flangeAt) do
		ddCyl(folder, "DD_Flange", 0.26, diam + 0.3, Vector3.new(cx + ox, y, z), "X", DD.dark, Enum.Material.Metal)
	end
	return p
end

local function paintBand(folder, cx, ox, y, z, diam, color)
	ddCyl(folder, "DD_PipeBand", 0.9, diam + 0.04, Vector3.new(cx + ox, y, z), "X", color, Enum.Material.SmoothPlastic)
end

local function dressPipes(folder, i, cx)
	local flip = (i % 2 == 0) and -1 or 1   -- rooms differ: bundle offset and paint codes alternate
	local shift = (i % 3) * 2
	-- +Z: the main bundle, under the arch
	pipeRun(folder, "DD_PipeMain", cx, 14.5, 9.2, 0.8, HULL.pipeRust, "MG-Rust 14", { -18 + shift, -6 + shift, 6 + shift, 18 - shift })
	pipeRun(folder, "DD_PipeB", cx, 14.65, 10.25, 0.5, HULL.pipeSteel, nil, { -12 + shift, 12 - shift })
	pipeRun(folder, "DD_PipeC", cx, 13.85, 10.35, 0.36, HULL.pipeCopper, nil, { -8 - shift, 16 })
	paintBand(folder, cx, -12 * flip, 14.5, 9.2, 0.8, (i % 3 == 0) and HULL.bandRed or HULL.bandYellow)
	paintBand(folder, cx, 12 * flip, 14.5, 9.2, 0.8, (i % 3 == 0) and HULL.bandRed or HULL.bandYellow)
	paintBand(folder, cx, 7 * flip, 14.65, 10.25, 0.5, HULL.bandBlue)
	-- -Z: a second, thinner run against the arch
	pipeRun(folder, "DD_PipeD", cx, 14.1, -10.4, 0.55, HULL.pipeNavy, nil, { -15, 3 + shift })
	-- hangers from the frames
	for _, ox in ipairs({ -15, -3, 9, 21 }) do
		ddPart(folder, "DD_Hanger", Vector3.new(0.14, 0.95, 1.9), Vector3.new(cx + ox + 0.45, 15.05, 9.7), DD.dark, Enum.Material.Metal)
	end
	-- wall conduit + junction boxes
	ddPart(folder, "DD_Conduit", Vector3.new(IL, 0.32, 0.32), Vector3.new(cx, 2.9, -IW / 2 + 0.5), DD.dark)
	ddPart(folder, "DD_Conduit2", Vector3.new(IL, 0.22, 0.22), Vector3.new(cx, 3.35, -IW / 2 + 0.5), DD.dark)
	for _, ox in ipairs({ -12 + shift, 6 + shift }) do
		ddPart(folder, "DD_JunctionBox", Vector3.new(1.4, 1.5, 0.45), Vector3.new(cx + ox, 3.2, -IW / 2 + 0.55), HULL.tray, Enum.Material.Metal)
		ddCyl(folder, "DD_Riser", 8.6, 0.2, Vector3.new(cx + ox + 0.35, 8.3, -IW / 2 + 0.4), "Y", DD.dark, Enum.Material.Metal)
	end
	-- valve teed off the main run: drop pipe, elbow, valve body, spoked wheel
	local vx = cx + ((i == 8) and -7.5 or -6) -- (§8: clear of the flywheel)
	ddCyl(folder, "DD_ValveDrop", 8.6, 0.42, Vector3.new(vx, 9.8, 10.6), "Y", HULL.pipeRust, Enum.Material.Metal).MaterialVariant = "MG-Rust 14"
	ddPart(folder, "DD_ValveElbow", Vector3.new(0.62, 0.62, 0.62), Vector3.new(vx, 14.2, 10.2), HULL.pipeRust, Enum.Material.Metal, Enum.PartType.Ball)
	ddCyl(folder, "DD_Valve", 1.1, 0.7, Vector3.new(vx, 5.4, 10.6), "Y", HULL.bandRed, Enum.Material.Metal)
	ddCyl(folder, "DD_ValveStem", 0.9, 0.14, Vector3.new(vx, 5.4, 9.85), "Z", DD.dark, Enum.Material.Metal)
	local wheel = Vector3.new(vx, 5.4, 9.42)
	ddCyl(folder, "DD_ValveHub", 0.18, 0.34, wheel, "Z", DD.dark, Enum.Material.Metal)
	for k = 0, 7 do -- rim (octagon) + spokes
		local a = math.rad(k * 45)
		local rim = wheel + Vector3.new(math.cos(a) * 0.82, math.sin(a) * 0.82, 0)
		local seg = ddPart(folder, "DD_ValveRim", Vector3.new(0.7, 0.13, 0.13), rim, HULL.bandRed, Enum.Material.Metal)
		seg.CFrame = CFrame.new(rim) * CFrame.Angles(0, 0, a + math.rad(90))
		if k % 2 == 0 then
			local spoke = ddPart(folder, "DD_ValveSpoke", Vector3.new(0.8, 0.09, 0.09), wheel + Vector3.new(math.cos(a) * 0.4, math.sin(a) * 0.4, 0), DD.dark, Enum.Material.Metal)
			spoke.CFrame = CFrame.new(wheel + Vector3.new(math.cos(a) * 0.4, math.sin(a) * 0.4, 0)) * CFrame.Angles(0, 0, a)
		end
	end
	-- gauge on the bulkhead-side run of the wall
	local g = Vector3.new(cx + ((i == 3) and 16 or 6), 6.2, IW / 2 - 0.35) -- (§3: clear of the notice board)
	ddCyl(folder, "DD_Gauge", 0.3, 1.4, g, "Z", DD.dark, Enum.Material.Metal)
	ddCyl(folder, "DD_GaugeFace", 0.05, 1.15, g - Vector3.new(0, 0, 0.17), "Z", Color3.fromRGB(176, 170, 150), Enum.Material.SmoothPlastic)
	local nx = ddPart(folder, "DD_GaugeNeedle", Vector3.new(0.5, 0.05, 0.03), g + Vector3.new(0.12, 0.12, -0.21), HULL.bandRed, Enum.Material.SmoothPlastic)
	nx.Orientation = Vector3.new(0, 0, 38 + i * 11)
	ddNeon(folder, "DD_GaugeLED", g + Vector3.new(1.1, 0.4, -0.05), Color3.fromRGB(60, 220, 90), Vector3.new(0.24, 0.24, 0.18))
end

-- cable tray on the -Z arch: open tray, cable loom inside, and loose cables sagging
-- out of it between the frames (Beams, so the sag is a real curve at almost no cost)
local function dressCableTray(folder, i, cx)
	local y, z = 14.95, -8.1
	ddPart(folder, "DD_TrayBase", Vector3.new(IL, 0.08, 1.5), Vector3.new(cx, y, z), HULL.tray, Enum.Material.Metal)
	for _, s in ipairs({ -1, 1 }) do
		ddPart(folder, "DD_TrayRail", Vector3.new(IL, 0.32, 0.07), Vector3.new(cx, y + 0.13, z + s * 0.72), HULL.tray, Enum.Material.Metal)
	end
	for k, off in ipairs({ -0.42, -0.1, 0.24, 0.5 }) do
		ddCyl(folder, "DD_Loom", IL, 0.13 + (k % 2) * 0.05, Vector3.new(cx, y + 0.13, z + off), "X", HULL.cable, Enum.Material.Rubber)
	end
	-- sagging loops
	local anchor = ddPart(folder, "DD_CableAnchor", Vector3.new(0.2, 0.2, 0.2), Vector3.new(cx, y, z + 0.8), HULL.cable, Enum.Material.Rubber)
	anchor.Transparency = 1
	local loops = { { -19, -13, 1.4 }, { -7, -1, 2.2 }, { 5, 9, 1.2 }, { 11, 19, 2.8 } }
	for idx, l in ipairs(loops) do
		if (idx + i) % 4 ~= 0 then -- each room drops a different subset
			local a0 = Instance.new("Attachment") ; a0.Name = "DD_CableA" ; a0.Parent = anchor ; a0.WorldPosition = Vector3.new(cx + l[1], y, z + 0.8)
			local a1 = Instance.new("Attachment") ; a1.Name = "DD_CableB" ; a1.Parent = anchor ; a1.WorldPosition = Vector3.new(cx + l[2], y, z + 0.8)
			local beam = Instance.new("Beam")
			beam.Name = "DD_CableSag" ; beam.Attachment0 = a0 ; beam.Attachment1 = a1
			beam.Color = ColorSequence.new(HULL.cable) ; beam.Width0 = 0.11 ; beam.Width1 = 0.11
			beam.FaceCamera = true ; beam.Segments = 12 ; beam.LightInfluence = 1 ; beam.Transparency = NumberSequence.new(0)
			-- a beam's curve leaves along each attachment's Axis: point both down so it sags
			a0.Axis = Vector3.new(0, -1, 0) ; a0.SecondaryAxis = Vector3.new(1, 0, 0)
			a1.Axis = Vector3.new(0, -1, 0) ; a1.SecondaryAxis = Vector3.new(1, 0, 0)
			beam.CurveSize0 = l[3] * 0.9 ; beam.CurveSize1 = -l[3] * 0.9
			beam.Parent = anchor
		end
	end
end

-- generic industrial dressing for a normal (non-tower) hull section
local function dressIndustrial(folder, cx, i)
	dressArch(folder, cx, "MG-Rust 24")
	dressFrames(folder, cx)
	dressPipes(folder, i, cx)
	dressCableTray(folder, i, cx)
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
	-- the sonar/radio partition is riveted rust plate (a CorrodedMetal variant)
	local function plate(p: BasePart) p.MaterialVariant = "deepdescent_hull_rust" ; p.Color = Color3.fromRGB(100, 96, 92) end
	plate(ddPart(folder, "DD_PartZneg", Vector3.new(0.6, IH - 0.5, sideW), Vector3.new(cx, (IH - 0.5) / 2, -(DW / 2) - sideW / 2), DD.dark, Enum.Material.CorrodedMetal))
	plate(ddPart(folder, "DD_PartZpos", Vector3.new(0.6, IH - 0.5, sideW), Vector3.new(cx, (IH - 0.5) / 2, (DW / 2) + sideW / 2), DD.dark, Enum.Material.CorrodedMetal))
	plate(ddPart(folder, "DD_PartTop", Vector3.new(0.6, IH - DH, DW), Vector3.new(cx, DH + (IH - DH) / 2, 0), DD.dark, Enum.Material.CorrodedMetal))
	local fix = ddPart(folder, "DD_RadioFixture", Vector3.new(2, 0.5, 2), Vector3.new(cx + 12, IH - 0.6, 0), Color3.fromRGB(120, 20, 20), Enum.Material.Neon)
	-- radio half: a dimmer, shadowless lamp (the sonar half's hero lantern casts the room's shadows)
	local pl = Instance.new("PointLight") ; pl.Color = Color3.fromRGB(255, 45, 28) ; pl.Brightness = 0.9 ; pl.Range = 20 ; pl:SetAttribute("BaseBrightness", 0.9) ; pl.Shadows = false ; pl.Parent = fix
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
	-- cold teal glow from the open sea: the stern half's light (and a shadow caster) against
	-- the bow half's red lantern
	-- (raised above the start waterline -- under the water volume it lit almost nothing)
	local la = ddPart(folder, "DD_BreachLightAnchor", Vector3.new(0.5, 0.5, 0.5), b + Vector3.new(-4, 5, 0), Color3.fromRGB(40, 110, 130), Enum.Material.Neon)
	local pl = Instance.new("PointLight") ; pl.Color = Color3.fromRGB(60, 150, 170) ; pl.Brightness = 2.2 ; pl.Range = 26 ; pl.Shadows = true ; pl.Parent = la
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
	wall.CFrame = CFrame.new(-23.8, 10.9, 0) * CFrame.Angles(0, math.rad(-90), 0)   -- bow wall opposite the aft door (interior face x=-24), centered z=0 clear above the tube lids and their lamps (y 6.9); Front face -> +X into the room
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

-- ============================================================================
-- Hull surfaces (visual batch 2a)
-- Every room had the same blue-flecked MG-Rust 30 on its walls, and the floors put
-- the DiamondPlate-based "deepdescent_floor_grate" variant on CorrodedMetal parts,
-- so it never rendered (a MaterialVariant only applies on its own base material).
-- Each room now gets its own wall finish from the MG-Rust pack, riveted bulkheads,
-- dark steel ceilings and real tread-plate floors; the connectors match.
-- ============================================================================
local WALL_FINISH = {
	[1] = "MG-Rust 24", -- dark steel, rust streaks
	[2] = "MG-Rust 32", -- navy paint over rust (crew quarters)
	[3] = "MG-Rust 15", -- cream galley paint, peeling
	[4] = "MG-Rust 18", -- cream officers' paint, peeling
	[5] = "MG-Rust 28", -- blue-grey control-room paint
	[6] = "MG-Rust 29", -- slate
	[7] = "MG-Rust 24",
	[8] = "MG-Rust 14", -- rust running down the walls
	[9] = "MG-Rust 05", -- dark rust with teal growth (the flooded stern)
}
local SURF = {
	wall = Color3.fromRGB(72, 72, 74),
	wallPainted = Color3.fromRGB(64, 62, 60),  -- the cream rooms read too bright otherwise
	bulkhead = Color3.fromRGB(110, 104, 100),
	ceiling = Color3.fromRGB(44, 46, 50),
	floor = Color3.fromRGB(58, 60, 62),
}

local function finish(p: BasePart, mat: Enum.Material, variant: string, color: Color3)
	p.Material = mat ; p.MaterialVariant = variant ; p.Color = color
end

local function dressSurfaces(model: Instance, i: number)
	local wallCol = (i == 3 or i == 4) and SURF.wallPainted or SURF.wall
	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") then
			local n = p.Name
			if n == "WallZpos" or n == "WallZneg" or n:match("^TowerWall") or n:match("^CaptainWall") then
				finish(p, Enum.Material.Metal, WALL_FINISH[i], wallCol)
			elseif n:match("^EndWall") or n:match("^SternCap") then
				finish(p, Enum.Material.CorrodedMetal, "deepdescent_hull_rust1", SURF.bulkhead)
			elseif n == "Ceiling" or n == "TowerCeil" then
				finish(p, Enum.Material.Metal, "MG-Rust 24", SURF.ceiling)
			elseif n == "Floor" or n == "TowerFloor" then
				finish(p, Enum.Material.DiamondPlate, "deepdescent_floor_grate", SURF.floor)
			end
		end
	end
end

local function dressConnectorSurfaces()
	for _, c in ipairs(root:GetChildren()) do
		if c.Name:match("^Connector_") then
			for _, p in ipairs(c:GetChildren()) do
				if p:IsA("BasePart") then
					if p.Name:match("^CorrWall") then
						finish(p, Enum.Material.CorrodedMetal, "deepdescent_hull_rust1", SURF.bulkhead)
					elseif p.Name == "CorrCeil" then
						finish(p, Enum.Material.Metal, "MG-Rust 24", SURF.ceiling)
					elseif p.Name == "CorrFloor" then
						finish(p, Enum.Material.DiamondPlate, "deepdescent_floor_grate", SURF.floor)
					end
				end
			end
		end
	end
end

-- ============================================================================
-- Emergency lighting design (visual batch 1b)
-- Each room gets ONE off-centre "hero" battle lantern on a side wall -- the room's
-- only shadow-casting light -- plus a dim bounce fill and a few small shadowless
-- practicals in that room's own colour, so rooms read as pools of light and
-- silhouettes instead of one flat red wash. The baked EmergencyFixture is MOVED onto
-- the wall and becomes the lantern's lens: it stays the tagged part, so PowerManager's
-- flicker / MainGlow and PolishManager's sparks keep working. Positions derive from
-- the section centre (absolute), so re-running Dress never drifts.
-- ============================================================================
local LENS_ON = Color3.fromRGB(255, 52, 30)
local DOOR_LAMP = Color3.fromRGB(170, 30, 18)
-- x = offset from the section centre, side = wall (+1 = +Z, -1 = -Z),
-- calm = flicker-interval multiplier (>1 steadier, <1 twitchier)
local HERO_LAMP = {
	[1] = { x = -13, side = 1, calm = 1.6 },  -- over the escape pod + torpedo tubes
	[2] = { x = 4, side = -1, calm = 1.0 },   -- across the bunks
	[3] = { x = -14, side = 1, calm = 0.6 },  -- over the mess tables; a sick, twitchy lamp
	[4] = { x = -4, side = 1, calm = 1.2 },   -- facing the captain's door
	[5] = { x = 14, side = -1, calm = 1.4 },  -- pools on the ballast panel + valve plate
	[6] = { x = -4, side = -1, calm = 1.0 },  -- grazes the sonar/radio partition (radio half keeps its own dim lamp)
	[8] = { x = 4, side = -1, calm = 0.5 },   -- over the walkway; the engine room's lamp is dying
	[9] = { x = 6, side = 1, calm = 1.0 },    -- across the water onto the torpedoes; the stern glows cold from the breach
}

-- Re-dress a tagged emergency fixture as a caged wall lantern. wallPos is a point on
-- the wall face, inward the unit normal into the room. bounce > 0 adds a dim
-- shadowless fill out in the room (fake bounce off the lit floor); PowerManager
-- flickers the lens, the light cone and the bounce together with the bulb.
local function dressLantern(folder: Instance, fixture: BasePart, wallPos: Vector3, inward: Vector3, bounce: number)
	local light = fixture:FindFirstChildOfClass("PointLight")
	local up = Vector3.new(0, 1, 0)
	local c = wallPos + inward * 1.05
	local f = fixture :: Part
	f.Shape = Enum.PartType.Cylinder
	f.Size = Vector3.new(1.1, 0.85, 0.85)
	f.CFrame = CFrame.new(c) * CFrame.Angles(0, 0, math.rad(90))
	f.Material = Enum.Material.Neon
	f.Color = LENS_ON
	f.CastShadow = false
	f:SetAttribute("LensColor", LENS_ON)
	-- cap, base, four cage bars, wall plate + arm
	ddCyl(folder, "DD_LanternCap", 0.35, 1.25, c + up * 0.72, "Y", DD.dark)
	ddCyl(folder, "DD_LanternBase", 0.3, 1.1, c - up * 0.7, "Y", DD.dark)
	local tangent = inward:Cross(up)
	for k = 0, 3 do
		local a = math.rad(45 + k * 90)
		ddPart(folder, "DD_LanternBar", Vector3.new(0.09, 1.3, 0.09), c + (inward * math.cos(a) + tangent * math.sin(a)) * 0.55, DD.dark)
	end
	local plate = ddPart(folder, "DD_LanternPlate", Vector3.new(1, 1.9, 0.14), wallPos, DD.dark)
	plate.CFrame = CFrame.lookAt(wallPos + inward * 0.07, wallPos + inward * 2)
	local armPos = wallPos + inward * 0.55 + up * 0.72
	local arm = ddPart(folder, "DD_LanternArm", Vector3.new(0.28, 0.28, 1.1), armPos, DD.dark)
	arm.CFrame = CFrame.lookAt(armPos, armPos + inward)
	-- faint camera-facing light cone falling from the lens onto the floor
	local a0 = Instance.new("Attachment") ; a0.Name = "DD_ConeA0" ; a0.Parent = f ; a0.WorldPosition = c - up * 0.45
	local a1 = Instance.new("Attachment") ; a1.Name = "DD_ConeA1" ; a1.Parent = f ; a1.WorldPosition = Vector3.new(c.X, 0.8, c.Z) + inward * 4.5
	local beam = Instance.new("Beam")
	beam.Name = "DD_LightCone" ; beam.Attachment0 = a0 ; beam.Attachment1 = a1
	beam.Color = ColorSequence.new(light and light.Color or LENS_ON)
	beam.LightEmission = 1 ; beam.LightInfluence = 0 ; beam.FaceCamera = true ; beam.Segments = 1
	beam.Width0 = 0.9 ; beam.Width1 = 10
	beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.82), NumberSequenceKeypoint.new(0.45, 0.94), NumberSequenceKeypoint.new(1, 1) })
	beam.Parent = f
	if bounce > 0 then
		local att = Instance.new("Attachment") ; att.Name = "DD_BounceAtt" ; att.Parent = f
		att.WorldPosition = Vector3.new(c.X, 2.5, c.Z) + inward * 7
		local bl = Instance.new("PointLight")
		bl.Name = "DD_Bounce" ; bl.Color = Color3.fromRGB(190, 38, 24) ; bl.Brightness = bounce ; bl.Range = 30 ; bl.Shadows = false
		bl:SetAttribute("BaseBrightness", bounce)
		bl.Parent = att
	end
end

-- small shadowless practical: a neon lens with its own short-range light
local function practical(folder: Instance, name: string, pos: Vector3, color: Color3, brightness: number, range: number, size: Vector3, shape: Enum.PartType?)
	local lens = ddNeon(folder, name, pos, color, size)
	if shape then lens.Shape = shape end
	local pl = Instance.new("PointLight") ; pl.Color = color ; pl.Brightness = brightness ; pl.Range = range ; pl.Shadows = false ; pl.Parent = lens
	return lens
end

-- light an existing part (a console screen, the generator panel) as a glowing practical
local function glowFrom(part: Instance?, color: Color3, brightness: number, range: number)
	if not (part and part:IsA("BasePart")) then return end
	local pl = Instance.new("PointLight") ; pl.Color = color ; pl.Brightness = brightness ; pl.Range = range ; pl.Shadows = false ; pl.Parent = part
end

local function dressEmergencyLighting(folder: Instance, model: Instance, i: number, cx: number)
	local fixture = model:FindFirstChild("EmergencyFixture")
	if not (fixture and fixture:IsA("BasePart")) then return end
	local light = fixture:FindFirstChildOfClass("PointLight")
	if not light then return end
	if i == 7 then
		-- the tower's lamp sat at §5's ceiling (lighting §5 twice, leaving the tower black):
		-- hang it inside the tower instead, small and shadowless
		light.Brightness = 1.4 ; light.Range = 16 ; light.Shadows = false ; light:SetAttribute("BaseBrightness", 1.4)
		dressLantern(folder, fixture, Vector3.new(cx + 4, 29, -1.5), Vector3.new(-1, 0, 0), 0)
		fixture:SetAttribute("FlickerCalm", 1.5)
		return
	end
	local h = HERO_LAMP[i]
	if not h then return end
	light.Brightness = 3 ; light.Range = 38 ; light.Shadows = true ; light:SetAttribute("BaseBrightness", 3)
	dressLantern(folder, fixture, Vector3.new(cx + h.x, 11.5, h.side * IW / 2), Vector3.new(0, 0, -h.side), 1.0)
	fixture:SetAttribute("FlickerCalm", h.calm)
	-- dim red lamp strip over each doorway (reads even at the lowest graphics quality)
	local slot = hullSlot[i]
	for _, dir in ipairs({ -1, 1 }) do
		if (dir == -1 and slot > 0) or (dir == 1 and slot < LAST_SLOT) then
			ddNeon(folder, "DD_DoorLamp", Vector3.new(cx + dir * (IL / 2 - 0.12), DH + 1.5, 0), DOOR_LAMP, Vector3.new(0.2, 0.3, 3.4))
		end
	end
	-- room practicals
	if i == 1 then
		practical(folder, "DD_PodLamp", Vector3.new(cx - 19, 7.3, 8), Color3.fromRGB(255, 140, 50), 1.4, 9, Vector3.new(0.6, 0.6, 0.6), Enum.PartType.Ball)
		for t = 0, 3 do  -- tube status lamps on the bow wall; tube 3 reads "ready"
			ddNeon(folder, "DD_TubeLamp", Vector3.new(cx - IL / 2 + 0.12, 5.2, -9 + t * 6), (t == 2) and Color3.fromRGB(255, 150, 40) or Color3.fromRGB(150, 24, 16), Vector3.new(0.2, 0.35, 0.8))
		end
	elseif i == 2 then
		practical(folder, "DD_BunkLamp", Vector3.new(cx - 14, 4.3, IW / 2 - 0.5), Color3.fromRGB(255, 170, 90), 0.9, 7, Vector3.new(0.4, 0.4, 0.4), Enum.PartType.Ball)
	elseif i == 3 then
		-- the stove's pilot light still burns under the pot
		local ring = ddCyl(folder, "DD_StoveRing", 0.08, 1.5, Vector3.new(cx, 3.3, -IW / 2 + 3), "Y", Color3.fromRGB(255, 110, 30), Enum.Material.Neon)
		glowFrom(ring, Color3.fromRGB(255, 120, 40), 1.2, 8)
	elseif i == 4 then
		local cap = model:FindFirstChild("CaptainLight")
		local cl = cap and cap:FindFirstChildOfClass("PointLight")
		if cl then cl.Shadows = false end
	elseif i == 5 then
		local nav = folder:FindFirstChild("DD_Screen_NavConsole")
		if nav and nav:IsA("BasePart") then nav.Material = Enum.Material.Neon ; nav.Color = Color3.fromRGB(16, 60, 38) end
		glowFrom(nav, Color3.fromRGB(70, 210, 120), 0.8, 8)
		local helm = folder:FindFirstChild("DD_Screen_Helm")
		if helm and helm:IsA("BasePart") then helm.Material = Enum.Material.Neon ; helm.Color = Color3.fromRGB(14, 46, 34) end
		practical(folder, "DD_BallastLamp", Vector3.new(cx + 12, 4.75, -IW / 2 + 2.45), Color3.fromRGB(255, 150, 60), 0.7, 6, Vector3.new(0.3, 0.3, 0.2))
	elseif i == 6 then
		-- the sonar still runs on emergency power: its screen glows green
		local sonar = folder:FindFirstChild("DD_Screen_SonarConsole")
		if sonar and sonar:IsA("BasePart") then sonar.Material = Enum.Material.Neon ; sonar.Color = Color3.fromRGB(20, 80, 44) end
		glowFrom(sonar, Color3.fromRGB(60, 220, 120), 1.1, 10)
	elseif i == 8 then
		glowFrom(folder:FindFirstChild("DD_GPanel"), Color3.fromRGB(255, 150, 60), 1.0, 9)
	end
end

-- ============================================================================
-- Main-power work lamps (visual batch 1c)
-- Each tagged MainFixture becomes a caged tungsten pendant: a stem from the ceiling,
-- a dark housing (the tagged part, still holding its downward SpotLight) and a
-- DD_Bulb that PowerManager lights. The +Z lamp of each room casts the shadows while
-- the generator runs (MainShadows attr) and carries a warm ceiling-bounce fill
-- (DD_MainFillAtt). §6's lamps step off the sonar/radio partition line.
-- ============================================================================
local function dressMainLamps(folder: Instance, model: Instance, i: number, cx: number)
	for _, fixture in ipairs(model:GetChildren()) do
		if fixture.Name == "MainFixture" and fixture:IsA("BasePart") and CollectionService:HasTag(fixture, "MainLight") then
			local zSide = (fixture.Position.Z >= 0) and 1 or -1
			local x = (i == 6) and (cx - zSide * 7) or cx   -- §6: sonar half (+Z) / radio half (-Z)
			local z = zSide * IW / 4
			local housingY = IH - 1.9
			local f = fixture :: Part
			f.Size = Vector3.new(1.5, 0.5, 1.5)
			f.CFrame = CFrame.new(x, housingY, z)
			f.Color = DD.dark
			f.Material = Enum.Material.Metal
			f.CastShadow = false
			f.CanCollide = false
			local light = f:FindFirstChildOfClass("SpotLight")
			if light then
				light.Face = Enum.NormalId.Bottom ; light.Angle = 105 ; light.Range = 30
				light.Shadows = false ; light.Enabled = false ; light.Brightness = 0
			end
			ddCyl(folder, "DD_LampStem", IH - housingY - 0.25, 0.14, Vector3.new(x, (IH + housingY + 0.25) / 2, z), "Y", DD.dark)
			-- the bulb hangs under the housing inside a four-bar cage; parented to the fixture
			-- so PowerManager finds it (dark glass until the generator runs)
			ddPart(f, "DD_Bulb", Vector3.new(0.6, 0.6, 0.6), Vector3.new(x, housingY - 0.55, z), Color3.fromRGB(58, 50, 42), Enum.Material.Glass, Enum.PartType.Ball)
			for k = 0, 3 do
				local a = math.rad(45 + k * 90)
				ddPart(folder, "DD_LampCage", Vector3.new(0.07, 0.75, 0.07), Vector3.new(x + math.cos(a) * 0.42, housingY - 0.6, z + math.sin(a) * 0.42), DD.dark)
			end
			if zSide > 0 then
				f:SetAttribute("MainShadows", true)
				local att = Instance.new("Attachment") ; att.Name = "DD_MainFillAtt" ; att.Parent = f
				att.WorldPosition = Vector3.new(x, IH - 3, 0)
				local fill = Instance.new("PointLight")
				fill.Name = "MainFill" ; fill.Range = 34 ; fill.Shadows = false ; fill.Enabled = false ; fill.Brightness = 0
				fill.Parent = att
			end
		end
	end
end

-- ============================================================================
-- Bulkhead doors + door frames (visual batch 3c)
-- The tagged BulkheadDoor stays as the invisible logic part (collision + prompts).
-- What you see is DD_DoorLeaf, a steel leaf welded to its stiffeners, dogs and hatch
-- wheel; WaterRenderer (client) slides it into the corridor wall on the Open attr.
-- ============================================================================
local DOOR = {
	leaf = Color3.fromRGB(112, 114, 104),
	leafSealed = Color3.fromRGB(96, 50, 40),
	bar = Color3.fromRGB(58, 60, 60),
	frame = Color3.fromRGB(150, 138, 110),
	seal = Color3.fromRGB(150, 36, 26),
}

local function leafPart(leaf: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?)
	local cf = leaf.CFrame * offset
	local p = ddPart(leaf, name, size, cf.Position, color, material, shape)
	p.CFrame = cf
	p.Anchored = false
	local w = Instance.new("WeldConstraint")
	w.Part0 = leaf ; w.Part1 = p ; w.Parent = p
	return p
end

local function dressDoorFace(leaf: BasePart, fx: number)
	local t = leaf.Size.X / 2
	local h, w = leaf.Size.Y / 2, leaf.Size.Z / 2
	local f = t + 0.05
	-- gasket round the edge
	leafPart(leaf, "DD_DrGasket", Vector3.new(0.1, 0.26, w * 2), CFrame.new(fx * f, h - 0.13, 0), DOOR.bar)
	leafPart(leaf, "DD_DrGasket", Vector3.new(0.1, 0.26, w * 2), CFrame.new(fx * f, -h + 0.13, 0), DOOR.bar)
	leafPart(leaf, "DD_DrGasket", Vector3.new(0.1, h * 2, 0.26), CFrame.new(fx * f, 0, w - 0.13), DOOR.bar)
	leafPart(leaf, "DD_DrGasket", Vector3.new(0.1, h * 2, 0.26), CFrame.new(fx * f, 0, -w + 0.13), DOOR.bar)
	-- stiffeners + dogs
	for _, y in ipairs({ -3.1, 3.1 }) do
		leafPart(leaf, "DD_DrBar", Vector3.new(0.14, 0.55, w * 2 - 1), CFrame.new(fx * (t + 0.07), y, 0), DOOR.bar).MaterialVariant = "MG-Rust 24"
		for _, s in ipairs({ -1, 1 }) do
			leafPart(leaf, "DD_DrDog", Vector3.new(0.26, 0.72, 0.34), CFrame.new(fx * (t + 0.13), y, s * (w - 0.3)), HULL.pipeSteel)
		end
	end
	-- hatch wheel
	local R, wx = 1.32, fx * (t + 0.44)
	leafPart(leaf, "DD_DrStem", Vector3.new(0.46, 0.34, 0.34), CFrame.new(fx * (t + 0.23), 0.2, 0), DOOR.bar, Enum.Material.Metal, Enum.PartType.Cylinder)
	leafPart(leaf, "DD_DrHub", Vector3.new(0.16, 0.6, 0.6), CFrame.new(wx, 0.2, 0), HULL.bandRed, Enum.Material.Metal, Enum.PartType.Cylinder)
	for k = 0, 7 do
		local a = math.rad(k * 45)
		leafPart(leaf, "DD_DrRim", Vector3.new(0.15, 0.17, 1.12), CFrame.new(wx, 0.2 + math.cos(a) * R, math.sin(a) * R) * CFrame.Angles(a, 0, 0), HULL.bandRed)
	end
	for _, deg in ipairs({ 45, 135 }) do
		leafPart(leaf, "DD_DrSpoke", Vector3.new(0.1, 0.13, R * 2), CFrame.new(wx, 0.2, 0) * CFrame.Angles(math.rad(deg), 0, 0), HULL.bandRed)
	end
	-- welded-shut bars, shown only once the door is sealed
	for _, deg in ipairs({ 40, -40 }) do
		local bar = leafPart(leaf, "DD_SealBar", Vector3.new(0.16, 0.5, w * 2.3), CFrame.new(fx * (t + 0.72), 0, 0) * CFrame.Angles(math.rad(deg), 0, 0), DOOR.seal)
		bar.Transparency = 1
	end
end

local function dressBulkheadDoors()
	for _, door in ipairs(CollectionService:GetTagged("BulkheadDoor")) do
		if door:IsA("BasePart") and door:IsDescendantOf(root) then
			door.Transparency = 1
			local leaf = ddPart(door, "DD_DoorLeaf", Vector3.new(0.7, DH - 0.06, DW - 0.04), door.Position, DOOR.leaf, Enum.Material.Metal)
			leaf.MaterialVariant = "MG-Rust 06"
			dressDoorFace(leaf, -1)
			dressDoorFace(leaf, 1)
			local num = 0
			for k, sec in ipairs(SectionData.HullOrder) do
				if sec == door:GetAttribute("SectionA") then num = k end
			end
			for _, face in ipairs({ Enum.NormalId.Left, Enum.NormalId.Right }) do
				local sg = Instance.new("SurfaceGui")
				sg.Name = "DD_DoorStencil" ; sg.Face = face
				sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud ; sg.PixelsPerStud = 20
				sg.LightInfluence = 1 ; sg.Parent = leaf
				local tl = Instance.new("TextLabel")
				tl.BackgroundTransparency = 1 ; tl.AnchorPoint = Vector2.new(0.5, 0)
				tl.Position = UDim2.fromScale(0.5, 0.08) ; tl.Size = UDim2.fromScale(0.5, 0.11)
				tl.Font = Enum.Font.Oswald ; tl.TextScaled = true ; tl.Text = ("WTD %d"):format(num)
				tl.TextColor3 = Color3.fromRGB(196, 190, 170) ; tl.TextTransparency = 0.3 ; tl.Parent = sg
			end
			local function syncSeal()
				local sealed = door:GetAttribute("Sealed") == true
				leaf.Color = sealed and DOOR.leafSealed or DOOR.leaf
				for _, c in ipairs(leaf:GetChildren()) do
					if c.Name == "DD_SealBar" and c:IsA("BasePart") then c.Transparency = sealed and 0 or 1 end
				end
			end
			door:GetAttributeChangedSignal("Sealed"):Connect(syncSeal)
			syncSeal()
		end
	end
	-- corridor: the tracks the leaf runs in + a dim red lens either side
	for _, c in ipairs(root:GetChildren()) do
		local door = c.Name:match("^Connector_") and c:FindFirstChild("BulkheadDoor")
		if door and door:IsA("BasePart") then
			local f = door:FindFirstChild("DD_DoorLeaf")
			local x = door.Position.X
			for _, sx in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					ddPart(f, "DD_DoorRail", Vector3.new(0.22, DH, 0.5), Vector3.new(x + sx * 0.5, DH / 2, sz * (DW / 2 - 0.2)), DOOR.bar).Anchored = true
				end
				ddPart(f, "DD_DoorTrack", Vector3.new(0.22, 0.45, DW), Vector3.new(x + sx * 0.5, DH - 0.22, 0), DOOR.bar)
				ddNeon(f, "DD_CorrLens", Vector3.new(x + sx * 2.3, DH - 0.08, 0), DOOR_LAMP, Vector3.new(1.3, 0.12, 0.5))
			end
		end
	end
end

-- diagonal black/yellow bands: one Frame + a UIGradient with hard colour steps
local function hazardFace(part: BasePart, face: Enum.NormalId)
	local sg = Instance.new("SurfaceGui")
	sg.Name = "DD_Hazard" ; sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud ; sg.PixelsPerStud = 24
	sg.LightInfluence = 1 ; sg.Parent = part
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1) ; f.BackgroundColor3 = Color3.new(1, 1, 1) ; f.BorderSizePixel = 0 ; f.BackgroundTransparency = 0.18 ; f.Parent = sg
	local keys, n = {}, 9
	local yellow, black = Color3.fromRGB(176, 142, 44), Color3.fromRGB(18, 18, 16)
	for k = 0, n - 1 do
		local c = (k % 2 == 0) and yellow or black
		keys[#keys + 1] = ColorSequenceKeypoint.new(k / n, c)
		keys[#keys + 1] = ColorSequenceKeypoint.new(math.min((k + 1) / n - 0.0005, 1), c)
	end
	keys[#keys] = ColorSequenceKeypoint.new(1, keys[#keys].Value)
	local g = Instance.new("UIGradient") ; g.Color = ColorSequence.new(keys) ; g.Rotation = 8 ; g.Parent = f
end

-- painted text on the hull: a sliver of invisible part so it can sit on anything
local function stencil(folder: Instance, pos: Vector3, inward: Vector3, w: number, h: number, text: string, color: Color3?, font: Enum.Font?, transparency: number?, tilt: number?)
	local p = ddPart(folder, "DD_Stencil", Vector3.new(w, h, 0.05), pos, HULL.cable, Enum.Material.SmoothPlastic)
	p.Transparency = 1
	p.CFrame = CFrame.lookAt(pos, pos + inward)
	local sg = Instance.new("SurfaceGui")
	sg.Name = "DD_StencilGui" ; sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud ; sg.PixelsPerStud = 36
	sg.LightInfluence = 1 ; sg.Parent = p
	local tl = Instance.new("TextLabel")
	tl.BackgroundTransparency = 1 ; tl.Size = UDim2.fromScale(1, 1)
	tl.Font = font or Enum.Font.Oswald ; tl.TextScaled = true ; tl.Text = text
	tl.TextColor3 = color or Color3.fromRGB(196, 190, 170) ; tl.TextTransparency = transparency or 0.22
	tl.Rotation = tilt or 0 ; tl.Parent = sg
	return p
end

local function dressDoorFrames(folder: Instance, i: number, cx: number)
	local slot = hullSlot[i]
	if slot == nil then return end
	for _, dir in ipairs({ -1, 1 }) do
		if (dir == -1 and slot > 0) or (dir == 1 and slot < LAST_SLOT) then
			local x = cx + dir * (IL / 2 - 0.25)
			local function fp(name, size, pos)
				local p = ddPart(folder, name, size, pos, DOOR.frame, Enum.Material.Metal)
				p.MaterialVariant = "MG-Rust 12"
				p.CastShadow = true
				return p
			end
			for _, s in ipairs({ -1, 1 }) do
				fp("DD_DoorJamb", Vector3.new(0.55, DH + 1.1, 1.1), Vector3.new(x, (DH + 1.1) / 2, s * (DW / 2 + 0.55)))
				local gusset = fp("DD_DoorGusset", Vector3.new(0.5, 0.26, 1.7), Vector3.new(x, DH - 0.5, s * (DW / 2 - 0.5)))
				gusset.Orientation = Vector3.new(s * 45, 0, 0)
			end
			local header = fp("DD_DoorHeader", Vector3.new(0.55, 1.1, DW + 2.2), Vector3.new(x, DH + 0.55, 0))
			hazardFace(header, (dir > 0) and Enum.NormalId.Left or Enum.NormalId.Right)
			fp("DD_DoorSill", Vector3.new(1.2, 0.22, DW), Vector3.new(cx + dir * (IL / 2 - 0.1), 0.11, 0))
		end
	end
end

-- ============================================================================
-- Machinery + instruments (visual batch 3d)
-- Instrument faces and screens are SurfaceGuis (dozens of dials and LEDs for one
-- part). LEDs tagged DD_Blink and sonar sweeps are animated by WaterRenderer.
-- ============================================================================
local function roundFrame(parent: Instance, size: UDim2, pos: UDim2, color: Color3)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5) ; f.Size = size ; f.Position = pos
	f.BackgroundColor3 = color ; f.BorderSizePixel = 0
	local uc = Instance.new("UICorner") ; uc.CornerRadius = UDim.new(1, 0) ; uc.Parent = f
	local ar = Instance.new("UIAspectRatioConstraint") ; ar.Parent = f
	f.Parent = parent
	return f
end

local function guiLabel(parent: Instance, text: string, x: number, y: number, w: number, h: number, color: Color3, font: Enum.Font?)
	local tl = Instance.new("TextLabel")
	tl.BackgroundTransparency = 1 ; tl.Position = UDim2.fromScale(x, y) ; tl.Size = UDim2.fromScale(w, h)
	tl.Font = font or Enum.Font.Code ; tl.Text = text ; tl.TextColor3 = color ; tl.TextScaled = true
	tl.TextXAlignment = Enum.TextXAlignment.Left
	tl.Parent = parent
	return tl
end

local function panelFace(part: BasePart, face: Enum.NormalId, cols: number, rows: number, seed: number, title: string?)
	local rng = Random.new(seed)
	local sg = Instance.new("SurfaceGui")
	sg.Name = "DD_PanelFace" ; sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud ; sg.PixelsPerStud = 44
	sg.LightInfluence = 0.8 ; sg.Brightness = 1 ; sg.Parent = part -- dials need room light; only the LEDs read in the dark
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1) ; bg.BackgroundColor3 = Color3.fromRGB(20, 24, 24) ; bg.BorderSizePixel = 0 ; bg.Parent = sg
	local top = title and 0.16 or 0.04
	if title then guiLabel(bg, title, 0.04, 0.02, 0.92, 0.11, Color3.fromRGB(196, 186, 150)) end
	for r = 1, rows do
		for c = 1, cols do
			local px, py = (c - 0.5) / cols, top + (1 - top) * (r - 0.5) / rows
			local pos = UDim2.fromScale(px, py)
			local kind = rng:NextInteger(1, 10)
			if kind <= 4 then
				local dial = roundFrame(bg, UDim2.fromScale(0.82 / cols, 0.82 * (1 - top) / rows), pos, Color3.fromRGB(116, 112, 98))
				local st = Instance.new("UIStroke") ; st.Color = Color3.fromRGB(60, 62, 60) ; st.Thickness = 2 ; st.Parent = dial
				local n = Instance.new("Frame")
				n.AnchorPoint = Vector2.new(0.5, 1) ; n.Position = UDim2.fromScale(0.5, 0.5) ; n.Size = UDim2.fromScale(0.07, 0.42)
				n.BackgroundColor3 = Color3.fromRGB(170, 40, 30) ; n.BorderSizePixel = 0 ; n.Rotation = rng:NextInteger(-115, 115) ; n.Parent = dial
			elseif kind <= 8 then
				local cols3 = { Color3.fromRGB(60, 225, 110), Color3.fromRGB(255, 176, 52), Color3.fromRGB(230, 56, 44) }
				local led = roundFrame(bg, UDim2.fromScale(0.3 / cols, 0.3 * (1 - top) / rows), pos, cols3[rng:NextInteger(1, 3)])
				if rng:NextNumber() < 0.45 then CollectionService:AddTag(led, "DD_Blink") end
			else
				local sw = Instance.new("Frame")
				sw.AnchorPoint = Vector2.new(0.5, 0.5) ; sw.Position = pos ; sw.Size = UDim2.fromScale(0.34 / cols, 0.62 * (1 - top) / rows)
				sw.BackgroundColor3 = Color3.fromRGB(70, 74, 76) ; sw.BorderSizePixel = 0 ; sw.Parent = bg
			end
		end
	end
	return sg
end

-- a wall cabinet with an instrument face looking into the room
local function wallPanel(folder: Instance, x: number, y: number, side: number, w: number, h: number, seed: number, title: string?)
	local pos = Vector3.new(x, y, side * (IW / 2 - 0.45))
	local cab = ddPart(folder, "DD_WallPanel", Vector3.new(w, h, 0.5), pos, HULL.tray, Enum.Material.Metal)
	cab.CFrame = CFrame.lookAt(pos, pos + Vector3.new(0, 0, -side))
	panelFace(cab, Enum.NormalId.Front, math.floor(w / 0.8), math.floor(h / 0.8), seed, title)
	return cab
end

local SCREEN_INK = Color3.fromRGB(96, 240, 150)
local function screenGui(part: BasePart, face: Enum.NormalId)
	part.Material = Enum.Material.SmoothPlastic ; part.Color = Color3.fromRGB(6, 12, 10) ; part.Reflectance = 0
	local sg = Instance.new("SurfaceGui")
	sg.Name = "DD_ScreenGui" ; sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud ; sg.PixelsPerStud = 70
	sg.LightInfluence = 0 ; sg.Brightness = 1.5 ; sg.Parent = part
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1) ; bg.BackgroundColor3 = Color3.fromRGB(6, 22, 14) ; bg.BorderSizePixel = 0 ; bg.Parent = sg
	return bg
end

local function sonarScreen(part: BasePart, face: Enum.NormalId)
	local bg = screenGui(part, face)
	local scope = roundFrame(bg, UDim2.fromScale(0.92, 0.92), UDim2.fromScale(0.5, 0.5), Color3.fromRGB(4, 34, 18))
	for _, s in ipairs({ 0.66, 0.33 }) do
		local ring = roundFrame(scope, UDim2.fromScale(s, s), UDim2.fromScale(0.5, 0.5), Color3.new(0, 0, 0))
		ring.BackgroundTransparency = 1
		local st = Instance.new("UIStroke") ; st.Color = SCREEN_INK ; st.Transparency = 0.55 ; st.Thickness = 1 ; st.Parent = ring
	end
	local st = Instance.new("UIStroke") ; st.Color = SCREEN_INK ; st.Transparency = 0.25 ; st.Thickness = 2 ; st.Parent = scope
	local sweep = Instance.new("Frame")
	sweep.Name = "DD_Sweep" ; sweep.BackgroundTransparency = 1 ; sweep.Size = UDim2.fromScale(1, 1) ; sweep.Parent = scope
	for k = 0, 3 do
		local ln = Instance.new("Frame")
		ln.AnchorPoint = Vector2.new(0.5, 1) ; ln.Position = UDim2.fromScale(0.5, 0.5) ; ln.Size = UDim2.new(0, 2, 0.48, 0)
		ln.BackgroundColor3 = SCREEN_INK ; ln.BackgroundTransparency = 0.1 + k * 0.28 ; ln.BorderSizePixel = 0 ; ln.Rotation = -k * 5 ; ln.Parent = sweep
	end
	CollectionService:AddTag(sweep, "DD_SonarSweep")
end

-- text status screen; `lines` is { {text, colorOrNil}, ... }. Returns the labels.
local function textScreen(part: BasePart, face: Enum.NormalId, lines: { any })
	local bg = screenGui(part, face)
	local out = {}
	local h = 0.86 / #lines
	for k, l in ipairs(lines) do
		out[k] = guiLabel(bg, l[1], 0.05, 0.07 + (k - 1) * h, 0.9, h * 0.8, l[2] or SCREEN_INK)
	end
	return out
end

-- dressConsole faces its screen -Z; consoles against the -Z wall need it on +Z
local function consoleScreen(folder: Instance, model: Instance, partName: string)
	local p = model:FindFirstChild(partName)
	local s = folder:FindFirstChild("DD_Screen_" .. partName)
	if not (p and s and p:IsA("BasePart") and s:IsA("BasePart")) then return nil, Enum.NormalId.Front end
	if p.Position.Z < -2 then
		s.Position = p.Position + Vector3.new(0, p.Size.Y * 0.15, p.Size.Z / 2 + 0.08)
		local led = folder:FindFirstChild("DD_ScreenLED_" .. partName)
		if led and led:IsA("BasePart") then
			led.Position = p.Position + Vector3.new(s.Size.X / 2 - 0.3, p.Size.Y * 0.42, p.Size.Z / 2 + 0.12)
		end
		return s, Enum.NormalId.Back
	end
	return s, Enum.NormalId.Front
end

local function shelf(folder: Instance, x: number, y: number, side: number, w: number, seed: number)
	local rng = Random.new(seed)
	local z = side * (IW / 2 - 0.75)
	ddPart(folder, "DD_Shelf", Vector3.new(w, 0.14, 1.1), Vector3.new(x, y, z), HULL.tray, Enum.Material.Metal)
	local px = x - w / 2 + 0.5
	while px < x + w / 2 - 0.4 do
		local tin = { Color3.fromRGB(120, 114, 100), Color3.fromRGB(96, 60, 44), Color3.fromRGB(60, 74, 80), Color3.fromRGB(140, 120, 70) }
		local col = tin[rng:NextInteger(1, 4)]
		if rng:NextNumber() < 0.65 then
			local h = rng:NextNumber(0.5, 0.85)
			ddCyl(folder, "DD_Tin", h, 0.5, Vector3.new(px, y + 0.07 + h / 2, z + rng:NextNumber(-0.2, 0.2)), "Y", col, Enum.Material.Metal)
		else
			local h = rng:NextNumber(0.5, 0.95)
			local b = ddPart(folder, "DD_Crate", Vector3.new(0.75, h, 0.7), Vector3.new(px, y + 0.07 + h / 2, z), col, Enum.Material.Cardboard)
			b.Orientation = Vector3.new(0, rng:NextInteger(-14, 14), 0)
		end
		px += rng:NextNumber(0.75, 1.3)
	end
end

local function dressTorpedoRoom(folder: Instance, model: Instance, cx: number)
	for t = 0, 3 do
		local tube = model:FindFirstChild("TorpedoTube_" .. t)
		if tube and tube:IsA("BasePart") then
			-- the baked tubes stood upright; lay them through the bow wall, mouths to the room
			local z = -9 + t * 6
			local y = (z > 5) and 8.6 or 4.6 -- tube 4 clears the escape pod
			tube.CFrame = CFrame.new(cx - IL / 2 + 2, y, z)
			tube.Material = Enum.Material.Metal ; tube.MaterialVariant = "MG-Rust 24" ; tube.Color = HULL.frame
			local mx = cx - IL / 2 + 4
			ddCyl(folder, "DD_TubeFlange", 0.4, 3.7, Vector3.new(mx, y, z), "X", DD.dark, Enum.Material.Metal)
			local lid = ddCyl(folder, "DD_TubeLid", 0.22, 3.1, Vector3.new(mx + 0.28, y, z), "X", HULL.pipeSteel, Enum.Material.Metal)
			lid.MaterialVariant = "MG-Rust 27"
			ddPart(folder, "DD_TubeLatch", Vector3.new(0.18, 0.34, 2.6), Vector3.new(mx + 0.45, y, z), HULL.bandRed, Enum.Material.Metal)
			ddCyl(folder, "DD_TubeHub", 0.26, 0.7, Vector3.new(mx + 0.5, y, z), "X", DD.dark, Enum.Material.Metal)
		end
	end
	-- the status lamps sit over the tube mouths now
	for _, c in ipairs(folder:GetChildren()) do
		if c.Name == "DD_TubeLamp" and c:IsA("BasePart") then
			local up = (c.Position.Z > 5) and 10.9 or 6.9
			c.Position = Vector3.new(cx - IL / 2 + 4.3, up, c.Position.Z)
			c.Size = Vector3.new(0.14, 0.3, 0.8)
		end
	end
	wallPanel(folder, cx - 12, 6.6, -1, 3.6, 3.2, 11, "TUBE CONTROL")
	shelf(folder, cx + 18, 7.2, 1, 4.6, 12)
	-- the pod's porthole: Glass mirrored the sky pale pink in the dark room
	local podWindow = model:FindFirstChild("PodWindow")
	if podWindow and podWindow:IsA("BasePart") then
		podWindow.Material = Enum.Material.SmoothPlastic
		podWindow.Reflectance = 0.04
		podWindow.Color = Color3.fromRGB(12, 20, 28)
	end
end

local function dressBerthingDetail(folder: Instance, cx: number)
	for _, ox in ipairs({ -12, 0, 12 }) do
		shelf(folder, cx + ox, 7.6, 1, 4.6, 20 + ox)
	end
	-- a bunk-room clothes rail
	ddCyl(folder, "DD_ClothesRail", 8, 0.14, Vector3.new(cx - 6, 8.2, -IW / 2 + 1.6), "X", HULL.pipeSteel, Enum.Material.Metal)
	for k, ox in ipairs({ -9, -7.4, -5.2, -3.4 }) do
		local coat = ddPart(folder, "DD_Coverall", Vector3.new(1.05, 4.2, 0.34), Vector3.new(cx + ox, 6, -IW / 2 + 1.6), (k % 2 == 0) and Color3.fromRGB(70, 74, 62) or Color3.fromRGB(58, 62, 74), Enum.Material.Fabric)
		coat.Orientation = Vector3.new(0, (k * 37) % 28 - 14, (k % 2 == 0) and 2.5 or -2)
	end
end

local function dressGalleyDetail(folder: Instance, model: Instance, cx: number)
	local counter = model:FindFirstChild("Counter")
	if counter and counter:IsA("BasePart") then
		counter.MaterialVariant = "MG-Rust 27" ; counter.Color = Color3.fromRGB(100, 102, 102)
	end
	local z = -IW / 2 + 3
	ddPart(folder, "DD_Worktop", Vector3.new(IL - 11.6, 0.18, 3.3), Vector3.new(cx, 3.08, z), Color3.fromRGB(126, 130, 132), Enum.Material.Metal)
	for k = -4, 4 do
		local front = ddPart(folder, "DD_CabFront", Vector3.new(3.6, 2.3, 0.1), Vector3.new(cx + k * 4, 1.4, z + 1.54), Color3.fromRGB(92, 94, 94), Enum.Material.Metal)
		front.MaterialVariant = "MG-Rust 27"
		ddPart(folder, "DD_CabHandle", Vector3.new(1.6, 0.1, 0.1), Vector3.new(cx + k * 4, 2.3, z + 1.65), HULL.pipeSteel, Enum.Material.Metal)
	end
	-- range + extractor hood + flue
	ddPart(folder, "DD_Range", Vector3.new(3.4, 0.14, 2.6), Vector3.new(cx, 3.2, z), DD.dark, Enum.Material.Metal)
	ddPart(folder, "DD_Hood", Vector3.new(4.4, 0.9, 2.6), Vector3.new(cx, 9.2, -IW / 2 + 1.6), Color3.fromRGB(110, 112, 112), Enum.Material.Metal)
	ddPart(folder, "DD_Flue", Vector3.new(1.4, 5.4, 1.4), Vector3.new(cx, 12.3, -IW / 2 + 1.4), Color3.fromRGB(96, 98, 98), Enum.Material.Metal)
	-- sink + tap
	ddPart(folder, "DD_Sink", Vector3.new(2.6, 0.05, 1.9), Vector3.new(cx - 10, 3.19, z), Color3.fromRGB(44, 46, 48), Enum.Material.Metal)
	ddCyl(folder, "DD_Tap", 1, 0.16, Vector3.new(cx - 10, 3.65, z - 1.1), "Y", HULL.pipeSteel, Enum.Material.Metal)
	shelf(folder, cx - 12, 7, -1, 7, 31)
	shelf(folder, cx + 12, 7, -1, 7, 32)
end

local function dressOfficersDetail(folder: Instance, model: Instance, cx: number)
	local desk = model:FindFirstChild("Desk")
	if desk and desk:IsA("BasePart") then
		desk.Material = Enum.Material.WoodPlanks ; desk.Color = Color3.fromRGB(78, 54, 36)
	end
	-- captain's bookcase (behind the partition)
	local bx = cx + 2
	local back = ddPart(folder, "DD_Bookcase", Vector3.new(6, 8, 1.2), Vector3.new(bx, 4.1, -IW / 2 + 0.8), Color3.fromRGB(62, 42, 28), Enum.Material.WoodPlanks)
	back.CanCollide = true
	local rng = Random.new(44)
	for _, sy in ipairs({ 2.4, 4.6, 6.8 }) do
		ddPart(folder, "DD_BookShelf", Vector3.new(5.8, 0.14, 0.5), Vector3.new(bx, sy, -IW / 2 + 1.6), Color3.fromRGB(70, 48, 32), Enum.Material.WoodPlanks)
		local px = bx - 2.6
		while px < bx + 2.5 do
			local w = rng:NextNumber(0.2, 0.42)
			local h = rng:NextNumber(1.1, 1.65)
			local b = ddPart(folder, "DD_Book", Vector3.new(w, h, 0.45), Vector3.new(px, sy + 0.07 + h / 2, -IW / 2 + 1.6), Color3.fromHSV(rng:NextNumber(0, 0.12), rng:NextNumber(0.35, 0.7), rng:NextNumber(0.18, 0.42)), Enum.Material.Fabric)
			if rng:NextNumber() < 0.12 then b.Orientation = Vector3.new(0, 0, rng:NextInteger(6, 14)) end
			px += w + 0.04
		end
	end
	ddPart(folder, "DD_Rug", Vector3.new(9, 0.05, 5), Vector3.new(cx - 3, 0.04, -8), Color3.fromRGB(70, 28, 24), Enum.Material.Fabric)
	wallPanel(folder, cx + 15, 6.4, 1, 2.8, 3.2, 41, "BUS C")
end

local function dressControlRoom(folder: Instance, model: Instance, cx: number)
	wallPanel(folder, cx - 12, 7.8, 1, 4.4, 3.8, 51, "DEPTH / TRIM")
	wallPanel(folder, cx + 12, 7, 1, 4.4, 4.4, 52, "HYDRAULICS")
	wallPanel(folder, cx - 6, 7, -1, 4.4, 4.4, 53, "BATTERY BUS")
	wallPanel(folder, cx - 12, 7, -1, 4.4, 4.4, 54, "ATMOSPHERE")
	-- helm: tilted instrument desk + control yoke
	local helm = model:FindFirstChild("Helm")
	if helm and helm:IsA("BasePart") then
		local d = ddPart(folder, "DD_HelmDesk", Vector3.new(3.8, 0.2, 2.3), helm.Position + Vector3.new(0, 1.85, 0.5), HULL.tray, Enum.Material.Metal)
		d.Orientation = Vector3.new(24, 0, 0)
		panelFace(d, Enum.NormalId.Top, 5, 3, 55)
		ddCyl(folder, "DD_YokeColumn", 1.5, 0.26, helm.Position + Vector3.new(0, 1.2, -2.5), "Y", DD.dark, Enum.Material.Metal)
		ddPart(folder, "DD_Yoke", Vector3.new(1.9, 0.2, 0.2), helm.Position + Vector3.new(0, 2, -2.5), HULL.pipeSteel, Enum.Material.Metal)
		for _, s in ipairs({ -1, 1 }) do
			ddPart(folder, "DD_YokeGrip", Vector3.new(0.24, 0.6, 0.24), helm.Position + Vector3.new(s * 0.95, 2.1, -2.5), Color3.fromRGB(26, 26, 28), Enum.Material.Rubber)
		end
	end
	local nav = model:FindFirstChild("NavConsole")
	if nav and nav:IsA("BasePart") then
		local d = ddPart(folder, "DD_NavDesk", Vector3.new(7.6, 0.2, 1.6), nav.Position + Vector3.new(0, 1.85, 0), HULL.tray, Enum.Material.Metal)
		d.Orientation = Vector3.new(-18, 0, 0)
		panelFace(d, Enum.NormalId.Top, 9, 2, 56)
	end
	local s, face = consoleScreen(folder, model, "Helm")
	if s then textScreen(s, face, { { "HDG  ---" }, { "TRIM  -14 DEG", Color3.fromRGB(255, 176, 52) }, { "PROPULSION LOST", Color3.fromRGB(240, 70, 56) } }) end
	s, face = consoleScreen(folder, model, "NavConsole")
	if s then textScreen(s, face, { { "NAV  NO FIX" }, { "DEPTH  OFF SCALE", Color3.fromRGB(255, 176, 52) } }) end
	s, face = consoleScreen(folder, model, "BallastPanel")
	local ballast = model:FindFirstChild("BallastPanel")
	if s and ballast then
		local labels = textScreen(s, face, { { "BALLAST CTRL" }, { "" } })
		local function sync()
			local on = ballast:GetAttribute("FuseInstalled") == true
			labels[2].Text = on and "BUS ONLINE" or "FUSE BAY OPEN"
			labels[2].TextColor3 = on and SCREEN_INK or Color3.fromRGB(240, 70, 56)
		end
		ballast:GetAttributeChangedSignal("FuseInstalled"):Connect(sync)
		sync()
	end
end

local function dressSonarDetail(folder: Instance, model: Instance, cx: number)
	local s, face = consoleScreen(folder, model, "SonarConsole")
	if s then sonarScreen(s, face) end
	s, face = consoleScreen(folder, model, "RadioConsole")
	local radio = model:FindFirstChild("RadioConsole")
	if s and radio then
		local labels = textScreen(s, face, { { "HF  2182 kHz" }, { "" } })
		local function sync()
			local locked = radio:GetAttribute("Locked") ~= false
			labels[2].Text = locked and "NO POWER" or "TX READY"
			labels[2].TextColor3 = locked and Color3.fromRGB(240, 70, 56) or SCREEN_INK
		end
		radio:GetAttributeChangedSignal("Locked"):Connect(sync)
		sync()
	end
	-- floor-standing radio rack in the radio half
	local rack = ddPart(folder, "DD_RadioRack", Vector3.new(3.6, 9, 1.4), Vector3.new(cx + 6, 4.5, -IW / 2 + 1), HULL.tray, Enum.Material.Metal)
	rack.MaterialVariant = "MG-Rust 29" ; rack.CanCollide = true
	local rf = Vector3.new(cx + 6, 4.5, -IW / 2 + 1)
	rack.CFrame = CFrame.lookAt(rf, rf + Vector3.new(0, 0, 1))
	panelFace(rack, Enum.NormalId.Front, 5, 11, 61, "TRANSMIT")
	wallPanel(folder, cx - 18, 7, 1, 4.4, 4, 62, "HYDROPHONE ARRAY")
	wallPanel(folder, cx + 18, 7, -1, 4.4, 4, 63, "RADIO BUS")
end

local function dressEngineRoom(folder: Instance, model: Instance, cx: number)
	local gen = model:FindFirstChild("Generator")
	if not (gen and gen:IsA("BasePart")) then return end
	local g = gen.Position
	gen.Material = Enum.Material.Metal ; gen.MaterialVariant = "MG-Rust 06" ; gen.Color = Color3.fromRGB(110, 112, 100)
	for _, c in ipairs(folder:GetChildren()) do
		if c:IsA("BasePart") then
			if c.Name:match("^DD_GTrim") then
				c.Material = Enum.Material.Metal ; c.MaterialVariant = "MG-Rust 12" ; c.Color = DOOR.frame
			elseif c.Name == "DD_GStack" or c.Name == "DD_GCeilPipe" or c.Name:match("^DD_GCoolant") then
				c:Destroy()
			end
		end
	end
	-- skid, cylinder heads, rocker cover, exhaust manifold + stack to the ceiling
	ddPart(folder, "DD_GSkid", Vector3.new(9.6, 0.6, 7.4), Vector3.new(g.X, 0.3, g.Z), DD.dark, Enum.Material.Metal)
	for k = 0, 5 do
		local hx = g.X - 3 + k * 1.2
		ddCyl(folder, "DD_GHead", 0.9, 1.05, Vector3.new(hx, 8.42, g.Z + 0.8), "Y", HULL.pipeSteel, Enum.Material.Metal)
		ddPart(folder, "DD_GPushrod", Vector3.new(0.16, 0.9, 0.7), Vector3.new(hx, 8.42, g.Z - 0.2), DD.dark, Enum.Material.Metal)
		ddCyl(folder, "DD_GRunner", 1.1, 0.34, Vector3.new(hx, 8.5, g.Z - 0.9), "Z", HULL.pipeRust, Enum.Material.Metal).MaterialVariant = "MG-Rust 14"
	end
	ddPart(folder, "DD_GRocker", Vector3.new(7.4, 0.26, 1.5), Vector3.new(g.X, 8.98, g.Z + 0.8), HULL.frame, Enum.Material.Metal)
	ddCyl(folder, "DD_GManifold", 7.8, 0.72, Vector3.new(g.X, 8.5, g.Z - 1.5), "X", HULL.pipeRust, Enum.Material.Metal).MaterialVariant = "MG-Rust 14"
	ddCyl(folder, "DD_GStackPipe", 7, 1.1, Vector3.new(g.X + 3.4, 12, g.Z - 1.5), "Y", HULL.pipeRust, Enum.Material.Metal).MaterialVariant = "MG-Rust 14"
	ddCyl(folder, "DD_GStackBand", 0.3, 1.3, Vector3.new(g.X + 3.4, 11.4, g.Z - 1.5), "Y", DD.dark, Enum.Material.Metal)
	-- access doors either side of the control panel
	for _, s in ipairs({ -1, 1 }) do
		ddPart(folder, "DD_GDoor", Vector3.new(1.6, 5, 0.1), Vector3.new(g.X + s * 3.1, 3.5, g.Z - 3.05), HULL.frame, Enum.Material.Metal).MaterialVariant = "MG-Rust 06"
		ddPart(folder, "DD_GLatch", Vector3.new(0.14, 0.7, 0.16), Vector3.new(g.X + s * 2.5, 3.6, g.Z - 3.14), HULL.pipeSteel, Enum.Material.Metal)
	end
	-- flywheel: an anchored root with welded spokes (WaterRenderer spins it on Running)
	local fly = ddCyl(folder, "DD_GFlywheel", 0.7, 5.4, Vector3.new(g.X - 4.65, 3.2, g.Z), "X", HULL.frame, Enum.Material.Metal)
	fly.Orientation = Vector3.new(0, 0, 0)
	for k = 0, 3 do
		local a = math.rad(k * 90)
		leafPart(fly, "DD_GFlySpoke", Vector3.new(0.14, 0.7, 0.34), CFrame.new(-0.38, math.cos(a) * 1.9, math.sin(a) * 1.9), DD.dark)
	end
	leafPart(fly, "DD_GFlyHub", Vector3.new(0.3, 1.1, 1.1), CFrame.new(-0.42, 0, 0), HULL.pipeSteel, Enum.Material.Metal, Enum.PartType.Cylinder)
	ddPart(folder, "DD_GGuard", Vector3.new(1.3, 0.16, 5.9), Vector3.new(g.X - 4.65, 6.2, g.Z), DOOR.frame, Enum.Material.Metal).MaterialVariant = "MG-Rust 12"
	-- control panel status follows the generator
	local panel = folder:FindFirstChild("DD_GPanel")
	local status
	if panel then
		for _, d in ipairs(panel:GetDescendants()) do
			if d:IsA("TextLabel") and d.Text:find("OFFLINE") then status = d end
		end
	end
	if status then
		local function sync()
			local on = gen:GetAttribute("Running") == true
			status.Text = on and "ONLINE - BUS LIVE" or "OFFLINE - STANDBY"
			status.TextColor3 = on and Color3.fromRGB(96, 240, 150) or Color3.fromRGB(200, 120, 40)
		end
		gen:GetAttributeChangedSignal("Running"):Connect(sync)
		sync()
	end
	-- walkway deck + hazard edge
	local walk = model:FindFirstChild("Walkway")
	if walk and walk:IsA("BasePart") then
		walk.Material = Enum.Material.DiamondPlate ; walk.MaterialVariant = "deepdescent_floor_grate" ; walk.Color = Color3.fromRGB(72, 74, 76)
		ddPart(folder, "DD_WalkEdge", Vector3.new(walk.Size.X, 0.05, 0.22), walk.Position + Vector3.new(0, 0.22, 2.02), DOOR.frame, Enum.Material.SmoothPlastic)
	end
	-- plant on the +Z side: pressure tank on cradles, and a pump + motor set
	local tx = cx + 14
	local tank = ddCyl(folder, "DD_Tank", 8, 3.6, Vector3.new(tx, 2.9, 8.6), "X", HULL.pipeNavy, Enum.Material.Metal)
	tank.MaterialVariant = "MG-Rust 28" ; tank.CanCollide = true ; tank.CastShadow = true
	for _, ox in ipairs({ -2.6, 2.6 }) do
		ddPart(folder, "DD_TankCradle", Vector3.new(0.5, 1.4, 3.6), Vector3.new(tx + ox, 0.7, 8.6), DD.dark, Enum.Material.Metal)
		ddCyl(folder, "DD_TankStrap", 0.26, 3.72, Vector3.new(tx + ox, 2.9, 8.6), "X", DD.dark, Enum.Material.Metal)
	end
	ddCyl(folder, "DD_TankPipe", 9.2, 0.5, Vector3.new(tx - 1.2, 9.2, 8.6), "Y", HULL.pipeSteel, Enum.Material.Metal)
	local mx = cx - 14
	ddPart(folder, "DD_PumpSkid", Vector3.new(7, 0.5, 3.2), Vector3.new(mx, 0.25, 8.6), DD.dark, Enum.Material.Metal)
	local motor = ddCyl(folder, "DD_Motor", 3.4, 2.4, Vector3.new(mx - 1.4, 1.75, 8.6), "X", HULL.frame, Enum.Material.Metal)
	motor.MaterialVariant = "MG-Rust 06" ; motor.CanCollide = true ; motor.CastShadow = true
	for k = 0, 3 do
		ddCyl(folder, "DD_MotorFin", 0.12, 2.6, Vector3.new(mx - 2.6 + k * 0.8, 1.75, 8.6), "X", DD.dark, Enum.Material.Metal)
	end
	local pump = ddPart(folder, "DD_Pump", Vector3.new(2, 2, 2), Vector3.new(mx + 1.6, 1.5, 8.6), HULL.bandRed, Enum.Material.Metal, Enum.PartType.Ball)
	pump.MaterialVariant = "MG-Rust 13" ; pump.CanCollide = true
	ddCyl(folder, "DD_PumpRiser", 11.8, 0.6, Vector3.new(mx + 1.6, 8, 8.6), "Y", HULL.pipeRust, Enum.Material.Metal).MaterialVariant = "MG-Rust 14"
	wallPanel(folder, cx - 18, 7, 1, 4.4, 4.2, 81, "AUX BUS")
	wallPanel(folder, cx + 12, 7, -1, 4.4, 4.2, 82, "ENGINE ORDER")
end

local function dressAftDetail(folder: Instance, cx: number)
	-- torpedo hoist: an overhead rail, trolley and chain
	local rz, ry = -IW / 2 + 3, 12.9
	ddPart(folder, "DD_HoistRail", Vector3.new(IL - 2, 0.5, 0.34), Vector3.new(cx, ry, rz), DD.dark, Enum.Material.Metal).CastShadow = true
	for _, ox in ipairs({ -15, -3, 9, 21 }) do
		ddPart(folder, "DD_HoistHanger", Vector3.new(0.2, 2.2, 0.2), Vector3.new(cx + ox + 0.5, ry + 1.3, rz), DD.dark, Enum.Material.Metal)
	end
	local tx = cx + 7
	local trolley = ddPart(folder, "DD_HoistTrolley", Vector3.new(1.3, 0.5, 0.9), Vector3.new(tx, ry - 0.4, rz), DOOR.frame, Enum.Material.Metal)
	trolley.MaterialVariant = "MG-Rust 12"
	local hook = ddPart(folder, "DD_HoistHook", Vector3.new(0.5, 0.5, 0.2), Vector3.new(tx, 6.5, rz), DD.dark, Enum.Material.Metal)
	local a0 = Instance.new("Attachment") ; a0.Name = "DD_ChainA" ; a0.Parent = trolley
	local a1 = Instance.new("Attachment") ; a1.Name = "DD_ChainB" ; a1.Parent = hook
	local chain = Instance.new("Beam")
	chain.Name = "DD_Chain" ; chain.Attachment0 = a0 ; chain.Attachment1 = a1 ; chain.Width0 = 0.14 ; chain.Width1 = 0.14
	chain.FaceCamera = true ; chain.LightInfluence = 1 ; chain.Color = ColorSequence.new(Color3.fromRGB(36, 36, 38)) ; chain.Transparency = NumberSequence.new(0)
	chain.Parent = trolley
	wallPanel(folder, cx - 12, 11, -1, 3.8, 3, 91, "TUBE AFT")
end

-- ============================================================================
-- Grime + signage (visual batch 2b): no textures, just gradients and paint.
-- Each side wall gets one low-res SurfaceGui with a dark waterline band, a pale salt
-- line at the old high-water mark and rust streaks running down from the pipes.
-- ============================================================================
local function gradientDown(f: Frame, topT: number, bottomT: number)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Transparency = NumberSequence.new(topT, bottomT)
	g.Parent = f
end

local function wallGrime(wall: Instance?, face: Enum.NormalId, seed: number, startLevel: number)
	if not (wall and wall:IsA("BasePart")) then return end
	local rng = Random.new(seed)
	local sg = Instance.new("SurfaceGui")
	sg.Name = "DD_Grime" ; sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud ; sg.PixelsPerStud = 14
	sg.LightInfluence = 1 ; sg.Parent = wall
	local tideH = math.clamp(startLevel / 100 + 0.22, 0.24, 0.72)
	local tide = Instance.new("Frame")
	tide.Position = UDim2.fromScale(0, 1 - tideH) ; tide.Size = UDim2.fromScale(1, tideH)
	tide.BackgroundColor3 = Color3.fromRGB(10, 10, 8) ; tide.BorderSizePixel = 0 ; tide.Parent = sg
	gradientDown(tide, 1, 0.12)
	local salt = Instance.new("Frame")
	salt.Position = UDim2.fromScale(0, 1 - tideH * 0.72) ; salt.Size = UDim2.fromScale(1, 0.012)
	salt.BackgroundColor3 = Color3.fromRGB(150, 150, 132) ; salt.BackgroundTransparency = 0.72 ; salt.BorderSizePixel = 0 ; salt.Parent = sg
	for _ = 1, 16 do
		local s = Instance.new("Frame")
		local rust = rng:NextNumber() < 0.7
		s.Position = UDim2.fromScale(rng:NextNumber(0, 0.99), rng:NextNumber(0.06, 0.3))
		s.Size = UDim2.fromScale(rng:NextNumber(0.004, 0.02), rng:NextNumber(0.18, 0.6))
		s.BackgroundColor3 = rust and Color3.fromRGB(70, 36, 18) or Color3.fromRGB(12, 11, 10)
		s.BorderSizePixel = 0 ; s.Parent = sg
		gradientDown(s, 0.22, 1)
	end
end

local ROOM_SIGN = {
	[1] = "FWD TORPEDO ROOM", [2] = "CREW BERTHING", [3] = "GALLEY + MESS", [4] = "OFFICERS",
	[5] = "CONTROL ROOM", [6] = "SONAR + RADIO", [8] = "ENGINE ROOM", [9] = "AFT TORPEDO ROOM",
}
local WARNING = {
	[1] = "LIVE WARHEADS", [2] = "NO LOOSE GEAR", [3] = "SECURE FOR DIVE", [4] = "AUTHORIZED ONLY",
	[5] = "SILENCE ON THE BOAT", [6] = "EARPHONES ONLY", [8] = "HEARING PROTECTION", [9] = "LIVE WARHEADS",
}
-- scratched into the paint by someone who had time to think about it
local SCRAWL = {
	[2] = { x = 2, side = -1, y = 6.6, w = 7, text = "DON'T RUN", tilt = -4 },
	[6] = { x = -8, side = -1, y = 6.2, w = 7.5, text = "IT'S LISTENING", tilt = 3 },
	[8] = { x = 15, side = -1, y = 5.4, w = 9, text = "IT COMES WHEN THE LIGHTS DO", tilt = -3 },
}

local function dressGrime(folder: Instance, model: Instance, i: number, cx: number)
	local data = SectionData.Sections[i]
	local lvl = (data and data.startLevel) or 10
	wallGrime(model:FindFirstChild("WallZpos"), Enum.NormalId.Front, 100 + i, lvl)
	wallGrime(model:FindFirstChild("WallZneg"), Enum.NormalId.Back, 200 + i, lvl)
	-- compartment name over each doorway, facing into the room
	local slot = hullSlot[i]
	for _, dir in ipairs({ -1, 1 }) do
		if (dir == -1 and slot > 0) or (dir == 1 and slot < LAST_SLOT) then
			stencil(folder, Vector3.new(cx + dir * (IL / 2 - 0.04), 13.2, 0), Vector3.new(-dir, 0, 0), 10, 1.15, ROOM_SIGN[i] or "")
		end
	end
	-- side-wall stencils: frame number + standing order
	stencil(folder, Vector3.new(cx - 12, 10.4, IW / 2 - 0.04), Vector3.new(0, 0, -1), 4, 0.8, WARNING[i] or "", Color3.fromRGB(190, 150, 70), nil, 0.4)
	for _, ox in ipairs({ -18, 0, 18 }) do
		stencil(folder, Vector3.new(cx + ox, 2.6, -IW / 2 + 0.04), Vector3.new(0, 0, 1), 1.5, 0.55, ("FR %d"):format(10 + (slot or 0) * 18 + math.floor((ox + 18) / 2)))
	end
	local s = SCRAWL[i]
	if s then
		stencil(folder, Vector3.new(cx + s.x, s.y, s.side * (IW / 2 - 0.04)), Vector3.new(0, 0, -s.side), s.w, 1.6, s.text, Color3.fromRGB(140, 44, 30), Enum.Font.PermanentMarker, 0.12, s.tilt)
	end
	if i == 1 then
		for t = 0, 3 do
			local z = -9 + t * 6
			local y = (z > 5) and 8.6 or 4.6
			stencil(folder, Vector3.new(cx - IL / 2 + 4.45, y + 1.05, z), Vector3.new(1, 0, 0), 0.8, 0.8, tostring(t + 1))
		end
	end
end

-- ============================================================================
-- Atmosphere effects (visual batch 4b): drips, steam leaks, a dangling cable that
-- sparks, and light shafts at the breach. Everything sits on tiny invisible parts.
-- WaterRenderer adds a ripple where each DD_Drip lands; PolishManager fires sparks.
-- ============================================================================
local SMOKE_TEX = "rbxasset://textures/particles/smoke_main.dds"

local function fxPoint(folder: Instance, name: string, pos: Vector3)
	local p = ddPart(folder, name, Vector3.new(0.1, 0.1, 0.1), pos, HULL.cable, Enum.Material.SmoothPlastic)
	p.Transparency = 1
	return p
end

local function addDrip(folder: Instance, i: number, x: number, y: number, z: number, rate: number)
	local p = fxPoint(folder, "DD_Drip", Vector3.new(x, y, z))
	p:SetAttribute("Section", i)
	p:SetAttribute("Rate", rate)
	CollectionService:AddTag(p, "DD_Drip")
	local e = Instance.new("ParticleEmitter")
	e.Name = "DD_DripFX" ; e.Texture = SMOKE_TEX ; e.Rate = rate
	e.EmissionDirection = Enum.NormalId.Bottom ; e.Speed = NumberRange.new(0.2) ; e.SpreadAngle = Vector2.new(0, 0)
	e.Acceleration = Vector3.new(0, -48, 0) ; e.Lifetime = NumberRange.new(0.8)
	e.Size = NumberSequence.new(0.09) ; e.Squash = NumberSequence.new(1.4)
	e.Transparency = NumberSequence.new(0.1) ; e.LightInfluence = 0.75 ; e.Brightness = 3
	e.Color = ColorSequence.new(Color3.fromRGB(200, 214, 220)) ; e.Parent = p
end

local function addSteam(folder: Instance, pos: Vector3, dir: Vector3, rate: number)
	local p = fxPoint(folder, "DD_SteamLeak", pos)
	p.CFrame = CFrame.lookAt(pos, pos + dir)
	local e = Instance.new("ParticleEmitter")
	e.Name = "DD_SteamFX" ; e.Texture = SMOKE_TEX ; e.Rate = rate
	e.EmissionDirection = Enum.NormalId.Front ; e.Speed = NumberRange.new(1.6, 3) ; e.SpreadAngle = Vector2.new(14, 14)
	e.Acceleration = Vector3.new(0, 1.2, 0) ; e.Drag = 1.2 ; e.Lifetime = NumberRange.new(2, 3.6)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 3) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.72), NumberSequenceKeypoint.new(1, 1) })
	e.LightInfluence = 1 ; e.Brightness = 1.4 ; e.RotSpeed = NumberRange.new(-30, 30) ; e.Rotation = NumberRange.new(0, 360)
	e.Color = ColorSequence.new(Color3.fromRGB(205, 208, 212)) ; e.Parent = p
end

-- a cable hanging out of the tray; its cut end is what sparks (PolishManager)
local function addSparker(folder: Instance, x: number, y: number)
	local z = -8.3
	local p = fxPoint(folder, "DD_CableEnd", Vector3.new(x, y, z))
	CollectionService:AddTag(p, "DD_Sparker")
	local a0 = Instance.new("Attachment") ; a0.Name = "DD_TopA" ; a0.Parent = p ; a0.WorldPosition = Vector3.new(x + 0.9, 14.95, z)
	local a1 = Instance.new("Attachment") ; a1.Name = "DD_EndA" ; a1.Parent = p
	a0.Axis = Vector3.new(0, -1, 0) ; a0.SecondaryAxis = Vector3.new(1, 0, 0)
	a1.Axis = Vector3.new(1, 0.4, 0) ; a1.SecondaryAxis = Vector3.new(0, 1, 0)
	local beam = Instance.new("Beam")
	beam.Name = "DD_LooseCable" ; beam.Attachment0 = a0 ; beam.Attachment1 = a1
	beam.Color = ColorSequence.new(HULL.cable) ; beam.Width0 = 0.13 ; beam.Width1 = 0.1 ; beam.FaceCamera = true
	beam.Segments = 10 ; beam.LightInfluence = 1 ; beam.Transparency = NumberSequence.new(0)
	beam.CurveSize0 = 2 ; beam.CurveSize1 = 1
	beam.Parent = p
end

local function dressEffects(folder: Instance, i: number, cx: number)
	local shift = (i % 3) * 2
	addDrip(folder, i, cx - 18 + shift, 14, 9.2, 0.55)
	addDrip(folder, i, cx + 6 + shift, 14, 9.2, 0.9)
	addDrip(folder, i, cx - 7, 14.7, -8.1, 0.35)
	addSteam(folder, Vector3.new(cx - 6 + shift, 14.3, 8.8), Vector3.new(0.2, -0.4, -1).Unit, (i == 8) and 7 or 3)
	if i == 3 then addSteam(folder, Vector3.new(cx, 11.4, -9.2), Vector3.new(0.1, -1, 0.3).Unit, 3) end
	if i == 8 then addSteam(folder, Vector3.new(cx + 18, 14.1, -10.2), Vector3.new(-0.5, -0.5, 0.7).Unit, 5) end
	if i == 2 then addSparker(folder, cx + 12, 8.6)
	elseif i == 3 then addSparker(folder, cx - 16, 9.2)
	elseif i == 6 then addSparker(folder, cx + 15, 8.2)
	elseif i == 9 then addSparker(folder, cx - 5, 9.4)
	end
	if i == 9 then
		-- cold light falling in through the breach
		local la = folder:FindFirstChild("DD_BreachLightAnchor")
		if la then
			for k = -1, 1 do
				local a0 = Instance.new("Attachment") ; a0.Name = "DD_ShaftA" ; a0.Parent = la
				a0.WorldPosition = Vector3.new(cx + IL / 2 - 0.6, 7.5 + k * 1.4, 5 + k * 3.4)
				local a1 = Instance.new("Attachment") ; a1.Name = "DD_ShaftB" ; a1.Parent = la
				a1.WorldPosition = Vector3.new(cx + IL / 2 - 20, 2 + k * 1.4, 3 + k * 6)
				local b = Instance.new("Beam")
				b.Name = "DD_BreachShaft" ; b.Attachment0 = a0 ; b.Attachment1 = a1
				b.Width0 = 3 ; b.Width1 = 8 ; b.FaceCamera = true ; b.Segments = 1 ; b.LightEmission = 1 ; b.LightInfluence = 0
				b.Color = ColorSequence.new(Color3.fromRGB(70, 170, 190))
				b.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.84), NumberSequenceKeypoint.new(0.6, 0.95), NumberSequenceKeypoint.new(1, 1) })
				b.Parent = la
			end
		end
	end
end

-- ============================================================================
-- Conning tower (visual batch 6): frames + two viewports. There is nothing outside the
-- hull to look at, so a viewport is a painted view: a round SurfaceGui of black water
-- and marine snow in a bolted rim. On its Sighting attribute (PolishManager) the
-- DD_SightLight dots drift across it; WaterRenderer runs that on the client.
-- ============================================================================
local function towerWindow(folder: Instance, x: number, y: number, z: number, inwardX: number)
	local pos = Vector3.new(x, y, z)
	local base = CFrame.lookAt(pos, pos + Vector3.new(inwardX, 0, 0))
	local R = 1.9
	for k = 0, 7 do
		local a = math.rad(k * 45)
		local seg = ddPart(folder, "DD_PortRim", Vector3.new(1.62, 0.36, 0.42), pos, HULL.frame, Enum.Material.Metal)
		seg.CFrame = base * CFrame.new(math.cos(a) * R, math.sin(a) * R, 0) * CFrame.Angles(0, 0, a + math.rad(90))
		seg.MaterialVariant = "MG-Rust 24"
	end
	local view = ddPart(folder, "DD_PortView", Vector3.new(3.5, 3.5, 0.05), pos, HULL.cable, Enum.Material.SmoothPlastic)
	view.Transparency = 1
	view.CFrame = base * CFrame.new(0, 0, -0.04)
	CollectionService:AddTag(view, "DD_TowerWindow")
	local sg = Instance.new("SurfaceGui")
	sg.Name = "DD_PortGui" ; sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud ; sg.PixelsPerStud = 50
	sg.LightInfluence = 0 ; sg.Brightness = 2 ; sg.Parent = view
	local water = roundFrame(sg, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), Color3.new(1, 1, 1)) -- the gradient multiplies this
	water.Name = "Water"
	local g = Instance.new("UIGradient") ; g.Rotation = 90
	g.Color = ColorSequence.new(Color3.fromRGB(18, 54, 76), Color3.fromRGB(1, 4, 8)) ; g.Parent = water
	local rng = Random.new(math.floor(z * 10) + 7)
	for _ = 1, 16 do
		local r, ang = rng:NextNumber(0, 0.42), rng:NextNumber(0, math.pi * 2)
		local s = rng:NextNumber(0.006, 0.016)
		local snow = roundFrame(water, UDim2.fromScale(s, s), UDim2.fromScale(0.5 + math.cos(ang) * r, 0.5 + math.sin(ang) * r), Color3.fromRGB(170, 200, 210))
		snow.BackgroundTransparency = rng:NextNumber(0.45, 0.85)
	end
	for k = 1, 5 do
		local l = roundFrame(water, UDim2.fromScale(0.02 + (k % 2) * 0.014, 0.02 + (k % 2) * 0.014), UDim2.fromScale(0.5, 0.5), Color3.fromRGB(150, 235, 215))
		l.Name = "DD_SightLight" ; l.BackgroundTransparency = 1 ; l.ZIndex = 3 ; l:SetAttribute("Index", k)
	end
	-- something huge eclipsing the deep's glow: a soft black band, clipped by the round glass
	local mass = roundFrame(water, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), Color3.new(0, 0, 0))
	mass.Name = "DD_SightMass" ; mass.ZIndex = 2
	local band = Instance.new("UIGradient")
	band.Name = "Band" ; band.Offset = Vector2.new(-1, 0)
	band.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.28, 1), NumberSequenceKeypoint.new(0.44, 0.04),
		NumberSequenceKeypoint.new(0.56, 0.04), NumberSequenceKeypoint.new(0.72, 1), NumberSequenceKeypoint.new(1, 1),
	})
	band.Parent = mass
end

local function dressTower(folder: Instance, cx: number)
	local baseY, topY = 19, 33
	local cy = (baseY + topY) / 2
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local post = ddPart(folder, "DD_TowerPost", Vector3.new(0.7, topY - baseY, 0.7), Vector3.new(cx + sx * 3.65, cy, sz * 3.65), HULL.frame, Enum.Material.Metal)
			post.MaterialVariant = "MG-Rust 24" ; post.CastShadow = true
		end
	end
	for _, y in ipairs({ 21, 27.6, 32.4 }) do
		for _, s in ipairs({ -1, 1 }) do
			ddPart(folder, "DD_TowerRing", Vector3.new(8, 0.5, 0.3), Vector3.new(cx, y, s * 3.86), HULL.frame, Enum.Material.Metal).MaterialVariant = "MG-Rust 24"
			ddPart(folder, "DD_TowerRing", Vector3.new(0.3, 0.5, 8), Vector3.new(cx + s * 3.86, y, 0), HULL.frame, Enum.Material.Metal).MaterialVariant = "MG-Rust 24"
		end
	end
	towerWindow(folder, cx - 3.82, 24.2, 0.4, 1)
	towerWindow(folder, cx + 3.82, 24.2, 1, -1)
	stencil(folder, Vector3.new(cx, 29.8, 3.96), Vector3.new(0, 0, -1), 4.4, 0.7, "CONNING TOWER")
end

local function dressMachinery(folder: Instance, model: Instance, i: number, cx: number)
	if i == 7 then dressTower(folder, cx) ; return end
	dressDoorFrames(folder, i, cx)
	dressGrime(folder, model, i, cx)
	dressEffects(folder, i, cx)
	if i == 1 then dressTorpedoRoom(folder, model, cx)
	elseif i == 2 then dressBerthingDetail(folder, cx)
	elseif i == 3 then dressGalleyDetail(folder, model, cx)
	elseif i == 4 then dressOfficersDetail(folder, model, cx)
	elseif i == 5 then dressControlRoom(folder, model, cx)
	elseif i == 6 then dressSonarDetail(folder, model, cx)
	elseif i == 8 then dressEngineRoom(folder, model, cx)
	elseif i == 9 then dressAftDetail(folder, cx)
	end
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
				dressIndustrial(folder, cx, i)
				if i == 2 then dressBerthing(folder, model, cx)
				elseif i == 3 then dressGalley(folder, model, cx) ; dressNotice(folder, model, cx)
				elseif i == 4 then dressOfficers(folder, model, cx)
				elseif i == 5 then dressConsole(folder, model, "Helm") ; dressConsole(folder, model, "NavConsole") ; dressConsole(folder, model, "BallastPanel")
				elseif i == 6 then dressConsole(folder, model, "SonarConsole") ; dressConsole(folder, model, "RadioConsole") ; dressSonarRadio(folder, model, cx)
				elseif i == 8 then dressGenerator(folder, model)
				elseif i == 9 then dressBreach(folder, model, cx) ; dressAft(folder, model, cx)
				end
			end
			dressSurfaces(model, i)
			dressEmergencyLighting(folder, model, i, cx)  -- after the room dressing (uses its screens/panels)
			dressMainLamps(folder, model, i, cx)
			dressMachinery(folder, model, i, cx)
			n += 1
		end
	end
	dressConnectorSurfaces()
	dressBulkheadDoors()
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
