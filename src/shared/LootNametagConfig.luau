--!strict

export type LootNametagConfigModule = {
	ITEM_NAME_LABEL: string,
	ITEM_RARITY_LABEL: string,
	ITEM_WORTH_LABEL: string,
	RARITY_LABELS_FOLDER: string,
	RARITY_GRADIENT_NAME: string,
	NAMETAG_ANCHOR_NAME: string,
	SUPPORTED_RARITIES: { string },
	formatCashValue: (value: number) -> string,
	applyRarityStyle: (billboard: BillboardGui, rarity: string) -> (),
	resetRarityStyle: (billboard: BillboardGui) -> (),
	resetNametagText: (billboard: BillboardGui) -> (),
}

local ITEM_NAME_LABEL = "ItemName"
local ITEM_RARITY_LABEL = "ItemRarity"
local ITEM_WORTH_LABEL = "ItemWorth"
local RARITY_LABELS_FOLDER = "RarityLabels"
local RARITY_GRADIENT_NAME = "RarityGradient"
local NAMETAG_ANCHOR_NAME = "NametagAnchor"

local SUPPORTED_RARITIES: { string } = {
	"Common",
	"Uncommon",
	"Rare",
	"Epic",
	"Legendary",
	"Mythic",
	"Godly",
	"Divine",
	"Celestial",
	"Secret",
}

local warnedMissingRarities: { [string]: boolean } = {}

local function findTextLabel(parent: Instance, labelName: string): TextLabel?
	local child = parent:FindFirstChild(labelName)
	if child and child:IsA("TextLabel") then
		return child
	end

	return nil
end

local function clearUIGradients(targetLabel: TextLabel): ()
	local existing = targetLabel:GetChildren()
	for _, child in existing do
		if child:IsA("UIGradient") then
			child:Destroy()
		end
	end
end

local function findTemplateUIGradient(templateLabel: TextLabel): UIGradient?
	local direct = templateLabel:FindFirstChildOfClass("UIGradient")
	if direct then
		return direct
	end

	local named = templateLabel:FindFirstChild(RARITY_GRADIENT_NAME)
	if named and named:IsA("UIGradient") then
		return named
	end

	local nested = templateLabel:FindFirstChildWhichIsA("UIGradient", true)
	if nested and nested:IsA("UIGradient") then
		return nested
	end

	return nil
end

local function copyUIGradient(sourceGradient: UIGradient, targetLabel: TextLabel): ()
	-- Remove every UIGradient (including Studio leftovers not named RarityGradient)
	-- so a single cloned gradient is the only one Roblox can apply.
	clearUIGradients(targetLabel)

	local targetGradient = sourceGradient:Clone()
	targetGradient.Name = RARITY_GRADIENT_NAME
	targetGradient.Color = sourceGradient.Color
	targetGradient.Rotation = sourceGradient.Rotation
	targetGradient.Offset = sourceGradient.Offset
	targetGradient.Transparency = sourceGradient.Transparency
	targetGradient.Enabled = sourceGradient.Enabled
	targetGradient.Parent = targetLabel

	targetLabel.TextColor3 = Color3.new(1, 1, 1)
end

local function copyUIStroke(sourceLabel: TextLabel, targetLabel: TextLabel): ()
	local sourceStroke = sourceLabel:FindFirstChildOfClass("UIStroke")
	local targetStroke = targetLabel:FindFirstChildOfClass("UIStroke")

	if sourceStroke == nil then
		if targetStroke then
			targetStroke:Destroy()
		end
		return
	end

	if targetStroke == nil then
		targetStroke = sourceStroke:Clone()
		targetStroke.Parent = targetLabel
	end

	targetStroke.Color = sourceStroke.Color
	targetStroke.Thickness = sourceStroke.Thickness
	targetStroke.Transparency = sourceStroke.Transparency
	targetStroke.ApplyStrokeMode = sourceStroke.ApplyStrokeMode
	targetStroke.LineJoinMode = sourceStroke.LineJoinMode
	targetStroke.Enabled = sourceStroke.Enabled
end

local function formatCashValue(value: number): string
	return `${math.floor(value)}`
end

local function resetRarityStyle(billboard: BillboardGui): ()
	local itemRarity = findTextLabel(billboard, ITEM_RARITY_LABEL)
	if itemRarity == nil then
		return
	end

	itemRarity.Text = ""
	clearUIGradients(itemRarity)

	local stroke = itemRarity:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke:Destroy()
	end
end

local function resetNametagText(billboard: BillboardGui): ()
	local itemName = findTextLabel(billboard, ITEM_NAME_LABEL)
	if itemName then
		itemName.Text = ""
	end

	local itemWorth = findTextLabel(billboard, ITEM_WORTH_LABEL)
	if itemWorth then
		itemWorth.Text = ""
	end

	resetRarityStyle(billboard)
end

local function applyRarityStyle(billboard: BillboardGui, rarity: string): ()
	local itemRarity = findTextLabel(billboard, ITEM_RARITY_LABEL)
	if itemRarity == nil then
		warn("[LootNametagConfig] Missing ItemRarity label on nametag template")
		return
	end

	local rarityLabelsFolder = billboard:FindFirstChild(RARITY_LABELS_FOLDER)
	if rarityLabelsFolder == nil then
		warn("[LootNametagConfig] Missing RarityLabels folder on nametag template")
		itemRarity.Text = rarity
		return
	end

	local templateLabel = rarityLabelsFolder:FindFirstChild(rarity)
	if templateLabel == nil or not templateLabel:IsA("TextLabel") then
		if not warnedMissingRarities[rarity] then
			warnedMissingRarities[rarity] = true
			warn(`[LootNametagConfig] Missing rarity template label "{rarity}" under RarityLabels`)
		end

		itemRarity.Text = rarity
		return
	end

	itemRarity.Text = if templateLabel.Text ~= "" then templateLabel.Text else rarity

	local templateGradient = findTemplateUIGradient(templateLabel)
	if templateGradient then
		copyUIGradient(templateGradient, itemRarity)
	else
		clearUIGradients(itemRarity)
		itemRarity.TextColor3 = templateLabel.TextColor3
	end

	copyUIStroke(templateLabel, itemRarity)
end

local LootNametagConfig: LootNametagConfigModule = {
	ITEM_NAME_LABEL = ITEM_NAME_LABEL,
	ITEM_RARITY_LABEL = ITEM_RARITY_LABEL,
	ITEM_WORTH_LABEL = ITEM_WORTH_LABEL,
	RARITY_LABELS_FOLDER = RARITY_LABELS_FOLDER,
	RARITY_GRADIENT_NAME = RARITY_GRADIENT_NAME,
	NAMETAG_ANCHOR_NAME = NAMETAG_ANCHOR_NAME,
	SUPPORTED_RARITIES = SUPPORTED_RARITIES,
	formatCashValue = formatCashValue,
	applyRarityStyle = applyRarityStyle,
	resetRarityStyle = resetRarityStyle,
	resetNametagText = resetNametagText,
}

return LootNametagConfig
