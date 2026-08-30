--!strict
--!native

export type LootRarity =
	"Common"
	| "Uncommon"
	| "Rare"
	| "Epic"
	| "Legendary"
	| "Mythic"
	| "Godly"
	| "Divine"
	| "Celestial"
	| "Secret"

export type LootItemConfig = {
	Name: string,
	Rarity: LootRarity,
	BaseSellValue: number,
	IconId: string,
}

export type LootItemEntry = LootItemConfig & {
	ItemId: string,
}

export type ZoneSpawnTuning = {
	RespawnDelayMin: number,
	RespawnDelayMax: number,
	StaleTimeoutMin: number,
	StaleTimeoutMax: number,
}

export type ZoneRarityWeight = {
	Rarity: LootRarity,
	Weight: number,
}

export type LootConfigModule = {
	GetItem: (itemId: string) -> LootItemEntry?,
	GetItemsByRarity: (rarity: LootRarity) -> { LootItemEntry },
	GetAllLootIds: () -> { string },
	GetZoneSpawnTuning: (zoneNumber: number) -> ZoneSpawnTuning,
	RollRespawnDelay: (zoneNumber: number) -> number,
	RollStaleTimeout: (zoneNumber: number) -> number,
	RollLootItem: (
		zoneNumber: number,
		availableLootIds: { [string]: boolean }?,
		activeItemCounts: { [string]: number }?,
		excludeItemId: string?
	) -> LootItemEntry?,
}

-- Data table keyed by ItemId (GDD 1.5).
local LOOT_BY_ITEM_ID: { [string]: LootItemConfig } = {
	Snowflake = {
		Name = "Snowflake",
		Rarity = "Common",
		BaseSellValue = 100,
		IconId = "rbxassetid://101127721398134",
	},
	FireShard = {
		Name = "Fire Shard",
		Rarity = "Uncommon",
		BaseSellValue = 300,
		IconId = "rbxassetid://80138988307906",
	},
	Acorn = {
		Name = "Acorn",
		Rarity = "Common",
		BaseSellValue = 120,
		IconId = "rbxassetid://77687013541649",
	},
	MessageInABottle = {
		Name = "Message In A Bottle",
		Rarity = "Common",
		BaseSellValue = 200,
		IconId = "rbxassetid://140090323166216",
	},
	GoldCoin = {
		Name = "Gold Coin",
		Rarity = "Uncommon",
		BaseSellValue = 250,
		IconId = "rbxassetid://75490486399699",
	},
	Key = {
		Name = "Key",
		Rarity = "Uncommon",
		BaseSellValue = 275,
		IconId = "rbxassetid://79142777967290",
	},
	Goblet = {
		Name = "Goblet",
		Rarity = "Uncommon",
		BaseSellValue = 295,
		IconId = "rbxassetid://99644360781640",
	},
	Rune = {
		Name = "Rune",
		Rarity = "Rare",
		BaseSellValue = 500,
		IconId = "rbxassetid://126279010466239",
	},
	DiamondRing = {
		Name = "Diamond Ring",
		Rarity = "Rare",
		BaseSellValue = 870,
		IconId = "rbxassetid://128771873664049",
	},
	Pendant = {
		Name = "Pendant",
		Rarity = "Rare",
		BaseSellValue = 680,
		IconId = "rbxassetid://102647815048023",
	},
	TreasureChest = {
		Name = "Treasure Chest",
		Rarity = "Epic",
		BaseSellValue = 6000,
		IconId = "rbxassetid://121781999320565",
	},
	GemBag = {
		Name = "Gem Bag",
		Rarity = "Epic",
		BaseSellValue = 4750,
		IconId = "rbxassetid://118707999427940",
	},
	PhoenixFeather = {
		Name = "Phoenix Feather",
		Rarity = "Epic",
		BaseSellValue = 5800,
		IconId = "rbxassetid://0", -- TODO(GDD 1.5): replace with PhoenixFeather icon asset id
	},
	AncientScroll = {
		Name = "Ancient Scroll",
		Rarity = "Epic",
		BaseSellValue = 5100,
		IconId = "rbxassetid://0", -- TODO(GDD 1.5): replace with AncientScroll icon asset id
	},
	Compass = {
		Name = "Compass",
		Rarity = "Rare",
		BaseSellValue = 750,
		IconId = "rbxassetid://0", -- TODO(GDD 1.5): replace with Compass icon asset id
	},
	Trident = {
		Name = "Trident",
		Rarity = "Legendary",
		BaseSellValue = 98000,
		IconId = "rbxassetid://0", -- TODO(GDD 1.5): replace with Trident icon asset id
	},
	Hourglass = {
		Name = "Hourglass",
		Rarity = "Legendary",
		BaseSellValue = 95000,
		IconId = "rbxassetid://0", -- TODO(GDD 1.5): replace with Hourglass icon asset id
	},
	MageBook = {
		Name = "Mage Book",
		Rarity = "Legendary",
		BaseSellValue = 105000,
		IconId = "rbxassetid://0", -- TODO(GDD 1.5): replace with MageBook icon asset id
	},
	GoldenBanana = {
		Name = "Golden Banana",
		Rarity = "Mythic",
		BaseSellValue = 500000,
		IconId = "rbxassetid://0", -- TODO(GDD 1.5): replace with GoldenBanana icon asset id
	},
	Anchor = {
		Name = "Anchor",
		Rarity = "Legendary",
		BaseSellValue = 100000,
		IconId = "rbxassetid://0", -- TODO(GDD 1.5): replace with Anchor icon asset id
	},
	Barrel = {
		Name = "Barrel",
		Rarity = "Rare",
		BaseSellValue = 720,
		IconId = "rbxassetid://0", -- TODO(GDD 1.5): replace with Barrel icon asset id
	},
	CactusPlant = {
		Name = "Cactus Plant",
		Rarity = "Common",
		BaseSellValue = 130,
		IconId = "rbxassetid://0", -- TODO(GDD 1.5): replace with CactusPlant icon asset id
	},
	DiamondBench = {
		Name = "Diamond Bench",
		Rarity = "Divine",
		BaseSellValue = 10500000,
		IconId = "rbxassetid://0", -- TODO(GDD 1.5): replace with DiamondBench icon asset id
	},
	DragonTooth = {
		Name = "Dragon Tooth",
		Rarity = "Godly",
		BaseSellValue = 2050000,
		IconId = "rbxassetid://0", -- TODO(GDD 1.5): replace with DragonTooth icon asset id
	},
	EvilCactus = {
		Name = "Evil Cactus",
		Rarity = "Divine",
		BaseSellValue = 9800000,
		IconId = "rbxassetid://0", -- TODO(GDD 1.5): replace with EvilCactus icon asset id
	},
	Exaclibur = {
		Name = "Excalibur",
		Rarity = "Divine",
		BaseSellValue = 10200000,
		IconId = "rbxassetid://0", -- TODO(GDD 1.5): replace with Exaclibur icon asset id
	},
	FallenStar = {
		Name = "Fallen Star",
		Rarity = "Godly",
		BaseSellValue = 1980000,
		IconId = "rbxassetid://0", -- TODO(GDD 1.5): replace with FallenStar icon asset id
	},
	FryingPan = {
		Name = "Frying Pan",
		Rarity = "Uncommon",
		BaseSellValue = 290,
		IconId = "rbxassetid://0", -- TODO(GDD 1.5): replace with FryingPan icon asset id
	},
	GeorgeFish = {
		Name = "George Fish",
		Rarity = "Celestial",
		BaseSellValue = 52000000,
		IconId = "rbxassetid://0", -- TODO(GDD 1.5): replace with GeorgeFish icon asset id
	},
	GiantGem = {
		Name = "Giant Gem",
		Rarity = "Godly",
		BaseSellValue = 2000000,
		IconId = "rbxassetid://0", -- TODO(GDD 1.5): replace with GiantGem icon asset id
	},
	GoldenBell = {
		Name = "Golden Bell",
		Rarity = "Mythic",
		BaseSellValue = 485000,
		IconId = "rbxassetid://0", -- TODO(GDD 1.5): replace with GoldenBell icon asset id
	},
	GoldenMagnifyingGlass = {
		Name = "Golden Magnifying Glass",
		Rarity = "Divine",
		BaseSellValue = 10000000,
		IconId = "rbxassetid://0", -- TODO(GDD 1.5): replace with GoldenMagnifyingGlass icon asset id
	},
	KingsCrown = {
		Name = "Kings Crown",
		Rarity = "Mythic",
		BaseSellValue = 515000,
		IconId = "rbxassetid://0", -- TODO(GDD 1.5): replace with KingsCrown icon asset id
	},
	LuckyHorseShoe = {
		Name = "Lucky Horseshoe",
		Rarity = "Godly",
		BaseSellValue = 2100000,
		IconId = "rbxassetid://0", -- TODO(GDD 1.5): replace with LuckyHorseShoe icon asset id
	},
	Mammoth = {
		Name = "Mammoth",
		Rarity = "Secret",
		BaseSellValue = 250000000,
		IconId = "rbxassetid://0", -- TODO(GDD 1.5): replace with Mammoth icon asset id
	},
	MoonFragment = {
		Name = "Moon Fragment",
		Rarity = "Mythic",
		BaseSellValue = 500000,
		IconId = "rbxassetid://0", -- TODO(GDD 1.5): replace with MoonFragment icon asset id
	},
	Radio = {
		Name = "Radio",
		Rarity = "Celestial",
		BaseSellValue = 48000000,
		IconId = "rbxassetid://0", -- TODO(GDD 1.5): replace with Radio icon asset id
	},
	StopSign = {
		Name = "Stop Sign",
		Rarity = "Secret",
		BaseSellValue = 255000000,
		IconId = "rbxassetid://0", -- TODO(GDD 1.5): replace with StopSign icon asset id
	},
	TrafficCone = {
		Name = "Traffic Cone",
		Rarity = "Celestial",
		BaseSellValue = 50000000,
		IconId = "rbxassetid://0", -- TODO(GDD 1.5): replace with TrafficCone icon asset id
	},
}

-- Rarity ladder low → high (GDD 1.5). Per-zone weights live in ZONE_RARITY_WEIGHTS.

local FLOOR_WEIGHT = 100
local INTRO_LOWER_WEIGHT = 80
local INTRO_HIGHER_WEIGHT = 20
local MAX_PER_ITEM_PER_ZONE = 2

local ITEMS_BY_RARITY: { [LootRarity]: { LootItemEntry } } = {
	Common = {},
	Uncommon = {},
	Rare = {},
	Epic = {},
	Legendary = {},
	Mythic = {},
	Godly = {},
	Divine = {},
	Celestial = {},
	Secret = {},
}

-- Per-zone rarity roll weights (GDD 1.5). Introduction zones use 80/20; pure zones use 100%.
local ZONE_RARITY_WEIGHTS: { [number]: { ZoneRarityWeight } } = {
	[1] = {
		{ Rarity = "Common", Weight = INTRO_LOWER_WEIGHT },
		{ Rarity = "Uncommon", Weight = INTRO_HIGHER_WEIGHT },
	},
	[2] = {
		{ Rarity = "Uncommon", Weight = FLOOR_WEIGHT },
	},
	[3] = {
		{ Rarity = "Uncommon", Weight = INTRO_LOWER_WEIGHT },
		{ Rarity = "Rare", Weight = INTRO_HIGHER_WEIGHT },
	},
	[4] = {
		{ Rarity = "Rare", Weight = FLOOR_WEIGHT },
	},
	[5] = {
		{ Rarity = "Rare", Weight = INTRO_LOWER_WEIGHT },
		{ Rarity = "Epic", Weight = INTRO_HIGHER_WEIGHT },
	},
	[6] = {
		{ Rarity = "Epic", Weight = FLOOR_WEIGHT },
	},
	[7] = {
		{ Rarity = "Epic", Weight = INTRO_LOWER_WEIGHT },
		{ Rarity = "Legendary", Weight = INTRO_HIGHER_WEIGHT },
	},
	[8] = {
		{ Rarity = "Legendary", Weight = FLOOR_WEIGHT },
	},
	[9] = {
		{ Rarity = "Legendary", Weight = INTRO_LOWER_WEIGHT },
		{ Rarity = "Mythic", Weight = INTRO_HIGHER_WEIGHT },
	},
	[10] = {
		{ Rarity = "Mythic", Weight = FLOOR_WEIGHT },
	},
	[11] = {
		{ Rarity = "Mythic", Weight = INTRO_LOWER_WEIGHT },
		{ Rarity = "Godly", Weight = INTRO_HIGHER_WEIGHT },
	},
	[12] = {
		{ Rarity = "Godly", Weight = FLOOR_WEIGHT },
	},
	[13] = {
		{ Rarity = "Godly", Weight = INTRO_LOWER_WEIGHT },
		{ Rarity = "Divine", Weight = INTRO_HIGHER_WEIGHT },
	},
	[14] = {
		{ Rarity = "Divine", Weight = FLOOR_WEIGHT },
	},
	[15] = {
		{ Rarity = "Divine", Weight = INTRO_LOWER_WEIGHT },
		{ Rarity = "Celestial", Weight = INTRO_HIGHER_WEIGHT },
	},
	[16] = {
		{ Rarity = "Celestial", Weight = FLOOR_WEIGHT },
	},
	[17] = {
		{ Rarity = "Celestial", Weight = INTRO_LOWER_WEIGHT },
		{ Rarity = "Secret", Weight = INTRO_HIGHER_WEIGHT },
	},
}

local DEFAULT_ZONE_RARITY_WEIGHTS = ZONE_RARITY_WEIGHTS[1]

local DEFAULT_RESPAWN_DELAY_MIN = 15
local DEFAULT_RESPAWN_DELAY_MAX = 60
local DEFAULT_STALE_TIMEOUT_MIN = 15
local DEFAULT_STALE_TIMEOUT_MAX = 60

-- Per-zone loot spawn tuning (random delay rolled per loot node via RollRespawnDelay / RollStaleTimeout).
local ZONE_SPAWN_TUNING: { [number]: ZoneSpawnTuning } = {
	[1] = { RespawnDelayMin = 15, RespawnDelayMax = 60, StaleTimeoutMin = 15, StaleTimeoutMax = 60 },
	[2] = { RespawnDelayMin = 15, RespawnDelayMax = 60, StaleTimeoutMin = 15, StaleTimeoutMax = 60 },
	[3] = { RespawnDelayMin = 15, RespawnDelayMax = 60, StaleTimeoutMin = 15, StaleTimeoutMax = 60 },
	[4] = { RespawnDelayMin = 15, RespawnDelayMax = 60, StaleTimeoutMin = 15, StaleTimeoutMax = 60 },
	[5] = { RespawnDelayMin = 15, RespawnDelayMax = 60, StaleTimeoutMin = 15, StaleTimeoutMax = 60 },
	[6] = { RespawnDelayMin = 15, RespawnDelayMax = 60, StaleTimeoutMin = 15, StaleTimeoutMax = 60 },
	[7] = { RespawnDelayMin = 15, RespawnDelayMax = 60, StaleTimeoutMin = 15, StaleTimeoutMax = 60 },
	[8] = { RespawnDelayMin = 15, RespawnDelayMax = 60, StaleTimeoutMin = 15, StaleTimeoutMax = 60 },
	[9] = { RespawnDelayMin = 15, RespawnDelayMax = 60, StaleTimeoutMin = 15, StaleTimeoutMax = 60 },
	[10] = { RespawnDelayMin = 15, RespawnDelayMax = 60, StaleTimeoutMin = 15, StaleTimeoutMax = 60 },
	[11] = { RespawnDelayMin = 15, RespawnDelayMax = 60, StaleTimeoutMin = 15, StaleTimeoutMax = 60 },
	[12] = { RespawnDelayMin = 15, RespawnDelayMax = 60, StaleTimeoutMin = 15, StaleTimeoutMax = 60 },
	[13] = { RespawnDelayMin = 15, RespawnDelayMax = 60, StaleTimeoutMin = 15, StaleTimeoutMax = 60 },
	[14] = { RespawnDelayMin = 15, RespawnDelayMax = 60, StaleTimeoutMin = 15, StaleTimeoutMax = 60 },
	[15] = { RespawnDelayMin = 15, RespawnDelayMax = 60, StaleTimeoutMin = 15, StaleTimeoutMax = 60 },
	[16] = { RespawnDelayMin = 15, RespawnDelayMax = 60, StaleTimeoutMin = 15, StaleTimeoutMax = 60 },
	[17] = { RespawnDelayMin = 15, RespawnDelayMax = 60, StaleTimeoutMin = 15, StaleTimeoutMax = 60 },
}

for itemId, config in LOOT_BY_ITEM_ID do
	local entry: LootItemEntry = {
		ItemId = itemId,
		Name = config.Name,
		Rarity = config.Rarity,
		BaseSellValue = config.BaseSellValue,
		IconId = config.IconId,
	}
	table.insert(ITEMS_BY_RARITY[config.Rarity], entry)
end

local function getZoneRarityWeights(zoneNumber: number): { ZoneRarityWeight }
	local weights = ZONE_RARITY_WEIGHTS[zoneNumber]
	if weights == nil then
		return DEFAULT_ZONE_RARITY_WEIGHTS
	end

	return weights
end

local function isItemAvailable(item: LootItemEntry, availableLootIds: { [string]: boolean }?): boolean
	if availableLootIds == nil then
		return true
	end

	return availableLootIds[item.ItemId] == true
end

local function isItemUnderDuplicateCap(item: LootItemEntry, activeItemCounts: { [string]: number }?): boolean
	if activeItemCounts == nil then
		return true
	end

	local count = activeItemCounts[item.ItemId] or 0
	return count < MAX_PER_ITEM_PER_ZONE
end

local function pickItemFromRarity(
	chosenRarity: LootRarity,
	availableLootIds: { [string]: boolean }?,
	activeItemCounts: { [string]: number }?,
	excludeItemId: string?
): LootItemEntry?
	local rarityItems = ITEMS_BY_RARITY[chosenRarity]
	local cappedItems: { LootItemEntry } = {}
	local allAvailableItems: { LootItemEntry } = {}

	for _, item in rarityItems do
		if excludeItemId ~= nil and item.ItemId == excludeItemId then
			continue
		end

		if isItemAvailable(item, availableLootIds) then
			table.insert(allAvailableItems, item)
			if isItemUnderDuplicateCap(item, activeItemCounts) then
				table.insert(cappedItems, item)
			end
		end
	end

	local pool = if #cappedItems > 0 then cappedItems else allAvailableItems
	if #pool == 0 then
		return nil
	end

	return pool[math.random(1, #pool)]
end

local function rarityHasAvailableItem(rarity: LootRarity, availableLootIds: { [string]: boolean }?): boolean
	local items = ITEMS_BY_RARITY[rarity]
	if items == nil or #items == 0 then
		return false
	end

	for _, item in items do
		if isItemAvailable(item, availableLootIds) then
			return true
		end
	end

	return false
end

local function GetItem(itemId: string): LootItemEntry?
	local config = LOOT_BY_ITEM_ID[itemId]
	if config == nil then
		return nil
	end

	return {
		ItemId = itemId,
		Name = config.Name,
		Rarity = config.Rarity,
		BaseSellValue = config.BaseSellValue,
		IconId = config.IconId,
	}
end

local function GetItemsByRarity(rarity: LootRarity): { LootItemEntry }
	local items = ITEMS_BY_RARITY[rarity]
	if items == nil then
		return {}
	end

	return items
end

local function GetAllLootIds(): { string }
	local ids: { string } = {}
	for itemId in LOOT_BY_ITEM_ID do
		table.insert(ids, itemId)
	end

	return ids
end

local function GetZoneSpawnTuning(zoneNumber: number): ZoneSpawnTuning
	local tuning = ZONE_SPAWN_TUNING[zoneNumber]
	if tuning == nil then
		return {
			RespawnDelayMin = DEFAULT_RESPAWN_DELAY_MIN,
			RespawnDelayMax = DEFAULT_RESPAWN_DELAY_MAX,
			StaleTimeoutMin = DEFAULT_STALE_TIMEOUT_MIN,
			StaleTimeoutMax = DEFAULT_STALE_TIMEOUT_MAX,
		}
	end

	return tuning
end

local function RollRespawnDelay(zoneNumber: number): number
	local tuning = GetZoneSpawnTuning(zoneNumber)
	return math.random(tuning.RespawnDelayMin, tuning.RespawnDelayMax)
end

local function RollStaleTimeout(zoneNumber: number): number
	local tuning = GetZoneSpawnTuning(zoneNumber)
	return math.random(tuning.StaleTimeoutMin, tuning.StaleTimeoutMax)
end

local function RollLootItem(
	zoneNumber: number,
	availableLootIds: { [string]: boolean }?,
	activeItemCounts: { [string]: number }?,
	excludeItemId: string?
): LootItemEntry?
	local zoneWeights = getZoneRarityWeights(zoneNumber)
	local weightedRarities: { LootRarity } = {}
	local rarityWeights: { number } = {}

	for _, entry in zoneWeights do
		if rarityHasAvailableItem(entry.Rarity, availableLootIds) then
			table.insert(weightedRarities, entry.Rarity)
			table.insert(rarityWeights, entry.Weight)
		end
	end

	if #weightedRarities == 0 then
		return nil
	end

	local totalWeight = 0
	for _, weight in rarityWeights do
		totalWeight += weight
	end

	local roll = math.random() * totalWeight
	local cumulativeWeight = 0
	local chosenRarity: LootRarity? = nil

	for index, rarity in weightedRarities do
		cumulativeWeight += rarityWeights[index]
		if roll <= cumulativeWeight then
			chosenRarity = rarity
			break
		end
	end

	if chosenRarity == nil then
		chosenRarity = weightedRarities[#weightedRarities]
	end

	local excludedEntry = pickItemFromRarity(chosenRarity, availableLootIds, activeItemCounts, excludeItemId)
	if excludedEntry ~= nil then
		return excludedEntry
	end

	if excludeItemId ~= nil then
		return pickItemFromRarity(chosenRarity, availableLootIds, activeItemCounts, nil)
	end

	return nil
end

local LootConfig: LootConfigModule = {
	GetItem = GetItem,
	GetItemsByRarity = GetItemsByRarity,
	GetAllLootIds = GetAllLootIds,
	GetZoneSpawnTuning = GetZoneSpawnTuning,
	RollRespawnDelay = RollRespawnDelay,
	RollStaleTimeout = RollStaleTimeout,
	RollLootItem = RollLootItem,
}

return LootConfig
