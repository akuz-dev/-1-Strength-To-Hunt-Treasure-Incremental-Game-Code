--!strict

--[[
	Section 6 pool for loot pickup Models cloned from ReplicatedStorage.Assets.Loot templates.
	Clone is confined to this module; callers acquire/release instead of Destroy.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local LootConfig = require(ReplicatedStorage.Shared.LootConfig)
local LootModelUtil = require(ReplicatedStorage.Shared.LootModelUtil)
local LootPrefabSetup = require(ReplicatedStorage.Shared.LootPrefabSetup)

local LOOT_PICKUP_TAG = "LootPickup"
local STORAGE_FOLDER_NAME = "LootPickupPool"
local LOOT_ASSETS_PATH = { "Assets", "Loot" }
local LOOT_FOLDER_NAME = "ActiveLoot"
local OFFSCREEN_STORAGE_CFRAME = CFrame.new(0, -500, 0)
local TEMPLATE_WAIT_TIMEOUT = 5
local PROMPT_MAX_ACTIVATION_DISTANCE = 10
local PROMPT_ACTION_TEXT = "Collect"
local SOURCE_OBSTACLE_VALUE_NAME = "SourceObstacle"

type LootItemEntry = LootConfig.LootItemEntry

type LootPoolModule = {
	acquire: (lootId: string) -> Model?,
	activate: (
		model: Model,
		spawnCFrame: CFrame,
		sourceSegment: BasePart,
		itemEntry: LootItemEntry,
		canCollect: (player: Player) -> boolean,
		onCollected: (player: Player) -> boolean
	) -> boolean,
	release: (model: Model) -> (),
	getAvailableLootIds: () -> { [string]: boolean },
}

local availableByLootId: { [string]: { Model } } = {}
local templatesByLootId: { [string]: Model } = {}
local availableLootIds: { [string]: boolean } = {}
local triggeredConnectionsByModel: { [Model]: RBXScriptConnection } = {}

local storageFolder = Instance.new("Folder")
storageFolder.Name = STORAGE_FOLDER_NAME
storageFolder.Parent = ServerStorage

local activeLootFolder: Folder

local function getActiveLootFolder(): Folder
	if activeLootFolder and activeLootFolder.Parent then
		return activeLootFolder
	end

	local existingFolder = Workspace:FindFirstChild(LOOT_FOLDER_NAME)
	if existingFolder and existingFolder:IsA("Folder") then
		activeLootFolder = existingFolder
		return activeLootFolder
	end

	local lootFolder = Instance.new("Folder")
	lootFolder.Name = LOOT_FOLDER_NAME
	lootFolder.Parent = Workspace
	activeLootFolder = lootFolder
	return activeLootFolder
end

local function resolveLootAssetsFolder(): Folder?
	local current: Instance = ReplicatedStorage
	for _, childName in LOOT_ASSETS_PATH do
		local child = current:FindFirstChild(childName)
		if child == nil then
			child = current:WaitForChild(childName, TEMPLATE_WAIT_TIMEOUT)
		end
		if child == nil or not child:IsA("Folder") then
			warn(`[LootPool] Missing ReplicatedStorage.{table.concat(LOOT_ASSETS_PATH, ".")} folder`)
			return nil
		end
		current = child
	end

	return current
end

local function getOrCreateProximityPrompt(primaryPart: BasePart): ProximityPrompt
	local existingPrompt = primaryPart:FindFirstChildOfClass("ProximityPrompt")
	if existingPrompt then
		return existingPrompt
	end

	for _, descendant in primaryPart:GetDescendants() do
		if descendant:IsA("ProximityPrompt") then
			return descendant
		end
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "LootProximityPrompt"
	prompt.Parent = primaryPart
	return prompt
end

local function findProximityPrompt(primaryPart: BasePart): ProximityPrompt?
	local prompt = primaryPart:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		return prompt
	end

	for _, descendant in primaryPart:GetDescendants() do
		if descendant:IsA("ProximityPrompt") then
			return descendant
		end
	end

	return nil
end

local function getOrCreateSourceObstacleValue(model: Model): ObjectValue
	local existing = model:FindFirstChild(SOURCE_OBSTACLE_VALUE_NAME)
	if existing and existing:IsA("ObjectValue") then
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local sourceObstacleValue = Instance.new("ObjectValue")
	sourceObstacleValue.Name = SOURCE_OBSTACLE_VALUE_NAME
	sourceObstacleValue.Parent = model
	return sourceObstacleValue
end

local function configureProximityPrompt(prompt: ProximityPrompt, itemEntry: LootItemEntry): ()
	prompt.ActionText = PROMPT_ACTION_TEXT
	prompt.ObjectText = itemEntry.Name
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = PROMPT_MAX_ACTIVATION_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
end

local function prepareTemplateModel(model: Model): boolean
	local primaryPart = LootModelUtil.findPrimaryPart(model)
	if primaryPart == nil then
		warn(`[LootPool] Loot template {model:GetFullName()} is missing a PrimaryPart`)
		return false
	end

	primaryPart.Anchored = true
	primaryPart.CanCollide = false
	primaryPart.CanTouch = false

	local prompt = getOrCreateProximityPrompt(primaryPart)
	prompt.Enabled = false

	return true
end

local function loadTemplates(): ()
	local lootAssetsFolder = resolveLootAssetsFolder()
	if lootAssetsFolder == nil then
		return
	end

	for _, lootId in LootConfig.GetAllLootIds() do
		local template = lootAssetsFolder:FindFirstChild(lootId)
		if template == nil then
			template = lootAssetsFolder:WaitForChild(lootId, TEMPLATE_WAIT_TIMEOUT)
		end

		if template == nil or not template:IsA("Model") then
			warn(`[LootPool] Missing loot Model template "{lootId}" under ReplicatedStorage.Assets.Loot`)
			continue
		end

		if LootModelUtil.findPrimaryPart(template) == nil then
			warn(`[LootPool] Loot template {template:GetFullName()} is missing a PrimaryPart`)
			continue
		end

		LootPrefabSetup.SetupLootPrefab(template)

		if not prepareTemplateModel(template) then
			continue
		end

		templatesByLootId[lootId] = template
		availableByLootId[lootId] = {}
		availableLootIds[lootId] = true
	end
end

local function disconnectTriggeredConnection(model: Model): ()
	local existingConnection = triggeredConnectionsByModel[model]
	if existingConnection then
		existingConnection:Disconnect()
		triggeredConnectionsByModel[model] = nil
	end
end

local function resetModel(model: Model): ()
	disconnectTriggeredConnection(model)

	CollectionService:RemoveTag(model, LOOT_PICKUP_TAG)

	local primaryPart = LootModelUtil.findPrimaryPart(model)
	if primaryPart then
		local prompt = findProximityPrompt(primaryPart)
		if prompt then
			prompt.Enabled = false
		end
	end

	model:SetAttribute("LootId", nil)
	model:SetAttribute("Rarity", nil)
	model:SetAttribute("CashValue", nil)
	local sourceObstacleValue = model:FindFirstChild(SOURCE_OBSTACLE_VALUE_NAME)
	if sourceObstacleValue and sourceObstacleValue:IsA("ObjectValue") then
		sourceObstacleValue.Value = nil
	end
	model:PivotTo(OFFSCREEN_STORAGE_CFRAME)
	model.Parent = storageFolder
end

local function acquire(lootId: string): Model?
	local template = templatesByLootId[lootId]
	if template == nil then
		return nil
	end

	local pool = availableByLootId[lootId]
	local model = if pool then table.remove(pool) else nil
	if model == nil then
		model = template:Clone()
		LootPrefabSetup.SetupLootPrefab(model)
		if not prepareTemplateModel(model) then
			model:Destroy()
			return nil
		end
	end

	return model
end

local function release(model: Model): ()
	local lootId = model:GetAttribute("LootId")
	if typeof(lootId) ~= "string" or lootId == "" then
		disconnectTriggeredConnection(model)
		model:Destroy()
		return
	end

	resetModel(model)

	local pool = availableByLootId[lootId]
	if pool == nil then
		pool = {}
		availableByLootId[lootId] = pool
	end

	table.insert(pool, model)
end

local function activate(
	model: Model,
	spawnCFrame: CFrame,
	sourceSegment: BasePart,
	itemEntry: LootItemEntry,
	canCollect: (player: Player) -> boolean,
	onCollected: (player: Player) -> boolean
): boolean
	local primaryPart = LootModelUtil.findPrimaryPart(model)
	if primaryPart == nil then
		return false
	end

	disconnectTriggeredConnection(model)

	model:SetAttribute("LootId", itemEntry.ItemId)
	model:SetAttribute("Rarity", itemEntry.Rarity)
	model:SetAttribute("CashValue", itemEntry.BaseSellValue)
	local sourceObstacleValue = getOrCreateSourceObstacleValue(model)
	sourceObstacleValue.Value = sourceSegment
	model:PivotTo(spawnCFrame)
	model.Parent = getActiveLootFolder()
	CollectionService:AddTag(model, LOOT_PICKUP_TAG)

	local prompt = getOrCreateProximityPrompt(primaryPart)
	configureProximityPrompt(prompt, itemEntry)
	prompt.Enabled = true

	local triggeredConnection: RBXScriptConnection
	triggeredConnection = prompt.Triggered:Connect(function(playerWhoTriggered: Player)
		if not canCollect(playerWhoTriggered) then
			return
		end

		if onCollected(playerWhoTriggered) then
			prompt.Enabled = false
			disconnectTriggeredConnection(model)
		end
	end)
	triggeredConnectionsByModel[model] = triggeredConnection

	return true
end

local function getAvailableLootIds(): { [string]: boolean }
	return availableLootIds
end

loadTemplates()

local LootPool: LootPoolModule = {
	acquire = acquire,
	activate = activate,
	release = release,
	getAvailableLootIds = getAvailableLootIds,
}

return LootPool

--[[
	SELF-AUDIT (Section 7):
	- ProximityPrompt.Triggered:Connect — stored in triggeredConnectionsByModel per model;
	  disconnected on successful collect or in resetModel/release. OK.
	- Instance.new (Folder, ProximityPrompt, ObjectValue) — Folder at init; ProximityPrompt only in
	  getOrCreateProximityPrompt when template lacks one; ObjectValue SourceObstacle only in
	  getOrCreateSourceObstacleValue when the pooled model lacks one. OK.
	- LootPrefabSetup.SetupLootPrefab — once per unique template in loadTemplates; also on new
	  clones in acquire (idempotent). WeldConstraints guarded; clones inherit welds/reparented NametagAnchor. OK.
	- template:Clone() — confined to acquire(); released models return to pool instead of Destroy. OK.
]]
