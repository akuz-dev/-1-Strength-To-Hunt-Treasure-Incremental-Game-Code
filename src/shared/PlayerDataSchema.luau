--!strict
-- src/shared/PlayerDataSchema.luau
-- Single source of truth for the shape of a player's saved data.
-- Bump SCHEMA_VERSION any time you add/rename/remove a field, and add
-- a migration step in Migrate() below so old saves don't break.

local PlayerDataSchema = {}

local WeaponConfig = require(script.Parent.WeaponConfig)

PlayerDataSchema.SCHEMA_VERSION = 7

export type InventoryItemId = string

export type StatLevels = {
	Range: number,
	Agility: number,
	Capacity: number,
	WalkSpeed: number,
}

export type PlayerData = {
	SchemaVersion: number,

	-- Core progression (GDD Section 1.2 / 3)
	Strength: number,
	Level: number,
	LevelProgress: number,
	Cash: number,
	Rebirths: number,
	HasRebirthed: boolean, -- legacy flag; multipliers now derive from Rebirths count (Section 3.3)

	-- Stat upgrade tracks (GDD Section 2.1)
	StatLevels: StatLevels,

	-- Equipment (GDD Section 2.2 / 2.3) — one-at-a-time slots
	EquippedWeaponId: string?,
	EquippedAuraId: string?,
	EquippedPetId: string?, -- revisit if pet stacking gets greenlit (open question, GDD 2.7)

	OwnedWeaponIds: { string },
	OwnedAuraIds: { string },
	OwnedPetIds: { string },

	-- Session loot carried until sold at the spawn NPC (GDD Section 1.1 / sell-system addendum)
	Inventory: { InventoryItemId },

	-- Robux purchase idempotency ledger (GDD Section 2.6)
	-- Keyed by PurchaseId -> true, so ProcessReceipt can check membership
	-- before granting, even across retries/server restarts.
	GrantedPurchaseIds: { [string]: boolean },

	-- Monotonic save counter for multi-server overwrite mitigation (not session locking).
	SaveVersion: number,

	-- Onboarding tutorial (GDD Section 1.7)
	TutorialStep: number,
	TutorialCompleted: boolean,
}

function PlayerDataSchema.GetDefaultData(): PlayerData
	return {
		SchemaVersion = PlayerDataSchema.SCHEMA_VERSION,

		Strength = 1,
		Level = 1,
		LevelProgress = 0,
		Cash = 0,
		Rebirths = 0,
		HasRebirthed = false,

		StatLevels = {
			Range = 0,
			Agility = 0,
			Capacity = 0,
			WalkSpeed = 0,
		},

		EquippedWeaponId = "WoodenShovel",
		EquippedAuraId = nil,
		EquippedPetId = nil,

		OwnedWeaponIds = { "WoodenShovel" },
		OwnedAuraIds = {},
		OwnedPetIds = {},

		Inventory = {},

		GrantedPurchaseIds = {},

		SaveVersion = 0,

		TutorialStep = 1,
		TutorialCompleted = false,
	}
end

-- Deep-copies the default table so callers never accidentally share
-- references between players (tables-of-tables like StatLevels are the risk).
function PlayerDataSchema.CloneDefaults(): PlayerData
	local defaults = PlayerDataSchema.GetDefaultData()
	local function deepCopy(tbl: any): any
		local copy = {}
		for key, value in tbl do
			if type(value) == "table" then
				copy[key] = deepCopy(value)
			else
				copy[key] = value
			end
		end
		return copy
	end
	return deepCopy(defaults) :: PlayerData
end

-- Fills in any fields missing from an older save without touching
-- fields the player already has. Add version-specific branches here
-- as SCHEMA_VERSION increases.
function PlayerDataSchema.Migrate(loadedData: any): PlayerData
	local defaults = PlayerDataSchema.CloneDefaults()
	local previousSchemaVersion = if type(loadedData.SchemaVersion) == "number" then loadedData.SchemaVersion else 0

	local function fillMissing(target: any, defaultTbl: any)
		for key, defaultValue in defaultTbl do
			if target[key] == nil then
				target[key] = defaultValue
			elseif type(defaultValue) == "table" and type(target[key]) == "table" then
				fillMissing(target[key], defaultValue)
			end
		end
	end

	fillMissing(loadedData, defaults)

	-- Legacy flat stat field from pre-schema saves (dev/testing only).
	if loadedData.RangeLevel ~= nil and loadedData.StatLevels ~= nil then
		if loadedData.StatLevels.Range == defaults.StatLevels.Range then
			loadedData.StatLevels.Range = loadedData.RangeLevel
		end
		loadedData.RangeLevel = nil
	end

	-- Schema v3: level 0 is baseline (previously level 1 meant no purchases).
	if previousSchemaVersion < 3 and type(loadedData.StatLevels) == "table" then
		local statLevels = loadedData.StatLevels
		local function migrateBaselineLevel(level: any): number
			if type(level) ~= "number" then
				return 0
			end
			return math.max(0, level - 1)
		end
		statLevels.Range = migrateBaselineLevel(statLevels.Range)
		statLevels.Agility = migrateBaselineLevel(statLevels.Agility)
		statLevels.Capacity = migrateBaselineLevel(statLevels.Capacity)
		statLevels.WalkSpeed = migrateBaselineLevel(statLevels.WalkSpeed)
	end

	-- Schema v4: Power renamed to Strength (GDD Section 1.2 / 3).
	if previousSchemaVersion < 4 and type(loadedData.Power) == "number" then
		loadedData.Strength = loadedData.Power
	end
	loadedData.Power = nil

	if loadedData.EquippedWeapon ~= nil and loadedData.EquippedWeaponId == nil then
		loadedData.EquippedWeaponId = loadedData.EquippedWeapon
		loadedData.EquippedWeapon = nil
	end

	if loadedData.CarriedLoot ~= nil and type(loadedData.CarriedLoot) == "table" then
		if loadedData.Inventory == nil or #loadedData.Inventory == 0 then
			local migratedInventory: { InventoryItemId } = {}
			for _, entry in loadedData.CarriedLoot do
				if type(entry) == "table" and type(entry.LootId) == "string" and entry.LootId ~= "" then
					table.insert(migratedInventory, entry.LootId)
				end
			end
			loadedData.Inventory = migratedInventory
		end
		loadedData.CarriedLoot = nil
	end

	if loadedData.Inventory == nil then
		loadedData.Inventory = {}
	end

	-- Schema v5: starter Bucket weapon owned/equipped by default.
	if previousSchemaVersion < 5 then
		if loadedData.EquippedWeaponId == nil
			or loadedData.EquippedWeaponId == "BaseTool"
			or WeaponConfig.GetWeapon(loadedData.EquippedWeaponId) == nil
		then
			loadedData.EquippedWeaponId = "Bucket"
		end

		if type(loadedData.OwnedWeaponIds) ~= "table" then
			loadedData.OwnedWeaponIds = { "Bucket" }
		elseif #loadedData.OwnedWeaponIds == 0 then
			table.insert(loadedData.OwnedWeaponIds, "Bucket")
		end

		local ownedSet: { [string]: boolean } = {}
		for _, weaponId in loadedData.OwnedWeaponIds do
			if type(weaponId) == "string" and weaponId ~= "" then
				ownedSet[weaponId] = true
			end
		end
		if not ownedSet.Bucket then
			table.insert(loadedData.OwnedWeaponIds, "Bucket")
		end
	end

	-- Schema v6: onboarding tutorial — skip for existing saves.
	if previousSchemaVersion < 6 then
		loadedData.TutorialCompleted = true
		loadedData.TutorialStep = 0
	end

	-- Schema v7: old weapon lineup (Bucket/Spade/SmallShovel/MediumShovel/LargeShovel/BigScooper)
	-- replaced by the shovel tier list (GDD Section 2.8). Remove removed ids and fall back to
	-- the new starter, WoodenShovel.
	if previousSchemaVersion < 7 then
		local removedWeaponIds: { [string]: boolean } = {
			Bucket = true,
			Spade = true,
			SmallShovel = true,
			MediumShovel = true,
			LargeShovel = true,
			BigScooper = true,
		}

		if type(loadedData.EquippedWeaponId) == "string" and removedWeaponIds[loadedData.EquippedWeaponId] then
			loadedData.EquippedWeaponId = "WoodenShovel"
		end

		if type(loadedData.OwnedWeaponIds) == "table" then
			local survivingOwnedWeaponIds: { string } = {}
			for _, weaponId in loadedData.OwnedWeaponIds do
				if type(weaponId) == "string" and not removedWeaponIds[weaponId] then
					table.insert(survivingOwnedWeaponIds, weaponId)
				end
			end
			loadedData.OwnedWeaponIds = survivingOwnedWeaponIds
		end

		if type(loadedData.OwnedWeaponIds) ~= "table" or #loadedData.OwnedWeaponIds == 0 then
			loadedData.OwnedWeaponIds = { "WoodenShovel" }
		end
	end

	loadedData.SchemaVersion = PlayerDataSchema.SCHEMA_VERSION

	return loadedData :: PlayerData
end

return PlayerDataSchema
