--!strict

--[[
	Section 6 pool for loot pickup HUD FX (holders, item containers, trails, sparks, rings, orbs, flares, flash).
	Instance.new/Clone churn is confined to warm-up; runtime play cycles acquire/release.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local STORAGE_FOLDER_NAME = "LootPickupFxPoolStorage"
local FLASH_GUI_NAME = "LootPickupFlashOverlay"
local PICKUP_SOUND_NAME = "LootPickup"
local PICKUP_SOUND_ID = "rbxassetid://127056360624218"
local SOUND_ASSETS_PATH = { "Assets", "Sounds" }
local STAR_NAME = "Star"
local SHADOW_NAME = "Shadow"
local ITEM_NAME = "Item"
local VLINE_NAME = "VLine"
local HLINE_NAME = "HLine"
local STROKE_NAME = "Stroke"

local HOLDER_POOL_SIZE = 8
local CONTAINER_POOL_SIZE = 4
local TRAIL_POOL_SIZE = 48
local SPARK_POOL_SIZE = 80
local RING_POOL_SIZE = 12
local ORB_POOL_SIZE = 16
local FLARE_POOL_SIZE = 4
local FLASH_POOL_SIZE = 2

local TEMPLATE_WAIT_TIMEOUT = 5

type PooledGuiEntry = {
	instance: GuiObject,
	inUse: boolean,
	reset: (guiObject: GuiObject) -> (),
}

type LootPickupFxPoolModule = {
	STAR_NAME: string,
	SHADOW_NAME: string,
	ITEM_NAME: string,
	VLINE_NAME: string,
	HLINE_NAME: string,
	STROKE_NAME: string,
	initialize: () -> boolean,
	acquireHolder: () -> Frame?,
	acquireContainer: () -> Frame?,
	acquireTrailSegment: () -> Frame?,
	acquireSpark: () -> Frame?,
	acquireRing: () -> Frame?,
	acquireOrb: () -> Frame?,
	acquireFlareRay: () -> Frame?,
	acquireFlash: () -> Frame?,
	getNamedChild: (parent: Instance, childName: string) -> GuiObject?,
	getStroke: (parent: Instance) -> UIStroke?,
	getPickupSoundTemplate: () -> Sound?,
	release: (guiObject: GuiObject) -> (),
}

local storageFolder = Instance.new("Folder")
storageFolder.Name = STORAGE_FOLDER_NAME
storageFolder.Parent = script

local holderPool: { PooledGuiEntry } = table.create(HOLDER_POOL_SIZE)
local containerPool: { PooledGuiEntry } = table.create(CONTAINER_POOL_SIZE)
local trailPool: { PooledGuiEntry } = table.create(TRAIL_POOL_SIZE)
local sparkPool: { PooledGuiEntry } = table.create(SPARK_POOL_SIZE)
local ringPool: { PooledGuiEntry } = table.create(RING_POOL_SIZE)
local orbPool: { PooledGuiEntry } = table.create(ORB_POOL_SIZE)
local flarePool: { PooledGuiEntry } = table.create(FLARE_POOL_SIZE)
local flashPool: { PooledGuiEntry } = table.create(FLASH_POOL_SIZE)
local entriesByInstance: { [GuiObject]: PooledGuiEntry } = {}

local flashScreenGui: ScreenGui? = nil
local pickupSoundTemplate: Sound? = nil
local initialized = false

local function addCorner(parent: GuiObject, radius: UDim): ()
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = parent
end

local function addStroke(parent: GuiObject, name: string): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Name = name
	stroke.Thickness = 2
	stroke.Parent = parent
	return stroke
end

local function resetHolder(guiObject: GuiObject): ()
	guiObject.Visible = false
	guiObject.Size = UDim2.new(1, 0, 1, 0)
	guiObject.Position = UDim2.fromScale(0, 0)
	guiObject.AnchorPoint = Vector2.new(0, 0)
	guiObject.BackgroundTransparency = 1
	guiObject.ZIndex = 1
	guiObject.Parent = storageFolder
end

local function resetContainer(guiObject: GuiObject): ()
	guiObject.Visible = false
	guiObject.Size = UDim2.new(0, 0, 0, 0)
	guiObject.Position = UDim2.new(0.5, 0, 0.5, 0)
	guiObject.AnchorPoint = Vector2.new(0.5, 0.5)
	guiObject.BackgroundTransparency = 1
	guiObject.Rotation = 0
	guiObject.ZIndex = 10
	guiObject.Parent = storageFolder

	local star = guiObject:FindFirstChild(STAR_NAME)
	if star and star:IsA("ImageLabel") then
		star.ImageTransparency = 0
		star.Rotation = 0
		star.Size = UDim2.new(1.8, 0, 1.8, 0)
		star.ImageColor3 = Color3.new(1, 1, 1)
	end

	local shadow = guiObject:FindFirstChild(SHADOW_NAME)
	if shadow and shadow:IsA("ImageLabel") then
		shadow.ImageTransparency = 0.35
		shadow.Position = UDim2.new(0.5, 4, 0.5, 4)
		shadow.ImageColor3 = Color3.fromRGB(220, 220, 220)
	end

	local item = guiObject:FindFirstChild(ITEM_NAME)
	if item and item:IsA("ImageLabel") then
		item.ImageTransparency = 0
		item.ImageColor3 = Color3.new(1, 1, 1)
	end
end

local function resetTrail(guiObject: GuiObject): ()
	guiObject.Visible = false
	guiObject.Size = UDim2.new(0, 0, 0, 0)
	guiObject.Position = UDim2.fromOffset(0, 0)
	guiObject.Rotation = 0
	guiObject.BackgroundTransparency = 0
	guiObject.BackgroundColor3 = Color3.new(1, 1, 1)
	guiObject.ZIndex = 1
	guiObject.Parent = storageFolder
end

local function resetSpark(guiObject: GuiObject): ()
	guiObject.Visible = false
	guiObject.Size = UDim2.fromOffset(0, 0)
	guiObject.Position = UDim2.fromOffset(0, 0)
	guiObject.Rotation = 0
	guiObject.BackgroundTransparency = 1
	guiObject.ZIndex = 25
	guiObject.Parent = storageFolder

	local vLine = guiObject:FindFirstChild(VLINE_NAME)
	if vLine and vLine:IsA("Frame") then
		vLine.BackgroundTransparency = 0
		vLine.BackgroundColor3 = Color3.new(1, 1, 1)
	end

	local hLine = guiObject:FindFirstChild(HLINE_NAME)
	if hLine and hLine:IsA("Frame") then
		hLine.BackgroundTransparency = 0
		hLine.BackgroundColor3 = Color3.new(1, 1, 1)
	end
end

local function resetRing(guiObject: GuiObject): ()
	guiObject.Visible = false
	guiObject.Size = UDim2.fromOffset(0, 0)
	guiObject.Position = UDim2.fromOffset(0, 0)
	guiObject.BackgroundTransparency = 1
	guiObject.ZIndex = 15
	guiObject.Parent = storageFolder

	local stroke = guiObject:FindFirstChild(STROKE_NAME)
	if stroke and stroke:IsA("UIStroke") then
		stroke.Transparency = 0
		stroke.Thickness = 4
		stroke.Color = Color3.new(1, 1, 1)
	end
end

local function resetOrb(guiObject: GuiObject): ()
	guiObject.Visible = false
	guiObject.Size = UDim2.fromOffset(0, 0)
	guiObject.Position = UDim2.fromOffset(0, 0)
	guiObject.BackgroundTransparency = 0
	guiObject.BackgroundColor3 = Color3.new(1, 1, 1)
	guiObject.ZIndex = 18
	guiObject.Parent = storageFolder

	local stroke = guiObject:FindFirstChild(STROKE_NAME)
	if stroke and stroke:IsA("UIStroke") then
		stroke.Transparency = 0
		stroke.Thickness = 2
		stroke.Color = Color3.new(1, 1, 1)
	end
end

local function resetFlare(guiObject: GuiObject): ()
	guiObject.Visible = false
	guiObject.Size = UDim2.fromOffset(0, 0)
	guiObject.Position = UDim2.fromOffset(0, 0)
	guiObject.Rotation = 0
	guiObject.BackgroundTransparency = 0
	guiObject.BackgroundColor3 = Color3.new(1, 1, 1)
	guiObject.ZIndex = 30
	guiObject.Parent = storageFolder
end

local function resetFlash(guiObject: GuiObject): ()
	guiObject.Visible = false
	guiObject.Size = UDim2.fromScale(1, 1)
	guiObject.Position = UDim2.fromScale(0.5, 0.5)
	guiObject.AnchorPoint = Vector2.new(0.5, 0.5)
	guiObject.BackgroundTransparency = 0.2
	guiObject.BackgroundColor3 = Color3.new(1, 1, 1)
	guiObject.Parent = storageFolder
end

local function trackEntry(pool: { PooledGuiEntry }, instance: GuiObject, reset: (guiObject: GuiObject) -> (), inUse: boolean): PooledGuiEntry
	local entry: PooledGuiEntry = {
		instance = instance,
		inUse = inUse,
		reset = reset,
	}
	table.insert(pool, entry)
	entriesByInstance[instance] = entry
	return entry
end

local function createHolder(): Frame
	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.BorderSizePixel = 0
	holder.BackgroundTransparency = 1
	resetHolder(holder)
	return holder
end

local function createContainer(): Frame
	local container = Instance.new("Frame")
	container.Name = "ItemContainer"
	container.BorderSizePixel = 0
	container.BackgroundTransparency = 1
	container.AnchorPoint = Vector2.new(0.5, 0.5)

	local starImage = Instance.new("ImageLabel")
	starImage.Name = STAR_NAME
	starImage.BackgroundTransparency = 1
	starImage.AnchorPoint = Vector2.new(0.5, 0.5)
	starImage.Position = UDim2.new(0.5, 0, 0.5, 0)
	starImage.Size = UDim2.new(1.8, 0, 1.8, 0)
	starImage.ZIndex = 2
	starImage.Parent = container

	local itemShadow = Instance.new("ImageLabel")
	itemShadow.Name = SHADOW_NAME
	itemShadow.BackgroundTransparency = 1
	itemShadow.AnchorPoint = Vector2.new(0.5, 0.5)
	itemShadow.Position = UDim2.new(0.5, 4, 0.5, 4)
	itemShadow.Size = UDim2.new(1, 0, 1, 0)
	itemShadow.ZIndex = 3
	itemShadow.Parent = container

	local itemImage = Instance.new("ImageLabel")
	itemImage.Name = ITEM_NAME
	itemImage.BackgroundTransparency = 1
	itemImage.AnchorPoint = Vector2.new(0.5, 0.5)
	itemImage.Position = UDim2.new(0.5, 0, 0.5, 0)
	itemImage.Size = UDim2.new(1, 0, 1, 0)
	itemImage.ZIndex = 4
	itemImage.Parent = container

	resetContainer(container)
	return container
end

local function createTrailSegment(): Frame
	local segment = Instance.new("Frame")
	segment.Name = "TrailSegment"
	segment.BorderSizePixel = 0
	segment.AnchorPoint = Vector2.new(0.5, 0.5)
	addCorner(segment, UDim.new(1, 0))
	resetTrail(segment)
	return segment
end

local function createSpark(): Frame
	local sparkFrame = Instance.new("Frame")
	sparkFrame.Name = "Spark"
	sparkFrame.BackgroundTransparency = 1
	sparkFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	sparkFrame.BorderSizePixel = 0

	local vLine = Instance.new("Frame")
	vLine.Name = VLINE_NAME
	vLine.Size = UDim2.new(0.35, 0, 1, 0)
	vLine.Position = UDim2.new(0.5, 0, 0.5, 0)
	vLine.AnchorPoint = Vector2.new(0.5, 0.5)
	vLine.BorderSizePixel = 0
	vLine.Parent = sparkFrame
	addCorner(vLine, UDim.new(1, 0))

	local hLine = Instance.new("Frame")
	hLine.Name = HLINE_NAME
	hLine.Size = UDim2.new(1, 0, 0.35, 0)
	hLine.Position = UDim2.new(0.5, 0, 0.5, 0)
	hLine.AnchorPoint = Vector2.new(0.5, 0.5)
	hLine.BorderSizePixel = 0
	hLine.Parent = sparkFrame
	addCorner(hLine, UDim.new(1, 0))

	resetSpark(sparkFrame)
	return sparkFrame
end

local function createRing(): Frame
	local ring = Instance.new("Frame")
	ring.Name = "ShockwaveRing"
	ring.BackgroundTransparency = 1
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.BorderSizePixel = 0
	addCorner(ring, UDim.new(1, 0))
	addStroke(ring, STROKE_NAME)
	resetRing(ring)
	return ring
end

local function createOrb(): Frame
	local orb = Instance.new("Frame")
	orb.Name = "OrbitOrb"
	orb.AnchorPoint = Vector2.new(0.5, 0.5)
	orb.BorderSizePixel = 0
	addCorner(orb, UDim.new(1, 0))
	addStroke(orb, STROKE_NAME)
	resetOrb(orb)
	return orb
end

local function createFlareRay(): Frame
	local flareRay = Instance.new("Frame")
	flareRay.Name = "FlareRay"
	flareRay.AnchorPoint = Vector2.new(0.5, 0.5)
	flareRay.BorderSizePixel = 0
	addCorner(flareRay, UDim.new(1, 0))
	resetFlare(flareRay)
	return flareRay
end

local function createFlash(): Frame
	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.BorderSizePixel = 0
	resetFlash(flash)
	return flash
end

local function warmPool(pool: { PooledGuiEntry }, count: number, createFn: () -> Frame, reset: (guiObject: GuiObject) -> ()): ()
	for _ = 1, count do
		trackEntry(pool, createFn(), reset, false)
	end
end

local function acquireFromPool(pool: { PooledGuiEntry }, createFn: () -> Frame, reset: (guiObject: GuiObject) -> ()): GuiObject?
	for _, entry in pool do
		if not entry.inUse then
			entry.inUse = true
			return entry.instance
		end
	end

	local instance = createFn()
	reset(instance)
	trackEntry(pool, instance, reset, true)
	return instance
end

local function resolveFlashScreenGui(): ScreenGui?
	local player = Players.LocalPlayer
	if player == nil then
		return nil
	end

	local playerGui = player:WaitForChild("PlayerGui", TEMPLATE_WAIT_TIMEOUT)
	if playerGui == nil or not playerGui:IsA("PlayerGui") then
		warn("[LootPickupFxPool] PlayerGui not found within timeout")
		return nil
	end

	local existing = playerGui:FindFirstChild(FLASH_GUI_NAME)
	if existing and existing:IsA("ScreenGui") then
		return existing
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = FLASH_GUI_NAME
	screenGui.DisplayOrder = 999999
	screenGui.IgnoreGuiInset = true
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui
	return screenGui
end

local function resolvePickupSoundTemplate(): Sound
	if pickupSoundTemplate then
		return pickupSoundTemplate
	end

	local current: Instance = ReplicatedStorage
	local foundExisting = true
	for _, childName in SOUND_ASSETS_PATH do
		local child = current:FindFirstChild(childName)
		if child == nil then
			foundExisting = false
			break
		end
		current = child
	end

	if foundExisting then
		local existing = current:FindFirstChild(PICKUP_SOUND_NAME)
		if existing and existing:IsA("Sound") then
			pickupSoundTemplate = existing
			return existing
		end
	end

	local sound = Instance.new("Sound")
	sound.Name = PICKUP_SOUND_NAME
	sound.SoundId = PICKUP_SOUND_ID
	sound.Volume = 0.5
	sound.Parent = storageFolder
	pickupSoundTemplate = sound
	return sound
end

local function initialize(): boolean
	if initialized then
		return true
	end

	warmPool(holderPool, HOLDER_POOL_SIZE, createHolder, resetHolder)
	warmPool(containerPool, CONTAINER_POOL_SIZE, createContainer, resetContainer)
	warmPool(trailPool, TRAIL_POOL_SIZE, createTrailSegment, resetTrail)
	warmPool(sparkPool, SPARK_POOL_SIZE, createSpark, resetSpark)
	warmPool(ringPool, RING_POOL_SIZE, createRing, resetRing)
	warmPool(orbPool, ORB_POOL_SIZE, createOrb, resetOrb)
	warmPool(flarePool, FLARE_POOL_SIZE, createFlareRay, resetFlare)
	warmPool(flashPool, FLASH_POOL_SIZE, createFlash, resetFlash)

	flashScreenGui = resolveFlashScreenGui()
	resolvePickupSoundTemplate()
	initialized = true
	return true
end

local function acquireHolder(): Frame?
	local instance = acquireFromPool(holderPool, createHolder, resetHolder)
	if instance and instance:IsA("Frame") then
		return instance
	end
	return nil
end

local function acquireContainer(): Frame?
	local instance = acquireFromPool(containerPool, createContainer, resetContainer)
	if instance and instance:IsA("Frame") then
		return instance
	end
	return nil
end

local function acquireTrailSegment(): Frame?
	local instance = acquireFromPool(trailPool, createTrailSegment, resetTrail)
	if instance and instance:IsA("Frame") then
		return instance
	end
	return nil
end

local function acquireSpark(): Frame?
	local instance = acquireFromPool(sparkPool, createSpark, resetSpark)
	if instance and instance:IsA("Frame") then
		return instance
	end
	return nil
end

local function acquireRing(): Frame?
	local instance = acquireFromPool(ringPool, createRing, resetRing)
	if instance and instance:IsA("Frame") then
		return instance
	end
	return nil
end

local function acquireOrb(): Frame?
	local instance = acquireFromPool(orbPool, createOrb, resetOrb)
	if instance and instance:IsA("Frame") then
		return instance
	end
	return nil
end

local function acquireFlareRay(): Frame?
	local instance = acquireFromPool(flarePool, createFlareRay, resetFlare)
	if instance and instance:IsA("Frame") then
		return instance
	end
	return nil
end

local function acquireFlash(): Frame?
	local instance = acquireFromPool(flashPool, createFlash, resetFlash)
	if instance and instance:IsA("Frame") then
		if flashScreenGui then
			instance.Parent = flashScreenGui
		end
		return instance
	end
	return nil
end

local function getNamedChild(parent: Instance, childName: string): GuiObject?
	local child = parent:FindFirstChild(childName)
	if child and child:IsA("GuiObject") then
		return child
	end
	return nil
end

local function getStroke(parent: Instance): UIStroke?
	local child = parent:FindFirstChild(STROKE_NAME)
	if child and child:IsA("UIStroke") then
		return child
	end
	return nil
end

local function getPickupSoundTemplate(): Sound?
	if not initialized then
		initialize()
	end
	return pickupSoundTemplate
end

local function release(guiObject: GuiObject): ()
	local entry = entriesByInstance[guiObject]
	if entry == nil or not entry.inUse then
		return
	end

	entry.inUse = false
	guiObject:SetAttribute("PlaybackId", nil)
	entry.reset(guiObject)
end

local LootPickupFxPool: LootPickupFxPoolModule = {
	STAR_NAME = STAR_NAME,
	SHADOW_NAME = SHADOW_NAME,
	ITEM_NAME = ITEM_NAME,
	VLINE_NAME = VLINE_NAME,
	HLINE_NAME = HLINE_NAME,
	STROKE_NAME = STROKE_NAME,
	initialize = initialize,
	acquireHolder = acquireHolder,
	acquireContainer = acquireContainer,
	acquireTrailSegment = acquireTrailSegment,
	acquireSpark = acquireSpark,
	acquireRing = acquireRing,
	acquireOrb = acquireOrb,
	acquireFlareRay = acquireFlareRay,
	acquireFlash = acquireFlash,
	getNamedChild = getNamedChild,
	getStroke = getStroke,
	getPickupSoundTemplate = getPickupSoundTemplate,
	release = release,
}

return LootPickupFxPool

--[[
	SELF-AUDIT (Section 7):
	- Instance.new("Folder") storage — script-lifetime singleton. OK.
	- Instance.new("ScreenGui") flash overlay — once in resolveFlashScreenGui at initialize. OK.
	- Instance.new("Sound") pickup template — once in resolvePickupSoundTemplate if ReplicatedStorage.Assets.Sounds.LootPickup is missing. OK.
	- Instance.new Frame/ImageLabel/UICorner/UIStroke — warm-up + overflow only inside this pool
	  (holders, containers, trail segments, sparks, rings, orbs, flare rays, flash). OK.
	- acquire/release reset visibility/parent to storageFolder; SetAttribute("PlaybackId", nil) on release; no :Destroy() on hot path. OK.
	- Players.LocalPlayer:WaitForChild("PlayerGui") — one-shot during initialize, not a connection. OK.
	- No :Connect(), task.spawn, task.delay, or task.defer in this module. OK.
]]
