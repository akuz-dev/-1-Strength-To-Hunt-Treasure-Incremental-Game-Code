--!strict

local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local ProgressionConfig = require(ReplicatedStorage.Shared.ProgressionConfig)
local StatUpgradeConfig = require(ReplicatedStorage.Shared.StatUpgradeConfig)
local ShopBuyButton = require(script.Parent.ShopBuyButton)
local SoundPool = require(script.Parent.SoundPool)
local UIJuice = require(script.Parent.UIJuice)

local UI_WAIT_TIMEOUT = 5
local REMOTE_WAIT_TIMEOUT = 5
local REMOTES_FOLDER_NAME = "Remotes"
local PURCHASE_REMOTE_NAME = "PurchaseStatUpgrade"
local UPGRADES_BOOTH_NAME = "UpgradesBooth"
local MAIN_CONTENT_NAME = "MainContent"
local CLOSE_BUTTON_NAME = "CloseButton"
local UPGRADE_NPC_TAG = "UpgradeNPC"
local BUY_UPGRADE_SOUND_PATH = { "Assets", "Sounds", "BuyUpgrade" }
local UI_OPEN_CLOSE_SOUND_PATH = { "Assets", "Sounds", "UiOpenClose" }

type StatUpgradeDelta = {
	StatName: string,
	Level: number,
	Cash: number,
}

type StatRowBinding = {
	statName: string,
	levelAttribute: string,
	rowFrameName: string,
	beforeLabelName: string,
	afterLabelName: string,
	buyButtonName: string,
	robuxButtonName: string,
	beforeLabel: TextLabel?,
	afterLabel: TextLabel?,
	buyButton: GuiButton?,
}

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local purchaseRemote: RemoteEvent? = nil
local upgradesBoothGui: ScreenGui? = nil
local upgradesBoothOuterFrame: Frame? = nil
local isBoothOpen = false
local activeOpeningPrompt: ProximityPrompt? = nil
local wiredBoothGuis: { [ScreenGui]: boolean } = {}
local connectedUpgradeNpcPrompts: { [ProximityPrompt]: boolean } = {}
local buyUpgradeSoundTemplate: Sound? = nil
local uiOpenCloseSoundTemplate: Sound? = nil

local STAT_ROWS: { StatRowBinding } = {
	{
		statName = "Agility",
		levelAttribute = "AgilityLevel",
		rowFrameName = "AttackSpeedUpgrade",
		beforeLabelName = "BeforeAttackSpeedUpgrades",
		afterLabelName = "AfterAttackSpeedUpgrades",
		buyButtonName = "BuyAttackSpeed1",
		robuxButtonName = "RobuxBuyAttackSpeed1",
		beforeLabel = nil,
		afterLabel = nil,
	},
	{
		statName = "WalkSpeed",
		levelAttribute = "WalkSpeedLevel",
		rowFrameName = "WalkSpeedUpgrades",
		beforeLabelName = "BeforeWalkSpeedUpgrade",
		afterLabelName = "AfterWalkSpeedUpgrade",
		buyButtonName = "BuyWalkSpeed1",
		robuxButtonName = "RobuxBuyWalkSpeed1",
		beforeLabel = nil,
		afterLabel = nil,
	},
	{
		statName = "Capacity",
		levelAttribute = "CapacityLevel",
		rowFrameName = "BackpackUpgrades",
		beforeLabelName = "BeforeCarryUpgrade",
		afterLabelName = "AfterCarryUpgrade",
		buyButtonName = "BuyCarryUpgrade1",
		robuxButtonName = "RobuxBuyCarryUpgrade1",
		beforeLabel = nil,
		afterLabel = nil,
	},
	{
		statName = "Range",
		levelAttribute = "RangeLevel",
		rowFrameName = "RangeUpgrade",
		beforeLabelName = "BeforeRangeUpgrades",
		afterLabelName = "AfterRangeUpgrades",
		buyButtonName = "BuyRange1",
		robuxButtonName = "RobuxBuyRange1",
		beforeLabel = nil,
		afterLabel = nil,
	},
}

local function resolveBuyUpgradeSoundTemplate(): Sound?
	if buyUpgradeSoundTemplate then
		return buyUpgradeSoundTemplate
	end

	local current: Instance = ReplicatedStorage
	for _, childName in BUY_UPGRADE_SOUND_PATH do
		local child = current:WaitForChild(childName, REMOTE_WAIT_TIMEOUT)
		if child == nil then
			warn(`[UpgradesBoothController] Sound path missing "{childName}" within {REMOTE_WAIT_TIMEOUT}s`)
			return nil
		end
		current = child
	end

	if current:IsA("Sound") then
		buyUpgradeSoundTemplate = current
		return current
	end

	warn("[UpgradesBoothController] BuyUpgrade sound template is not a Sound")
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
			warn(`[UpgradesBoothController] Sound path missing "{childName}" within {REMOTE_WAIT_TIMEOUT}s`)
			return nil
		end
		current = child
	end

	if current:IsA("Sound") then
		uiOpenCloseSoundTemplate = current
		return current
	end

	warn("[UpgradesBoothController] UiOpenClose sound template is not a Sound")
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

local function findUpgradesBoothGui(root: Instance): ScreenGui?
	local directChild = root:FindFirstChild(UPGRADES_BOOTH_NAME)
	if directChild and directChild:IsA("ScreenGui") then
		return directChild
	end

	for _, descendant in root:GetDescendants() do
		if descendant.Name == UPGRADES_BOOTH_NAME and descendant:IsA("ScreenGui") then
			return descendant
		end
	end

	return nil
end

local function waitForUpgradesBoothGui(): ScreenGui
	while true do
		local existing = findUpgradesBoothGui(playerGui)
		if existing then
			return existing
		end

		playerGui.DescendantAdded:Wait()
	end
end

local function getStatLevel(levelAttribute: string): number
	local value = player:GetAttribute(levelAttribute)
	if type(value) ~= "number" or value ~= value or value < 0 then
		return 0
	end
	return value
end

local function getPlayerCash(): number
	local value = player:GetAttribute("Cash")
	if type(value) ~= "number" or value ~= value or value < 0 then
		return 0
	end
	return value
end

local function formatDisplayValue(statName: string, level: number): string
	if statName == "Agility" then
		local effect = StatUpgradeConfig.GetEffect("Agility", level)
		if effect == nil then
			return ProgressionConfig.FormatMultiplier(1)
		end
		return ProgressionConfig.FormatMultiplier(effect)
	elseif statName == "Range" then
		return NumberFormatter.Format(StatUpgradeConfig.GetEffectiveRange(level), { Decimals = 2 })
	elseif statName == "Capacity" or statName == "WalkSpeed" then
		-- Flat tracks: show purchased bonus units starting at 0 (not base capacity/walk speed).
		local effect = StatUpgradeConfig.GetEffect(statName, level)
		if effect == nil then
			return "0"
		end
		return NumberFormatter.Format(effect)
	end

	return "0"
end

local function refreshRow(binding: StatRowBinding): ()
	local level = getStatLevel(binding.levelAttribute)
	if binding.beforeLabel then
		binding.beforeLabel.Text = formatDisplayValue(binding.statName, level)
	end
	if binding.afterLabel then
		binding.afterLabel.Text = formatDisplayValue(binding.statName, level + 1)
	end

	if binding.buyButton then
		local nextLevel = level + 1
		local cost = StatUpgradeConfig.GetCost(binding.statName, nextLevel)
		if cost ~= nil then
			ShopBuyButton.applyPurchasePrice(binding.buyButton, cost, getPlayerCash())
		end
	end
end

local function refreshAllRows(): ()
	for _, binding in STAT_ROWS do
		refreshRow(binding)
	end
end

local function onCashBuyActivated(statName: string): ()
	local remote = purchaseRemote
	if remote == nil then
		return
	end

	remote:FireServer(statName)
end

local function onRobuxBuyActivated(statName: string): ()
	local def = StatUpgradeConfig.Stats[statName]
	if def == nil then
		return
	end

	local productId = def.DevProductId
	if type(productId) ~= "number" or productId <= 0 then
		return
	end

	MarketplaceService:PromptProductPurchase(player, productId)
end

local function wireStatRow(rowRoot: Instance, binding: StatRowBinding): ()
	local beforeLabel = findDescendantNamed(rowRoot, binding.beforeLabelName, "TextLabel")
	local afterLabel = findDescendantNamed(rowRoot, binding.afterLabelName, "TextLabel")
	local buyButton = findDescendantNamed(rowRoot, binding.buyButtonName, "GuiButton")
	local robuxButton = findDescendantNamed(rowRoot, binding.robuxButtonName, "GuiButton")

	if beforeLabel ~= nil and beforeLabel:IsA("TextLabel") then
		binding.beforeLabel = beforeLabel
	else
		warn(`[UpgradesBoothController] {binding.beforeLabelName} not found under {binding.rowFrameName}`)
	end

	if afterLabel ~= nil and afterLabel:IsA("TextLabel") then
		binding.afterLabel = afterLabel
	else
		warn(`[UpgradesBoothController] {binding.afterLabelName} not found under {binding.rowFrameName}`)
	end

	if buyButton ~= nil and buyButton:IsA("GuiButton") then
		binding.buyButton = buyButton
		buyButton.Activated:Connect(function()
			onCashBuyActivated(binding.statName)
		end)
	else
		warn(`[UpgradesBoothController] {binding.buyButtonName} not found under {binding.rowFrameName}`)
	end

	if robuxButton ~= nil and robuxButton:IsA("GuiButton") then
		robuxButton.Activated:Connect(function()
			onRobuxBuyActivated(binding.statName)
		end)
	else
		warn(`[UpgradesBoothController] {binding.robuxButtonName} not found under {binding.rowFrameName}`)
	end

	refreshRow(binding)
end

local function wireStatRows(searchRoot: Instance): ()
	for _, binding in STAT_ROWS do
		-- Prefer exact row frame name (ignore duplicate AttackSpeedUpgrades).
		local rowFrame = searchRoot:FindFirstChild(binding.rowFrameName, true)
		if rowFrame == nil or not rowFrame:IsA("GuiObject") then
			warn(`[UpgradesBoothController] Row frame {binding.rowFrameName} not found`)
			continue
		end

		wireStatRow(rowFrame, binding)
	end
end

local function onBoothOpened(): ()
	refreshAllRows()
end

local function onBoothClosed(): ()
	isBoothOpen = false
	activeOpeningPrompt = nil
	if upgradesBoothGui then
		upgradesBoothGui.Enabled = false
	end
end

local function closeBooth(): ()
	if upgradesBoothGui == nil or upgradesBoothOuterFrame == nil then
		return
	end

	UIJuice.RequestCloseMenu(
		upgradesBoothOuterFrame,
		uiOpenCloseSoundTemplate,
		onBoothClosed,
		upgradesBoothGui.Enabled
	)
end

local function toggleBoothOpen(): ()
	if upgradesBoothGui == nil or upgradesBoothOuterFrame == nil then
		return
	end

	upgradesBoothGui.Enabled = true
	local isOpen = UIJuice.ToggleMenu(
		upgradesBoothOuterFrame,
		uiOpenCloseSoundTemplate,
		uiOpenCloseSoundTemplate,
		onBoothClosed
	)
	if isOpen then
		isBoothOpen = true
		onBoothOpened()
	elseif UIJuice.GetMenuPhase(upgradesBoothOuterFrame) == "closed" then
		onBoothClosed()
	end
end

local function getUpgradeNpcPrompt(taggedPart: Instance): ProximityPrompt?
	local proximityPrompt = taggedPart:FindFirstChildWhichIsA("ProximityPrompt")
	if proximityPrompt and proximityPrompt:IsA("ProximityPrompt") then
		return proximityPrompt
	end

	return nil
end

local function registerUpgradeNpc(taggedPart: Instance): ()
	if not CollectionService:HasTag(taggedPart, UPGRADE_NPC_TAG) then
		return
	end

	local proximityPrompt = getUpgradeNpcPrompt(taggedPart)
	if proximityPrompt == nil then
		warn(
			`[UpgradesBoothController] ProximityPrompt child not found on tagged {UPGRADE_NPC_TAG} part {taggedPart:GetFullName()}`
		)
		return
	end

	if connectedUpgradeNpcPrompts[proximityPrompt] then
		return
	end

	connectedUpgradeNpcPrompts[proximityPrompt] = true

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

local function connectUpgradeNpcPrompts(): ()
	for _, upgradeNpc in CollectionService:GetTagged(UPGRADE_NPC_TAG) do
		registerUpgradeNpc(upgradeNpc)
	end

	CollectionService:GetInstanceAddedSignal(UPGRADE_NPC_TAG):Connect(registerUpgradeNpc)
end

local function wireCloseButton(outerFrame: Frame, gui: ScreenGui): ()
	local closeButton = findCloseButton({ outerFrame, gui })
	if closeButton then
		closeButton.Activated:Connect(closeBooth)
	else
		warn(`[UpgradesBoothController] {CLOSE_BUTTON_NAME} GuiButton not found under {UPGRADES_BOOTH_NAME}`)
	end
end

local function bindUpgradesBoothGui(gui: ScreenGui): ()
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
		warn("[UpgradesBoothController] UpgradesBooth outer Frame not found")
		return
	end

	local mainContent = outerFrame:WaitForChild(MAIN_CONTENT_NAME, UI_WAIT_TIMEOUT)
	if mainContent == nil then
		warn(`[UpgradesBoothController] {MAIN_CONTENT_NAME} not found under UpgradesBooth`)
		return
	end

	wiredBoothGuis[gui] = true
	upgradesBoothGui = gui
	upgradesBoothOuterFrame = outerFrame

	UIJuice.EnsureMenuUIScale(outerFrame)
	UIJuice.EnsureMenuCanvasGroup(outerFrame)
	wireCloseButton(outerFrame, gui)
	wireStatRows(mainContent)

	gui.Destroying:Once(function()
		wiredBoothGuis[gui] = nil
		if upgradesBoothGui == gui then
			upgradesBoothGui = nil
			upgradesBoothOuterFrame = nil
			isBoothOpen = false
			for _, binding in STAT_ROWS do
				binding.beforeLabel = nil
				binding.afterLabel = nil
				binding.buyButton = nil
			end
		end
	end)
end

local function connectLevelAttributeListeners(): ()
	for _, binding in STAT_ROWS do
		player:GetAttributeChangedSignal(binding.levelAttribute):Connect(function()
			refreshRow(binding)
		end)
	end

	player:GetAttributeChangedSignal("Cash"):Connect(refreshAllRows)
end

local function onPurchaseDelta(payload: unknown): ()
	if type(payload) ~= "table" then
		return
	end

	local delta = payload :: StatUpgradeDelta
	if type(delta.StatName) ~= "string" then
		return
	end

	for _, binding in STAT_ROWS do
		if binding.statName == delta.StatName then
			refreshRow(binding)
			playBuyUpgradeSound()
			break
		end
	end
end

local function initialize(): ()
	bindUpgradesBoothGui(waitForUpgradesBoothGui())

	playerGui.ChildAdded:Connect(function(child: Instance)
		if child.Name == UPGRADES_BOOTH_NAME and child:IsA("ScreenGui") then
			bindUpgradesBoothGui(child)
		end
	end)

	local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME, REMOTE_WAIT_TIMEOUT)
	if remotesFolder == nil then
		warn(`[UpgradesBoothController] Remotes folder not found within {REMOTE_WAIT_TIMEOUT}s`)
		return
	end

	local purchaseRemoteInstance = remotesFolder:WaitForChild(PURCHASE_REMOTE_NAME, REMOTE_WAIT_TIMEOUT)
	if purchaseRemoteInstance and purchaseRemoteInstance:IsA("RemoteEvent") then
		purchaseRemote = purchaseRemoteInstance
		purchaseRemoteInstance.OnClientEvent:Connect(onPurchaseDelta)
	else
		warn(`[UpgradesBoothController] {PURCHASE_REMOTE_NAME} RemoteEvent not found`)
	end

	resolveBuyUpgradeSoundTemplate()
	resolveUiOpenCloseSoundTemplate()
	connectUpgradeNpcPrompts()
	connectLevelAttributeListeners()
	refreshAllRows()
end

initialize()

--[[
	SELF-AUDIT (Section 7):
	- PurchaseStatUpgrade.OnClientEvent:Connect — permanent client-lifetime listener. OK.
	- ProximityPrompt.Triggered:Connect — wired per tagged UpgradeNPC prompt. OK.
	- CollectionService UpgradeNPC added signal:Connect — script-lifetime singleton. OK.
	- Buy / RobuxBuy / CloseButton Activated — wired per UpgradesBooth ScreenGui; Destroying clears refs. OK.
	- Attribute GetAttributeChangedSignal — permanent client-lifetime per stat level attr. OK.
	- BuyUpgrade via SoundPool.play2D — client-only audio on successful purchase delta (GDD 5.5). Ended:Once release inside SoundPool. OK.
]]
