--!strict

--[[
	Pooled client toast notifications using the Studio-authored Notifications ScreenGui.
	Clone churn is confined to warm-up; runtime Show cycles acquire/release only.
	Duplicate messages merge as "message (xN)"; different messages stack vertically below.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local SoundPool = require(script.Parent.SoundPool)
local TutorialNotification = require(script.Parent.TutorialNotification)

local UI_WAIT_TIMEOUT = 5
local REMOTE_WAIT_TIMEOUT = 5
local NOTIFICATIONS_GUI_NAME = "Notifications"
local TEMPLATE_FRAME_NAME = "Frame"
local TEXT_LABEL_NAME = "DefaultNotificationText"
local STORAGE_FOLDER_NAME = "NotificationToastPoolStorage"
local NEGATIVE_SOUND_PATH = { "Assets", "Sounds", "NegativeNotification" }
local POOL_SIZE = 5
local DEFAULT_DURATION = 2.5
local APPEAR_TIME = 0.25
local DISAPPEAR_TIME = 0.18
local SLIDE_OFFSET_Y = -16
local STACK_GAP_PX = 8

type PooledToastEntry = {
	frame: Frame,
	textLabel: TextLabel,
	inUse: boolean,
	generation: number,
	dismissThread: thread?,
	appearTween: Tween?,
	disappearTween: Tween?,
	restBackgroundTransparency: number,
	restTextTransparency: number,
	baseMessage: string,
	repeatCount: number,
	stackIndex: number,
}

local storageFolder = Instance.new("Folder")
storageFolder.Name = STORAGE_FOLDER_NAME
storageFolder.Parent = script

local toastPool: { PooledToastEntry } = {}
local activeToasts: { PooledToastEntry } = {}
local templateFrame: Frame? = nil
local notificationsGui: ScreenGui? = nil
local templateRestPosition: UDim2 = UDim2.new()
local templateFrameHeightPx = 48
local initialized = false
local initFailed = false
local negativeSoundTemplate: Sound? = nil

local appearTweenInfo = TweenInfo.new(APPEAR_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local disappearTweenInfo = TweenInfo.new(DISAPPEAR_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local function formatToastText(baseMessage: string, repeatCount: number): string
	if repeatCount <= 1 then
		return baseMessage
	end

	return `{baseMessage} (x{repeatCount})`
end

local function resolveNegativeSoundTemplate(): Sound?
	if negativeSoundTemplate then
		return negativeSoundTemplate
	end

	local current: Instance = ReplicatedStorage
	for _, childName in NEGATIVE_SOUND_PATH do
		local child = current:WaitForChild(childName, REMOTE_WAIT_TIMEOUT)
		if child == nil then
			warn("[NotificationToast] NegativeNotification sound not found under ReplicatedStorage")
			return nil
		end
		current = child
	end

	if not current:IsA("Sound") then
		warn("[NotificationToast] NegativeNotification asset is not a Sound")
		return nil
	end

	negativeSoundTemplate = current
	return negativeSoundTemplate
end

local function playNegativeFeedbackSound(): ()
	local template = resolveNegativeSoundTemplate()
	if template == nil then
		return
	end

	SoundPool.play2D(template)
end

local function cancelToastAnimations(entry: PooledToastEntry): ()
	if entry.appearTween then
		entry.appearTween:Cancel()
		entry.appearTween = nil
	end
	if entry.disappearTween then
		entry.disappearTween:Cancel()
		entry.disappearTween = nil
	end
	if entry.dismissThread then
		task.cancel(entry.dismissThread)
		entry.dismissThread = nil
	end
end

local function findTextLabel(frame: Frame): TextLabel?
	local named = frame:FindFirstChild(TEXT_LABEL_NAME)
	if named and named:IsA("TextLabel") then
		return named
	end

	for _, descendant in frame:GetDescendants() do
		if descendant.Name == TEXT_LABEL_NAME and descendant:IsA("TextLabel") then
			return descendant
		end
	end

	return nil
end

local function resolveNotificationsGui(playerGui: Instance): ScreenGui?
	local directChild = playerGui:FindFirstChild(NOTIFICATIONS_GUI_NAME)
	if directChild and directChild:IsA("ScreenGui") then
		return directChild
	end

	for _, descendant in playerGui:GetDescendants() do
		if descendant.Name == NOTIFICATIONS_GUI_NAME and descendant:IsA("ScreenGui") then
			return descendant
		end
	end

	return nil
end

local function waitForNotificationsGui(): ScreenGui?
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local existing = resolveNotificationsGui(playerGui)
	if existing then
		return existing
	end

	local waitedGui = playerGui:WaitForChild(NOTIFICATIONS_GUI_NAME, UI_WAIT_TIMEOUT)
	if waitedGui and waitedGui:IsA("ScreenGui") then
		return waitedGui
	end

	return resolveNotificationsGui(playerGui)
end

local function estimateTemplateFrameHeightPx(template: Frame): number
	local absoluteHeight = template.AbsoluteSize.Y
	if absoluteHeight > 0 then
		return absoluteHeight
	end

	if template.Size.Y.Offset > 0 then
		return template.Size.Y.Offset
	end

	return 48
end

local function measureEntryHeightPx(entry: PooledToastEntry): number
	local frame = entry.frame
	local absoluteHeight = frame.AbsoluteSize.Y
	if absoluteHeight > 0 then
		return absoluteHeight
	end

	if frame.Size.Y.Offset > 0 then
		return frame.Size.Y.Offset
	end

	if frame.Size.Y.Scale > 0 and notificationsGui then
		local guiHeight = notificationsGui.AbsoluteSize.Y
		if guiHeight > 0 then
			return frame.Size.Y.Scale * guiHeight
		end
	end

	return templateFrameHeightPx
end

local function computeStackPositionForEntry(entryIndex: number): UDim2
	local yOffset = templateRestPosition.Y.Offset + TutorialNotification.GetStackOffsetPx()
	for index = 1, entryIndex - 1 do
		local previousEntry = activeToasts[index]
		if previousEntry then
			yOffset += measureEntryHeightPx(previousEntry) + STACK_GAP_PX
		end
	end

	return UDim2.new(
		templateRestPosition.X.Scale,
		templateRestPosition.X.Offset,
		templateRestPosition.Y.Scale,
		yOffset
	)
end

local function applyStackPosition(entry: PooledToastEntry, entryIndex: number, instant: boolean): ()
	entry.stackIndex = entryIndex - 1
	local targetPosition = computeStackPositionForEntry(entryIndex)

	if instant or (entry.appearTween == nil and entry.disappearTween == nil) then
		entry.frame.Position = targetPosition
	else
		TweenService:Create(entry.frame, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = targetPosition,
		}):Play()
	end
end

local function layoutActiveToasts(instant: boolean): ()
	for index, entry in activeToasts do
		applyStackPosition(entry, index, instant)
	end
end

local function createPooledEntry(sourceTemplate: Frame, textLabel: TextLabel): PooledToastEntry
	local frame = sourceTemplate:Clone()
	frame.Visible = false
	frame.Parent = storageFolder

	local cloneTextLabel = findTextLabel(frame)
	if cloneTextLabel == nil then
		warn("[NotificationToast] Cloned toast frame is missing DefaultNotificationText")
		frame:Destroy()
		error("[NotificationToast] Invalid toast template")
	end

	return {
		frame = frame,
		textLabel = cloneTextLabel,
		inUse = false,
		generation = 0,
		dismissThread = nil,
		appearTween = nil,
		disappearTween = nil,
		restBackgroundTransparency = sourceTemplate.BackgroundTransparency,
		restTextTransparency = textLabel.TextTransparency,
		baseMessage = "",
		repeatCount = 0,
		stackIndex = 0,
	}
end

local function removeFromActiveList(entry: PooledToastEntry): ()
	for index, activeEntry in activeToasts do
		if activeEntry == entry then
			table.remove(activeToasts, index)
			return
		end
	end
end

local function findActiveToastByMessage(message: string): PooledToastEntry?
	for _, entry in activeToasts do
		if entry.baseMessage == message then
			return entry
		end
	end

	return nil
end

local function initialize(): boolean
	if initialized then
		return notificationsGui ~= nil and templateFrame ~= nil
	end
	if initFailed then
		return false
	end

	local gui = waitForNotificationsGui()
	if gui == nil then
		warn(`[NotificationToast] {NOTIFICATIONS_GUI_NAME} ScreenGui not found within {UI_WAIT_TIMEOUT}s`)
		initFailed = true
		return false
	end

	local template = gui:FindFirstChild(TEMPLATE_FRAME_NAME)
	if template == nil then
		template = gui:WaitForChild(TEMPLATE_FRAME_NAME, UI_WAIT_TIMEOUT)
	end
	if template == nil or not template:IsA("Frame") then
		warn(`[NotificationToast] Template frame "{TEMPLATE_FRAME_NAME}" not found`)
		initFailed = true
		return false
	end

	local templateTextLabel = findTextLabel(template)
	if templateTextLabel == nil then
		warn(`[NotificationToast] Text label "{TEXT_LABEL_NAME}" not found on template frame`)
		initFailed = true
		return false
	end

	template.Visible = false
	templateRestPosition = template.Position
	templateFrameHeightPx = estimateTemplateFrameHeightPx(template)
	notificationsGui = gui
	templateFrame = template

	for _ = 1, POOL_SIZE do
		table.insert(toastPool, createPooledEntry(template, templateTextLabel))
	end

	initialized = true
	return true
end

local function resetToastEntry(entry: PooledToastEntry): ()
	cancelToastAnimations(entry)

	entry.frame.Position = templateRestPosition
	entry.frame.BackgroundTransparency = entry.restBackgroundTransparency
	entry.textLabel.TextTransparency = entry.restTextTransparency
	entry.frame.Visible = false
	entry.frame.Parent = storageFolder
	entry.inUse = false
	entry.baseMessage = ""
	entry.repeatCount = 0
	entry.stackIndex = 0
end

local function releaseToast(entry: PooledToastEntry): ()
	entry.generation += 1
	removeFromActiveList(entry)
	resetToastEntry(entry)
	layoutActiveToasts(true)
end

local function dismissToast(entry: PooledToastEntry): ()
	if not entry.inUse then
		return
	end

	cancelToastAnimations(entry)
	local generation = entry.generation

	local currentPosition = entry.frame.Position
	local hiddenPosition = UDim2.new(
		currentPosition.X.Scale,
		currentPosition.X.Offset,
		currentPosition.Y.Scale,
		currentPosition.Y.Offset + SLIDE_OFFSET_Y
	)

	local disappearTween = TweenService:Create(entry.frame, disappearTweenInfo, {
		Position = hiddenPosition,
		BackgroundTransparency = 1,
	})
	local textDisappearTween = TweenService:Create(entry.textLabel, disappearTweenInfo, {
		TextTransparency = 1,
	})

	entry.disappearTween = disappearTween
	disappearTween:Play()
	textDisappearTween:Play()

	disappearTween.Completed:Once(function(playbackState: Enum.PlaybackState)
		if playbackState ~= Enum.PlaybackState.Completed then
			return
		end
		if entry.generation ~= generation or not entry.inUse then
			return
		end

		entry.disappearTween = nil
		releaseToast(entry)
	end)
end

local function scheduleDismiss(entry: PooledToastEntry, holdDuration: number, generation: number): ()
	entry.dismissThread = task.delay(holdDuration, function()
		entry.dismissThread = nil
		if entry.generation ~= generation or not entry.inUse then
			return
		end
		dismissToast(entry)
	end)
end

local function acquireToast(): PooledToastEntry?
	if not initialize() or notificationsGui == nil then
		return nil
	end

	for _, entry in toastPool do
		if not entry.inUse then
			entry.inUse = true
			table.insert(activeToasts, entry)
			return entry
		end
	end

	local oldestEntry = activeToasts[1]
	if oldestEntry then
		releaseToast(oldestEntry)
	end

	for _, entry in toastPool do
		if not entry.inUse then
			entry.inUse = true
			table.insert(activeToasts, entry)
			return entry
		end
	end

	return nil
end

local function bumpExistingToast(entry: PooledToastEntry, holdDuration: number): ()
	cancelToastAnimations(entry)
	entry.generation += 1
	local generation = entry.generation

	entry.repeatCount += 1
	entry.textLabel.Text = formatToastText(entry.baseMessage, entry.repeatCount)
	layoutActiveToasts(true)

	scheduleDismiss(entry, holdDuration, generation)
end

local function presentNewToast(entry: PooledToastEntry, message: string, holdDuration: number): ()
	cancelToastAnimations(entry)
	entry.generation += 1
	local generation = entry.generation

	entry.baseMessage = message
	entry.repeatCount = 1
	entry.textLabel.Text = formatToastText(message, 1)

	if notificationsGui then
		entry.frame.Parent = notificationsGui
	end
	entry.frame.Visible = true
	entry.frame.BackgroundTransparency = entry.restBackgroundTransparency
	entry.textLabel.TextTransparency = entry.restTextTransparency

	layoutActiveToasts(true)

	local entryIndex = #activeToasts
	local targetPosition = computeStackPositionForEntry(entryIndex)
	local hiddenPosition = UDim2.new(
		targetPosition.X.Scale,
		targetPosition.X.Offset,
		targetPosition.Y.Scale,
		targetPosition.Y.Offset + SLIDE_OFFSET_Y
	)

	entry.frame.Position = hiddenPosition
	entry.frame.BackgroundTransparency = 1
	entry.textLabel.TextTransparency = 1

	local appearTween = TweenService:Create(entry.frame, appearTweenInfo, {
		Position = targetPosition,
		BackgroundTransparency = entry.restBackgroundTransparency,
	})
	local textAppearTween = TweenService:Create(entry.textLabel, appearTweenInfo, {
		TextTransparency = entry.restTextTransparency,
	})

	entry.appearTween = appearTween
	appearTween:Play()
	textAppearTween:Play()

	appearTween.Completed:Once(function(playbackState: Enum.PlaybackState)
		if playbackState ~= Enum.PlaybackState.Completed then
			return
		end
		if entry.generation ~= generation or not entry.inUse then
			return
		end

		entry.appearTween = nil
		scheduleDismiss(entry, holdDuration, generation)
	end)
end

local function showToast(message: string, duration: number?): ()
	if message == "" then
		return
	end
	if not initialize() then
		return
	end

	local holdDuration = if duration then duration else DEFAULT_DURATION
	local existingEntry = findActiveToastByMessage(message)
	if existingEntry then
		bumpExistingToast(existingEntry, holdDuration)
		return
	end

	local entry = acquireToast()
	if entry == nil then
		return
	end

	presentNewToast(entry, message, holdDuration)
end

local function showNegativeToast(message: string, duration: number?): ()
	playNegativeFeedbackSound()
	showToast(message, duration)
end

return {
	Show = showToast,
	ShowNegative = showNegativeToast,
}

--[[
	SELF-AUDIT (Section 7):
	- Instance.new("Folder") storage — script-lifetime singleton. OK.
	- template:Clone() toast frames — warm-up only inside this pool (POOL_SIZE). OK.
	- acquire/release reset visibility/position/transparency/parent; no :Destroy() on hot path. OK.
	- Tween Completed:Once guarded by entry.generation + entry.inUse. OK.
	- task.delay for hold duration — cancelled in cancelToastAnimations on reuse/dismiss (7.2 C). OK.
	- NegativeNotification via SoundPool.play2D — client-only on ShowNegative (GDD 5.5). OK.
	- activeToasts stack reflow uses measured clone heights — no polling loop. OK.
]]
