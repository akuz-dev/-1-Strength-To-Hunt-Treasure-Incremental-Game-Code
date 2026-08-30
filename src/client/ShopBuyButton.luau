--!strict
--[[
	Buy-button text for shop booths. Only `.Text` is updated at runtime — text color stays as set in Studio.

	Preferred: BuyButton is a TextButton — text is written directly on the button.
	Fallback: ImageButton with a child TextLabel named "Price" (or any TextLabel descendant).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)

export type BuyButtonVisualState = "PurchaseAffordable" | "PurchaseUnaffordable" | "Equip" | "Equipped"

type TextWriteTarget = TextLabel | TextButton

export type ShopBuyButtonModule = {
	formatCashPrice: (amount: number) -> string,
	resolveButtonLabel: (button: GuiButton) -> TextLabel?,
	applyPurchasePrice: (button: GuiButton, price: number, playerCash: number) -> boolean,
	applyEquip: (button: GuiButton) -> boolean,
	applyEquipped: (button: GuiButton) -> boolean,
}

local PRICE_LABEL_NAME = "Price"
local BASE_IMAGE_TRANSPARENCY_ATTRIBUTE = "ShopBuyButtonBaseImageTransparency"
local BASE_BACKGROUND_TRANSPARENCY_ATTRIBUTE = "ShopBuyButtonBaseBackgroundTransparency"

local STYLE = {
	PurchaseAffordable = {
		dimAmount = 0,
		active = true,
		autoButtonColor = true,
	},
	PurchaseUnaffordable = {
		dimAmount = 0.35,
		active = true,
		autoButtonColor = false,
	},
	Equip = {
		dimAmount = 0,
		active = true,
		autoButtonColor = true,
	},
	Equipped = {
		dimAmount = 0.45,
		active = false,
		autoButtonColor = false,
	},
}

local function formatCashPrice(amount: number): string
	return `$` .. NumberFormatter.Format(amount)
end

local function resolveImageButtonLabel(button: GuiButton): TextLabel?
	local named = button:FindFirstChild(PRICE_LABEL_NAME)
	if named and named:IsA("TextLabel") then
		return named
	end

	for _, descendant in button:GetDescendants() do
		if descendant:IsA("TextLabel") then
			return descendant
		end
	end

	return nil
end

local function resolveButtonLabel(button: GuiButton): TextLabel?
	if button:IsA("TextButton") then
		return nil
	end

	return resolveImageButtonLabel(button)
end

local function resolveTextWriteTarget(button: GuiButton): TextWriteTarget?
	if button:IsA("TextButton") then
		return button
	end

	return resolveImageButtonLabel(button)
end

local function getBaseImageTransparency(button: ImageButton): number
	local stored = button:GetAttribute(BASE_IMAGE_TRANSPARENCY_ATTRIBUTE)
	if typeof(stored) == "number" then
		return stored
	end

	local baseTransparency = button.ImageTransparency
	button:SetAttribute(BASE_IMAGE_TRANSPARENCY_ATTRIBUTE, baseTransparency)
	return baseTransparency
end

local function getBaseBackgroundTransparency(button: TextButton): number
	local stored = button:GetAttribute(BASE_BACKGROUND_TRANSPARENCY_ATTRIBUTE)
	if typeof(stored) == "number" then
		return stored
	end

	local baseTransparency = button.BackgroundTransparency
	button:SetAttribute(BASE_BACKGROUND_TRANSPARENCY_ATTRIBUTE, baseTransparency)
	return baseTransparency
end

local function applyVisualState(button: GuiButton, text: string, styleKey: BuyButtonVisualState): boolean
	local textTarget = resolveTextWriteTarget(button)
	if textTarget == nil then
		return false
	end

	local style = STYLE[styleKey]

	textTarget.Text = text

	button.Active = style.active
	if button:IsA("TextButton") then
		button.AutoButtonColor = style.autoButtonColor
		local baseTransparency = getBaseBackgroundTransparency(button)
		button.BackgroundTransparency = math.clamp(baseTransparency + style.dimAmount, 0, 1)
	elseif button:IsA("ImageButton") then
		button.AutoButtonColor = style.autoButtonColor
		local baseTransparency = getBaseImageTransparency(button)
		button.ImageTransparency = math.clamp(baseTransparency + style.dimAmount, 0, 1)
	end

	return true
end

local function applyPurchasePrice(button: GuiButton, price: number, playerCash: number): boolean
	local canAfford = playerCash >= price
	local styleKey: BuyButtonVisualState = if canAfford then "PurchaseAffordable" else "PurchaseUnaffordable"
	return applyVisualState(button, formatCashPrice(price), styleKey)
end

local function applyEquip(button: GuiButton): boolean
	return applyVisualState(button, "Equip", "Equip")
end

local function applyEquipped(button: GuiButton): boolean
	return applyVisualState(button, "Equipped", "Equipped")
end

local ShopBuyButton: ShopBuyButtonModule = {
	formatCashPrice = formatCashPrice,
	resolveButtonLabel = resolveButtonLabel,
	applyPurchasePrice = applyPurchasePrice,
	applyEquip = applyEquip,
	applyEquipped = applyEquipped,
}

return ShopBuyButton
