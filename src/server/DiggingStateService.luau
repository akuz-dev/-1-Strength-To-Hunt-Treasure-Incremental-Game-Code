--!strict

local Players = game:GetService("Players")

export type DiggingStateServiceModule = {
	BeginDigging: (userId: number) -> (),
	EndDigging: (userId: number) -> (),
	ForceStopDigging: (userId: number) -> (),
}

local activeDigContactCountByUserId: { [number]: number } = {}

local function syncDiggingAttribute(userId: number): ()
	local player = Players:GetPlayerByUserId(userId)
	if player == nil then
		return
	end

	local count = activeDigContactCountByUserId[userId] or 0
	player:SetAttribute("IsDigging", count > 0)
end

local function BeginDigging(userId: number): ()
	local count = activeDigContactCountByUserId[userId] or 0
	activeDigContactCountByUserId[userId] = count + 1

	if count == 0 then
		syncDiggingAttribute(userId)
	end
end

local function EndDigging(userId: number): ()
	local count = activeDigContactCountByUserId[userId]
	if count == nil or count <= 0 then
		activeDigContactCountByUserId[userId] = nil
		syncDiggingAttribute(userId)
		return
	end

	count -= 1
	if count <= 0 then
		activeDigContactCountByUserId[userId] = nil
	else
		activeDigContactCountByUserId[userId] = count
	end

	syncDiggingAttribute(userId)
end

local function ForceStopDigging(userId: number): ()
	activeDigContactCountByUserId[userId] = nil
	syncDiggingAttribute(userId)
end

Players.PlayerRemoving:Connect(function(player: Player)
	activeDigContactCountByUserId[player.UserId] = nil
end)

local DiggingStateService: DiggingStateServiceModule = {
	BeginDigging = BeginDigging,
	EndDigging = EndDigging,
	ForceStopDigging = ForceStopDigging,
}

return DiggingStateService
