--!strict



local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Workspace = game:GetService("Workspace")



local AttackZoneConfig = require(ReplicatedStorage.Shared.AttackZoneConfig)

local ObstacleAPI = require(script.Parent.ObstacleAPI)

local PlayerDataService = require(ReplicatedStorage.Shared.PlayerDataService)

local SafeZoneAPI = require(script.Parent.SafeZoneAPI)



local ATTACK_ZONE_NAME = "AttackZone"

local OWNER_USER_ID_ATTRIBUTE = "OwnerUserId"

-- Overlap is re-checked on a fixed interval while the AttackZone exists (not tied to movement).

local OVERLAP_SCAN_INTERVAL = 0.1

-- Require several consecutive missed scans before ending contact (GetPartsInPart can flicker).

local EXIT_MISS_THRESHOLD = 3



export type AttackZoneManagerModule = {

	updateZoneForPlayer: (player: Player) -> (),

	rescanForPlayer: (userId: number) -> (),

}



type PlayerAttackZoneState = {

	attackZone: BasePart?,

	weld: Weld?,

	overlapScanLoopActive: boolean,

	overlappingBlockers: { [BasePart]: boolean },

	exitMissCounts: { [BasePart]: number },

}



local attackZoneStateByUserId: { [number]: PlayerAttackZoneState } = {}

local initialized = false



local function createObstacleOverlapParams(character: Model): OverlapParams

	local params = OverlapParams.new()

	-- Query as Default so Obstacle blockers (Obstacles group) are included.

	-- Do not use FilterType Include without IncludeInstances — that returns nothing.

	params.CollisionGroup = "Default"

	params:AddToFilter(character)

	return params

end



local function getHumanoidRootPart(character: Model): BasePart?

	local rootPart = character:FindFirstChild("HumanoidRootPart")

	if rootPart and rootPart:IsA("BasePart") then

		return rootPart

	end



	return nil

end



local function getRangeLevelForUserId(userId: number): number

	local player = Players:GetPlayerByUserId(userId)

	if player == nil then

		return 0

	end



	local playerData = PlayerDataService.GetData(player)

	if playerData == nil then

		return 0

	end



	return playerData.StatLevels.Range

end



local function resolveBlockerFromOverlapPart(part: BasePart): BasePart?

	return ObstacleAPI.resolveBlockerFromPart(part)

end



local scanAttackZoneOverlaps: (userId: number) -> ()



local function scanAllActiveAttackZones(): ()

	for userId in attackZoneStateByUserId do

		scanAttackZoneOverlaps(userId)

	end

end



local function destroyAttackZoneForUserId(userId: number): ()

	local state = attackZoneStateByUserId[userId]

	if state == nil then

		return

	end



	state.overlapScanLoopActive = false



	ObstacleAPI.stopAllContactForPlayer(userId)



	if state.weld then

		state.weld:Destroy()

		state.weld = nil

	end



	if state.attackZone then

		state.attackZone:Destroy()

		state.attackZone = nil

	end



	attackZoneStateByUserId[userId] = nil

end



local function applyZoneGeometry(state: PlayerAttackZoneState, rangeLevel: number): ()

	local attackZone = state.attackZone

	local weld = state.weld

	if attackZone == nil or weld == nil then

		return

	end



	attackZone.Size = AttackZoneConfig.GetZoneSize(rangeLevel)

	weld.C0 = AttackZoneConfig.GetZoneOffsetCFrame(rangeLevel)

end



local function startOverlapScanLoop(userId: number): ()

	task.spawn(function()

		while true do

			local state = attackZoneStateByUserId[userId]

			if state == nil or not state.overlapScanLoopActive then

				break

			end



			scanAttackZoneOverlaps(userId)

			task.wait(OVERLAP_SCAN_INTERVAL)

		end

	end)

end



local function doesAttackZoneOverlapBlocker(userId: number, blocker: BasePart): boolean

	local state = attackZoneStateByUserId[userId]

	if state == nil then

		return false

	end



	return state.overlappingBlockers[blocker] == true

end



scanAttackZoneOverlaps = function(userId: number): ()

	local state = attackZoneStateByUserId[userId]

	if state == nil then

		return

	end



	local attackZone = state.attackZone

	if attackZone == nil then

		return

	end



	local player = Players:GetPlayerByUserId(userId)

	local character = if player then player.Character else nil

	if character == nil then

		return

	end



	local overlapParams = createObstacleOverlapParams(character)

	local newOverlapping: { [BasePart]: boolean } = {}



	for _, part in Workspace:GetPartsInPart(attackZone, overlapParams) do

		if part:IsA("BasePart") then

			local blocker = resolveBlockerFromOverlapPart(part)

			if blocker then

				if player == nil or not ObstacleAPI.isObstacleBrokenForPlayer(player, blocker) then

					newOverlapping[blocker] = true

				end

			end

		end

	end



	local previousOverlapping = state.overlappingBlockers

	local exitMissCounts = state.exitMissCounts

	local confirmedExits: { BasePart } = {}



	for blocker in previousOverlapping do

		if player and ObstacleAPI.isObstacleBrokenForPlayer(player, blocker) then

			table.insert(confirmedExits, blocker)

			exitMissCounts[blocker] = nil

		elseif newOverlapping[blocker] then

			exitMissCounts[blocker] = nil

		else

			local missCount = (exitMissCounts[blocker] or 0) + 1

			exitMissCounts[blocker] = missCount

			if missCount >= EXIT_MISS_THRESHOLD then

				table.insert(confirmedExits, blocker)

				exitMissCounts[blocker] = nil

			end

		end

	end



	for blocker in newOverlapping do

		exitMissCounts[blocker] = nil

		if not previousOverlapping[blocker] then

			ObstacleAPI.notifyAttackZoneTouched(blocker, userId)

		else

			ObstacleAPI.sustainAttackZoneContact(blocker, userId)

		end

	end



	local nextOverlapping: { [BasePart]: boolean } = {}

	for blocker in newOverlapping do

		nextOverlapping[blocker] = true

	end

	for _, blocker in confirmedExits do

		ObstacleAPI.notifyAttackZoneTouchEnded(blocker, userId)

		nextOverlapping[blocker] = nil

	end

	for blocker, missCount in exitMissCounts do

		if missCount > 0 and previousOverlapping[blocker] then

			nextOverlapping[blocker] = true

		end

	end



	state.overlappingBlockers = nextOverlapping

end



local function createAttackZoneForUserId(userId: number): ()

	if SafeZoneAPI.isPlayerInSafeZone(userId) then

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



	local humanoidRootPart = getHumanoidRootPart(character)

	if humanoidRootPart == nil then

		return

	end



	destroyAttackZoneForUserId(userId)



	local rangeLevel = getRangeLevelForUserId(userId)



	local attackZone = Instance.new("Part")

	attackZone.Name = ATTACK_ZONE_NAME

	attackZone.Transparency = 1

	attackZone.CanCollide = false

	attackZone.CanTouch = false

	attackZone.CanQuery = true

	attackZone.Massless = true

	attackZone.Anchored = false

	attackZone:SetAttribute(OWNER_USER_ID_ATTRIBUTE, userId)

	attackZone.Size = AttackZoneConfig.GetZoneSize(rangeLevel)

	attackZone.Parent = character



	local weld = Instance.new("Weld")

	weld.Name = "AttackZoneWeld"

	weld.Part0 = humanoidRootPart

	weld.Part1 = attackZone

	weld.C0 = AttackZoneConfig.GetZoneOffsetCFrame(rangeLevel)

	weld.C1 = CFrame.new()

	weld.Parent = attackZone



	attackZoneStateByUserId[userId] = {

		attackZone = attackZone,

		weld = weld,

		overlapScanLoopActive = true,

		overlappingBlockers = {},

		exitMissCounts = {},

	}



	startOverlapScanLoop(userId)

end



local function onPlayerEnteredSafeZone(userId: number): ()

	destroyAttackZoneForUserId(userId)

end



local function onPlayerLeftSafeZone(userId: number): ()

	createAttackZoneForUserId(userId)

end



local function onPlayerCharacterAdded(userId: number): ()

	if SafeZoneAPI.isPlayerInSafeZone(userId) then

		return

	end



	createAttackZoneForUserId(userId)

end



local function onPlayerCharacterRemoving(userId: number): ()

	destroyAttackZoneForUserId(userId)

end



local function updateZoneForPlayer(player: Player): ()

	local userId = player.UserId

	local state = attackZoneStateByUserId[userId]

	if state == nil then

		return

	end



	local rangeLevel = getRangeLevelForUserId(userId)

	applyZoneGeometry(state, rangeLevel)

	scanAttackZoneOverlaps(userId)

end



local function rescanForPlayer(userId: number): ()

	scanAttackZoneOverlaps(userId)

end



local function hookPlayer(player: Player): ()

	local userId = player.UserId



	player.CharacterAdded:Connect(function(_character: Model)

		onPlayerCharacterAdded(userId)

	end)



	player.CharacterRemoving:Connect(function()

		onPlayerCharacterRemoving(userId)

	end)



	if player.Character and not SafeZoneAPI.isPlayerInSafeZone(userId) then

		createAttackZoneForUserId(userId)

	end

end



local function init(): ()

	if initialized then

		return

	end

	initialized = true



	ObstacleAPI.registerOnObstacleRegistered(function(_blocker: BasePart)

		scanAllActiveAttackZones()

	end)



	ObstacleAPI.registerDoesAttackZoneOverlapBlocker(doesAttackZoneOverlapBlocker)



	ObstacleAPI.registerOnSegmentBrokenForPlayer(function(blocker: BasePart, userId: number)

		local attackZoneState = attackZoneStateByUserId[userId]

		if attackZoneState == nil then

			return

		end



		attackZoneState.overlappingBlockers[blocker] = nil

		attackZoneState.exitMissCounts[blocker] = nil

	end)



	SafeZoneAPI.registerOnEnteredSafeZone(onPlayerEnteredSafeZone)

	SafeZoneAPI.registerOnLeftSafeZone(onPlayerLeftSafeZone)



	Players.PlayerRemoving:Connect(function(player: Player)

		destroyAttackZoneForUserId(player.UserId)

	end)



	for _, player in Players:GetPlayers() do

		hookPlayer(player)

	end



	Players.PlayerAdded:Connect(hookPlayer)

end



init()



local AttackZoneManager: AttackZoneManagerModule = {

	updateZoneForPlayer = updateZoneForPlayer,

	rescanForPlayer = rescanForPlayer,

}



--[[

	SELF-AUDIT (Section 7):

	- overlap scan task.spawn loop — scoped per userId while AttackZone exists;

	  overlapScanLoopActive cleared in destroyAttackZoneForUserId. OK.

	- player.CharacterAdded/CharacterRemoving:Connect — per-player hooks via hookPlayer;

	  CharacterRemoving destroys zone and stops contact via ObstacleAPI.stopAllContactForPlayer. OK.

	- SafeZoneAPI enter/exit callbacks — registered once in init(); destroy/create zone. OK.

	- ObstacleAPI.registerOnSegmentBrokenForPlayer — clears overlappingBlockers for broken segment. OK.

	- Players.PlayerRemoving:Connect — script-lifetime singleton; destroys zone for userId. OK.

	- task.spawn — one overlap-scan loop per active AttackZone; exits when zone destroyed. OK.

	- Instance.new (Part, Weld) — one per field session per player; destroyed on teardown, not hot path. OK.

	- Contact is overlap-driven via GetPartsInPart + diff; AttackZone is CanCollide=false query volume. OK.

	- doesAttackZoneOverlapBlocker reads overlappingBlockers from scanAttackZoneOverlaps (O(1));

	  damage loops no longer run independent GetPartsInPart queries. OK.

]]



return AttackZoneManager
