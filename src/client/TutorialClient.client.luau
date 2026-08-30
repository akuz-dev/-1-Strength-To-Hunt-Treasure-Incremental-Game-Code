--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TutorialConfig = require(ReplicatedStorage.Shared.TutorialConfig)
local TutorialNotification = require(script.Parent.TutorialNotification)

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local NOTIFICATIONS_GUI_NAME = "Notifications"

local strengthProgressConnection: RBXScriptConnection? = nil
local cashProgressConnection: RBXScriptConnection? = nil
local lastShownStep: number? = nil
local lastShownMessage = ""

local function disconnectStrengthProgress(): ()
	if strengthProgressConnection then
		strengthProgressConnection:Disconnect()
		strengthProgressConnection = nil
	end
end

local function disconnectCashProgress(): ()
	if cashProgressConnection then
		cashProgressConnection:Disconnect()
		cashProgressConnection = nil
	end
end

local function formatStep1Message(baseMessage: string): string
	local strength = player:GetAttribute("Strength")
	if typeof(strength) ~= "number" then
		return baseMessage
	end

	local target = TutorialConfig.GetTargetStrengthForStep1()
	local clampedStrength = math.min(strength, target)
	return `{baseMessage} ({clampedStrength}/{target})`
end

local function logTutorialShown(tutorialStep: number, displayMessage: string): ()
	if lastShownStep == tutorialStep and lastShownMessage == displayMessage then
		return
	end

	lastShownStep = tutorialStep
	lastShownMessage = displayMessage
	print(`[TutorialClient] Showing step {tutorialStep}: "{displayMessage}"`)
end

local function bindStep1StrengthProgress(baseMessage: string): ()
	disconnectStrengthProgress()

	local function refreshProgress(): ()
		local currentStep = player:GetAttribute("TutorialStep")
		if typeof(currentStep) ~= "number" or currentStep ~= 1 then
			disconnectStrengthProgress()
			return
		end

		local displayMessage = formatStep1Message(baseMessage)
		TutorialNotification.Show(displayMessage)
		logTutorialShown(1, displayMessage)
	end

	strengthProgressConnection = player:GetAttributeChangedSignal("Strength"):Connect(refreshProgress)
	refreshProgress()
end

local function bindStep5CashProgress(): ()
	disconnectCashProgress()

	local function refreshProgress(): ()
		local currentStep = player:GetAttribute("TutorialStep")
		if typeof(currentStep) ~= "number" or currentStep ~= 5 then
			disconnectCashProgress()
			return
		end

		local cash = player:GetAttribute("Cash")
		local currentCash = if typeof(cash) == "number" then cash else 0
		local displayMessage = TutorialConfig.GetSaveForShovelMessage(currentCash)
		TutorialNotification.Show(displayMessage)
		logTutorialShown(5, displayMessage)
	end

	cashProgressConnection = player:GetAttributeChangedSignal("Cash"):Connect(refreshProgress)
	refreshProgress()
end

local function applyTutorialState(): ()
	local tutorialCompleted = player:GetAttribute("TutorialCompleted")
	if tutorialCompleted == true then
		disconnectStrengthProgress()
		disconnectCashProgress()
		lastShownStep = nil
		lastShownMessage = ""
		TutorialNotification.Hide()
		return
	end

	local tutorialStep = player:GetAttribute("TutorialStep")
	if typeof(tutorialStep) ~= "number" or tutorialStep < 1 or tutorialStep > TutorialConfig.STEP_COUNT then
		disconnectStrengthProgress()
		disconnectCashProgress()
		lastShownStep = nil
		lastShownMessage = ""
		TutorialNotification.Hide()
		return
	end

	local message = player:GetAttribute("TutorialMessage")
	local displayMessage = if typeof(message) == "string" and message ~= ""
		then message
		else TutorialConfig.GetStepMessage(tutorialStep) or ""

	if displayMessage == "" then
		disconnectStrengthProgress()
		disconnectCashProgress()
		lastShownStep = nil
		lastShownMessage = ""
		TutorialNotification.Hide()
		return
	end

	if tutorialStep == 1 then
		disconnectCashProgress()
		bindStep1StrengthProgress(displayMessage)
	elseif tutorialStep == 5 then
		disconnectStrengthProgress()
		bindStep5CashProgress()
	else
		disconnectStrengthProgress()
		disconnectCashProgress()
		TutorialNotification.Show(displayMessage)
		logTutorialShown(tutorialStep, displayMessage)
	end
end

local function onPlayerGuiChildAdded(child: Instance): ()
	if child.Name == NOTIFICATIONS_GUI_NAME and child:IsA("ScreenGui") then
		TutorialNotification.Invalidate()
		applyTutorialState()
	end
end

player:GetAttributeChangedSignal("TutorialStep"):Connect(applyTutorialState)
player:GetAttributeChangedSignal("TutorialMessage"):Connect(applyTutorialState)
player:GetAttributeChangedSignal("TutorialCompleted"):Connect(applyTutorialState)
playerGui.ChildAdded:Connect(onPlayerGuiChildAdded)

task.spawn(function()
	TutorialNotification.WaitForReady()
	applyTutorialState()
end)

--[[
	SELF-AUDIT (Section 7):
	- GetAttributeChangedSignal (TutorialStep/Message/Completed) — script-lifetime
	  singleton on LocalPlayer; closes over LocalPlayer only. OK.
	- PlayerGui.ChildAdded:Connect — script-lifetime; re-resolves Notifications after re-clone. OK.
	- Strength progress connection — disconnected when leaving step 1 or tutorial ends. OK.
	- Cash progress connection — disconnected when leaving step 5 or tutorial ends. OK.
	- task.spawn WaitForReady + applyTutorialState — one-shot bootstrap, no polling loop. OK.
]]
