--!strict

--[[
	Client-local persistent loot VFX on networked loot Models:
	VFX anchor clones are parented locally to PrimaryPart and do NOT replicate to other clients or the server.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LootModelUtil = require(ReplicatedStorage.Shared.LootModelUtil)
local LootVfxPool = require(script.Parent.LootVfxPool)

local LOOT_PICKUP_TAG = "LootPickup"
local PRIMARY_PART_WAIT_TIMEOUT = 5

type LootVfxState = {
	anchorPart: BasePart,
	destroyingConnection: RBXScriptConnection,
}

local vfxStates: { [Model]: LootVfxState } = {}
local trackedModels: { [Model]: boolean } = {}
local pendingPrimaryPartAdded: { [Model]: RBXScriptConnection } = {}
local pendingPrimaryPartTimeout: { [Model]: thread } = {}

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

local function clearLootVfxState(lootModel: Model): ()
	disconnectPendingPrimaryPartWait(lootModel)

	local state = vfxStates[lootModel]
	if state == nil then
		trackedModels[lootModel] = nil
		return
	end

	state.destroyingConnection:Disconnect()
	LootVfxPool.release(state.anchorPart)
	vfxStates[lootModel] = nil
	trackedModels[lootModel] = nil
end

local function bindVfxToPrimaryPart(lootModel: Model, primaryPart: BasePart): boolean
	disconnectPendingPrimaryPartWait(lootModel)

	local anchorPart = LootVfxPool.acquire()
	if anchorPart == nil then
		return false
	end

	anchorPart.CFrame = CFrame.identity
	anchorPart.Anchored = false
	anchorPart.Parent = primaryPart

	vfxStates[lootModel] = {
		anchorPart = anchorPart,
		destroyingConnection = lootModel.Destroying:Connect(function()
			clearLootVfxState(lootModel)
		end),
	}

	return true
end

local function tryBindLootVfx(lootModel: Model): boolean
	if vfxStates[lootModel] ~= nil then
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

	return bindVfxToPrimaryPart(lootModel, primaryPart)
end

local function listenForPrimaryPart(lootModel: Model): ()
	if pendingPrimaryPartAdded[lootModel] ~= nil then
		return
	end

	pendingPrimaryPartAdded[lootModel] = lootModel.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			tryBindLootVfx(lootModel)
		end
	end)

	pendingPrimaryPartTimeout[lootModel] = task.delay(PRIMARY_PART_WAIT_TIMEOUT, function()
		pendingPrimaryPartTimeout[lootModel] = nil
		if vfxStates[lootModel] ~= nil then
			return
		end

		disconnectPendingPrimaryPartWait(lootModel)

		if not trackedModels[lootModel] or not CollectionService:HasTag(lootModel, LOOT_PICKUP_TAG) then
			trackedModels[lootModel] = nil
			return
		end

		warn(`[LootVfxHandler] Loot model {lootModel:GetFullName()} is missing PrimaryPart; skipping loot VFX`)
		trackedModels[lootModel] = nil
	end)

	tryBindLootVfx(lootModel)
end

local function trackLootModel(lootModel: Model): ()
	if trackedModels[lootModel] then
		return
	end

	trackedModels[lootModel] = true

	task.defer(function()
		if not trackedModels[lootModel] or lootModel.Parent == nil then
			trackedModels[lootModel] = nil
			return
		end

		if not CollectionService:HasTag(lootModel, LOOT_PICKUP_TAG) then
			trackedModels[lootModel] = nil
			return
		end

		if tryBindLootVfx(lootModel) then
			return
		end

		listenForPrimaryPart(lootModel)
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

	clearLootVfxState(instance)
end

for _, lootModel in CollectionService:GetTagged(LOOT_PICKUP_TAG) do
	onLootPickupAdded(lootModel)
end

CollectionService:GetInstanceAddedSignal(LOOT_PICKUP_TAG):Connect(onLootPickupAdded)
CollectionService:GetInstanceRemovedSignal(LOOT_PICKUP_TAG):Connect(onLootPickupRemoved)

--[[
	SELF-AUDIT (Section 7):
	- lootModel.Destroying:Connect — stored in vfxStates[lootModel].destroyingConnection,
	  disconnected in clearLootVfxState; guarded by trackedModels against double-track. OK.
	- CollectionService LootPickup added/removed signals:Connect — script-lifetime singletons;
	  removed signal drives cleanup when loot is pooled on pickup. OK.
	- task.defer (trackLootModel) — single immediate deferral for replicated PrimaryPart;
	  falls back to DescendantAdded wait for pooled re-activate replication. OK.
	- task.delay (PRIMARY_PART_WAIT_TIMEOUT) — one-shot per tracked model; cancelled on bind or
	  clearLootVfxState; warns only if PrimaryPart still missing after timeout. OK.
	- lootModel.DescendantAdded:Connect — pendingPrimaryPartAdded per model; disconnected in
	  disconnectPendingPrimaryPartWait on bind, tag removal, or timeout. OK.
]]
