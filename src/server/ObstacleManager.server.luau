--!strict

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ObstacleAPI = require(script.Parent.ObstacleAPI)
local DiggingStateService = require(script.Parent.DiggingStateService)
local NoCollisionConstraintPool = require(script.Parent.NoCollisionConstraintPool)
local ObstacleConfig = require(ReplicatedStorage.Shared.ObstacleConfig)
local PlayerDataService = require(ReplicatedStorage.Shared.PlayerDataService)
local SafeZoneAPI = require(script.Parent.SafeZoneAPI)
local SandObstacleUtil = require(ReplicatedStorage.Shared.SandObstacleUtil)
local StatUpgradeConfig = require(ReplicatedStorage.Shared.StatUpgradeConfig)
local StrengthService = require(script.Parent.StrengthService)
local WeaponCombatUtil = require(ReplicatedStorage.Shared.WeaponCombatUtil)

local OBSTACLE_TAG = "Obstacle"
local REMOTES_FOLDER_NAME = "Remotes"

local COLLISION_GROUP_OBSTACLES = "Obstacles"
local COLLISION_GROUP_CHARACTERS = "Characters"
local COLLISION_GROUP_WEAPONS = "Weapons"

type ObstacleTypeEntry = {
	Name: string,
	MaxHP: number,
	Zone: number,
}

type ObstacleRuntimeState = {
	blocker: BasePart,
	visualPart: BasePart?,
	maxHP: number,
	currentHP: { [number]: number },
	bypassConstraints: { [number]: { NoCollisionConstraint } },
}

type PlayerContactState = {
	touchCount: number,
	damageLoopActive: boolean,
	diggingBegun: boolean,
}

type PlayerCharacterConnectionState = {
	characterAddedConnection: RBXScriptConnection?,
	characterRemovingConnection: RBXScriptConnection?,
	descendantAddedConnection: RBXScriptConnection?,
}

local obstacleStates: { [BasePart]: ObstacleRuntimeState } = {}
local pairRegistrationWarned: { [Instance]: boolean } = {}
local registeredSegmentContainers: { [Instance]: boolean } = {}
local playerContactByObstacle: { [BasePart]: { [number]: PlayerContactState } } = {}
local touchDebounceByObstacle: { [BasePart]: { [number]: boolean } } = {}
local playerCharacterConnectionsByUserId: { [number]: PlayerCharacterConnectionState } = {}
local damagedObstaclesByUserId: { [number]: { [BasePart]: boolean } } = {}
-- Matches AttackZoneManager OVERLAP_SCAN_INTERVAL; caps passive strength + activity popups per scan.
local TRAVERSAL_AWARD_INTERVAL = 0.1
local lastTraversalAwardClockByUserId: { [number]: number } = {}

local obstacleDestroyedEvent: BindableEvent
local obstacleResetAllRemote: RemoteEvent
local obstacleBrokenRemote: RemoteEvent
local obstacleHitRemote: RemoteEvent
local obstacleHitVisualRemote: RemoteEvent

local function getPlayerHP(runtimeState: ObstacleRuntimeState, userId: number): number?
	return runtimeState.currentHP[userId]
end

local function initPlayerHP(runtimeState: ObstacleRuntimeState, userId: number): number
	local existingHP = runtimeState.currentHP[userId]
	if existingHP ~= nil then
		return existingHP
	end

	runtimeState.currentHP[userId] = runtimeState.maxHP
	return runtimeState.maxHP
end

local function syncSegmentAttributes(runtimeState: ObstacleRuntimeState, currentHP: number): ()
	local blocker = runtimeState.blocker
	blocker:SetAttribute("MaxHP", runtimeState.maxHP)
	blocker:SetAttribute("CurrentHP", currentHP)
end

local function markObstacleDamagedForPlayer(userId: number, blocker: BasePart): ()
	local damagedSet = damagedObstaclesByUserId[userId]
	if damagedSet == nil then
		damagedSet = {}
		damagedObstaclesByUserId[userId] = damagedSet
	end

	damagedSet[blocker] = true
end

local function releaseBypassConstraintsForPlayer(runtimeState: ObstacleRuntimeState, userId: number): ()
	local constraints = runtimeState.bypassConstraints[userId]
	if constraints == nil then
		return
	end

	NoCollisionConstraintPool.releaseAll(constraints)
	runtimeState.bypassConstraints[userId] = nil
end

local WEAPON_VISUAL_FOLDER_NAME = "WeaponVisual"

local function isWeaponVisualPart(descendant: Instance): boolean
	local current: Instance? = descendant
	while current do
		if current.Name == WEAPON_VISUAL_FOLDER_NAME then
			return true
		end
		if current:GetAttribute("IsPlayerWeapon") == true then
			return true
		end
		current = current.Parent
	end

	return false
end

local function appendBypassConstraintForPart(
	runtimeState: ObstacleRuntimeState,
	userId: number,
	characterPart: BasePart
): ()
	local currentHP = getPlayerHP(runtimeState, userId)
	if currentHP == nil or currentHP > 0 then
		return
	end

	local constraints = runtimeState.bypassConstraints[userId]
	if constraints == nil then
		constraints = {}
		runtimeState.bypassConstraints[userId] = constraints
	end

	local constraint = NoCollisionConstraintPool.acquire()
	NoCollisionConstraintPool.activate(constraint, characterPart, runtimeState.blocker)
	table.insert(constraints, constraint)
end

local function activateBypassConstraintsForPlayer(
	runtimeState: ObstacleRuntimeState,
	userId: number,
	character: Model
): ()
	releaseBypassConstraintsForPlayer(runtimeState, userId)

	local currentHP = getPlayerHP(runtimeState, userId)
	if currentHP == nil or currentHP > 0 then
		return
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		appendBypassConstraintForPart(runtimeState, userId, humanoidRootPart)
	end

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= humanoidRootPart and not isWeaponVisualPart(descendant) then
			appendBypassConstraintForPart(runtimeState, userId, descendant)
		end
	end
end

local function activateBypassForBrokenObstacles(userId: number, character: Model): ()
	for _, runtimeState in obstacleStates do
		activateBypassConstraintsForPlayer(runtimeState, userId, character)
	end
end

local function getOrCreateContactState(obstacle: BasePart, userId: number): PlayerContactState
	local obstacleContacts = playerContactByObstacle[obstacle]
	if obstacleContacts == nil then
		obstacleContacts = {}
		playerContactByObstacle[obstacle] = obstacleContacts
	end

	local contactState = obstacleContacts[userId]
	if contactState == nil then
		contactState = {
			touchCount = 0,
			damageLoopActive = false,
			diggingBegun = false,
		}
		obstacleContacts[userId] = contactState
	end

	return contactState
end

local ONE_SHOT_DIG_MIN_SECONDS = 0.15

local function beginDiggingForContact(userId: number, contactState: PlayerContactState): ()
	if contactState.diggingBegun then
		return
	end

	contactState.diggingBegun = true
	DiggingStateService.BeginDigging(userId)
end

local function endDiggingForContact(userId: number, contactState: PlayerContactState): ()
	if not contactState.diggingBegun then
		return
	end

	contactState.diggingBegun = false
	DiggingStateService.EndDigging(userId)
end

local function scheduleOneShotDigEnd(userId: number, contactState: PlayerContactState): ()
	task.delay(ONE_SHOT_DIG_MIN_SECONDS, function()
		endDiggingForContact(userId, contactState)
	end)
end

local function getOrCreateTouchDebounce(obstacle: BasePart, userId: number): boolean
	local obstacleDebounce = touchDebounceByObstacle[obstacle]
	if obstacleDebounce == nil then
		obstacleDebounce = {}
		touchDebounceByObstacle[obstacle] = obstacleDebounce
	end

	return obstacleDebounce[userId] == true
end

local function setTouchDebounce(obstacle: BasePart, userId: number, debounced: boolean): ()
	local obstacleDebounce = touchDebounceByObstacle[obstacle]
	if obstacleDebounce == nil then
		obstacleDebounce = {}
		touchDebounceByObstacle[obstacle] = obstacleDebounce
	end

	obstacleDebounce[userId] = debounced
end

local function registerCollisionGroups(): ()
	PhysicsService:RegisterCollisionGroup(COLLISION_GROUP_OBSTACLES)
	PhysicsService:RegisterCollisionGroup(COLLISION_GROUP_CHARACTERS)
	PhysicsService:RegisterCollisionGroup(COLLISION_GROUP_WEAPONS)
	PhysicsService:CollisionGroupSetCollidable(COLLISION_GROUP_OBSTACLES, COLLISION_GROUP_CHARACTERS, true)
	PhysicsService:CollisionGroupSetCollidable(COLLISION_GROUP_WEAPONS, COLLISION_GROUP_OBSTACLES, false)
end

local function getOrCreateObstacleDestroyedEvent(): BindableEvent
	local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
	local existingEvent = sharedFolder:FindFirstChild("ObstacleDestroyed")
	if existingEvent and existingEvent:IsA("BindableEvent") then
		return existingEvent
	end

	local newEvent = Instance.new("BindableEvent")
	newEvent.Name = "ObstacleDestroyed"
	newEvent.Parent = sharedFolder
	return newEvent
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

local function getObstacleRemotes(): (RemoteEvent, RemoteEvent, RemoteEvent, RemoteEvent)
	local remotesFolder = getOrCreateRemotesFolder()
	local resetAll = getOrCreateRemoteEvent(remotesFolder, "ObstacleResetAll")
	local obstacleBroken = getOrCreateRemoteEvent(remotesFolder, "ObstacleBroken")
	local obstacleHit = getOrCreateRemoteEvent(remotesFolder, "ObstacleHit")
	local obstacleHitVisual = getOrCreateRemoteEvent(remotesFolder, "ObstacleHitVisual")
	return resetAll, obstacleBroken, obstacleHit, obstacleHitVisual
end

local function fireObstacleResetAll(player: Player, resetBlockers: { BasePart }): ()
	if #resetBlockers == 0 then
		return
	end

	obstacleResetAllRemote:FireClient(player, resetBlockers)
end

local function getClientNotifyPart(runtimeState: ObstacleRuntimeState): BasePart?
	return runtimeState.visualPart or runtimeState.blocker
end

local function fireObstacleBroken(player: Player, runtimeState: ObstacleRuntimeState): ()
	local clientPart = getClientNotifyPart(runtimeState)
	if clientPart == nil then
		return
	end

	obstacleBrokenRemote:FireClient(player, clientPart)
end

local function fireObstacleHit(player: Player, runtimeState: ObstacleRuntimeState): ()
	local clientPart = getClientNotifyPart(runtimeState)
	if clientPart == nil then
		return
	end

	obstacleHitRemote:FireClient(player, clientPart)
end

-- Delta-only: single Instance reference per damage tick, no tables (Section 5.5).
-- Server never references TweenService/Color3/Highlight — flash is entirely client-side (Section 5, "Server is Blind").
local function fireObstacleHitVisual(player: Player, runtimeState: ObstacleRuntimeState): ()
	local clientPart = getClientNotifyPart(runtimeState)
	if clientPart == nil then
		return
	end

	obstacleHitVisualRemote:FireClient(player, clientPart)
end

local function clearTraversalAwardClock(userId: number): ()
	lastTraversalAwardClockByUserId[userId] = nil
end

local function tryAwardTraversalFeedback(
	player: Player,
	playerData: PlayerDataService.PlayerData,
	runtimeState: ObstacleRuntimeState
): boolean
	local userId = player.UserId
	local now = os.clock()
	if now - (lastTraversalAwardClockByUserId[userId] or 0) < TRAVERSAL_AWARD_INTERVAL then
		return false
	end

	lastTraversalAwardClockByUserId[userId] = now
	StrengthService.AddStrength(player, WeaponCombatUtil.GetClickStrengthGain(playerData))
	fireObstacleHit(player, runtimeState)
	return true
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

local function resolveSegmentFromPart(part: BasePart): (BasePart?, ObstacleRuntimeState?)
	local directState = obstacleStates[part]
	if directState then
		return part, directState
	end

	local blocker = SandObstacleUtil.resolveSegmentFromTaggedInstance(part)
	if blocker then
		local runtimeState = obstacleStates[blocker]
		if runtimeState then
			return blocker, runtimeState
		end
	end

	local current: Instance? = part
	while current do
		if current:IsA("BasePart") then
			local runtimeState = obstacleStates[current]
			if runtimeState then
				return current, runtimeState
			end

			if CollectionService:HasTag(current, OBSTACLE_TAG) then
				local taggedState = obstacleStates[current]
				if taggedState then
					return current, taggedState
				end
			end
		end

		current = current.Parent
	end

	return nil, nil
end

local function stopContactDamageLoop(obstacle: BasePart, userId: number): ()
	local obstacleContacts = playerContactByObstacle[obstacle]
	if obstacleContacts == nil then
		return
	end

	local contactState = obstacleContacts[userId]
	if contactState == nil then
		return
	end

	contactState.damageLoopActive = false
end

local function clearPlayerContactOnObstacle(obstacle: BasePart, userId: number): ()
	stopContactDamageLoop(obstacle, userId)

	local obstacleContacts = playerContactByObstacle[obstacle]
	if obstacleContacts == nil then
		return
	end

	obstacleContacts[userId] = nil

	local hasAny = false
	for _ in obstacleContacts do
		hasAny = true
		break
	end

	if not hasAny then
		playerContactByObstacle[obstacle] = nil
	end
end

local function markSegmentBrokenForPlayer(
	runtimeState: ObstacleRuntimeState,
	userId: number,
	player: Player
): ()
	local blocker = runtimeState.blocker
	local character = player.Character
	if character then
		activateBypassConstraintsForPlayer(runtimeState, userId, character)
	end

	clearPlayerContactOnObstacle(blocker, userId)
	ObstacleAPI.notifySegmentBrokenForPlayer(blocker, userId)

	fireObstacleBroken(player, runtimeState)
	obstacleDestroyedEvent:Fire(blocker, player)
end

local function applyDamageTick(blocker: BasePart, player: Player, runtimeState: ObstacleRuntimeState): boolean
	local userId = player.UserId
	if SafeZoneAPI.isPlayerInSafeZone(userId) then
		return false
	end

	local currentHP = getPlayerHP(runtimeState, userId)
	if currentHP ~= nil and currentHP <= 0 then
		return false
	end

	local playerData = PlayerDataService.GetData(player)
	if playerData == nil then
		return false
	end

	local maxHP = runtimeState.maxHP
	local damageDealt = WeaponCombatUtil.GetEffectiveDamage(playerData)
	currentHP = initPlayerHP(runtimeState, userId)

	currentHP = math.max(0, currentHP - damageDealt)
	runtimeState.currentHP[userId] = currentHP

	if currentHP < maxHP then
		markObstacleDamagedForPlayer(userId, blocker)
	end

	local isBroken = currentHP <= 0
	syncSegmentAttributes(runtimeState, currentHP)

	if isBroken then
		markSegmentBrokenForPlayer(runtimeState, userId, player)
	end

	return true
end

local function runContactDamageLoop(obstacle: BasePart, userId: number): ()
	local contactState = getOrCreateContactState(obstacle, userId)
	if contactState.damageLoopActive then
		return
	end

	contactState.damageLoopActive = true
	beginDiggingForContact(userId, contactState)

	task.spawn(function()
		local loopOk, loopErr = pcall(function()
			while contactState.damageLoopActive do
				local runtimeState = obstacleStates[obstacle]
				if runtimeState == nil then
					break
				end

				local player = Players:GetPlayerByUserId(userId)
				if player == nil then
					break
				end

				local playerData = PlayerDataService.GetData(player)
				if playerData == nil then
					break
				end

				local tickInterval = StatUpgradeConfig.GetDamageTickInterval(playerData.StatLevels.Agility)
				task.wait(tickInterval)

				if not contactState.damageLoopActive then
					break
				end

				if not ObstacleAPI.doesAttackZoneOverlapBlocker(userId, obstacle) then
					break
				end

				runtimeState = obstacleStates[obstacle]
				if runtimeState == nil then
					break
				end

				player = Players:GetPlayerByUserId(userId)
				if player == nil then
					break
				end

				playerData = PlayerDataService.GetData(player)
				if playerData == nil then
					break
				end

				local currentHP = getPlayerHP(runtimeState, userId)
				if currentHP ~= nil and currentHP <= 0 then
					break
				end

				if SafeZoneAPI.isPlayerInSafeZone(userId) then
					break
				end

				if applyDamageTick(obstacle, player, runtimeState) then
					fireObstacleHitVisual(player, runtimeState)
					tryAwardTraversalFeedback(player, playerData, runtimeState)
				end
			end
		end)

		if not loopOk then
			warn(`[ObstacleManager] contact damage loop error for userId={userId}: {loopErr}`)
		end

		contactState.damageLoopActive = false
		endDiggingForContact(userId, contactState)
		clearPlayerContactOnObstacle(obstacle, userId)
	end)
end

local function sustainAttackZoneContact(obstacle: BasePart, userId: number): ()
	local segment, runtimeState = resolveSegmentFromPart(obstacle)
	if segment == nil or runtimeState == nil or segment ~= obstacle then
		return
	end

	local hp = getPlayerHP(runtimeState, userId)
	if hp ~= nil and hp <= 0 then
		return
	end

	local contactState = getOrCreateContactState(obstacle, userId)
	if contactState.damageLoopActive then
		return
	end

	runContactDamageLoop(obstacle, userId)
end

local function onAttackZoneTouched(obstacle: BasePart, userId: number): ()
	local segment, runtimeState = resolveSegmentFromPart(obstacle)
	if segment == nil or runtimeState == nil or segment ~= obstacle then
		return
	end

	local hp = getPlayerHP(runtimeState, userId)
	if hp ~= nil and hp <= 0 then
		return
	end

	if getOrCreateTouchDebounce(obstacle, userId) then
		return
	end

	local contactState = getOrCreateContactState(obstacle, userId)
	if contactState.damageLoopActive then
		return
	end

	setTouchDebounce(obstacle, userId, true)
	task.defer(function()
		setTouchDebounce(obstacle, userId, false)
	end)

	contactState.touchCount += 1

	if contactState.touchCount == 1 then
		local player = Players:GetPlayerByUserId(userId)
		if player == nil then
			return
		end

		beginDiggingForContact(userId, contactState)

		local playerData = PlayerDataService.GetData(player)
		if applyDamageTick(obstacle, player, runtimeState) then
			fireObstacleHitVisual(player, runtimeState)
			if playerData then
				tryAwardTraversalFeedback(player, playerData, runtimeState)
			end
		end

		local hpAfterTick = getPlayerHP(runtimeState, userId)
		if hpAfterTick == nil or hpAfterTick > 0 then
			runContactDamageLoop(obstacle, userId)
		else
			scheduleOneShotDigEnd(userId, contactState)
		end
	end
end

local function onAttackZoneTouchEnded(_obstacle: BasePart, _userId: number): ()
	-- AttackZone overlap flicker must not stop the damage loop; the loop self-checks
	-- live overlap via ObstacleAPI.doesAttackZoneOverlapBlocker each tick.
end

local function disconnectDescendantAddedConnection(userId: number): ()
	local connState = playerCharacterConnectionsByUserId[userId]
	if connState == nil then
		return
	end

	local descendantAddedConnection = connState.descendantAddedConnection
	if descendantAddedConnection then
		descendantAddedConnection:Disconnect()
		connState.descendantAddedConnection = nil
	end
end

local function cleanupPlayerCharacterConnections(userId: number): ()
	local connState = playerCharacterConnectionsByUserId[userId]
	if connState == nil then
		return
	end

	disconnectDescendantAddedConnection(userId)

	local characterAddedConnection = connState.characterAddedConnection
	if characterAddedConnection then
		characterAddedConnection:Disconnect()
	end

	local characterRemovingConnection = connState.characterRemovingConnection
	if characterRemovingConnection then
		characterRemovingConnection:Disconnect()
	end

	playerCharacterConnectionsByUserId[userId] = nil
end

local function assignCharacterCollisionGroup(userId: number, character: Model): ()
	disconnectDescendantAddedConnection(userId)

	local connState = playerCharacterConnectionsByUserId[userId]
	if connState == nil then
		connState = {}
		playerCharacterConnectionsByUserId[userId] = connState
	end

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = COLLISION_GROUP_CHARACTERS
		end
	end

	connState.descendantAddedConnection = character.DescendantAdded:Connect(function(descendant: Instance)
		if not descendant:IsA("BasePart") then
			return
		end

		if isWeaponVisualPart(descendant) then
			return
		end

		descendant.CollisionGroup = COLLISION_GROUP_CHARACTERS

		for _, runtimeState in obstacleStates do
			appendBypassConstraintForPart(runtimeState, userId, descendant)
		end
	end)
end

local function onPlayerCharacterAdded(userId: number, character: Model): ()
	assignCharacterCollisionGroup(userId, character)
	activateBypassForBrokenObstacles(userId, character)
end

local function stopAllContactForPlayer(userId: number): ()
	for obstacle in playerContactByObstacle do
		clearPlayerContactOnObstacle(obstacle, userId)
	end
	DiggingStateService.ForceStopDigging(userId)
	clearTraversalAwardClock(userId)
end

local function cleanupPlayerHP(player: Player): ()
	local userId = player.UserId

	stopAllContactForPlayer(userId)
	cleanupPlayerCharacterConnections(userId)
	damagedObstaclesByUserId[userId] = nil

	for _, runtimeState in obstacleStates do
		releaseBypassConstraintsForPlayer(runtimeState, userId)
		runtimeState.currentHP[userId] = nil
	end
end

local function resetSegmentForPlayer(runtimeState: ObstacleRuntimeState, userId: number): ()
	runtimeState.currentHP[userId] = runtimeState.maxHP
	syncSegmentAttributes(runtimeState, runtimeState.maxHP)
	releaseBypassConstraintsForPlayer(runtimeState, userId)
end

local function resetPlayerObstacleHP(player: Player): ()
	local userId = player.UserId

	stopAllContactForPlayer(userId)

	local resetBlockers: { BasePart } = {}
	local damagedSet = damagedObstaclesByUserId[userId]
	if damagedSet ~= nil then
		for blocker in damagedSet do
			local runtimeState = obstacleStates[blocker]
			if runtimeState ~= nil then
				resetSegmentForPlayer(runtimeState, userId)
				table.insert(resetBlockers, blocker)
			end
		end

		damagedObstaclesByUserId[userId] = nil
	end

	fireObstacleResetAll(player, resetBlockers)
end

local function unregisterObstacle(blocker: BasePart): ()
	local runtimeState = obstacleStates[blocker]
	if runtimeState == nil then
		return
	end

	for userId in runtimeState.bypassConstraints do
		releaseBypassConstraintsForPlayer(runtimeState, userId)
	end

	playerContactByObstacle[blocker] = nil
	touchDebounceByObstacle[blocker] = nil
	obstacleStates[blocker] = nil
end

local function registerObstacleSegment(
	blocker: BasePart,
	visualPart: BasePart,
	obstacleTypeConfig: ObstacleTypeEntry
): ()
	if obstacleStates[blocker] ~= nil then
		return
	end

	SandObstacleUtil.configureVisualPart(visualPart)
	SandObstacleUtil.configureBlockerPart(blocker)

	local restY, sunkY = SandObstacleUtil.ensureRestYSunkYAttributes(visualPart)
	visualPart:SetAttribute("RestY", restY)
	visualPart:SetAttribute("SunkY", sunkY)

	local maxHP = obstacleTypeConfig.MaxHP
	blocker.CollisionGroup = COLLISION_GROUP_OBSTACLES

	local runtimeState: ObstacleRuntimeState = {
		blocker = blocker,
		visualPart = visualPart,
		maxHP = maxHP,
		currentHP = {},
		bypassConstraints = {},
	}

	blocker:SetAttribute("MaxHP", maxHP)
	blocker:SetAttribute("CurrentHP", maxHP)
	SandObstacleUtil.applySegmentY(visualPart, restY, sunkY, maxHP, maxHP)

	obstacleStates[blocker] = runtimeState
	ObstacleAPI.notifyObstacleRegistered(blocker)
end

local function isInsideObstacleLootPart(instance: Instance): boolean
	return instance:IsA("BasePart") and string.lower(instance.Name) == "insideobstacleloot"
end

local function resolveRegistrationContainerKey(taggedInstance: Instance): Instance
	local container = SandObstacleUtil.getSegmentContainer(taggedInstance)
	if container then
		return container
	end

	if taggedInstance:IsA("BasePart") then
		local parent = taggedInstance.Parent
		if parent and parent.Name == "Obstacles" and not parent:IsA("Model") then
			return taggedInstance
		end
	end

	return taggedInstance
end

local function isBlockerRoleTaggedPart(instance: Instance): boolean
	return instance:IsA("BasePart")
		and (instance.Name == ObstacleConfig.SegmentPartNames.Blocker or instance.Name == "Hitbox")
end

local function isPileModelAlreadyRegistered(pileModel: Model): boolean
	for registeredBlocker in obstacleStates do
		if registeredBlocker.Parent == pileModel then
			return true
		end
	end

	return false
end

local function registerTaggedObstacle(taggedInstance: Instance): ()
	if isInsideObstacleLootPart(taggedInstance) then
		return
	end

	local containerKey = resolveRegistrationContainerKey(taggedInstance)
	if registeredSegmentContainers[containerKey] then
		return
	end

	if taggedInstance:IsA("BasePart") and isBlockerRoleTaggedPart(taggedInstance) then
		if obstacleStates[taggedInstance] ~= nil then
			return
		end

		local pileModel = taggedInstance.Parent
		if pileModel and pileModel:IsA("Model") and isPileModelAlreadyRegistered(pileModel) then
			registeredSegmentContainers[containerKey] = true
			return
		end
	end

	local blocker, visualPart = SandObstacleUtil.ensureBlockerVisualPair(taggedInstance)
	if blocker == nil or visualPart == nil then
		if not pairRegistrationWarned[containerKey] then
			pairRegistrationWarned[containerKey] = true
			warn(
				`Tagged obstacle {taggedInstance:GetFullName()} could not resolve a Blocker/Visual segment pair`
			)
		end
		return
	end

	if obstacleStates[blocker] ~= nil then
		registeredSegmentContainers[containerKey] = true
		local segmentContainer = blocker.Parent
		if segmentContainer then
			registeredSegmentContainers[segmentContainer] = true
		end
		return
	end

	local obstacleType = getObstacleTypeAttribute(taggedInstance)
	if obstacleType == nil then
		warn(`Tagged obstacle {taggedInstance:GetFullName()} is missing ObstacleType attribute`)
		return
	end

	local obstacleTypeConfig = ObstacleConfig.GetObstacleType(obstacleType)
	if obstacleTypeConfig == nil then
		warn(
			`Tagged obstacle {taggedInstance:GetFullName()} has unknown ObstacleType "{obstacleType}" (expected Sand through Sand17)`
		)
		return
	end

	registerObstacleSegment(blocker, visualPart, obstacleTypeConfig)
	registeredSegmentContainers[containerKey] = true
	local segmentContainer = blocker.Parent
	if segmentContainer then
		registeredSegmentContainers[segmentContainer] = true
	end
end

local function onObstacleInstanceAdded(instance: Instance): ()
	registerTaggedObstacle(instance)
end

local function onObstacleInstanceRemoved(instance: Instance): ()
	local blocker = SandObstacleUtil.resolveSegmentFromTaggedInstance(instance, "touch")
	if blocker ~= nil then
		unregisterObstacle(blocker)
	end
end

local function onPlayerAdded(player: Player): ()
	local userId = player.UserId

	local connState: PlayerCharacterConnectionState = {}
	playerCharacterConnectionsByUserId[userId] = connState

	if player.Character then
		onPlayerCharacterAdded(userId, player.Character)
	end

	connState.characterAddedConnection = player.CharacterAdded:Connect(function(character: Model)
		onPlayerCharacterAdded(userId, character)
	end)

	connState.characterRemovingConnection = player.CharacterRemoving:Connect(function()
		disconnectDescendantAddedConnection(userId)
		stopAllContactForPlayer(userId)
	end)
end

local function isObstacleBrokenForPlayer(player: Player, blocker: BasePart): boolean
	local runtimeState = obstacleStates[blocker]
	if runtimeState == nil then
		return false
	end

	local currentHP = getPlayerHP(runtimeState, player.UserId)
	if currentHP == nil then
		return false
	end

	return currentHP <= 0
end

registerCollisionGroups()

obstacleDestroyedEvent = getOrCreateObstacleDestroyedEvent()
obstacleResetAllRemote, obstacleBrokenRemote, obstacleHitRemote, obstacleHitVisualRemote = getObstacleRemotes()

ObstacleAPI.registerResetPlayerObstacles(resetPlayerObstacleHP)
ObstacleAPI.registerIsObstacleBrokenForPlayer(isObstacleBrokenForPlayer)
ObstacleAPI.registerResolveBlockerFromPart(function(part: BasePart): BasePart?
	local segment, _runtimeState = resolveSegmentFromPart(part)
	return segment
end)
ObstacleAPI.registerAttackZoneContactHandlers(onAttackZoneTouched, onAttackZoneTouchEnded)
ObstacleAPI.registerStopAllContactForPlayer(stopAllContactForPlayer)
ObstacleAPI.registerSustainAttackZoneContact(sustainAttackZoneContact)

for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(cleanupPlayerHP)

for _, obstacle in CollectionService:GetTagged(OBSTACLE_TAG) do
	onObstacleInstanceAdded(obstacle)
end

CollectionService:GetInstanceAddedSignal(OBSTACLE_TAG):Connect(onObstacleInstanceAdded)
CollectionService:GetInstanceRemovedSignal(OBSTACLE_TAG):Connect(onObstacleInstanceRemoved)

--[[
	SELF-AUDIT (Section 7):
	- AttackZone touchEnded is a no-op for damage sessions; loop self-checks live overlap
	  via ObstacleAPI.doesAttackZoneOverlapBlocker (O(1) read of scanAttackZoneOverlaps state)
	  each Agility tick and clears on exit. OK.
	- sustainAttackZoneContact restarts loop when overlap scan still sees a blocker. OK.
	- character.DescendantAdded:Connect — stored in playerCharacterConnectionsByUserId[userId],
	  disconnected on CharacterRemoving and before next CharacterAdded. OK.
	- player.CharacterAdded:Connect — stored per userId, disconnected in cleanupPlayerCharacterConnections
	  on PlayerRemoving; closes over userId only. OK.
	- player.CharacterRemoving:Connect — stored per userId, disconnected in cleanupPlayerCharacterConnections;
	  stops contact loops via stopAllContactForPlayer. OK.
	- Players.PlayerAdded/PlayerRemoving:Connect — script-lifetime singletons; PlayerRemoving triggers
	  full per-player teardown. OK.
	- CollectionService obstacle tag signals:Connect — script-lifetime singletons. OK.
	- task.spawn (contact damage loop) — scoped to (obstacle, userId) contact session;
	  exits when contactState.damageLoopActive is false, player leaves, or HP <= 0;
	  closes over obstacle reference + userId, not Player instance. OK.
	- tryAwardTraversalFeedback — per-userId os.clock cooldown (TRAVERSAL_AWARD_INTERVAL);
	  cleared in stopAllContactForPlayer; gates AddStrength + ObstacleHit only, not damage. OK.
	- task.defer (touch debounce) — single-frame debounce per (obstacle, userId); no captured Player. OK.
	- Blocker stays CanCollide=true, CanTouch=false; per-player pass-through uses
	  NoCollisionConstraintPool only when HP<=0 (HRP first, then descendants;
	  incremental on DescendantAdded). markSegmentBrokenForPlayer applies bypass
	  synchronously on the damage tick that reaches HP=0. Released on reset/unregister/
	  PlayerRemoving. Re-applied on CharacterAdded when HP<=0. OK.
	- Visual Part never receives collision; client restores Visual Y via ObstacleResetAll with a
	  delta list of reset Blocker parts only (Server is Blind). OK.
	- Instance.new (BindableEvent, Folder, RemoteEvent) — one-time init in getOrCreate* helpers only. OK.
	- fireObstacleHitVisual — fires ObstacleHitVisual with a single Instance reference (client
	  notify part) after every successful applyDamageTick: once on the first-touch tick in
	  onAttackZoneTouched, and once per iteration inside the contact damage loop — covers
	  one-shot kills (HP hits 0 on the first touch, before the loop ever starts) as well as
	  ticks inside the loop. No tables, no TweenService/Color3/Highlight reference on the
	  server (Server is Blind). OK.
]]
