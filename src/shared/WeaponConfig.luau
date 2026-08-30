--!strict

export type WeaponDef = {
	Id: string,
	ToolAssetName: string,
	SwingAnimationId: string,
	DigAnimationId: string,
	BaseDamage: number,
	IsStarter: boolean,
	CashCost: number?,
	DevProductId: number,
	MinLevel: number?,
}

export type WeaponConfigModule = {
	Weapons: { [string]: WeaponDef },
	WeaponOrder: { string },
	GetWeapon: (weaponId: string) -> WeaponDef?,
	GetDefaultWeaponId: () -> string,
	GetAllWeaponIds: () -> { string },
	GetStarterWeaponIds: () -> { string },
	IsOwnedByDefault: (weaponId: string) -> boolean,
	GetCashCost: (weaponId: string) -> number?,
	GetDevProductId: (weaponId: string) -> number?,
	GetWeaponByDevProductId: (productId: number) -> WeaponDef?,
}

local DEFAULT_WEAPON_ID = "WoodenShovel"
local DEFAULT_DIG_ANIMATION_ID = "rbxassetid://125314733287462"

local function createWeaponDef(
	id: string,
	toolAssetName: string,
	baseDamage: number,
	isStarter: boolean,
	cashCost: number?
): WeaponDef
	return {
		Id = id,
		ToolAssetName = toolAssetName,
		SwingAnimationId = "rbxassetid://0",
		DigAnimationId = DEFAULT_DIG_ANIMATION_ID,
		BaseDamage = baseDamage,
		IsStarter = isStarter,
		CashCost = cashCost,
		DevProductId = 0,
		MinLevel = nil,
	}
end

-- Shovel tier list & pricing per GDD Section 2.8 (target-zone mapping + pricing formula).
local WeaponOrder: { string } = {
	"WoodenShovel",
	"IronShovel",
	"GoldShovel",
	"DiamondShovel",
	"EmeraldShovel",
	"AduriteShovel",
	"SpikyShovel",
	"MushroomShovel",
	"LoveShovel",
	"ChocolateShovel",
	"MagmaShovel",
	"RadioactiveShovel",
	"RainbowShovel",
	"GalaxyShovel",
	"SlimyShovel",
	"AngelicShovel",
	"SunshineShovel",
	"MoonlightShovel",
}

local Weapons: { [string]: WeaponDef } = {
	WoodenShovel = createWeaponDef("WoodenShovel", "WoodenShovel", 1, true, nil),
	IronShovel = createWeaponDef("IronShovel", "IronShovel", 3, false, 500),
	GoldShovel = createWeaponDef("GoldShovel", "GoldShovel", 15, false, 1100),
	DiamondShovel = createWeaponDef("DiamondShovel", "DiamondShovel", 30, false, 1700),
	EmeraldShovel = createWeaponDef("EmeraldShovel", "EmeraldShovel", 50, false, 4000),
	AduriteShovel = createWeaponDef("AduriteShovel", "AduriteShovel", 85, false, 10500),
	SpikyShovel = createWeaponDef("SpikyShovel", "SpikyShovel", 170, false, 39000),
	MushroomShovel = createWeaponDef("MushroomShovel", "MushroomShovel", 350, false, 195000),
	LoveShovel = createWeaponDef("LoveShovel", "LoveShovel", 750, false, 1600000),
	ChocolateShovel = createWeaponDef("ChocolateShovel", "ChocolateShovel", 2000, false, 7900000),
	MagmaShovel = createWeaponDef("MagmaShovel", "MagmaShovel", 3500, false, 21600000),
	RadioactiveShovel = createWeaponDef("RadioactiveShovel", "RadioactiveShovel", 7500, false, 116000000),
	RainbowShovel = createWeaponDef("RainbowShovel", "RainbowShovel", 15000, false, 617000000),
	GalaxyShovel = createWeaponDef("GalaxyShovel", "GalaxyShovel", 27500, false, 2390000000),
	SlimyShovel = createWeaponDef("SlimyShovel", "SlimyShovel", 50000, false, 5090000000),
	AngelicShovel = createWeaponDef("AngelicShovel", "AngelicShovel", 125000, false, 21600000000),
	SunshineShovel = createWeaponDef("SunshineShovel", "SunshineShovel", 500000, false, 91200000000),
	MoonlightShovel = createWeaponDef("MoonlightShovel", "MoonlightShovel", 1100000, false, 384600000000),
}

local devProductIdToWeaponId: { [number]: string } = {}
for weaponId, weaponDef in Weapons do
	if weaponDef.DevProductId > 0 then
		devProductIdToWeaponId[weaponDef.DevProductId] = weaponId
	end
end

local function GetWeapon(weaponId: string): WeaponDef?
	return Weapons[weaponId]
end

local function GetDefaultWeaponId(): string
	return DEFAULT_WEAPON_ID
end

local function GetAllWeaponIds(): { string }
	return table.clone(WeaponOrder)
end

local function GetStarterWeaponIds(): { string }
	local starterIds: { string } = {}
	for _, weaponId in WeaponOrder do
		local weaponDef = Weapons[weaponId]
		if weaponDef and weaponDef.IsStarter then
			table.insert(starterIds, weaponId)
		end
	end
	return starterIds
end

local function IsOwnedByDefault(weaponId: string): boolean
	local weaponDef = Weapons[weaponId]
	return weaponDef ~= nil and weaponDef.IsStarter
end

local function GetCashCost(weaponId: string): number?
	local weaponDef = Weapons[weaponId]
	if weaponDef == nil then
		return nil
	end
	return weaponDef.CashCost
end

local function GetDevProductId(weaponId: string): number?
	local weaponDef = Weapons[weaponId]
	if weaponDef == nil or weaponDef.DevProductId <= 0 then
		return nil
	end
	return weaponDef.DevProductId
end

local function GetWeaponByDevProductId(productId: number): WeaponDef?
	local weaponId = devProductIdToWeaponId[productId]
	if weaponId == nil then
		return nil
	end
	return Weapons[weaponId]
end

local WeaponConfig: WeaponConfigModule = {
	Weapons = Weapons,
	WeaponOrder = WeaponOrder,
	GetWeapon = GetWeapon,
	GetDefaultWeaponId = GetDefaultWeaponId,
	GetAllWeaponIds = GetAllWeaponIds,
	GetStarterWeaponIds = GetStarterWeaponIds,
	IsOwnedByDefault = IsOwnedByDefault,
	GetCashCost = GetCashCost,
	GetDevProductId = GetDevProductId,
	GetWeaponByDevProductId = GetWeaponByDevProductId,
}

return WeaponConfig
