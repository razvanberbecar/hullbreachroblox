--!strict
-- EndingClient.client.lua  →  LocalScript in StarterPlayerScripts/Client
-- =============================================================================
-- Phase 7 (client): ending cutscenes (fade to black + title card + blurb), the
-- ballast valve-sequence puzzle keypad, and the SOS survival countdown. Kept on
-- one ScreenGui so these full-screen takeovers never fight each other.
-- =============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Monetization = require(Shared:WaitForChild("MonetizationData"))

local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "DeepDescentEndings"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 50
gui.Parent = player:WaitForChild("PlayerGui")

-- ---------------------------------------------------------------------------
-- Cutscene
-- ---------------------------------------------------------------------------
local black = Instance.new("Frame")
black.Size = UDim2.fromScale(1, 1)
black.BackgroundColor3 = Color3.new(0, 0, 0)
black.BackgroundTransparency = 1
black.Visible = false
black.ZIndex = 10
black.Parent = gui

local title = Instance.new("TextLabel")
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.new(0.5, 0, 0.42, 0)
title.Size = UDim2.fromScale(0.8, 0.2)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBlack
title.TextColor3 = Color3.fromRGB(220, 225, 230)
title.TextScaled = true
title.TextTransparency = 1
title.Text = ""
title.ZIndex = 11
title.Parent = gui

local blurb = Instance.new("TextLabel")
blurb.AnchorPoint = Vector2.new(0.5, 0.5)
blurb.Position = UDim2.new(0.5, 0, 0.58, 0)
blurb.Size = UDim2.fromScale(0.6, 0.18)
blurb.BackgroundTransparency = 1
blurb.Font = Enum.Font.Code
blurb.TextColor3 = Color3.fromRGB(170, 180, 190)
blurb.TextWrapped = true
blurb.TextSize = 20
blurb.TextTransparency = 1
blurb.Text = ""
blurb.ZIndex = 11
blurb.Parent = gui

-- Try Again / Play Again button shown at the end of the cutscene; restarts the run.
local restartBtn = Instance.new("TextButton")
restartBtn.AnchorPoint = Vector2.new(0.5, 0.5)
restartBtn.Position = UDim2.fromScale(0.5, 0.70)
restartBtn.Size = UDim2.fromOffset(240, 56)
restartBtn.BackgroundColor3 = Color3.fromRGB(28, 36, 44)
restartBtn.AutoButtonColor = true
restartBtn.Font = Enum.Font.GothamBold
restartBtn.TextColor3 = Color3.fromRGB(225, 230, 235)
restartBtn.TextSize = 22
restartBtn.Text = "TRY AGAIN"
restartBtn.TextTransparency = 1
restartBtn.BackgroundTransparency = 1
restartBtn.Visible = false
restartBtn.ZIndex = 12
restartBtn.Parent = gui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = restartBtn
	local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(90, 100, 110); s.Thickness = 1; s.Parent = restartBtn
end

-- first person locks the mouse to centre; free it so the button is clickable.
local RESTART_CURSOR = "DD_RestartCursor"
local function freeCursor(on: boolean)
	if on then
		UserInputService.MouseIconEnabled = true
		RunService:BindToRenderStep(RESTART_CURSOR, Enum.RenderPriority.Camera.Value + 1, function()
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end)
	else
		pcall(function() RunService:UnbindFromRenderStep(RESTART_CURSOR) end)
		UserInputService.MouseIconEnabled = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end
end

local restarting = false
-- Forward-declared so the Try Again handler below can also fade/hide it (it is
-- created further down, after this handler). Assigned at the menuBtn block.
local menuBtn: TextButton
-- Developer Commentary: request a dev to rate how you solved the map (good endings only).
local lastInfo = nil
local rateSent = false
local ownsCommentary = false
local rateBtn = Instance.new("TextButton")
rateBtn.AnchorPoint = Vector2.new(0.5, 0.5)
rateBtn.Position = UDim2.fromScale(0.5, 0.85)
rateBtn.Size = UDim2.fromOffset(340, 40)
rateBtn.BackgroundColor3 = Color3.fromRGB(24, 30, 26)
rateBtn.Font = Enum.Font.GothamMedium
rateBtn.TextColor3 = Color3.fromRGB(190, 220, 200)
rateBtn.TextSize = 16
rateBtn.Text = "ASK FOR DEVELOPER COMMENTARY"
rateBtn.TextTransparency = 1
rateBtn.BackgroundTransparency = 1
rateBtn.Visible = false
rateBtn.ZIndex = 12
rateBtn.Parent = gui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = rateBtn
	local st = Instance.new("UIStroke"); st.Color = Color3.fromRGB(70, 100, 80); st.Thickness = 1; st.Parent = rateBtn
end
-- ---- Developer Commentary modal: optional notes -> submit -> Discord invite ----
local commentaryCatcher = Instance.new("TextButton")
commentaryCatcher.Name = "CommentaryDismiss"; commentaryCatcher.Size = UDim2.fromScale(1, 1)
commentaryCatcher.BackgroundColor3 = Color3.new(0, 0, 0); commentaryCatcher.BackgroundTransparency = 0.4
commentaryCatcher.Text = ""; commentaryCatcher.AutoButtonColor = false
commentaryCatcher.Visible = false; commentaryCatcher.ZIndex = 25; commentaryCatcher.Parent = gui

local commentaryPanel = Instance.new("Frame")
commentaryPanel.AnchorPoint = Vector2.new(0.5, 0.5); commentaryPanel.Position = UDim2.fromScale(0.5, 0.5)
commentaryPanel.Size = UDim2.fromOffset(440, 300); commentaryPanel.BackgroundColor3 = Color3.fromRGB(18, 22, 28)
commentaryPanel.BackgroundTransparency = 0.05; commentaryPanel.Visible = false
commentaryPanel.ZIndex = 26; commentaryPanel.Parent = gui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = commentaryPanel
	local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(70, 100, 80); s.Thickness = 1; s.Parent = commentaryPanel
end

local cTitle = Instance.new("TextLabel")
cTitle.Position = UDim2.fromOffset(18, 14); cTitle.Size = UDim2.new(1, -60, 0, 26)
cTitle.BackgroundTransparency = 1; cTitle.Font = Enum.Font.GothamBold
cTitle.TextColor3 = Color3.fromRGB(200, 225, 210); cTitle.TextSize = 20
cTitle.TextXAlignment = Enum.TextXAlignment.Left; cTitle.Text = "DEVELOPER COMMENTARY"
cTitle.ZIndex = 27; cTitle.Parent = commentaryPanel

local cClose = Instance.new("TextButton")
cClose.AnchorPoint = Vector2.new(1, 0); cClose.Position = UDim2.new(1, -10, 0, 10)
cClose.Size = UDim2.fromOffset(28, 28); cClose.BackgroundColor3 = Color3.fromRGB(60, 46, 46)
cClose.Font = Enum.Font.GothamBold; cClose.TextColor3 = Color3.fromRGB(235, 225, 225)
cClose.TextSize = 16; cClose.Text = "X"; cClose.ZIndex = 27; cClose.Parent = commentaryPanel
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = cClose end

local cDesc = Instance.new("TextLabel")
cDesc.Position = UDim2.fromOffset(18, 46); cDesc.Size = UDim2.new(1, -36, 0, 40)
cDesc.BackgroundTransparency = 1; cDesc.Font = Enum.Font.Gotham
cDesc.TextColor3 = Color3.fromRGB(180, 190, 200); cDesc.TextSize = 14; cDesc.TextWrapped = true
cDesc.TextXAlignment = Enum.TextXAlignment.Left; cDesc.TextYAlignment = Enum.TextYAlignment.Top
cDesc.Text = "Ask a developer to rate how you solved this run. Add notes below, or just send — your run details are attached automatically."
cDesc.ZIndex = 27; cDesc.Parent = commentaryPanel

local cBox = Instance.new("TextBox")
cBox.Position = UDim2.fromOffset(18, 92); cBox.Size = UDim2.fromOffset(404, 132)
cBox.BackgroundColor3 = Color3.fromRGB(10, 13, 17); cBox.BackgroundTransparency = 0.1
cBox.Font = Enum.Font.Gotham; cBox.TextColor3 = Color3.fromRGB(225, 230, 235); cBox.TextSize = 15
cBox.TextXAlignment = Enum.TextXAlignment.Left; cBox.TextYAlignment = Enum.TextYAlignment.Top
cBox.MultiLine = true; cBox.ClearTextOnFocus = false; cBox.TextWrapped = true
cBox.PlaceholderText = "Add notes about your run… (optional)"; cBox.Text = ""
cBox.ZIndex = 27; cBox.Parent = commentaryPanel
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = cBox
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8); pad.PaddingRight = UDim.new(0, 8); pad.PaddingTop = UDim.new(0, 6); pad.Parent = cBox
end

local cSend = Instance.new("TextButton")
cSend.AnchorPoint = Vector2.new(1, 1); cSend.Position = UDim2.new(1, -18, 1, -16)
cSend.Size = UDim2.fromOffset(150, 40); cSend.BackgroundColor3 = Color3.fromRGB(30, 60, 40)
cSend.Font = Enum.Font.GothamBold; cSend.TextColor3 = Color3.fromRGB(210, 235, 215); cSend.TextSize = 16
cSend.Text = "SEND"; cSend.ZIndex = 27; cSend.Parent = commentaryPanel
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = cSend end

local cSent = Instance.new("TextLabel")
cSent.Position = UDim2.fromOffset(18, 52); cSent.Size = UDim2.new(1, -36, 0, 74)
cSent.BackgroundTransparency = 1; cSent.Font = Enum.Font.Gotham
cSent.TextColor3 = Color3.fromRGB(200, 225, 205); cSent.TextSize = 16; cSent.TextWrapped = true
cSent.TextXAlignment = Enum.TextXAlignment.Left; cSent.TextYAlignment = Enum.TextYAlignment.Top
cSent.Text = ""; cSent.Visible = false; cSent.ZIndex = 27; cSent.Parent = commentaryPanel

local cInvite = Instance.new("TextBox")
cInvite.Position = UDim2.fromOffset(18, 134); cInvite.Size = UDim2.fromOffset(404, 40)
cInvite.BackgroundColor3 = Color3.fromRGB(10, 13, 17); cInvite.BackgroundTransparency = 0.1
cInvite.Font = Enum.Font.Code; cInvite.TextColor3 = Color3.fromRGB(150, 200, 230); cInvite.TextSize = 16
cInvite.Text = ""; cInvite.ClearTextOnFocus = false; cInvite.Visible = false
cInvite.ZIndex = 27; cInvite.Parent = commentaryPanel
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = cInvite end
cInvite.FocusLost:Connect(function() cInvite.Text = Monetization.DiscordInvite end)

local function showCommentary(open)
	commentaryPanel.Visible = open
	commentaryCatcher.Visible = open
end
local function openCommentary()
	rateSent = false
	cDesc.Visible = true; cBox.Visible = true; cSend.Visible = true
	cBox.Text = ""; cSend.Text = "SEND"; cSend.AutoButtonColor = true
	cSent.Visible = false; cInvite.Visible = false
	showCommentary(true)
end
local function sendCommentary()
	if rateSent then return end
	rateSent = true
	cSend.AutoButtonColor = false; cSend.Text = "SENT"
	Net.Event("SubmitRun"):FireServer({
		ending = lastInfo and (lastInfo.name or lastInfo.title) or "unknown",
		category = lastInfo and lastInfo.category or "unknown",
		notes = cBox.Text,
	})
	cDesc.Visible = false; cBox.Visible = false; cSend.Visible = false
	local invite = Monetization.DiscordInvite
	if type(invite) == "string" and invite ~= "" then
		cSent.Text = "Sent for review — thank you.\nFind the developer's reply in our Discord:"
		cInvite.Text = invite; cInvite.Visible = true
	else
		cSent.Text = "Sent for review — thank you.\nWatch our community for the developer's reply."
	end
	cSent.Visible = true
end
cClose.MouseButton1Click:Connect(function() showCommentary(false) end)
commentaryCatcher.MouseButton1Click:Connect(function() showCommentary(false) end)
cSend.MouseButton1Click:Connect(sendCommentary)

rateBtn.MouseButton1Click:Connect(function()
	if ownsCommentary then
		openCommentary()
	else
		Net.Event("Purchase"):FireServer("pass", "commentary")   -- upsell; panel opens on purchase-finished
	end
end)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(_plr, passId, purchased)
	local com = Monetization.Passes.commentary
	if purchased and com and passId == com.id then
		ownsCommentary = true
		if rateBtn.Visible then openCommentary() end
	end
end)

restartBtn.MouseButton1Click:Connect(function()
	if restarting then return end
	restarting = true
	Net.Event("RequestRestart"):FireServer()
	freeCursor(false)
	TweenService:Create(restartBtn, TweenInfo.new(0.4), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
	TweenService:Create(menuBtn, TweenInfo.new(0.4), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
	TweenService:Create(title, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
	TweenService:Create(blurb, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
	rateBtn.Visible = false
	task.wait(1.8)   -- let the server rebuild + respawn us behind the black
	restartBtn.Visible = false
	menuBtn.Visible = false
	TweenService:Create(black, TweenInfo.new(1.2), { BackgroundTransparency = 1 }):Play()
	task.wait(1.2)
	black.Visible = false
	restarting = false
end)

-- Main Menu button, shown beneath Try Again on the ending screen.
menuBtn = Instance.new("TextButton")
menuBtn.AnchorPoint = Vector2.new(0.5, 0.5)
menuBtn.Position = UDim2.fromScale(0.5, 0.78)
menuBtn.Size = UDim2.fromOffset(240, 44)
menuBtn.BackgroundColor3 = Color3.fromRGB(20, 24, 30)
menuBtn.AutoButtonColor = true
menuBtn.Font = Enum.Font.GothamMedium
menuBtn.TextColor3 = Color3.fromRGB(200, 208, 216)
menuBtn.TextSize = 18
menuBtn.Text = "MAIN MENU"
menuBtn.TextTransparency = 1
menuBtn.BackgroundTransparency = 1
menuBtn.Visible = false
menuBtn.ZIndex = 12
menuBtn.Parent = gui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = menuBtn
	local st = Instance.new("UIStroke"); st.Color = Color3.fromRGB(70, 80, 90); st.Thickness = 1; st.Parent = menuBtn
end
local goingMenu = false
menuBtn.MouseButton1Click:Connect(function()
	if goingMenu or restarting then return end
	goingMenu = true
	Net.Event("ReturnToMenu"):FireServer()
	freeCursor(false)
	TweenService:Create(menuBtn, TweenInfo.new(0.4), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
	TweenService:Create(restartBtn, TweenInfo.new(0.4), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
	TweenService:Create(title, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
	TweenService:Create(blurb, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
	rateBtn.Visible = false
	task.wait(1.2)
	restartBtn.Visible = false
	menuBtn.Visible = false
	TweenService:Create(black, TweenInfo.new(1.2), { BackgroundTransparency = 1 }):Play()
	task.wait(1.2)
	black.Visible = false
	goingMenu = false
end)

local function playCutscene(info)
	lastInfo = info
	rateSent = false
	rateBtn.Visible = false
	black.Visible = true
	title.Text = info.title or ""
	blurb.Text = info.blurb or ""
	local tint = (info.category == "good") and Color3.fromRGB(8, 12, 16) or Color3.new(0, 0, 0)
	black.BackgroundColor3 = tint

	if info.id == "taken" and player:GetAttribute("DeathAnim") == "dragged" then
		-- "Dragged Under" (paid): red flash + violent shake, then hard black.
		black.Size = UDim2.new(1, 80, 1, 80); black.Position = UDim2.fromOffset(-40, -40)
		black.BackgroundColor3 = Color3.fromRGB(70, 0, 0)
		for i = 1, 12 do
			black.Position = UDim2.fromOffset(-40 + math.random(-16, 16), -40 + math.random(-8, 28))
			black.BackgroundTransparency = math.max(0, 0.4 - i * 0.035)
			task.wait(0.03)
		end
		black.Size = UDim2.fromScale(1, 1); black.Position = UDim2.fromScale(0, 0)
		black.BackgroundColor3 = Color3.new(0, 0, 0); black.BackgroundTransparency = 0
	else
		TweenService:Create(black, TweenInfo.new(1.2), { BackgroundTransparency = 0 }):Play()
		task.wait(1.2)
	end
	TweenService:Create(title, TweenInfo.new(1.4), { TextTransparency = 0 }):Play()
	task.wait(1.0)
	TweenService:Create(blurb, TweenInfo.new(1.6), { TextTransparency = 0 }):Play()
	task.wait(2.5)
	-- Instead of auto-respawning, hold the screen and offer Try Again / Play Again.
	restarting = false
	restartBtn.Text = (info.category == "good") and "PLAY AGAIN" or "TRY AGAIN"
	restartBtn.Visible = true
	menuBtn.Visible = true
	goingMenu = false
	freeCursor(true)
	TweenService:Create(restartBtn, TweenInfo.new(1.0), { TextTransparency = 0, BackgroundTransparency = 0.05 }):Play()
	TweenService:Create(menuBtn, TweenInfo.new(1.0), { TextTransparency = 0, BackgroundTransparency = 0.05 }):Play()
	do
		-- "Ask for Developer Commentary" shows on EVERY ending (win or lose). Owners
		-- open the notes panel; non-owners are prompted to buy the pass (upsell).
		ownsCommentary = (function()
			local ok, stt = pcall(function() return Net.Func("GetGameState"):InvokeServer() end)
			return ok and stt ~= nil and stt.passes ~= nil and stt.passes.commentary == true
		end)()
		rateBtn.Text = "ASK FOR DEVELOPER COMMENTARY"; rateBtn.AutoButtonColor = true; rateBtn.Visible = true
		TweenService:Create(rateBtn, TweenInfo.new(1.0), { TextTransparency = 0, BackgroundTransparency = 0.05 }):Play()
	end
end

Net.Event("EndingTrigger").OnClientEvent:Connect(function(info)
	task.spawn(playCutscene, info)
end)

-- legacy/death fallback before EndingManager hands a full payload
Net.Event("PlayerDied").OnClientEvent:Connect(function(endingId)
	playCutscene({ title = "...", blurb = "The dark takes you.", category = "bad" })
end)

-- Co-op shared reset: the OTHER player clicked Try Again / Main Menu, so the
-- server rebuilt the run. Dismiss our ending screen too. If WE clicked, our own
-- button handler is already running the fade (restarting/goingMenu), so ignore.
Net.Event("RunReset").OnClientEvent:Connect(function(_info)
	if restarting or goingMenu then return end
	if not black.Visible and not restartBtn.Visible then return end  -- no ending screen up
	restarting = true  -- reuse the guard so our button handlers stay inert during the fade
	freeCursor(false)
	rateBtn.Visible = false
	showCommentary(false)
	TweenService:Create(restartBtn, TweenInfo.new(0.4), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
	TweenService:Create(menuBtn, TweenInfo.new(0.4), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
	TweenService:Create(title, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
	TweenService:Create(blurb, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
	task.wait(0.6)
	restartBtn.Visible = false
	menuBtn.Visible = false
	TweenService:Create(black, TweenInfo.new(1.0), { BackgroundTransparency = 1 }):Play()
	task.wait(1.0)
	black.Visible = false
	restarting = false
end)

-- ---------------------------------------------------------------------------
-- SOS survival countdown
-- ---------------------------------------------------------------------------
local timer = Instance.new("TextLabel")
timer.AnchorPoint = Vector2.new(0.5, 0)
timer.Position = UDim2.new(0.5, 0, 0, 16)
timer.Size = UDim2.fromOffset(160, 28)
timer.BackgroundTransparency = 1
timer.Font = Enum.Font.Code
timer.TextColor3 = Color3.fromRGB(220, 120, 110)
timer.TextStrokeTransparency = 0.4
timer.TextSize = 22
timer.Visible = false
timer.Parent = gui

Net.Event("SurvivalUpdate").OnClientEvent:Connect(function(remaining: number)
	timer.Visible = remaining > 0
	local m = math.floor(remaining / 60)
	local s = remaining % 60
	timer.Text = ("RESCUE  %d:%02d"):format(m, s)
end)

-- ---------------------------------------------------------------------------
-- Ballast valve-sequence puzzle
-- ---------------------------------------------------------------------------
-- Full-screen click-catcher behind the panel. Clicking outside dismisses it.
local ballastCatcher = Instance.new("TextButton")
ballastCatcher.Name = "BallastDismiss"
ballastCatcher.Size = UDim2.fromScale(1, 1)
ballastCatcher.BackgroundColor3 = Color3.new(0, 0, 0)
ballastCatcher.BackgroundTransparency = 0.45
ballastCatcher.Text = ""
ballastCatcher.AutoButtonColor = false
ballastCatcher.Visible = false
ballastCatcher.ZIndex = 19
ballastCatcher.Parent = gui

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(360, 190)
panel.BackgroundColor3 = Color3.fromRGB(18, 22, 26)
panel.BackgroundTransparency = 0.1
panel.Visible = false
panel.ZIndex = 20
panel.Parent = gui
local pcorner = Instance.new("UICorner"); pcorner.CornerRadius = UDim.new(0, 8); pcorner.Parent = panel

local pTitle = Instance.new("TextLabel")
pTitle.Size = UDim2.new(1, 0, 0, 34)
pTitle.BackgroundTransparency = 1
pTitle.Font = Enum.Font.Code
pTitle.TextColor3 = Color3.fromRGB(210, 220, 230)
pTitle.TextSize = 18
pTitle.Text = "BALLAST VALVE SEQUENCE"
pTitle.ZIndex = 21
pTitle.Parent = panel

local pHint = Instance.new("TextLabel")
pHint.Position = UDim2.new(0, 0, 0, 34)
pHint.Size = UDim2.new(1, 0, 0, 20)
pHint.BackgroundTransparency = 1
pHint.Font = Enum.Font.Code
pHint.TextColor3 = Color3.fromRGB(150, 160, 170)
pHint.TextSize = 13
pHint.Text = "press the valves in order  ·  keys 1-5 or click  ·  Esc to close"
pHint.ZIndex = 21
pHint.Parent = panel

-- X close button (top-right)
local closeBtn = Instance.new("TextButton")
closeBtn.Name = "Close"
closeBtn.AnchorPoint = Vector2.new(1, 0)
closeBtn.Position = UDim2.new(1, -6, 0, 6)
closeBtn.Size = UDim2.fromOffset(26, 26)
closeBtn.BackgroundColor3 = Color3.fromRGB(120, 40, 36)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextColor3 = Color3.fromRGB(240, 235, 235)
closeBtn.TextSize = 18
closeBtn.Text = "X"
closeBtn.ZIndex = 22
closeBtn.Parent = panel
local ccorner = Instance.new("UICorner"); ccorner.CornerRadius = UDim.new(0, 6); ccorner.Parent = closeBtn

local row = Instance.new("Frame")
row.AnchorPoint = Vector2.new(0.5, 1)
row.Position = UDim2.new(0.5, 0, 1, -20)
row.Size = UDim2.fromOffset(320, 70)
row.BackgroundTransparency = 1
row.ZIndex = 21
row.Parent = panel
local rl = Instance.new("UIListLayout")
rl.FillDirection = Enum.FillDirection.Horizontal
rl.Padding = UDim.new(0, 10)
rl.HorizontalAlignment = Enum.HorizontalAlignment.Center
rl.Parent = row

local valveButtons = {}
for n = 1, 5 do
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(52, 52)
	b.BackgroundColor3 = Color3.fromRGB(40, 50, 60)
	b.Font = Enum.Font.GothamBold
	b.TextColor3 = Color3.fromRGB(230, 235, 240)
	b.TextSize = 24
	b.Text = tostring(n)
	b.LayoutOrder = n
	b.ZIndex = 22
	b.Parent = row
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = b
	valveButtons[n] = b
	b.MouseButton1Click:Connect(function()
		Net.Event("BallastInput"):FireServer(n)
	end)
end

local VALVE_IDLE = Color3.fromRGB(40, 50, 60)
-- Neutral press feedback (NOT green) so a wrong press never looks "accepted".
local function flashValve(n: number, color: Color3?)
	local b = valveButtons[n]
	if not b then return end
	b.BackgroundColor3 = color or Color3.fromRGB(70, 90, 105)
	task.delay(0.14, function() b.BackgroundColor3 = VALVE_IDLE end)
end
local function flashAllWrong()
	for i = 1, 5 do flashValve(i, Color3.fromRGB(150, 60, 55)) end
end

-- Show/hide. The first-person camera locks the mouse to the centre, so while the
-- panel is open we force the cursor free every frame (so the valves, X and the
-- outside-click all work) and flag UIModalOpen so the inventory hotbar ignores
-- keys (no double switching items + entering the combination).
local CURSOR_BIND = "DD_BallastCursor"
local function setBallastOpen(open: boolean)
	panel.Visible = open
	ballastCatcher.Visible = open
	player:SetAttribute("UIModalOpen", open)
	if open then
		UserInputService.MouseIconEnabled = true
		RunService:BindToRenderStep(CURSOR_BIND, Enum.RenderPriority.Camera.Value + 1, function()
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end)
	else
		pcall(function() RunService:UnbindFromRenderStep(CURSOR_BIND) end)
		UserInputService.MouseIconEnabled = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end
end

closeBtn.MouseButton1Click:Connect(function() setBallastOpen(false) end)
ballastCatcher.MouseButton1Click:Connect(function() setBallastOpen(false) end)

-- Keyboard entry: 1-5 feed the sequence, Esc closes. Only while the panel is up.

-- ---------------------------------------------------------------------------
-- Reset Character button -> full game restart (same as losing)
-- ---------------------------------------------------------------------------
-- Intercept the in-experience Reset so it no longer just kills + respawns the
-- character (which kept the inventory and the explored world). Instead it fires
-- the same full restart as "Try Again": the server rebuilds the world, clears
-- the inventory + flashlight, and respawns the player at the start.
local StarterGui = game:GetService("StarterGui")
local resetEvent = Instance.new("BindableEvent")
local resetBusy = false
resetEvent.Event:Connect(function()
	if resetBusy then return end
	resetBusy = true
	-- quick fade to black while the server restores the world + respawns us
	black.BackgroundColor3 = Color3.new(0, 0, 0)
	black.BackgroundTransparency = 1
	black.Visible = true
	TweenService:Create(black, TweenInfo.new(0.4), { BackgroundTransparency = 0 }):Play()
	Net.Event("RequestResetRun"):FireServer()
	task.wait(1.8)
	TweenService:Create(black, TweenInfo.new(1.0), { BackgroundTransparency = 1 }):Play()
	task.wait(1.0)
	black.Visible = false
	resetBusy = false
end)

-- Install the custom reset callback (CoreGui can reject it early; retry briefly).
task.spawn(function()
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCore("ResetButtonCallback", resetEvent)
		end)
		if ok then break end
		task.wait(0.5)
	end
end)
local VALVE_KEYS = {
	[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.KeypadOne] = 1, [Enum.KeyCode.KeypadTwo] = 2, [Enum.KeyCode.KeypadThree] = 3,
	[Enum.KeyCode.KeypadFour] = 4, [Enum.KeyCode.KeypadFive] = 5,
}
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not panel.Visible then return end
	if input.KeyCode == Enum.KeyCode.Escape then
		setBallastOpen(false)
		return
	end
	local n = VALVE_KEYS[input.KeyCode]
	if n then
		flashValve(n)
		Net.Event("BallastInput"):FireServer(n)
	end
end)

Net.Event("BallastPuzzle").OnClientEvent:Connect(function(info)
	setBallastOpen(info.open == true)
	if info.reset then
		flashAllWrong()
		pTitle.Text = "WRONG — SEQUENCE RESET"
		task.delay(1.2, function() pTitle.Text = "BALLAST VALVE SEQUENCE" end)
	end
end)
