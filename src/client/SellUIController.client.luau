--!strict

local MarketplaceService = game:GetService("MarketplaceService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CashUtil = require(ReplicatedStorage.Shared.CashUtil)
local LootConfig = require(ReplicatedStorage.Shared.LootConfig)
local LootNametagConfig = require(ReplicatedStorage.Shared.LootNametagConfig)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local ProgressionConfig = require(ReplicatedStorage.Shared.ProgressionConfig)
local SoundPool = require(script.Parent.SoundPool)
local UIJuice = require(script.Parent.UIJuice)

-- TODO: replace with real dev product id once SellBoost is created in the Creator Dashboard.
local SELL_BOOST_DEV_PRODUCT_ID = 0

local UI_WAIT_TIMEOUT = 5
local REMOTES_FOLDER_NAME = "Remotes"
local INVENTORY_UPDATED_REMOTE_NAME = "InventoryUpdated"
local SELL_ITEM_REMOTE_NAME = "SellItem"
local SELL_ALL_REMOTE_NAME = "SellAll"
local REMOTE_WAIT_TIMEOUT = 5
local SELL_NPC_TAG = "SellNPC"
local SELL_LOOT_BOOTH_NAME = "SellLootBooth"
local MAIN_CONTENT_NAME = "MainContent"
local TEMPLATES_FOLDER_NAME = "Templates"
local SELL_SCROLL_FRAME_NAME = "SellScrollFrame"
local SELL_ALL_BUTTON_NAME = "SellAllButton"
local SELL_AMOUNT_LABEL_NAME = "SellAmount"
local SELL_X2_ROBUX_BUTTON_NAME = "Sellx2RobuxButton"
local SELL_ITEM_BUTTON_NAME = "SellItemButton"
local CLOSE_BUTTON_NAME = "CloseButton"
local ITEM_TEMPLATE_SUFFIX = "ItemTemplate"
local INVENTORY_ROW_SUFFIX = "Row"
local SELL_ALL_ROW_STAGGER_SECONDS = 0.02
local SELL_ALL_TWEEN_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local SELL_SOUND_PATH = { "Assets", "Sounds", "SellSound" }
local UI_OPEN_CLOSE_SOUND_PATH = { "Assets", "Sounds", "UiOpenClose" }

type InventoryUpdatedPayload = {
	Action: "Add" | "Remove" | "Sync",
	ItemId: string?,
	Items: { string }?,
}

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local localInventory: { string } = {}
local isBoothOpen = false
local activeOpeningPrompt: ProximityPrompt? = nil
local isSellAllAnimating = false

local sellLootBoothGui: ScreenGui? = nil
local sellBoothOuterFrame: Frame? = nil
local sellScrollFrame: ScrollingFrame? = nil
local templatesFolder: Folder? = nil
local sellItemRemote: RemoteEvent? = nil
local sellAllRemote: RemoteEvent? = nil
local sellAmountLabel: TextLabel? = nil
local sellSoundTemplate: Sound? = nil
local uiOpenCloseSoundTemplate: Sound? = nil
local connectedSellNpcPrompts: { [ProximityPrompt]: boolean } = {}
local wiredSellBoothGuis: { [ScreenGui]: boolean } = {}

local function resolveSellSoundTemplate(): Sound?
	if sellSoundTemplate then
		return sellSoundTemplate
	end

	local current: Instance = ReplicatedStorage
	for _, childName in SELL_SOUND_PATH do
		local child = current:WaitForChild(childName, REMOTE_WAIT_TIMEOUT)
		if child == nil then
			warn(`[SellUIController] Sound path missing "{childName}" within {REMOTE_WAIT_TIMEOUT}s`)
			return nil
		end
		current = child
	end

	if not current:IsA("Sound") then
		warn("[SellUIController] SellSound asset is not a Sound")
		return nil
	end

	sellSoundTemplate = current
	return sellSoundTemplate
end

local function resolveUiOpenCloseSoundTemplate(): Sound?
	if uiOpenCloseSoundTemplate then
		return uiOpenCloseSoundTemplate
	end

	local current: Instance = ReplicatedStorage
	for _, childName in UI_OPEN_CLOSE_SOUND_PATH do
		local child = current:WaitForChild(childName, REMOTE_WAIT_TIMEOUT)
		if child == nil then
			warn(`[SellUIController] Sound path missing "{childName}" within {REMOTE_WAIT_TIMEOUT}s`)
			return nil
		end
		current = child
	end

	if not current:IsA("Sound") then
		warn("[SellUIController] UiOpenClose asset is not a Sound")
		return nil
	end

	uiOpenCloseSoundTemplate = current
	return uiOpenCloseSoundTemplate
end

local function playSellSound(): ()
	local template = resolveSellSoundTemplate()
	if template == nil then
		return
	end

	SoundPool.play2D(template)
end

local function findDescendantOfClass<T>(root: Instance, name: string, className: string): T?
	local found = root:FindFirstChild(name, true)
	if found and found:IsA(className) then
		return found :: any
	end

	return nil
end

local function isUnderNamedFolder(instance: Instance, root: Instance, folderName: string): boolean
	local parent = instance.Parent
	while parent and parent ~= root do
		if parent.Name == folderName then
			return true
		end
		parent = parent.Parent
	end

	return false
end

local function findCloseButton(searchRoots: { Instance }): GuiButton?
	for _, root in searchRoots do
		for _, descendant in root:GetDescendants() do
			if descendant.Name == CLOSE_BUTTON_NAME and descendant:IsA("GuiButton") then
				if not isUnderNamedFolder(descendant, root, TEMPLATES_FOLDER_NAME) then
					return descendant
				end
			end
		end
	end

	return nil
end

local function findSellLootBoothGui(root: Instance): ScreenGui?
	local directChild = root:FindFirstChild(SELL_LOOT_BOOTH_NAME)
	if directChild and directChild:IsA("ScreenGui") then
		return directChild
	end

	for _, descendant in root:GetDescendants() do
		if descendant.Name == SELL_LOOT_BOOTH_NAME and descendant:IsA("ScreenGui") then
			return descendant
		end
	end

	return nil
end

local function waitForSellLootBoothGui(): ScreenGui
	while true do
		local existing = findSellLootBoothGui(playerGui)
		if existing then
			return existing
		end

		playerGui.DescendantAdded:Wait()
	end
end

local function ensureTemplatesFolder(mainContent: Instance): Folder?
	local existingTemplates = mainContent:FindFirstChild(TEMPLATES_FOLDER_NAME)
	if existingTemplates and existingTemplates:IsA("Folder") then
		return existingTemplates
	end

	local createdTemplates = Instance.new("Folder")
	createdTemplates.Name = TEMPLATES_FOLDER_NAME
	createdTemplates.Parent = mainContent
	return createdTemplates
end

local function migrateItemTemplatesToFolder(mainContent: Instance, scrollFrame: ScrollingFrame, templates: Folder): ()
	for _, child in scrollFrame:GetChildren() do
		if string.sub(child.Name, -#ITEM_TEMPLATE_SUFFIX) == ITEM_TEMPLATE_SUFFIX then
			child.Parent = templates
		end
	end
end

local function hideInventoryTemplates(): ()
	if templatesFolder == nil then
		return
	end

	for _, child in templatesFolder:GetChildren() do
		if child:IsA("GuiObject") and string.sub(child.Name, -#ITEM_TEMPLATE_SUFFIX) == ITEM_TEMPLATE_SUFFIX then
			child.Visible = false
		end
	end
end

local function getLocalCashMultiplier(): number
	local rebirths = player:GetAttribute("Rebirths")
	if typeof(rebirths) == "number" then
		return ProgressionConfig.GetCashGainMultiplier(rebirths)
	end

	return 1
end

local function formatItemSellPrice(baseSellValue: number): string
	local sellValue = CashUtil.ComputeSellValue(baseSellValue, getLocalCashMultiplier())
	return `${NumberFormatter.Format(sellValue)}`
end

local function calculateTotalSellValue(): number
	local cashMultiplier = getLocalCashMultiplier()
	local total = 0

	for _, itemId in localInventory do
		local itemEntry = LootConfig.GetItem(itemId)
		if itemEntry == nil then
			continue
		end

		total += CashUtil.ComputeSellValue(itemEntry.BaseSellValue, cashMultiplier)
	end

	return total
end

local function updateSellAmountDisplay(): ()
	if sellAmountLabel == nil then
		return
	end

	sellAmountLabel.Text = `${NumberFormatter.Format(calculateTotalSellValue())}`
end

local function getTemplateForRarity(rarity: string): GuiObject?
	if templatesFolder == nil then
		return nil
	end

	local templateName = `{rarity}{ITEM_TEMPLATE_SUFFIX}`
	local template = templatesFolder:FindFirstChild(templateName)
	if template and template:IsA("GuiObject") then
		return template
	end

	warn(`[SellUIController] Missing UI template {templateName}; TODO(GDD 1.5): add template for rarity {rarity}`)
	return nil
end

local function clearRenderedInventoryRows(): ()
	if sellScrollFrame == nil then
		return
	end

	for _, child in sellScrollFrame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function setTextIfPresent(root: Instance, name: string, text: string): ()
	local label = findDescendantOfClass(root, name, "TextLabel")
	if label then
		label.Text = text
	end
end

local function setImageIfPresent(root: Instance, name: string, imageId: string): ()
	local imageLabel = findDescendantOfClass(root, name, "ImageLabel")
	if imageLabel and imageId ~= "" then
		imageLabel.Image = imageId
	end
end

local function bindInventoryRow(clone: Instance, itemEntry: LootConfig.LootItemEntry): ()
	local sellPriceText = formatItemSellPrice(itemEntry.BaseSellValue)

	setTextIfPresent(clone, "ItemName", itemEntry.Name)
	setTextIfPresent(clone, "Name", itemEntry.Name)
	setTextIfPresent(clone, "ItemPrice", sellPriceText)
	setTextIfPresent(clone, "SellValue", sellPriceText)
	setTextIfPresent(clone, "Worth", sellPriceText)
	setImageIfPresent(clone, "ItemImage", itemEntry.IconId)
end

local function wireSellItemButton(clone: Instance, itemId: string): ()
	local sellButton = findDescendantOfClass(clone, SELL_ITEM_BUTTON_NAME, "GuiButton")
	if sellButton == nil or sellItemRemote == nil then
		return
	end

	sellButton.Activated:Connect(function()
		sellItemRemote:FireServer(itemId)
	end)
end

local function renderInventoryRows(): ()
	if sellScrollFrame == nil or isSellAllAnimating then
		return
	end

	clearRenderedInventoryRows()

	for _, itemId in localInventory do
		local itemEntry = LootConfig.GetItem(itemId)
		if itemEntry == nil then
			continue
		end

		local template = getTemplateForRarity(itemEntry.Rarity)
		if template == nil then
			continue
		end

		local clone = template:Clone()
		clone.Name = `{itemId}Row`
		clone.Visible = true
		clone.Parent = sellScrollFrame

		bindInventoryRow(clone, itemEntry)
		wireSellItemButton(clone, itemId)
	end

	updateSellAmountDisplay()
end

local function isInventoryRow(instance: Instance): boolean
	return instance:IsA("GuiObject")
		and string.sub(instance.Name, -#INVENTORY_ROW_SUFFIX) == INVENTORY_ROW_SUFFIX
end

local function collectRenderedInventoryRows(): { GuiObject }
	local rows: { GuiObject } = {}
	if sellScrollFrame == nil then
		return rows
	end

	for _, child in sellScrollFrame:GetChildren() do
		if not child:IsA("GuiObject") then
			continue
		end

		if isInventoryRow(child) then
			table.insert(rows, child)
		end
	end

	if #rows == 0 then
		for _, child in sellScrollFrame:GetChildren() do
			if child:IsA("GuiObject") and not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
				table.insert(rows, child)
			end
		end
	end

	return rows
end

local function animateAndDestroyInventoryRow(row: GuiObject, onFinished: () -> ()): ()
	if row.Parent == nil then
		onFinished()
		return
	end

	row.AnchorPoint = Vector2.new(0.5, 0.5)

	for _, child in row:GetDescendants() do
		if child:IsA("ImageLabel") or child:IsA("ImageButton") then
			TweenService:Create(child, SELL_ALL_TWEEN_INFO, { ImageTransparency = 1 }):Play()
		elseif child:IsA("TextLabel") or child:IsA("TextButton") then
			TweenService:Create(child, SELL_ALL_TWEEN_INFO, { TextTransparency = 1 }):Play()
		elseif child:IsA("UIStroke") then
			TweenService:Create(child, SELL_ALL_TWEEN_INFO, { Transparency = 1 }):Play()
		end
	end

	local rowTween = TweenService:Create(row, SELL_ALL_TWEEN_INFO, {
		Size = UDim2.new(0, 0, 0, 0),
		Rotation = 10,
		BackgroundTransparency = 1,
	})

	rowTween.Completed:Once(function()
		if row.Parent then
			row:Destroy()
		end
		onFinished()
	end)
	rowTween:Play()
end

local function playSellAllRowAnimations(rows: { GuiObject }): ()
	isSellAllAnimating = true

	local remainingAnimations = #rows
	if remainingAnimations == 0 then
		isSellAllAnimating = false
		return
	end

	local function onRowAnimationFinished(): ()
		remainingAnimations -= 1
		if remainingAnimations > 0 then
			return
		end

		isSellAllAnimating = false
		if isBoothOpen then
			renderInventoryRows()
			updateSellAmountDisplay()
		end
	end

	for index, row in rows do
		task.spawn(function()
			if index > 1 then
				task.wait((index - 1) * SELL_ALL_ROW_STAGGER_SECONDS)
			end
			animateAndDestroyInventoryRow(row, onRowAnimationFinished)
		end)
	end
end

local function onSellAllClicked(): ()
	if isSellAllAnimating or sellAllRemote == nil or sellScrollFrame == nil then
		return
	end

	if #localInventory == 0 then
		return
	end

	local rows = collectRenderedInventoryRows()
	if #rows == 0 then
		return
	end

	sellAllRemote:FireServer()
	playSellSound()
	playSellAllRowAnimations(rows)
end

local function applyInventoryDelta(payload: InventoryUpdatedPayload): ()
	if payload.Action == "Sync" then
		table.clear(localInventory)
		if payload.Items then
			for _, itemId in payload.Items do
				table.insert(localInventory, itemId)
			end
		end
	elseif payload.Action == "Add" and payload.ItemId then
		table.insert(localInventory, payload.ItemId)
	elseif payload.Action == "Remove" and payload.ItemId then
		for index, ownedItemId in localInventory do
			if ownedItemId == payload.ItemId then
				table.remove(localInventory, index)
				break
			end
		end

		if isBoothOpen and not isSellAllAnimating then
			playSellSound()
		end
	end

	if isBoothOpen then
		if not isSellAllAnimating then
			renderInventoryRows()
		else
			updateSellAmountDisplay()
		end
	end
end

local function onBoothOpened(): ()
	if not isSellAllAnimating then
		renderInventoryRows()
	else
		updateSellAmountDisplay()
	end
end

local function onBoothClosed(): ()
	isBoothOpen = false
	activeOpeningPrompt = nil
	if sellLootBoothGui then
		sellLootBoothGui.Enabled = false
	end
end

local function closeBooth(): ()
	if sellLootBoothGui == nil or sellBoothOuterFrame == nil then
		return
	end

	UIJuice.RequestCloseMenu(
		sellBoothOuterFrame,
		uiOpenCloseSoundTemplate,
		onBoothClosed,
		sellLootBoothGui.Enabled
	)
end

local function toggleBoothOpen(): ()
	if sellLootBoothGui == nil or sellBoothOuterFrame == nil then
		return
	end

	sellLootBoothGui.Enabled = true
	local isOpen = UIJuice.ToggleMenu(
		sellBoothOuterFrame,
		uiOpenCloseSoundTemplate,
		uiOpenCloseSoundTemplate,
		onBoothClosed
	)
	if isOpen then
		isBoothOpen = true
		onBoothOpened()
	elseif UIJuice.GetMenuPhase(sellBoothOuterFrame) == "closed" then
		onBoothClosed()
	end
end

local function getSellNpcPrompt(taggedPart: Instance): ProximityPrompt?
	-- Expected hierarchy: BasePart [SellNPC tag] > ProximityPrompt
	local proximityPrompt = taggedPart:FindFirstChildWhichIsA("ProximityPrompt")
	if proximityPrompt and proximityPrompt:IsA("ProximityPrompt") then
		return proximityPrompt
	end

	return nil
end

local function registerSellNpc(taggedPart: Instance): ()
	if not CollectionService:HasTag(taggedPart, SELL_NPC_TAG) then
		return
	end

	local proximityPrompt = getSellNpcPrompt(taggedPart)
	if proximityPrompt == nil then
		warn(
			`[SellUIController] ProximityPrompt child not found on tagged {SELL_NPC_TAG} part {taggedPart:GetFullName()}`
		)
		return
	end

	if connectedSellNpcPrompts[proximityPrompt] then
		return
	end

	connectedSellNpcPrompts[proximityPrompt] = true

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

local function connectSellNpcPrompts(): ()
	for _, sellNpc in CollectionService:GetTagged(SELL_NPC_TAG) do
		registerSellNpc(sellNpc)
	end

	CollectionService:GetInstanceAddedSignal(SELL_NPC_TAG):Connect(registerSellNpc)
end

local function wireActionButtons(outerFrame: Frame): ()
	local sellAllButton = findDescendantOfClass(outerFrame, SELL_ALL_BUTTON_NAME, "GuiButton")
	sellAmountLabel = findDescendantOfClass(outerFrame, SELL_AMOUNT_LABEL_NAME, "TextLabel")

	if sellAmountLabel == nil then
		warn(`[SellUIController] {SELL_AMOUNT_LABEL_NAME} TextLabel not found under SellLootBooth`)
	end

	if sellAllButton then
		sellAllButton.Activated:Connect(onSellAllClicked)
	else
		warn(`[SellUIController] {SELL_ALL_BUTTON_NAME} not found under SellLootBooth`)
	end

	local sellBoostButton = findDescendantOfClass(outerFrame, SELL_X2_ROBUX_BUTTON_NAME, "GuiButton")
	if sellBoostButton then
		sellBoostButton.Activated:Connect(function()
			if SELL_BOOST_DEV_PRODUCT_ID <= 0 then
				warn("[SellUIController] SellBoost dev product id is not configured yet")
				return
			end

			MarketplaceService:PromptProductPurchase(player, SELL_BOOST_DEV_PRODUCT_ID)
		end)
	end

	local closeButton = findCloseButton({ outerFrame, sellLootBoothGui :: Instance })
	if closeButton then
		closeButton.Activated:Connect(closeBooth)
	else
		warn(`[SellUIController] {CLOSE_BUTTON_NAME} GuiButton not found under {SELL_LOOT_BOOTH_NAME}`)
	end
end

local function bindSellBoothGui(gui: ScreenGui): ()
	if wiredSellBoothGuis[gui] then
		return
	end

	gui.Enabled = false
	UIJuice.WireMenuButtons(gui, nil)

	local staleBackdrop = gui:FindFirstChild("Backdrop")
	if staleBackdrop then
		staleBackdrop:Destroy()
	end

	local outerFrame = gui:WaitForChild("Frame", UI_WAIT_TIMEOUT)
	local mainContent = if outerFrame then outerFrame:WaitForChild(MAIN_CONTENT_NAME, UI_WAIT_TIMEOUT) else nil
	local scrollFrame = if mainContent then mainContent:WaitForChild(SELL_SCROLL_FRAME_NAME, UI_WAIT_TIMEOUT) else nil

	if outerFrame == nil or mainContent == nil or scrollFrame == nil or not scrollFrame:IsA("ScrollingFrame") then
		warn("[SellUIController] SellLootBooth hierarchy not found")
		return
	end

	wiredSellBoothGuis[gui] = true
	sellLootBoothGui = gui
	sellScrollFrame = scrollFrame
	templatesFolder = ensureTemplatesFolder(mainContent)
	if templatesFolder then
		migrateItemTemplatesToFolder(mainContent, scrollFrame, templatesFolder)
		hideInventoryTemplates()
	end

	if outerFrame:IsA("Frame") then
		sellBoothOuterFrame = outerFrame
		UIJuice.EnsureMenuUIScale(outerFrame)
		UIJuice.EnsureMenuCanvasGroup(outerFrame)
		wireActionButtons(outerFrame)
	end

	gui.Destroying:Once(function()
		wiredSellBoothGuis[gui] = nil
		if sellLootBoothGui == gui then
			sellLootBoothGui = nil
			sellBoothOuterFrame = nil
			sellScrollFrame = nil
			isBoothOpen = false
		end
	end)
end

local function initialize(): ()
	bindSellBoothGui(waitForSellLootBoothGui())

	playerGui.ChildAdded:Connect(function(child: Instance)
		if child.Name == SELL_LOOT_BOOTH_NAME and child:IsA("ScreenGui") then
			bindSellBoothGui(child)
		end
	end)

	local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME, REMOTE_WAIT_TIMEOUT)
	if remotesFolder == nil then
		warn(`[SellUIController] Remotes folder not found within {REMOTE_WAIT_TIMEOUT}s`)
		return
	end

	local inventoryUpdatedRemote = remotesFolder:WaitForChild(INVENTORY_UPDATED_REMOTE_NAME, REMOTE_WAIT_TIMEOUT)
	local sellItemRemoteInstance = remotesFolder:WaitForChild(SELL_ITEM_REMOTE_NAME, REMOTE_WAIT_TIMEOUT)
	local sellAllRemoteInstance = remotesFolder:WaitForChild(SELL_ALL_REMOTE_NAME, REMOTE_WAIT_TIMEOUT)

	if inventoryUpdatedRemote and inventoryUpdatedRemote:IsA("RemoteEvent") then
		inventoryUpdatedRemote.OnClientEvent:Connect(function(payload: InventoryUpdatedPayload)
			applyInventoryDelta(payload)
		end)
	else
		warn(`[SellUIController] {INVENTORY_UPDATED_REMOTE_NAME} RemoteEvent not found`)
	end

	if sellItemRemoteInstance and sellItemRemoteInstance:IsA("RemoteEvent") then
		sellItemRemote = sellItemRemoteInstance
	else
		warn(`[SellUIController] {SELL_ITEM_REMOTE_NAME} RemoteEvent not found`)
	end

	if sellAllRemoteInstance and sellAllRemoteInstance:IsA("RemoteEvent") then
		sellAllRemote = sellAllRemoteInstance
	else
		warn(`[SellUIController] {SELL_ALL_REMOTE_NAME} RemoteEvent not found`)
	end

	resolveSellSoundTemplate()
	resolveUiOpenCloseSoundTemplate()

	connectSellNpcPrompts()

	player:GetAttributeChangedSignal("Rebirths"):Connect(function()
		if not isBoothOpen then
			return
		end

		if isSellAllAnimating then
			updateSellAmountDisplay()
			return
		end

		renderInventoryRows()
	end)
end

initialize()

--[[
	SELF-AUDIT (Section 7):
	- InventoryUpdated.OnClientEvent:Connect — permanent client-lifetime listener. OK.
	- ProximityPrompt.Triggered:Connect — wired per tagged SellNPC prompt via CollectionService. OK.
	- CollectionService SellNPC added signal:Connect — script-lifetime singleton. OK.
	- SellAllButton / Sellx2RobuxButton / CloseButton / SellItemButton Activated connections —
	  wired per SellLootBooth ScreenGui clone; Destroying clears booth refs. OK.
	- PlayerGui.ChildAdded:Connect — re-binds booth after ResetOnSpawn re-clone. OK.
	- template:Clone() for inventory rows — UI list refresh only, not a hot gameplay path. OK.
	- clearRenderedInventoryRows :Destroy() — tears down prior row clones before re-render. OK.
	- SellAllButton Activated — fires SellAllRemote then plays client-only row tweens; server owns grant logic. OK.
	- TweenService row tweens on sell-all — client-only visuals (GDD 5.5 Server is Blind). Completed:Once per row tween. OK.
	- isSellAllAnimating guard — blocks renderInventoryRows mid-animation while inventory mirror still updates from Remove deltas. OK.
	- task.spawn stagger loop for sell-all rows — scoped one-shot delays tied to sell-all click, not a polling loop. OK.
	- player Rebirths attribute changed — re-renders open booth prices only when not animating sell-all. OK.
	- SellAmount TextLabel — updated from local inventory mirror total via updateSellAmountDisplay. OK.
	- SellSound via SoundPool.play2D — client-only audio on single sell Remove and sell-all click (GDD 5.5). Ended:Once release inside SoundPool. OK.
]]
