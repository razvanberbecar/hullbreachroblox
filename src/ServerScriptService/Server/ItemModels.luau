--!strict
-- ItemModels.lua  →  ModuleScript in ServerScriptService/Server
-- =============================================================================
-- Builds recognizable greybox-plus models for every world pickup + journal, so
-- items read as real objects in the dark rather than identical neon cubes.
--
-- Contract: each model is ONE invisible ROOT BasePart (MapBuilder tags it
-- "Pickup"/"Journal", sets ItemId/PageIndex, and adds the ProximityPrompt;
-- InventoryManager destroys it on collection). All visible detail parts are
-- parented UNDER the root, so destroying the root removes the whole model.
--
-- Horror lighting rule: items do NOT illuminate the room (that would kill the
-- dark and the purpose of the flashlight). Only genuine light sources (glow
-- stick, flashlight lens) carry a faint glow; everything else relies on the
-- player's beam catching its surfaces, with small emissive accents for a glint.
--
-- Drop-in art: if ReplicatedStorage/Assets/ItemModels/<itemId> (a Model) exists,
-- it is cloned and used instead — imported meshes replace these with no code
-- change.
-- =============================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemModels = {}

local COL = {
	metalDark = Color3.fromRGB(40, 44, 50),
	metal     = Color3.fromRGB(74, 80, 88),
	steel     = Color3.fromRGB(120, 128, 136),
	rubber    = Color3.fromRGB(22, 24, 28),
	rust      = Color3.fromRGB(110, 64, 38),
	caution   = Color3.fromRGB(206, 170, 60),
	brass     = Color3.fromRGB(176, 142, 74),
	paper     = Color3.fromRGB(208, 197, 166),
	ink       = Color3.fromRGB(40, 34, 28),
	lensWarm  = Color3.fromRGB(255, 244, 214),
	tank      = Color3.fromRGB(46, 92, 74),
	glassPale = Color3.fromRGB(225, 235, 235),
	cardBody  = Color3.fromRGB(38, 66, 92),
	ledRed    = Color3.fromRGB(220, 70, 60),
	glowGreen = Color3.fromRGB(120, 255, 150),
}

-- helpers --------------------------------------------------------------------
local function makeRoot(cframe: CFrame): Part
	local r = Instance.new("Part")
	r.Name = "Root"
	r.Size = Vector3.new(0.6, 0.6, 0.6)
	r.Transparency = 1
	r.Anchored = true
	r.CanCollide = false
	r.CanQuery = true       -- allow the Hint Highlight + selection to adorn it
	r.CanTouch = false
	r.CastShadow = false
	r.CFrame = cframe
	return r
end

local function child(root: Part, name: string, size: Vector3, color: Color3, material: Enum.Material, offset: CFrame, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then p.Shape = shape end
	p.CFrame = root.CFrame * offset
	p.Parent = root
	return p
end

-- cylinder whose LENGTH points along a local axis ("x" | "y" | "z")
local function cyl(root: Part, name: string, length: number, diameter: number, color: Color3, material: Enum.Material, pos: Vector3, axis: string): Part
	local rot
	if axis == "y" then rot = CFrame.Angles(0, 0, math.rad(90))
	elseif axis == "z" then rot = CFrame.Angles(0, math.rad(90), 0)
	else rot = CFrame.new() end
	return child(root, name, Vector3.new(length, diameter, diameter), color, material, CFrame.new(pos) * rot, Enum.PartType.Cylinder)
end

-- per-item builders ----------------------------------------------------------
local function buildFlashlight(root: Part)
	cyl(root, "Body", 1.3, 0.34, COL.metalDark, Enum.Material.Metal, Vector3.new(0, 0, 0.10), "z")
	cyl(root, "Grip", 0.45, 0.37, COL.rubber, Enum.Material.Plastic, Vector3.new(0, 0, 0.28), "z")
	cyl(root, "Head", 0.32, 0.52, COL.metal, Enum.Material.Metal, Vector3.new(0, 0, -0.62), "z")
	local lens = cyl(root, "Lens", 0.06, 0.44, COL.lensWarm, Enum.Material.Glass, Vector3.new(0, 0, -0.80), "z")
	lens.Transparency = 0.2
	child(root, "Switch", Vector3.new(0.1, 0.08, 0.16), COL.ledRed, Enum.Material.SmoothPlastic, CFrame.new(0, 0.16, 0.34))
end

local function buildBattery(root: Part)
	child(root, "Casing", Vector3.new(0.62, 0.5, 0.42), COL.rubber, Enum.Material.Plastic, CFrame.new(0, 0, 0))
	child(root, "Stripe", Vector3.new(0.64, 0.06, 0.44), COL.caution, Enum.Material.SmoothPlastic, CFrame.new(0, 0.26, 0))
	cyl(root, "TermA", 0.14, 0.12, COL.brass, Enum.Material.Metal, Vector3.new(0.18, 0.32, 0), "y")
	cyl(root, "TermB", 0.14, 0.12, COL.brass, Enum.Material.Metal, Vector3.new(-0.18, 0.32, 0), "y")
	child(root, "Plate", Vector3.new(0.02, 0.32, 0.32), COL.steel, Enum.Material.Metal, CFrame.new(0.32, 0, 0))
end

local function buildOxygen(root: Part)
	cyl(root, "Tank", 1.3, 0.5, COL.tank, Enum.Material.Metal, Vector3.new(0, 0, 0), "y")
	cyl(root, "Band", 0.12, 0.54, COL.caution, Enum.Material.SmoothPlastic, Vector3.new(0, 0.3, 0), "y")
	cyl(root, "Cap", 0.16, 0.42, COL.metal, Enum.Material.Metal, Vector3.new(0, 0.7, 0), "y")
	child(root, "Valve", Vector3.new(0.16, 0.16, 0.16), COL.brass, Enum.Material.Metal, CFrame.new(0, 0.84, 0))
	cyl(root, "Wheel", 0.06, 0.34, COL.brass, Enum.Material.Metal, Vector3.new(0, 0.95, 0), "y")
	child(root, "Label", Vector3.new(0.02, 0.4, 0.3), COL.glassPale, Enum.Material.SmoothPlastic, CFrame.new(0.27, -0.1, 0))
end

local function buildKeycard(root: Part)
	child(root, "Card", Vector3.new(0.78, 0.05, 0.5), COL.cardBody, Enum.Material.SmoothPlastic, CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(12), 0))
	child(root, "Stripe", Vector3.new(0.78, 0.01, 0.12), COL.ink, Enum.Material.SmoothPlastic, CFrame.new(0, 0.03, 0.16) * CFrame.Angles(0, math.rad(12), 0))
	child(root, "Chip", Vector3.new(0.12, 0.02, 0.1), COL.brass, Enum.Material.Metal, CFrame.new(-0.22, 0.03, -0.12) * CFrame.Angles(0, math.rad(12), 0))
end

local function buildFuse(root: Part)
	local glass = cyl(root, "Glass", 0.5, 0.16, COL.glassPale, Enum.Material.Glass, Vector3.new(0, 0, 0), "z")
	glass.Transparency = 0.4
	cyl(root, "CapA", 0.12, 0.18, COL.brass, Enum.Material.Metal, Vector3.new(0, 0, 0.28), "z")
	cyl(root, "CapB", 0.12, 0.18, COL.brass, Enum.Material.Metal, Vector3.new(0, 0, -0.28), "z")
	cyl(root, "Filament", 0.34, 0.03, COL.caution, Enum.Material.Neon, Vector3.new(0, 0, 0), "z")
end

local function buildPodComponent(root: Part)
	child(root, "Housing", Vector3.new(0.7, 0.6, 0.6), COL.metalDark, Enum.Material.Metal, CFrame.new(0, 0, 0))
	child(root, "Face", Vector3.new(0.02, 0.5, 0.5), COL.metal, Enum.Material.Metal, CFrame.new(0.36, 0, 0))
	cyl(root, "Pipe", 0.8, 0.16, COL.steel, Enum.Material.Metal, Vector3.new(0, 0.34, 0), "x")
	cyl(root, "Wheel", 0.06, 0.3, COL.brass, Enum.Material.Metal, Vector3.new(0.42, 0.34, 0), "x")
	child(root, "Caution", Vector3.new(0.72, 0.08, 0.08), COL.caution, Enum.Material.SmoothPlastic, CFrame.new(0, -0.28, 0.28))
	child(root, "LED", Vector3.new(0.06, 0.06, 0.06), COL.ledRed, Enum.Material.Neon, CFrame.new(0.37, -0.18, 0.18))
end

local function buildGlowStick(root: Part)
	local tube = cyl(root, "Tube", 0.7, 0.14, COL.glowGreen, Enum.Material.Neon, Vector3.new(0, 0, 0), "z")
	cyl(root, "CapA", 0.06, 0.16, COL.rubber, Enum.Material.Plastic, Vector3.new(0, 0, 0.36), "z")
	cyl(root, "CapB", 0.06, 0.16, COL.rubber, Enum.Material.Plastic, Vector3.new(0, 0, -0.36), "z")
	local light = Instance.new("PointLight")
	light.Color = COL.glowGreen
	light.Brightness = 0.6
	light.Range = 7
	light.Shadows = false
	light.Parent = tube
end

local function buildJournal(root: Part)
	child(root, "Sheet1", Vector3.new(0.7, 0.02, 0.92), COL.paper, Enum.Material.SmoothPlastic, CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(8), 0))
	child(root, "Sheet2", Vector3.new(0.66, 0.02, 0.88), COL.paper, Enum.Material.SmoothPlastic, CFrame.new(0.04, 0.025, 0.03) * CFrame.Angles(0, math.rad(-6), 0))
	for i = -1, 1 do
		child(root, "Ink" .. (i + 2), Vector3.new(0.42, 0.005, 0.02), COL.ink, Enum.Material.SmoothPlastic, CFrame.new(0, 0.04, i * 0.2) * CFrame.Angles(0, math.rad(8), 0))
	end
end

local BUILDERS = {
	flashlight = buildFlashlight,
	battery = buildBattery,
	oxygen_canister = buildOxygen,
	keycard = buildKeycard,
	fuse = buildFuse,
	pod_component = buildPodComponent,
	glow_stick = buildGlowStick,
}

-- imported-art override ------------------------------------------------------
local function tryOverride(itemId: string, cframe: CFrame): Part?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local lib = assets and assets:FindFirstChild("ItemModels")
	local tmpl = lib and lib:FindFirstChild(itemId)
	if tmpl and tmpl:IsA("Model") then
		local root = makeRoot(cframe)
		local clone = tmpl:Clone()
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
			end
		end
		clone.Parent = root
		clone:PivotTo(cframe)
		return root
	end
	return nil
end

function ItemModels.BuildPickup(itemId: string, cframe: CFrame): Part
	local ov = tryOverride(itemId, cframe)
	if ov then return ov end
	local root = makeRoot(cframe)
	local builder = BUILDERS[itemId]
	if builder then
		builder(root)
	else
		child(root, "Crate", Vector3.new(0.8, 0.8, 0.8), COL.rust, Enum.Material.Wood, CFrame.new())
	end
	return root
end

function ItemModels.BuildJournal(_pageIndex: number, cframe: CFrame): Part
	local ov = tryOverride("journal_page", cframe)
	if ov then return ov end
	local root = makeRoot(cframe)
	buildJournal(root)
	return root
end

return ItemModels
