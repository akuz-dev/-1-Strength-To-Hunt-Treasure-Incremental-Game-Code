--!strict

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local SandObstacleUtil = require(ReplicatedStorage.Shared.SandObstacleUtil)
local ObstacleConfig = require(ReplicatedStorage.Shared.ObstacleConfig)
local SoundPool = require(script.Parent.SoundPool)

local OBSTACLE_TAG = "Obstacle"
local REMOTES_FOLDER_NAME = "Remotes"
local SOUND_WAIT_TIMEOUT = 5
local HIT_SOUND_PATH = { "Assets", "Sounds", "ObstacleBreak" }
local HIT_PLAYBACK_SPEED_MIN = 0.88
local HIT_PLAYBACK_SPEED_MAX = 1.12
local HIT_VOLUME_MIN = 0.42
local HIT_VOLUME_MAX = 0.58

local TWEEN_DURATION = 0.35
local DEATH_SINK_TWEEN_DURATION = SandObstacleUtil.DEATH_SINK_TWEEN_DURATION
local TWEEN_EASING = Enum.EasingStyle.Quad
local TWEEN_DIRECTION = Enum.EasingDirection.Out

type PileVisualState = {
	visualPart: BasePart,
	hpSourcePart: BasePart,
	restY: number,
	sunkY: number,
	maxHP: number,
	hpChangedConnection: RBXScriptConnection,
	activeTween: Tween?,
}

local pileVisualStates: { [BasePart]: PileVisualState } = {}
local trackedVisualParts: { [BasePart]: boolean } = {}
local hitSoundTemplate: Sound? = nil
local isBatchResetting = false

local function cancelActiveTween(state: PileVisualState): ()
	if state.activeTween then
		state.activeTween:Cancel()
		state.activeTween = nil
	end
end

local function getHitSoundTemplate(): Sound?
	if hitSoundTemplate then
		return hitSoundTemplate
	end

	local current: Instance = ReplicatedStorage
	for _, childName in HIT_SOUND_PATH do
		local child = current:WaitForChild(childName, SOUND_WAIT_TIMEOUT)
		if child == nil then
			warn("[SandPileVisual] Hit sound template not found at ReplicatedStorage.Assets.Sounds.ObstacleBreak")
			return nil
		end
		current = child
	end

	if not current:IsA("Sound") then
		warn("[SandPileVisual] ReplicatedStorage.Assets.Sounds.ObstacleBreak is not a Sound")
		return nil
	end

	hitSoundTemplate = current
	return hitSoundTemplate
end

local function playHitSound(): ()
	local template = getHitSoundTemplate()
	if template == nil then
		return
	end

	local playbackSpeed = math.random(
		math.floor(HIT_PLAYBACK_SPEED_MIN * 100),
		math.floor(HIT_PLAYBACK_SPEED_MAX * 100)
	) / 100
	local volume = math.random(
		math.floor(HIT_VOLUME_MIN * 100),
		math.floor(HIT_VOLUME_MAX * 100)
	) / 100
	SoundPool.play2DWithVariation(template, playbackSpeed, volume)
end

local function isTrackedSandBlocker(part: BasePart): boolean
	for _, state in pileVisualStates do
		if state.hpSourcePart == part then
			return true
		end
	end

	local blocker, _visual = SandObstacleUtil.resolveBlockerVisualPair(part)
	return blocker == part
end

local function isBlockerRegistered(blocker: BasePart): boolean
	local maxHP = blocker:GetAttribute("MaxHP")
	return typeof(maxHP) == "number" and maxHP > 0
end

local function onObstacleHit(obstacle: Instance): ()
	if obstacle == nil or not obstacle:IsA("BasePart") then
		return
	end

	if pileVisualStates[obstacle] then
		playHitSound()
		return
	end

	local _blocker, visual = SandObstacleUtil.resolveBlockerVisualPair(obstacle)
	if visual and pileVisualStates[visual] then
		playHitSound()
	end
end

local function readMaxHP(hpSourcePart: BasePart, state: PileVisualState): number
	local maxHP = hpSourcePart:GetAttribute("MaxHP")
	if typeof(maxHP) == "number" and maxHP > 0 then
		state.maxHP = maxHP
		return maxHP
	end

	return state.maxHP
end

local function refreshRestYSunkY(state: PileVisualState): ()
	local restY, sunkY = SandObstacleUtil.ensureRestYSunkYAttributes(state.visualPart)
	state.restY = restY
	state.sunkY = sunkY
end

local function hideVisualForLocalPlayer(visualPart: BasePart): ()
	visualPart.LocalTransparencyModifier = 1
end

local function showVisualForLocalPlayer(visualPart: BasePart): ()
	visualPart.LocalTransparencyModifier = 0
end

local function snapVisualPartToY(visualPart: BasePart, targetY: number): ()
	local currentCFrame = visualPart.CFrame
	local position = currentCFrame.Position
	visualPart.CFrame = CFrame.new(position.X, targetY, position.Z) * (currentCFrame - currentCFrame.Position)
end

local function tweenPileToTargetY(
	visualPart: BasePart,
	state: PileVisualState,
	targetY: number,
	duration: number,
	onComplete: ((playbackState: Enum.PlaybackState) -> ())?
): ()
	cancelActiveTween(state)

	local currentCFrame = visualPart.CFrame
	local position = currentCFrame.Position
	local targetCFrame = CFrame.new(position.X, targetY, position.Z) * (currentCFrame - currentCFrame.Position)

	local tweenInfo = TweenInfo.new(duration, TWEEN_EASING, TWEEN_DIRECTION)
	local tween = TweenService:Create(visualPart, tweenInfo, {
		CFrame = targetCFrame,
	})

	state.activeTween = tween
	tween:Play()

	tween.Completed:Once(function(playbackState: Enum.PlaybackState)
		if state.activeTween == tween then
			state.activeTween = nil
		end

		if playbackState == Enum.PlaybackState.Cancelled then
			return
		end

		if onComplete then
			onComplete(playbackState)
		end
	end)
end

local function applyHpToVisualPart(visualPart: BasePart): ()
	local state = pileVisualStates[visualPart]
	if state == nil then
		return
	end

	if isBatchResetting then
		return
	end

	refreshRestYSunkY(state)

	local maxHP = readMaxHP(state.hpSourcePart, state)
	local currentHP = state.hpSourcePart:GetAttribute("CurrentHP")
	if typeof(currentHP) ~= "number" then
		return
	end

	local targetY = SandObstacleUtil.computeTargetY(state.restY, state.sunkY, currentHP, maxHP)
	local isBroken = currentHP <= 0

	if isBroken then
		tweenPileToTargetY(visualPart, state, state.sunkY, DEATH_SINK_TWEEN_DURATION, function()
			local currentState = pileVisualStates[visualPart]
			if currentState == nil then
				return
			end

			local hpNow = currentState.hpSourcePart:GetAttribute("CurrentHP")
			if typeof(hpNow) ~= "number" or hpNow > 0 then
				return
			end

			snapVisualPartToY(visualPart, currentState.sunkY)
			hideVisualForLocalPlayer(visualPart)
		end)
	else
		showVisualForLocalPlayer(visualPart)
		tweenPileToTargetY(visualPart, state, targetY, TWEEN_DURATION, nil)
	end
end

local function resetPileVisual(visualPart: BasePart, state: PileVisualState): ()
	cancelActiveTween(state)
	refreshRestYSunkY(state)
	showVisualForLocalPlayer(visualPart)

	local currentCFrame = visualPart.CFrame
	local position = currentCFrame.Position
	visualPart.CFrame = CFrame.new(position.X, state.restY, position.Z) * (currentCFrame - currentCFrame.Position)
end

local function clearPileVisualState(visualPart: BasePart): ()
	local state = pileVisualStates[visualPart]
	if state == nil then
		return
	end

	cancelActiveTween(state)
	state.hpChangedConnection:Disconnect()
	pileVisualStates[visualPart] = nil
	trackedVisualParts[visualPart] = nil
end

local function beginTrackingVisual(
	taggedInstance: Instance,
	blocker: BasePart,
	visualPart: BasePart
): ()
	local hpSourcePart = blocker

	if trackedVisualParts[visualPart] then
		return
	end

	trackedVisualParts[visualPart] = true
	SandObstacleUtil.configureVisualPart(visualPart)
	showVisualForLocalPlayer(visualPart)

	local restY, sunkY = SandObstacleUtil.ensureRestYSunkYAttributes(visualPart)
	local maxHPAttr = hpSourcePart:GetAttribute("MaxHP")
	local maxHP = if typeof(maxHPAttr) == "number" and maxHPAttr > 0 then maxHPAttr else 1

	local state: PileVisualState = {
		visualPart = visualPart,
		hpSourcePart = hpSourcePart,
		restY = restY,
		sunkY = sunkY,
		maxHP = maxHP,
		hpChangedConnection = nil :: any,
		activeTween = nil,
	}

	pileVisualStates[visualPart] = state

	state.hpChangedConnection = hpSourcePart:GetAttributeChangedSignal("CurrentHP"):Connect(function()
		applyHpToVisualPart(visualPart)
	end)

	visualPart.Destroying:Connect(function()
		clearPileVisualState(visualPart)
	end)

	applyHpToVisualPart(visualPart)
end

local function trackSandPile(taggedInstance: Instance): ()
	local blocker, visualPart = SandObstacleUtil.resolveBlockerVisualPair(taggedInstance)
	if blocker == nil then
		return
	end

	if visualPart == nil then
		local container = if taggedInstance:IsA("BasePart") then taggedInstance.Parent else taggedInstance
		if container == nil then
			return
		end

		local pendingConnection: RBXScriptConnection?
		pendingConnection = container.ChildAdded:Connect(function(child: Instance)
			if not child:IsA("BasePart") then
				return
			end

			if child.Name ~= ObstacleConfig.SegmentPartNames.Visual then
				return
			end

			if pendingConnection then
				pendingConnection:Disconnect()
				pendingConnection = nil
			end

			trackSandPile(taggedInstance)
		end)

		return
	end

	if not isBlockerRegistered(blocker) then
		local pendingRegistration: RBXScriptConnection?
		pendingRegistration = blocker:GetAttributeChangedSignal("MaxHP"):Connect(function()
			if not isBlockerRegistered(blocker) then
				return
			end

			if pendingRegistration then
				pendingRegistration:Disconnect()
				pendingRegistration = nil
			end

			trackSandPile(taggedInstance)
		end)

		return
	end

	beginTrackingVisual(taggedInstance, blocker, visualPart)
end

local function onTaggedObstacleAdded(instance: Instance): ()
	trackSandPile(instance)
end

local function onObstacleResetAll(resetBlockers: { BasePart }): ()
	if #resetBlockers == 0 then
		return
	end

	local resetBlockerSet: { [BasePart]: boolean } = {}
	for _, blocker in resetBlockers do
		if typeof(blocker) == "Instance" and blocker:IsA("BasePart") then
			resetBlockerSet[blocker] = true
		end
	end

	if next(resetBlockerSet) == nil then
		return
	end

	isBatchResetting = true

	for visualPart, state in pileVisualStates do
		if resetBlockerSet[state.hpSourcePart] then
			resetPileVisual(visualPart, state)
		end
	end

	task.defer(function()
		isBatchResetting = false
	end)
end

local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME)
local resetAllRemote = remotesFolder:WaitForChild("ObstacleResetAll")
local obstacleHitRemote = remotesFolder:WaitForChild("ObstacleHit")

if not resetAllRemote:IsA("RemoteEvent") then
	warn("[SandPileVisual] ObstacleResetAll remote exists but is not a RemoteEvent")
else
	resetAllRemote.OnClientEvent:Connect(onObstacleResetAll)
end

if not obstacleHitRemote:IsA("RemoteEvent") then
	warn("[SandPileVisual] ObstacleHit remote exists but is not a RemoteEvent")
else
	obstacleHitRemote.OnClientEvent:Connect(onObstacleHit)
end

for _, obstacle in CollectionService:GetTagged(OBSTACLE_TAG) do
	onTaggedObstacleAdded(obstacle)
end

CollectionService:GetInstanceAddedSignal(OBSTACLE_TAG):Connect(onTaggedObstacleAdded)

--[[
	SELF-AUDIT (Section 7):
	- hpSourcePart (Blocker):GetAttributeChangedSignal("CurrentHP"):Connect — stored in
	  pileVisualStates[visualPart].hpChangedConnection; disconnected in clearPileVisualState;
	  callback resolves state from pileVisualStates (no nil closure capture). OK.
	- visualPart.Destroying:Connect — guarded by trackedVisualParts; tears down in clearPileVisualState. OK.
	- ObstacleResetAll OnClientEvent:Connect — script-lifetime singleton; receives reset Blocker
	  list and only resets matching pileVisualStates entries (delta-only). OK.
	- ObstacleHit OnClientEvent:Connect — script-lifetime singleton; plays SoundPool SFX only,
	  no Broken replay (one-shot = single Hit). OK.
	- CollectionService tag added signal:Connect — script-lifetime singleton. OK.
	- Tween Completed:Once — one-shot per tween; death-hit callback snaps Visual Y and hides locally. OK.
	- TweenService:Create — no Instance.new on hot path; tweens Visual Part CFrame only. OK.
	- configureVisualPart deferred until Blocker has MaxHP from server registration;
	  waits on GetAttributeChangedSignal("MaxHP") before beginTrackingVisual. OK.
	- container ChildAdded:Connect — one-shot wait for server-migrated Visual; disconnected when Visual appears. OK.
	- Hit sound — SoundPool.play2DWithVariation (parented to SoundService, non-directional). OK.
	- refreshRestYSunkY reads RestY/SunkY from visualPart attributes on each HP change and reset. OK.
]]
