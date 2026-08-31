--!strict

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ObstacleAPI = require(script.Parent.ObstacleAPI)
local TripInventoryManager = require(script.Parent.TripInventoryManager)
local TutorialService = require(script.Parent.TutorialService)
local LootConfig = require(ReplicatedStorage.Shared.LootConfig)
local LootModelUtil = require(ReplicatedStorage.Shared.LootModelUtil)
local LootPool = require(script.Parent.LootPool)
local ObstacleConfig = require(ReplicatedStorage.Shared.ObstacleConfig)
local SandObstacleUtil = require(ReplicatedStorage.Shared.SandObstacleUtil)

local OBSTACLE_TAG = "Obstacle"
local INSIDE_OBSTACLE_LOOT_NAME = "InsideObstacleLoot"
local REMOTES_FOLDER_NAME = "Remotes"
local LOOT_COLLECTED_REMOTE_NAME = "LootCollected"
local SOURCE_OBSTACLE_VALUE_NAME = "SourceObstacle"

-- Per-zone loot spawn tuning lives in LootConfig (RespawnDelay, StaleTimeout).
local MAX_ACTIVE_LOOT_PER_ZONE = 5
-- Vertical clearance above the segment's live top surface (GDD 1.5 spawn-height note).
local LOOT_SPAWN_CLEARANCE = 1.5

type SpawnPointState = {
	spawnPart: BasePart,
	zoneNumber: number,
	blockerSegment: BasePart,
	visualSegment: BasePart,
}

type StaleItemSwapJob = {
	model: Model,
	currentSpawnPart: BasePart,
	newSpawnPart: BasePart,
	newItemEntry: LootConfig.LootItemEntry,
	zoneNumber: number,
}

local spawnPointsByZone: { [number]: { BasePart } } = {}
local spawnPointStates: { [BasePart]: SpawnPointState } = {}
local occupiedSpawnPoints: { [BasePart]: Model } = {}
local modelToSpawnPoint: { [Model]: BasePart } = {}
local segmentSpawnPoints: { [BasePart]: { BasePart } } = {}

local activeLootCountByZone: { [number]: number } = {}
local activeItemCountsByZone: { [number]: { [string]: number } } = {}
local modelToItemId: { [Model]: string } = {}
local staleTimerByModel: { [Model]: thread } = {}
local staleItemSwapQueue: { StaleItemSwapJob } = {}
local staleItemSwapDrainPending = false

local lootCollectedRemote: RemoteEvent

local spawnLootAtPoint: (spawnPart: BasePart, zoneNumber: number) -> ()
local scheduleZoneRespawn: (zoneNumber: number) -> ()
local fillZoneToCap: (zoneNumber: number) -> ()
local cancelStaleTimer: (model: Model) -> ()
local scheduleStaleTimer: (model: Model, zoneNumber: number) -> ()
local performSilentRespawn: (model: Model) -> ()
local relocateLootModel: (model: Model, currentSpawnPart: BasePart, newSpawnPart: BasePart, zoneNumber: number) -> ()
local enqueueStaleItemSwap: (job: StaleItemSwapJob) -> ()
local drainStaleItemSwapQueue: () -> ()
local onLootCollected: (player: Player, spawnPart: BasePart, model: Model, itemEntry: LootConfig.LootItemEntry) -> boolean

local function getActiveLootCountForZone(zoneNumber: number): number
	return activeLootCountByZone[zoneNumber] or 0
end

local function incrementActiveLootCountForZone(zoneNumber: number): ()
	activeLootCountByZone[zoneNumber] = getActiveLootCountForZone(zoneNumber) + 1
end

local function decrementActiveLootCountForZone(zoneNumber: number): ()
	local nextCount = getActiveLootCountForZone(zoneNumber) - 1
	if nextCount <= 0 then
		activeLootCountByZone[zoneNumber] = nil
	else
		activeLootCountByZone[zoneNumber] = nextCount
	end
end

local function incrementActiveItemCountForZone(zoneNumber: number, itemId: string): ()
	local counts = activeItemCountsByZone[zoneNumber]
	if counts == nil then
		counts = {}
		activeItemCountsByZone[zoneNumber] = counts
	end

	counts[itemId] = (counts[itemId] or 0) + 1
end

local function decrementActiveItemCountForZone(zoneNumber: number, itemId: string): ()
	local counts = activeItemCountsByZone[zoneNumber]
	if counts == nil then
		return
	end

	local nextCount = (counts[itemId] or 0) - 1
	if nextCount <= 0 then
		counts[itemId] = nil
	else
		counts[itemId] = nextCount
	end

	local hasAny = false
	for _ in counts do
		hasAny = true
		break
	end

	if not hasAny then
		activeItemCountsByZone[zoneNumber] = nil
	end
end

local function clearActiveLootAtSpawnPoint(spawnPart: BasePart, zoneNumber: number, model: Model): ()
	cancelStaleTimer(model)

	occupiedSpawnPoints[spawnPart] = nil
	modelToSpawnPoint[model] = nil

	local itemId = modelToItemId[model]
	if itemId ~= nil then
		modelToItemId[model] = nil
		decrementActiveItemCountForZone(zoneNumber, itemId)
	end

	decrementActiveLootCountForZone(zoneNumber)
	LootPool.release(model)
end

local function isInsideObstacleLootPartName(name: string): boolean
	return string.lower(name) == string.lower(INSIDE_OBSTACLE_LOOT_NAME)
end

local function getObstacleTypeAttribute(instance: Instance): string?
	local current: Instance? = instance
	while current do
		local obstacleType = current:GetAttribute("ObstacleType")
		if typeof(obstacleType) == "string" and obstacleType ~= "" then
			return obstacleType
		end

		current = current.Parent
	end

	return nil
end

local function resolveSegmentForSpawnPart(spawnPart: BasePart): BasePart?
	local segmentRef = spawnPart:GetAttribute("Segment")
	if typeof(segmentRef) == "Instance" and segmentRef:IsA("BasePart") then
		return segmentRef
	end

	local current: Instance? = spawnPart.Parent
	while current do
		if current:IsA("BasePart") and CollectionService:HasTag(current, OBSTACLE_TAG) then
			return current
		end

		current = current.Parent
	end

	return nil
end

local function getZoneNumberForSegment(segment: BasePart): number?
	local obstacleType = getObstacleTypeAttribute(segment)
	if obstacleType == nil then
		return nil
	end

	local obstacleTypeConfig = ObstacleConfig.GetObstacleType(obstacleType)
	if obstacleTypeConfig == nil then
		return nil
	end

	return obstacleTypeConfig.Zone
end

local function ensureZoneBucket(zoneNumber: number): { BasePart }
	local bucket = spawnPointsByZone[zoneNumber]
	if bucket == nil then
		bucket = {}
		spawnPointsByZone[zoneNumber] = bucket
	end

	return bucket
end

local function registerSpawnPoint(
	blockerSegment: BasePart,
	visualSegment: BasePart,
	spawnPart: BasePart,
	zoneNumber: number
): ()
	if spawnPointStates[spawnPart] ~= nil then
		return
	end

	local zoneBucket = ensureZoneBucket(zoneNumber)
	table.insert(zoneBucket, spawnPart)

	spawnPointStates[spawnPart] = {
		spawnPart = spawnPart,
		zoneNumber = zoneNumber,
		blockerSegment = blockerSegment,
		visualSegment = visualSegment,
	}

	local segmentPoints = segmentSpawnPoints[blockerSegment]
	if segmentPoints == nil then
		segmentPoints = {}
		segmentSpawnPoints[blockerSegment] = segmentPoints
	end

	table.insert(segmentPoints, spawnPart)
end

local function unregisterSpawnPoint(spawnPart: BasePart): ()
	local state = spawnPointStates[spawnPart]
	if state == nil then
		return
	end

	local activeModel = occupiedSpawnPoints[spawnPart]
	if activeModel then
		clearActiveLootAtSpawnPoint(spawnPart, state.zoneNumber, activeModel)
	end

	local zoneBucket = spawnPointsByZone[state.zoneNumber]
	if zoneBucket then
		for index, bucketSpawnPart in zoneBucket do
			if bucketSpawnPart == spawnPart then
				table.remove(zoneBucket, index)
				break
			end
		end

		if #zoneBucket == 0 then
			spawnPointsByZone[state.zoneNumber] = nil
		end
	end

	local segmentPoints = segmentSpawnPoints[state.blockerSegment]
	if segmentPoints then
		for index, segmentSpawnPart in segmentPoints do
			if segmentSpawnPart == spawnPart then
				table.remove(segmentPoints, index)
				break
			end
		end

		if #segmentPoints == 0 then
			segmentSpawnPoints[state.blockerSegment] = nil
		end
	end

	spawnPointStates[spawnPart] = nil
end

local function collectLootSpawnParts(blockerSegment: BasePart): { BasePart }
	local spawnParts: { BasePart } = {}
	local searchRoot: Instance = blockerSegment.Parent or blockerSegment

	if isInsideObstacleLootPartName(blockerSegment.Name) then
		table.insert(spawnParts, blockerSegment)
		return spawnParts
	end

	for _, descendant in searchRoot:GetDescendants() do
		if descendant:IsA("BasePart") and isInsideObstacleLootPartName(descendant.Name) then
			table.insert(spawnParts, descendant)
		end
	end

	if #spawnParts == 0 then
		table.insert(spawnParts, blockerSegment)
	end

	return spawnParts
end

local function registerObstacleSegment(blockerSegment: BasePart, visualSegment: BasePart): ()
	local zoneNumber = getZoneNumberForSegment(blockerSegment)
	if zoneNumber == nil then
		warn(`[LootManager] Segment {blockerSegment:GetFullName()} has no valid ObstacleType zone; loot spawn points skipped`)
		return
	end

	for _, spawnPart in collectLootSpawnParts(blockerSegment) do
		local linkedBlocker = resolveSegmentForSpawnPart(spawnPart) or blockerSegment
		registerSpawnPoint(linkedBlocker, visualSegment, spawnPart, zoneNumber)
	end

	fillZoneToCap(zoneNumber)
end

local function unregisterObstacleSegment(blockerSegment: BasePart): ()
	local spawnParts = segmentSpawnPoints[blockerSegment]
	if spawnParts == nil then
		return
	end

	local spawnPartsCopy = table.clone(spawnParts)
	for _, spawnPart in spawnPartsCopy do
		unregisterSpawnPoint(spawnPart)
	end
end

local function pickRandomFreeSpawnPointInZone(zoneNumber: number): BasePart?
	local zoneSpawnPoints = spawnPointsByZone[zoneNumber]
	if zoneSpawnPoints == nil then
		return nil
	end

	local freeSpawnPoints: { BasePart } = {}
	for _, spawnPart in zoneSpawnPoints do
		if occupiedSpawnPoints[spawnPart] == nil then
			table.insert(freeSpawnPoints, spawnPart)
		end
	end

	if #freeSpawnPoints == 0 then
		return nil
	end

	return freeSpawnPoints[math.random(1, #freeSpawnPoints)]
end

local function pickRandomAlternateSpawnPointInZone(zoneNumber: number, excludeSpawnPart: BasePart): BasePart?
	local zoneSpawnPoints = spawnPointsByZone[zoneNumber]
	if zoneSpawnPoints == nil then
		return nil
	end

	local alternateSpawnPoints: { BasePart } = {}
	for _, spawnPart in zoneSpawnPoints do
		if spawnPart ~= excludeSpawnPart and occupiedSpawnPoints[spawnPart] == nil then
			table.insert(alternateSpawnPoints, spawnPart)
		end
	end

	if #alternateSpawnPoints == 0 then
		return nil
	end

	return alternateSpawnPoints[math.random(1, #alternateSpawnPoints)]
end

cancelStaleTimer = function(model: Model): ()
	local staleTimer = staleTimerByModel[model]
	if staleTimer == nil then
		return
	end

	staleTimerByModel[model] = nil
	task.cancel(staleTimer)
end

scheduleStaleTimer = function(model: Model, zoneNumber: number): ()
	cancelStaleTimer(model)

	local staleTimeout = LootConfig.RollStaleTimeout(zoneNumber)
	local staleTimer = task.delay(staleTimeout, function()
		staleTimerByModel[model] = nil
		performSilentRespawn(model)
	end)
	staleTimerByModel[model] = staleTimer
end

local function activateLootModelAtSpawnPoint(
	lootModel: Model,
	spawnPart: BasePart,
	zoneNumber: number,
	itemEntry: LootConfig.LootItemEntry
): boolean
	local spawnState = spawnPointStates[spawnPart]
	if spawnState == nil then
		return false
	end

	local spawnCFrame = SandObstacleUtil.computeLootSpawnCFrame(spawnState.visualSegment, spawnPart, LOOT_SPAWN_CLEARANCE)

	return LootPool.activate(
		lootModel,
		spawnCFrame,
		spawnState.blockerSegment,
		itemEntry,
		function(playerWhoTriggered: Player)
			local currentSpawnPart = modelToSpawnPoint[lootModel]
			if currentSpawnPart == nil then
				return false
			end

			local currentSpawnState = spawnPointStates[currentSpawnPart]
			if currentSpawnState == nil then
				return false
			end

			if not ObstacleAPI.isObstacleBrokenForPlayer(playerWhoTriggered, currentSpawnState.blockerSegment) then
				return false
			end

			return TripInventoryManager.CanAddItem(playerWhoTriggered)
		end,
		function(playerWhoTriggered: Player)
			local currentSpawnPart = modelToSpawnPoint[lootModel]
			local currentItemId = modelToItemId[lootModel]
			if currentSpawnPart == nil or currentItemId == nil then
				return false
			end

			local currentItemEntry = LootConfig.GetItem(currentItemId)
			if currentItemEntry == nil then
				return false
			end

			return onLootCollected(playerWhoTriggered, currentSpawnPart, lootModel, currentItemEntry)
		end
	)
end

local function bumpLootPoseVersion(model: Model): ()
	local currentVersion = model:GetAttribute(LootModelUtil.LOOT_POSE_VERSION_ATTRIBUTE)
	local nextVersion = if typeof(currentVersion) == "number" then currentVersion + 1 else 1
	model:SetAttribute(LootModelUtil.LOOT_POSE_VERSION_ATTRIBUTE, nextVersion)
end

local function updateSourceObstacleValue(model: Model, blockerSegment: BasePart): ()
	local sourceObstacleValue = model:FindFirstChild(SOURCE_OBSTACLE_VALUE_NAME)
	if sourceObstacleValue == nil or not sourceObstacleValue:IsA("ObjectValue") then
		return
	end

	sourceObstacleValue.Value = blockerSegment
end

relocateLootModel = function(model: Model, currentSpawnPart: BasePart, newSpawnPart: BasePart, zoneNumber: number): ()
	local newSpawnState = spawnPointStates[newSpawnPart]
	if newSpawnState == nil then
		scheduleStaleTimer(model, zoneNumber)
		return
	end

	local spawnCFrame = SandObstacleUtil.computeLootSpawnCFrame(
		newSpawnState.visualSegment,
		newSpawnPart,
		LOOT_SPAWN_CLEARANCE
	)

	occupiedSpawnPoints[currentSpawnPart] = nil
	occupiedSpawnPoints[newSpawnPart] = model
	modelToSpawnPoint[model] = newSpawnPart

	model:PivotTo(spawnCFrame)
	updateSourceObstacleValue(model, newSpawnState.blockerSegment)
	bumpLootPoseVersion(model)
	scheduleStaleTimer(model, zoneNumber)
end

local function isStaleSwapJobStillValid(job: StaleItemSwapJob): boolean
	if modelToSpawnPoint[job.model] ~= job.currentSpawnPart then
		return false
	end

	if occupiedSpawnPoints[job.currentSpawnPart] ~= job.model then
		return false
	end

	if modelToItemId[job.model] == nil then
		return false
	end

	return true
end

local function performQueuedItemSwap(job: StaleItemSwapJob): ()
	if not isStaleSwapJobStillValid(job) then
		return
	end

	local newSpawnPart = job.newSpawnPart
	if occupiedSpawnPoints[newSpawnPart] ~= nil or spawnPointStates[newSpawnPart] == nil then
		local fallbackSpawnPart = pickRandomAlternateSpawnPointInZone(job.zoneNumber, job.currentSpawnPart)
		if fallbackSpawnPart == nil then
			scheduleStaleTimer(job.model, job.zoneNumber)
			return
		end
		newSpawnPart = fallbackSpawnPart
	end

	local currentItemId = modelToItemId[job.model]
	local replacementModel = LootPool.acquire(job.newItemEntry.ItemId)
	if replacementModel == nil then
		scheduleStaleTimer(job.model, job.zoneNumber)
		return
	end

	if currentItemId ~= nil then
		decrementActiveItemCountForZone(job.zoneNumber, currentItemId)
	end
	incrementActiveItemCountForZone(job.zoneNumber, job.newItemEntry.ItemId)

	occupiedSpawnPoints[job.currentSpawnPart] = nil
	modelToSpawnPoint[job.model] = nil
	modelToItemId[job.model] = nil
	cancelStaleTimer(job.model)
	LootPool.release(job.model)

	occupiedSpawnPoints[newSpawnPart] = replacementModel
	modelToSpawnPoint[replacementModel] = newSpawnPart
	modelToItemId[replacementModel] = job.newItemEntry.ItemId

	if not activateLootModelAtSpawnPoint(replacementModel, newSpawnPart, job.zoneNumber, job.newItemEntry) then
		clearActiveLootAtSpawnPoint(newSpawnPart, job.zoneNumber, replacementModel)
		return
	end

	scheduleStaleTimer(replacementModel, job.zoneNumber)
end

drainStaleItemSwapQueue = function(): ()
	staleItemSwapDrainPending = false

	local job = table.remove(staleItemSwapQueue, 1)
	if job == nil then
		return
	end

	performQueuedItemSwap(job)

	if #staleItemSwapQueue > 0 then
		staleItemSwapDrainPending = true
		task.delay(0, drainStaleItemSwapQueue)
	end
end

enqueueStaleItemSwap = function(job: StaleItemSwapJob): ()
	table.insert(staleItemSwapQueue, job)

	if staleItemSwapDrainPending then
		return
	end

	staleItemSwapDrainPending = true
	task.delay(0, drainStaleItemSwapQueue)
end

performSilentRespawn = function(model: Model): ()
	local currentSpawnPart = modelToSpawnPoint[model]
	if currentSpawnPart == nil or occupiedSpawnPoints[currentSpawnPart] ~= model then
		return
	end

	local spawnState = spawnPointStates[currentSpawnPart]
	if spawnState == nil then
		return
	end

	local zoneNumber = spawnState.zoneNumber
	local currentItemId = modelToItemId[model]
	local alternateSpawnPart = pickRandomAlternateSpawnPointInZone(zoneNumber, currentSpawnPart)
	if alternateSpawnPart == nil then
		scheduleStaleTimer(model, zoneNumber)
		return
	end

	local newItemEntry = LootConfig.RollLootItem(
		zoneNumber,
		LootPool.getAvailableLootIds(),
		activeItemCountsByZone[zoneNumber],
		currentItemId
	)
	if newItemEntry == nil then
		scheduleStaleTimer(model, zoneNumber)
		return
	end

	if spawnPointStates[alternateSpawnPart] == nil then
		scheduleStaleTimer(model, zoneNumber)
		return
	end

	if currentItemId == newItemEntry.ItemId then
		relocateLootModel(model, currentSpawnPart, alternateSpawnPart, zoneNumber)
		return
	end

	enqueueStaleItemSwap({
		model = model,
		currentSpawnPart = currentSpawnPart,
		newSpawnPart = alternateSpawnPart,
		newItemEntry = newItemEntry,
		zoneNumber = zoneNumber,
	})
end

onLootCollected = function(player: Player, spawnPart: BasePart, model: Model, itemEntry: LootConfig.LootItemEntry): boolean
	if occupiedSpawnPoints[spawnPart] ~= model then
		return false
	end

	local inventoryEntry = itemEntry.ItemId

	if not TripInventoryManager.CanAddItem(player) then
		return false
	end

	if not TripInventoryManager.AddItem(player, inventoryEntry) then
		warn(`[LootManager] Failed to add trip inventory item for {player.Name}`)
		return false
	end

	local spawnState = spawnPointStates[spawnPart]
	local zoneNumberForRespawn: number? = if spawnState then spawnState.zoneNumber else nil

	occupiedSpawnPoints[spawnPart] = nil
	modelToSpawnPoint[model] = nil

	if spawnState then
		decrementActiveLootCountForZone(spawnState.zoneNumber)
		decrementActiveItemCountForZone(spawnState.zoneNumber, itemEntry.ItemId)
	end

	modelToItemId[model] = nil

	cancelStaleTimer(model)

	lootCollectedRemote:FireClient(player, itemEntry.ItemId, itemEntry.Rarity, itemEntry.BaseSellValue)
	LootPool.release(model)

	if zoneNumberForRespawn then
		scheduleZoneRespawn(zoneNumberForRespawn)
	end

	TutorialService.NotifyLootCollected(player)

	return true
end

spawnLootAtPoint = function(spawnPart: BasePart, zoneNumber: number): ()
	if occupiedSpawnPoints[spawnPart] ~= nil then
		return
	end

	if getActiveLootCountForZone(zoneNumber) >= MAX_ACTIVE_LOOT_PER_ZONE then
		return
	end

	local itemEntry = LootConfig.RollLootItem(
		zoneNumber,
		LootPool.getAvailableLootIds(),
		activeItemCountsByZone[zoneNumber]
	)
	if itemEntry == nil then
		return
	end

	local lootModel = LootPool.acquire(itemEntry.ItemId)
	if lootModel == nil then
		return
	end

	if not activateLootModelAtSpawnPoint(lootModel, spawnPart, zoneNumber, itemEntry) then
		LootPool.release(lootModel)
		return
	end

	occupiedSpawnPoints[spawnPart] = lootModel
	modelToSpawnPoint[lootModel] = spawnPart
	modelToItemId[lootModel] = itemEntry.ItemId
	incrementActiveLootCountForZone(zoneNumber)
	incrementActiveItemCountForZone(zoneNumber, itemEntry.ItemId)
	scheduleStaleTimer(lootModel, zoneNumber)
end

scheduleZoneRespawn = function(zoneNumber: number): ()
	local respawnDelay = LootConfig.RollRespawnDelay(zoneNumber)
	task.delay(respawnDelay, function()
		if spawnPointsByZone[zoneNumber] == nil then
			return
		end

		local freeSpawnPart = pickRandomFreeSpawnPointInZone(zoneNumber)
		if freeSpawnPart then
			spawnLootAtPoint(freeSpawnPart, zoneNumber)
		end
	end)
end

fillZoneToCap = function(zoneNumber: number): ()
	while getActiveLootCountForZone(zoneNumber) < MAX_ACTIVE_LOOT_PER_ZONE do
		local freeSpawnPart = pickRandomFreeSpawnPointInZone(zoneNumber)
		if freeSpawnPart == nil then
			break
		end

		spawnLootAtPoint(freeSpawnPart, zoneNumber)
	end
end

local function fillAllZonesToCap(): ()
	for zoneNumber in spawnPointsByZone do
		fillZoneToCap(zoneNumber)
	end
end

local function tryRegisterLootForObstacle(instance: Instance): ()
	local blockerSegment = SandObstacleUtil.resolveSegmentFromTaggedInstance(instance, "touch")
	if blockerSegment ~= nil and segmentSpawnPoints[blockerSegment] ~= nil then
		return
	end

	local blocker, visualSegment = SandObstacleUtil.resolveBlockerVisualPair(instance)
	if blocker == nil or visualSegment == nil then
		return
	end

	registerObstacleSegment(blocker, visualSegment)
end

local function onObstacleInstanceAdded(instance: Instance): ()
	if instance:IsA("BasePart") and string.lower(instance.Name) == string.lower(INSIDE_OBSTACLE_LOOT_NAME) then
		return
	end

	task.defer(function()
		tryRegisterLootForObstacle(instance)
	end)
end

local function onObstacleInstanceRemoved(instance: Instance): ()
	local blockerSegment = SandObstacleUtil.resolveSegmentFromTaggedInstance(instance, "touch")
	if blockerSegment == nil then
		return
	end

	unregisterObstacleSegment(blockerSegment)
end

local function getOrCreateRemotesFolder(): Folder
	local existingFolder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if existingFolder and existingFolder:IsA("Folder") then
		return existingFolder
	end

	local remotesFolder = Instance.new("Folder")
	remotesFolder.Name = REMOTES_FOLDER_NAME
	remotesFolder.Parent = ReplicatedStorage
	return remotesFolder
end

local function getOrCreateRemoteEvent(parent: Instance, remoteName: string): RemoteEvent
	local existingRemote = parent:FindFirstChild(remoteName)
	if existingRemote and existingRemote:IsA("RemoteEvent") then
		return existingRemote
	end

	local remoteEvent = Instance.new("RemoteEvent")
	remoteEvent.Name = remoteName
	remoteEvent.Parent = parent
	return remoteEvent
end

lootCollectedRemote = getOrCreateRemoteEvent(getOrCreateRemotesFolder(), LOOT_COLLECTED_REMOTE_NAME)

CollectionService:GetInstanceAddedSignal(OBSTACLE_TAG):Connect(onObstacleInstanceAdded)
CollectionService:GetInstanceRemovedSignal(OBSTACLE_TAG):Connect(onObstacleInstanceRemoved)

task.defer(function()
	for _, obstacle in CollectionService:GetTagged(OBSTACLE_TAG) do
		if obstacle:IsA("BasePart") and string.lower(obstacle.Name) == string.lower(INSIDE_OBSTACLE_LOOT_NAME) then
			continue
		end
		tryRegisterLootForObstacle(obstacle)
	end

	fillAllZonesToCap()
end)

--[[
	SELF-AUDIT (Section 7):
	- task.delay (per-collection zone respawn; per-node StaleTimeout silent respawn) — independent
	  one-shot delays; collected respawn picks random free spawn point at fire time; stale timer
	  cancels via task.cancel on successful collect or cleanup. No captured Player/Model. OK.
	- task.delay(0) stale-item swap drain — one-shot chain, armed only while staleItemSwapQueue
	  is non-empty (staleItemSwapDrainPending); at most one release+acquire+activate per frame.
	  Idle when the queue is empty. Not a polling loop. OK.
	- LootPoseVersion attribute — bumped on same-item relocate only; cleared in LootPool.resetModel.
	  Client spin rebases from it; no extra connections on the server. OK.
	- CollectionService obstacle tag signals:Connect — script-lifetime singletons. OK.
	- ProximityPrompt.Triggered:Connect — wired in LootPool.activate per model; disconnected on
	  successful collect or in LootPool.release. Same-item relocate keeps the existing connection
	  and canCollect/onCollected read live modelToSpawnPoint. OK.
	- Instance.new (Folder, RemoteEvent) — one-time getOrCreate* init for LootCollected remote. OK.
	- Model Clone/release — confined to LootPool; LootManager calls release on pickup/cleanup/swap. OK.
	- Loot spawn CFrame computed at spawn time from segment live Position/Size (GDD 1.5). OK.
]]
