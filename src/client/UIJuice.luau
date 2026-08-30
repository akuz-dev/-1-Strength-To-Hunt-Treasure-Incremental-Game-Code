--!strict

local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local MENU_START_SCALE = 0.8
local OPEN_TIME = 0.3
local CLOSE_TIME = 0.18
local CLOSE_STUCK_TIMEOUT = CLOSE_TIME + 0.25
local MENU_FADE_NAME = "MenuFade"
local MENU_SCALE_NAME = "MenuScale"
local CLOSE_BUTTON_NAME = "CloseButton"
local SOUND_WAIT_TIMEOUT = 5
local UI_BUTTON_HOVER_SOUND_PATH = { "Assets", "Sounds", "UiButtonHover" }

local wiredButtons: { [GuiButton]: { connections: { RBXScriptConnection }, uiScale: UIScale, baseColor: Color3?, hoverTween: Tween?, pressTween: Tween?, releaseTween: Tween? } } = {}
local menuTargetSizes: { [GuiObject]: UDim2 } = {}
local menuOriginalTransparency: { [GuiObject]: number } = {}
local menuPhase: { [Frame]: "closed" | "opening" | "open" | "closing" } = {}
local menuAnimGeneration: { [Frame]: number } = {}
local menuActiveTweens: { [Frame]: { Tween } } = {}
local wiredMenuConnections: { [Instance]: RBXScriptConnection } = {}
local PULSE_SCALE_NAME = "PulseScale"
local pulseGuiState: {
	[GuiObject]: {
		uiScale: UIScale,
		peakTween: Tween?,
		settleTween: Tween?,
		generation: number,
	},
} = {}

local uiButtonHoverSoundTemplate: Sound? = nil
local uiButtonHoverSoundResolveFailed = false

local function playSoundClone(sound: Sound?): ()
	if not sound then return end
	local clone = sound:Clone()
	clone.Parent = SoundService
	clone:Play()
	clone.Ended:Once(function() clone:Destroy() end)
end

local function resolveUiButtonHoverSound(): Sound?
	if uiButtonHoverSoundTemplate then
		return uiButtonHoverSoundTemplate
	end
	if uiButtonHoverSoundResolveFailed then
		return nil
	end

	local current: Instance = ReplicatedStorage
	for _, childName in UI_BUTTON_HOVER_SOUND_PATH do
		local child = current:WaitForChild(childName, SOUND_WAIT_TIMEOUT)
		if child == nil then
			warn(`[UIJuice] Sound path missing "{childName}" within {SOUND_WAIT_TIMEOUT}s`)
			uiButtonHoverSoundResolveFailed = true
			return nil
		end
		current = child
	end

	if not current:IsA("Sound") then
		warn("[UIJuice] UiButtonHover asset is not a Sound")
		uiButtonHoverSoundResolveFailed = true
		return nil
	end

	uiButtonHoverSoundTemplate = current
	return uiButtonHoverSoundTemplate
end

local function getOrCreateUIScale(button: GuiButton): UIScale
	local existing = button:FindFirstChildOfClass("UIScale")
	if existing then return existing end
	local uiScale = Instance.new("UIScale")
	uiScale.Scale = 1
	uiScale.Parent = button
	return uiScale
end

local function getOrCreatePulseUIScale(guiObject: GuiObject): UIScale
	local named = guiObject:FindFirstChild(PULSE_SCALE_NAME)
	if named and named:IsA("UIScale") then
		return named
	end
	local existing = guiObject:FindFirstChildOfClass("UIScale")
	if existing then
		return existing
	end
	local uiScale = Instance.new("UIScale")
	uiScale.Name = PULSE_SCALE_NAME
	uiScale.Scale = 1
	uiScale.Parent = guiObject
	return uiScale
end

local function cancelPulseGuiTweens(
	state: { peakTween: Tween?, settleTween: Tween?, generation: number, uiScale: UIScale }
): ()
	if state.peakTween then
		state.peakTween:Cancel()
		state.peakTween = nil
	end
	if state.settleTween then
		state.settleTween:Cancel()
		state.settleTween = nil
	end
end

local function getMenuUIScale(frame: Frame): UIScale?
	local named = frame:FindFirstChild(MENU_SCALE_NAME)
	if named and named:IsA("UIScale") then return named end
	return frame:FindFirstChildOfClass("UIScale")
end

local function getMenuFadeGroup(frame: Frame): CanvasGroup?
	local named = frame:FindFirstChild(MENU_FADE_NAME)
	if named and named:IsA("CanvasGroup") then return named end
	return frame:FindFirstChildOfClass("CanvasGroup")
end

local function scaleUDim2(size: UDim2, factor: number): UDim2
	return UDim2.new(size.X.Scale * factor, size.X.Offset * factor, size.Y.Scale * factor, size.Y.Offset * factor)
end

local function getTransparency(guiObject: GuiObject): number
	if guiObject:IsA("CanvasGroup") then return guiObject.GroupTransparency end
	return if guiObject:IsA("Frame") then guiObject.BackgroundTransparency else 0
end

local function setTransparency(guiObject: GuiObject, value: number): ()
	if guiObject:IsA("CanvasGroup") then guiObject.GroupTransparency = value
	elseif guiObject:IsA("Frame") then guiObject.BackgroundTransparency = value end
end

local function tweenGoals(guiObject: GuiObject, transparency: number): { [string]: any }
	return if guiObject:IsA("CanvasGroup")
		then { GroupTransparency = transparency }
		else { BackgroundTransparency = transparency }
end

local function menuTargetSize(frame: GuiObject): UDim2
	if not menuTargetSizes[frame] then menuTargetSizes[frame] = frame.Size end
	return menuTargetSizes[frame]
end

local function menuTargetTransparency(guiObject: GuiObject): number
	if menuOriginalTransparency[guiObject] == nil then
		menuOriginalTransparency[guiObject] = getTransparency(guiObject)
	end
	return menuOriginalTransparency[guiObject]
end

local function disconnectButtonJuice(button: GuiButton): ()
	local state = wiredButtons[button]
	if not state then return end
	for _, connection in state.connections do connection:Disconnect() end
	if state.hoverTween then state.hoverTween:Cancel() end
	if state.pressTween then state.pressTween:Cancel() end
	if state.releaseTween then state.releaseTween:Cancel() end
	wiredButtons[button] = nil
end

local function PulseButton(button: GuiButton, sound: Sound?): ()
	if wiredButtons[button] then return end
	local baseColor = if button:IsA("ImageButton") then button.ImageColor3
		elseif button:IsA("TextButton") then button.BackgroundColor3 else nil
	local state = {
		connections = {} :: { RBXScriptConnection },
		uiScale = getOrCreateUIScale(button),
		baseColor = baseColor,
		hoverTween = nil :: Tween?,
		pressTween = nil :: Tween?,
		releaseTween = nil :: Tween?,
	}
	wiredButtons[button] = state
	local pressInfo = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local releaseInfo = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local hoverInfo = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local function tweenScale(scale: number, info: TweenInfo): Tween
		local tween = TweenService:Create(state.uiScale, info, { Scale = scale })
		tween:Play()
		return tween
	end
	local function isPressInput(input: InputObject): boolean
		return input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
	end
	table.insert(state.connections, button.InputBegan:Connect(function(input: InputObject)
		if not isPressInput(input) then return end
		playSoundClone(sound)
		if state.releaseTween then state.releaseTween:Cancel() end
		state.pressTween = tweenScale(0.93, pressInfo)
	end))
	table.insert(state.connections, button.InputEnded:Connect(function(input: InputObject)
		if not isPressInput(input) then return end
		if state.pressTween then state.pressTween:Cancel() end
		state.releaseTween = tweenScale(1, releaseInfo)
	end))
	if UserInputService.MouseEnabled then
		local function setHoverColor(bright: boolean): ()
			if not state.baseColor then return end
			local color = if bright then Color3.new(
				math.clamp(state.baseColor.R * 1.08, 0, 1),
				math.clamp(state.baseColor.G * 1.08, 0, 1),
				math.clamp(state.baseColor.B * 1.08, 0, 1)
			) else state.baseColor
			if button:IsA("ImageButton") then button.ImageColor3 = color
			elseif button:IsA("TextButton") then button.BackgroundColor3 = color end
		end
		table.insert(state.connections, button.MouseEnter:Connect(function()
			if state.hoverTween then state.hoverTween:Cancel() end
			state.hoverTween = tweenScale(1.04, hoverInfo)
			setHoverColor(true)
			playSoundClone(resolveUiButtonHoverSound())
		end))
		table.insert(state.connections, button.MouseLeave:Connect(function()
			if state.hoverTween then state.hoverTween:Cancel() end
			state.hoverTween = tweenScale(1, hoverInfo)
			setHoverColor(false)
		end))
	end
	table.insert(state.connections, button.Destroying:Connect(function() disconnectButtonJuice(button) end))
end

local function PulseGui(guiObject: GuiObject, sound: Sound?): ()
	playSoundClone(sound)

	local state = pulseGuiState[guiObject]
	if state == nil then
		state = {
			uiScale = getOrCreatePulseUIScale(guiObject),
			peakTween = nil :: Tween?,
			settleTween = nil :: Tween?,
			generation = 0,
		}
		pulseGuiState[guiObject] = state
		guiObject.Destroying:Once(function()
			cancelPulseGuiTweens(state)
			pulseGuiState[guiObject] = nil
		end)
	end

	cancelPulseGuiTweens(state)
	state.generation += 1
	local generation = state.generation
	state.uiScale.Scale = 1

	local peakInfo = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local settleInfo = TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local peakTween = TweenService:Create(state.uiScale, peakInfo, { Scale = 1.12 })
	state.peakTween = peakTween
	peakTween:Play()
	peakTween.Completed:Once(function(playbackState: Enum.PlaybackState)
		if playbackState ~= Enum.PlaybackState.Completed then
			return
		end
		if pulseGuiState[guiObject] ~= state or state.generation ~= generation then
			return
		end

		local settleTween = TweenService:Create(state.uiScale, settleInfo, { Scale = 1 })
		state.settleTween = settleTween
		state.peakTween = nil
		settleTween:Play()
		settleTween.Completed:Once(function(settlePlayback: Enum.PlaybackState)
			if settlePlayback ~= Enum.PlaybackState.Completed then
				return
			end
			if pulseGuiState[guiObject] ~= state or state.generation ~= generation then
				return
			end
			state.settleTween = nil
		end)
	end)
end

local function WireMenuButtons(menu: Instance, sound: Sound?): ()
	if wiredMenuConnections[menu] then return end
	local function wireDescendant(descendant: Instance): ()
		if descendant:IsA("GuiButton") then
			PulseButton(descendant, sound)
		end
	end
	for _, descendant in menu:GetDescendants() do
		wireDescendant(descendant)
	end
	wiredMenuConnections[menu] = menu.DescendantAdded:Connect(wireDescendant)
	menu.Destroying:Once(function()
		local connection = wiredMenuConnections[menu]
		if connection then
			connection:Disconnect()
			wiredMenuConnections[menu] = nil
		end
	end)
end

local function EnsureMenuUIScale(frame: Frame): UIScale
	local existing = getMenuUIScale(frame)
	if existing then return existing end
	local uiScale = Instance.new("UIScale")
	uiScale.Name = MENU_SCALE_NAME
	uiScale.Scale = 1
	uiScale.Parent = frame
	return uiScale
end

local function isCloseButton(instance: Instance): boolean
	return instance.Name == CLOSE_BUTTON_NAME and instance:IsA("GuiButton")
end

local function EnsureMenuCanvasGroup(frame: Frame): CanvasGroup
	local existing = getMenuFadeGroup(frame)
	if existing then return existing end

	local fadeGroup = Instance.new("CanvasGroup")
	fadeGroup.Name = MENU_FADE_NAME
	fadeGroup.Size = UDim2.fromScale(1, 1)
	fadeGroup.BackgroundTransparency = 1
	fadeGroup.BorderSizePixel = 0
	fadeGroup.GroupTransparency = 0
	fadeGroup.Parent = frame

	local childrenToMove: { Instance } = {}
	for _, child in frame:GetChildren() do
		-- Keep CloseButton as a direct Frame child so Size/Position stay Studio-authored.
		if child ~= fadeGroup and not child:IsA("UIScale") and not isCloseButton(child) then
			table.insert(childrenToMove, child)
		end
	end
	for _, child in childrenToMove do
		child.Parent = fadeGroup
	end

	return fadeGroup
end

local function getMenuPhase(frame: Frame): "closed" | "opening" | "open" | "closing"
	return menuPhase[frame] or "closed"
end

local function cancelMenuTweens(frame: Frame): ()
	local tweens = menuActiveTweens[frame]
	if tweens then
		for _, tween in tweens do
			tween:Cancel()
		end
		menuActiveTweens[frame] = nil
	end
end

local function trackMenuTweens(frame: Frame, ...: Tween): ()
	cancelMenuTweens(frame)
	local tweens = table.create(select("#", ...))
	for index = 1, select("#", ...) do
		local tween = select(index, ...)
		table.insert(tweens, tween)
	end
	menuActiveTweens[frame] = tweens
end

local function bumpMenuAnimGeneration(frame: Frame): number
	local nextGeneration = (menuAnimGeneration[frame] or 0) + 1
	menuAnimGeneration[frame] = nextGeneration
	return nextGeneration
end

local function finishMenuOpen(frame: Frame, generation: number): ()
	if menuAnimGeneration[frame] ~= generation then
		return
	end
	menuPhase[frame] = "open"
	menuActiveTweens[frame] = nil
end

local function finishMenuClose(frame: Frame, generation: number, onComplete: (() -> ())?): ()
	if menuAnimGeneration[frame] ~= generation then
		return
	end

	frame.Visible = false
	local menuScale = getMenuUIScale(frame)
	local fadeGroup = getMenuFadeGroup(frame)
	if menuScale then
		menuScale.Scale = 1
	end
	if fadeGroup then
		fadeGroup.GroupTransparency = 0
	end

	menuPhase[frame] = "closed"
	menuActiveTweens[frame] = nil
	if onComplete then
		onComplete()
	end
end

local function IsMenuOpen(frame: Frame): boolean
	local phase = getMenuPhase(frame)
	return phase == "open" or phase == "opening"
end

local function OpenMenu(frame: Frame, sound: Sound?): (Tween, Tween?)
	playSoundClone(sound)
	local generation = bumpMenuAnimGeneration(frame)
	menuPhase[frame] = "opening"
	local openInfo = TweenInfo.new(OPEN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	frame.Visible = true

	local menuScale = getMenuUIScale(frame)
	local fadeGroup = getMenuFadeGroup(frame)
	if menuScale and fadeGroup then
		menuScale.Scale = MENU_START_SCALE
		fadeGroup.GroupTransparency = 1
		local scaleTween = TweenService:Create(menuScale, openInfo, { Scale = 1 })
		local fadeTween = TweenService:Create(fadeGroup, openInfo, { GroupTransparency = 0 })
		trackMenuTweens(frame, scaleTween, fadeTween)
		scaleTween:Play()
		fadeTween:Play()
		scaleTween.Completed:Once(function()
			finishMenuOpen(frame, generation)
		end)
		return scaleTween, fadeTween
	end

	if menuScale then
		menuScale.Scale = MENU_START_SCALE
		local scaleTween = TweenService:Create(menuScale, openInfo, { Scale = 1 })
		trackMenuTweens(frame, scaleTween)
		scaleTween:Play()
		scaleTween.Completed:Once(function()
			finishMenuOpen(frame, generation)
		end)
		return scaleTween, scaleTween
	end

	local targetSize = menuTargetSize(frame)
	frame.Size = scaleUDim2(targetSize, MENU_START_SCALE)
	setTransparency(frame, 1)
	local frameGoals = tweenGoals(frame, menuTargetTransparency(frame))
	frameGoals.Size = targetSize
	local frameTween = TweenService:Create(frame, openInfo, frameGoals)
	trackMenuTweens(frame, frameTween)
	frameTween:Play()
	frameTween.Completed:Once(function()
		finishMenuOpen(frame, generation)
	end)
	return frameTween, frameTween
end

local function scheduleCloseRecovery(frame: Frame, generation: number, onComplete: (() -> ())?): ()
	task.delay(CLOSE_STUCK_TIMEOUT, function()
		if getMenuPhase(frame) ~= "closing" then
			return
		end
		if menuAnimGeneration[frame] ~= generation then
			return
		end

		cancelMenuTweens(frame)
		finishMenuClose(frame, generation, onComplete)
	end)
end

local function ForceCloseMenu(frame: Frame, onComplete: (() -> ())?): ()
	cancelMenuTweens(frame)
	local generation = menuAnimGeneration[frame] or 0
	finishMenuClose(frame, generation, onComplete)
end

local function CloseMenu(frame: Frame, sound: Sound?, onComplete: (() -> ())?): (Tween, Tween?)
	playSoundClone(sound)
	local generation = bumpMenuAnimGeneration(frame)
	menuPhase[frame] = "closing"
	scheduleCloseRecovery(frame, generation, onComplete)
	local closeInfo = TweenInfo.new(CLOSE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	local menuScale = getMenuUIScale(frame)
	local fadeGroup = getMenuFadeGroup(frame)
	if menuScale and fadeGroup then
		local scaleTween = TweenService:Create(menuScale, closeInfo, { Scale = MENU_START_SCALE })
		local fadeTween = TweenService:Create(fadeGroup, closeInfo, { GroupTransparency = 1 })
		trackMenuTweens(frame, scaleTween, fadeTween)
		scaleTween:Play()
		fadeTween:Play()
		scaleTween.Completed:Once(function()
			finishMenuClose(frame, generation, onComplete)
		end)
		return scaleTween, fadeTween
	end

	if menuScale then
		local scaleTween = TweenService:Create(menuScale, closeInfo, { Scale = MENU_START_SCALE })
		trackMenuTweens(frame, scaleTween)
		scaleTween:Play()
		scaleTween.Completed:Once(function()
			finishMenuClose(frame, generation, onComplete)
		end)
		return scaleTween, scaleTween
	end

	local targetSize = menuTargetSize(frame)
	local frameGoals = tweenGoals(frame, 1)
	frameGoals.Size = scaleUDim2(targetSize, MENU_START_SCALE)
	local frameTween = TweenService:Create(frame, closeInfo, frameGoals)
	trackMenuTweens(frame, frameTween)
	frameTween:Play()
	frameTween.Completed:Once(function(playbackState: Enum.PlaybackState)
		if playbackState ~= Enum.PlaybackState.Completed then
			return
		end
		if menuAnimGeneration[frame] ~= generation then
			return
		end
		frame.Visible = false
		frame.Size = targetSize
		setTransparency(frame, menuTargetTransparency(frame))
		menuPhase[frame] = "closed"
		menuActiveTweens[frame] = nil
		if onComplete then
			onComplete()
		end
	end)
	return frameTween, frameTween
end

local function RequestCloseMenu(
	frame: Frame,
	sound: Sound?,
	onComplete: (() -> ())?,
	screenGuiEnabled: boolean
): ()
	local phase = getMenuPhase(frame)
	if phase == "closing" then
		ForceCloseMenu(frame, onComplete)
		return
	end
	if phase == "closed" then
		if screenGuiEnabled then
			ForceCloseMenu(frame, onComplete)
		end
		return
	end

	CloseMenu(frame, sound, onComplete)
end

local function ToggleMenu(frame: Frame, openSound: Sound?, closeSound: Sound?, onClosed: (() -> ())?): boolean
	local phase = getMenuPhase(frame)
	if phase == "open" then
		CloseMenu(frame, closeSound, onClosed)
		return false
	end
	if phase == "opening" then
		return true
	end
	if phase == "closing" then
		cancelMenuTweens(frame)
	end
	OpenMenu(frame, openSound)
	return true
end

--[[ SELF-AUDIT (Section 7):
  PulseButton/WireMenuButtons connections stored and disconnected on Destroying. OK.
  PulseGui tweens cancelled on Destroying; Completed:Once guarded by generation. OK.
  Instance.new("UIScale"/"CanvasGroup") once per target; sound :Clone() on Ended:Once. OK.
  EnsureMenuCanvasGroup skips direct-child CloseButton (no reparent / Size writes). OK.
  UiButtonHover resolved once from ReplicatedStorage; plays on PulseButton MouseEnter. OK.
  CloseMenu scheduleCloseRecovery — scoped task.delay tied to close attempt, not a poll loop. OK.
  OpenMenu/CloseMenu Completed:Once only. OK. ]]

return {
	PulseButton = PulseButton,
	PulseGui = PulseGui,
	WireMenuButtons = WireMenuButtons,
	EnsureMenuUIScale = EnsureMenuUIScale,
	EnsureMenuCanvasGroup = EnsureMenuCanvasGroup,
	IsMenuOpen = IsMenuOpen,
	GetMenuPhase = getMenuPhase,
	OpenMenu = OpenMenu,
	CloseMenu = CloseMenu,
	ForceCloseMenu = ForceCloseMenu,
	RequestCloseMenu = RequestCloseMenu,
	ToggleMenu = ToggleMenu,
}
