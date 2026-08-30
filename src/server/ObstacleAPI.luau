--!strict

local ObstacleAPI = {}

local resetPlayerObstaclesCallback: ((Player) -> ())? = nil
local isObstacleBrokenForPlayerCallback: ((Player, BasePart) -> boolean)? = nil
local resolveBlockerFromPartCallback: ((BasePart) -> BasePart?)? = nil
local notifyAttackZoneTouchedCallback: ((BasePart, number) -> ())? = nil
local notifyAttackZoneTouchEndedCallback: ((BasePart, number) -> ())? = nil
local stopAllContactForPlayerCallback: ((number) -> ())? = nil
local doesAttackZoneOverlapBlockerCallback: ((number, BasePart) -> boolean)? = nil
local sustainAttackZoneContactCallback: ((BasePart, number) -> ())? = nil
local onObstacleRegisteredCallbacks: { (BasePart) -> () } = {}
local onSegmentBrokenForPlayerCallbacks: { (BasePart, number) -> () } = {}

function ObstacleAPI.registerResetPlayerObstacles(callback: (Player) -> ()): ()
	resetPlayerObstaclesCallback = callback
end

function ObstacleAPI.registerIsObstacleBrokenForPlayer(callback: (Player, BasePart) -> boolean): ()
	isObstacleBrokenForPlayerCallback = callback
end

function ObstacleAPI.registerResolveBlockerFromPart(callback: (BasePart) -> BasePart?): ()
	resolveBlockerFromPartCallback = callback
end

function ObstacleAPI.registerAttackZoneContactHandlers(
	onTouched: (BasePart, number) -> (),
	onTouchEnded: (BasePart, number) -> ()
): ()
	notifyAttackZoneTouchedCallback = onTouched
	notifyAttackZoneTouchEndedCallback = onTouchEnded
end

function ObstacleAPI.registerStopAllContactForPlayer(callback: (number) -> ()): ()
	stopAllContactForPlayerCallback = callback
end

function ObstacleAPI.registerDoesAttackZoneOverlapBlocker(callback: (number, BasePart) -> boolean): ()
	doesAttackZoneOverlapBlockerCallback = callback
end

function ObstacleAPI.doesAttackZoneOverlapBlocker(userId: number, blocker: BasePart): boolean
	local callback = doesAttackZoneOverlapBlockerCallback
	if callback == nil then
		return false
	end

	return callback(userId, blocker)
end

function ObstacleAPI.registerSustainAttackZoneContact(callback: (BasePart, number) -> ()): ()
	sustainAttackZoneContactCallback = callback
end

function ObstacleAPI.sustainAttackZoneContact(blocker: BasePart, userId: number): ()
	local callback = sustainAttackZoneContactCallback
	if callback == nil then
		return
	end

	callback(blocker, userId)
end

function ObstacleAPI.registerOnObstacleRegistered(callback: (BasePart) -> ()): ()
	table.insert(onObstacleRegisteredCallbacks, callback)
end

function ObstacleAPI.notifyObstacleRegistered(blocker: BasePart): ()
	for _, callback in onObstacleRegisteredCallbacks do
		callback(blocker)
	end
end

function ObstacleAPI.registerOnSegmentBrokenForPlayer(callback: (BasePart, number) -> ()): ()
	table.insert(onSegmentBrokenForPlayerCallbacks, callback)
end

function ObstacleAPI.notifySegmentBrokenForPlayer(blocker: BasePart, userId: number): ()
	for _, callback in onSegmentBrokenForPlayerCallbacks do
		callback(blocker, userId)
	end
end

function ObstacleAPI.resetPlayerObstacles(player: Player): ()
	local callback = resetPlayerObstaclesCallback
	if callback == nil then
		warn("[ObstacleAPI] resetPlayerObstacles called before ObstacleManager registered")
		return
	end

	callback(player)
end

function ObstacleAPI.isObstacleBrokenForPlayer(player: Player, segment: BasePart): boolean
	local callback = isObstacleBrokenForPlayerCallback
	if callback == nil then
		warn("[ObstacleAPI] isObstacleBrokenForPlayer called before ObstacleManager registered")
		return false
	end

	return callback(player, segment)
end

function ObstacleAPI.resolveBlockerFromPart(part: BasePart): BasePart?
	local callback = resolveBlockerFromPartCallback
	if callback == nil then
		return nil
	end

	return callback(part)
end

function ObstacleAPI.notifyAttackZoneTouched(blocker: BasePart, userId: number): ()
	local callback = notifyAttackZoneTouchedCallback
	if callback == nil then
		warn("[ObstacleAPI] notifyAttackZoneTouched called before ObstacleManager registered")
		return
	end

	callback(blocker, userId)
end

function ObstacleAPI.notifyAttackZoneTouchEnded(blocker: BasePart, userId: number): ()
	local callback = notifyAttackZoneTouchEndedCallback
	if callback == nil then
		warn("[ObstacleAPI] notifyAttackZoneTouchEnded called before ObstacleManager registered")
		return
	end

	callback(blocker, userId)
end

function ObstacleAPI.stopAllContactForPlayer(userId: number): ()
	local callback = stopAllContactForPlayerCallback
	if callback == nil then
		warn("[ObstacleAPI] stopAllContactForPlayer called before ObstacleManager registered")
		return
	end

	callback(userId)
end

return ObstacleAPI
