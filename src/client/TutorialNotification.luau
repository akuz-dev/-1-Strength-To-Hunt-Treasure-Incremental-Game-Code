--!strict

--[[
	Persistent tutorial copy on the Studio-authored Notifications ScreenGui.
	Clones Notifications -> Frame once so NotificationToast can keep the template hidden.
]]

local Players = game:GetService("Players")

local NOTIFICATIONS_GUI_NAME = "Notifications"
local TEMPLATE_FRAME_NAME = "Frame"
local DISPLAY_FRAME_NAME = "TutorialNotificationFrame"
local TEXT_LABEL_NAME = "DefaultNotificationText"
local TOAST_STACK_GAP_PX = 8

type TutorialUiRefs = {
	gui: ScreenGui,
	templateFrame: Frame,
	displayFrame: Frame,
	textLabel: TextLabel,
	restBackgroundTransparency: number,
	restTextTransparency: number,
}

local uiRefs: TutorialUiRefs? = nil
local isShowing = false

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

local function waitForNotificationsGui(playerGui: Instance): ScreenGui
	while true do
		local existing = resolveNotificationsGui(playerGui)
		if existing then
			return existing
		end

		playerGui.ChildAdded:Wait()
	end
end

local function resolveTemplateFrame(gui: ScreenGui): Frame?
	local frame = gui:FindFirstChild(TEMPLATE_FRAME_NAME)
	if frame and frame:IsA("Frame") then
		return frame
	end

	return nil
end

local function waitForTemplateFrame(gui: ScreenGui): Frame
	while true do
		local frame = resolveTemplateFrame(gui)
		if frame then
			return frame
		end

		gui.ChildAdded:Wait()
	end
end

local function measureDisplayHeightPx(refs: TutorialUiRefs): number
	local absoluteHeight = refs.displayFrame.AbsoluteSize.Y
	if absoluteHeight > 0 then
		return absoluteHeight
	end

	if refs.displayFrame.Size.Y.Offset > 0 then
		return refs.displayFrame.Size.Y.Offset
	end

	if refs.displayFrame.Size.Y.Scale > 0 then
		local guiHeight = refs.gui.AbsoluteSize.Y
		if guiHeight > 0 then
			return refs.displayFrame.Size.Y.Scale * guiHeight
		end
	end

	return 48
end

local function createDisplayFrame(gui: ScreenGui, templateFrame: Frame): (Frame, TextLabel)
	local displayFrame = templateFrame:Clone()
	displayFrame.Name = DISPLAY_FRAME_NAME
	displayFrame.Visible = false
	displayFrame.Parent = gui

	local textLabel = findTextLabel(displayFrame)
	if textLabel == nil then
		displayFrame:Destroy()
		error("[TutorialNotification] Cloned frame is missing DefaultNotificationText")
	end

	return displayFrame, textLabel
end

local function tryResolveUi(): boolean
	if uiRefs ~= nil then
		return true
	end

	local player = Players.LocalPlayer
	local playerGui = player:FindFirstChild("PlayerGui")
	if playerGui == nil then
		return false
	end

	local gui = resolveNotificationsGui(playerGui)
	if gui == nil then
		return false
	end

	local templateFrame = resolveTemplateFrame(gui)
	if templateFrame == nil then
		return false
	end

	local templateTextLabel = findTextLabel(templateFrame)
	if templateTextLabel == nil then
		return false
	end

	local displayFrame, textLabel = createDisplayFrame(gui, templateFrame)

	uiRefs = {
		gui = gui,
		templateFrame = templateFrame,
		displayFrame = displayFrame,
		textLabel = textLabel,
		restBackgroundTransparency = templateFrame.BackgroundTransparency,
		restTextTransparency = templateTextLabel.TextTransparency,
	}
	return true
end

local function ensureUiReady(): boolean
	if tryResolveUi() then
		return true
	end

	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = waitForNotificationsGui(playerGui)
	local templateFrame = waitForTemplateFrame(gui)
	local templateTextLabel = findTextLabel(templateFrame)
	if templateTextLabel == nil then
		while true do
			templateFrame.ChildAdded:Wait()
			templateTextLabel = findTextLabel(templateFrame)
			if templateTextLabel then
				break
			end
		end
	end

	local displayFrame, textLabel = createDisplayFrame(gui, templateFrame)

	uiRefs = {
		gui = gui,
		templateFrame = templateFrame,
		displayFrame = displayFrame,
		textLabel = textLabel,
		restBackgroundTransparency = templateFrame.BackgroundTransparency,
		restTextTransparency = templateTextLabel.TextTransparency,
	}
	return true
end

local function Show(message: string): ()
	if message == "" then
		return
	end
	if not ensureUiReady() or uiRefs == nil then
		return
	end

	local refs = uiRefs
	refs.gui.Enabled = true
	refs.textLabel.Text = message
	refs.displayFrame.BackgroundTransparency = refs.restBackgroundTransparency
	refs.textLabel.TextTransparency = refs.restTextTransparency
	refs.displayFrame.Visible = true
	isShowing = true
end

local function Hide(): ()
	isShowing = false

	if not tryResolveUi() or uiRefs == nil then
		return
	end

	local refs = uiRefs
	refs.textLabel.Text = ""
	refs.displayFrame.Visible = false
end

local function IsActive(): boolean
	return isShowing
end

local function GetStackOffsetPx(): number
	if not isShowing or not tryResolveUi() or uiRefs == nil then
		return 0
	end

	return measureDisplayHeightPx(uiRefs) + TOAST_STACK_GAP_PX
end

local function WaitForReady(): boolean
	return ensureUiReady()
end

local function Invalidate(): ()
	isShowing = false

	if uiRefs then
		uiRefs.displayFrame:Destroy()
	end

	uiRefs = nil
end

return {
	Show = Show,
	Hide = Hide,
	IsActive = IsActive,
	GetStackOffsetPx = GetStackOffsetPx,
	WaitForReady = WaitForReady,
	Invalidate = Invalidate,
}

--[[
	SELF-AUDIT (Section 7):
	- templateFrame:Clone() once per resolve — not on hot path; displayFrame reused until Invalidate. OK.
	- PlayerGui/Notifications ChildAdded:Wait loops — one-shot during ensureUiReady only. OK.
	- No polling loop; visibility tied to Show/Hide from TutorialClient attribute listeners. OK.
]]
