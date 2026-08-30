--!strict

local ProgressionConfig = require(script.Parent.ProgressionConfig)
local PlayerDataSchema = require(script.Parent.PlayerDataSchema)
local WeaponConfig = require(script.Parent.WeaponConfig)

export type PlayerData = PlayerDataSchema.PlayerData

export type WeaponCombatUtilModule = {
	ResolveEquippedWeaponId: (playerData: PlayerData) -> string,
	GetWeaponBaseDamage: (playerData: PlayerData) -> number,
	GetWeaponBaseDamageForId: (weaponId: string?) -> number,
	GetEffectiveDamage: (playerData: PlayerData) -> number,
	GetClickStrengthGain: (playerData: PlayerData) -> number,
	GetClickStrengthGainForRebirths: (rebirthCount: number, equippedWeaponId: string?) -> number,
	PlayerOwnsWeapon: (playerData: PlayerData, weaponId: string) -> boolean,
}

local function ResolveEquippedWeaponId(playerData: PlayerData): string
	local equippedWeaponId = playerData.EquippedWeaponId
	if typeof(equippedWeaponId) == "string" and equippedWeaponId ~= "" then
		if WeaponConfig.GetWeapon(equippedWeaponId) ~= nil then
			return equippedWeaponId
		end
	end

	return WeaponConfig.GetDefaultWeaponId()
end

local function GetWeaponBaseDamageForId(weaponId: string?): number
	if typeof(weaponId) == "string" and weaponId ~= "" then
		local weaponDef = WeaponConfig.GetWeapon(weaponId)
		if weaponDef then
			return weaponDef.BaseDamage
		end
	end

	local defaultWeapon = WeaponConfig.GetWeapon(WeaponConfig.GetDefaultWeaponId())
	if defaultWeapon then
		return defaultWeapon.BaseDamage
	end

	return 1
end

local function GetWeaponBaseDamage(playerData: PlayerData): number
	return GetWeaponBaseDamageForId(ResolveEquippedWeaponId(playerData))
end

local function GetEffectiveDamage(playerData: PlayerData): number
	local baseDamage = GetWeaponBaseDamage(playerData)
	return playerData.Strength + (baseDamage - 1)
end

local function GetClickStrengthGainForRebirths(rebirthCount: number, equippedWeaponId: string?): number
	local baseDamage = GetWeaponBaseDamageForId(equippedWeaponId)
	local rebirthMultiplier = ProgressionConfig.GetStrengthGainMultiplier(rebirthCount)
	return math.round(baseDamage * rebirthMultiplier)
end

local function GetClickStrengthGain(playerData: PlayerData): number
	return GetClickStrengthGainForRebirths(playerData.Rebirths, ResolveEquippedWeaponId(playerData))
end

local function PlayerOwnsWeapon(playerData: PlayerData, weaponId: string): boolean
	if WeaponConfig.IsOwnedByDefault(weaponId) then
		return true
	end

	for _, ownedWeaponId in playerData.OwnedWeaponIds do
		if ownedWeaponId == weaponId then
			return true
		end
	end

	return false
end

local WeaponCombatUtil: WeaponCombatUtilModule = {
	ResolveEquippedWeaponId = ResolveEquippedWeaponId,
	GetWeaponBaseDamage = GetWeaponBaseDamage,
	GetWeaponBaseDamageForId = GetWeaponBaseDamageForId,
	GetEffectiveDamage = GetEffectiveDamage,
	GetClickStrengthGain = GetClickStrengthGain,
	GetClickStrengthGainForRebirths = GetClickStrengthGainForRebirths,
	PlayerOwnsWeapon = PlayerOwnsWeapon,
}

return WeaponCombatUtil
