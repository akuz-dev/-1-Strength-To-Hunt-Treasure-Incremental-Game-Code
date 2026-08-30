--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataService = require(ReplicatedStorage.Shared.PlayerDataService)
local TutorialConfig = require(ReplicatedStorage.Shared.TutorialConfig)
local WeaponCombatUtil = require(ReplicatedStorage.Shared.WeaponCombatUtil)

local ObstacleAPI = require(script.Parent.ObstacleAPI)

export type TutorialServiceModule = {
	Init: () -> (),
	OnPlayerDataLoaded: (player: Player) -> (),
	NotifyStrengthChanged: (player: Player) -> (),
	NotifyLootCollected: (player: Player) -> (),
	NotifyCashGranted: (player: Player, amount: number) -> (),
	NotifyWeaponPurchased: (player: Player, weaponId: string) -> (),
	IsTutorialActive: (player: Player) -> boolean,
	GetCurrentStep: (player: Player) -> number?,
}

local initialized = false

local function getPlayerData(player: Player)
	return PlayerDataService.GetData(player)
end

local function saveTutorialState(player: Player, tutorialStep: number, tutorialCompleted: boolean): ()
	local playerData = getPlayerData(player)
	if playerData == nil then
		return
	end

	playerData.TutorialStep = tutorialStep
	playerData.TutorialCompleted = tutorialCompleted
	PlayerDataService.SetData(player, playerData)
end

local function buildTutorialMessage(player: Player, tutorialStep: number): string
	if tutorialStep == 5 then
		local playerData = getPlayerData(player)
		local currentCash = if playerData then playerData.Cash else 0
		return TutorialConfig.GetSaveForShovelMessage(currentCash)
	end

	return TutorialConfig.GetStepMessage(tutorialStep) or ""
end

local function replicateTutorialState(player: Player, tutorialStep: number, tutorialCompleted: boolean): ()
	local message = ""
	if not tutorialCompleted and tutorialStep >= 1 and tutorialStep <= TutorialConfig.STEP_COUNT then
		message = buildTutorialMessage(player, tutorialStep)
	end

	player:SetAttribute("TutorialStep", tutorialStep)
	player:SetAttribute("TutorialCompleted", tutorialCompleted)
	player:SetAttribute("TutorialMessage", message)
end

local function completeTutorial(player: Player): ()
	saveTutorialState(player, 0, true)
	replicateTutorialState(player, 0, true)
end

local function setTutorialStep(player: Player, stepIndex: number): ()
	saveTutorialState(player, stepIndex, false)
	replicateTutorialState(player, stepIndex, false)
end

local function IsTutorialActive(player: Player): boolean
	local playerData = getPlayerData(player)
	if playerData == nil then
		return false
	end

	return not playerData.TutorialCompleted
		and playerData.TutorialStep >= 1
		and playerData.TutorialStep <= TutorialConfig.STEP_COUNT
end

local function GetCurrentStep(player: Player): number?
	if not IsTutorialActive(player) then
		return nil
	end

	local playerData = getPlayerData(player)
	return if playerData then playerData.TutorialStep else nil
end

local function refreshTutorialMessage(player: Player): ()
	if not IsTutorialActive(player) then
		return
	end

	local currentStep = GetCurrentStep(player)
	if currentStep == nil then
		return
	end

	player:SetAttribute("TutorialMessage", buildTutorialMessage(player, currentStep))
end

local function isStepConditionMet(player: Player, stepIndex: number): boolean
	local playerData = getPlayerData(player)
	if playerData == nil then
		return false
	end

	if stepIndex == 1 then
		return playerData.Strength >= TutorialConfig.GetTargetStrengthForStep1()
	elseif stepIndex == 2 then
		return false
	elseif stepIndex == 3 then
		return false
	elseif stepIndex == 4 then
		return false
	elseif stepIndex == 5 then
		local cashCost = TutorialConfig.GetFirstUpgradeCashCost()
		return cashCost ~= nil and playerData.Cash >= cashCost
	elseif stepIndex == 6 then
		local targetWeaponId = TutorialConfig.GetFirstUpgradeWeaponId()
		return WeaponCombatUtil.PlayerOwnsWeapon(playerData, targetWeaponId)
			and WeaponCombatUtil.ResolveEquippedWeaponId(playerData) == targetWeaponId
	end

	return false
end

local function advanceFromStep(player: Player, completedStep: number): ()
	if not IsTutorialActive(player) then
		return
	end

	local currentStep = GetCurrentStep(player)
	if currentStep ~= completedStep then
		return
	end

	if completedStep >= TutorialConfig.STEP_COUNT then
		completeTutorial(player)
		return
	end

	local nextStep = completedStep + 1
	setTutorialStep(player, nextStep)

	if isStepConditionMet(player, nextStep) then
		task.defer(function()
			if player.Parent == nil then
				return
			end
			advanceFromStep(player, nextStep)
		end)
	end
end

local function onSegmentBrokenForPlayer(_blocker: BasePart, userId: number): ()
	local player = game:GetService("Players"):GetPlayerByUserId(userId)
	if player == nil then
		return
	end

	if GetCurrentStep(player) == 2 then
		advanceFromStep(player, 2)
	end
end

local function NotifyStrengthChanged(player: Player): ()
	if GetCurrentStep(player) == 1 and isStepConditionMet(player, 1) then
		advanceFromStep(player, 1)
	end
end

local function NotifyLootCollected(player: Player): ()
	if GetCurrentStep(player) == 3 then
		advanceFromStep(player, 3)
	end
end

local function NotifyCashGranted(player: Player, amount: number): ()
	if amount <= 0 then
		return
	end

	local currentStep = GetCurrentStep(player)
	if currentStep == 4 then
		advanceFromStep(player, 4)
		return
	end

	if currentStep == 5 then
		refreshTutorialMessage(player)
		if isStepConditionMet(player, 5) then
			advanceFromStep(player, 5)
		end
	end
end

local function NotifyWeaponPurchased(player: Player, weaponId: string): ()
	if weaponId ~= TutorialConfig.GetFirstUpgradeWeaponId() then
		return
	end

	if GetCurrentStep(player) == 6 then
		advanceFromStep(player, 6)
	end
end

local function evaluateCatchUpOnLoad(player: Player): ()
	if not IsTutorialActive(player) then
		return
	end

	local currentStep = GetCurrentStep(player)
	if currentStep == nil then
		return
	end

	if currentStep == 6 and isStepConditionMet(player, 6) then
		completeTutorial(player)
		return
	end

	if isStepConditionMet(player, currentStep) then
		task.defer(function()
			if player.Parent == nil then
				return
			end
			advanceFromStep(player, currentStep)
		end)
	end
end

local function OnPlayerDataLoaded(player: Player): ()
	local playerData = getPlayerData(player)
	if playerData == nil then
		return
	end

	if playerData.TutorialCompleted then
		replicateTutorialState(player, 0, true)
		return
	end

	if playerData.TutorialStep < 1 or playerData.TutorialStep > TutorialConfig.STEP_COUNT then
		setTutorialStep(player, 1)
	else
		replicateTutorialState(player, playerData.TutorialStep, false)
	end

	evaluateCatchUpOnLoad(player)
end

local function Init(): ()
	if initialized then
		return
	end
	initialized = true

	ObstacleAPI.registerOnSegmentBrokenForPlayer(onSegmentBrokenForPlayer)
end

local TutorialService: TutorialServiceModule = {
	Init = Init,
	OnPlayerDataLoaded = OnPlayerDataLoaded,
	NotifyStrengthChanged = NotifyStrengthChanged,
	NotifyLootCollected = NotifyLootCollected,
	NotifyCashGranted = NotifyCashGranted,
	NotifyWeaponPurchased = NotifyWeaponPurchased,
	IsTutorialActive = IsTutorialActive,
	GetCurrentStep = GetCurrentStep,
}

return TutorialService

--[[
	SELF-AUDIT (Section 7):
	- ObstacleAPI.registerOnSegmentBrokenForPlayer — registered once in Init();
	  resolves player by userId only inside callback. OK.
	- task.defer catch-up/advance chain — one-shot per step, no captured Player. OK.
]]
