--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataService = require(ReplicatedStorage.Shared.PlayerDataService)
local WeaponCombatUtil = require(ReplicatedStorage.Shared.WeaponCombatUtil)
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)

export type WeaponLoadoutServiceModule = {
	SyncPlayerWeaponData: (player: Player) -> (),
	EncodeOwnedWeaponIdsAttribute: (ownedWeaponIds: { string }) -> string,
}

local LEGACY_WEAPON_IDS: { [string]: boolean } = {
	BaseTool = true,
	-- Removed with the shovel tier list overhaul (GDD Section 2.8); PlayerDataSchema v7
	-- migrates saved data, but this guards any id that slips through unmigrated.
	Bucket = true,
	Spade = true,
	SmallShovel = true,
	MediumShovel = true,
	LargeShovel = true,
	BigScooper = true,
}

local function dedupeOwnedWeaponIds(ownedWeaponIds: { string }): { string }
	local seen: { [string]: boolean } = {}
	local deduped: { string } = {}

	for _, weaponId in ownedWeaponIds do
		if
			type(weaponId) == "string"
			and weaponId ~= ""
			and not seen[weaponId]
			and not LEGACY_WEAPON_IDS[weaponId]
			and WeaponConfig.GetWeapon(weaponId) ~= nil
		then
			seen[weaponId] = true
			table.insert(deduped, weaponId)
		end
	end

	return deduped
end

local function ensureStarterWeaponsOwned(ownedWeaponIds: { string }): { string }
	local ownedSet: { [string]: boolean } = {}
	for _, weaponId in ownedWeaponIds do
		ownedSet[weaponId] = true
	end

	local nextOwned = table.clone(ownedWeaponIds)
	for _, starterWeaponId in WeaponConfig.GetStarterWeaponIds() do
		if not ownedSet[starterWeaponId] then
			table.insert(nextOwned, starterWeaponId)
			ownedSet[starterWeaponId] = true
		end
	end

	return dedupeOwnedWeaponIds(nextOwned)
end

local function resolveEquippedWeaponId(equippedWeaponId: string?): string
	if typeof(equippedWeaponId) == "string" and equippedWeaponId ~= "" then
		if LEGACY_WEAPON_IDS[equippedWeaponId] then
			return WeaponConfig.GetDefaultWeaponId()
		end
		if WeaponConfig.GetWeapon(equippedWeaponId) ~= nil then
			return equippedWeaponId
		end
	end

	return WeaponConfig.GetDefaultWeaponId()
end

local function EncodeOwnedWeaponIdsAttribute(ownedWeaponIds: { string }): string
	return table.concat(ownedWeaponIds, ",")
end

local function SyncPlayerWeaponData(player: Player): ()
	local playerData = PlayerDataService.GetData(player)
	if playerData == nil then
		return
	end

	local ownedWeaponIds = ensureStarterWeaponsOwned(dedupeOwnedWeaponIds(playerData.OwnedWeaponIds))
	local equippedWeaponId = resolveEquippedWeaponId(playerData.EquippedWeaponId)
	local previousEquippedWeaponId = playerData.EquippedWeaponId
	local previousOwnedCount = #playerData.OwnedWeaponIds

	playerData.OwnedWeaponIds = ownedWeaponIds
	if not WeaponCombatUtil.PlayerOwnsWeapon(playerData, equippedWeaponId) then
		equippedWeaponId = WeaponConfig.GetDefaultWeaponId()
	end

	local changed = equippedWeaponId ~= previousEquippedWeaponId
		or #ownedWeaponIds ~= previousOwnedCount

	if changed then
		playerData.OwnedWeaponIds = ownedWeaponIds
		playerData.EquippedWeaponId = equippedWeaponId
		PlayerDataService.SetData(player, playerData)
	end

	player:SetAttribute("EquippedWeaponId", equippedWeaponId)
	player:SetAttribute("OwnedWeaponIds", EncodeOwnedWeaponIdsAttribute(ownedWeaponIds))
end

local WeaponLoadoutService: WeaponLoadoutServiceModule = {
	SyncPlayerWeaponData = SyncPlayerWeaponData,
	EncodeOwnedWeaponIdsAttribute = EncodeOwnedWeaponIdsAttribute,
}

return WeaponLoadoutService
