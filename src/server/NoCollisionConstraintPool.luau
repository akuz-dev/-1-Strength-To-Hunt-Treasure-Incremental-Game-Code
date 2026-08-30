--!strict

--[[
	Section 6 pool for broken-obstacle NoCollisionConstraint instances.
	Instance.new is confined to this module; callers acquire/release instead of Destroy.
]]

local ServerStorage = game:GetService("ServerStorage")

local INITIAL_POOL_SIZE = 32
local STORAGE_FOLDER_NAME = "NoCollisionConstraintPool"

local available: { NoCollisionConstraint } = {}

local storageFolder = Instance.new("Folder")
storageFolder.Name = STORAGE_FOLDER_NAME
storageFolder.Parent = ServerStorage

local function resetConstraint(constraint: NoCollisionConstraint): ()
	constraint.Part0 = nil
	constraint.Part1 = nil
	constraint.Enabled = true
	constraint.Name = "BrokenObstacleBypass"
	constraint.Parent = storageFolder
end

local function acquire(): NoCollisionConstraint
	local constraint = table.remove(available)
	if constraint == nil then
		constraint = Instance.new("NoCollisionConstraint")
		constraint.Name = "BrokenObstacleBypass"
	end

	return constraint
end

local function release(constraint: NoCollisionConstraint): ()
	resetConstraint(constraint)
	table.insert(available, constraint)
end

local function releaseAll(constraints: { NoCollisionConstraint }): ()
	for _, constraint in constraints do
		release(constraint)
	end

	table.clear(constraints)
end

local function activate(constraint: NoCollisionConstraint, part0: BasePart, part1: BasePart): ()
	constraint.Part0 = part0
	constraint.Part1 = part1
	constraint.Parent = part1
end

for _ = 1, INITIAL_POOL_SIZE do
	local constraint = Instance.new("NoCollisionConstraint")
	constraint.Name = "BrokenObstacleBypass"
	resetConstraint(constraint)
	table.insert(available, constraint)
end

return {
	acquire = acquire,
	release = release,
	releaseAll = releaseAll,
	activate = activate,
}
