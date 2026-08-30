--!strict

local DataStoreManagerEvents = require(script.Parent.DataStoreManager)
local StrengthService = require(script.Parent.StrengthService)
local StatUpgradeService = require(script.Parent.StatUpgradeService)
local WeaponShopService = require(script.Parent.WeaponShopService)
local WeaponEquipService = require(script.Parent.WeaponEquipService)
local TutorialService = require(script.Parent.TutorialService)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerDataService = require(ReplicatedStorage.Shared.PlayerDataService)

local function onPlayerDataLoaded(player: Player): ()
	WeaponShopService.SyncWeaponShopAttributes(player)
	WeaponEquipService.SyncEquippedWeaponVisual(player)
	StrengthService.SyncAttributes(player)
	StatUpgradeService.ApplyWalkSpeed(player)
	TutorialService.OnPlayerDataLoaded(player)
end

-- Fired by DataStoreManager once a PlayerRemoving save attempt has
-- finished (success or exhausted retries). Clearing here — rather than
-- from a separate PlayerRemoving connection in this script — guarantees
-- cleanup can never run before the save it depends on.
local function onPlayerDataSaved(player: Player): ()
	PlayerDataService.ClearData(player)
end

StatUpgradeService.InitCharacterHooks()
TutorialService.Init()

DataStoreManagerEvents.PlayerDataLoaded.Event:Connect(onPlayerDataLoaded)
DataStoreManagerEvents.PlayerDataSaved.Event:Connect(onPlayerDataSaved)

for _, player in game:GetService("Players"):GetPlayers() do
	if PlayerDataService.GetData(player) ~= nil then
		onPlayerDataLoaded(player)
	end
end

--[[
	SELF-AUDIT (Section 7.3):
	- PlayerDataLoaded.Event:Connect (onPlayerDataLoaded) — permanent,
	  game-lifetime listener; torn down implicitly on server shutdown. OK.
	- PlayerDataSaved.Event:Connect (onPlayerDataSaved) — permanent,
	  game-lifetime listener; fires only after DataStoreManager's leave
	  save completes, so ClearData never races ahead of persistence. OK.
]]
