--!strict
--!native

--[[
	Shared sand-segment math (GDD 5.9 / 1.5 spawn-height):
	Blocker holds HP/collision; Visual sinks via RestY / SunkY / HP fraction.
	Loot spawn height uses live Visual Position + Size.
]]

local ObstacleConfig = require(script.Parent.ObstacleConfig)

export type SegmentRole = "touch" | "visual"

export type SandObstacleUtilModule = {
	DEATH_SINK_TWEEN_DURATION: number,
	computeTargetY: (restY: number, sunkY: number, currentHP: number, maxHP: number) -> number,
	computeHpFraction: (currentHP: number, maxHP: number) -> number,
	applySegmentY: (segment: BasePart, restY: number, sunkY: number, currentHP: number, maxHP: number) -> (),
	computeLootSpawnCFrame: (segment: BasePart, spawnMarker: BasePart?, clearance: number) -> CFrame,
	ensureRestYSunkYAttributes: (segment: BasePart) -> (number, number),
	getSegmentContainer: (taggedInstance: Instance) -> Instance?,
	resolveSegmentFromTaggedInstance: (taggedInstance: Instance, role: SegmentRole?) -> BasePart?,
	ensureBlockerVisualPair: (taggedInstance: Instance) -> (BasePart?, BasePart?),
	resolveBlockerVisualPair: (taggedInstance: Instance) -> (BasePart?, BasePart?),
	configureVisualPart: (visualPart: BasePart) -> (),
	configureBlockerPart: (blockerPart: BasePart) -> (),
}

local INSIDE_OBSTACLE_LOOT_NAME = "InsideObstacleLoot"
local DEATH_SINK_TWEEN_DURATION = 0.35
local SUNKY_EPSILON = 0.01

local BLOCKER_PART_NAME = ObstacleConfig.SegmentPartNames.Blocker
local VISUAL_PART_NAME = ObstacleConfig.SegmentPartNames.Visual
local LEGACY_HITBOX_PART_NAME = "Hitbox"
local LEGACY_VISUAL_PART_NAME = "default"

local function computeAutoSunkY(restY: number, sizeY: number): number
	return restY - sizeY
end

local function computeLegacyAutoSunkY(restY: number, sizeY: number): number
	return restY - sizeY / 2
end

local function isLegacyAutoSunkY(restY: number, sizeY: number, sunkY: number): boolean
	return math.abs(sunkY - computeLegacyAutoSunkY(restY, sizeY)) <= SUNKY_EPSILON
end

local function isInsideObstacleLootPartName(name: string): boolean
	return string.lower(name) == string.lower(INSIDE_OBSTACLE_LOOT_NAME)
end

local function isCandidateSegmentPart(part: BasePart): boolean
	return not isInsideObstacleLootPartName(part.Name)
end

local function findNamedSegmentPart(parent: Instance, partName: string): BasePart?
	local child = parent:FindFirstChild(partName)
	if child and child:IsA("BasePart") then
		return child
	end

	return nil
end

local function findNamedSegmentPartInContainer(container: Instance, partName: string): BasePart?
	local directChild = findNamedSegmentPart(container, partName)
	if directChild and isCandidateSegmentPart(directChild) then
		return directChild
	end

	for _, descendant in container:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name == partName and isCandidateSegmentPart(descendant) then
			return descendant
		end
	end

	return nil
end

local function isBlockerRolePartName(partName: string): boolean
	return partName == BLOCKER_PART_NAME or partName == LEGACY_HITBOX_PART_NAME
end

local function isObstaclesFolder(instance: Instance): boolean
	return instance.Name == "Obstacles" and not instance:IsA("Model")
end

local SAND_SEGMENT_ROOT_ATTRIBUTE = "SandSegmentRoot"

local function isSandSegmentRootModel(model: Model): boolean
	return model:GetAttribute(SAND_SEGMENT_ROOT_ATTRIBUTE) == true
end

local function ensureSegmentModelForPart(part: BasePart): Model
	local parent = part.Parent
	if parent and parent:IsA("Model") and isSandSegmentRootModel(parent) then
		return parent
	end

	local obstaclesFolder = part.Parent
	local segmentModel = Instance.new("Model")
	segmentModel.Name = part.Name
	segmentModel:SetAttribute(SAND_SEGMENT_ROOT_ATTRIBUTE, true)
	segmentModel.Parent = obstaclesFolder
	part.Parent = segmentModel
	segmentModel.PrimaryPart = part

	return segmentModel
end

local function getSegmentContainer(taggedInstance: Instance): Instance?
	if taggedInstance:IsA("Model") then
		return taggedInstance
	end

	if taggedInstance:IsA("BasePart") then
		local current: Instance? = taggedInstance.Parent
		while current do
			if current:IsA("Model") then
				return current
			end

			if isObstaclesFolder(current) then
				return nil
			end

			current = current.Parent
		end
	end

	return nil
end

local function resolveSegmentContainer(taggedInstance: Instance): Instance?
	if taggedInstance:IsA("Model") then
		return taggedInstance
	end

	if taggedInstance:IsA("BasePart") then
		local current: Instance? = taggedInstance.Parent
		while current do
			if current:IsA("Model") then
				return current
			end

			if isObstaclesFolder(current) then
				return ensureSegmentModelForPart(taggedInstance)
			end

			current = current.Parent
		end
	end

	return nil
end

local function findLargestCandidateVisualInContainer(container: Instance, excludePart: BasePart?): BasePart?
	local bestPart: BasePart? = nil
	local bestVolume = -1

	for _, descendant in container:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end

		if descendant == excludePart then
			continue
		end

		if not isCandidateSegmentPart(descendant) then
			continue
		end

		if isBlockerRolePartName(descendant.Name) then
			continue
		end

		local volume = descendant.Size.X * descendant.Size.Y * descendant.Size.Z
		if volume > bestVolume then
			bestVolume = volume
			bestPart = descendant
		end
	end

	return bestPart
end

local function findBestVisualInContainer(container: Instance, excludePart: BasePart?): BasePart?
	local bestPart: BasePart? = nil
	local bestScore = -1
	local containerModelName: string? = if container:IsA("Model") then container.Name else nil

	for _, descendant in container:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end

		if descendant == excludePart then
			continue
		end

		if not isCandidateSegmentPart(descendant) then
			continue
		end

		if isBlockerRolePartName(descendant.Name) then
			continue
		end

		local score = descendant.Size.X * descendant.Size.Y * descendant.Size.Z
		if descendant.Name == VISUAL_PART_NAME or descendant.Name == LEGACY_VISUAL_PART_NAME then
			score += 1e9
		end
		if containerModelName and descendant.Name == containerModelName then
			score -= 1e8
		end
		if descendant.Transparency < 1 then
			score += 1e6
		end

		if score > bestScore then
			bestScore = score
			bestPart = descendant
		end
	end

	if bestPart then
		return bestPart
	end

	if container:IsA("Model") then
		local primaryPart = container.PrimaryPart
		if primaryPart and primaryPart:IsA("BasePart") and primaryPart ~= excludePart and isCandidateSegmentPart(primaryPart) then
			if not isBlockerRolePartName(primaryPart.Name) then
				return primaryPart
			end
		end
	end

	return findLargestCandidateVisualInContainer(container, excludePart)
end

local function findAlternateVisualInContainer(container: Instance, blocker: BasePart?): BasePart?
	return findBestVisualInContainer(container, blocker)
end

local function createBlockerFromVisual(visual: BasePart, container: Instance): BasePart
	local existingBlocker = findNamedSegmentPartInContainer(container, BLOCKER_PART_NAME)
	if existingBlocker then
		return existingBlocker
	end

	local legacyHitbox = findNamedSegmentPartInContainer(container, LEGACY_HITBOX_PART_NAME)
	if legacyHitbox then
		return legacyHitbox
	end

	local blocker = visual:Clone()
	blocker.Name = BLOCKER_PART_NAME
	blocker.Parent = container
	return blocker
end

local function createVisualFromBlocker(blocker: BasePart, container: Instance): BasePart
	local existingVisual = findNamedSegmentPartInContainer(container, VISUAL_PART_NAME)
	if existingVisual then
		ensureVisualPartVisible(existingVisual)
		return existingVisual
	end

	local visual = blocker:Clone()
	visual.Name = VISUAL_PART_NAME
	visual.Transparency = 0
	visual.LocalTransparencyModifier = 0
	visual.Parent = container
	return visual
end

local function resolveVisualFromContainer(container: Instance, blocker: BasePart?): BasePart?
	local bestVisual = findBestVisualInContainer(container, blocker)
	if bestVisual then
		return bestVisual
	end

	local namedVisual = findNamedSegmentPartInContainer(container, VISUAL_PART_NAME)
	if namedVisual and namedVisual ~= blocker then
		return namedVisual
	end

	local legacyVisual = findNamedSegmentPartInContainer(container, LEGACY_VISUAL_PART_NAME)
	if legacyVisual and legacyVisual ~= blocker then
		return legacyVisual
	end

	return nil
end

local function ensureVisualPartVisible(visualPart: BasePart): ()
	if isBlockerRolePartName(visualPart.Name) then
		return
	end

	if visualPart.Transparency >= 1 then
		visualPart.Transparency = 0
	end

	visualPart.LocalTransparencyModifier = 0
end

local function findVisualPartNearTaggedInstance(taggedInstance: Instance, blocker: BasePart?): BasePart?
	local container = resolveSegmentContainer(taggedInstance)
	if container == nil then
		return nil
	end

	if taggedInstance:IsA("BasePart") then
		if taggedInstance.Name == VISUAL_PART_NAME or taggedInstance.Name == LEGACY_VISUAL_PART_NAME then
			return taggedInstance
		end

		if isBlockerRolePartName(taggedInstance.Name) then
			return resolveVisualFromContainer(container, blocker or taggedInstance)
		end

		local fromContainer = resolveVisualFromContainer(container, blocker)
		if fromContainer then
			return fromContainer
		end

		return taggedInstance
	end

	if taggedInstance:IsA("Model") then
		local fromContainer = resolveVisualFromContainer(container, blocker or findBlockerPartInContainer(container))
		if fromContainer then
			return fromContainer
		end

		local primaryPart = taggedInstance.PrimaryPart
		if primaryPart and primaryPart:IsA("BasePart") and isCandidateSegmentPart(primaryPart) then
			if not isBlockerRolePartName(primaryPart.Name) then
				return primaryPart
			end
		end

		return findLargestCandidateVisualInContainer(container, blocker)
	end

	return nil
end

local function findBlockerPartInContainer(container: Instance): BasePart?
	local blockerPart = findNamedSegmentPartInContainer(container, BLOCKER_PART_NAME)
	if blockerPart then
		return blockerPart
	end

	local legacyHitbox = findNamedSegmentPartInContainer(container, LEGACY_HITBOX_PART_NAME)
	if legacyHitbox then
		return legacyHitbox
	end

	for _, descendant in container:GetDescendants() do
		if descendant:IsA("BasePart") and isBlockerRolePartName(descendant.Name) and isCandidateSegmentPart(descendant) then
			return descendant
		end
	end

	return nil
end

local function findBlockerPartNearTaggedInstance(taggedInstance: Instance): BasePart?
	if taggedInstance:IsA("BasePart") and isBlockerRolePartName(taggedInstance.Name) then
		return taggedInstance
	end

	local container = resolveSegmentContainer(taggedInstance)
	if container == nil then
		return nil
	end

	local blockerPart = findBlockerPartInContainer(container)
	if blockerPart then
		return blockerPart
	end

	if taggedInstance:IsA("Model") then
		local primaryPart = taggedInstance.PrimaryPart
		if primaryPart and primaryPart:IsA("BasePart") and isCandidateSegmentPart(primaryPart) then
			if isBlockerRolePartName(primaryPart.Name) then
				return primaryPart
			end
		end
	end

	return nil
end

local function resolveSegmentFromTaggedInstance(taggedInstance: Instance, role: SegmentRole?): BasePart?
	if role == "visual" then
		local blocker = findBlockerPartNearTaggedInstance(taggedInstance)
		return findVisualPartNearTaggedInstance(taggedInstance, blocker)
	end

	return findBlockerPartNearTaggedInstance(taggedInstance)
end

local function configureVisualPart(visualPart: BasePart): ()
	visualPart.CanCollide = false
	visualPart.CanTouch = false
	ensureVisualPartVisible(visualPart)
end

local function configureBlockerPart(blockerPart: BasePart): ()
	if not isBlockerRolePartName(blockerPart.Name) then
		blockerPart.Name = BLOCKER_PART_NAME
	end

	blockerPart.Transparency = 1
	blockerPart.Anchored = true
	blockerPart.CanCollide = true
	blockerPart.CanTouch = false
end

local function resolveBlockerVisualPair(taggedInstance: Instance): (BasePart?, BasePart?)
	local blocker = findBlockerPartNearTaggedInstance(taggedInstance)
	local visual = findVisualPartNearTaggedInstance(taggedInstance, blocker)

	if visual == blocker then
		visual = nil
	end

	return blocker, visual
end

local function ensureBlockerVisualPair(taggedInstance: Instance): (BasePart?, BasePart?)
	local container = resolveSegmentContainer(taggedInstance)
	if container == nil then
		return nil, nil
	end

	local blocker, visual = resolveBlockerVisualPair(taggedInstance)

	if visual == nil and blocker ~= nil then
		visual = createVisualFromBlocker(blocker, container)
	elseif blocker == nil and visual ~= nil then
		blocker = createBlockerFromVisual(visual, container)
	elseif blocker == nil and visual == nil then
		local fallbackVisual = findBestVisualInContainer(container, nil)
		if fallbackVisual then
			visual = fallbackVisual
			blocker = createBlockerFromVisual(visual, container)
		end
	end

	if blocker == nil or visual == nil then
		return nil, nil
	end

	if blocker.Parent ~= container then
		blocker.Parent = container
	end

	configureBlockerPart(blocker)
	configureVisualPart(visual)

	return blocker, visual
end

local function computeHpFraction(currentHP: number, maxHP: number): number
	if maxHP <= 0 then
		return 0
	end

	return math.clamp(currentHP / maxHP, 0, 1)
end

local function computeTargetY(restY: number, sunkY: number, currentHP: number, maxHP: number): number
	local hpFraction = computeHpFraction(currentHP, maxHP)
	return sunkY + (restY - sunkY) * hpFraction
end

local function applySegmentY(
	segment: BasePart,
	restY: number,
	sunkY: number,
	currentHP: number,
	maxHP: number
): ()
	local targetY = computeTargetY(restY, sunkY, currentHP, maxHP)
	local currentCFrame = segment.CFrame
	local position = currentCFrame.Position
	segment.CFrame = CFrame.new(position.X, targetY, position.Z) * (currentCFrame - currentCFrame.Position)
end

local function computeLootSpawnCFrame(segment: BasePart, spawnMarker: BasePart?, clearance: number): CFrame
	local topY = segment.Position.Y + segment.Size.Y / 2 + clearance
	local marker = spawnMarker or segment
	local spawnPosition = Vector3.new(marker.Position.X, topY, marker.Position.Z)
	return CFrame.new(spawnPosition) * (marker.CFrame - marker.CFrame.Position)
end

local function ensureRestYSunkYAttributes(segment: BasePart): (number, number)
	local restY = segment:GetAttribute("RestY")
	local sunkY = segment:GetAttribute("SunkY")

	if typeof(restY) ~= "number" then
		restY = segment.Position.Y
		segment:SetAttribute("RestY", restY)
	end

	if typeof(sunkY) ~= "number" then
		sunkY = computeAutoSunkY(restY, segment.Size.Y)
		segment:SetAttribute("SunkY", sunkY)
	elseif isLegacyAutoSunkY(restY, segment.Size.Y, sunkY) then
		sunkY = computeAutoSunkY(restY, segment.Size.Y)
		segment:SetAttribute("SunkY", sunkY)
	end

	return restY, sunkY
end

local SandObstacleUtil: SandObstacleUtilModule = {
	DEATH_SINK_TWEEN_DURATION = DEATH_SINK_TWEEN_DURATION,
	computeTargetY = computeTargetY,
	computeHpFraction = computeHpFraction,
	applySegmentY = applySegmentY,
	computeLootSpawnCFrame = computeLootSpawnCFrame,
	ensureRestYSunkYAttributes = ensureRestYSunkYAttributes,
	getSegmentContainer = getSegmentContainer,
	resolveSegmentFromTaggedInstance = resolveSegmentFromTaggedInstance,
	ensureBlockerVisualPair = ensureBlockerVisualPair,
	resolveBlockerVisualPair = resolveBlockerVisualPair,
	configureVisualPart = configureVisualPart,
	configureBlockerPart = configureBlockerPart,
}

return SandObstacleUtil
