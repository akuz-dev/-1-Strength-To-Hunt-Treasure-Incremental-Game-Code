--!strict

--[[
	Section 6 pool for mouse-click ripple ImageLabel instances.
	Clone churn is confined to warm-up; runtime play cycles acquire/release.
]]

local POOL_SIZE = 15
local STORAGE_FOLDER_NAME = "MouseClickParticlePoolStorage"
local PARTICLE_Z_INDEX = 1000

type PooledEntry = {
	instance: ImageLabel,
	inUse: boolean,
	fadeTween: Tween?,
}

local storageFolder = Instance.new("Folder")
storageFolder.Name = STORAGE_FOLDER_NAME
storageFolder.Parent = script

local pool: { PooledEntry } = {}
local templateImageLabel: ImageLabel? = nil
local initialized = false

local function createParticle(): ImageLabel
	local template = templateImageLabel
	assert(template ~= nil, "MouseClickParticlePool not initialized")

	local particle = template:Clone()
	particle.AnchorPoint = Vector2.new(0.5, 0.5)
	particle.Visible = false
	particle.Parent = storageFolder
	return particle
end

local function resetParticle(particle: ImageLabel): ()
	particle.Visible = false
	particle.ImageTransparency = 0
	particle.Size = UDim2.fromOffset(0, 0)
	particle.ZIndex = PARTICLE_Z_INDEX
	particle.Parent = storageFolder
end

local function findEntryForInstance(instance: ImageLabel): PooledEntry?
	for _, entry in pool do
		if entry.instance == instance then
			return entry
		end
	end
	return nil
end

local function initialize(template: ImageLabel): ()
	if initialized then
		return
	end

	templateImageLabel = template
	template.Visible = false

	for _ = 1, POOL_SIZE do
		local particle = createParticle()
		resetParticle(particle)
		table.insert(pool, {
			instance = particle,
			inUse = false,
			fadeTween = nil,
		})
	end

	initialized = true
end

local function cancelFadeTween(entry: PooledEntry): ()
	local fadeTween = entry.fadeTween
	if fadeTween ~= nil then
		fadeTween:Cancel()
		entry.fadeTween = nil
	end
end

local function acquire(): ImageLabel?
	if not initialized or templateImageLabel == nil then
		return nil
	end

	for _, entry in pool do
		if not entry.inUse then
			entry.inUse = true
			cancelFadeTween(entry)
			return entry.instance
		end
	end

	local particle = createParticle()
	resetParticle(particle)
	local entry: PooledEntry = {
		instance = particle,
		inUse = true,
		fadeTween = nil,
	}
	table.insert(pool, entry)
	return particle
end

local function release(instance: ImageLabel): ()
	local entry = findEntryForInstance(instance)
	if entry == nil then
		return
	end

	cancelFadeTween(entry)
	entry.inUse = false
	resetParticle(instance)
end

local function setFadeTween(instance: ImageLabel, fadeTween: Tween): ()
	local entry = findEntryForInstance(instance)
	if entry == nil then
		return
	end
	entry.fadeTween = fadeTween
end

return {
	initialize = initialize,
	acquire = acquire,
	release = release,
	setFadeTween = setFadeTween,
}

--[[
	SELF-AUDIT (Section 7):
	- Instance.new("Folder") storage — script-lifetime singleton. OK.
	- template:Clone() ImageLabels — warm-up + overflow only inside this pool. OK.
	- acquire/release reset visibility/transparency/size/parent to storageFolder; no :Destroy() on hot path. OK.
	- fadeTween:Cancel on reuse/release — teardown via Tween cancel, not instance destroy. OK.
]]
