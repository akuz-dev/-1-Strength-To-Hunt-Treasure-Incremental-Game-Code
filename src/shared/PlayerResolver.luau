--!strict

local Players = game:GetService("Players")

-- GDD 5.7 step 1: resolve hit part to a player; ignore non-player touches.
local function getPlayerFromHitPart(hitPart: BasePart): Player?
	local current: Instance? = hitPart
	while current do
		if current:IsA("Model") then
			local player = Players:GetPlayerFromCharacter(current)
			if player then
				return player
			end
		end

		current = current.Parent
	end

	return nil
end

return {
	getPlayerFromHitPart = getPlayerFromHitPart,
}
