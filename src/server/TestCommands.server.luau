--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataSchema = require(ReplicatedStorage.Shared.PlayerDataSchema)
local PlayerDataService = require(ReplicatedStorage.Shared.PlayerDataService)
local ProgressionConfig = require(ReplicatedStorage.Shared.ProgressionConfig)
local StrengthService = require(script.Parent.StrengthService)
local StatUpgradeService = require(script.Parent.StatUpgradeService)
local WeaponCombatUtil = require(ReplicatedStorage.Shared.WeaponCombatUtil)
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)
local WeaponEquipService = require(script.Parent.WeaponEquipService)
local WeaponLoadoutService = require(script.Parent.WeaponLoadoutService)
local TutorialService = require(script.Parent.TutorialService)

local ALLOWED_USER_IDS: { [number]: boolean } = {
	[3953144856] = true,
	[93404147] = true,
	[1566664828] = true,
}

local HELP_TEXT =
	"Test commands: /cash <n>, /strength <n>, /rebirth, /resetdata, /equip <weapon>, /grantweapon <weapon>, /grantallweapons, /weapons, /help"

local function isAllowed(player: Player): boolean
	return ALLOWED_USER_IDS[player.UserId] == true
end

local function parseNonNegativeNumber(arg: string?): number?
	if arg == nil then
		return nil
	end

	local amount = tonumber(arg)
	if amount == nil or amount ~= amount or amount < 0 then
		return nil
	end

	return amount
end

local function commandCash(player: Player, arg: string?): ()
	local amount = parseNonNegativeNumber(arg)
	if amount == nil then
		warn(`[TestCommands] /cash requires a non-negative number`)
		return
	end

	if PlayerDataService.GetData(player) == nil then
		warn(`[TestCommands] player data not loaded`)
		return
	end

	if not PlayerDataService.SetField(player, "Cash", amount) then
		warn(`[TestCommands] failed to set cash`)
		return
	end

	local playerData = PlayerDataService.GetData(player)
	if playerData == nil then
		return
	end

	player:SetAttribute("Cash", playerData.Cash)
	warn(`[TestCommands] set Cash to {playerData.Cash}`)
end

local function commandStrength(player: Player, arg: string?): ()
	local amount = parseNonNegativeNumber(arg)
	if amount == nil or amount <= 0 then
		warn(`[TestCommands] /strength requires a positive number`)
		return
	end

	if not StrengthService.AddStrength(player, amount) then
		warn(`[TestCommands] failed to add strength`)
		return
	end

	warn(`[TestCommands] added {amount} strength`)
end

local function commandRebirth(player: Player): ()
	local playerData = PlayerDataService.GetData(player)
	if playerData == nil then
		warn(`[TestCommands] player data not loaded`)
		return
	end

	PlayerDataService.SetField(player, "Rebirths", playerData.Rebirths + 1)
	PlayerDataService.SetField(player, "Strength", ProgressionConfig.BaselineStrength)
	PlayerDataService.SetField(player, "Level", ProgressionConfig.BaselineLevel)
	PlayerDataService.SetField(player, "LevelProgress", ProgressionConfig.BaselineLevelProgress)
	StrengthService.SyncAttributes(player)

	warn(`[TestCommands] forced rebirth (Rebirths={playerData.Rebirths + 1})`)
end

local function commandResetData(player: Player): ()
	if PlayerDataService.GetData(player) == nil then
		warn(`[TestCommands] player data not loaded`)
		return
	end

	PlayerDataService.SetData(player, PlayerDataSchema.GetDefaultData())
	StrengthService.SyncAttributes(player)
	StatUpgradeService.ApplyWalkSpeed(player)
	WeaponLoadoutService.SyncPlayerWeaponData(player)
	WeaponEquipService.SyncEquippedWeaponVisual(player)
	TutorialService.OnPlayerDataLoaded(player)

	warn(`[TestCommands] reset player data to defaults`)
end

local function resolveWeaponId(input: string?): string?
	if input == nil or input == "" then
		return nil
	end

	if WeaponConfig.GetWeapon(input) ~= nil then
		return input
	end

	local lowerInput = string.lower(input)
	for _, weaponId in WeaponConfig.GetAllWeaponIds() do
		if string.lower(weaponId) == lowerInput then
			return weaponId
		end
	end

	return nil
end

local function grantWeaponToPlayer(player: Player, weaponId: string): boolean
	local playerData = PlayerDataService.GetData(player)
	if playerData == nil then
		return false
	end

	if WeaponCombatUtil.PlayerOwnsWeapon(playerData, weaponId) then
		return true
	end

	local ownedWeaponIds = table.clone(playerData.OwnedWeaponIds)
	table.insert(ownedWeaponIds, weaponId)
	playerData.OwnedWeaponIds = ownedWeaponIds
	PlayerDataService.SetData(player, playerData)
	return true
end

local function commandEquip(player: Player, arg: string?): ()
	local weaponId = resolveWeaponId(arg)
	if weaponId == nil then
		warn(`[TestCommands] /equip requires a valid weapon id. Try /weapons`)
		return
	end

	if PlayerDataService.GetData(player) == nil then
		warn(`[TestCommands] player data not loaded`)
		return
	end

	if not grantWeaponToPlayer(player, weaponId) then
		warn(`[TestCommands] failed to grant weapon`)
		return
	end

	if not PlayerDataService.SetField(player, "EquippedWeaponId", weaponId) then
		warn(`[TestCommands] failed to set equipped weapon`)
		return
	end

	WeaponLoadoutService.SyncPlayerWeaponData(player)
	WeaponEquipService.SyncEquippedWeaponVisual(player)

	local equippedWeaponId = player:GetAttribute("EquippedWeaponId")
	if typeof(equippedWeaponId) == "string" and equippedWeaponId == weaponId then
		warn(`[TestCommands] equipped {weaponId}`)
	else
		warn(
			`[TestCommands] requested {weaponId} but equipped {tostring(equippedWeaponId)} — check ownership or Assets.Weapons templates`
		)
	end
end

local function commandGrantWeapon(player: Player, arg: string?): ()
	local weaponId = resolveWeaponId(arg)
	if weaponId == nil then
		warn(`[TestCommands] /grantweapon requires a valid weapon id. Try /weapons`)
		return
	end

	if PlayerDataService.GetData(player) == nil then
		warn(`[TestCommands] player data not loaded`)
		return
	end

	if not grantWeaponToPlayer(player, weaponId) then
		warn(`[TestCommands] failed to grant weapon`)
		return
	end

	WeaponLoadoutService.SyncPlayerWeaponData(player)
	warn(`[TestCommands] granted {weaponId}`)
end

local function commandGrantAllWeapons(player: Player): ()
	if PlayerDataService.GetData(player) == nil then
		warn(`[TestCommands] player data not loaded`)
		return
	end

	for _, weaponId in WeaponConfig.GetAllWeaponIds() do
		if not grantWeaponToPlayer(player, weaponId) then
			warn(`[TestCommands] failed to grant weapon {weaponId}`)
			return
		end
	end

	WeaponLoadoutService.SyncPlayerWeaponData(player)
	warn(`[TestCommands] granted all weapons`)
end

local function commandWeapons(): ()
	warn(`[TestCommands] weapons: {table.concat(WeaponConfig.GetAllWeaponIds(), ", ")}`)
end

local function commandHelp(): ()
	warn(`[TestCommands] {HELP_TEXT}`)
end

local function handleCommand(player: Player, message: string): ()
	if not isAllowed(player) then
		return
	end

	local trimmed = string.match(message, "^%s*(.-)%s*$") or message
	if string.sub(trimmed, 1, 1) ~= "/" then
		return
	end

	local withoutSlash = string.sub(trimmed, 2)
	local commandName, arg = string.match(withoutSlash, "^(%S+)%s*(.*)$")
	if commandName == nil then
		return
	end

	commandName = string.lower(commandName)
	local argOrNil: string? = if arg ~= nil and arg ~= "" then arg else nil

	if commandName == "cash" then
		commandCash(player, argOrNil)
	elseif commandName == "strength" then
		commandStrength(player, argOrNil)
	elseif commandName == "rebirth" then
		commandRebirth(player)
	elseif commandName == "resetdata" then
		commandResetData(player)
	elseif commandName == "equip" then
		commandEquip(player, argOrNil)
	elseif commandName == "grantweapon" or commandName == "ownweapon" then
		commandGrantWeapon(player, argOrNil)
	elseif commandName == "grantallweapons" then
		commandGrantAllWeapons(player)
	elseif commandName == "weapons" then
		commandWeapons()
	elseif commandName == "help" then
		commandHelp()
	else
		warn(`[TestCommands] unknown command /{commandName}. {HELP_TEXT}`)
	end
end

local function onPlayerAdded(player: Player): ()
	player.Chatted:Connect(function(message: string)
		handleCommand(player, message)
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

--[[
	SELF-AUDIT (Section 7):
	- Players.PlayerAdded:Connect — script-lifetime singleton. OK.
	- player.Chatted:Connect — per-player; Instance destroy cleans up on leave. OK.
	- task.spawn(onPlayerAdded) for already-present players — one-shot, no long-lived capture. OK.
]]
