--!strict

--[[
	One-time streaming-mode setup (GDD 5.4).
	Obstacle-tagged models stream with Default (progress-axis ReplicationFocus).
	Non-obstacle world Models stay Persistent so hub/spawn/map never stream out.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local OBSTACLE_TAG = "Obstacle"
local OBSTACLES_FOLDER_NAME = "Obstacles"
local INSIDE_OBSTACLE_LOOT_NAME = "InsideObstacleLoot"
local WAIT_TIMEOUT = 5

-- Workspace children that must not be forced Persistent: they either stream
-- on purpose (obstacles, loot) or are engine/player objects.
local SKIP_PERSIST_CHILD_NAMES: { [string]: boolean } = {
	Obstacles = true,
	ActiveLoot = true,
	StreamFocusPoints = true,
	Baseplate = true,
	Terrain = true,
	Camera = true,
}

local function resolveStreamingModel(instance: Instance): Model?
	if instance:IsA("Model") then
		return instance
	end

	return instance:FindFirstAncestorOfClass("Model")
end

local function isInsideObstacleLoot(instance: Instance): boolean
	return string.lower(instance.Name) == string.lower(INSIDE_OBSTACLE_LOOT_NAME)
end

local function hasObstacleTagInTree(instance: Instance): boolean
	if CollectionService:HasTag(instance, OBSTACLE_TAG) then
		return true
	end

	for _, descendant in instance:GetDescendants() do
		if CollectionService:HasTag(descendant, OBSTACLE_TAG) then
			return true
		end
	end

	return false
end

local function applyObstacleDefaultStreaming(instance: Instance): boolean
	local model = resolveStreamingModel(instance)
	if model == nil then
		warn(`[StreamingSetup] Tagged obstacle {instance:GetFullName()} has no Model ancestor; ModelStreamingMode not set`)
		return false
	end

	model.ModelStreamingMode = Enum.ModelStreamingMode.Default
	return true
end

local function isUnderObstaclesFolder(instance: Instance): boolean
	local current: Instance? = instance.Parent
	while current and current ~= Workspace do
		if current.Name == OBSTACLES_FOLDER_NAME and not current:IsA("Model") then
			return true
		end
		current = current.Parent
	end

	return false
end

local function applyPersistentIfModel(instance: Instance, persistedNames: { string }): ()
	if not instance:IsA("Model") then
		return
	end

	if CollectionService:HasTag(instance, OBSTACLE_TAG) or isUnderObstaclesFolder(instance) then
		return
	end

	instance.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	table.insert(persistedNames, instance:GetFullName())
end

local function shouldSkipPersistChild(child: Instance): boolean
	if SKIP_PERSIST_CHILD_NAMES[child.Name] then
		return true
	end

	if child:IsA("Model") and Players:GetPlayerFromCharacter(child) ~= nil then
		return true
	end

	return false
end

local function persistNonObstacleWorldModels(): { string }
	local persistedNames: { string } = {}

	for _, child in Workspace:GetChildren() do
		if not shouldSkipPersistChild(child) then
			if child:IsA("Model") then
				applyPersistentIfModel(child, persistedNames)
			elseif child:IsA("Folder") then
				-- Persist Models in whatever map/hub/spawn folder Studio actually has.
				-- Do not invent a MapStructure name.
				for _, descendant in child:GetDescendants() do
					applyPersistentIfModel(descendant, persistedNames)
				end
			end
		end
	end

	return persistedNames
end

local function reportUntaggedObstacles(obstaclesFolder: Instance): { string }
	local untaggedNames: { string } = {}

	for _, child in obstaclesFolder:GetChildren() do
		if not isInsideObstacleLoot(child) and not hasObstacleTagInTree(child) then
			table.insert(untaggedNames, child:GetFullName())
			warn(`[StreamingSetup] Possible untagged obstacle (not auto-tagged): {child:GetFullName()}`)
		end
	end

	return untaggedNames
end

-- Defer so ObstacleManager can wrap tagged parts in Models before we set streaming mode.
-- Persistent first, then Obstacle Default, so nested Obstacles cannot inherit Persistent.
task.defer(function()
	local obstaclesFolder = Workspace:FindFirstChild(OBSTACLES_FOLDER_NAME)
	if obstaclesFolder == nil then
		local waited = Workspace:WaitForChild(OBSTACLES_FOLDER_NAME, WAIT_TIMEOUT)
		if waited then
			obstaclesFolder = waited
		end
	end

	if obstaclesFolder and obstaclesFolder:IsA("Model") then
		-- Folder is expected (SandObstacleUtil); if Studio used a Model, do not persist the whole pile.
		obstaclesFolder.ModelStreamingMode = Enum.ModelStreamingMode.Default
	end

	local untaggedNames: { string } = {}
	if obstaclesFolder then
		untaggedNames = reportUntaggedObstacles(obstaclesFolder)
	else
		warn(
			`[StreamingSetup] Workspace.{OBSTACLES_FOLDER_NAME} not found within {WAIT_TIMEOUT}s; cannot audit untagged obstacles`
		)
	end

	local persistedNames = persistNonObstacleWorldModels()

	local taggedCount = 0
	for _, tagged in CollectionService:GetTagged(OBSTACLE_TAG) do
		if applyObstacleDefaultStreaming(tagged) then
			taggedCount += 1
		end
	end

	print(
		`[StreamingSetup] Obstacle tag Default streaming: {taggedCount} instance(s); Persistent world Models: {#persistedNames}; untagged under {OBSTACLES_FOLDER_NAME}: {#untaggedNames}`
	)
end)

--[[
	SELF-AUDIT (Section 7):
	- No :Connect() — one-time start-up loop only (GetTagged + Workspace children). OK.
	- No Instance.new() — only writes ModelStreamingMode on existing instances. OK.
	- WaitForChild(Obstacles, 5) — one-shot inside task.defer, not a connection. OK.
	- task.defer — one immediate deferral so ObstacleManager can wrap segments first;
	  no captured Player/Model. OK.
]]
