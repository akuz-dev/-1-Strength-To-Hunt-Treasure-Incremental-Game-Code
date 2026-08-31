--!strict

--[[
	Debounced character-position refresh for distance-gated client presentation.
	Shared by loot spin, VFX, and nametag handlers.

	Uses Heartbeat to sample HumanoidRootPart.Position because GetPropertyChangedSignal("Position")
	does not fire for Humanoid / physics walking — only for scripted Position writes.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

export type ClientPresentationDistanceModule = {
	getDistanceToPosition: (worldPosition: Vector3) -> number?,
	getDistanceToPart: (part: BasePart) -> number?,
	subscribeRefresh: (callback: () -> ()) -> () -> (),
}

local REFRESH_DEBOUNCE_SEC = 0.15
-- Jitter gate so idle physics micro-moves do not schedule a refresh. Not a presentation radius.
local MOVEMENT_REFRESH_THRESHOLD_STUDS = 1

local refreshCallbacks: { () -> () } = {}
local pendingRefreshThread: thread? = nil
local characterPositionConnection: RBXScriptConnection? = nil
local lastSampledPosition: Vector3? = nil

local function getLocalRootPart(): BasePart?
	local character = Players.LocalPlayer.Character
	if character == nil then
		return nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart == nil or not rootPart:IsA("BasePart") then
		return nil
	end

	return rootPart
end

local function getDistanceToPosition(worldPosition: Vector3): number?
	local rootPart = getLocalRootPart()
	if rootPart == nil then
		return nil
	end

	return (rootPart.Position - worldPosition).Magnitude
end

local function getDistanceToPart(part: BasePart): number?
	return getDistanceToPosition(part.Position)
end

local function runRefreshCallbacks(): ()
	for _, callback in refreshCallbacks do
		callback()
	end
end

local function scheduleRefresh(): ()
	if pendingRefreshThread then
		return
	end

	pendingRefreshThread = task.delay(REFRESH_DEBOUNCE_SEC, function()
		pendingRefreshThread = nil
		runRefreshCallbacks()
	end)
end

local function disconnectCharacterPositionConnection(): ()
	if characterPositionConnection then
		characterPositionConnection:Disconnect()
		characterPositionConnection = nil
	end

	lastSampledPosition = nil
end

local function bindCharacterRefresh(character: Model): ()
	disconnectCharacterPositionConnection()

	local rootPart = character:WaitForChild("HumanoidRootPart", 5)
	if rootPart == nil or not rootPart:IsA("BasePart") then
		return
	end

	lastSampledPosition = rootPart.Position
	characterPositionConnection = RunService.Heartbeat:Connect(function()
		local position = rootPart.Position
		local previousPosition = lastSampledPosition
		if previousPosition ~= nil and (position - previousPosition).Magnitude < MOVEMENT_REFRESH_THRESHOLD_STUDS then
			return
		end

		lastSampledPosition = position
		scheduleRefresh()
	end)
end

local function subscribeRefresh(callback: () -> ()): () -> ()
	table.insert(refreshCallbacks, callback)

	return function()
		local index = table.find(refreshCallbacks, callback)
		if index then
			table.remove(refreshCallbacks, index)
		end
	end
end

local localPlayer = Players.LocalPlayer
if localPlayer then
	if localPlayer.Character then
		bindCharacterRefresh(localPlayer.Character)
		scheduleRefresh()
	end

	localPlayer.CharacterAdded:Connect(function(character: Model)
		bindCharacterRefresh(character)
		scheduleRefresh()
	end)

	localPlayer.CharacterRemoving:Connect(disconnectCharacterPositionConnection)
end

local ClientPresentationDistance: ClientPresentationDistanceModule = {
	getDistanceToPosition = getDistanceToPosition,
	getDistanceToPart = getDistanceToPart,
	subscribeRefresh = subscribeRefresh,
}

return ClientPresentationDistance

--[[
	SELF-AUDIT (Section 7):
	- RunService.Heartbeat:Connect — stored in characterPositionConnection; disconnected in
	  disconnectCharacterPositionConnection on CharacterRemoving and before rebind on CharacterAdded.
	  Samples HumanoidRootPart.Position and only calls scheduleRefresh after a 1-stud move. OK.
	- localPlayer.CharacterAdded:Connect / CharacterRemoving:Connect — script-lifetime singletons. OK.
	- task.delay (scheduleRefresh) — one pending debounce thread; cancelled implicitly by replacing
	  pendingRefreshThread nil-check (next schedule is a no-op until the delay completes). OK.
]]
