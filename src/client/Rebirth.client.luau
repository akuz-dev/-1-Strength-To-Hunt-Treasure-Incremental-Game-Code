--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local ProgressionConfig = require(ReplicatedStorage.Shared.ProgressionConfig)
local UIJuice = require(script.Parent.UIJuice)

local UI_WAIT_TIMEOUT = 5
local REMOTES_FOLDER_NAME = "Remotes"
local REBIRTH_REMOTE_NAME = "Rebirth"
local REMOTE_WAIT_TIMEOUT = 5
local UI_OPEN_CLOSE_SOUND_PATH = { "Assets", "Sounds", "UiOpenClose" }
local REBIRTH_GUI_NAME = "Rebirth"
local HUD_REBIRTH_PERCENT_NAME = "RebirthPercent"
local TEMPLATES_FOLDER_NAME = "Templates"
local CLOSE_BUTTON_NAME = "CloseButton"
local FILL_TWEEN_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function findRebirthGui(root: Instance): ScreenGui?
	local directChild = root:FindFirstChild("Rebirth")
	if directChild and directChild:IsA("ScreenGui") then
		return directChild
	end

	for _, descendant in root:GetDescendants() do
		if descendant.Name == "Rebirth" and descendant:IsA("ScreenGui") then
			return descendant
		end
	end

	return nil
end

local function waitForRebirthGui(): ScreenGui
	while true do
		local existing = findRebirthGui(playerGui)
		if existing then
			return existing
		end

		playerGui.ChildAdded:Wait()
	end
end

local function findDescendantOfClass<T>(root: Instance, name: string, className: string): T?
	local found = root:FindFirstChild(name, true)
	if found and found:IsA(className) then
		return found :: any
	end

	return nil
end

local function isUnderNamedFolder(instance: Instance, root: Instance, folderName: string): boolean
	local parent = instance.Parent
	while parent and parent ~= root do
		if parent.Name == folderName then
			return true
		end
		parent = parent.Parent
	end

	return false
end

local function findCloseButton(root: Instance): GuiButton?
	for _, descendant in root:GetDescendants() do
		if descendant.Name == CLOSE_BUTTON_NAME and descendant:IsA("GuiButton") then
			if not isUnderNamedFolder(descendant, root, TEMPLATES_FOLDER_NAME) then
				return descendant
			end
		end
	end

	return nil
end

local function resolveUiOpenCloseSound(): Sound?
	local current: Instance = ReplicatedStorage
	for _, childName in UI_OPEN_CLOSE_SOUND_PATH do
		local child = current:WaitForChild(childName, REMOTE_WAIT_TIMEOUT)
		if child == nil then
			warn(`[Rebirth] Sound path missing "{childName}" within {REMOTE_WAIT_TIMEOUT}s`)
			return nil
		end
		current = child
	end

	if not current:IsA("Sound") then
		warn("[Rebirth] UiOpenClose asset is not a Sound")
		return nil
	end

	return current
end

local rebirthGui = waitForRebirthGui()

local outerFrame = rebirthGui:WaitForChild("Frame", UI_WAIT_TIMEOUT)
local mainContent = if outerFrame then outerFrame:WaitForChild("MainContent", UI_WAIT_TIMEOUT) else nil
local contentFrame = if mainContent then mainContent:WaitForChild("Frame", UI_WAIT_TIMEOUT) else nil

if contentFrame == nil then
	warn(`[Rebirth] Rebirth UI hierarchy not found within {UI_WAIT_TIMEOUT}s`)
	return
end

local beforeSection = contentFrame:WaitForChild("Before", UI_WAIT_TIMEOUT)
local afterSection = contentFrame:WaitForChild("After", UI_WAIT_TIMEOUT)

if beforeSection == nil or afterSection == nil then
	warn(`[Rebirth] Before/After sections not found within {UI_WAIT_TIMEOUT}s`)
	return
end

local beforeStrengthMulti = findDescendantOfClass(beforeSection, "BeforeStrengthMulti", "TextLabel")
local beforeCashMulti = findDescendantOfClass(beforeSection, "BeforeCashMulti", "TextLabel")
local afterStrengthMulti = findDescendantOfClass(afterSection, "AfterStrengthMulti", "TextLabel")
local afterCashMulti = findDescendantOfClass(afterSection, "AfterCashMulti", "TextLabel")
local levelCounter = findDescendantOfClass(contentFrame, "LevelCounter", "TextLabel")
local levelIndicator = findDescendantOfClass(contentFrame, "LevelIndicator", "TextLabel")
local fillBar = findDescendantOfClass(contentFrame, "FillBar", "Frame")
local rebirthButton = findDescendantOfClass(contentFrame, "RebirthButton", "GuiButton")

if rebirthButton == nil then
	rebirthButton = findDescendantOfClass(rebirthGui, "RebirthButton", "GuiButton")
end

local missingRebirthUiElementNames: { string } = {}
if beforeStrengthMulti == nil then
	table.insert(missingRebirthUiElementNames, "BeforeStrengthMulti")
end
if beforeCashMulti == nil then
	table.insert(missingRebirthUiElementNames, "BeforeCashMulti")
end
if afterStrengthMulti == nil then
	table.insert(missingRebirthUiElementNames, "AfterStrengthMulti")
end
if afterCashMulti == nil then
	table.insert(missingRebirthUiElementNames, "AfterCashMulti")
end
if levelCounter == nil then
	table.insert(missingRebirthUiElementNames, "LevelCounter")
end
if fillBar == nil then
	table.insert(missingRebirthUiElementNames, "FillBar")
end
if rebirthButton == nil then
	table.insert(missingRebirthUiElementNames, "RebirthButton")
end

if #missingRebirthUiElementNames > 0 then
	warn(`[Rebirth] Missing Rebirth UI element(s): {table.concat(missingRebirthUiElementNames, ", ")}`)
	return
end

local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME, REMOTE_WAIT_TIMEOUT)
if remotesFolder == nil then
	warn(`[Rebirth] Remotes folder not found within {REMOTE_WAIT_TIMEOUT}s`)
	return
end

local rebirthRemote = remotesFolder:WaitForChild(REBIRTH_REMOTE_NAME, REMOTE_WAIT_TIMEOUT)
if rebirthRemote == nil or not rebirthRemote:IsA("RemoteEvent") then
	warn(`[Rebirth] Rebirth RemoteEvent not found within {REMOTE_WAIT_TIMEOUT}s`)
	return
end

local function getStatValue(attributeName: string): number?
	local value = player:GetAttribute(attributeName)
	if typeof(value) == "number" then
		return value
	end

	return nil
end

local activeFillTween: Tween? = nil
local pendingFillScale: number? = nil
local fillCoalesceConnection: RBXScriptConnection? = nil

local fillBarXOffset = fillBar.Size.X.Offset
local fillBarYScale = fillBar.Size.Y.Scale
local fillBarYOffset = fillBar.Size.Y.Offset

local function buildFillBarSize(fillScale: number): UDim2
	return UDim2.new(fillScale, fillBarXOffset, fillBarYScale, fillBarYOffset)
end

local function cancelActiveFillTween(): ()
	if activeFillTween then
		activeFillTween:Cancel()
		activeFillTween = nil
	end
end

local function cancelFillCoalesce(): ()
	if fillCoalesceConnection then
		fillCoalesceConnection:Disconnect()
		fillCoalesceConnection = nil
	end
end

local function tweenFillBarTo(targetScale: number): ()
	cancelActiveFillTween()

	local tween = TweenService:Create(fillBar, FILL_TWEEN_INFO, {
		Size = buildFillBarSize(targetScale),
	})
	activeFillTween = tween
	tween:Play()
end

local function scheduleFillBarTween(targetScale: number): ()
	pendingFillScale = targetScale

	if fillCoalesceConnection then
		return
	end

	fillCoalesceConnection = RunService.Heartbeat:Connect(function()
		cancelFillCoalesce()

		local scale = pendingFillScale
		pendingFillScale = nil
		if scale ~= nil then
			tweenFillBarTo(scale)
		end
	end)
end

local function setFillBarInstant(targetScale: number): ()
	cancelActiveFillTween()
	cancelFillCoalesce()
	pendingFillScale = nil
	fillBar.Size = buildFillBarSize(targetScale)
end

local function canRebirth(level: number, rebirths: number): boolean
	local requiredLevel = ProgressionConfig.GetNextRebirthGate(rebirths)
	return level >= requiredLevel
end

local function updateRebirthUi(instantFill: boolean): ()
	local level = getStatValue("Level")
	local rebirths = getStatValue("Rebirths")
	if level == nil or rebirths == nil then
		return
	end

	local requiredLevel = ProgressionConfig.GetNextRebirthGate(rebirths)
	local fillScale = if requiredLevel > 0 then math.clamp(level / requiredLevel, 0, 1) else 0

	beforeStrengthMulti.Text =
		`Strength {ProgressionConfig.FormatMultiplier(ProgressionConfig.GetStrengthGainMultiplier(rebirths))}`
	beforeCashMulti.Text =
		`Cash Multi {ProgressionConfig.FormatMultiplier(ProgressionConfig.GetCashGainMultiplier(rebirths))}`
	afterStrengthMulti.Text =
		`Strength {ProgressionConfig.FormatMultiplier(ProgressionConfig.GetStrengthGainMultiplier(rebirths + 1))}`
	afterCashMulti.Text =
		`Cash Multi {ProgressionConfig.FormatMultiplier(ProgressionConfig.GetCashGainMultiplier(rebirths + 1))}`
	levelCounter.Text = `Level {NumberFormatter.Format(level)}`
	if levelIndicator then
		levelIndicator.Text = `{NumberFormatter.Format(level)}/{NumberFormatter.Format(requiredLevel)}`
	end
	rebirthButton.Active = canRebirth(level, rebirths)

	if instantFill then
		setFillBarInstant(fillScale)
	else
		scheduleFillBarTween(fillScale)
	end
end

local function onRebirthStatsChanged(): ()
	updateRebirthUi(false)
end

rebirthButton.MouseButton1Click:Connect(function()
	rebirthRemote:FireServer()
end)

player:GetAttributeChangedSignal("Level"):Connect(onRebirthStatsChanged)
player:GetAttributeChangedSignal("Rebirths"):Connect(onRebirthStatsChanged)
updateRebirthUi(true)

local function freezeMenuTextLabels(root: Instance): ()
	for _, descendant in root:GetDescendants() do
		if not descendant:IsA("TextLabel") then
			continue
		end

		local label = descendant :: TextLabel
		if label.AutomaticSize == Enum.AutomaticSize.None then
			continue
		end

		local parent = label.Parent
		if parent and parent:IsA("GuiObject") then
			local parentSize = parent.AbsoluteSize
			if parentSize.X > 0 and parentSize.Y > 0 then
				local absSize = label.AbsoluteSize
				label.Size = UDim2.new(absSize.X / parentSize.X, 0, absSize.Y / parentSize.Y, 0)
			end
		end
		label.AutomaticSize = Enum.AutomaticSize.None
	end
end

-- Rebirth menu: static root Size, UIScale grow + CanvasGroup fade, toggle open/close
local menuButtonSound: Sound? = nil -- TODO: pass your button-click Sound template here
local uiOpenCloseSound = resolveUiOpenCloseSound()
local activeRebirthGui: ScreenGui? = nil
local activeOuterFrame: Frame? = nil
local wiredRebirthMenuGuis: { [ScreenGui]: boolean } = {}

local function closeRebirthMenu(): ()
	local gui = activeRebirthGui
	local frame = activeOuterFrame
	if gui == nil or frame == nil then
		return
	end

	UIJuice.RequestCloseMenu(frame, uiOpenCloseSound, function()
		gui.Enabled = false
	end, gui.Enabled)
end

local function toggleRebirthMenu(): ()
	local gui = activeRebirthGui
	local frame = activeOuterFrame
	if gui == nil or frame == nil then
		return
	end

	gui.Enabled = true
	local isOpen = UIJuice.ToggleMenu(frame, uiOpenCloseSound, uiOpenCloseSound, function()
		gui.Enabled = false
	end)
	if not isOpen and UIJuice.GetMenuPhase(frame) == "closed" then
		gui.Enabled = false
	end
end

local function setupRebirthMenuShell(gui: ScreenGui): ()
	if wiredRebirthMenuGuis[gui] then
		return
	end

	local frame = gui:WaitForChild("Frame", UI_WAIT_TIMEOUT)
	if frame == nil or not frame:IsA("Frame") then
		warn(`[Rebirth] Frame not found under {REBIRTH_GUI_NAME} within {UI_WAIT_TIMEOUT}s`)
		return
	end

	wiredRebirthMenuGuis[gui] = true
	activeRebirthGui = gui
	activeOuterFrame = frame
	gui.Enabled = false

	freezeMenuTextLabels(frame)

	local staleBackdrop = gui:FindFirstChild("Backdrop")
	if staleBackdrop then
		staleBackdrop:Destroy()
	end

	UIJuice.WireMenuButtons(gui, menuButtonSound)
	UIJuice.EnsureMenuUIScale(frame)
	UIJuice.EnsureMenuCanvasGroup(frame)

	local closeButton = findCloseButton(gui)
	if closeButton then
		closeButton.Activated:Connect(closeRebirthMenu)
	else
		warn(`[Rebirth] {CLOSE_BUTTON_NAME} GuiButton not found under {REBIRTH_GUI_NAME}`)
	end

	gui.Destroying:Once(function()
		wiredRebirthMenuGuis[gui] = nil
		if activeRebirthGui == gui then
			activeRebirthGui = nil
			activeOuterFrame = nil
		end
	end)
end

setupRebirthMenuShell(rebirthGui)

playerGui.ChildAdded:Connect(function(child: Instance)
	if child.Name == REBIRTH_GUI_NAME and child:IsA("ScreenGui") then
		setupRebirthMenuShell(child)
	end
end)

local hudButtonsGui = playerGui:WaitForChild("HUDButtons", UI_WAIT_TIMEOUT)
local hudButtonsFrame = if hudButtonsGui then hudButtonsGui:WaitForChild("Buttons", UI_WAIT_TIMEOUT) else nil
local hudRebirthButton = if hudButtonsFrame
	then hudButtonsFrame:WaitForChild("RebirthButton", UI_WAIT_TIMEOUT)
	else nil

if hudRebirthButton and hudRebirthButton:IsA("GuiButton") then
	UIJuice.PulseButton(hudRebirthButton, menuButtonSound)
	hudRebirthButton.Activated:Connect(toggleRebirthMenu)
end

local hudRebirthPercentLabel = if hudRebirthButton
	then hudRebirthButton:WaitForChild(HUD_REBIRTH_PERCENT_NAME, UI_WAIT_TIMEOUT)
	else nil

if hudRebirthPercentLabel == nil or not hudRebirthPercentLabel:IsA("TextLabel") then
	warn(`[Rebirth] {HUD_REBIRTH_PERCENT_NAME} TextLabel not found within {UI_WAIT_TIMEOUT}s`)
	hudRebirthPercentLabel = nil
end

local function updateHudRebirthPercent(): ()
	if hudRebirthPercentLabel == nil then
		return
	end

	local level = getStatValue("Level")
	local rebirths = getStatValue("Rebirths")
	if level == nil or rebirths == nil then
		return
	end

	local requiredLevel = ProgressionConfig.GetNextRebirthGate(rebirths)
	local percent = if requiredLevel > 0 then math.clamp(level / requiredLevel, 0, 1) * 100 else 0

	(hudRebirthPercentLabel :: TextLabel).Text = `{math.floor(percent)}%`
end

if hudRebirthPercentLabel then
	player:GetAttributeChangedSignal("Level"):Connect(updateHudRebirthPercent)
	player:GetAttributeChangedSignal("Rebirths"):Connect(updateHudRebirthPercent)
	updateHudRebirthPercent()
end

--[[ SELF-AUDIT (Section 7):
  hudRebirthButton.Activated, closeButton.Activated — wired per ScreenGui clone; Destroying clears active refs. OK.
  PlayerGui.ChildAdded:Connect — re-wires menu shell after ResetOnSpawn re-clone. OK.
  WireMenuButtons DescendantAdded disconnected on rebirthGui Destroying via UIJuice. OK.
  GetAttributeChangedSignal Level/Rebirths (HUD percent label) — permanent player-lifetime connections. OK. ]]
