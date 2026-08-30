--!strict

--[[
	Section 6 pooled cache for obstacle "ghostly hit flash" Highlights.
	One Highlight per obstacle Part, created lazily on first hit and reused forever —
	never Instance.new()'d more than once per Part. Purely client-side visual/tween
	logic (Section 5, "Server is Blind"); the server only ever sends a single Instance
	reference per damage tick (Section 5.5, delta-only networking).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local function findObstacleHitVisualRemote(): RemoteEvent?
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 5)
	if remotesFolder == nil then
		return nil
	end

	local remoteInstance = remotesFolder:WaitForChild("ObstacleHitVisual", 5)
	if remoteInstance ~= nil and remoteInstance:IsA("RemoteEvent") then
		return remoteInstance
	end

	return nil
end

local obstacleHitVisualRemote = findObstacleHitVisualRemote()

local FLASH_COLOR = Color3.fromRGB(255, 255, 255)

local FILL_TRANSPARENCY_HIDDEN = 1
local REST_OUTLINE_TRANSPARENCY = 1
local FLASH_OUTLINE_TRANSPARENCY = 0

local FLASH_IN_SECONDS = 0.05
local FLASH_OUT_SECONDS = 0.25

local flashInTweenInfo = TweenInfo.new(FLASH_IN_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
local flashOutTweenInfo = TweenInfo.new(FLASH_OUT_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.In)

type ActiveFlashTweens = {
	flashIn: Tween,
	flashOut: Tween,
}

local highlightsByPart: { [BasePart]: Highlight } = {}
local activeTweensByPart: { [BasePart]: ActiveFlashTweens } = {}

local function cancelActiveFlash(part: BasePart): ()
	local activeTweens = activeTweensByPart[part]
	if activeTweens == nil then
		return
	end

	activeTweens.flashIn:Cancel()
	activeTweens.flashOut:Cancel()
	activeTweensByPart[part] = nil
end

local function releaseHighlightCacheEntry(part: BasePart): ()
	cancelActiveFlash(part)
	highlightsByPart[part] = nil
end

local function getOrCreateHighlight(part: BasePart): Highlight
	local existingHighlight = highlightsByPart[part]
	if existingHighlight ~= nil then
		return existingHighlight
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "GhostlyHitFlash"
	highlight.FillColor = FLASH_COLOR
	highlight.OutlineColor = FLASH_COLOR
	highlight.FillTransparency = FILL_TRANSPARENCY_HIDDEN
	highlight.OutlineTransparency = REST_OUTLINE_TRANSPARENCY
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = part
	highlight.Parent = part

	highlightsByPart[part] = highlight

	part.Destroying:Once(function()
		releaseHighlightCacheEntry(part)
	end)

	return highlight
end

local function playHitFlash(part: BasePart): ()
	if not part:IsDescendantOf(Workspace) then
		return
	end

	local highlight = getOrCreateHighlight(part)
	cancelActiveFlash(part)

	highlight.OutlineTransparency = REST_OUTLINE_TRANSPARENCY

	local flashInTween = TweenService:Create(highlight, flashInTweenInfo, {
		OutlineTransparency = FLASH_OUTLINE_TRANSPARENCY,
	})
	local flashOutTween = TweenService:Create(highlight, flashOutTweenInfo, {
		OutlineTransparency = REST_OUTLINE_TRANSPARENCY,
	})

	activeTweensByPart[part] = {
		flashIn = flashInTween,
		flashOut = flashOutTween,
	}

	flashInTween.Completed:Once(function(playbackState: Enum.PlaybackState)
		if playbackState ~= Enum.PlaybackState.Completed then
			return
		end

		if not part:IsDescendantOf(Workspace) then
			return
		end

		flashOutTween:Play()
	end)

	flashInTween:Play()
end

local function onObstacleHitVisual(obstaclePart: Instance): ()
	if typeof(obstaclePart) ~= "Instance" or not obstaclePart:IsA("BasePart") then
		return
	end

	playHitFlash(obstaclePart)
end

if obstacleHitVisualRemote ~= nil then
	obstacleHitVisualRemote.OnClientEvent:Connect(onObstacleHitVisual)
else
	warn("[ObstacleHitEffects] ReplicatedStorage.Remotes.ObstacleHitVisual not found")
end

--[[
	SELF-AUDIT (Section 7):
	- obstacleHitVisualRemote.OnClientEvent:Connect — script-lifetime singleton, never
	  disconnected (matches other client remote listeners in this codebase). OK.
	- part.Destroying:Once — one-shot per Part the first time a Highlight is created for
	  it; self-cleans the pooled cache entry if the Part is ever actually destroyed. OK.
	- flashInTween.Completed:Once — one-shot per flash, per Section 7.2-D. OK.
	- Instance.new("Highlight") — pooled cache keyed by obstacle Part in highlightsByPart;
	  created at most once per Part (checked via getOrCreateHighlight), reused forever,
	  never :Destroy()'d on the hot path. OK.
]]
