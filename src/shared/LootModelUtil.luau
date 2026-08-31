--!strict

local LootNametagConfig = require(script.Parent.LootNametagConfig)

export type LootModelUtilModule = {
	LOOT_POSE_VERSION_ATTRIBUTE: string,
	findPrimaryPart: (model: Model) -> BasePart?,
	findNametagAnchor: (model: Model) -> Attachment?,
	getLootWorldPosition: (model: Model) -> Vector3,
}

local LOOT_POSE_VERSION_ATTRIBUTE = "LootPoseVersion"

local function findPrimaryPart(model: Model): BasePart?
	local namedPrimaryPart = model:FindFirstChild("PrimaryPart", true)
	if namedPrimaryPart and namedPrimaryPart:IsA("BasePart") then
		model.PrimaryPart = namedPrimaryPart
		return namedPrimaryPart
	end

	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			model.PrimaryPart = descendant
			return descendant
		end
	end

	return nil
end

local function getLootWorldPosition(model: Model): Vector3
	return model:GetPivot().Position
end

local function findNametagAnchor(model: Model): Attachment?
	local anchor = model:FindFirstChild(LootNametagConfig.NAMETAG_ANCHOR_NAME, true)
	if anchor and anchor:IsA("Attachment") then
		return anchor
	end

	return nil
end

local LootModelUtil: LootModelUtilModule = {
	LOOT_POSE_VERSION_ATTRIBUTE = LOOT_POSE_VERSION_ATTRIBUTE,
	findPrimaryPart = findPrimaryPart,
	findNametagAnchor = findNametagAnchor,
	getLootWorldPosition = getLootWorldPosition,
}

return LootModelUtil
