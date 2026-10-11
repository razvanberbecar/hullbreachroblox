--!strict
-- CameraController.client.lua  →  LocalScript in StarterPlayer/StarterPlayerScripts
-- =============================================================================
-- Locks the player to first person permanently. The GDD is explicit: first
-- person is essential, never allow third person. We force LockFirstPerson, and
-- re-assert it on respawn and on any attempt to zoom out.
-- =============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local player = Players.LocalPlayer

local function lockFirstPerson()
	if not GameConfig.ForceFirstPerson then return end
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	-- Prevent zoom-out entirely.
	player.CameraMinZoomDistance = 0.5
	player.CameraMaxZoomDistance = 0.5
end

lockFirstPerson()

-- Re-assert whenever the property is changed (e.g. by other systems or respawn).
player:GetPropertyChangedSignal("CameraMode"):Connect(function()
	if player.CameraMode ~= Enum.CameraMode.LockFirstPerson and GameConfig.ForceFirstPerson then
		lockFirstPerson()
	end
end)

player.CharacterAdded:Connect(function()
	task.wait(0.1)
	lockFirstPerson()
end)

-- Suit skins (paid cosmetic): recolor the diver's arms/hands to the equipped suit.
-- First-person shows mostly hands + lower arms; a Shirt texture can hide upper arms.
local Monetization = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MonetizationData"))
local ARM_PARTS = { "LeftHand", "RightHand", "LeftLowerArm", "RightLowerArm", "LeftUpperArm", "RightUpperArm", "Left Arm", "Right Arm" }
local function applySuit()
	local char = player.Character
	if not char then return end
	local skin = Monetization.SuitSkins[player:GetAttribute("SuitSkin") or "default"] or Monetization.SuitSkins.default
	if not skin then return end
	for _, name in ipairs(ARM_PARTS) do
		local p = char:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			if skin.color then p.Color = skin.color end
			if skin.material then p.Material = skin.material end
		end
	end
end
player:GetAttributeChangedSignal("SuitSkin"):Connect(applySuit)
player.CharacterAdded:Connect(function() task.wait(0.4); applySuit() end)
if player.Character then task.defer(applySuit) end
