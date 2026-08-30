--!strict

--[[
	One-time loot prefab geometry setup (welds mesh parts to PrimaryPart, reparents NametagAnchor).
	Call once per unique template at server startup before clones spawn; clones inherit state.

	TODO(follow-up): LootNametagHandler.client.luau sets BillboardGui.Adornee to NametagAnchor
	once at bindNametagToLoot (not a cached WorldPosition snapshot). Roblox Adornee on an
	Attachment should track world position live — verify in Studio that nametags follow spin/bob
	after NametagAnchor is reparented under PrimaryPart; update that handler if they do not.
]]

local LootModelUtil = require(script.Parent.LootModelUtil)
local LootNametagConfig = require(script.Parent.LootNametagConfig)

export type LootPrefabSetupModule = {
	SetupLootPrefab: (lootModel: Model) -> (),
}

local function hasWeldBetween(meshPart: BasePart, primaryPart: BasePart): boolean
	for _, child in meshPart:GetChildren() do
		if child:IsA("WeldConstraint") then
			local part0 = child.Part0
			local part1 = child.Part1
			if (part0 == meshPart and part1 == primaryPart) or (part0 == primaryPart and part1 == meshPart) then
				return true
			end
		end
	end

	return false
end

local function weldMeshPartToPrimary(meshPart: BasePart, primaryPart: BasePart): ()
	meshPart.Anchored = false

	if hasWeldBetween(meshPart, primaryPart) then
		return
	end

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = primaryPart
	weld.Part1 = meshPart
	weld.Parent = meshPart
end

local function findNametagAnchorForSetup(lootModel: Model, primaryPart: BasePart): Attachment?
	local underPrimary = primaryPart:FindFirstChild(LootNametagConfig.NAMETAG_ANCHOR_NAME)
	if underPrimary and underPrimary:IsA("Attachment") then
		return underPrimary
	end

	local directChild = lootModel:FindFirstChild(LootNametagConfig.NAMETAG_ANCHOR_NAME)
	if directChild and directChild:IsA("Attachment") then
		return directChild
	end

	return nil
end

local function reparentNametagAnchor(lootModel: Model, primaryPart: BasePart): ()
	local nametagAnchor = findNametagAnchorForSetup(lootModel, primaryPart)
	if nametagAnchor == nil then
		warn(`[LootPrefabSetup] Loot model {lootModel:GetFullName()} is missing NametagAnchor Attachment`)
		return
	end

	if nametagAnchor.Parent == primaryPart then
		return
	end

	local worldCFrame = nametagAnchor.WorldCFrame
	nametagAnchor.Parent = primaryPart
	nametagAnchor.WorldCFrame = worldCFrame
end

local function SetupLootPrefab(lootModel: Model): ()
	local primaryPart = LootModelUtil.findPrimaryPart(lootModel)
	if primaryPart == nil then
		warn(`[LootPrefabSetup] Loot model {lootModel:GetFullName()} is missing PrimaryPart`)
		return
	end

	primaryPart.Anchored = true

	for _, child in lootModel:GetChildren() do
		if child:IsA("BasePart") and child ~= primaryPart then
			weldMeshPartToPrimary(child, primaryPart)
		end
	end

	reparentNametagAnchor(lootModel, primaryPart)
end

local LootPrefabSetup: LootPrefabSetupModule = {
	SetupLootPrefab = SetupLootPrefab,
}

return LootPrefabSetup

--[[
	SELF-AUDIT (Section 7):
	- Instance.new(WeldConstraint) — template-time only via SetupLootPrefab at LootPool.loadTemplates;
	  idempotent hasWeldBetween guard prevents duplicate welds on re-call. OK.
]]
