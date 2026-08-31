--!strict

--[[
	Per-player ReplicationFocus that tracks zone-strip progress only.
	Focus part moves on the progress axis (measured from tagged obstacles);
	the other two axes stay fixed at mid-strip so sidestepping a wall does
	not stream obstacles in/out.

	Heartbeat (not GetPropertyChangedSignal("Position")): GDD 5.4.1 — Humanoid
	/ physics walking does not fire Position changed. Distance-gated so this is
	not a bare poll (GDD 5.2).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local OBSTACLE_TAG = "Obstacle"
local FOCUS_FOLDER_NAME = "StreamFocusPoints"
local WAIT_TIMEOUT = 5
-- StreamingMinRadius is 256; sub-this-stud jitter must not rewrite ReplicationFocus.
local MIN_PROGRESS_DELTA_STUDS = 8

type ProgressAxis = "X" | "Z"

type StreamLayout = {
	progressAxis: ProgressAxis,
	fixedX: number,
	fixedY: number,
	fixedZ: number,
}

type PlayerFocusState = {
	focusPart: BasePart,
	heartbeatConnection: RBXScriptConnection?,
	characterAddedConnection: RBXScriptConnection?,
	lastProgress: number,
}

local focusStateByUserId: { [number]: PlayerFocusState } = {}

local function getTaggedWorldPosition(instance: Instance): Vector3?
	if instance:IsA("BasePart") then
		return instance.Position
	end

	if instance:IsA("Model") then
		return instance:GetPivot().Position
	end

	local model = instance:FindFirstAncestorOfClass("Model")
	if model then
		return model:GetPivot().Position
	end

	return nil
end

local function midpoint(minValue: number, maxValue: number): number
	return (minValue + maxValue) / 2
end

local function measureStreamLayout(): StreamLayout
	local minX = math.huge
	local maxX = -math.huge
	local minY = math.huge
	local maxY = -math.huge
	local minZ = math.huge
	local maxZ = -math.huge
	local sampleCount = 0

	for _, tagged in CollectionService:GetTagged(OBSTACLE_TAG) do
		local position = getTaggedWorldPosition(tagged)
		if position ~= nil then
			sampleCount += 1
			minX = math.min(minX, position.X)
			maxX = math.max(maxX, position.X)
			minY = math.min(minY, position.Y)
			maxY = math.max(maxY, position.Y)
			minZ = math.min(minZ, position.Z)
			maxZ = math.max(maxZ, position.Z)
		end
	end

	if sampleCount == 0 then
		local spawnLocation = Workspace:FindFirstChildWhichIsA("SpawnLocation")
		local spawnPosition = if spawnLocation and spawnLocation:IsA("BasePart")
			then spawnLocation.Position
			else Vector3.new(0, 5, 0)

		warn(
			"[ZoneStreamFocus] No Obstacle-tagged instances to measure; falling back to X progress axis and spawn Y/Z"
		)

		return {
			progressAxis = "X",
			fixedX = spawnPosition.X,
			fixedY = spawnPosition.Y,
			fixedZ = spawnPosition.Z,
		}
	end

	local xSpan = maxX - minX
	local zSpan = maxZ - minZ
	-- Larger horizontal span is the strip; GDD assumes X, confirmed against live obstacle AABB.
	local progressAxis: ProgressAxis = if xSpan >= zSpan then "X" else "Z"

	local layout: StreamLayout = {
		progressAxis = progressAxis,
		fixedX = midpoint(minX, maxX),
		fixedY = midpoint(minY, maxY),
		fixedZ = midpoint(minZ, maxZ),
	}

	print(
		`[ZoneStreamFocus] Progress axis={progressAxis} (X span={string.format("%.1f", xSpan)}, Z span={string.format("%.1f", zSpan)}); fixed Y={string.format("%.1f", layout.fixedY)} lateral={string.format("%.1f", if progressAxis == "X" then layout.fixedZ else layout.fixedX)} from {sampleCount} tagged obstacle(s)`
	)

	return layout
end

local streamLayout = measureStreamLayout()

local function getOrCreateFocusFolder(): Folder
	local existing = Workspace:FindFirstChild(FOCUS_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = FOCUS_FOLDER_NAME
	folder.Parent = Workspace
	return folder
end

local focusFolder = getOrCreateFocusFolder()

local function readProgress(position: Vector3): number
	if streamLayout.progressAxis == "X" then
		return position.X
	end

	return position.Z
end

local function focusPositionForProgress(progress: number): Vector3
	if streamLayout.progressAxis == "X" then
		return Vector3.new(progress, streamLayout.fixedY, streamLayout.fixedZ)
	end

	return Vector3.new(streamLayout.fixedX, streamLayout.fixedY, progress)
end

local function applyFocusProgress(state: PlayerFocusState, progress: number): ()
	state.lastProgress = progress
	state.focusPart.Position = focusPositionForProgress(progress)
end

local function tryUpdateFocusFromCharacter(userId: number): ()
	local state = focusStateByUserId[userId]
	if state == nil then
		return
	end

	local player = Players:GetPlayerByUserId(userId)
	if player == nil then
		return
	end

	local character = player.Character
	if character == nil then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart == nil or not rootPart:IsA("BasePart") then
		return
	end

	local progress = readProgress(rootPart.Position)
	if math.abs(progress - state.lastProgress) < MIN_PROGRESS_DELTA_STUDS then
		return
	end

	applyFocusProgress(state, progress)
end

local function snapFocusToCharacter(userId: number, character: Model): ()
	local state = focusStateByUserId[userId]
	if state == nil then
		return
	end

	local rootPart = character:WaitForChild("HumanoidRootPart", WAIT_TIMEOUT)
	if rootPart == nil or not rootPart:IsA("BasePart") then
		return
	end

	if focusStateByUserId[userId] ~= state then
		return
	end

	applyFocusProgress(state, readProgress(rootPart.Position))
end

local function disconnectFocusConnections(state: PlayerFocusState): ()
	local heartbeatConnection = state.heartbeatConnection
	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		state.heartbeatConnection = nil
	end

	local characterAddedConnection = state.characterAddedConnection
	if characterAddedConnection then
		characterAddedConnection:Disconnect()
		state.characterAddedConnection = nil
	end
end

local function destroyPlayerFocus(userId: number): ()
	local state = focusStateByUserId[userId]
	if state == nil then
		return
	end

	focusStateByUserId[userId] = nil
	disconnectFocusConnections(state)

	local player = Players:GetPlayerByUserId(userId)
	if player and player.ReplicationFocus == state.focusPart then
		player.ReplicationFocus = nil
	end

	state.focusPart:Destroy()
end

local function createFocusPart(userId: number): BasePart
	local focusPart = Instance.new("Part")
	focusPart.Name = `StreamFocus_{userId}`
	focusPart.Anchored = true
	focusPart.CanCollide = false
	focusPart.CanQuery = false
	focusPart.CanTouch = false
	focusPart.CastShadow = false
	focusPart.Massless = true
	focusPart.Size = Vector3.new(1, 1, 1)
	focusPart.Transparency = 1
	local initialProgress = if streamLayout.progressAxis == "X" then streamLayout.fixedX else streamLayout.fixedZ
	focusPart.Position = focusPositionForProgress(initialProgress)
	focusPart.Parent = focusFolder
	return focusPart
end

local function onPlayerAdded(player: Player): ()
	local userId = player.UserId
	if focusStateByUserId[userId] ~= nil then
		return
	end

	local focusPart = createFocusPart(userId)
	player.ReplicationFocus = focusPart

	local state: PlayerFocusState = {
		focusPart = focusPart,
		heartbeatConnection = nil,
		characterAddedConnection = nil,
		lastProgress = readProgress(focusPart.Position),
	}
	focusStateByUserId[userId] = state

	-- Throttled Heartbeat: only writes when progress-axis movement exceeds MIN_PROGRESS_DELTA_STUDS.
	state.heartbeatConnection = RunService.Heartbeat:Connect(function()
		tryUpdateFocusFromCharacter(userId)
	end)

	state.characterAddedConnection = player.CharacterAdded:Connect(function(character: Model)
		local currentPlayer = Players:GetPlayerByUserId(userId)
		local currentState = focusStateByUserId[userId]
		if currentPlayer == nil or currentState == nil then
			return
		end

		currentPlayer.ReplicationFocus = currentState.focusPart
		snapFocusToCharacter(userId, character)
	end)

	local existingCharacter = player.Character
	if existingCharacter then
		task.spawn(snapFocusToCharacter, userId, existingCharacter)
	end
end

local function onPlayerRemoving(player: Player): ()
	destroyPlayerFocus(player.UserId)
end

for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

--[[
	SELF-AUDIT (Section 7):
	- RunService.Heartbeat:Connect — stored in focusStateByUserId[userId].heartbeatConnection;
	  disconnected in disconnectFocusConnections on PlayerRemoving; closure holds userId only
	  and re-resolves Player each tick (anti-pattern A). Distance-gated by
	  MIN_PROGRESS_DELTA_STUDS; not a while-true poll. OK.
	- player.CharacterAdded:Connect — stored per userId, disconnected on PlayerRemoving;
	  re-asserts ReplicationFocus and snaps progress (anti-pattern B: torn down with the
	  player, not left dangling across sessions). OK.
	- Players.PlayerAdded/PlayerRemoving:Connect — script-lifetime singletons; Removing
	  destroys the focus part and disconnects per-player connections. OK.
	- Instance.new (Folder, Part) — one Folder at script start; one Part per player join,
	  :Destroy()'d on PlayerRemoving. Not a hit/break hot path. OK.
	- character:WaitForChild("HumanoidRootPart", 5) — one-shot per spawn inside CharacterAdded
	  / initial task.spawn; bails if focus state was cleared while waiting. OK.
	- task.spawn (snapFocusToCharacter on existing character) — one-shot so PlayerAdded does
	  not yield before CharacterAdded is connected; closes over userId + character for the
	  wait only. OK.
]]
