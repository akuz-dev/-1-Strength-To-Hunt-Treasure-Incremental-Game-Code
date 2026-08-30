--!strict

--[[
	Section 6 pool for persistent loot world VFX anchor Parts from ReplicatedStorage.Assets.VFX.Loot.
	Clone churn is confined to warm-up; runtime bind cycles acquire/release with Enabled toggling.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local STORAGE_FOLDER_NAME = "LootVfxPoolStorage"
local LOOT_VFX_ASSETS_PATH = { "Assets", "VFX", "Loot" }
local TEMPLATE_WAIT_TIMEOUT = 5
local POOL_WARM_SIZE = 14
local OFFSCREEN_CFRAME = CFrame.new(0, -10000, 0)

type PooledVfxEntry = {
	anchorPart: BasePart,
	inUse: boolean,
}

type LootVfxPoolModule = {
	acquire: () -> BasePart?,
	release: (anchorPart: BasePart) -> (),
}

local storageFolder = Instance.new("Folder")
storageFolder.Name = STORAGE_FOLDER_NAME
storageFolder.Parent = script

local vfxPool: { PooledVfxEntry } = {}
local templateAnchorPart: BasePart? = nil
local initialized = false

local function setEmittersEnabled(anchorPart: BasePart, enabled: boolean): ()
	for _, descendant in anchorPart:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			descendant.Enabled = enabled
		end
	end
end

local function resolveLootVfxTemplate(): BasePart?
	local current: Instance = ReplicatedStorage
	for index, childName in LOOT_VFX_ASSETS_PATH do
		local child = current:FindFirstChild(childName)
		if child == nil then
			child = current:WaitForChild(childName, TEMPLATE_WAIT_TIMEOUT)
		end

		if child == nil then
			warn(`[LootVfxPool] Missing ReplicatedStorage.{table.concat(LOOT_VFX_ASSETS_PATH, ".")}`)
			return nil
		end

		if index == #LOOT_VFX_ASSETS_PATH then
			if not child:IsA("BasePart") then
				warn(`[LootVfxPool] ReplicatedStorage.{table.concat(LOOT_VFX_ASSETS_PATH, ".")} must be a BasePart`)
				return nil
			end
		elseif not child:IsA("Folder") then
			warn(`[LootVfxPool] Expected folder at ReplicatedStorage.{table.concat(LOOT_VFX_ASSETS_PATH, ".", 1, index)}`)
			return nil
		end

		current = child
	end

	return current :: BasePart
end

local function resetAnchorPart(anchorPart: BasePart): ()
	setEmittersEnabled(anchorPart, false)

	anchorPart.Anchored = true
	anchorPart.CanCollide = false
	anchorPart.CanQuery = false
	anchorPart.CanTouch = false
	anchorPart.CFrame = OFFSCREEN_CFRAME
	anchorPart.Parent = storageFolder
end

local function createAnchorPartFromTemplate(): BasePart?
	if templateAnchorPart == nil then
		return nil
	end

	local clone = templateAnchorPart:Clone()
	resetAnchorPart(clone)
	return clone
end

local function initialize(): ()
	if initialized then
		return
	end

	local template = resolveLootVfxTemplate()
	if template == nil then
		return
	end

	templateAnchorPart = template

	for _ = 1, POOL_WARM_SIZE do
		local anchorPart = createAnchorPartFromTemplate()
		if anchorPart == nil then
			break
		end

		table.insert(vfxPool, {
			anchorPart = anchorPart,
			inUse = false,
		})
	end

	initialized = true
end

local function acquire(): BasePart?
	if not initialized then
		initialize()
	end

	if templateAnchorPart == nil then
		return nil
	end

	for _, entry in vfxPool do
		if not entry.inUse then
			entry.inUse = true
			setEmittersEnabled(entry.anchorPart, true)
			return entry.anchorPart
		end
	end

	local anchorPart = createAnchorPartFromTemplate()
	if anchorPart == nil then
		return nil
	end

	local entry: PooledVfxEntry = {
		anchorPart = anchorPart,
		inUse = true,
	}
	table.insert(vfxPool, entry)
	setEmittersEnabled(anchorPart, true)
	return anchorPart
end

local function release(anchorPart: BasePart): ()
	for _, entry in vfxPool do
		if entry.anchorPart == anchorPart then
			entry.inUse = false
			resetAnchorPart(anchorPart)
			return
		end
	end

	resetAnchorPart(anchorPart)
	anchorPart:Destroy()
end

local LootVfxPool: LootVfxPoolModule = {
	acquire = acquire,
	release = release,
}

return LootVfxPool

--[[
	SELF-AUDIT (Section 7):
	- Instance.new("Folder") storage — script-lifetime singleton. OK.
	- templateAnchorPart:Clone() — warm-up + overflow only inside this pool. OK.
	- acquire/release toggle ParticleEmitter.Enabled and reset parent/CFrame; overflow Destroy only when untracked. OK.
]]
