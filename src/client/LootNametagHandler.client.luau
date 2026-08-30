--!strict

--[[
	Client-local loot nametags on networked loot Models:
	BillboardGui clones are parented locally and do NOT replicate to other clients or the server.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CashUtil = require(ReplicatedStorage.Shared.CashUtil)
local LootConfig = require(ReplicatedStorage.Shared.LootConfig)
local LootModelUtil = require(ReplicatedStorage.Shared.LootModelUtil)
local LootNametagConfig = require(ReplicatedStorage.Shared.LootNametagConfig)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local ProgressionConfig = require(ReplicatedStorage.Shared.ProgressionConfig)
local LootNametagPool = require(script.Parent.LootNametagPool)

local LOOT_PICKUP_TAG = "LootPickup"
local LOOT_MODEL_WAIT_TIMEOUT = 5

type LootNametagAdornee = Attachment | BasePart

type LootNametagState = {
	billboard: BillboardGui,
	destroyingConnection: RBXScriptConnection,
}

local nametagStates: { [Model]: LootNametagState } = {}
local trackedModels: { [Model]: boolean } = {}
local pendingNametagDescendantAdded: { [Model]: RBXScriptConnection } = {}
local pendingNametagTimeout: { [Model]: thread } = {}
local player = Players.LocalPlayer

local function getLocalCashMultiplier(): number
	local rebirths = player:GetAttribute("Rebirths")
	if typeof(rebirths) == "number" then
		return ProgressionConfig.GetCashGainMultiplier(rebirths)
	end

	return 1
end

local function resolveNametagAdornee(lootModel: Model, allowPrimaryPartFallback: boolean): (LootNametagAdornee?, boolean)
	local nametagAnchor = LootModelUtil.findNametagAnchor(lootModel)
	if nametagAnchor then
		return nametagAnchor, false
	end

	if not allowPrimaryPartFallback then
		return nil, false
	end

	local primaryPart = LootModelUtil.findPrimaryPart(lootModel)
	if primaryPart then
		return primaryPart, true
	end

	return nil, false
end

local function disconnectPendingNametagWait(lootModel: Model): ()
	local pending = pendingNametagDescendantAdded[lootModel]
	if pending then
		pending:Disconnect()
		pendingNametagDescendantAdded[lootModel] = nil
	end

	local timeoutThread = pendingNametagTimeout[lootModel]
	if timeoutThread then
		pendingNametagTimeout[lootModel] = nil
		task.cancel(timeoutThread)
	end
end

local function getLootIdAttribute(lootModel: Model): string?
	local lootId = lootModel:GetAttribute("LootId")
	if typeof(lootId) == "string" and lootId ~= "" then
		return lootId
	end

	return nil
end

local function getCashValueAttribute(lootModel: Model): number?
	local cashValue = lootModel:GetAttribute("CashValue")
	if typeof(cashValue) == "number" then
		return cashValue
	end

	return nil
end

local function getRarityAttribute(lootModel: Model): string?
	local rarity = lootModel:GetAttribute("Rarity")
	if typeof(rarity) == "string" and rarity ~= "" then
		return rarity
	end

	return nil
end

local function populateNametag(billboard: BillboardGui, lootModel: Model): boolean
	local lootId = getLootIdAttribute(lootModel)
	if lootId == nil then
		return false
	end

	local itemEntry = LootConfig.GetItem(lootId)
	if itemEntry == nil then
		warn(`[LootNametagHandler] Unknown loot id "{lootId}"`)
		return false
	end

	local itemName = billboard:FindFirstChild(LootNametagConfig.ITEM_NAME_LABEL)
	if itemName and itemName:IsA("TextLabel") then
		itemName.Text = itemEntry.Name
	end

	local rarity = getRarityAttribute(lootModel) or itemEntry.Rarity
	LootNametagConfig.applyRarityStyle(billboard, rarity)

	local cashValue = getCashValueAttribute(lootModel) or itemEntry.BaseSellValue
	local displaySellValue = CashUtil.ComputeSellValue(cashValue, getLocalCashMultiplier())
	local itemWorth = billboard:FindFirstChild(LootNametagConfig.ITEM_WORTH_LABEL)
	if itemWorth and itemWorth:IsA("TextLabel") then
		itemWorth.Text = `${NumberFormatter.Format(displaySellValue)}`
	end

	return true
end

local function clearLootNametagState(lootModel: Model): ()
	disconnectPendingNametagWait(lootModel)

	local state = nametagStates[lootModel]
	if state == nil then
		trackedModels[lootModel] = nil
		return
	end

	state.destroyingConnection:Disconnect()
	LootNametagPool.release(state.billboard)
	nametagStates[lootModel] = nil
	trackedModels[lootModel] = nil
end

local function bindNametagToLoot(lootModel: Model, adornee: LootNametagAdornee, usedPrimaryPartFallback: boolean): boolean
	local billboard = LootNametagPool.acquire()
	if billboard == nil then
		return false
	end

	if not populateNametag(billboard, lootModel) then
		LootNametagPool.release(billboard)
		return false
	end

	if usedPrimaryPartFallback then
		warn(`[LootNametagHandler] Loot model {lootModel:GetFullName()} is missing {LootNametagConfig.NAMETAG_ANCHOR_NAME}; falling back to PrimaryPart`)
	end

	billboard.Adornee = adornee
	if adornee:IsA("Attachment") then
		billboard.Parent = lootModel
	else
		billboard.Parent = adornee
	end

	nametagStates[lootModel] = {
		billboard = billboard,
		destroyingConnection = lootModel.Destroying:Connect(function()
			clearLootNametagState(lootModel)
		end),
	}

	return true
end

local function tryBindNametag(lootModel: Model, allowPrimaryPartFallback: boolean): boolean
	if nametagStates[lootModel] ~= nil then
		disconnectPendingNametagWait(lootModel)
		return true
	end

	if not trackedModels[lootModel] or lootModel.Parent == nil then
		return false
	end

	if not CollectionService:HasTag(lootModel, LOOT_PICKUP_TAG) then
		return false
	end

	local adornee, usedPrimaryPartFallback = resolveNametagAdornee(lootModel, allowPrimaryPartFallback)
	if adornee == nil then
		return false
	end

	if not bindNametagToLoot(lootModel, adornee, usedPrimaryPartFallback) then
		return false
	end

	disconnectPendingNametagWait(lootModel)
	return true
end

local function listenForNametagAdornee(lootModel: Model): ()
	if pendingNametagDescendantAdded[lootModel] ~= nil then
		return
	end

	pendingNametagDescendantAdded[lootModel] = lootModel.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("Attachment") and descendant.Name == LootNametagConfig.NAMETAG_ANCHOR_NAME then
			tryBindNametag(lootModel, false)
			return
		end

		-- PrimaryPart often replicates with NametagAnchor already parented under it, so only
		-- the BasePart fires DescendantAdded. Retry anchor lookup without PrimaryPart fallback.
		if descendant:IsA("BasePart") then
			tryBindNametag(lootModel, false)
		end
	end)

	pendingNametagTimeout[lootModel] = task.delay(LOOT_MODEL_WAIT_TIMEOUT, function()
		pendingNametagTimeout[lootModel] = nil

		if nametagStates[lootModel] ~= nil then
			return
		end

		disconnectPendingNametagWait(lootModel)

		if not trackedModels[lootModel] or not CollectionService:HasTag(lootModel, LOOT_PICKUP_TAG) then
			trackedModels[lootModel] = nil
			return
		end

		if tryBindNametag(lootModel, true) then
			return
		end

		warn(`[LootNametagHandler] Loot model {lootModel:GetFullName()} is missing {LootNametagConfig.NAMETAG_ANCHOR_NAME} and PrimaryPart`)
		trackedModels[lootModel] = nil
	end)

	tryBindNametag(lootModel, false)
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

		if tryBindNametag(lootModel, false) then
			return
		end

		listenForNametagAdornee(lootModel)
	end)
end

local function refreshTrackedNametagWorth(): ()
	for lootModel, state in nametagStates do
		if lootModel.Parent == nil then
			continue
		end

		populateNametag(state.billboard, lootModel)
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

	clearLootNametagState(instance)
end

for _, lootModel in CollectionService:GetTagged(LOOT_PICKUP_TAG) do
	onLootPickupAdded(lootModel)
end

CollectionService:GetInstanceAddedSignal(LOOT_PICKUP_TAG):Connect(onLootPickupAdded)
CollectionService:GetInstanceRemovedSignal(LOOT_PICKUP_TAG):Connect(onLootPickupRemoved)
player:GetAttributeChangedSignal("Rebirths"):Connect(refreshTrackedNametagWorth)

--[[
	SELF-AUDIT (Section 7):
	- lootModel.Destroying:Connect — stored in nametagStates[lootModel].destroyingConnection,
	  disconnected in clearLootNametagState; guarded by trackedModels against double-track. OK.
	- CollectionService LootPickup added/removed signals:Connect — script-lifetime singletons;
	  removed signal drives pool release when loot is collected. OK.
	- Rebirths GetAttributeChangedSignal — refreshes worth labels when cash multiplier changes. OK.
	- task.defer (trackLootModel) — single immediate deferral; falls back to DescendantAdded wait
	  for pooled re-activate replication. OK.
	- task.delay (LOOT_MODEL_WAIT_TIMEOUT) — one-shot per tracked model; cancelled on bind or
	  clearLootNametagState; warns only if adornee still missing after timeout. OK.
	- lootModel.DescendantAdded:Connect — pendingNametagDescendantAdded per model; retries anchor
	  lookup on NametagAnchor or BasePart (anchor may replicate nested under PrimaryPart); PrimaryPart
	  fallback only after LOOT_MODEL_WAIT_TIMEOUT. OK.
	- LootNametagPool.acquire/release — BillboardGui pooling; no hot-path Instance.new. OK.
]]
