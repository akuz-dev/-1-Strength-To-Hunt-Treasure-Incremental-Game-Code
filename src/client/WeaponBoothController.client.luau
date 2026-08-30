--!strict

local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local ShopBuyButton = require(script.Parent.ShopBuyButton)
local SoundPool = require(script.Parent.SoundPool)
local UIJuice = require(script.Parent.UIJuice)
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)

local UI_WAIT_TIMEOUT = 5
local REMOTE_WAIT_TIMEOUT = 5
local REMOTES_FOLDER_NAME = "Remotes"
local PURCHASE_REMOTE_NAME = "PurchaseWeapon"
local EQUIP_REMOTE_NAME = "EquipWeapon"
local SHOP_UPDATED_REMOTE_NAME = "WeaponShopUpdated"
local WEAPON_BOOTH_NAME = "WeaponBooth"
local MAIN_CONTENT_NAME = "MainContent"
local SCROLLING_FRAME_NAME = "ScrollingFrame"
local CLOSE_BUTTON_NAME = "CloseButton"
local WEAPON_NPC_TAG = "WeaponNPC"
local BUY_BUTTON_NAME = "BuyButton"
local ROBUX_BUY_BUTTON_NAME = "RobuxBuyButton"
local WEAPON_POWER_LABEL_NAME = "WeaponPower"
local ROW_NAME_PREFIX = "Weapon"
local BUY_UPGRADE_SOUND_PATH = { "Assets", "Sounds", "BuyUpgrade" }
local UI_OPEN_CLOSE_SOUND_PATH = { "Assets", "Sounds", "UiOpenClose" }

type WeaponShopDelta = {
	Action: string,
	WeaponId: string,
	EquippedWeaponId: string,
	OwnedWeaponIds: { string },
	Cash: number,
}

type WeaponRowBinding = {
	weaponId: string,
	rowFrameName: string,
	buyButton: GuiButton?,
	robuxButton: GuiButton?,
	powerLabel: TextLabel?,
}

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local purchaseRemote: RemoteEvent? = nil
local equipRemote: RemoteEvent? = nil
local weaponBoothGui: ScreenGui? = nil
local weaponBoothOuterFrame: Frame? = nil
local isBoothOpen = false
local activeOpeningPrompt: ProximityPrompt? = nil
local wiredBoothGuis: { [ScreenGui]: boolean } = {}
local connectedWeaponNpcPrompts: { [ProximityPrompt]: boolean } = {}
local buyUpgradeSoundTemplate: Sound? = nil
local uiOpenCloseSoundTemplate: Sound? = nil

local weaponRowBindings: { WeaponRowBinding } = {}

local function buildWeaponRowBindings(): ()
	table.clear(weaponRowBindings)

	for index, weaponId in WeaponConfig.WeaponOrder do
		table.insert(weaponRowBindings, {
			weaponId = weaponId,
			rowFrameName = `{ROW_NAME_PREFIX}{index}`,
			buyButton = nil,
			robuxButton = nil,
			powerLabel = nil,
		})
	end
end

buildWeaponRowBindings()

local function resolveBuyUpgradeSoundTemplate(): Sound?
	if buyUpgradeSoundTemplate then
		return buyUpgradeSoundTemplate
	end

	local current: Instance = ReplicatedStorage
	for _, childName in BUY_UPGRADE_SOUND_PATH do
		local child = current:WaitForChild(childName, REMOTE_WAIT_TIMEOUT)
		if child == nil then
			warn(`[WeaponBoothController] Sound path missing "{childName}" within {REMOTE_WAIT_TIMEOUT}s`)
			return nil
		end
		current = child
	end

	if current:IsA("Sound") then
		buyUpgradeSoundTemplate = current
		return current
	end

	warn("[WeaponBoothController] BuyUpgrade sound template is not a Sound")
	return nil
end

local function resolveUiOpenCloseSoundTemplate(): Sound?
	if uiOpenCloseSoundTemplate then
		return uiOpenCloseSoundTemplate
	end

	local current: Instance = ReplicatedStorage
	for _, childName in UI_OPEN_CLOSE_SOUND_PATH do
		local child = current:WaitForChild(childName, REMOTE_WAIT_TIMEOUT)
		if child == nil then
			warn(`[WeaponBoothController] Sound path missing "{childName}" within {REMOTE_WAIT_TIMEOUT}s`)
			return nil
		end
		current = child
	end

	if current:IsA("Sound") then
		uiOpenCloseSoundTemplate = current
		return current
	end

	warn("[WeaponBoothController] UiOpenClose sound template is not a Sound")
	return nil
end

local function playBuyUpgradeSound(): ()
	local template = resolveBuyUpgradeSoundTemplate()
	if template == nil then
		return
	end

	SoundPool.play2D(template)
end

local function findDescendantNamed(root: Instance, name: string, className: string): Instance?
	local direct = root:FindFirstChild(name, true)
	if direct ~= nil and direct:IsA(className) then
		return direct
	end

	for _, descendant in root:GetDescendants() do
		if descendant.Name == name and descendant:IsA(className) then
			return descendant
		end
	end

	return nil
end

local function findCloseButton(searchRoots: { Instance }): GuiButton?
	for _, root in searchRoots do
		local button = findDescendantNamed(root, CLOSE_BUTTON_NAME, "GuiButton")
		if button ~= nil and button:IsA("GuiButton") then
			return button
		end
	end

	return nil
end

local function findWeaponBoothGui(root: Instance): ScreenGui?
	local directChild = root:FindFirstChild(WEAPON_BOOTH_NAME)
	if directChild and directChild:IsA("ScreenGui") then
		return directChild
	end

	for _, descendant in root:GetDescendants() do
		if descendant.Name == WEAPON_BOOTH_NAME and descendant:IsA("ScreenGui") then
			return descendant
		end
	end

	return nil
end

local function waitForWeaponBoothGui(): ScreenGui
	while true do
		local existing = findWeaponBoothGui(playerGui)
		if existing then
			return existing
		end

		playerGui.DescendantAdded:Wait()
	end
end

local function getPlayerCash(): number
	local value = player:GetAttribute("Cash")
	if type(value) ~= "number" or value ~= value or value < 0 then
		return 0
	end
	return value
end

local function getEquippedWeaponId(): string
	local value = player:GetAttribute("EquippedWeaponId")
	if typeof(value) == "string" and value ~= "" then
		return value
	end
	return WeaponConfig.GetDefaultWeaponId()
end

local function getOwnedWeaponSet(): { [string]: boolean }
	local ownedSet: { [string]: boolean } = {}

	local attributeValue = player:GetAttribute("OwnedWeaponIds")
	if typeof(attributeValue) == "string" and attributeValue ~= "" then
		for weaponId in string.gmatch(attributeValue, "[^,]+") do
			if weaponId ~= "" then
				ownedSet[weaponId] = true
			end
		end
	end

	for _, starterWeaponId in WeaponConfig.GetStarterWeaponIds() do
		ownedSet[starterWeaponId] = true
	end

	return ownedSet
end

local function playerOwnsWeapon(weaponId: string): boolean
	if WeaponConfig.IsOwnedByDefault(weaponId) then
		return true
	end
	return getOwnedWeaponSet()[weaponId] == true
end

local function refreshRobuxButton(binding: WeaponRowBinding): ()
	local robuxButton = binding.robuxButton
	if robuxButton == nil then
		return
	end

	local owned = playerOwnsWeapon(binding.weaponId)
	local productId = WeaponConfig.GetDevProductId(binding.weaponId)
	local showRobux = not owned and productId ~= nil and productId > 0
	robuxButton.Visible = showRobux
	robuxButton.Active = showRobux
end

local function formatWeaponPower(weaponId: string): string
	local weaponDef = WeaponConfig.GetWeapon(weaponId)
	local baseDamage = if weaponDef then weaponDef.BaseDamage else 0
	return `+{NumberFormatter.Format(baseDamage)}`
end

local function applyWeaponPower(binding: WeaponRowBinding): ()
	local powerLabel = binding.powerLabel
	if powerLabel == nil then
		return
	end

	powerLabel.Text = formatWeaponPower(binding.weaponId)
end

local function refreshRow(binding: WeaponRowBinding): ()
	local buyButton = binding.buyButton
	if buyButton == nil then
		return
	end

	local equippedWeaponId = getEquippedWeaponId()
	local owned = playerOwnsWeapon(binding.weaponId)

	if owned then
		if equippedWeaponId == binding.weaponId then
			ShopBuyButton.applyEquipped(buyButton)
		else
			ShopBuyButton.applyEquip(buyButton)
		end
	else
		local cost = WeaponConfig.GetCashCost(binding.weaponId)
		if cost ~= nil then
			ShopBuyButton.applyPurchasePrice(buyButton, cost, getPlayerCash())
		end
	end

	refreshRobuxButton(binding)
end

local function refreshAllRows(): ()
	for _, binding in weaponRowBindings do
		refreshRow(binding)
	end
end

local function onCashBuyActivated(weaponId: string): ()
	local remote = purchaseRemote
	if remote == nil then
		return
	end

	if playerOwnsWeapon(weaponId) then
		return
	end

	remote:FireServer(weaponId)
end

local function onEquipActivated(weaponId: string): ()
	local remote = equipRemote
	if remote == nil then
		return
	end

	if not playerOwnsWeapon(weaponId) then
		return
	end

	if getEquippedWeaponId() == weaponId then
		return
	end

	remote:FireServer(weaponId)
end

local function onBuyButtonActivated(binding: WeaponRowBinding): ()
	if playerOwnsWeapon(binding.weaponId) then
		onEquipActivated(binding.weaponId)
	else
		onCashBuyActivated(binding.weaponId)
	end
end

local function onRobuxBuyActivated(weaponId: string): ()
	local productId = WeaponConfig.GetDevProductId(weaponId)
	if productId == nil or productId <= 0 then
		return
	end

	if playerOwnsWeapon(weaponId) then
		return
	end

	MarketplaceService:PromptProductPurchase(player, productId)
end

local function wireWeaponRow(rowRoot: Instance, binding: WeaponRowBinding): ()
	local buyButton = findDescendantNamed(rowRoot, BUY_BUTTON_NAME, "GuiButton")
	local robuxButton = findDescendantNamed(rowRoot, ROBUX_BUY_BUTTON_NAME, "GuiButton")
	local powerLabel = findDescendantNamed(rowRoot, WEAPON_POWER_LABEL_NAME, "TextLabel")

	if buyButton ~= nil and buyButton:IsA("GuiButton") then
		binding.buyButton = buyButton
		buyButton.Activated:Connect(function()
			onBuyButtonActivated(binding)
		end)
	else
		warn(`[WeaponBoothController] {BUY_BUTTON_NAME} not found under {binding.rowFrameName}`)
	end

	if robuxButton ~= nil and robuxButton:IsA("GuiButton") then
		binding.robuxButton = robuxButton
		robuxButton.Activated:Connect(function()
			onRobuxBuyActivated(binding.weaponId)
		end)
	else
		warn(`[WeaponBoothController] {ROBUX_BUY_BUTTON_NAME} not found under {binding.rowFrameName}`)
	end

	if powerLabel ~= nil and powerLabel:IsA("TextLabel") then
		binding.powerLabel = powerLabel
		applyWeaponPower(binding)
	else
		warn(`[WeaponBoothController] {WEAPON_POWER_LABEL_NAME} not found under {binding.rowFrameName}`)
	end

	refreshRow(binding)
end

local function wireWeaponRows(searchRoot: Instance): ()
	local scrollFrame = findDescendantNamed(searchRoot, SCROLLING_FRAME_NAME, "ScrollingFrame")
	local rowSearchRoot = if scrollFrame then scrollFrame else searchRoot

	for _, binding in weaponRowBindings do
		local rowFrame = rowSearchRoot:FindFirstChild(binding.rowFrameName, true)
		if rowFrame == nil or not rowFrame:IsA("GuiObject") then
			warn(`[WeaponBoothController] Row frame {binding.rowFrameName} not found`)
			continue
		end

		wireWeaponRow(rowFrame, binding)
	end
end

local function onBoothOpened(): ()
	refreshAllRows()
end

local function onBoothClosed(): ()
	isBoothOpen = false
	activeOpeningPrompt = nil
	if weaponBoothGui then
		weaponBoothGui.Enabled = false
	end
end

local function closeBooth(): ()
	if weaponBoothGui == nil or weaponBoothOuterFrame == nil then
		return
	end

	UIJuice.RequestCloseMenu(
		weaponBoothOuterFrame,
		uiOpenCloseSoundTemplate,
		onBoothClosed,
		weaponBoothGui.Enabled
	)
end

local function toggleBoothOpen(): ()
	if weaponBoothGui == nil or weaponBoothOuterFrame == nil then
		return
	end

	weaponBoothGui.Enabled = true
	local isOpen = UIJuice.ToggleMenu(
		weaponBoothOuterFrame,
		uiOpenCloseSoundTemplate,
		uiOpenCloseSoundTemplate,
		onBoothClosed
	)
	if isOpen then
		isBoothOpen = true
		onBoothOpened()
	elseif UIJuice.GetMenuPhase(weaponBoothOuterFrame) == "closed" then
		onBoothClosed()
	end
end

local function getWeaponNpcPrompt(taggedPart: Instance): ProximityPrompt?
	local proximityPrompt = taggedPart:FindFirstChildWhichIsA("ProximityPrompt")
	if proximityPrompt and proximityPrompt:IsA("ProximityPrompt") then
		return proximityPrompt
	end

	return nil
end

local function registerWeaponNpc(taggedPart: Instance): ()
	if not CollectionService:HasTag(taggedPart, WEAPON_NPC_TAG) then
		return
	end

	local proximityPrompt = getWeaponNpcPrompt(taggedPart)
	if proximityPrompt == nil then
		warn(
			`[WeaponBoothController] ProximityPrompt child not found on tagged {WEAPON_NPC_TAG} part {taggedPart:GetFullName()}`
		)
		return
	end

	if connectedWeaponNpcPrompts[proximityPrompt] then
		return
	end

	connectedWeaponNpcPrompts[proximityPrompt] = true

	proximityPrompt.Triggered:Connect(function(triggeringPlayer: Player)
		if triggeringPlayer ~= player then
			return
		end

		toggleBoothOpen()
		if isBoothOpen then
			activeOpeningPrompt = proximityPrompt
		elseif activeOpeningPrompt == proximityPrompt then
			activeOpeningPrompt = nil
		end
	end)

	proximityPrompt.PromptHidden:Connect(function()
		if isBoothOpen and activeOpeningPrompt == proximityPrompt then
			closeBooth()
		end
	end)
end

local function connectWeaponNpcPrompts(): ()
	for _, weaponNpc in CollectionService:GetTagged(WEAPON_NPC_TAG) do
		registerWeaponNpc(weaponNpc)
	end

	CollectionService:GetInstanceAddedSignal(WEAPON_NPC_TAG):Connect(registerWeaponNpc)
end

local function wireCloseButton(outerFrame: Frame, gui: ScreenGui): ()
	local closeButton = findCloseButton({ outerFrame, gui })
	if closeButton then
		closeButton.Activated:Connect(closeBooth)
	else
		warn(`[WeaponBoothController] {CLOSE_BUTTON_NAME} GuiButton not found under {WEAPON_BOOTH_NAME}`)
	end
end

local function bindWeaponBoothGui(gui: ScreenGui): ()
	if wiredBoothGuis[gui] then
		return
	end

	gui.Enabled = false
	UIJuice.WireMenuButtons(gui, nil)

	local staleBackdrop = gui:FindFirstChild("Backdrop")
	if staleBackdrop then
		staleBackdrop:Destroy()
	end

	local outerFrame = gui:WaitForChild("Frame", UI_WAIT_TIMEOUT)
	if outerFrame == nil or not outerFrame:IsA("Frame") then
		warn("[WeaponBoothController] WeaponBooth outer Frame not found")
		return
	end

	local mainContent = outerFrame:WaitForChild(MAIN_CONTENT_NAME, UI_WAIT_TIMEOUT)
	if mainContent == nil then
		warn(`[WeaponBoothController] {MAIN_CONTENT_NAME} not found under WeaponBooth`)
		return
	end

	wiredBoothGuis[gui] = true
	weaponBoothGui = gui
	weaponBoothOuterFrame = outerFrame

	UIJuice.EnsureMenuUIScale(outerFrame)
	UIJuice.EnsureMenuCanvasGroup(outerFrame)
	wireCloseButton(outerFrame, gui)
	wireWeaponRows(mainContent)

	gui.Destroying:Once(function()
		wiredBoothGuis[gui] = nil
		if weaponBoothGui == gui then
			weaponBoothGui = nil
			weaponBoothOuterFrame = nil
			isBoothOpen = false
			for _, binding in weaponRowBindings do
				binding.buyButton = nil
				binding.robuxButton = nil
				binding.powerLabel = nil
			end
		end
	end)
end

local function connectShopAttributeListeners(): ()
	player:GetAttributeChangedSignal("EquippedWeaponId"):Connect(refreshAllRows)
	player:GetAttributeChangedSignal("OwnedWeaponIds"):Connect(refreshAllRows)
	player:GetAttributeChangedSignal("Cash"):Connect(refreshAllRows)
end

local function onShopDelta(payload: unknown): ()
	if type(payload) ~= "table" then
		return
	end

	local delta = payload :: WeaponShopDelta
	if type(delta.WeaponId) ~= "string" then
		return
	end

	refreshAllRows()

	if delta.Action == "Purchase" then
		playBuyUpgradeSound()
	end
end

local function initialize(): ()
	bindWeaponBoothGui(waitForWeaponBoothGui())

	playerGui.ChildAdded:Connect(function(child: Instance)
		if child.Name == WEAPON_BOOTH_NAME and child:IsA("ScreenGui") then
			bindWeaponBoothGui(child)
		end
	end)

	local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME, REMOTE_WAIT_TIMEOUT)
	if remotesFolder == nil then
		warn(`[WeaponBoothController] Remotes folder not found within {REMOTE_WAIT_TIMEOUT}s`)
		return
	end

	local purchaseRemoteInstance = remotesFolder:WaitForChild(PURCHASE_REMOTE_NAME, REMOTE_WAIT_TIMEOUT)
	if purchaseRemoteInstance and purchaseRemoteInstance:IsA("RemoteEvent") then
		purchaseRemote = purchaseRemoteInstance
	else
		warn(`[WeaponBoothController] {PURCHASE_REMOTE_NAME} RemoteEvent not found`)
	end

	local equipRemoteInstance = remotesFolder:WaitForChild(EQUIP_REMOTE_NAME, REMOTE_WAIT_TIMEOUT)
	if equipRemoteInstance and equipRemoteInstance:IsA("RemoteEvent") then
		equipRemote = equipRemoteInstance
	else
		warn(`[WeaponBoothController] {EQUIP_REMOTE_NAME} RemoteEvent not found`)
	end

	local shopUpdatedRemoteInstance = remotesFolder:WaitForChild(SHOP_UPDATED_REMOTE_NAME, REMOTE_WAIT_TIMEOUT)
	if shopUpdatedRemoteInstance and shopUpdatedRemoteInstance:IsA("RemoteEvent") then
		shopUpdatedRemoteInstance.OnClientEvent:Connect(onShopDelta)
	else
		warn(`[WeaponBoothController] {SHOP_UPDATED_REMOTE_NAME} RemoteEvent not found`)
	end

	resolveBuyUpgradeSoundTemplate()
	resolveUiOpenCloseSoundTemplate()
	connectWeaponNpcPrompts()
	connectShopAttributeListeners()
	refreshAllRows()
end

initialize()

--[[
	SELF-AUDIT (Section 7):
	- WeaponShopUpdated.OnClientEvent:Connect — permanent client-lifetime listener. OK.
	- ProximityPrompt.Triggered:Connect — wired per tagged WeaponNPC prompt. OK.
	- CollectionService WeaponNPC added signal:Connect — script-lifetime singleton. OK.
	- Buy / RobuxBuy / CloseButton Activated — wired per WeaponBooth ScreenGui; Destroying clears refs. OK.
	- EquippedWeaponId / OwnedWeaponIds / Cash GetAttributeChangedSignal — permanent client-lifetime. OK.
	- BuyUpgrade via SoundPool.play2D — client-only audio on successful purchase delta (GDD 5.5). OK.
]]
