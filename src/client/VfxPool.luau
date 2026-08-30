--!strict

--[[
	Section 6 pool for world-space VFX anchor Parts.
	Instance.new/Clone churn is confined to warm-up; runtime play cycles acquire/release.
]]

local STORAGE_FOLDER_NAME = "VfxPoolStorage"
local OFFSCREEN_CFRAME = CFrame.new(0, -10000, 0)

local POOL_SIZE_BY_TEMPLATE_NAME: { [string]: number } = {
	ObstacleHit = 4,
	LevelUp = 2,
	Rebirth = 2,
}

local DEFAULT_POOL_SIZE = 2

local storageFolder = Instance.new("Folder")
storageFolder.Name = STORAGE_FOLDER_NAME
storageFolder.Parent = script

type PooledPartEntry = {
	part: BasePart,
	template: BasePart,
	inUse: boolean,
}

local poolsByTemplate: { [BasePart]: { PooledPartEntry } } = {}

local function getPoolSize(template: BasePart): number
	return POOL_SIZE_BY_TEMPLATE_NAME[template.Name] or DEFAULT_POOL_SIZE
end

local function resetAnchorPart(part: BasePart): ()
	for _, descendant in part:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			descendant.Enabled = false
		end
	end

	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CFrame = OFFSCREEN_CFRAME
	part.Parent = storageFolder
end

local function getOrCreatePool(template: BasePart): { PooledPartEntry }
	local pool = poolsByTemplate[template]
	if pool == nil then
		pool = {}
		poolsByTemplate[template] = pool

		local poolSize = getPoolSize(template)
		for _ = 1, poolSize do
			local part = template:Clone()
			resetAnchorPart(part)
			table.insert(pool, {
				part = part,
				template = template,
				inUse = false,
			})
		end
	end

	return pool
end

local function acquire(template: BasePart): BasePart?
	local pool = getOrCreatePool(template)

	for _, entry in pool do
		if not entry.inUse then
			entry.inUse = true
			return entry.part
		end
	end

	local part = template:Clone()
	resetAnchorPart(part)
	table.insert(pool, {
		part = part,
		template = template,
		inUse = false,
	})

	local newEntry = pool[#pool]
	newEntry.inUse = true
	return newEntry.part
end

local function release(anchorPart: BasePart): ()
	for _, pool in poolsByTemplate do
		for _, entry in pool do
			if entry.part == anchorPart then
				resetAnchorPart(anchorPart)
				entry.inUse = false
				return
			end
		end
	end
end

return {
	acquire = acquire,
	release = release,
}
