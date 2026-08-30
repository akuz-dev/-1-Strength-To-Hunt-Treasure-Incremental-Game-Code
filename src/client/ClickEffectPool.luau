--!strict

--[[
	Section 6 pool for click VFX Frame instances (sparks + template effect frames).
	Instance.new/Clone churn is confined to warm-up; runtime play cycles acquire/release.
]]

local SPARK_POOL_SIZE = 24
local EFFECT_FRAME_POOL_SIZE = 8
local STORAGE_FOLDER_NAME = "ClickEffectPoolStorage"
local EFFECT_CONTENT_NAME = "EffectContent"
local EFFECT_SCALE_NAME = "EffectScale"

type PooledFrameEntry = {
	frame: Frame,
	inUse: boolean,
}

local storageFolder = Instance.new("Folder")
storageFolder.Name = STORAGE_FOLDER_NAME
storageFolder.Parent = script

local sparkPool: { PooledFrameEntry } = {}
local effectFramePool: { PooledFrameEntry } = {}
local templateFrame: Frame? = nil
local templateBackgroundTransparency = 0
local initialized = false

local function unwrapLegacyFadeGroup(frame: Frame): ()
	local fadeGroup = frame:FindFirstChild("EffectFade")
	if fadeGroup == nil or not fadeGroup:IsA("CanvasGroup") then
		return
	end

	for _, child in fadeGroup:GetChildren() do
		child.Parent = frame
	end
	fadeGroup:Destroy()
end

local function ensureEffectContent(frame: Frame): Frame
	local existing = frame:FindFirstChild(EFFECT_CONTENT_NAME)
	if existing and existing:IsA("Frame") then
		return existing
	end

	local content = Instance.new("Frame")
	content.Name = EFFECT_CONTENT_NAME
	content.Size = UDim2.fromScale(1, 1)
	content.Position = UDim2.fromScale(0, 0)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Parent = frame

	local childrenToMove: { Instance } = {}
	for _, child in frame:GetChildren() do
		if child ~= content and not child:IsA("UIScale") then
			table.insert(childrenToMove, child)
		end
	end

	for _, child in childrenToMove do
		child.Parent = content
	end

	return content
end

local function ensureEffectScale(frame: Frame): UIScale
	unwrapLegacyFadeGroup(frame)

	local content = ensureEffectContent(frame)

	local uiScale = content:FindFirstChild(EFFECT_SCALE_NAME)
	if uiScale and uiScale:IsA("UIScale") then
		return uiScale
	end

	local legacyScale = frame:FindFirstChild(EFFECT_SCALE_NAME)
	if legacyScale and legacyScale:IsA("UIScale") then
		legacyScale.Parent = content
		return legacyScale
	end

	local created = Instance.new("UIScale")
	created.Name = EFFECT_SCALE_NAME
	created.Scale = 1
	created.Parent = content
	return created
end

local function getEffectScale(frame: Frame): UIScale?
	local content = frame:FindFirstChild(EFFECT_CONTENT_NAME)
	if content and content:IsA("Frame") then
		local named = content:FindFirstChild(EFFECT_SCALE_NAME)
		if named and named:IsA("UIScale") then
			return named
		end
	end

	local legacyNamed = frame:FindFirstChild(EFFECT_SCALE_NAME)
	if legacyNamed and legacyNamed:IsA("UIScale") then
		return legacyNamed
	end

	return frame:FindFirstChildOfClass("UIScale")
end

local function resetSparkFrame(frame: Frame): ()
	frame.Visible = false
	frame.BackgroundTransparency = 0
	frame.Size = UDim2.fromOffset(4, 4)
	frame.ZIndex = 95
	frame.Parent = storageFolder
end

local function resetEffectFrame(frame: Frame): ()
	local uiScale = ensureEffectScale(frame)
	uiScale.Scale = 1

	frame.Visible = false
	frame.BackgroundTransparency = templateBackgroundTransparency
	frame.Parent = storageFolder
end

local function createSparkFrame(): Frame
	local spark = Instance.new("Frame")
	spark.BorderSizePixel = 0
	spark.AnchorPoint = Vector2.new(0.5, 0.5)
	spark.Visible = false
	spark.Parent = storageFolder
	return spark
end

local function createEffectFrame(template: Frame): Frame
	local frame = template:Clone()
	frame.Visible = false
	ensureEffectScale(frame)
	frame.Parent = storageFolder
	return frame
end

local function initialize(template: Frame, _clickGui: ScreenGui): ()
	if initialized then
		return
	end

	templateFrame = template
	templateBackgroundTransparency = template.BackgroundTransparency
	template.Visible = false

	for _ = 1, SPARK_POOL_SIZE do
		local spark = createSparkFrame()
		resetSparkFrame(spark)
		table.insert(sparkPool, {
			frame = spark,
			inUse = false,
		})
	end

	for _ = 1, EFFECT_FRAME_POOL_SIZE do
		local frame = createEffectFrame(template)
		resetEffectFrame(frame)
		table.insert(effectFramePool, {
			frame = frame,
			inUse = false,
		})
	end

	initialized = true
end

local function acquireSpark(): Frame?
	for _, entry in sparkPool do
		if not entry.inUse then
			entry.inUse = true
			return entry.frame
		end
	end

	local spark = createSparkFrame()
	resetSparkFrame(spark)
	local entry: PooledFrameEntry = {
		frame = spark,
		inUse = true,
	}
	table.insert(sparkPool, entry)
	return spark
end

local function acquireEffectFrame(): Frame?
	if not initialized or templateFrame == nil then
		return nil
	end

	for _, entry in effectFramePool do
		if not entry.inUse then
			entry.inUse = true
			ensureEffectScale(entry.frame)
			return entry.frame
		end
	end

	local frame = createEffectFrame(templateFrame)
	local entry: PooledFrameEntry = {
		frame = frame,
		inUse = true,
	}
	table.insert(effectFramePool, entry)
	return frame
end

local function release(frame: Frame): ()
	for _, entry in sparkPool do
		if entry.frame == frame then
			entry.inUse = false
			resetSparkFrame(frame)
			return
		end
	end

	for _, entry in effectFramePool do
		if entry.frame == frame then
			entry.inUse = false
			resetEffectFrame(frame)
			return
		end
	end
end

return {
	initialize = initialize,
	acquireSpark = acquireSpark,
	acquireEffectFrame = acquireEffectFrame,
	getEffectScale = getEffectScale,
	release = release,
}

--[[
	SELF-AUDIT (Section 7):
	- Instance.new("Folder") storage — script-lifetime singleton. OK.
	- Instance.new("Frame") spark/content frames — warm-up + overflow only inside this pool. OK.
	- Instance.new("UIScale") — warm-up/ensure inside this pool only. OK.
	- Legacy EffectFade CanvasGroup:Destroy — one-shot migration on ensure, not hot path. OK.
	- template:Clone() effect frames — warm-up + overflow only inside this pool. OK.
	- acquire/release reset visibility/scale/parent to storageFolder; no :Destroy() on hot path. OK.
]]
