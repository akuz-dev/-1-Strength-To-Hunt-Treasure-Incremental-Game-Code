--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ClickEffectPool = require(script.Parent.ClickEffectPool)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local WeaponCombatUtil = require(ReplicatedStorage.Shared.WeaponCombatUtil)
local SoundPool = require(script.Parent.SoundPool)

local UI_WAIT_TIMEOUT = 5
local SOUND_WAIT_TIMEOUT = 5
local REMOTES_FOLDER_NAME = "Remotes"
local OBSTACLE_HIT_REMOTE_NAME = "ObstacleHit"
local TWEEN_TIME = 0.35
local APPEAR_TIME = 0.15
local DISAPPEAR_TIME = 0.12
local APPEAR_START_SCALE = 0
local DISAPPEAR_END_SCALE = 0
local SPARK_TWEEN_TIME = 0.3
local SPARK_Z_INDEX = 95
local EFFECT_Z_INDEX = 95
local RANDOM_SCREEN_MARGIN = 48
local SOUND_PATH = { "Assets", "Sounds", "FireClick" }
local PLAYBACK_SPEED_MIN = 0.5
local PLAYBACK_SPEED_MAX = 1.5

local SPARK_COUNT_MIN = 6
local SPARK_COUNT_MAX = 10
local SPARK_SIZE_MIN = 4
local SPARK_SIZE_MAX = 8
local SPARK_COLOR_GREEN_MIN = 140
local SPARK_COLOR_GREEN_MAX = 220
local SPARK_GRAVITY_OFFSET_MIN = 10
local SPARK_GRAVITY_OFFSET_MAX = 25
local STRENGTH_INCREASE_LABEL_NAME = "StrengthIncrease"
local START_SIZE_VIEWPORT_FRACTION = 0.055
local START_SIZE_MIN = 24
local START_SIZE_MAX = 72
local END_SIZE_VIEWPORT_FRACTION = 0.01
local END_SIZE_MIN = 4
local END_SIZE_MAX = 16

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local fireClickGui: ScreenGui? = nil
local fillBar: Frame? = nil
local clickSoundTemplate: Sound? = nil
local isReady = false

local function findStrengthBar(root: Instance): ScreenGui?
	local directChild = root:FindFirstChild("StrengthBar")
	if directChild and directChild:IsA("ScreenGui") then
		return directChild
	end

	for _, descendant in root:GetDescendants() do
		if descendant.Name == "StrengthBar" and descendant:IsA("ScreenGui") then
			return descendant
		end
	end

	return nil
end

local function findFireClickGui(root: Instance): ScreenGui?
	local directChild = root:FindFirstChild("FireClick")
	if directChild and directChild:IsA("ScreenGui") then
		return directChild
	end

	for _, descendant in root:GetDescendants() do
		if descendant.Name == "FireClick" and descendant:IsA("ScreenGui") then
			return descendant
		end
	end

	return nil
end

local function waitForScreenGui(finder: (Instance) -> ScreenGui?): ScreenGui
	while true do
		local existing = finder(playerGui)
		if existing then
			return existing
		end

		playerGui.ChildAdded:Wait()
	end
end

local function resolveSoundTemplate(): Sound?
	local current: Instance = ReplicatedStorage
	for _, childName in SOUND_PATH do
		local child = current:WaitForChild(childName, SOUND_WAIT_TIMEOUT)
		if child == nil then
			warn(`[ClickEffect] Sound path missing "{childName}" within {SOUND_WAIT_TIMEOUT}s`)
			return nil
		end
		current = child
	end

	if not current:IsA("Sound") then
		warn("[ClickEffect] FireClick sound asset is not a Sound")
		return nil
	end

	return current
end

local function getFillBarEndPosition(): Vector2?
	local bar = fillBar
	if bar == nil then
		return nil
	end

	local barPos = bar.AbsolutePosition
	local barSize = bar.AbsoluteSize
	return Vector2.new(barPos.X + barSize.X, barPos.Y + (barSize.Y / 2))
end

local function getViewportSize(): Vector2
	local camera = Workspace.CurrentCamera
	if camera then
		return camera.ViewportSize
	end

	return playerGui.AbsoluteSize
end

local function getViewportHeight(): number
	return getViewportSize().Y
end

local function getRandomScreenPosition(): Vector2
	local viewportSize = getViewportSize()
	local maxX = math.max(RANDOM_SCREEN_MARGIN, viewportSize.X - RANDOM_SCREEN_MARGIN)
	local maxY = math.max(RANDOM_SCREEN_MARGIN, viewportSize.Y - RANDOM_SCREEN_MARGIN)
	local x = math.random(RANDOM_SCREEN_MARGIN, maxX)
	local y = math.random(RANDOM_SCREEN_MARGIN, maxY)
	return Vector2.new(x, y)
end

local function setupTextScaling(instance: Instance): ()
	if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
		instance.TextScaled = true
	end

	for _, child in instance:GetChildren() do
		setupTextScaling(child)
	end
end

local function getCurrentStrengthGainAmount(): number
	local rebirths = player:GetAttribute("Rebirths")
	if typeof(rebirths) ~= "number" then
		rebirths = 0
	end

	local equippedWeaponId = player:GetAttribute("EquippedWeaponId")
	if typeof(equippedWeaponId) ~= "string" then
		equippedWeaponId = nil
	end

	return WeaponCombatUtil.GetClickStrengthGainForRebirths(rebirths, equippedWeaponId)
end

local function applyStrengthGainText(effectFrame: Frame): ()
	local strengthIncreaseLabel = effectFrame:FindFirstChild(STRENGTH_INCREASE_LABEL_NAME, true)
	if strengthIncreaseLabel == nil or not strengthIncreaseLabel:IsA("TextLabel") then
		return
	end

	strengthIncreaseLabel.Text = `+{NumberFormatter.Format(getCurrentStrengthGainAmount())}`
end

local function playClickSound(): ()
	local template = clickSoundTemplate
	if template == nil then
		return
	end

	local playbackSpeed = math.random(
		math.floor(PLAYBACK_SPEED_MIN * 100),
		math.floor(PLAYBACK_SPEED_MAX * 100)
	) / 100
	SoundPool.play2DWithPlaybackSpeed(template, playbackSpeed)
end

local function createInitialSparks(clickPos: Vector2, startPx: number, parentGui: ScreenGui): ()
	local sparkCount = math.random(SPARK_COUNT_MIN, SPARK_COUNT_MAX)

	for _ = 1, sparkCount do
		local spark = ClickEffectPool.acquireSpark()
		if spark == nil then
			continue
		end

		local sparkSize = math.random(SPARK_SIZE_MIN, SPARK_SIZE_MAX)
		spark.Size = UDim2.fromOffset(sparkSize, sparkSize)
		spark.BackgroundColor3 = Color3.fromRGB(255, math.random(SPARK_COLOR_GREEN_MIN, SPARK_COLOR_GREEN_MAX), 0)
		spark.AnchorPoint = Vector2.new(0.5, 0.5)
		spark.Position = UDim2.fromOffset(clickPos.X, clickPos.Y)
		spark.ZIndex = SPARK_Z_INDEX
		spark.Visible = true
		spark.Parent = parentGui

		local angle = math.rad(math.random(0, 360))
		local distance = math.random(math.floor(startPx * 0.5), math.ceil(startPx * 1.2))
		local targetX = clickPos.X + math.cos(angle) * distance
		local targetY = clickPos.Y + math.sin(angle) * distance + math.random(SPARK_GRAVITY_OFFSET_MIN, SPARK_GRAVITY_OFFSET_MAX)

		local sparkTween = TweenService:Create(spark, TweenInfo.new(SPARK_TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(targetX, targetY),
			Size = UDim2.fromOffset(0, 0),
			BackgroundTransparency = 1,
		})

		sparkTween:Play()
		sparkTween.Completed:Once(function()
			ClickEffectPool.release(spark)
		end)
	end
end

local function playAtScreenPosition(screenPos: Vector2): ()
	if not isReady then
		return
	end

	local parentGui = fireClickGui
	local targetPos = getFillBarEndPosition()
	if parentGui == nil or targetPos == nil then
		return
	end

	playClickSound()

	local viewportHeight = getViewportHeight()
	local startPx = math.clamp(viewportHeight * START_SIZE_VIEWPORT_FRACTION, START_SIZE_MIN, START_SIZE_MAX)
	local endPx = math.clamp(viewportHeight * END_SIZE_VIEWPORT_FRACTION, END_SIZE_MIN, END_SIZE_MAX)

	createInitialSparks(screenPos, startPx, parentGui)

	local effectFrame = ClickEffectPool.acquireEffectFrame()
	if effectFrame == nil then
		return
	end

	local uiScale = ClickEffectPool.getEffectScale(effectFrame)
	if uiScale == nil then
		ClickEffectPool.release(effectFrame)
		return
	end

	effectFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	effectFrame.Position = UDim2.fromOffset(screenPos.X, screenPos.Y)
	effectFrame.Size = UDim2.fromOffset(startPx, startPx)
	effectFrame.ZIndex = EFFECT_Z_INDEX
	uiScale.Scale = APPEAR_START_SCALE
	setupTextScaling(effectFrame)
	applyStrengthGainText(effectFrame)
	effectFrame.Visible = true
	effectFrame.Parent = parentGui

	local appearTween = TweenService:Create(
		uiScale,
		TweenInfo.new(APPEAR_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	)

	appearTween:Play()
	appearTween.Completed:Once(function()
		local flyEndScale = endPx / startPx
		local flyInfo = TweenInfo.new(TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local flyTween = TweenService:Create(effectFrame, flyInfo, {
			Position = UDim2.fromOffset(targetPos.X, targetPos.Y),
		})
		local shrinkTween = TweenService:Create(uiScale, flyInfo, {
			Scale = flyEndScale,
		})

		flyTween:Play()
		shrinkTween:Play()
		shrinkTween.Completed:Once(function()
			local disappearTween = TweenService:Create(
				uiScale,
				TweenInfo.new(DISAPPEAR_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.In),
				{ Scale = DISAPPEAR_END_SCALE }
			)

			disappearTween:Play()
			disappearTween.Completed:Once(function()
				ClickEffectPool.release(effectFrame)
			end)
		end)
	end)
end

local function play(inputPosition: Vector3): ()
	playAtScreenPosition(Vector2.new(inputPosition.X, inputPosition.Y))
end

local function resolveObstacleScreenPosition(obstacle: Instance): Vector2
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return getRandomScreenPosition()
	end

	local worldPos: Vector3
	if obstacle:IsA("BasePart") then
		local parent = obstacle.Parent
		local visualPart: BasePart? = nil
		if parent then
			local visual = parent:FindFirstChild("Visual")
			if visual and visual:IsA("BasePart") then
				visualPart = visual
			end
		end

		worldPos = if visualPart then visualPart.Position else obstacle.Position
	elseif obstacle:IsA("Model") then
		worldPos = obstacle:GetBoundingBox().Position
	else
		return getRandomScreenPosition()
	end

	local screenPos, onScreen = camera:WorldToViewportPoint(worldPos)
	if onScreen then
		return Vector2.new(screenPos.X, screenPos.Y)
	end

	return getRandomScreenPosition()
end

local function playFromObstacle(obstacle: Instance): ()
	if not isReady then
		return
	end

	if not obstacle:IsA("Model") and not obstacle:IsA("BasePart") then
		return
	end

	local screenPos = resolveObstacleScreenPosition(obstacle)
	playAtScreenPosition(screenPos)
end

local function initialize(): ()
	if isReady then
		return
	end

	local clickGui = waitForScreenGui(findFireClickGui)
	local templateFrame = clickGui:WaitForChild("Frame", UI_WAIT_TIMEOUT)
	if templateFrame == nil or not templateFrame:IsA("Frame") then
		warn(`[ClickEffect] Frame template not found within {UI_WAIT_TIMEOUT}s`)
		return
	end

	local strengthBarGui = waitForScreenGui(findStrengthBar)
	local topBar = strengthBarGui:WaitForChild("TopBar", UI_WAIT_TIMEOUT)
	if topBar == nil then
		warn(`[ClickEffect] TopBar not found within {UI_WAIT_TIMEOUT}s`)
		return
	end

	local bar = topBar:WaitForChild("FillBar", UI_WAIT_TIMEOUT)
	if bar == nil or not bar:IsA("Frame") then
		warn(`[ClickEffect] FillBar not found within {UI_WAIT_TIMEOUT}s`)
		return
	end

	clickSoundTemplate = resolveSoundTemplate()
	ClickEffectPool.initialize(templateFrame, clickGui)

	fireClickGui = clickGui
	fillBar = bar
	isReady = true

	local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME, UI_WAIT_TIMEOUT)
	if remotesFolder == nil then
		warn(`[ClickEffect] Remotes folder not found within {UI_WAIT_TIMEOUT}s`)
		return
	end

	local obstacleHitRemote = remotesFolder:WaitForChild(OBSTACLE_HIT_REMOTE_NAME, UI_WAIT_TIMEOUT)
	if obstacleHitRemote == nil or not obstacleHitRemote:IsA("RemoteEvent") then
		warn(`[ClickEffect] ObstacleHit RemoteEvent not found within {UI_WAIT_TIMEOUT}s`)
		return
	end

	obstacleHitRemote.OnClientEvent:Connect(function(obstacle: Instance)
		if obstacle == nil then
			return
		end

		if obstacle:IsA("Model") or obstacle:IsA("BasePart") then
			playFromObstacle(obstacle)
		end
	end)
end

task.spawn(initialize)

return {
	play = play,
	playFromObstacle = playFromObstacle,
}

--[[
	SELF-AUDIT (Section 7):
	- task.spawn(initialize) — one-shot async UI/sound resolution; no loop. OK.
	- ObstacleHit OnClientEvent:Connect — script-lifetime singleton in initialize(). OK.
	- Spark tweens — Tween Completed:Once → ClickEffectPool.release per spark. OK.
	- Appear/fly/disappear scale tweens — chained Completed:Once; release only after disappear. OK.
	- Click sound — SoundPool.play2DWithPlaybackSpeed; Ended:Once release inside SoundPool. OK.
	- No per-click :Connect() — all teardown via :Once(). OK.
	- No Instance.new() outside ClickEffectPool/SoundPool on hot path. OK.
]]
