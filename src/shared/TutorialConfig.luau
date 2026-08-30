--!strict

local WeaponConfig = require(script.Parent.WeaponConfig)

export type TutorialStepDef = {
	Id: string,
	Message: string,
}

export type TutorialConfigModule = {
	STEP_COUNT: number,
	STEPS: { TutorialStepDef },
	GetStepMessage: (stepIndex: number) -> string?,
	GetSaveForShovelMessage: (currentCash: number) -> string,
	GetTargetStrengthForStep1: () -> number,
	GetFirstUpgradeWeaponId: () -> string,
	GetFirstUpgradeCashCost: () -> number?,
	GetRemainingCashForFirstUpgrade: (currentCash: number) -> number?,
}

local TARGET_STRENGTH_STEP_1 = 20

local STEPS: { TutorialStepDef } = {
	{ Id = "GainStrength", Message = "Press to gain 20 strength" },
	{ Id = "ClearSand", Message = "Shovel sand to clear the area" },
	{ Id = "CollectLoot", Message = "Dig to the loot to pick it up" },
	{ Id = "SellLoot", Message = "Sell the loot you collected" },
	{ Id = "SaveForShovel", Message = "Save money for a better shovel" },
	{ Id = "BuyShovel", Message = "Buy a better shovel" },
}

local function GetFirstUpgradeWeaponId(): string
	local weaponOrder = WeaponConfig.WeaponOrder
	for _, weaponId in weaponOrder do
		local weaponDef = WeaponConfig.GetWeapon(weaponId)
		if weaponDef and not weaponDef.IsStarter then
			return weaponId
		end
	end

	return "IronShovel"
end

local function GetFirstUpgradeCashCost(): number?
	return WeaponConfig.GetCashCost(GetFirstUpgradeWeaponId())
end

local function GetRemainingCashForFirstUpgrade(currentCash: number): number?
	local cashCost = GetFirstUpgradeCashCost()
	if cashCost == nil then
		return nil
	end

	return math.max(0, cashCost - currentCash)
end

local function GetSaveForShovelMessage(currentCash: number): string
	local stepDef = STEPS[5]
	local baseMessage = if stepDef then stepDef.Message else "Save money for a better shovel"
	local remaining = GetRemainingCashForFirstUpgrade(currentCash)
	if remaining == nil then
		return baseMessage
	end

	if currentCash > 0 then
		return `{baseMessage} ({remaining} more Cash)`
	end

	return `{baseMessage} ({remaining} Cash)`
end

local function GetStepMessage(stepIndex: number): string?
	local stepDef = STEPS[stepIndex]
	if stepDef == nil then
		return nil
	end

	if stepDef.Id == "SaveForShovel" then
		return GetSaveForShovelMessage(0)
	end

	return stepDef.Message
end

local TutorialConfig: TutorialConfigModule = {
	STEP_COUNT = #STEPS,
	STEPS = STEPS,
	GetStepMessage = GetStepMessage,
	GetSaveForShovelMessage = GetSaveForShovelMessage,
	GetTargetStrengthForStep1 = function(): number
		return TARGET_STRENGTH_STEP_1
	end,
	GetFirstUpgradeWeaponId = GetFirstUpgradeWeaponId,
	GetFirstUpgradeCashCost = GetFirstUpgradeCashCost,
	GetRemainingCashForFirstUpgrade = GetRemainingCashForFirstUpgrade,
}

return TutorialConfig
