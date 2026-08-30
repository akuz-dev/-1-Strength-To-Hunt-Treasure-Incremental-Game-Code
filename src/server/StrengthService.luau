--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataService = require(ReplicatedStorage.Shared.PlayerDataService)
local ProgressionConfig = require(ReplicatedStorage.Shared.ProgressionConfig)
local StatUpgradeConfig = require(ReplicatedStorage.Shared.StatUpgradeConfig)

local TutorialService = require(script.Parent.TutorialService)

export type StrengthService = {
	AddStrength: (player: Player, amount: number) -> boolean,
	SyncAttributes: (player: Player) -> (),
}

local function syncAttributes(player: Player): ()
	local playerData = PlayerDataService.GetData(player)
	if playerData == nil then
		return
	end

	local levels = playerData.StatLevels
	player:SetAttribute("Strength", playerData.Strength)
	player:SetAttribute("Level", playerData.Level)
	player:SetAttribute("LevelProgress", playerData.LevelProgress)
	player:SetAttribute("AgilityLevel", levels.Agility)
	player:SetAttribute("RangeLevel", levels.Range)
	player:SetAttribute("CapacityLevel", levels.Capacity)
	player:SetAttribute("WalkSpeedLevel", levels.WalkSpeed)
	player:SetAttribute("Rebirths", playerData.Rebirths)
	player:SetAttribute("Cash", playerData.Cash)
	player:SetAttribute("MaxCapacity", StatUpgradeConfig.GetEffectiveCapacity(levels.Capacity))
	player:SetAttribute("TripCarryCount", 0)
end

local function checkLevelUp(player: Player, levelProgress: number, level: number): (number, number)
	while true do
		local strengthRequired = ProgressionConfig.StrengthRequired(level + 1)
		if strengthRequired <= 0 or levelProgress < strengthRequired then
			break
		end

		levelProgress -= strengthRequired
		level += 1
	end

	return levelProgress, level
end

local function addStrength(player: Player, amount: number): boolean
	if amount <= 0 then
		return false
	end

	local playerData = PlayerDataService.GetData(player)
	if playerData == nil then
		return false
	end

	local newStrength = playerData.Strength + amount
	local levelProgress = playerData.LevelProgress + amount
	local level = playerData.Level

	levelProgress, level = checkLevelUp(player, levelProgress, level)

	PlayerDataService.SetField(player, "Strength", newStrength)
	PlayerDataService.SetField(player, "LevelProgress", levelProgress)
	PlayerDataService.SetField(player, "Level", level)
	player:SetAttribute("Strength", newStrength)
	player:SetAttribute("LevelProgress", levelProgress)
	player:SetAttribute("Level", level)

	TutorialService.NotifyStrengthChanged(player)

	return true
end

local StrengthService: StrengthService = {
	AddStrength = addStrength,
	SyncAttributes = syncAttributes,
}

return StrengthService
