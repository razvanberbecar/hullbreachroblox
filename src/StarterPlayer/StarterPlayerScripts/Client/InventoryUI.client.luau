--!strict
-- InventoryUI.client.lua  →  LocalScript in StarterPlayerScripts/Client
-- =============================================================================
-- The 4-slot inventory at bottom center, plus a DEDICATED flashlight slot to its
-- left. The flashlight is NOT one of the 4 (the GDD keeps those as pressure): it
-- has its own slot and is toggled on/off with F (equip / holster).
--
-- Item use is two-step (so equipping never wastes a consumable): press 1-4 (or
-- tap a slot) to SELECT it; press E (or tap the already-selected slot again, for
-- mobile) to USE it. Right-click / long-press drops. While a modal menu is open
-- (UIModalOpen attribute, e.g. the ballast puzzle) the hotbar ignores keys so
-- number presses don't both switch items and feed the puzzle.
-- =============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemData = require(Shared:WaitForChild("ItemData"))
local Net = require(Shared:WaitForChild("Net"))

local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "DeepDescentInventory"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local SLOT_DIM = Color3.fromRGB(14, 16, 18)
local SLOT_FILLED = Color3.fromRGB(28, 34, 40)
local STROKE_DIM = Color3.fromRGB(60, 70, 80)
local STROKE_SEL = Color3.fromRGB(240, 220, 120)

-- Inventory slots ------------------------------------------------------------
local holder = Instance.new("Frame")
holder.AnchorPoint = Vector2.new(0.5, 1)
holder.Position = UDim2.new(0.5, 0, 1, -70)
holder.Size = UDim2.fromOffset(4 * 64 + 3 * 8, 64)
holder.BackgroundTransparency = 1
holder.Parent = gui
local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.Padding = UDim.new(0, 8)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Parent = holder

local slotButtons = {}
local slotStrokes = {}
local filled = {}            -- filled[i] = true when slot i holds an item
local selectedSlot: number? = nil

local function refreshSelection()
	for i = 1, ItemData.MAX_SLOTS do
		local st = slotStrokes[i]
		if st then
			if i == selectedSlot then
				st.Color = STROKE_SEL
				st.Thickness = 2
			else
				st.Color = STROKE_DIM
				st.Thickness = 1
			end
		end
	end
end

local function setSelected(i: number)
	selectedSlot = i
	refreshSelection()
end

local function useSelected()
	if selectedSlot and filled[selectedSlot] then
		Net.Event("UseItem"):FireServer(selectedSlot, "use")
	end
end

for i = 1, ItemData.MAX_SLOTS do
	local b = Instance.new("TextButton")
	b.Name = "Slot" .. i
	b.Size = UDim2.fromOffset(64, 64)
	b.BackgroundColor3 = SLOT_DIM
	b.BackgroundTransparency = 0.25
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	b.Text = ""
	b.Font = Enum.Font.Code
	b.TextColor3 = Color3.fromRGB(210, 220, 230)
	b.TextSize = 12
	b.TextWrapped = true
	b.LayoutOrder = i
	b.Parent = holder
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = b
	local stroke = Instance.new("UIStroke")
	stroke.Color = STROKE_DIM
	stroke.Thickness = 1
	stroke.Parent = b

	-- slot number badge (top-left) so the 1-4 keybinds are discoverable
	local num = Instance.new("TextLabel")
	num.Name = "Num"
	num.AnchorPoint = Vector2.new(0, 0)
	num.Position = UDim2.fromOffset(4, 2)
	num.Size = UDim2.fromOffset(14, 14)
	num.BackgroundTransparency = 1
	num.Font = Enum.Font.GothamBold
	num.TextColor3 = Color3.fromRGB(120, 135, 150)
	num.TextSize = 12
	num.TextXAlignment = Enum.TextXAlignment.Left
	num.Text = tostring(i)
	num.Parent = b

	-- Tap/click: first selects, tapping the already-selected slot uses it (mobile
	-- friendly). Right-click drops.
	b.MouseButton1Click:Connect(function()
		if selectedSlot == i then
			useSelected()
		else
			setSelected(i)
		end
	end)
	b.MouseButton2Click:Connect(function()
		Net.Event("UseItem"):FireServer(i, "drop")
	end)
	slotButtons[i] = b
	slotStrokes[i] = stroke
end

-- "use selected" hint under the slots
local hint = Instance.new("TextLabel")
hint.Name = "UseHint"
hint.AnchorPoint = Vector2.new(0.5, 1)
hint.Position = UDim2.new(0.5, 0, 1, -136)
hint.Size = UDim2.fromOffset(360, 16)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.Code
hint.TextColor3 = Color3.fromRGB(150, 160, 170)
hint.TextSize = 13
hint.TextTransparency = 0.2
hint.Text = "1-4 select  ·  E use  ·  Q drop"
hint.Visible = false
hint.Parent = gui

-- Dedicated flashlight slot (sits just left of the 4 item slots) -------------
local FL_DIM = Color3.fromRGB(14, 16, 18)
local FL_LIT = Color3.fromRGB(40, 44, 50)
local FL_STROKE_DIM = Color3.fromRGB(60, 70, 80)
local FL_STROKE_LIT = Color3.fromRGB(240, 220, 120)

local flSlot = Instance.new("TextButton")
flSlot.Name = "FlashlightSlot"
flSlot.AnchorPoint = Vector2.new(0.5, 1)
-- 4 slots span 280px centered; offset this one to their left with an 8px gap.
flSlot.Position = UDim2.new(0.5, -(140 + 8 + 32), 1, -70)
flSlot.Size = UDim2.fromOffset(64, 64)
flSlot.BackgroundColor3 = FL_DIM
flSlot.BackgroundTransparency = 0.25
flSlot.BorderSizePixel = 0
flSlot.AutoButtonColor = false
flSlot.Text = ""
flSlot.Visible = false
flSlot.Parent = gui
local flCorner = Instance.new("UICorner")
flCorner.CornerRadius = UDim.new(0, 6)
flCorner.Parent = flSlot
local flStroke = Instance.new("UIStroke")
flStroke.Color = FL_STROKE_DIM
flStroke.Thickness = 1
flStroke.Parent = flSlot

-- "F" keybind badge (top-left), tinted differently from the numbered slots
local flBadge = Instance.new("TextLabel")
flBadge.Name = "Key"
flBadge.AnchorPoint = Vector2.new(0, 0)
flBadge.Position = UDim2.fromOffset(4, 2)
flBadge.Size = UDim2.fromOffset(14, 14)
flBadge.BackgroundTransparency = 1
flBadge.Font = Enum.Font.GothamBold
flBadge.TextColor3 = Color3.fromRGB(220, 200, 120)
flBadge.TextSize = 12
flBadge.TextXAlignment = Enum.TextXAlignment.Left
flBadge.Text = "F"
flBadge.Parent = flSlot

local flLabel = Instance.new("TextLabel")
flLabel.Name = "Label"
flLabel.AnchorPoint = Vector2.new(0.5, 0.5)
flLabel.Position = UDim2.new(0.5, 0, 0.5, -4)
flLabel.Size = UDim2.fromOffset(60, 32)
flLabel.BackgroundTransparency = 1
flLabel.Font = Enum.Font.Code
flLabel.TextColor3 = Color3.fromRGB(210, 220, 230)
flLabel.TextSize = 12
flLabel.TextWrapped = true
flLabel.Text = "Light"
flLabel.Parent = flSlot

-- battery bar along the bottom of the flashlight slot
local flBattBg = Instance.new("Frame")
flBattBg.Name = "BatteryBg"
flBattBg.AnchorPoint = Vector2.new(0.5, 1)
flBattBg.Position = UDim2.new(0.5, 0, 1, -5)
flBattBg.Size = UDim2.fromOffset(52, 6)
flBattBg.BackgroundColor3 = Color3.fromRGB(10, 12, 14)
flBattBg.BackgroundTransparency = 0.2
flBattBg.BorderSizePixel = 0
flBattBg.Parent = flSlot
local flBattCorner = Instance.new("UICorner"); flBattCorner.CornerRadius = UDim.new(0, 3); flBattCorner.Parent = flBattBg

local flBattFill = Instance.new("Frame")
flBattFill.Name = "Fill"
flBattFill.Size = UDim2.fromScale(1, 1)
flBattFill.BackgroundColor3 = Color3.fromRGB(240, 220, 120)
flBattFill.BorderSizePixel = 0
flBattFill.Parent = flBattBg
local flFillCorner = Instance.new("UICorner"); flFillCorner.CornerRadius = UDim.new(0, 3); flFillCorner.Parent = flBattFill

flSlot.MouseButton1Click:Connect(function()
	Net.Event("FlashlightToggle"):FireServer()
end)

-- Keyboard: 1-4 select, E uses the selected item, F toggles the torch. Ignored
-- while a modal menu owns input (UIModalOpen).
local KEY_TO_SLOT = {
	[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3, [Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.KeypadOne] = 1, [Enum.KeyCode.KeypadTwo] = 2, [Enum.KeyCode.KeypadThree] = 3, [Enum.KeyCode.KeypadFour] = 4,
}
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if player:GetAttribute("UIModalOpen") then return end
	if input.KeyCode == Enum.KeyCode.F then
		Net.Event("FlashlightToggle"):FireServer()
		return
	end
	if input.KeyCode == Enum.KeyCode.E then
		-- while hiding, E means "get out of the locker" (deterministic exit; the
		-- in-locker ProximityPrompt is unreliable once you're inside the part).
		if player:GetAttribute("Hiding") then
			Net.Event("ExitHide"):FireServer()
		else
			useSelected()
		end
		return
	end
	if input.KeyCode == Enum.KeyCode.Q then
		-- drop the selected item (right-click also drops, but the cursor is locked
		-- to center in first person, so a key is the reliable drop path).
		if selectedSlot and filled[selectedSlot] then
			Net.Event("UseItem"):FireServer(selectedSlot, "drop")
		end
		return
	end
	local slot = KEY_TO_SLOT[input.KeyCode]
	if slot then
		setSelected(slot)
	end
end)

Net.Event("InventoryUpdate").OnClientEvent:Connect(function(slots)
	local anyItem = false
	for i = 1, ItemData.MAX_SLOTS do
		local entry = slots[i]
		local b = slotButtons[i]
		filled[i] = entry ~= nil and entry ~= false
		if entry then
			anyItem = true
			b.Text = entry.name or entry.id
			b.BackgroundColor3 = SLOT_FILLED
		else
			b.Text = ""
			b.BackgroundColor3 = SLOT_DIM
		end
	end
	if selectedSlot and not filled[selectedSlot] then
		selectedSlot = nil
	end
	hint.Visible = anyItem
	refreshSelection()
end)

-- Flashlight slot: visible once owned; highlighted while on; battery bar fills. --
Net.Event("BatteryUpdate").OnClientEvent:Connect(function(charge, max, on, _flicker, hasLight, equipped)
	flSlot.Visible = hasLight == true
	if not hasLight then return end
	local frac = math.clamp(charge / math.max(max, 1), 0, 1)
	flBattFill.Size = UDim2.fromScale(frac, 1)
	flBattFill.BackgroundColor3 = (frac < 0.2) and Color3.fromRGB(220, 80, 40) or Color3.fromRGB(240, 220, 120)
	flBattFill.BackgroundTransparency = on and 0 or 0.5
	if equipped then
		flSlot.BackgroundColor3 = FL_LIT
		flStroke.Color = FL_STROKE_LIT
		flStroke.Thickness = 2
		flLabel.TextColor3 = Color3.fromRGB(245, 235, 200)
	else
		flSlot.BackgroundColor3 = FL_DIM
		flStroke.Color = FL_STROKE_DIM
		flStroke.Thickness = 1
		flLabel.TextColor3 = Color3.fromRGB(150, 160, 170)
	end
end)
