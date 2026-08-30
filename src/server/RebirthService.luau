--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataService = require(ReplicatedStorage.Shared.PlayerDataService)
local ProgressionConfig = require(ReplicatedStorage.Shared.ProgressionConfig)
local StrengthService = require(script.Parent.StrengthService)

export type RebirthService = {
	CanRebirth: (player: Player) -> boolean,
	PerformRebirth: (player: Player) -> boolean,
}

local function canRebirth(player: Player): boolean
	local playerData = PlayerDataService.GetData(player)
	if playerData == nil then
		return false
	end

	local requiredLevel = ProgressionConfig.GetNextRebirthGate(playerData.Rebirths)
	return playerData.Level >= requiredLevel
end

local function performRebirth(player: Player): boolean
	if not canRebirth(player) then
		return false
	end

	local playerData = PlayerDataService.GetData(player)
	if playerData == nil then
		return false
	end

	PlayerDataService.SetField(player, "Rebirths", playerData.Rebirths + 1)
	PlayerDataService.SetField(player, "Strength", ProgressionConfig.BaselineStrength)
	PlayerDataService.SetField(player, "Level", ProgressionConfig.BaselineLevel)
	PlayerDataService.SetField(player, "LevelProgress", ProgressionConfig.BaselineLevelProgress)
	StrengthService.SyncAttributes(player)

	return true
end

local RebirthService: RebirthService = {
	CanRebirth = canRebirth,
	PerformRebirth = performRebirth,
}

return RebirthService
