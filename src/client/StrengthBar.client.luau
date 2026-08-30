--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local ProgressionConfig = require(ReplicatedStorage.Shared.ProgressionConfig)
local UIJuice = require(script.Parent.UIJuice)

local UI_WAIT_TIMEOUT = 5
local FILL_TWEEN_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local BAR_ABBREV_THRESHOLD = 1000
local BAR_ABBREV_DECIMALS = 2

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function findStrengthBar(root: Instance): ScreenGui?
	local directChild = root:FindFirstChild("StrengthBar")
	if directChild and directChild:IsA("ScreenGui") then
		return directChild
	end

	for _, descendant in root:GetDescendants() do
		if descendant.Name == "StrengthBar" and descendant:IsA("ScreenGui") then
			return descendant
		end
	end

	return nil
end

local function waitForStrengthBar(): ScreenGui
	while true do
		local existing = findStrengthBar(playerGui)
		if existing then
			return existing
		end

		playerGui.ChildAdded:Wait()
	end
end

local strengthBar = waitForStrengthBar()

local topBar = strengthBar:WaitForChild("TopBar", UI_WAIT_TIMEOUT)
if topBar == nil then
	warn(`[StrengthBar] TopBar not found within {UI_WAIT_TIMEOUT}s`)
	return
end

local fillBar = topBar:WaitForChild("FillBar", UI_WAIT_TIMEOUT)
local strengthText = topBar:WaitForChild("StrengthText", UI_WAIT_TIMEOUT)
local strengthGoalLevelRequirement = topBar:WaitForChild("StrengthGoalLevelRequirement", UI_WAIT_TIMEOUT)
local levelCounter = topBar:WaitForChild("LevelCounter", UI_WAIT_TIMEOUT)

if
	fillBar == nil
	or strengthText == nil
	or strengthGoalLevelRequirement == nil
	or levelCounter == nil
then
	warn(`[StrengthBar] One or more TopBar UI elements not found within {UI_WAIT_TIMEOUT}s`)
	return
end

if not fillBar:IsA("Frame") then
	warn("[StrengthBar] FillBar is not a Frame")
	return
end

if not strengthGoalLevelRequirement:IsA("TextLabel") then
	warn("[StrengthBar] StrengthGoalLevelRequirement is not a TextLabel")
	return
end

if not levelCounter:IsA("TextLabel") then
	warn("[StrengthBar] LevelCounter is not a TextLabel")
	return
end

local strengthTotal = strengthText:WaitForChild("StrengthTotal", UI_WAIT_TIMEOUT)
if strengthTotal == nil or not strengthTotal:IsA("TextLabel") then
	warn(`[StrengthBar] StrengthTotal TextLabel not found within {UI_WAIT_TIMEOUT}s`)
	return
end

local topBarImg = topBar:WaitForChild("TopBarImg", UI_WAIT_TIMEOUT)
if topBarImg == nil or not topBarImg:IsA("GuiObject") then
	warn(`[StrengthBar] TopBarImg not found within {UI_WAIT_TIMEOUT}s; pulse disabled`)
end

local function getStatValue(attributeName: string): number?
	local value = player:GetAttribute(attributeName)
	if typeof(value) == "number" then
		return value
	end

	return nil
end

local function formatBarNumber(value: number): string
	if value < BAR_ABBREV_THRESHOLD then
		return NumberFormatter.Format(value)
	end

	return NumberFormatter.Format(value, { Decimals = BAR_ABBREV_DECIMALS })
end

local activeFillTween: Tween? = nil
local pendingFillScale: number? = nil
local fillCoalesceConnection: RBXScriptConnection? = nil
local pendingBarUpdate = false
local barUpdateCoalesceConnection: RBXScriptConnection? = nil

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

local lastStrength = getStatValue("Strength") or 0
local lastLevel = getStatValue("Level") or 0

local function cancelBarUpdateCoalesce(): ()
	if barUpdateCoalesceConnection then
		barUpdateCoalesceConnection:Disconnect()
		barUpdateCoalesceConnection = nil
	end
end

local function updateStrengthBar(instantFill: boolean): ()
	local strength = getStatValue("Strength")
	local level = getStatValue("Level")
	local levelProgress = getStatValue("LevelProgress")
	if strength == nil or level == nil or levelProgress == nil then
		return
	end

	local levelChanged = level ~= lastLevel
	lastLevel = level

	local requiredForNext = ProgressionConfig.StrengthRequired(level + 1)
	local fillScale = if requiredForNext > 0
		then math.clamp(levelProgress / requiredForNext, 0, 1)
		else 0

	strengthTotal.Text = `{formatBarNumber(strength)} Strength`
	strengthGoalLevelRequirement.Text =
		`{formatBarNumber(levelProgress)}/{formatBarNumber(requiredForNext)}`
	levelCounter.Text = `Level {formatBarNumber(level)}`

	if instantFill or levelChanged then
		setFillBarInstant(fillScale)
	else
		scheduleFillBarTween(fillScale)
	end
end

local function flushBarUpdate(): ()
	cancelBarUpdateCoalesce()
	pendingBarUpdate = false

	local strength = getStatValue("Strength")
	if strength ~= nil and strength > lastStrength and topBarImg then
		UIJuice.PulseGui(topBarImg)
	end
	if strength ~= nil then
		lastStrength = strength
	end

	updateStrengthBar(false)
end

local function scheduleBarUpdate(): ()
	pendingBarUpdate = true

	if barUpdateCoalesceConnection then
		return
	end

	barUpdateCoalesceConnection = RunService.Heartbeat:Connect(function()
		if not pendingBarUpdate then
			return
		end

		flushBarUpdate()
	end)
end

local function onStrengthOrLevelChanged(): ()
	scheduleBarUpdate()
end

player:GetAttributeChangedSignal("Strength"):Connect(onStrengthOrLevelChanged)
player:GetAttributeChangedSignal("Level"):Connect(onStrengthOrLevelChanged)
player:GetAttributeChangedSignal("LevelProgress"):Connect(onStrengthOrLevelChanged)
updateStrengthBar(true)

--[[ SELF-AUDIT (Section 7):
  GetAttributeChangedSignal Strength/Level/LevelProgress — permanent player-lifetime connections. OK.
  RunService.Heartbeat:Connect (fill coalesce / bar update coalesce) — stored and disconnected on
    flush/cancel; closes over no long-lived foreign Instances beyond LocalPlayer UI refs. OK.
  PulseGui driven only by Strength increase; no polling loops. OK. ]]
