--!strict

--[[
	Client-local cosmetic spin + bob on networked loot Models.
	Uses Workspace:BulkMoveTo on PrimaryPart (one batch per frame) so server-anchored
	welded assemblies rotate locally without physics or replication.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ClientPresentationDistance = require(script.Parent.ClientPresentationDistance)
local LootModelUtil = require(ReplicatedStorage.Shared.LootModelUtil)
local LootPresentationConfig = require(ReplicatedStorage.Shared.LootPresentationConfig)
local LootSpinConfig = require(ReplicatedStorage.Shared.LootSpinConfig)

local LOOT_PICKUP_TAG = "LootPickup"
local PRIMARY_PART_WAIT_TIMEOUT = 5

type LootSpinState = {
	baseCFrame: CFrame,
	startTime: number,
	primaryPart: BasePart,
}

local activeLoot: { [Model]: LootSpinState } = {}
local trackedModels: { [Model]: boolean } = {}
local warnedMissingPrimaryPart: { [Model]: boolean } = {}
local destroyingConnections: { [Model]: RBXScriptConnection } = {}
local poseVersionConnections: { [Model]: RBXScriptConnection } = {}
local pendingPrimaryPartAdded: { [Model]: RBXScriptConnection } = {}
local pendingPrimaryPartTimeout: { [Model]: thread } = {}
local spinRenderStepConnection: RBXScriptConnection? = nil

local bulkParts: { BasePart } = table.create(64)
local bulkCFrames: { CFrame } = table.create(64)

local function disconnectPendingPrimaryPartWait(lootModel: Model): ()
	local pending = pendingPrimaryPartAdded[lootModel]
	if pending then
		pending:Disconnect()
		pendingPrimaryPartAdded[lootModel] = nil
	end

	local timeoutThread = pendingPrimaryPartTimeout[lootModel]
	if timeoutThread then
		pendingPrimaryPartTimeout[lootModel] = nil
		task.cancel(timeoutThread)
	end
end

local function isLootWithinPresentationRange(lootModel: Model): boolean
	local distanceStuds =
		ClientPresentationDistance.getDistanceToPosition(LootModelUtil.getLootWorldPosition(lootModel))
	return LootPresentationConfig.isWithinPresentationDistance(distanceStuds)
end

local function disconnectSpinRenderStepIfIdle(): ()
	if next(activeLoot) ~= nil then
		return
	end

	if spinRenderStepConnection then
		spinRenderStepConnection:Disconnect()
		spinRenderStepConnection = nil
	end
end

local function restoreLootBaseCFrame(state: LootSpinState): ()
	state.primaryPart.CFrame = state.baseCFrame
end

local function disconnectPoseVersionConnection(lootModel: Model): ()
	local poseConnection = poseVersionConnections[lootModel]
	if poseConnection then
		poseConnection:Disconnect()
		poseVersionConnections[lootModel] = nil
	end
end

local function updateActiveLootSpin(_deltaTime: number): ()
	local now = os.clock()
	local count = 0

	for lootModel, state in activeLoot do
		if lootModel.Parent == nil then
			continue
		end

		local elapsed = now - state.startTime
		local angle = elapsed * LootSpinConfig.SPIN_SPEED_RADIANS_PER_SEC
		local bobOffset = math.sin(elapsed * LootSpinConfig.BOB_SPEED_RADIANS_PER_SEC) * LootSpinConfig.BOB_AMPLITUDE_STUDS

		count += 1
		bulkParts[count] = state.primaryPart
		bulkCFrames[count] = state.baseCFrame * CFrame.Angles(0, angle, 0) + Vector3.new(0, bobOffset, 0)
	end

	if count > 0 then
		workspace:BulkMoveTo(bulkParts, bulkCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

local function ensureSpinRenderStep(): ()
	if spinRenderStepConnection then
		return
	end

	spinRenderStepConnection = RunService.RenderStepped:Connect(updateActiveLootSpin)
end

local function stopLootSpin(lootModel: Model): ()
	local state = activeLoot[lootModel]
	if state == nil then
		return
	end

	if lootModel.Parent ~= nil then
		restoreLootBaseCFrame(state)
	end

	activeLoot[lootModel] = nil
	disconnectSpinRenderStepIfIdle()
end

local function clearLootSpinState(lootModel: Model): ()
	disconnectPendingPrimaryPartWait(lootModel)
	disconnectPoseVersionConnection(lootModel)
	stopLootSpin(lootModel)

	local destroyingConnection = destroyingConnections[lootModel]
	if destroyingConnection then
		destroyingConnection:Disconnect()
		destroyingConnections[lootModel] = nil
	end

	trackedModels[lootModel] = nil
	warnedMissingPrimaryPart[lootModel] = nil
end

local function ensureDestroyingConnection(lootModel: Model): ()
	if destroyingConnections[lootModel] then
		return
	end

	destroyingConnections[lootModel] = lootModel.Destroying:Connect(function()
		clearLootSpinState(lootModel)
	end)
end

local function beginLootSpin(lootModel: Model, primaryPart: BasePart): ()
	disconnectPendingPrimaryPartWait(lootModel)

	activeLoot[lootModel] = {
		baseCFrame = primaryPart.CFrame,
		startTime = os.clock(),
		primaryPart = primaryPart,
	}

	ensureSpinRenderStep()
end

local function tryBeginLootSpin(lootModel: Model): boolean
	if activeLoot[lootModel] ~= nil then
		disconnectPendingPrimaryPartWait(lootModel)
		return true
	end

	if not trackedModels[lootModel] or lootModel.Parent == nil then
		return false
	end

	if not CollectionService:HasTag(lootModel, LOOT_PICKUP_TAG) then
		return false
	end

	local primaryPart = LootModelUtil.findPrimaryPart(lootModel)
	if primaryPart == nil then
		return false
	end

	beginLootSpin(lootModel, primaryPart)
	return true
end

local function ensurePoseVersionConnection(lootModel: Model): ()
	if poseVersionConnections[lootModel] then
		return
	end

	poseVersionConnections[lootModel] = lootModel:GetAttributeChangedSignal(LootModelUtil.LOOT_POSE_VERSION_ATTRIBUTE):Connect(function()
		local state = activeLoot[lootModel]
		if state == nil then
			return
		end

		-- Leave the replicated PivotTo in place; do not restore the old base.
		activeLoot[lootModel] = nil
		disconnectSpinRenderStepIfIdle()

		task.defer(function()
			if not trackedModels[lootModel] or lootModel.Parent == nil then
				return
			end

			state.baseCFrame = state.primaryPart.CFrame
			activeLoot[lootModel] = state
			ensureSpinRenderStep()
		end)
	end)
end

local function warnMissingPrimaryPartOnce(lootModel: Model): ()
	if warnedMissingPrimaryPart[lootModel] then
		return
	end

	if not isLootWithinPresentationRange(lootModel) then
		return
	end

	warnedMissingPrimaryPart[lootModel] = true
	warn(`[LootSpinHandler] Loot model {lootModel:GetFullName()} is missing PrimaryPart; skipping spin/bob`)
end

local function listenForPrimaryPart(lootModel: Model): ()
	if pendingPrimaryPartAdded[lootModel] ~= nil then
		return
	end

	if not isLootWithinPresentationRange(lootModel) then
		return
	end

	pendingPrimaryPartAdded[lootModel] = lootModel.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			tryBeginLootSpin(lootModel)
		end
	end)

	pendingPrimaryPartTimeout[lootModel] = task.delay(PRIMARY_PART_WAIT_TIMEOUT, function()
		pendingPrimaryPartTimeout[lootModel] = nil
		if activeLoot[lootModel] ~= nil then
			return
		end

		disconnectPendingPrimaryPartWait(lootModel)

		if not trackedModels[lootModel] or not CollectionService:HasTag(lootModel, LOOT_PICKUP_TAG) then
			return
		end

		if tryBeginLootSpin(lootModel) then
			return
		end

		warnMissingPrimaryPartOnce(lootModel)
		listenForPrimaryPart(lootModel)
	end)

	tryBeginLootSpin(lootModel)
end

local function tryTrackLootPresentation(lootModel: Model): ()
	if not isLootWithinPresentationRange(lootModel) then
		disconnectPendingPrimaryPartWait(lootModel)
		stopLootSpin(lootModel)
		return
	end

	if tryBeginLootSpin(lootModel) then
		return
	end

	listenForPrimaryPart(lootModel)
end

local function trackLootModel(lootModel: Model): ()
	if trackedModels[lootModel] then
		tryTrackLootPresentation(lootModel)
		return
	end

	trackedModels[lootModel] = true
	ensureDestroyingConnection(lootModel)
	ensurePoseVersionConnection(lootModel)

	task.defer(function()
		if not trackedModels[lootModel] or lootModel.Parent == nil then
			clearLootSpinState(lootModel)
			return
		end

		if not CollectionService:HasTag(lootModel, LOOT_PICKUP_TAG) then
			clearLootSpinState(lootModel)
			return
		end

		tryTrackLootPresentation(lootModel)
	end)
end

local function refreshAllLootPresentation(): ()
	for lootModel in trackedModels do
		if lootModel.Parent == nil then
			continue
		end

		tryTrackLootPresentation(lootModel)
	end
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

	clearLootSpinState(instance)
end

for _, lootModel in CollectionService:GetTagged(LOOT_PICKUP_TAG) do
	onLootPickupAdded(lootModel)
end

CollectionService:GetInstanceAddedSignal(LOOT_PICKUP_TAG):Connect(onLootPickupAdded)
CollectionService:GetInstanceRemovedSignal(LOOT_PICKUP_TAG):Connect(onLootPickupRemoved)
ClientPresentationDistance.subscribeRefresh(refreshAllLootPresentation)

--[[
	SELF-AUDIT (Section 7):
	- RunService.RenderStepped:Connect — single spinRenderStepConnection while activeLoot
	  is non-empty; disconnected in disconnectSpinRenderStepIfIdle. OK.
	- workspace:BulkMoveTo — one batch per RenderStepped frame for all active spin states. OK.
	- lootModel.Destroying:Connect — stored in destroyingConnections[lootModel], disconnected in
	  clearLootSpinState. OK.
	- LootPoseVersion GetAttributeChangedSignal:Connect — stored in poseVersionConnections[lootModel],
	  disconnected in clearLootSpinState; task.defer rebase of activeLoot baseCFrame after server
	  relocate PivotTo. OK.
	- CollectionService LootPickup added/removed signals:Connect — script-lifetime singletons. OK.
	- ClientPresentationDistance.subscribeRefresh — debounced movement retry for deferred bind. OK.
	- task.defer / task.delay — scoped one-shot deferrals per model bind. OK.
	- lootModel.DescendantAdded:Connect — pendingPrimaryPartAdded per model; disconnected in
	  disconnectPendingPrimaryPartWait; timeout re-arms listenForPrimaryPart when still missing so
	  slow-streaming loot self-heals instead of being abandoned. OK.
]]
