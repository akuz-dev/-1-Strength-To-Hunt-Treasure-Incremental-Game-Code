--!strict

--[[
	Section 6 pool for loot nametag BillboardGui clones from ReplicatedStorage.Assets.LootNametag.
	Clone churn is confined to warm-up; runtime bind cycles acquire/release.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LootNametagConfig = require(ReplicatedStorage.Shared.LootNametagConfig)

local STORAGE_FOLDER_NAME = "LootNametagPoolStorage"
local LOOT_NAMETAG_ASSETS_PATH = { "Assets", "LootNametag" }
local TEMPLATE_WAIT_TIMEOUT = 5
local POOL_WARM_SIZE = 14

type PooledNametagEntry = {
	billboard: BillboardGui,
	inUse: boolean,
}

type LootNametagPoolModule = {
	acquire: () -> BillboardGui?,
	release: (billboard: BillboardGui) -> (),
}

local storageFolder = Instance.new("Folder")
storageFolder.Name = STORAGE_FOLDER_NAME
storageFolder.Parent = script

local nametagPool: { PooledNametagEntry } = {}
local templateBillboard: BillboardGui? = nil
local initialized = false

local function resolveNametagTemplate(): BillboardGui?
	local current: Instance = ReplicatedStorage
	for index, childName in LOOT_NAMETAG_ASSETS_PATH do
		local child = current:FindFirstChild(childName)
		if child == nil then
			child = current:WaitForChild(childName, TEMPLATE_WAIT_TIMEOUT)
		end

		if child == nil then
			warn(`[LootNametagPool] Missing ReplicatedStorage.{table.concat(LOOT_NAMETAG_ASSETS_PATH, ".")}`)
			return nil
		end

		if index == #LOOT_NAMETAG_ASSETS_PATH then
			if not child:IsA("BillboardGui") then
				warn(`[LootNametagPool] ReplicatedStorage.{table.concat(LOOT_NAMETAG_ASSETS_PATH, ".")} must be a BillboardGui`)
				return nil
			end
		elseif not child:IsA("Folder") then
			warn(`[LootNametagPool] Expected folder at ReplicatedStorage.{table.concat(LOOT_NAMETAG_ASSETS_PATH, ".", 1, index)}`)
			return nil
		end

		current = child
	end

	return current :: BillboardGui
end

local function resetBillboard(billboard: BillboardGui): ()
	billboard.Enabled = false
	billboard.Adornee = nil
	billboard.Parent = storageFolder
	LootNametagConfig.resetNametagText(billboard)
end

local function createBillboardFromTemplate(): BillboardGui?
	if templateBillboard == nil then
		return nil
	end

	local clone = templateBillboard:Clone()
	resetBillboard(clone)
	return clone
end

local function initialize(): ()
	if initialized then
		return
	end

	local template = resolveNametagTemplate()
	if template == nil then
		return
	end

	templateBillboard = template

	for _ = 1, POOL_WARM_SIZE do
		local billboard = createBillboardFromTemplate()
		if billboard == nil then
			break
		end

		table.insert(nametagPool, {
			billboard = billboard,
			inUse = false,
		})
	end

	initialized = true
end

local function acquire(): BillboardGui?
	if not initialized then
		initialize()
	end

	if templateBillboard == nil then
		return nil
	end

	for _, entry in nametagPool do
		if not entry.inUse then
			entry.inUse = true
			entry.billboard.Enabled = true
			return entry.billboard
		end
	end

	local billboard = createBillboardFromTemplate()
	if billboard == nil then
		return nil
	end

	local entry: PooledNametagEntry = {
		billboard = billboard,
		inUse = true,
	}
	table.insert(nametagPool, entry)
	billboard.Enabled = true
	return billboard
end

local function release(billboard: BillboardGui): ()
	for _, entry in nametagPool do
		if entry.billboard == billboard then
			entry.inUse = false
			resetBillboard(billboard)
			return
		end
	end

	resetBillboard(billboard)
	billboard:Destroy()
end

local LootNametagPool: LootNametagPoolModule = {
	acquire = acquire,
	release = release,
}

return LootNametagPool

--[[
	SELF-AUDIT (Section 7):
	- Instance.new("Folder") storage — script-lifetime singleton. OK.
	- templateBillboard:Clone() — warm-up + overflow only inside this pool. OK.
	- acquire/release reset Enabled/Adornee/parent and call resetNametagText; overflow Destroy only when untracked. OK.
]]
