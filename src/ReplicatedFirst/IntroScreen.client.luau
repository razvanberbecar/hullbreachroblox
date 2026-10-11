-- IntroScreen — join cover + story prologue, now gated by the main menu.
-- Handshake (player attributes set by MenuUI, all client-local):
--   DD_MenuReady   : menu built + camera parked -> fade the join-black out to reveal it
--   DD_PlayPrologue: player pressed Play       -> fade to black, play the 3 lines
--   DD_PrologueDone : set here when the lines finish -> MenuUI releases into gameplay
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

ReplicatedFirst:RemoveDefaultLoadingScreen()

local LINES = {
	"The boat went down under sealed orders, sent to bring something back from the deep. They succeeded.",
	"Whatever they raised did not want to be raised. It followed them down.",
	"You are the only one still breathing. It cannot see you — but it hears everything.",
}
local INITIAL_BLACK = 1.2
local FADE_IN, HOLD, HOLD_LAST, FADE_OUT, GAP = 1.0, 3.4, 4.2, 0.9, 0.35

local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "IntroScreen"
gui.IgnoreGuiInset = true
gui.DisplayOrder = 1000
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local bg = Instance.new("Frame")
bg.Size = UDim2.fromScale(1, 1)
bg.BackgroundColor3 = Color3.new(0, 0, 0)
bg.BorderSizePixel = 0
bg.Parent = gui

local line = Instance.new("TextLabel")
line.AnchorPoint = Vector2.new(0.5, 0.5)
line.Position = UDim2.fromScale(0.5, 0.5)
line.Size = UDim2.fromScale(0.78, 0.32)
line.BackgroundTransparency = 1
line.Font = Enum.Font.Merriweather
line.TextColor3 = Color3.fromRGB(224, 220, 210)
line.TextSize = 30
line.TextWrapped = true
line.TextTransparency = 1
line.Text = ""
line.Parent = bg

gui.Parent = player:WaitForChild("PlayerGui")

local function tween(obj, prop, target, dur)
	local from = obj[prop]
	local t0 = os.clock()
	while true do
		local a = math.min((os.clock() - t0) / dur, 1)
		obj[prop] = from + (target - from) * a
		if a >= 1 then break end
		RunService.RenderStepped:Wait()
	end
end

local function waitAttr(name, timeout)
	local t0 = os.clock()
	while player:GetAttribute(name) ~= true do
		if timeout and (os.clock() - t0) > timeout then return false end
		RunService.Heartbeat:Wait()
	end
	return true
end

-- 1) hold black over the join until the world + character are ready and the menu
--    has been built, then fade the black out to reveal the main menu.
if not game:IsLoaded() then game.Loaded:Wait() end
do
	local char = player.Character or player.CharacterAdded:Wait()
	if not char:FindFirstChild("HumanoidRootPart") then char:WaitForChild("HumanoidRootPart", 30) end
end
waitAttr("DD_MenuReady", 20)
for _ = 1, 3 do RunService.RenderStepped:Wait() end
tween(bg, "BackgroundTransparency", 1, 1.2)

-- 2) each time the player presses Play, fade to black and play the prologue; the
-- gui persists so a Main Menu -> Play again replays it.
while true do
	waitAttr("DD_PlayPrologue")
	tween(bg, "BackgroundTransparency", 0, 0.8)
	task.wait(INITIAL_BLACK)
	for i, text in ipairs(LINES) do
		line.Text = text
		tween(line, "TextTransparency", 0, FADE_IN)
		task.wait((i == #LINES) and HOLD_LAST or HOLD)
		tween(line, "TextTransparency", 1, FADE_OUT)
		task.wait(GAP)
	end
	player:SetAttribute("DD_PrologueDone", true)
	tween(bg, "BackgroundTransparency", 1, 1.6)
	while player:GetAttribute("DD_PlayPrologue") == true do RunService.Heartbeat:Wait() end
end
