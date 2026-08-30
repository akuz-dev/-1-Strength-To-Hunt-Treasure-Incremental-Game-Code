--!strict

local DataStoreManagerEvents = require(script.Parent.DataStoreManager)
local InventoryManager = require(script.Parent.InventoryManager)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerDataService = require(ReplicatedStorage.Shared.PlayerDataService)

local function onPlayerDataLoaded(player: Player): ()
	InventoryManager.SendSync(player)
end

DataStoreManagerEvents.PlayerDataLoaded.Event:Connect(onPlayerDataLoaded)

for _, player in game:GetService("Players"):GetPlayers() do
	if PlayerDataService.GetData(player) ~= nil then
		onPlayerDataLoaded(player)
	end
end

--[[
	SELF-AUDIT (Section 7):
	- DataStoreManagerEvents.PlayerDataLoaded.Event:Connect — permanent game-lifetime listener. OK.
	- InventoryUpdated RemoteEvent — created once inside InventoryManager module init path. OK.
]]
