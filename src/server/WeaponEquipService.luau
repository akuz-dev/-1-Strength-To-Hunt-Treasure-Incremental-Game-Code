--!strict

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AttackZoneManager = require(script.Parent.AttackZoneManager)
local ObstacleAPI = require(script.Parent.ObstacleAPI)
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)
local WeaponCombatUtil = require(ReplicatedStorage.Shared.WeaponCombatUtil)
local PlayerDataService = require(ReplicatedStorage.Shared.PlayerDataService)

local WEAPONS_FOLDER_PATH = { "Assets", "Weapons" }
local WEAPON_VISUAL_ATTRIBUTE = "IsPlayerWeapon"
local WEAPON_GRIP_WELD_NAME = "WeaponGripWeld"
local WEAPON_VISUAL_FOLDER_NAME = "WeaponVisual"
local GRIP_PART_WAIT_TIMEOUT = 5
local COLLISION_GROUP_WEAPONS = "Weapons"
local COLLISION_GROUP_OBSTACLES = "Obstacles"

local weaponsCollisionGroupRegistered = false

export type WeaponEquipServiceModule = {
	Init: () -> (),
	SyncEquippedWeaponVisual: (player: Player) -> (),
}

type PlayerWeaponState = {
	equippedVisual: Model?,
	backpackGuardConnection: RBXScriptConnection?,
}

local weaponStateByUserId: { [number]: PlayerWeaponState } = {}
local warnedMissingToolAssets: { [string]: boolean } = {}
local initialized = false

local function warnMissingToolAssetOnce(assetKey: string, message: string): ()
	if warnedMissingToolAssets[assetKey] then
		return
	end
	warnedMissingToolAssets[assetKey] = true
	warn(`[WeaponEquipService] {message} — combat continues without a visual tool.`)
end

local function getWeaponsFolder(): Folder?
	local current: Instance = ReplicatedStorage
	for _, childName in WEAPONS_FOLDER_PATH do
		local child = current:FindFirstChild(childName)
		if child == nil or not child:IsA("Folder") then
			return nil
		end
		current = child
	end

	return current :: Folder
end

local function getRightGripPart(character: Model): BasePart?
	local rightHand = character:FindFirstChild("RightHand")
	if rightHand and rightHand:IsA("BasePart") then
		return rightHand
	end

	local rightArm = character:FindFirstChild("Right Arm")
	if rightArm and rightArm:IsA("BasePart") then
		return rightArm
	end

	return nil
end

local function waitForGripPart(character: Model): BasePart?
	local gripPart = getRightGripPart(character)
	if gripPart then
		return gripPart
	end

	local rightHand = character:WaitForChild("RightHand", GRIP_PART_WAIT_TIMEOUT)
	if rightHand and rightHand:IsA("BasePart") then
		return rightHand
	end

	local rightArm = character:WaitForChild("Right Arm", GRIP_PART_WAIT_TIMEOUT)
	if rightArm and rightArm:IsA("BasePart") then
		return rightArm
	end

	return getRightGripPart(character)
end

local function getOrCreateWeaponVisualFolder(character: Model): Folder
	local existing = character:FindFirstChild(WEAPON_VISUAL_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = WEAPON_VISUAL_FOLDER_NAME
	folder.Parent = character
	return folder
end

local function setEquippedWeaponAttribute(player: Player, weaponId: string): ()
	player:SetAttribute("EquippedWeaponId", weaponId)
end

local function isManagedWeaponInstance(instance: Instance): boolean
	return instance:GetAttribute(WEAPON_VISUAL_ATTRIBUTE) == true
end

local function clearWeaponGripWeld(character: Model): ()
	local gripPart = getRightGripPart(character)
	if gripPart == nil then
		return
	end

	local existingWeld = gripPart:FindFirstChild(WEAPON_GRIP_WELD_NAME)
	if existingWeld then
		existingWeld:Destroy()
	end
end

local function removeManagedWeaponInstancesFromBackpack(player: Player): ()
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack == nil then
		return
	end

	for _, child in backpack:GetChildren() do
		if isManagedWeaponInstance(child) then
			child:Destroy()
		end
	end
end

local function destroyEquippedVisual(state: PlayerWeaponState, character: Model?): ()
	if state.equippedVisual then
		if character then
			clearWeaponGripWeld(character)
		end
		state.equippedVisual:Destroy()
		state.equippedVisual = nil
	end
end

local function destroyEquippedToolForUserId(userId: number): ()
	local state = weaponStateByUserId[userId]
	if state == nil then
		return
	end

	local character: Model? = nil
	if state.equippedVisual then
		local parent = state.equippedVisual.Parent
		if parent and parent:IsA("Model") and parent:FindFirstChildOfClass("Humanoid") then
			character = parent
		elseif parent and parent:IsA("Folder") and parent.Parent and parent.Parent:IsA("Model") then
			character = parent.Parent
		end
	end

	destroyEquippedVisual(state, character)
end

local function cleanupPlayerWeaponState(userId: number): ()
	local state = weaponStateByUserId[userId]
	if state == nil then
		return
	end

	if state.backpackGuardConnection then
		state.backpackGuardConnection:Disconnect()
		state.backpackGuardConnection = nil
	end

	destroyEquippedToolForUserId(userId)
end

local function resolveWeaponIdForPlayer(player: Player): string?
	local playerData = PlayerDataService.GetData(player)
	if playerData == nil then
		return nil
	end

	local weaponId = WeaponCombatUtil.ResolveEquippedWeaponId(playerData)
	if not WeaponCombatUtil.PlayerOwnsWeapon(playerData, weaponId) then
		weaponId = WeaponConfig.GetDefaultWeaponId()
	end

	return weaponId
end

local function ensureWeaponsCollisionGroup(): ()
	if weaponsCollisionGroupRegistered then
		return
	end
	weaponsCollisionGroupRegistered = true
	pcall(function()
		PhysicsService:RegisterCollisionGroup(COLLISION_GROUP_WEAPONS)
	end)
	PhysicsService:CollisionGroupSetCollidable(COLLISION_GROUP_WEAPONS, COLLISION_GROUP_OBSTACLES, false)
end

local function configureWeaponPart(part: BasePart): ()
	ensureWeaponsCollisionGroup()
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.CollisionGroup = COLLISION_GROUP_WEAPONS
end

local function recoverCombatContactAfterEquip(userId: number): ()
	ObstacleAPI.stopAllContactForPlayer(userId)
	AttackZoneManager.rescanForPlayer(userId)
end

local function configureWeaponVisualParts(root: Instance): ()
	if root:IsA("BasePart") then
		configureWeaponPart(root)
	end

	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			configureWeaponPart(descendant)
		end
	end
end

-- Tool templates often place the mesh in a sibling Model (e.g. "default") positioned but not
-- welded to Handle. Only Handle is grip-welded to the hand, so orphan assemblies separate.
local function ensureWeaponVisualAssembly(visual: Model, handle: BasePart): ()
	visual.PrimaryPart = handle

	local connectedToHandle: { [BasePart]: boolean } = {}
	for _, part in handle:GetConnectedParts() do
		connectedToHandle[part] = true
	end

	local processedAssemblyRoots: { [BasePart]: boolean } = {}

	for _, descendant in visual:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end

		if connectedToHandle[descendant] then
			continue
		end

		local assemblyParts = descendant:GetConnectedParts()
		local assemblyRoot = assemblyParts[1]
		if assemblyRoot and processedAssemblyRoots[assemblyRoot] then
			continue
		end
		if assemblyRoot then
			processedAssemblyRoots[assemblyRoot] = true
		end

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = descendant
		weld.Parent = handle

		for _, part in assemblyParts do
			connectedToHandle[part] = true
		end
	end
end

local function cloneWeaponVisualFromTemplate(toolTemplate: Tool, grip: CFrame): Model?
	local handle = toolTemplate:FindFirstChild("Handle")
	if handle == nil or not handle:IsA("BasePart") then
		warn(`[WeaponEquipService] Tool template "{toolTemplate.Name}" is missing a Handle`)
		return nil
	end

	-- Clone the whole Tool so WeldConstraints between siblings (e.g. mesh + Handle) stay wired.
	local toolClone = toolTemplate:Clone()
	configureWeaponVisualParts(toolClone)

	local visual = Instance.new("Model")
	visual.Name = toolTemplate.Name
	visual:SetAttribute(WEAPON_VISUAL_ATTRIBUTE, true)
	visual:SetAttribute("WeaponGrip", grip)

	for _, child in toolClone:GetChildren() do
		child.Parent = visual
	end
	toolClone:Destroy()

	local handlePart = visual:FindFirstChild("Handle")
	if handlePart and handlePart:IsA("BasePart") then
		ensureWeaponVisualAssembly(visual, handlePart)
	end

	return visual
end

local function attachWeaponVisualToCharacter(visual: Model, character: Model): boolean
	local handle = visual:FindFirstChild("Handle")
	if handle == nil or not handle:IsA("BasePart") then
		return false
	end

	local gripPart = getRightGripPart(character)
	if gripPart == nil then
		return false
	end

	local grip = visual:GetAttribute("WeaponGrip")
	local gripCFrame = if typeof(grip) == "CFrame" then grip else CFrame.new()

	clearWeaponGripWeld(character)

	local visualFolder = getOrCreateWeaponVisualFolder(character)
	visual.Parent = visualFolder

	local weld = Instance.new("Weld")
	weld.Name = WEAPON_GRIP_WELD_NAME
	weld.Part0 = gripPart
	weld.Part1 = handle
	weld.C0 = CFrame.new()
	weld.C1 = gripCFrame
	weld.Parent = gripPart

	return true
end

local function bindBackpackGuard(player: Player): RBXScriptConnection?
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack == nil then
		return nil
	end

	return backpack.ChildAdded:Connect(function(child: Instance)
		if isManagedWeaponInstance(child) then
			child:Destroy()
		end
	end)
end

local function equipWeaponForUserId(userId: number): ()
	local player = Players:GetPlayerByUserId(userId)
	if player == nil then
		return
	end

	local weaponId = resolveWeaponIdForPlayer(player)
	if weaponId == nil then
		return
	end

	setEquippedWeaponAttribute(player, weaponId)
	removeManagedWeaponInstancesFromBackpack(player)

	local character = player.Character
	if character == nil then
		return
	end

	if waitForGripPart(character) == nil then
		return
	end

	local weaponDef = WeaponConfig.GetWeapon(weaponId)
	if weaponDef == nil then
		warn(`[WeaponEquipService] Weapon "{weaponId}" is not configured`)
		return
	end

	if weaponStateByUserId[userId] == nil then
		weaponStateByUserId[userId] = {
			equippedVisual = nil,
			backpackGuardConnection = nil,
		}
	end

	local state = weaponStateByUserId[userId]

	if state.backpackGuardConnection == nil then
		state.backpackGuardConnection = bindBackpackGuard(player)
	end

	local existingVisual = state.equippedVisual
	if existingVisual and existingVisual.Name == weaponDef.ToolAssetName and existingVisual.Parent ~= nil then
		return
	end

	local weaponsFolder = getWeaponsFolder()
	if weaponsFolder == nil then
		warnMissingToolAssetOnce("__folder__", "ReplicatedStorage.Assets.Weapons folder not found")
		return
	end

	local toolTemplate = weaponsFolder:FindFirstChild(weaponDef.ToolAssetName)
	if toolTemplate == nil or not toolTemplate:IsA("Tool") then
		warnMissingToolAssetOnce(weaponDef.ToolAssetName, `Tool template "{weaponDef.ToolAssetName}" not found in Assets.Weapons`)
		return
	end

	local visual = cloneWeaponVisualFromTemplate(toolTemplate, toolTemplate.Grip)
	if visual == nil then
		return
	end

	if not attachWeaponVisualToCharacter(visual, character) then
		visual:Destroy()
		return
	end

	local previousVisual = state.equippedVisual
	state.equippedVisual = visual

	if previousVisual and previousVisual ~= visual then
		previousVisual:Destroy()
	end

	recoverCombatContactAfterEquip(userId)
end

local function whenCharacterReadyForEquip(userId: number, character: Model, callback: () -> ()): ()
	task.defer(function()
		if character.Parent == nil then
			return
		end

		if waitForGripPart(character) == nil then
			return
		end

		if Players:GetPlayerByUserId(userId) == nil then
			return
		end

		callback()
	end)
end

local function onPlayerCharacterAdded(userId: number, character: Model): ()
	whenCharacterReadyForEquip(userId, character, function()
		equipWeaponForUserId(userId)
	end)
end

local function onPlayerCharacterRemoving(userId: number): ()
	destroyEquippedToolForUserId(userId)
end

local function hookPlayer(player: Player): ()
	local userId = player.UserId

	player.CharacterAdded:Connect(function(character: Model)
		onPlayerCharacterAdded(userId, character)
	end)

	player.CharacterRemoving:Connect(function()
		onPlayerCharacterRemoving(userId)
	end)

	if player.Character then
		onPlayerCharacterAdded(userId, player.Character)
	end
end

local function SyncEquippedWeaponVisual(player: Player): ()
	local character = player.Character
	if character then
		whenCharacterReadyForEquip(player.UserId, character, function()
			equipWeaponForUserId(player.UserId)
		end)
		return
	end

	equipWeaponForUserId(player.UserId)
end

local function Init(): ()
	if initialized then
		return
	end
	initialized = true

	Players.PlayerRemoving:Connect(function(player: Player)
		cleanupPlayerWeaponState(player.UserId)
		weaponStateByUserId[player.UserId] = nil
	end)

	for _, player in Players:GetPlayers() do
		hookPlayer(player)
	end

	Players.PlayerAdded:Connect(hookPlayer)
end

local WeaponEquipService: WeaponEquipServiceModule = {
	Init = Init,
	SyncEquippedWeaponVisual = SyncEquippedWeaponVisual,
}

--[[
	SELF-AUDIT (Section 7):
	- player.CharacterAdded/CharacterRemoving:Connect — per-player hooks via hookPlayer;
	  CharacterRemoving destroys welded visual clone only. OK.
	- backpack.ChildAdded:Connect — stored per player; destroys stray weapon instances only.
	  Disconnected on PlayerRemoving. OK.
	- Players.PlayerRemoving:Connect — registered once in Init. OK.
	- task.defer — one-shot grip wait then equip on CharacterAdded / data load. OK.
	- Tool templates cloned into Model under character.WeaponVisual — no Tool.Unequipped. OK.
	- WeldConstraint for orphan mesh assemblies welded to Handle at clone time — not hot path. OK.
]]

return WeaponEquipService
