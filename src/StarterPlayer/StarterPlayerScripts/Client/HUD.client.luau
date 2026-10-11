--!strict
-- HUD.client.lua  →  LocalScript in StarterPlayerScripts/Client
-- =============================================================================
-- Minimal HUD per the GDD: oxygen meter (only visible when in danger), and a
-- brief diegetic notification line for interactions/objectives. Flashlight
-- battery icon + 4-slot inventory arrive with their phases (6) and extend this.
-- Deliberately sparse — the less on screen, the more immersive.
-- =============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))

local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "DeepDescentHUD"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

-- Oxygen meter ---------------------------------------------------------------
local oxyHolder = Instance.new("Frame")
oxyHolder.Name = "OxygenMeter"
oxyHolder.AnchorPoint = Vector2.new(0.5, 1)
oxyHolder.Position = UDim2.new(0.5, 0, 1, -24)
oxyHolder.Size = UDim2.fromOffset(280, 14)
oxyHolder.BackgroundColor3 = Color3.fromRGB(10, 12, 14)
oxyHolder.BackgroundTransparency = 0.3
oxyHolder.BorderSizePixel = 0
oxyHolder.Visible = false
oxyHolder.Parent = gui
local oxyCorner = Instance.new("UICorner")
oxyCorner.CornerRadius = UDim.new(0, 4)
oxyCorner.Parent = oxyHolder

local oxyFill = Instance.new("Frame")
oxyFill.Name = "Fill"
oxyFill.Size = UDim2.fromScale(1, 1)
oxyFill.BackgroundColor3 = Color3.fromRGB(120, 200, 230)
oxyFill.BorderSizePixel = 0
oxyFill.Parent = oxyHolder
local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0, 4)
fillCorner.Parent = oxyFill

Net.Event("OxygenUpdate").OnClientEvent:Connect(function(current: number, max: number, danger: boolean)
	oxyHolder.Visible = danger
	if not danger then return end
	local frac = math.clamp(current / math.max(max, 1), 0, 1)
	oxyFill.Size = UDim2.fromScale(frac, 1)
	oxyFill.BackgroundColor3 = (frac < 0.34)
		and Color3.fromRGB(220, 50, 40)
		or Color3.fromRGB(120, 200, 230)
end)

-- Hint button (Hint dev product) -------------------------------------------
-- A constant, always-on-screen Hint during play. On PC the mouse is locked to the
-- camera (can't click UI), so it's ALSO bound to the H key; on touch you tap it.
-- Repeatable; greys out only when every captain's-log page has been found.
local hintUIS = game:GetService("UserInputService")
local hintLabel = hintUIS.KeyboardEnabled and "Hint   [H]" or "Hint"
local hintBtn = Instance.new("TextButton")
hintBtn.Name = "HintButton"
hintBtn.AnchorPoint = Vector2.new(1, 0)
hintBtn.Position = UDim2.new(1, -12, 0, 12)
hintBtn.Size = UDim2.fromOffset(132, 34)
hintBtn.BackgroundColor3 = Color3.fromRGB(22, 28, 34)
hintBtn.BackgroundTransparency = 0.15
hintBtn.BorderSizePixel = 0
hintBtn.AutoButtonColor = true
hintBtn.Font = Enum.Font.GothamMedium
hintBtn.TextSize = 15
hintBtn.TextColor3 = Color3.fromRGB(220, 228, 235)
hintBtn.Text = hintLabel
hintBtn.Visible = false
hintBtn.Parent = gui
local hbCorner = Instance.new("UICorner"); hbCorner.CornerRadius = UDim.new(0, 6); hbCorner.Parent = hintBtn
local function updateHint()
	if player:GetAttribute("InMenu") == true then
		hintBtn.Visible = false
		return
	end
	hintBtn.Visible = true
	local remaining = player:GetAttribute("JournalRemaining")
	if remaining ~= nil and remaining <= 0 then
		hintBtn.Text = "No pages left"
		hintBtn.Active = false
		hintBtn.AutoButtonColor = false
		hintBtn.TextColor3 = Color3.fromRGB(120, 130, 140)
		hintBtn.BackgroundTransparency = 0.6
	else
		hintBtn.Text = hintLabel
		hintBtn.Active = true
		hintBtn.AutoButtonColor = true
		hintBtn.TextColor3 = Color3.fromRGB(220, 228, 235)
		hintBtn.BackgroundTransparency = 0.15
	end
end
local function buyHint()
	if player:GetAttribute("InMenu") == true then return end
	local remaining = player:GetAttribute("JournalRemaining")
	if remaining ~= nil and remaining <= 0 then return end
	Net.Event("Purchase"):FireServer("product", "hint")
end
hintBtn.MouseButton1Click:Connect(buyHint)
hintUIS.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.H then buyHint() end
end)
player:GetAttributeChangedSignal("InMenu"):Connect(updateHint)
player:GetAttributeChangedSignal("JournalRemaining"):Connect(updateHint)
updateHint()

-- Notification line ----------------------------------------------------------
local notif = Instance.new("TextLabel")
notif.Name = "Notify"
notif.AnchorPoint = Vector2.new(0.5, 1)
notif.Position = UDim2.new(0.5, 0, 1, -48)
notif.Size = UDim2.fromOffset(700, 30)
notif.BackgroundTransparency = 1
notif.Font = Enum.Font.Code
notif.TextColor3 = Color3.fromRGB(210, 220, 230)
notif.TextStrokeTransparency = 0.5
notif.TextScaled = false
notif.TextSize = 18
notif.Text = ""
notif.TextTransparency = 1
notif.Parent = gui

local notifToken = 0
Net.Event("Notify").OnClientEvent:Connect(function(text: string)
	notif.Text = text
	notifToken += 1
	local myToken = notifToken

-- Journal reader ------------------------------------------------------------
-- A collected page is the game's main backstory delivery, so it gets a proper
-- readable "page" panel (worn paper, serif type) rather than the one-line notify.
-- Non-blocking; auto-fades after a read time scaled to its length, or is set
-- down early by any key / click / tap (after a short grace so a held movement
-- key can't snap it shut the instant it opens).
local UserInputService = game:GetService("UserInputService")

local jgui = Instance.new("ScreenGui")
jgui.Name = "DeepDescentJournal"
jgui.IgnoreGuiInset = true
jgui.ResetOnSpawn = false
jgui.DisplayOrder = 60
jgui.Parent = player:WaitForChild("PlayerGui")

local page = Instance.new("Frame")
page.Name = "Page"
page.AnchorPoint = Vector2.new(0.5, 0.5)
page.Position = UDim2.fromScale(0.5, 0.46)
page.Size = UDim2.fromOffset(660, 380)
page.BackgroundColor3 = Color3.fromRGB(18, 17, 14)
page.BackgroundTransparency = 1
page.BorderSizePixel = 0
page.Visible = false
page.Parent = jgui
local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 6); pc.Parent = page
local ps = Instance.new("UIStroke"); ps.Color = Color3.fromRGB(120, 105, 70); ps.Thickness = 1; ps.Transparency = 1; ps.Parent = page
local pp = Instance.new("UIPadding")
pp.PaddingLeft = UDim.new(0, 38); pp.PaddingRight = UDim.new(0, 38)
pp.PaddingTop = UDim.new(0, 30); pp.PaddingBottom = UDim.new(0, 30)
pp.Parent = page

local pageTitle = Instance.new("TextLabel")
pageTitle.AnchorPoint = Vector2.new(0.5, 0)
pageTitle.Position = UDim2.fromScale(0.5, 0)
pageTitle.Size = UDim2.new(1, 0, 0, 32)
pageTitle.BackgroundTransparency = 1
pageTitle.Font = Enum.Font.Merriweather
pageTitle.TextColor3 = Color3.fromRGB(228, 216, 186)
pageTitle.TextSize = 23
pageTitle.TextWrapped = true
pageTitle.TextTransparency = 1
pageTitle.Text = ""
pageTitle.Parent = page

local pageBody = Instance.new("TextLabel")
pageBody.AnchorPoint = Vector2.new(0.5, 0)
pageBody.Position = UDim2.new(0.5, 0, 0, 50)
pageBody.Size = UDim2.new(1, 0, 1, -86)
pageBody.BackgroundTransparency = 1
pageBody.Font = Enum.Font.Merriweather
pageBody.TextColor3 = Color3.fromRGB(206, 197, 178)
pageBody.TextSize = 18
pageBody.LineHeight = 1.25
pageBody.TextWrapped = true
pageBody.TextXAlignment = Enum.TextXAlignment.Left
pageBody.TextYAlignment = Enum.TextYAlignment.Top
pageBody.TextTransparency = 1
pageBody.Text = ""
pageBody.Parent = page

local pageHint = Instance.new("TextLabel")
pageHint.AnchorPoint = Vector2.new(0.5, 1)
pageHint.Position = UDim2.fromScale(0.5, 1)
pageHint.Size = UDim2.new(1, 0, 0, 18)
pageHint.BackgroundTransparency = 1
pageHint.Font = Enum.Font.Code
pageHint.TextColor3 = Color3.fromRGB(150, 140, 120)
pageHint.TextSize = 13
pageHint.TextTransparency = 1
pageHint.Text = "press any key to set it down"
pageHint.Parent = page

local pageToken = 0
local pageReadyAt = 0

local function fadePage(bg: number, txt: number, dur: number)
	TweenService:Create(page, TweenInfo.new(dur), { BackgroundTransparency = bg }):Play()
	TweenService:Create(ps, TweenInfo.new(dur), { Transparency = txt }):Play()
	TweenService:Create(pageTitle, TweenInfo.new(dur), { TextTransparency = txt }):Play()
	TweenService:Create(pageBody, TweenInfo.new(dur), { TextTransparency = txt }):Play()
	TweenService:Create(pageHint, TweenInfo.new(dur), { TextTransparency = math.min(txt + 0.35, 1) }):Play()
end

local function hidePage(token: number)
	if token ~= pageToken then return end
	fadePage(1, 1, 0.6)
	task.delay(0.6, function()
		if token == pageToken then page.Visible = false end
	end)
end

Net.Event("JournalRead").OnClientEvent:Connect(function(info)
	if type(info) ~= "table" then return end
	pageToken += 1
	local myToken = pageToken
	pageTitle.Text = tostring(info.title or "Captain's Log")
	pageBody.Text = tostring(info.text or "")
	page.BackgroundTransparency = 1
	ps.Transparency = 1
	pageTitle.TextTransparency = 1
	pageBody.TextTransparency = 1
	pageHint.TextTransparency = 1
	page.Visible = true
	fadePage(0.1, 0, 0.5)
	pageReadyAt = os.clock() + 1.2
	local _, words = (pageBody.Text):gsub("%S+", "")
	local readTime = math.clamp(4 + words * 0.32, 7, 16)
	task.delay(readTime, function() hidePage(myToken) end)
end)

UserInputService.InputBegan:Connect(function(input)
	if not page.Visible or os.clock() < pageReadyAt then return end
	local t = input.UserInputType
	if t == Enum.UserInputType.Keyboard
		or t == Enum.UserInputType.MouseButton1
		or t == Enum.UserInputType.Touch then
		hidePage(pageToken)
	end
end)
	notif.TextTransparency = 0
	TweenService:Create(notif, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
	task.delay(4, function()
		if notifToken == myToken then
			TweenService:Create(notif, TweenInfo.new(1), { TextTransparency = 1 }):Play()
		end
	end)
end)

-- Hint direction banner -----------------------------------------------------
-- When the player buys a Hint, this names the room the next captain's-log page
-- is in and sits just above the 4-slot item toolbar for a few seconds. Pairs
-- with the world beacon (which shows exactly where) as a plain "which room" cue.
local hintBanner = Instance.new("TextLabel")
hintBanner.Name = "HintDirection"
hintBanner.AnchorPoint = Vector2.new(0.5, 1)
hintBanner.Position = UDim2.new(0.5, 0, 1, -146) -- above the toolbar (slots sit at 1,-70..-134)
hintBanner.Size = UDim2.fromOffset(0, 30)
hintBanner.AutomaticSize = Enum.AutomaticSize.X    -- bubble hugs the text
hintBanner.BackgroundColor3 = Color3.fromRGB(22, 28, 34)
hintBanner.BackgroundTransparency = 1
hintBanner.BorderSizePixel = 0
hintBanner.Font = Enum.Font.GothamMedium
hintBanner.TextSize = 16
hintBanner.TextColor3 = Color3.fromRGB(240, 226, 180)
hintBanner.TextTransparency = 1
hintBanner.Text = ""
hintBanner.Parent = gui
local hbBannerCorner = Instance.new("UICorner"); hbBannerCorner.CornerRadius = UDim.new(0, 6); hbBannerCorner.Parent = hintBanner
local hbBannerPad = Instance.new("UIPadding")
hbBannerPad.PaddingLeft = UDim.new(0, 14); hbBannerPad.PaddingRight = UDim.new(0, 14)
hbBannerPad.PaddingTop = UDim.new(0, 5); hbBannerPad.PaddingBottom = UDim.new(0, 5)
hbBannerPad.Parent = hintBanner

local hintDirToken = 0
local function hideHintBanner()
	hintDirToken += 1
	hintBanner.TextTransparency = 1
	hintBanner.BackgroundTransparency = 1
end
Net.Event("HintDirection").OnClientEvent:Connect(function(roomName: string)
	hintBanner.Text = ("Go to the %s \u{2014} the next log page is there."):format(tostring(roomName))
	hintDirToken += 1
	local myToken = hintDirToken
	TweenService:Create(hintBanner, TweenInfo.new(0.3), { TextTransparency = 0, BackgroundTransparency = 0.2 }):Play()
	task.delay(8, function()
		if hintDirToken == myToken then
			TweenService:Create(hintBanner, TweenInfo.new(1), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		end
	end)
end)
-- Clear it instantly if the player drops back to the main menu.
player:GetAttributeChangedSignal("InMenu"):Connect(function()
	if player:GetAttribute("InMenu") == true then hideHintBanner() end
end)
