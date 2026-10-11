--!strict
-- Reticle.client.lua  →  LocalScript in StarterPlayerScripts/Client
-- =============================================================================
-- First-person aiming reticle: a single point at screen center marking the
-- "point of action" (ProximityPrompts, looking). The OS mouse cursor is hidden
-- during play and restored automatically while the click-driven [L] menu is open.
-- =============================================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "DeepDescentReticle"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 5
gui.Parent = playerGui

-- single center dot — the "visible point"
local dot = Instance.new("Frame")
dot.Name = "Dot"
dot.AnchorPoint = Vector2.new(0.5, 0.5)
dot.Position = UDim2.fromScale(0.5, 0.5)
dot.Size = UDim2.fromOffset(5, 5)
dot.BackgroundColor3 = Color3.fromRGB(232, 237, 242)
dot.BackgroundTransparency = 0.05
dot.BorderSizePixel = 0
dot.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(1, 0)
corner.Parent = dot
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(0, 0, 0)
stroke.Transparency = 0.35
stroke.Thickness = 1
stroke.Parent = dot

-- ---------------------------------------------------------------------------
-- Cursor handling: hide the OS cursor during play; restore it while the
-- click-driven [L] menu is open so its buttons stay usable.
-- ---------------------------------------------------------------------------
local menuGui: ScreenGui? = nil

local function refresh()
	local menuOpen = menuGui ~= nil and menuGui.Enabled
	UserInputService.MouseIconEnabled = menuOpen
	gui.Enabled = not menuOpen
end

local function bindMenu(inst: Instance)
	if inst.Name == "DeepDescentMenu" and inst:IsA("ScreenGui") then
		menuGui = inst
		inst:GetPropertyChangedSignal("Enabled"):Connect(refresh)
		refresh()
	end
end

for _, child in ipairs(playerGui:GetChildren()) do
	bindMenu(child)
end
playerGui.ChildAdded:Connect(bindMenu)

refresh()
