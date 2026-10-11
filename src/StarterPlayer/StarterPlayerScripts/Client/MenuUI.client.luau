--!strict
-- MenuUI.client.lua → LocalScript in StarterPlayerScripts/Client
-- GDD 7.4 main menu: an exterior-submarine backdrop with Play / Endings Log /
-- Settings / Credits, shown until the player presses Play (the run is server-
-- gated by the per-player InMenu attribute, begun fresh on StartRun). Also the
-- in-game [L] records/shop overlay during play. Settings (volume / sensitivity /
-- brightness) apply live and persist via the SaveSettings remote.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local MarketplaceService = game:GetService("MarketplaceService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EndingData = require(Shared:WaitForChild("EndingData"))
local Monetization = require(Shared:WaitForChild("MonetizationData"))
local SoundData = require(Shared:WaitForChild("SoundData"))
local Net = require(Shared:WaitForChild("Net"))

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")
local cam = Workspace.CurrentCamera

-- Co-op join layer (Half 2): am I in a private gameplay server, or the public
-- front-door router? In Studio (no TeleportService) we always play locally so the
-- game stays testable. `routerMode` = show the Solo / Co-op teleport chooser.
local SocialService = game:GetService("SocialService")
local TeleportService = game:GetService("TeleportService")
-- Are we in a private gameplay server? Client-side game.PrivateServerId reads empty in
-- reserved servers, which made the menu show there and Play Solo teleport again (a loop).
-- Detect from the teleport data we ARRIVED with (the reliable mechanism), backed by a
-- server-set flag (DD_ServerKind) for the fresh-join / edge cases.
local function detectReserved(): boolean
	local td = nil
	pcall(function() td = TeleportService:GetLocalPlayerTeleportData() end)
	if type(td) == "table" and (td.mode == "solo" or td.mode == "coop") then return true end
	local kind = ReplicatedStorage:GetAttribute("DD_ServerKind")
	if kind == nil then
		local t0 = os.clock()
		repeat task.wait(0.05) until ReplicatedStorage:GetAttribute("DD_ServerKind") ~= nil or os.clock() - t0 > 3
		kind = ReplicatedStorage:GetAttribute("DD_ServerKind")
	end
	return kind == "reserved"
end
local isReserved = detectReserved()
local routerMode = (not isReserved) and (not RunService:IsStudio())
local coopJoinKey: string? = nil
local mmContext: string? = nil  -- "solo" | "coop": which UI the next MatchmakingStatus updates

-- ===================== settings =====================
local settings = { master = 1, music = 0.8, sfx = 1, sensitivity = 1, brightness = 0 }
local brightnessCC
local function applySettings()
	local sfx = SoundService:FindFirstChild("SFX")
	local music = SoundService:FindFirstChild("Music")
	if sfx then sfx.Volume = settings.sfx * settings.master end
	if music then music.Volume = settings.music * settings.master end
	UserInputService.MouseDeltaSensitivity = math.clamp(settings.sensitivity, 0.2, 3)
	if not brightnessCC then
		brightnessCC = Instance.new("ColorCorrectionEffect")
		brightnessCC.Name = "DD_BrightnessCC"
		brightnessCC.Parent = Lighting
	end
	brightnessCC.Brightness = settings.brightness * 0.25
end
local saveQueued = false
local function queueSave()
	if saveQueued then return end
	saveQueued = true
	task.delay(0.4, function()
		saveQueued = false
		Net.Event("SaveSettings"):FireServer(settings)
	end)
end

-- ===================== gui scaffold =====================
local gui = Instance.new("ScreenGui")
gui.Name = "DeepDescentMenu"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 60
gui.Enabled = false
gui.Parent = pg

local mainMenu = Instance.new("Frame")
mainMenu.Size = UDim2.fromScale(1, 1)
mainMenu.BackgroundTransparency = 1
mainMenu.Visible = false
mainMenu.Parent = gui

-- Full-screen background photo for the main menu. Rendered behind every other
-- menu element (ZIndex 0) so the title / buttons / skip-intro row / vignette all
-- sit on top; the vignette below keeps the lower buttons legible over it. Crop
-- scale = cover the whole screen with no distortion (overflow is trimmed).
-- Covers the animated 3D MenuScene backdrop while the menu is up.
local bgImage = Instance.new("ImageLabel")
bgImage.Name = "MenuBackground"
bgImage.AnchorPoint = Vector2.new(0.5, 0.5)
bgImage.Position = UDim2.fromScale(0.5, 0.5)
bgImage.Size = UDim2.fromScale(1, 1)
bgImage.BackgroundColor3 = Color3.new(0, 0, 0)
bgImage.BorderSizePixel = 0
bgImage.ScaleType = Enum.ScaleType.Crop
bgImage.Image = "rbxassetid://102522616858545"
bgImage.ZIndex = 0
bgImage.Parent = mainMenu


local vig = Instance.new("Frame")
vig.AnchorPoint = Vector2.new(0, 1); vig.Position = UDim2.fromScale(0, 1)
vig.Size = UDim2.new(1, 0, 0.55, 0); vig.BackgroundColor3 = Color3.new(0, 0, 0)
vig.BorderSizePixel = 0; vig.Parent = mainMenu
local vg = Instance.new("UIGradient"); vg.Rotation = 90
vg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.25) })
vg.Parent = vig

local title = Instance.new("TextLabel")
title.AnchorPoint = Vector2.new(0.5, 0); title.Position = UDim2.fromScale(0.5, 0.12)
title.Size = UDim2.fromScale(0.8, 0.13); title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold; title.TextColor3 = Color3.fromRGB(225, 232, 238)
title.TextScaled = true; title.Text = "HULL BREACH"; title.Parent = mainMenu
local subtitle = Instance.new("TextLabel")
subtitle.AnchorPoint = Vector2.new(0.5, 0); subtitle.Position = UDim2.fromScale(0.5, 0.26)
subtitle.Size = UDim2.fromScale(0.6, 0.035); subtitle.BackgroundTransparency = 1
subtitle.Font = Enum.Font.Merriweather; subtitle.TextColor3 = Color3.fromRGB(150, 170, 185)
subtitle.TextScaled = true; subtitle.Text = "They should never have gone this deep."; subtitle.Parent = mainMenu

local btnHolder = Instance.new("Frame")
btnHolder.AnchorPoint = Vector2.new(0.5, 1); btnHolder.Position = UDim2.fromScale(0.5, 0.92)
btnHolder.Size = UDim2.fromOffset(280, 314); btnHolder.BackgroundTransparency = 1; btnHolder.Parent = mainMenu
local bl = Instance.new("UIListLayout"); bl.Padding = UDim.new(0, 10)
bl.HorizontalAlignment = Enum.HorizontalAlignment.Center; bl.Parent = btnHolder
local function menuButton(text, order, cb)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 44); b.BackgroundColor3 = Color3.fromRGB(22, 28, 34)
	b.BackgroundTransparency = 0.1; b.BorderSizePixel = 0; b.AutoButtonColor = true
	b.Font = Enum.Font.GothamMedium; b.TextSize = 18; b.TextColor3 = Color3.fromRGB(225, 232, 238)
	b.Text = text; b.LayoutOrder = order; b.Parent = btnHolder
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = b
	b.MouseButton1Click:Connect(cb)
	return b
end

local version = Instance.new("TextLabel")
version.AnchorPoint = Vector2.new(1, 1); version.Position = UDim2.new(1, -10, 1, -8)
version.Size = UDim2.fromOffset(240, 18); version.BackgroundTransparency = 1
version.Font = Enum.Font.Code; version.TextColor3 = Color3.fromRGB(120, 130, 140); version.TextSize = 12
version.TextXAlignment = Enum.TextXAlignment.Right; version.Text = "Hull Breach — build 1.0"; version.Parent = mainMenu

-- ===================== skip-intro checkbox (main menu, session-only) =====================
-- When ticked, pressing PLAY skips the ~15s story prologue. Deliberately NOT
-- persisted: resets to OFF on every fresh join, so a player's first descent of a
-- session always shows the cutscene; the skip only takes hold once they tick it
-- here in the menu. `skipIntro` is read by play() further below.
local skipIntro = false
local skipRow = Instance.new("TextButton")
skipRow.AnchorPoint = Vector2.new(0.5, 1)
skipRow.Position = UDim2.new(0.5, 0, 0.92, -324)  -- 10px above the 314px-tall button stack
skipRow.Size = UDim2.fromOffset(240, 26)
skipRow.BackgroundTransparency = 1
skipRow.AutoButtonColor = false
skipRow.Text = ""
skipRow.Parent = mainMenu
local skipBox = Instance.new("Frame")
skipBox.AnchorPoint = Vector2.new(0, 0.5); skipBox.Position = UDim2.new(0, 0, 0.5, 0)
skipBox.Size = UDim2.fromOffset(22, 22); skipBox.BackgroundColor3 = Color3.fromRGB(22, 28, 34)
skipBox.BackgroundTransparency = 0.1; skipBox.BorderSizePixel = 0; skipBox.Parent = skipRow
local skipBoxCorner = Instance.new("UICorner"); skipBoxCorner.CornerRadius = UDim.new(0, 4); skipBoxCorner.Parent = skipBox
local skipStroke = Instance.new("UIStroke"); skipStroke.Color = Color3.fromRGB(90, 100, 110); skipStroke.Thickness = 1; skipStroke.Parent = skipBox
local skipCheck = Instance.new("TextLabel")
skipCheck.Size = UDim2.fromScale(1, 1); skipCheck.BackgroundTransparency = 1
skipCheck.Font = Enum.Font.GothamBold; skipCheck.TextColor3 = Color3.fromRGB(150, 200, 220)
skipCheck.TextScaled = true; skipCheck.Text = "\u{2713}"; skipCheck.Visible = false; skipCheck.Parent = skipBox
local skipLabel = Instance.new("TextLabel")
skipLabel.AnchorPoint = Vector2.new(0, 0.5); skipLabel.Position = UDim2.new(0, 30, 0.5, 0)
skipLabel.Size = UDim2.new(1, -30, 1, 0); skipLabel.BackgroundTransparency = 1
skipLabel.Font = Enum.Font.GothamMedium; skipLabel.TextColor3 = Color3.fromRGB(200, 208, 214)
skipLabel.TextSize = 15; skipLabel.TextXAlignment = Enum.TextXAlignment.Left
skipLabel.Text = "Skip intro cutscene"; skipLabel.Parent = skipRow
local function updateSkip()
	skipCheck.Visible = skipIntro
	skipBox.BackgroundColor3 = skipIntro and Color3.fromRGB(28, 44, 52) or Color3.fromRGB(22, 28, 34)
end
skipRow.MouseButton1Click:Connect(function() skipIntro = not skipIntro; updateSkip() end)
updateSkip()


-- ===================== generic panel =====================
local function makePanel(headingText)
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5); panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(640, 460); panel.BackgroundColor3 = Color3.fromRGB(16, 20, 24)
	panel.BackgroundTransparency = 0.04; panel.Visible = false; panel.Parent = gui
	local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 10); pc.Parent = panel
	local heading = Instance.new("TextLabel")
	heading.Size = UDim2.new(1, -56, 0, 40); heading.Position = UDim2.fromOffset(16, 8)
	heading.BackgroundTransparency = 1; heading.Font = Enum.Font.GothamBold
	heading.TextColor3 = Color3.fromRGB(220, 228, 235); heading.TextSize = 22
	heading.TextXAlignment = Enum.TextXAlignment.Left; heading.Text = headingText; heading.Parent = panel
	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0); close.Position = UDim2.new(1, -12, 0, 12)
	close.Size = UDim2.fromOffset(28, 28); close.BackgroundColor3 = Color3.fromRGB(44, 50, 56)
	close.Text = "X"; close.Font = Enum.Font.GothamBold; close.TextColor3 = Color3.fromRGB(220, 228, 235)
	close.TextSize = 16; close.Parent = panel
	local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 6); cc.Parent = close
	return panel, close
end

-- ===================== records + store panels =====================
local function makeScroll(panel)
	local sc = Instance.new("ScrollingFrame")
	sc.Position = UDim2.fromOffset(16, 56); sc.Size = UDim2.new(1, -32, 1, -72)
	sc.BackgroundTransparency = 1; sc.BorderSizePixel = 0; sc.ScrollBarThickness = 6
	sc.CanvasSize = UDim2.new(); sc.AutomaticCanvasSize = Enum.AutomaticSize.Y; sc.Parent = panel
	local ll = Instance.new("UIListLayout"); ll.Padding = UDim.new(0, 6)
	ll.SortOrder = Enum.SortOrder.LayoutOrder; ll.Parent = sc
	return sc
end
local recordsPanel, recordsClose = makePanel("HULL BREACH — RECORDS")
local storePanel, storeClose = makePanel("HULL BREACH — STORE")
local leaderboardPanel, leaderboardClose = makePanel("HULL BREACH — LEADERBOARDS")
local recordsScroll = makeScroll(recordsPanel)
local storeScroll = makeScroll(storePanel)
local leaderboardScroll = makeScroll(leaderboardPanel)
-- `scroll` is retargeted to the active panel before each rebuild; the row/sectionLabel/clearScroll helpers below close over it.
local scroll = recordsScroll
local function clearScroll() for _, c in ipairs(scroll:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end end
local function sectionLabel(text, order)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, 0, 0, 26); l.BackgroundTransparency = 1; l.Font = Enum.Font.GothamBold
	l.TextColor3 = Color3.fromRGB(150, 200, 220); l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextSize = 16; l.Text = text; l.LayoutOrder = order; l.Parent = scroll
end
local function row(text, sub, order, button)
	local f = Instance.new(button and "TextButton" or "Frame")
	f.Size = UDim2.new(1, 0, 0, 44); f.BackgroundColor3 = Color3.fromRGB(26, 32, 38)
	f.BorderSizePixel = 0; f.LayoutOrder = order
	if f:IsA("TextButton") then f.Text = ""; f.AutoButtonColor = true end
	f.Parent = scroll
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = f
	local t = Instance.new("TextLabel")
	t.Position = UDim2.fromOffset(10, 4); t.Size = UDim2.new(1, -20, 0, 20); t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamMedium; t.TextColor3 = Color3.fromRGB(225, 230, 235)
	t.TextXAlignment = Enum.TextXAlignment.Left; t.TextSize = 15; t.Text = text; t.Parent = f
	local s = Instance.new("TextLabel")
	s.Position = UDim2.fromOffset(10, 22); s.Size = UDim2.new(1, -20, 0, 18); s.BackgroundTransparency = 1
	s.Font = Enum.Font.Code; s.TextColor3 = Color3.fromRGB(150, 160, 170)
	s.TextXAlignment = Enum.TextXAlignment.Left; s.TextSize = 12; s.Text = sub; s.Parent = f
	if button and f:IsA("TextButton") then button(f) end
end
local function refreshRecords()
	scroll = recordsScroll
	clearScroll()
	local state = nil
	pcall(function() state = Net.Func("GetGameState"):InvokeServer() end)
	local endings = (state and state.endings) or {}
	local order = 0
	-- save-slot picker (each slot is separate endings progress)
	local curSlot = (state and state.slot) or 1
	local slots = (state and state.slots) or 1
	local maxSlots = (state and state.maxSlots) or 3
	sectionLabel(("SAVE SLOTS   (slot %d · %d unlocked)"):format(curSlot, slots), order); order += 1
	for n = 1, maxSlots do
		local unlocked = n <= slots
		local isCur = n == curSlot
		local label = "Save Slot " .. n .. (isCur and "   \u{2190} current" or "")
		local sub = (not unlocked) and "Locked \u{2014} buy an Extra Save Slot" or (isCur and "Active" or "Click to switch (separate endings progress)")
		local wire = (unlocked and not isCur) and function(b)
			b.MouseButton1Click:Connect(function() Net.Event("SelectSlot"):FireServer(n); task.wait(0.3); refreshRecords() end)
		end or nil
		row(label, sub, order, wire); order += 1
	end
	local totalE, foundE = 0, 0
	for _, id in ipairs(EndingData.Order) do totalE += 1; if endings[id] == true then foundE += 1 end end
	sectionLabel(("ENDINGS LOG   (%d / %d found)"):format(foundE, totalE), order); order += 1
	for _, id in ipairs(EndingData.Order) do
		local data = EndingData.Endings[id]
		if endings[id] == true then
			row(("[%s]  %s"):format(data.category:upper(), data.name), data.blurb or "", order)
		else
			row(data.secret and "SECRET — ???" or (data.category:upper() .. " — ???"), "Undiscovered.", order)
		end
		order += 1
	end
end

local function refreshStore()
	scroll = storeScroll
	clearScroll()
	local state = nil
	pcall(function() state = Net.Func("GetGameState"):InvokeServer() end)
	local owned = (state and state.owned) or {}
	local passes = (state and state.passes) or {}
	local equipped = (state and state.cosmetics) or {}
	local order = 0
	-- cosmetic section: Equipped / Owned (click to equip) / Click to purchase.
	local function cosmeticSection(title, kind, list)
		sectionLabel(title, order); order += 1
		for _, item in pairs(list) do
			local label = item.name .. (item.price > 0 and ("  (" .. item.price .. " R$)") or "  (free)")
			local isOwned = item.key == "default" or owned[item.key] == true
			local isEquipped = (equipped[kind] or "default") == item.key
			local sub = isEquipped and "Equipped \u{2713}"
				or (isOwned and "Owned \u{2014} click to equip" or "Click to purchase")
			row(label, sub, order, function(b)
				b.MouseButton1Click:Connect(function()
					if isOwned then
						Net.Event("CosmeticSelect"):FireServer(kind, item.key)
						task.wait(0.25); refreshStore()
					else
						Net.Event("Purchase"):FireServer(kind, item.key)
					end
				end)
			end); order += 1
		end
	end
	-- game passes: one-time; flip to "Purchased" once owned. Fixed order so they
	-- don't shuffle between opens (pairs() is unordered).
	sectionLabel("GAME PASSES", order); order += 1
	for _, key in ipairs({ "supporter", "nightmare", "commentary" }) do
		local pass = Monetization.Passes[key]
		if pass then
			if passes[pass.key] == true then
				row(pass.name, "Purchased \u{2713}", order); order += 1
			else
				row(pass.name .. "  (" .. pass.price .. " R$)", pass.desc, order, function(b)
					b.MouseButton1Click:Connect(function() Net.Event("Purchase"):FireServer("pass", pass.key) end)
				end); order += 1
			end
		end
	end
	-- extra save slots (developer product)
	local slots = (state and state.slots) or 1
	local maxSlots = (state and state.maxSlots) or 3
	sectionLabel("SAVE SLOTS", order); order += 1
	local slotProd = Monetization.Products.save_slot
	if slots >= maxSlots then
		row("Extra Save Slot", ("All %d save slots unlocked."):format(maxSlots), order); order += 1
	elseif slotProd then
		row(slotProd.name .. "  (" .. slotProd.price .. " R$)", ("You have %d of %d slots \u{2014} buy one more."):format(slots, maxSlots), order, function(b)
			b.MouseButton1Click:Connect(function() Net.Event("Purchase"):FireServer("product", "save_slot") end)
		end); order += 1
	end
	cosmeticSection("FLASHLIGHT BEAMS", "flashlight", Monetization.FlashlightSkins)
	cosmeticSection("DIVING SUITS", "suit", Monetization.SuitSkins)
	cosmeticSection("DEATH ANIMATIONS", "death", Monetization.DeathAnimations)
end

-- ===================== leaderboards panel =====================
local function fmtTime(s)
	s = math.floor(tonumber(s) or 0)
	return string.format("%d:%02d", math.floor(s / 60), s % 60)
end
local function lbRows(entries, order, valueFmt)
	if not entries or #entries == 0 then
		row("No entries yet.", "This board fills from the published game.", order)
		return order + 1
	end
	for i, e in ipairs(entries) do
		row(("%d.  %s"):format(i, tostring(e.name)), valueFmt(e.value), order)
		order += 1
	end
	return order
end
local function refreshLeaderboards()
	scroll = leaderboardScroll
	clearScroll()
	local lb = nil
	pcall(function() lb = Net.Func("GetLeaderboards"):InvokeServer() end)
	lb = lb or {}
	local totalEndings = #EndingData.Order
	local order = 0
	sectionLabel("LONGEST SURVIVAL", order); order += 1
	order = lbRows(lb.survival, order, function(v) return fmtTime(v) .. " survived" end)
	sectionLabel("MOST ENDINGS UNLOCKED", order); order += 1
	order = lbRows(lb.endings, order, function(v) return ("%d / %d endings"):format(v, totalEndings) end)
	for _, id in ipairs(lb.escapeIds or {}) do
		local data = EndingData.Endings[id]
		sectionLabel("FASTEST ESCAPE — " .. (data and data.name or id):upper(), order); order += 1
		order = lbRows(lb.escape and lb.escape[id], order, function(v) return fmtTime(v) end)
	end
end

-- Refresh whichever shop panel is open (store, or the [L] records overlay) when a
-- purchase completes, so newly bought items flip to Purchased / can be equipped
-- without reopening the menu.
local function refreshVisibleShop()
	if storePanel.Visible then refreshStore()
	elseif recordsPanel.Visible then refreshRecords() end
end
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(_plr, _id, purchased)
	if purchased then task.wait(0.7); refreshVisibleShop() end
end)
MarketplaceService.PromptProductPurchaseFinished:Connect(function(_userId, _productId, purchased)
	if purchased then task.wait(0.7); refreshVisibleShop() end
end)

-- ===================== settings panel =====================
local settingsPanel, settingsClose = makePanel("SETTINGS")
local sBody = Instance.new("Frame")
sBody.Position = UDim2.fromOffset(0, 56); sBody.Size = UDim2.new(1, 0, 1, -72)
sBody.BackgroundTransparency = 1; sBody.Parent = settingsPanel
local function makeSlider(y, labelText, getV, setV, minV, maxV, fmt)
	local rowf = Instance.new("Frame")
	rowf.Size = UDim2.new(1, -32, 0, 46); rowf.Position = UDim2.fromOffset(16, y)
	rowf.BackgroundTransparency = 1; rowf.Parent = sBody
	local lab = Instance.new("TextLabel")
	lab.Size = UDim2.new(0.34, 0, 1, 0); lab.BackgroundTransparency = 1; lab.Font = Enum.Font.GothamMedium
	lab.TextColor3 = Color3.fromRGB(220, 228, 235); lab.TextSize = 15
	lab.TextXAlignment = Enum.TextXAlignment.Left; lab.Text = labelText; lab.Parent = rowf
	local track = Instance.new("Frame")
	track.AnchorPoint = Vector2.new(0, 0.5); track.Position = UDim2.new(0.36, 0, 0.5, 0)
	track.Size = UDim2.new(0.52, 0, 0, 8); track.BackgroundColor3 = Color3.fromRGB(40, 46, 52)
	track.BorderSizePixel = 0; track.Parent = rowf
	local tc = Instance.new("UICorner"); tc.CornerRadius = UDim.new(1, 0); tc.Parent = track
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = Color3.fromRGB(120, 180, 210); fill.BorderSizePixel = 0; fill.Parent = track
	local fc = Instance.new("UICorner"); fc.CornerRadius = UDim.new(1, 0); fc.Parent = fill
	local valLab = Instance.new("TextLabel")
	valLab.AnchorPoint = Vector2.new(0, 0.5); valLab.Position = UDim2.new(0.9, 8, 0.5, 0)
	valLab.Size = UDim2.fromOffset(64, 20); valLab.BackgroundTransparency = 1; valLab.Font = Enum.Font.Code
	valLab.TextColor3 = Color3.fromRGB(170, 180, 190); valLab.TextSize = 13
	valLab.TextXAlignment = Enum.TextXAlignment.Left; valLab.Parent = rowf
	local function redraw()
		local p = math.clamp((getV() - minV) / (maxV - minV), 0, 1)
		fill.Size = UDim2.fromScale(p, 1)
		valLab.Text = fmt and fmt(getV()) or (math.floor(p * 100 + 0.5) .. "%")
	end
	redraw()
	local dragging = false
	local function setFromX(px)
		local rel = math.clamp((px - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		setV(minV + rel * (maxV - minV)); redraw()
	end
	track.InputBegan:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
			dragging = true; setFromX(inp.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(inp)
		if dragging and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) then
			setFromX(inp.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then dragging = false end
	end)
end
local function buildSettings()
	for _, c in ipairs(sBody:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
	local function vol(k) return function() return settings[k] end, function(v) settings[k] = v; applySettings(); queueSave() end end
	local g, s
	g, s = vol("master");      makeSlider(8,   "Master Volume", g, s, 0, 1)
	g, s = vol("music");       makeSlider(58,  "Music / Ambient", g, s, 0, 1)
	g, s = vol("sfx");         makeSlider(108, "Sound Effects", g, s, 0, 1)
	g, s = vol("sensitivity"); makeSlider(168, "Mouse Sensitivity", g, s, 0.2, 3, function(v) return string.format("%.2fx", v) end)
	g, s = vol("brightness");  makeSlider(218, "Brightness", g, s, -1, 1, function(v) return (v >= 0 and "+" or "") .. math.floor(v * 100 + 0.5) end)
	local note = Instance.new("TextLabel")
	note.Position = UDim2.fromOffset(16, 280); note.Size = UDim2.new(1, -32, 0, 40); note.BackgroundTransparency = 1
	note.Font = Enum.Font.Code; note.TextColor3 = Color3.fromRGB(120, 130, 140); note.TextSize = 12
	note.TextWrapped = true; note.TextXAlignment = Enum.TextXAlignment.Left
	note.Text = "First-person view is fixed by design — there is no camera setting."; note.Parent = sBody
end

-- ===================== credits panel =====================
local creditsPanel, creditsClose = makePanel("CREDITS")
do
	local lines = {
		{ "HULL BREACH", true },
		{ "A first-person atmospheric submarine horror.", false },
		{ "", false },
		{ "Design & Development", true },
		{ "David Berbecar", false },
		{ "Razvan Berbecar", false },
		{ "", false },
		{ "With AI assistance", true },
		{ "", false },
		{ "Audio: free Creator Store SFX (ProSoundEffects et al.)", false },
		{ "Engine: Roblox  ·  Luau", false },
	}
	local y = 60
	for _, entry in ipairs(lines) do
		local l = Instance.new("TextLabel")
		l.Position = UDim2.fromOffset(24, y); l.Size = UDim2.new(1, -48, 0, entry[1] == "" and 10 or 24)
		l.BackgroundTransparency = 1; l.Font = entry[2] and Enum.Font.GothamBold or Enum.Font.Gotham
		l.TextColor3 = entry[2] and Color3.fromRGB(150, 200, 220) or Color3.fromRGB(215, 222, 228)
		l.TextSize = entry[2] and 17 or 15; l.TextXAlignment = Enum.TextXAlignment.Left
		l.Text = entry[1]; l.Parent = creditsPanel
		y += (entry[1] == "" and 12 or 28)
	end
end

-- ===================== co-op join UI (Half 2) =====================
-- Full-screen "connecting" cover for Play Solo + invited-friend routing + errors.
local connectOverlay = Instance.new("Frame")
connectOverlay.Name = "ConnectOverlay"; connectOverlay.Size = UDim2.fromScale(1, 1)
connectOverlay.BackgroundColor3 = Color3.new(0, 0, 0); connectOverlay.BackgroundTransparency = 0.2
connectOverlay.Active = true; connectOverlay.Visible = false; connectOverlay.ZIndex = 90; connectOverlay.Parent = gui
local connectLabel = Instance.new("TextLabel")
connectLabel.AnchorPoint = Vector2.new(0.5, 0.5); connectLabel.Position = UDim2.fromScale(0.5, 0.47)
connectLabel.Size = UDim2.fromScale(0.7, 0.1); connectLabel.BackgroundTransparency = 1
connectLabel.Font = Enum.Font.GothamMedium; connectLabel.TextColor3 = Color3.fromRGB(220, 228, 235)
connectLabel.TextScaled = true; connectLabel.Text = ""; connectLabel.ZIndex = 91; connectLabel.Parent = connectOverlay
local connectBack = Instance.new("TextButton")
connectBack.AnchorPoint = Vector2.new(0.5, 0.5); connectBack.Position = UDim2.fromScale(0.5, 0.58)
connectBack.Size = UDim2.fromOffset(160, 40); connectBack.BackgroundColor3 = Color3.fromRGB(40, 46, 52)
connectBack.Font = Enum.Font.GothamMedium; connectBack.TextColor3 = Color3.fromRGB(225, 232, 238)
connectBack.TextSize = 16; connectBack.Text = "BACK"; connectBack.Visible = false; connectBack.ZIndex = 91
connectBack.Parent = connectOverlay
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = connectBack end
connectBack.MouseButton1Click:Connect(function() connectOverlay.Visible = false end)
local function showConnecting(text, isError)
	connectLabel.Text = text or ""; connectBack.Visible = isError == true; connectOverlay.Visible = true
end

-- Co-op panel (Invite a Friend / Quick Match), opened from the router menu.
local coopPanel, coopClose = makePanel("PLAY WITH A FRIEND")
local function coopBigButton(text, sub, order)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, -32, 0, 64); b.Position = UDim2.fromOffset(16, 60 + (order - 1) * 74)
	b.BackgroundColor3 = Color3.fromRGB(26, 34, 42); b.BorderSizePixel = 0; b.AutoButtonColor = true
	b.Font = Enum.Font.GothamBold; b.TextColor3 = Color3.fromRGB(225, 232, 238); b.TextSize = 20
	b.Text = text; b.Parent = coopPanel
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = b
	local s = Instance.new("TextLabel")
	s.AnchorPoint = Vector2.new(0.5, 1); s.Position = UDim2.new(0.5, 0, 1, -8); s.Size = UDim2.new(1, -20, 0, 16)
	s.BackgroundTransparency = 1; s.Font = Enum.Font.Gotham; s.TextColor3 = Color3.fromRGB(150, 160, 170)
	s.TextSize = 12; s.Text = sub; s.Parent = b
	return b
end
local coopInviteBtn = coopBigButton("INVITE A FRIEND", "Create a private dive and invite someone", 1)
local coopQuickBtn = coopBigButton("QUICK MATCH", "Get paired with a random diver", 2)
local coopStatus = Instance.new("TextLabel")
coopStatus.Position = UDim2.fromOffset(16, 216); coopStatus.Size = UDim2.new(1, -32, 0, 44)
coopStatus.BackgroundTransparency = 1; coopStatus.Font = Enum.Font.Code
coopStatus.TextColor3 = Color3.fromRGB(150, 200, 220); coopStatus.TextSize = 15; coopStatus.TextWrapped = true
coopStatus.TextXAlignment = Enum.TextXAlignment.Left; coopStatus.Text = ""; coopStatus.Parent = coopPanel
local coopCancel = Instance.new("TextButton")
coopCancel.Position = UDim2.fromOffset(16, 264); coopCancel.Size = UDim2.fromOffset(170, 40)
coopCancel.BackgroundColor3 = Color3.fromRGB(60, 40, 40); coopCancel.Font = Enum.Font.GothamMedium
coopCancel.TextColor3 = Color3.fromRGB(235, 220, 220); coopCancel.TextSize = 16; coopCancel.Text = "CANCEL SEARCH"
coopCancel.Visible = false; coopCancel.Parent = coopPanel
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = coopCancel end
local function setCoopStatus(text) coopStatus.Text = text or "" end
local function resetCoopPanel() coopStatus.Text = ""; coopCancel.Visible = false end
coopInviteBtn.MouseButton1Click:Connect(function()
	mmContext = "coop"; setCoopStatus("Setting up a private dive…"); coopCancel.Visible = false
	Net.Event("RequestCoopHost"):FireServer()
end)
coopQuickBtn.MouseButton1Click:Connect(function()
	mmContext = "coop"; setCoopStatus("Searching for a partner…"); coopCancel.Visible = true
	Net.Event("RequestQuickMatch"):FireServer()
end)
coopCancel.MouseButton1Click:Connect(function()
	Net.Event("CancelMatchmaking"):FireServer(); resetCoopPanel()
end)

-- Play Solo: reserve a private 1-player server and teleport there.
local function startSolo()
	mmContext = "solo"; showConnecting("Preparing your dive…")
	Net.Event("RequestSolo"):FireServer()
end

-- Return to Lobby: teleport back to a public router server (the Solo/Co-op menu).
-- Roblox's teleport loading screen covers the transition.
local function returnToLobby()
	Net.Event("RequestLobby"):FireServer()
end

-- Prompt the Roblox friend-invite carrying the co-op joinKey as LaunchData.
local function promptInvite(joinKey)
	if not joinKey then return end
	local ok, canInvite = pcall(function() return SocialService:CanSendGameInviteAsync(player) end)
	if not (ok and canInvite) then return end
	local opts = Instance.new("ExperienceInviteOptions")
	opts.LaunchData = joinKey
	pcall(function() SocialService:PromptGameInvite(player, opts) end)
end

-- ===================== camera / controls / ambient =====================
local driftConn
local function startDrift()
	cam = Workspace.CurrentCamera
	local scene = Workspace:WaitForChild("MenuScene", 10)
	local anchor = scene and scene:FindFirstChild("CameraAnchor")
	local base = (anchor and anchor.CFrame) or CFrame.lookAt(Vector3.new(9, -494, 46), Vector3.new(0, -500, 0))
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = base
	local t0 = os.clock()
	driftConn = RunService.RenderStepped:Connect(function()
		if cam.CameraType ~= Enum.CameraType.Scriptable then cam.CameraType = Enum.CameraType.Scriptable end
		local t = os.clock() - t0
		cam.CFrame = base
			* CFrame.Angles(math.rad(1.4 * math.sin(t * 0.13)), math.rad(3 * math.sin(t * 0.09)), 0)
			* CFrame.new(0, 0, -2 * math.sin(t * 0.07))
	end)
end
local function stopDrift()
	if driftConn then driftConn:Disconnect(); driftConn = nil end
end

local function setControls(enabled)
	pcall(function()
		local pm = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
		local controls = pm:GetControls()
		if enabled then controls:Enable() else controls:Disable() end
	end)
end

local ambientHolder = Instance.new("Folder"); ambientHolder.Name = "DD_MenuAudio"; ambientHolder.Parent = pg
local ambientOn = false
local function startAmbient()
	ambientOn = true
	local musicGroup = SoundService:FindFirstChild("Music")
	local ocean = SoundData.Make("water_rushing", ambientHolder, { Looped = true, Volume = 0.22, SoundGroup = musicGroup })
	if SoundData.HasAsset("water_rushing") then ocean:Play() end
	task.spawn(function()
		while ambientOn do
			task.wait(8 + math.random() * 9)
			if not ambientOn then break end
			local w = SoundData.Make("creature_rumble", ambientHolder, { Volume = 0.4, PlaybackSpeed = 0.55, SoundGroup = musicGroup })
			w.Name = "Snd_whale_" .. tostring(math.random(1, 1e6))
			if SoundData.HasAsset("creature_rumble") then w:Play() end
			task.delay(8, function() if w then w:Destroy() end end)
		end
	end)
end
local function stopAmbient()
	ambientOn = false
	for _, c in ipairs(ambientHolder:GetChildren()) do c:Destroy() end
end

local hidden = {}
local function hideHud(hide)
	for _, g in ipairs(pg:GetChildren()) do
		if g:IsA("ScreenGui") and g ~= gui and g.Name ~= "IntroScreen" then
			if hide then
				if g.Enabled then hidden[g] = true; g.Enabled = false end
			elseif hidden[g] then g.Enabled = true; hidden[g] = nil end
		end
	end
end

-- ===================== navigation / flow =====================
local inMenu = true
local menuActive = false
local function showOnly(which)
	mainMenu.Visible = (which == "main")
	recordsPanel.Visible = (which == "records")
	storePanel.Visible = (which == "store")
	leaderboardPanel.Visible = (which == "leaderboard")
	settingsPanel.Visible = (which == "settings")
	creditsPanel.Visible = (which == "credits")
	coopPanel.Visible = (which == "coop")
end
local function backToMain()
	if inMenu then showOnly("main") else gui.Enabled = false; showOnly("none") end
end
recordsClose.MouseButton1Click:Connect(backToMain)
storeClose.MouseButton1Click:Connect(backToMain)
leaderboardClose.MouseButton1Click:Connect(backToMain)
settingsClose.MouseButton1Click:Connect(backToMain)
creditsClose.MouseButton1Click:Connect(backToMain)
coopClose.MouseButton1Click:Connect(backToMain)

local function enterMenu()
	if menuActive then return end
	menuActive = true
	inMenu = true
	gui.Enabled = true
	showOnly("main")
	hideHud(true)
	task.delay(1.5, function() if menuActive then hideHud(true) end end)
	setControls(false)
	startDrift()
	startAmbient()
	player:SetAttribute("DD_MenuReady", true)
end

local function releaseToGameplay()
	stopDrift()
	cam = Workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	setControls(true)
	hideHud(false)
	gui.Enabled = false
end

-- ===================== co-op ready-gate / lobby wait =====================
-- Shown while we've pressed Play but the shared run hasn't started yet (waiting
-- for the partner to ready up). Active=true so menu buttons behind it are blocked.
-- Solo: RunStarted lands within a frame, so the 0.4s delayed reveal below means
-- this overlay never actually appears.
local waitOverlay = Instance.new("Frame")
waitOverlay.Name = "CoopWait"
waitOverlay.Size = UDim2.fromScale(1, 1)
waitOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
waitOverlay.BackgroundTransparency = 0.35
waitOverlay.Active = true
waitOverlay.Visible = false
waitOverlay.ZIndex = 80
waitOverlay.Parent = gui
local waitLabel = Instance.new("TextLabel")
waitLabel.AnchorPoint = Vector2.new(0.5, 0.5)
waitLabel.Position = UDim2.fromScale(0.5, 0.46)
waitLabel.Size = UDim2.fromScale(0.7, 0.08)
waitLabel.BackgroundTransparency = 1
waitLabel.Font = Enum.Font.GothamMedium
waitLabel.TextColor3 = Color3.fromRGB(220, 228, 235)
waitLabel.TextScaled = true
waitLabel.Text = "Waiting for your partner\u{2026}"
waitLabel.ZIndex = 81
waitLabel.Parent = waitOverlay
local waitCancel = Instance.new("TextButton")
waitCancel.AnchorPoint = Vector2.new(0.5, 0.5)
waitCancel.Position = UDim2.fromScale(0.5, 0.58)
waitCancel.Size = UDim2.fromOffset(200, 44)
waitCancel.BackgroundColor3 = Color3.fromRGB(22, 28, 34)
waitCancel.BackgroundTransparency = 0.1
waitCancel.Font = Enum.Font.GothamMedium
waitCancel.TextColor3 = Color3.fromRGB(225, 232, 238)
waitCancel.TextSize = 18
waitCancel.Text = "CANCEL"
waitCancel.ZIndex = 81
waitCancel.Parent = waitOverlay
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = waitCancel end

-- The old play() body: released to gameplay once the server confirms the run began.
local function beginGameplay()
	if not inMenu then return end
	inMenu = false
	menuActive = false
	showOnly("none")
	stopAmbient()
	if skipIntro then
		-- Skip-intro checkbox is ticked: go straight into gameplay, no prologue.
		player:SetAttribute("DD_PlayPrologue", false)
		releaseToGameplay()
		return
	end
	player:SetAttribute("DD_PrologueDone", false)
	player:SetAttribute("DD_PlayPrologue", true)  -- IntroScreen fades to black + plays the prologue
	task.spawn(function()
		local t0 = os.clock()
		while player:GetAttribute("DD_PrologueDone") ~= true and (os.clock() - t0) < 45 do
			RunService.Heartbeat:Wait()
		end
		player:SetAttribute("DD_PlayPrologue", false)  -- consume so IntroScreen can replay
		releaseToGameplay()
	end)
end

-- Pressing Play readies us up; the run + this client's intro only begin when the
-- server broadcasts RunStarted (every player ready). We stay on the menu until then.
local pendingStart = false
local function play()
	if not inMenu or pendingStart then return end
	pendingStart = true
	Net.Event("StartRun"):FireServer()
	task.delay(0.4, function()
		if pendingStart then waitOverlay.Visible = true end
	end)
end

Net.Event("RunStarted").OnClientEvent:Connect(function()
	if not pendingStart then return end
	pendingStart = false
	waitOverlay.Visible = false
	beginGameplay()
end)

waitCancel.MouseButton1Click:Connect(function()
	if not pendingStart then return end
	pendingStart = false
	waitOverlay.Visible = false
	Net.Event("CancelReady"):FireServer()
end)

if routerMode then
	-- Public front-door router: choose how to descend (each teleports to a private server).
	menuButton("PLAY SOLO", 1, startSolo)
	menuButton("PLAY WITH A FRIEND", 2, function() showOnly("coop"); resetCoopPanel() end)
else
	-- Reserved gameplay server (or a Studio test): a single Play runs the local ready-gate.
	menuButton("PLAY", 1, play)
	if isReserved then
		menuButton("LEAVE TO LOBBY", 2, returnToLobby)  -- back to the Solo/Co-op chooser
	end
end
menuButton("ENDINGS LOG", 3, function() showOnly("records"); refreshRecords() end)
menuButton("STORE", 4, function() showOnly("store"); refreshStore() end)
menuButton("LEADERBOARDS", 5, function() showOnly("leaderboard"); refreshLeaderboards() end)
menuButton("SETTINGS", 6, function() buildSettings(); showOnly("settings") end)
menuButton("CREDITS", 7, function() showOnly("credits") end)

-- in-game [L] records overlay (only during play, not in the main menu)
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.L and not inMenu then
		if gui.Enabled and recordsPanel.Visible then
			gui.Enabled = false; showOnly("none")
		else
			gui.Enabled = true; showOnly("records"); refreshRecords()
		end
	elseif input.KeyCode == Enum.KeyCode.Escape then
		if inMenu and not mainMenu.Visible then showOnly("main")
		elseif (not inMenu) and gui.Enabled then gui.Enabled = false; showOnly("none") end
	end
end)

-- ===================== init =====================
task.spawn(function()
	local ok, state = pcall(function() return Net.Func("GetGameState"):InvokeServer() end)
	if ok and state and type(state.settings) == "table" then
		for k, v in pairs(state.settings) do
			if settings[k] ~= nil and type(v) == "number" then settings[k] = v end
		end
	end
	applySettings()
end)

-- Co-op Half 2: in a RESERVED gameplay server we arrived by teleport with our mode
-- already chosen, so skip the menu and auto-run the ready-gate (the intro plays after
-- RunStarted). In the PUBLIC router (or a Studio test) we show the menu instead.
local autoStarting = false
local function autoStartReserved()
	autoStarting = true
	-- We skip the main menu here, so DD_MenuReady would never be set and IntroScreen's
	-- opaque join-black would hang (a "stuck black screen"). Set it so the intro fades
	-- in, then the prologue plays normally when the run begins.
	player:SetAttribute("DD_MenuReady", true)
	waitCancel.Visible = false          -- no "cancel to menu" here; the solo-fallback covers a no-show partner
	gui.Enabled = true
	showOnly("none")
	hideHud(true)
	setControls(false)
	task.spawn(function()
		local t0 = os.clock()
		while player:GetAttribute("InMenu") == nil and os.clock() - t0 < 10 do task.wait(0.1) end
		play()  -- ready up; shows "Waiting for your partner…" for co-op; intro on RunStarted
	end)
end

if isReserved then
	autoStartReserved()
else
	enterMenu()
end

-- Return to the menu when the server sends us back (death-screen Main Menu). Ignored
-- during the reserved auto-start (that first InMenu=true is just the boot state).
player:GetAttributeChangedSignal("InMenu"):Connect(function()
	if player:GetAttribute("InMenu") == true and not autoStarting then enterMenu() end
end)
player.CharacterAdded:Connect(function()
	if menuActive then task.wait(0.2); if menuActive then setControls(false) end end
end)
-- Once the run actually begins, drop the auto-start guard so a later post-run Main
-- Menu re-enters the menu normally.
Net.Event("RunStarted").OnClientEvent:Connect(function() autoStarting = false end)

-- ---- co-op matchmaking status + friend-invite handling ----
local waitInviteBtn: TextButton? = nil
local function showWaitInvite(on)
	if on and not waitInviteBtn then
		waitInviteBtn = Instance.new("TextButton")
		waitInviteBtn.AnchorPoint = Vector2.new(0.5, 0.5); waitInviteBtn.Position = UDim2.fromScale(0.5, 0.7)
		waitInviteBtn.Size = UDim2.fromOffset(220, 44); waitInviteBtn.BackgroundColor3 = Color3.fromRGB(30, 46, 40)
		waitInviteBtn.Font = Enum.Font.GothamMedium; waitInviteBtn.TextColor3 = Color3.fromRGB(210, 235, 215)
		waitInviteBtn.TextSize = 17; waitInviteBtn.Text = "INVITE A FRIEND"; waitInviteBtn.ZIndex = 81
		waitInviteBtn.Parent = waitOverlay
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = waitInviteBtn
		waitInviteBtn.MouseButton1Click:Connect(function() promptInvite(coopJoinKey) end)
	end
	if waitInviteBtn then waitInviteBtn.Visible = on end
end

Net.Event("MatchmakingStatus").OnClientEvent:Connect(function(info)
	local st = info and info.state
	if st == "inviteReady" then
		coopJoinKey = info.joinKey
		promptInvite(info.joinKey)
		showWaitInvite(true)
		return
	elseif st == "searching" then
		setCoopStatus(info.text or "Searching for a partner…"); coopCancel.Visible = true
	elseif st == "cancelled" then
		resetCoopPanel()
	elseif st == "loading" or st == "found" then
		if mmContext == "coop" then setCoopStatus(info.text or "…"); coopCancel.Visible = false
		else showConnecting(info.text or "…") end
	elseif st == "error" then
		if mmContext == "coop" then setCoopStatus(info.text or "Something went wrong."); coopCancel.Visible = false
		else showConnecting(info.text or "Something went wrong.", true) end
	end
end)

-- ===================== in-game pause menu (reserved gameplay servers) =====================
-- Press M during a run to open a small menu with "Return to Lobby", so players can get
-- back to the Solo/Co-op chooser without leaving. Own ScreenGui (independent of the main
-- menu's Enabled state); frees the cursor while open like the ballast puzzle. Reserved
-- servers only — Studio/public have no lobby to teleport to.
if isReserved then
	local pauseGui = Instance.new("ScreenGui")
	pauseGui.Name = "DeepDescentPause"; pauseGui.IgnoreGuiInset = true
	pauseGui.ResetOnSpawn = false; pauseGui.DisplayOrder = 70; pauseGui.Parent = pg

	local catcher = Instance.new("TextButton")
	catcher.Size = UDim2.fromScale(1, 1); catcher.BackgroundColor3 = Color3.new(0, 0, 0)
	catcher.BackgroundTransparency = 0.45; catcher.Text = ""; catcher.AutoButtonColor = false
	catcher.Visible = false; catcher.ZIndex = 1; catcher.Parent = pauseGui

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5); panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(320, 224); panel.BackgroundColor3 = Color3.fromRGB(16, 20, 24)
	panel.BackgroundTransparency = 0.05; panel.Visible = false; panel.ZIndex = 2; panel.Parent = pauseGui
	do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = panel end
	local pt = Instance.new("TextLabel")
	pt.Position = UDim2.fromOffset(0, 16); pt.Size = UDim2.new(1, 0, 0, 28); pt.BackgroundTransparency = 1
	pt.Font = Enum.Font.GothamBold; pt.TextColor3 = Color3.fromRGB(220, 228, 235); pt.TextSize = 20
	pt.Text = "PAUSED"; pt.ZIndex = 3; pt.Parent = panel

	local CURSOR_BIND = "DD_PauseCursor"
	local function setPauseOpen(open)
		panel.Visible = open; catcher.Visible = open
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

	local function pauseButton(text, y, colour, cb)
		local b = Instance.new("TextButton")
		b.AnchorPoint = Vector2.new(0.5, 0); b.Position = UDim2.new(0.5, 0, 0, y)
		b.Size = UDim2.fromOffset(260, 46); b.BackgroundColor3 = colour; b.AutoButtonColor = true
		b.Font = Enum.Font.GothamMedium; b.TextColor3 = Color3.fromRGB(228, 234, 240); b.TextSize = 17
		b.Text = text; b.ZIndex = 3; b.Parent = panel
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = b
		b.MouseButton1Click:Connect(cb)
		return b
	end
	pauseButton("RESUME", 56, Color3.fromRGB(28, 44, 40), function() setPauseOpen(false) end)
	pauseButton("RETURN TO LOBBY", 110, Color3.fromRGB(40, 46, 52), function()
		setPauseOpen(false); returnToLobby()
	end)
	local warn = Instance.new("TextLabel")
	warn.AnchorPoint = Vector2.new(0.5, 0); warn.Position = UDim2.new(0.5, 0, 0, 168)
	warn.Size = UDim2.new(1, -24, 0, 40); warn.BackgroundTransparency = 1; warn.Font = Enum.Font.Gotham
	warn.TextColor3 = Color3.fromRGB(150, 160, 170); warn.TextSize = 12; warn.TextWrapped = true
	warn.Text = "Returning to the lobby ends your current dive."; warn.ZIndex = 3; warn.Parent = panel

	catcher.MouseButton1Click:Connect(function() setPauseOpen(false) end)
	UserInputService.InputBegan:Connect(function(input, gp)
		if gp then return end
		if input.KeyCode == Enum.KeyCode.M and not inMenu then
			if panel.Visible then
				setPauseOpen(false)
			elseif not player:GetAttribute("UIModalOpen") then  -- don't open over the ballast puzzle
				setPauseOpen(true)
			end
		elseif input.KeyCode == Enum.KeyCode.Escape and panel.Visible then
			setPauseOpen(false)
		end
	end)
end
