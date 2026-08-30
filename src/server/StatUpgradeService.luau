--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataService = require(ReplicatedStorage.Shared.PlayerDataService)
local StatUpgradeConfig = require(ReplicatedStorage.Shared.StatUpgradeConfig)

local AttackZoneManager = require(script.Parent.AttackZoneManager)

export type StatUpgradeDelta = {
	StatName: string,
	Level: number,
	Cash: number,
}

export type StatUpgradeService = {
	TryPurchase: (player: Player, statName: string) -> boolean,
	SyncStatAttributes: (player: Player) -> (),
	ApplyWalkSpeed: (player: Player) -> (),
	InitCharacterHooks: () -> (),
	SetPurchaseRemote: (remote: RemoteEvent) -> (),
}

local REMOTES_FOLDER_NAME = "Remotes"
local PURCHASE_REMOTE_NAME = "PurchaseStatUpgrade"
local REMOTE_WAIT_TIMEOUT = 5

local purchaseRemote: RemoteEvent? = nil
local characterHooksInitialized = false

local function getHumanoid(character: Model): Humanoid?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or not humanoid:IsA("Humanoid") then
		return nil
	end
	return humanoid
end

local function ApplyWalkSpeed(player: Player): ()
	local playerData = PlayerDataService.GetData(player)
	if playerData == nil then
		return
	end

	local character = player.Character
	if character == nil then
		return
	end

	local humanoid = getHumanoid(character)
	if humanoid == nil then
		return
	end

	humanoid.WalkSpeed = StatUpgradeConfig.GetEffectiveWalkSpeed(playerData.StatLevels.WalkSpeed)
end

local function SyncStatAttributes(player: Player): ()
	local playerData = PlayerDataService.GetData(player)
	if playerData == nil then
		return
	end

	local levels = playerData.StatLevels
	player:SetAttribute("Cash", playerData.Cash)
	player:SetAttribute("AgilityLevel", levels.Agility)
	player:SetAttribute("RangeLevel", levels.Range)
	player:SetAttribute("CapacityLevel", levels.Capacity)
	player:SetAttribute("WalkSpeedLevel", levels.WalkSpeed)
	player:SetAttribute("MaxCapacity", StatUpgradeConfig.GetEffectiveCapacity(levels.Capacity))
end

local function firePurchaseDelta(player: Player, statName: string, level: number, cash: number): ()
	local remote = purchaseRemote
	if remote == nil then
		return
	end

	local delta: StatUpgradeDelta = {
		StatName = statName,
		Level = level,
		Cash = cash,
	}
	remote:FireClient(player, delta)
end

local function TryPurchase(player: Player, statName: string): boolean
	if type(statName) ~= "string" or not StatUpgradeConfig.IsValidStatName(statName) then
		return false
	end

	local playerData = PlayerDataService.GetData(player)
	if playerData == nil then
		return false
	end

	local currentLevel: number
	if statName == "Agility" then
		currentLevel = playerData.StatLevels.Agility
	elseif statName == "Range" then
		currentLevel = playerData.StatLevels.Range
	elseif statName == "Capacity" then
		currentLevel = playerData.StatLevels.Capacity
	elseif statName == "WalkSpeed" then
		currentLevel = playerData.StatLevels.WalkSpeed
	else
		return false
	end

	local nextLevel = currentLevel + 1
	local cost = StatUpgradeConfig.GetCost(statName, nextLevel)
	if cost == nil then
		return false
	end

	if playerData.Cash < cost then
		return false
	end

	local newCash = playerData.Cash - cost
	if not PlayerDataService.SetField(player, "Cash", newCash) then
		return false
	end
	if not PlayerDataService.SetStatLevel(player, statName, nextLevel) then
		-- Best-effort rollback of cash if level write fails.
		PlayerDataService.SetField(player, "Cash", playerData.Cash)
		return false
	end

	SyncStatAttributes(player)
	if statName == "WalkSpeed" then
		ApplyWalkSpeed(player)
	elseif statName == "Range" then
		AttackZoneManager.updateZoneForPlayer(player)
	end

	firePurchaseDelta(player, statName, nextLevel, newCash)
	return true
end

local function onCharacterAdded(player: Player, _character: Model): ()
	ApplyWalkSpeed(player)
end

local function hookPlayer(player: Player): ()
	player.CharacterAdded:Connect(function(character: Model)
		onCharacterAdded(player, character)
	end)

	if player.Character ~= nil then
		ApplyWalkSpeed(player)
	end
end

local function InitCharacterHooks(): ()
	if characterHooksInitialized then
		return
	end
	characterHooksInitialized = true

	Players.PlayerAdded:Connect(hookPlayer)
	for _, player in Players:GetPlayers() do
		hookPlayer(player)
	end
end

local function SetPurchaseRemote(remote: RemoteEvent): ()
	purchaseRemote = remote
end

local function resolvePurchaseRemote(): RemoteEvent?
	local remotesFolder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if remotesFolder == nil or not remotesFolder:IsA("Folder") then
		remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME, REMOTE_WAIT_TIMEOUT)
	end
	if remotesFolder == nil or not remotesFolder:IsA("Folder") then
		return nil
	end

	local remote = remotesFolder:FindFirstChild(PURCHASE_REMOTE_NAME)
	if remote == nil then
		remote = remotesFolder:WaitForChild(PURCHASE_REMOTE_NAME, REMOTE_WAIT_TIMEOUT)
	end
	if remote == nil or not remote:IsA("RemoteEvent") then
		return nil
	end

	return remote
end

-- Resolve remote early when required so FireClient works even if handler loads later.
task.defer(function()
	if purchaseRemote == nil then
		local remote = resolvePurchaseRemote()
		if remote ~= nil then
			purchaseRemote = remote
		end
	end
end)

local StatUpgradeService: StatUpgradeService = {
	TryPurchase = TryPurchase,
	SyncStatAttributes = SyncStatAttributes,
	ApplyWalkSpeed = ApplyWalkSpeed,
	InitCharacterHooks = InitCharacterHooks,
	SetPurchaseRemote = SetPurchaseRemote,
}

return StatUpgradeService
