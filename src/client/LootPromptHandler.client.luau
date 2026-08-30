--!strict

--[[
	Client-local loot ProximityPrompt visibility:
	Server keeps Enabled true so Triggered still fires; this script hides the prompt until
	the local player has broken the source obstacle.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NotificationToast = require(script.Parent.NotificationToast)
local SandObstacleUtil = require(ReplicatedStorage.Shared.SandObstacleUtil)

local LOOT_PICKUP_TAG = "LootPickup"
local SOURCE_OBSTACLE_VALUE_NAME = "SourceObstacle"
local REMOTES_FOLDER_NAME = "Remotes"
local OBSTACLE_BROKEN_REMOTE_NAME = "ObstacleBroken"
local OBSTACLE_RESET_ALL_REMOTE_NAME = "ObstacleResetAll"
local REMOTE_WAIT_TIMEOUT = 5
local SOURCE_VALUE_WAIT_TIMEOUT = 5
local BAG_FULL_MESSAGE = "You can't carry more items, you need to sell!"

type LootPromptState = {
	prompt: ProximityPrompt,
	sourceObstacle: BasePart?,
	destroyingConnection: RBXScriptConnection,
	triggeredConnection: RBXScriptConnection?,
	valueChangedConnection: RBXScriptConnection?,
	enabledChangedConnection: RBXScriptConnection?,
}

local promptStates: { [Model]: LootPromptState } = {}
local trackedModels: { [Model]: boolean } = {}
local pendingPromptAdded: { [Model]: RBXScriptConnection } = {}
local brokenObstacles: { [BasePart]: boolean } = setmetatable({}, { __mode = "k" }) :: { [BasePart]: boolean }

local function isTripCapacityFull(): boolean
	local player = Players.LocalPlayer
	local tripCount = player:GetAttribute("TripCarryCount")
	local maxCapacity = player:GetAttribute("MaxCapacity")
	if typeof(tripCount) ~= "number" or typeof(maxCapacity) ~= "number" then
		return false
	end

	return tripCount >= maxCapacity
end

local function findProximityPrompt(lootModel: Model): ProximityPrompt?
	local primaryPart = lootModel.PrimaryPart
	if primaryPart then
		local prompt = primaryPart:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			return prompt
		end
	end

	for _, descendant in lootModel:GetDescendants() do
		if descendant:IsA("ProximityPrompt") then
			return descendant
		end
	end

	return nil
end

local function disconnectPendingPromptWait(lootModel: Model): ()
	local pending = pendingPromptAdded[lootModel]
	if pending == nil then
		return
	end

	pending:Disconnect()
	pendingPromptAdded[lootModel] = nil
end

local function applyPromptEnabled(state: LootPromptState): ()
	local obstacle = state.sourceObstacle
	local shouldEnable = obstacle ~= nil and brokenObstacles[obstacle] == true
	if state.prompt.Enabled ~= shouldEnable then
		state.prompt.Enabled = shouldEnable
	end
end

local function clearLootPromptState(lootModel: Model): ()
	disconnectPendingPromptWait(lootModel)

	local state = promptStates[lootModel]
	if state == nil then
		trackedModels[lootModel] = nil
		return
	end

	state.destroyingConnection:Disconnect()
	if state.triggeredConnection and state.triggeredConnection.Connected then
		state.triggeredConnection:Disconnect()
	end
	if state.valueChangedConnection and state.valueChangedConnection.Connected then
		state.valueChangedConnection:Disconnect()
	end
	if state.enabledChangedConnection and state.enabledChangedConnection.Connected then
		state.enabledChangedConnection:Disconnect()
	end

	promptStates[lootModel] = nil
	trackedModels[lootModel] = nil
end

local function bindPromptToLoot(lootModel: Model, prompt: ProximityPrompt): ()
	prompt.Enabled = false

	local state: LootPromptState = {
		prompt = prompt,
		sourceObstacle = nil,
		destroyingConnection = lootModel.Destroying:Connect(function()
			clearLootPromptState(lootModel)
		end),
		triggeredConnection = nil,
		valueChangedConnection = nil,
		enabledChangedConnection = nil,
	}
	promptStates[lootModel] = state

	state.triggeredConnection = prompt.Triggered:Connect(function(playerWhoTriggered: Player)
		if playerWhoTriggered ~= Players.LocalPlayer then
			return
		end
		if isTripCapacityFull() then
			NotificationToast.ShowNegative(BAG_FULL_MESSAGE)
		end
	end)

	state.enabledChangedConnection = prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
		local current = promptStates[lootModel]
		if current == nil then
			return
		end
		applyPromptEnabled(current)
	end)

	local sourceValue = lootModel:FindFirstChild(SOURCE_OBSTACLE_VALUE_NAME)
	if sourceValue == nil then
		local waited = lootModel:WaitForChild(SOURCE_OBSTACLE_VALUE_NAME, SOURCE_VALUE_WAIT_TIMEOUT)
		if waited then
			sourceValue = waited
		end
	end

	if sourceValue == nil or not sourceValue:IsA("ObjectValue") then
		return
	end

	local function assignSourceObstacle(obstacle: Instance?): ()
		local current = promptStates[lootModel]
		if current == nil then
			return
		end

		if obstacle and obstacle:IsA("BasePart") then
			current.sourceObstacle = obstacle
		else
			current.sourceObstacle = nil
		end
		applyPromptEnabled(current)
	end

	assignSourceObstacle(sourceValue.Value)
	state.valueChangedConnection = sourceValue.Changed:Connect(assignSourceObstacle)
end

local function tryBindPrompt(lootModel: Model): boolean
	if promptStates[lootModel] ~= nil then
		disconnectPendingPromptWait(lootModel)
		return true
	end

	if not trackedModels[lootModel] or lootModel.Parent == nil then
		return false
	end

	if not CollectionService:HasTag(lootModel, LOOT_PICKUP_TAG) then
		return false
	end

	local prompt = findProximityPrompt(lootModel)
	if prompt == nil then
		return false
	end

	disconnectPendingPromptWait(lootModel)
	prompt.Enabled = false
	bindPromptToLoot(lootModel, prompt)
	return true
end

local function listenForPrompt(lootModel: Model): ()
	if pendingPromptAdded[lootModel] ~= nil then
		return
	end

	pendingPromptAdded[lootModel] = lootModel.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("ProximityPrompt") then
			tryBindPrompt(lootModel)
		end
	end)

	-- Prompt may have replicated between findProximityPrompt and Connect.
	tryBindPrompt(lootModel)
end

local function trackLootModel(lootModel: Model): ()
	if trackedModels[lootModel] then
		return
	end

	trackedModels[lootModel] = true

	local existingPrompt = findProximityPrompt(lootModel)
	if existingPrompt then
		existingPrompt.Enabled = false
	end

	task.defer(function()
		if not trackedModels[lootModel] or lootModel.Parent == nil then
			trackedModels[lootModel] = nil
			return
		end

		if not CollectionService:HasTag(lootModel, LOOT_PICKUP_TAG) then
			trackedModels[lootModel] = nil
			return
		end

		if tryBindPrompt(lootModel) then
			return
		end

		listenForPrompt(lootModel)
	end)
end

local function onLootPickupAdded(instance: Instance): ()
	if not instance:IsA("Model") then
		return
	end

	trackLootModel(instance)
end

local function onLootPickupRemoved(instance: Instance): ()
	if not instance:IsA("Model") then
		return
	end

	clearLootPromptState(instance)
end

local function markObstacleBroken(obstacle: BasePart): ()
	brokenObstacles[obstacle] = true

	local blocker, visual = SandObstacleUtil.resolveBlockerVisualPair(obstacle)
	if blocker then
		brokenObstacles[blocker] = true
	end
	if visual then
		brokenObstacles[visual] = true
	end
end

local function clearObstacleBroken(obstacle: BasePart): ()
	brokenObstacles[obstacle] = nil

	local blocker, visual = SandObstacleUtil.resolveBlockerVisualPair(obstacle)
	if blocker then
		brokenObstacles[blocker] = nil
	end
	if visual then
		brokenObstacles[visual] = nil
	end
end

local function onObstacleBroken(obstacle: Instance): ()
	if obstacle == nil or not obstacle:IsA("BasePart") then
		return
	end

	markObstacleBroken(obstacle)

	for _, state in promptStates do
		applyPromptEnabled(state)
	end
end

local function onObstacleResetAll(resetBlockers: { BasePart }): ()
	if #resetBlockers == 0 then
		return
	end

	for _, blocker in resetBlockers do
		if typeof(blocker) == "Instance" and blocker:IsA("BasePart") then
			clearObstacleBroken(blocker)
		end
	end

	for _, state in promptStates do
		applyPromptEnabled(state)
	end
end

local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME, REMOTE_WAIT_TIMEOUT)
if remotesFolder == nil then
	warn(`[LootPromptHandler] Remotes folder not found within {REMOTE_WAIT_TIMEOUT}s`)
	return
end

local obstacleBrokenRemote = remotesFolder:WaitForChild(OBSTACLE_BROKEN_REMOTE_NAME, REMOTE_WAIT_TIMEOUT)
local resetAllRemote = remotesFolder:WaitForChild(OBSTACLE_RESET_ALL_REMOTE_NAME, REMOTE_WAIT_TIMEOUT)
if
	obstacleBrokenRemote == nil
	or not obstacleBrokenRemote:IsA("RemoteEvent")
	or resetAllRemote == nil
	or not resetAllRemote:IsA("RemoteEvent")
then
	warn("[LootPromptHandler] ObstacleBroken / ObstacleResetAll remotes not found")
	return
end

obstacleBrokenRemote.OnClientEvent:Connect(onObstacleBroken)
resetAllRemote.OnClientEvent:Connect(onObstacleResetAll)

for _, lootModel in CollectionService:GetTagged(LOOT_PICKUP_TAG) do
	onLootPickupAdded(lootModel)
end

CollectionService:GetInstanceAddedSignal(LOOT_PICKUP_TAG):Connect(onLootPickupAdded)
CollectionService:GetInstanceRemovedSignal(LOOT_PICKUP_TAG):Connect(onLootPickupRemoved)

--[[
	SELF-AUDIT (Section 7):
	- CollectionService LootPickup added/removed signals:Connect — script-lifetime singletons;
	  removed signal drives clearLootPromptState. OK.
	- brokenObstacles uses weak BasePart keys so streamed-out/destroyed obstacles do not leak
	  (GDD 7.2) and stream-out does not hide a prompt the player already unlocked. OK.
	- lootModel.DescendantAdded:Connect — stored in pendingPromptAdded[lootModel] until a
	  ProximityPrompt replicates; disconnected in tryBindPrompt / clearLootPromptState. OK.
	- lootModel.Destroying:Connect — stored in promptStates[lootModel].destroyingConnection,
	  disconnected in clearLootPromptState; guarded by trackedModels against double-track. OK.
	- ObjectValue.Changed:Connect — stored in promptStates[lootModel].valueChangedConnection,
	  disconnected in clearLootPromptState. OK.
	- ProximityPrompt Enabled GetPropertyChangedSignal:Connect — stored in
	  enabledChangedConnection, disconnected in clearLootPromptState; applyPromptEnabled
	  no-ops when the value already matches to avoid a set loop. OK.
	- ProximityPrompt.Triggered:Connect — stored in triggeredConnection, disconnected in
	  clearLootPromptState; shows NotificationToast when local trip capacity is full. OK.
	- ObstacleBroken / ObstacleResetAll OnClientEvent:Connect — script-lifetime singletons;
	  ObstacleResetAll clears only the received Blocker list from brokenObstacles (delta-only). OK.
	- task.defer (trackLootModel) — single immediate deferral; bind if prompt exists, otherwise
	  DescendantAdded until tagged loot is pooled/removed. OK.
	- No Instance.new() / :Destroy() in this script. OK.
]]
