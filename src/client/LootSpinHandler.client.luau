--!strict

--[[
	Client-local cosmetic rotation on networked loot Models:
	Changes made from a LocalScript do NOT replicate to other clients or the server.
	The server sets spawn CFrame once; this script owns spin + bob while the LootPickup tag is active.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LootModelUtil = require(ReplicatedStorage.Shared.LootModelUtil)

local LOOT_PICKUP_TAG = "LootPickup"
local PRIMARY_PART_WAIT_TIMEOUT = 5

-- TODO(GDD 1.5): loot motion values are placeholder, not yet specced in GDD.
local SPIN_SPEED_RADIANS_PER_SEC = math.rad(90)
local BOB_AMPLITUDE_STUDS = 0.25
local BOB_SPEED_RADIANS_PER_SEC = math.rad(45)

type LootSpinState = {
	baseCFrame: CFrame,
	startTime: number,
	primaryPart: BasePart,
	destroyingConnection: RBXScriptConnection,
}

local activeLoot: { [Model]: LootSpinState } = {}
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

local function clearLootSpinState(lootModel: Model): ()
	disconnectPendingPrimaryPartWait(lootModel)

	local state = activeLoot[lootModel]
	if state == nil then
		trackedModels[lootModel] = nil
		return
	end

	state.destroyingConnection:Disconnect()
	activeLoot[lootModel] = nil
	trackedModels[lootModel] = nil
end

local function beginLootSpin(lootModel: Model, primaryPart: BasePart): ()
	disconnectPendingPrimaryPartWait(lootModel)

	activeLoot[lootModel] = {
		baseCFrame = primaryPart.CFrame,
		startTime = os.clock(),
		primaryPart = primaryPart,
		destroyingConnection = lootModel.Destroying:Connect(function()
			clearLootSpinState(lootModel)
		end),
	}
end

RunService.RenderStepped:Connect(function()
	for lootModel, state in activeLoot do
		if lootModel.Parent == nil then
			clearLootSpinState(lootModel)
			continue
		end

		local elapsed = os.clock() - state.startTime
		local angle = elapsed * SPIN_SPEED_RADIANS_PER_SEC
		local bobOffset = math.sin(elapsed * BOB_SPEED_RADIANS_PER_SEC) * BOB_AMPLITUDE_STUDS
		state.primaryPart.CFrame = state.baseCFrame * CFrame.Angles(0, angle, 0) + Vector3.new(0, bobOffset, 0)
	end
end)

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

	if not primaryPart.Anchored then
		warn(`[LootSpinHandler] Loot model {lootModel:GetFullName()} PrimaryPart is not Anchored; spin/bob may conflict with physics`)
	end

	beginLootSpin(lootModel, primaryPart)
	return true
end

local function listenForPrimaryPart(lootModel: Model): ()
	if pendingPrimaryPartAdded[lootModel] ~= nil then
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
			trackedModels[lootModel] = nil
			return
		end

		warn(`[LootSpinHandler] Loot model {lootModel:GetFullName()} is missing PrimaryPart; skipping spin/bob`)
		trackedModels[lootModel] = nil
	end)

	tryBeginLootSpin(lootModel)
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

		if tryBeginLootSpin(lootModel) then
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

	clearLootSpinState(instance)
end

for _, lootModel in CollectionService:GetTagged(LOOT_PICKUP_TAG) do
	onLootPickupAdded(lootModel)
end

CollectionService:GetInstanceAddedSignal(LOOT_PICKUP_TAG):Connect(onLootPickupAdded)
CollectionService:GetInstanceRemovedSignal(LOOT_PICKUP_TAG):Connect(onLootPickupRemoved)

--[[
	SELF-AUDIT (Section 7):
	- RunService.RenderStepped:Connect — one script-lifetime singleton; iterates activeLoot each
	  frame and writes primaryPart.CFrame (not PivotTo). Entries removed in clearLootSpinState on
	  tag removal, Destroying, or Parent nil; guarded by trackedModels + activeLoot against
	  double-add on pooled re-activate. OK.
	- lootModel.Destroying:Connect — stored in activeLoot[lootModel].destroyingConnection,
	  disconnected in clearLootSpinState; guarded by trackedModels against double-track. OK.
	- CollectionService LootPickup added/removed signals:Connect — script-lifetime singletons;
	  removed signal drives cleanup when loot is pooled on pickup. OK.
	- task.defer (trackLootModel) — single immediate deferral to capture replicated spawn CFrame
	  on PrimaryPart; falls back to DescendantAdded wait for pooled re-activate replication. OK.
	- task.delay (PRIMARY_PART_WAIT_TIMEOUT) — one-shot per tracked model; cancelled on bind or
	  clearLootSpinState; warns only if PrimaryPart still missing after timeout. OK.
	- lootModel.DescendantAdded:Connect — pendingPrimaryPartAdded per model; disconnected in
	  disconnectPendingPrimaryPartWait on bind, tag removal, or timeout. OK.
]]
