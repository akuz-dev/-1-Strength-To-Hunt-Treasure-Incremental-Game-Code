--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local LootConfig = require(ReplicatedStorage.Shared.LootConfig)
local LootPickupFxPool = require(script.Parent.LootPickupFxPool)
local SoundPool = require(script.Parent.SoundPool)

local UI_WAIT_TIMEOUT = 5
local REMOTES_FOLDER_NAME = "Remotes"
local LOOT_COLLECTED_REMOTE_NAME = "LootCollected"
local HUD_BUTTONS_NAME = "HUDButtons"
local CURRENCY_COUNTERS_NAME = "CurrencyCounters"
local BACKPACK_COUNTER_NAME = "BackpackCounter"

local ITEM_IMAGE_ID = "rbxassetid://83668230191977"
local STAR_IMAGE_ID = "rbxassetid://128045918714416"
local END_SIZE_VIEWPORT_FRACTION = 0.035
local CLEANUP_TRAIL_FADE_BUFFER = 0.45

type RarityFxConfig = {
	itemScale: number,
	soundPitch: number,
	soundVolume: number,
	primary: Color3,
	secondary: Color3,
	glow: Color3,
	ringColor: Color3,
	shadowColor: Color3,
	starColor: Color3,
	trailColor: Color3,
	starSizeScale: number,
	spinDuration: number,
	popDuration: number,
	holdDuration: number,
	motionDuration: number,
	shadowTransparency: number,
	shadowStartOffset: number,
	shadowOffsetScale: number,
	shadowOffsetMax: number,
	trailThicknessScale: number,
	trailThicknessMin: number,
	trailThicknessMax: number,
	trailFadeDuration: number,
	curveOffsetMin: number,
	curveOffsetMax: number,
	burstCount: number,
	burstRadiusScale: number,
	burstSizeMin: number,
	burstSizeMax: number,
	burstTravelDuration: number,
	burstDistanceMin: number,
	burstDistanceMax: number,
	trailSparkleInterval: number,
	trailSparkleCount: number,
	trailSparkleExtraChance: number,
	trailSparkleSizeMin: number,
	trailSparkleSizeMax: number,
	shockwaveCount: number,
	shockwaveStagger: number,
	shockwaveStartScale: number,
	shockwaveExpandBase: number,
	shockwaveExpandPerRing: number,
	shockwaveDuration: number,
	shockwaveThickness: number,
	shockwaveColors: { Color3 },
	orbCount: number,
	orbRadiusX: number,
	orbRadiusY: number,
	orbSizeScale: number,
	orbSpeed: number,
	orbYAngleScale: number,
	orbZBase: number,
	orbZAmp: number,
	orbStrokeColor: Color3,
	orbUseRingAsPrimary: boolean,
	orbOddIsGlow: boolean,
	orbAlternateStroke: boolean,
	flareEntrance: boolean,
}

type PlaybackState = {
	playbackId: number,
	config: RarityFxConfig,
	container: Frame,
	burstHolder: Frame,
	trailHolder: Frame,
	starImage: ImageLabel,
	itemShadow: ImageLabel,
	trackedFrames: { GuiObject },
	delayThreads: { thread },
	orbs: { Frame },
	holdConnection: RBXScriptConnection?,
	motionConnection: RBXScriptConnection?,
	spinTween: Tween?,
	phase: number,
	holdStartClock: number,
	holdCenterPxSize: number,
	motionStartClock: number,
	motionStartPos: Vector2,
	motionControlPos: Vector2,
	motionCenterPxSize: number,
	motionEndPxSize: number,
	motionLastPos: Vector2,
	sparkleTimer: number,
}

local PHASE_POP = 1
local PHASE_HOLD = 2
local PHASE_MOTION = 3
local PHASE_DONE = 4

local RARITY_CONFIGS: { [string]: RarityFxConfig } = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local overlayGui: ScreenGui? = nil
local backpackCounter: GuiObject? = nil
local pickupSoundTemplate: Sound? = nil
local nextPlaybackIdValue = 0
local playbackStates: { [number]: PlaybackState } = {}
local remoteConnected = false
local hudWireStarted = false
local hudButtonsAddedConnection: RBXScriptConnection? = nil

local function nextPlaybackId(): number
	nextPlaybackIdValue += 1
	return nextPlaybackIdValue
end

local function makeConfig(overrides: { [string]: any }): RarityFxConfig
	local config: RarityFxConfig = {
		itemScale = 0.12,
		soundPitch = 1,
		soundVolume = 0.5,
		primary = Color3.fromRGB(255, 255, 255),
		secondary = Color3.fromRGB(255, 255, 255),
		glow = Color3.fromRGB(255, 255, 255),
		ringColor = Color3.fromRGB(255, 255, 255),
		shadowColor = Color3.fromRGB(220, 220, 220),
		starColor = Color3.fromRGB(255, 255, 255),
		trailColor = Color3.fromRGB(255, 255, 255),
		starSizeScale = 1.8,
		spinDuration = 3,
		popDuration = 0.35,
		holdDuration = 0.7,
		motionDuration = 0.65,
		shadowTransparency = 0.35,
		shadowStartOffset = 4,
		shadowOffsetScale = 0.035,
		shadowOffsetMax = 4,
		trailThicknessScale = 0.22,
		trailThicknessMin = 3,
		trailThicknessMax = 11,
		trailFadeDuration = 0.25,
		curveOffsetMin = 18,
		curveOffsetMax = 38,
		burstCount = 0,
		burstRadiusScale = 1.1,
		burstSizeMin = 18,
		burstSizeMax = 34,
		burstTravelDuration = 0.65,
		burstDistanceMin = 1.4,
		burstDistanceMax = 2.3,
		trailSparkleInterval = 0,
		trailSparkleCount = 0,
		trailSparkleExtraChance = 0,
		trailSparkleSizeMin = 12,
		trailSparkleSizeMax = 22,
		shockwaveCount = 0,
		shockwaveStagger = 0.1,
		shockwaveStartScale = 0.3,
		shockwaveExpandBase = 2.2,
		shockwaveExpandPerRing = 0.4,
		shockwaveDuration = 0.5,
		shockwaveThickness = 4,
		shockwaveColors = {},
		orbCount = 0,
		orbRadiusX = 0.8,
		orbRadiusY = 0.5,
		orbSizeScale = 0.22,
		orbSpeed = math.pi * 2.5,
		orbYAngleScale = 1.5,
		orbZBase = 0.8,
		orbZAmp = 0.35,
		orbStrokeColor = Color3.fromRGB(255, 255, 255),
		orbUseRingAsPrimary = false,
		orbOddIsGlow = false,
		orbAlternateStroke = false,
		flareEntrance = false,
	}

	for key, value in overrides do
		(config :: any)[key] = value
	end

	return config
end

RARITY_CONFIGS.Common = makeConfig({})

RARITY_CONFIGS.Uncommon = makeConfig({
	soundPitch = 1.15,
	primary = Color3.fromRGB(85, 255, 127),
	secondary = Color3.fromRGB(150, 255, 180),
	glow = Color3.fromRGB(220, 255, 230),
	shadowColor = Color3.fromRGB(200, 230, 210),
	starColor = Color3.fromRGB(85, 255, 127),
	trailColor = Color3.fromRGB(150, 255, 180),
	spinDuration = 2.5,
	holdDuration = 0.6,
	shadowTransparency = 0.3,
	trailThicknessScale = 0.24,
	trailThicknessMin = 4,
	trailThicknessMax = 12,
	burstCount = 22,
})

RARITY_CONFIGS.Rare = makeConfig({
	soundPitch = 1.25,
	primary = Color3.fromRGB(30, 144, 255),
	secondary = Color3.fromRGB(135, 206, 250),
	glow = Color3.fromRGB(220, 245, 255),
	shadowColor = Color3.fromRGB(180, 210, 230),
	starColor = Color3.fromRGB(30, 144, 255),
	trailColor = Color3.fromRGB(135, 206, 250),
	spinDuration = 2.5,
	holdDuration = 0.6,
	shadowTransparency = 0.3,
	trailThicknessScale = 0.24,
	trailThicknessMin = 4,
	trailThicknessMax = 12,
	burstCount = 22,
	trailSparkleInterval = 0.025,
	trailSparkleCount = 1,
	trailSparkleExtraChance = 0.5,
})

RARITY_CONFIGS.Epic = makeConfig({
	soundPitch = 1.35,
	primary = Color3.fromRGB(160, 32, 240),
	secondary = Color3.fromRGB(200, 100, 255),
	glow = Color3.fromRGB(240, 190, 255),
	ringColor = Color3.fromRGB(220, 80, 255),
	shadowColor = Color3.fromRGB(80, 20, 100),
	starColor = Color3.fromRGB(160, 32, 240),
	trailColor = Color3.fromRGB(200, 100, 255),
	spinDuration = 2.2,
	holdDuration = 0.6,
	shadowTransparency = 0.3,
	trailThicknessScale = 0.26,
	trailThicknessMin = 4,
	trailThicknessMax = 14,
	burstCount = 26,
	burstSizeMin = 20,
	burstSizeMax = 38,
	burstTravelDuration = 0.7,
	burstDistanceMax = 2.5,
	trailSparkleInterval = 0.02,
	trailSparkleCount = 1,
	trailSparkleExtraChance = 0.5,
	trailSparkleSizeMax = 24,
	shockwaveCount = 1,
	shockwaveStartScale = 0.4,
	shockwaveExpandBase = 2.2,
	shockwaveExpandPerRing = 0,
	shockwaveDuration = 0.5,
	shockwaveThickness = 4,
	shockwaveColors = { Color3.fromRGB(220, 80, 255) },
	orbCount = 2,
	orbStrokeColor = Color3.fromRGB(240, 190, 255),
	orbUseRingAsPrimary = true,
})

RARITY_CONFIGS.Legendary = makeConfig({
	itemScale = 0.14,
	soundPitch = 1.5,
	soundVolume = 0.6,
	primary = Color3.fromRGB(255, 185, 0),
	secondary = Color3.fromRGB(255, 225, 100),
	glow = Color3.fromRGB(255, 250, 210),
	ringColor = Color3.fromRGB(255, 140, 0),
	shadowColor = Color3.fromRGB(110, 50, 0),
	starColor = Color3.fromRGB(255, 185, 0),
	trailColor = Color3.fromRGB(255, 225, 100),
	starSizeScale = 2,
	spinDuration = 2,
	popDuration = 0.38,
	holdDuration = 0.7,
	motionDuration = 0.7,
	shadowOffsetScale = 0.04,
	shadowOffsetMax = 5,
	trailThicknessScale = 0.28,
	trailThicknessMin = 5,
	trailThicknessMax = 16,
	trailFadeDuration = 0.3,
	curveOffsetMin = 20,
	curveOffsetMax = 40,
	burstCount = 36,
	burstRadiusScale = 1.2,
	burstSizeMin = 22,
	burstSizeMax = 42,
	burstTravelDuration = 0.75,
	burstDistanceMin = 1.5,
	burstDistanceMax = 2.8,
	trailSparkleInterval = 0.018,
	trailSparkleCount = 2,
	trailSparkleSizeMin = 14,
	trailSparkleSizeMax = 28,
	shockwaveCount = 2,
	shockwaveStagger = 0.1,
	shockwaveDuration = 0.55,
	shockwaveThickness = 5,
	shockwaveColors = {
		Color3.fromRGB(255, 185, 0),
		Color3.fromRGB(255, 140, 0),
	},
	orbCount = 4,
	orbRadiusX = 0.9,
	orbRadiusY = 0.55,
	orbSpeed = math.pi * 2.2,
	orbYAngleScale = 1.4,
	orbZAmp = 0.4,
	orbStrokeColor = Color3.fromRGB(255, 250, 210),
})

RARITY_CONFIGS.Mythic = makeConfig({
	itemScale = 0.16,
	soundPitch = 1.65,
	soundVolume = 0.7,
	primary = Color3.fromRGB(230, 20, 50),
	secondary = Color3.fromRGB(255, 80, 100),
	glow = Color3.fromRGB(255, 200, 210),
	ringColor = Color3.fromRGB(180, 0, 40),
	shadowColor = Color3.fromRGB(60, 0, 15),
	starColor = Color3.fromRGB(230, 20, 50),
	trailColor = Color3.fromRGB(255, 80, 100),
	starSizeScale = 2.2,
	spinDuration = 1.8,
	popDuration = 0.4,
	holdDuration = 0.75,
	motionDuration = 0.75,
	shadowTransparency = 0.3,
	shadowStartOffset = 5,
	shadowOffsetScale = 0.045,
	shadowOffsetMax = 6,
	trailThicknessScale = 0.28,
	trailThicknessMin = 5,
	trailThicknessMax = 15,
	trailFadeDuration = 0.3,
	curveOffsetMin = 22,
	curveOffsetMax = 42,
	burstCount = 16,
	burstSizeMin = 18,
	burstSizeMax = 32,
	burstTravelDuration = 0.7,
	burstDistanceMax = 2.2,
	trailSparkleInterval = 0.05,
	trailSparkleCount = 1,
	shockwaveCount = 3,
	shockwaveStagger = 0.08,
	shockwaveExpandBase = 2.4,
	shockwaveExpandPerRing = 0.5,
	shockwaveDuration = 0.6,
	shockwaveThickness = 5,
	shockwaveColors = {
		Color3.fromRGB(255, 200, 210),
		Color3.fromRGB(230, 20, 50),
		Color3.fromRGB(180, 0, 40),
	},
	orbCount = 6,
	orbRadiusX = 0.95,
	orbRadiusY = 0.6,
	orbSizeScale = 0.2,
	orbSpeed = math.pi * 2,
	orbYAngleScale = 1.3,
	orbZBase = 0.75,
	orbZAmp = 0.45,
	orbStrokeColor = Color3.fromRGB(255, 80, 100),
})

RARITY_CONFIGS.Godly = makeConfig({
	itemScale = 0.18,
	soundPitch = 1.85,
	soundVolume = 0.75,
	primary = Color3.fromRGB(125, 0, 0),
	secondary = Color3.fromRGB(185, 20, 20),
	glow = Color3.fromRGB(255, 120, 120),
	ringColor = Color3.fromRGB(70, 0, 0),
	shadowColor = Color3.fromRGB(20, 0, 0),
	starColor = Color3.fromRGB(125, 0, 0),
	trailColor = Color3.fromRGB(185, 20, 20),
	starSizeScale = 2.4,
	spinDuration = 1.6,
	popDuration = 0.4,
	holdDuration = 0.8,
	motionDuration = 0.75,
	shadowTransparency = 0.3,
	shadowStartOffset = 5,
	shadowOffsetScale = 0.045,
	shadowOffsetMax = 6,
	trailThicknessScale = 0.32,
	trailThicknessMin = 6,
	trailThicknessMax = 18,
	trailFadeDuration = 0.35,
	curveOffsetMin = 25,
	curveOffsetMax = 45,
	burstCount = 18,
	burstSizeMin = 20,
	burstSizeMax = 36,
	burstTravelDuration = 0.7,
	burstDistanceMax = 2.2,
	trailSparkleInterval = 0.05,
	trailSparkleCount = 1,
	trailSparkleSizeMin = 14,
	trailSparkleSizeMax = 24,
	shockwaveCount = 4,
	shockwaveStagger = 0.07,
	shockwaveExpandBase = 2.6,
	shockwaveExpandPerRing = 0.5,
	shockwaveDuration = 0.65,
	shockwaveThickness = 6,
	shockwaveColors = {
		Color3.fromRGB(255, 120, 120),
		Color3.fromRGB(185, 20, 20),
		Color3.fromRGB(125, 0, 0),
		Color3.fromRGB(125, 0, 0),
	},
	orbCount = 8,
	orbRadiusX = 1.05,
	orbRadiusY = 0.45,
	orbSizeScale = 0.18,
	orbSpeed = math.pi * 2.2,
	orbYAngleScale = 1,
	orbZAmp = 0.4,
	orbStrokeColor = Color3.fromRGB(185, 20, 20),
	orbOddIsGlow = true,
})

RARITY_CONFIGS.Divine = makeConfig({
	itemScale = 0.2,
	soundPitch = 1.95,
	soundVolume = 0.75,
	primary = Color3.fromRGB(255, 210, 235),
	secondary = Color3.fromRGB(255, 170, 215),
	glow = Color3.fromRGB(255, 255, 255),
	ringColor = Color3.fromRGB(255, 225, 245),
	shadowColor = Color3.fromRGB(45, 10, 30),
	starColor = Color3.fromRGB(255, 210, 235),
	trailColor = Color3.fromRGB(255, 210, 235),
	starSizeScale = 2.4,
	spinDuration = 1.6,
	popDuration = 0.4,
	holdDuration = 0.8,
	motionDuration = 0.75,
	shadowTransparency = 0.3,
	shadowStartOffset = 5,
	shadowOffsetScale = 0.045,
	shadowOffsetMax = 6,
	trailThicknessScale = 0.32,
	trailThicknessMin = 6,
	trailThicknessMax = 18,
	trailFadeDuration = 0.35,
	curveOffsetMin = 25,
	curveOffsetMax = 45,
	burstCount = 20,
	burstSizeMin = 20,
	burstSizeMax = 36,
	burstTravelDuration = 0.7,
	burstDistanceMax = 2.2,
	trailSparkleInterval = 0.05,
	trailSparkleCount = 1,
	trailSparkleSizeMin = 14,
	trailSparkleSizeMax = 24,
	shockwaveCount = 4,
	shockwaveStagger = 0.07,
	shockwaveExpandBase = 2.6,
	shockwaveExpandPerRing = 0.5,
	shockwaveDuration = 0.65,
	shockwaveThickness = 6,
	shockwaveColors = {
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(255, 210, 235),
		Color3.fromRGB(255, 170, 215),
		Color3.fromRGB(255, 170, 215),
	},
	orbCount = 8,
	orbRadiusX = 1.05,
	orbRadiusY = 0.45,
	orbSizeScale = 0.18,
	orbSpeed = math.pi * 2.2,
	orbYAngleScale = 1,
	orbZAmp = 0.4,
	orbStrokeColor = Color3.fromRGB(255, 170, 215),
	orbOddIsGlow = true,
})

RARITY_CONFIGS.Celestial = makeConfig({
	itemScale = 0.21,
	soundPitch = 2.05,
	soundVolume = 0.75,
	primary = Color3.fromRGB(240, 255, 205),
	secondary = Color3.fromRGB(215, 245, 160),
	glow = Color3.fromRGB(255, 255, 240),
	ringColor = Color3.fromRGB(180, 220, 130),
	shadowColor = Color3.fromRGB(20, 30, 15),
	starColor = Color3.fromRGB(240, 255, 205),
	trailColor = Color3.fromRGB(240, 255, 205),
	starSizeScale = 2.4,
	spinDuration = 1.6,
	popDuration = 0.4,
	holdDuration = 0.8,
	motionDuration = 0.75,
	shadowTransparency = 0.3,
	shadowStartOffset = 5,
	shadowOffsetScale = 0.045,
	shadowOffsetMax = 6,
	trailThicknessScale = 0.32,
	trailThicknessMin = 6,
	trailThicknessMax = 18,
	trailFadeDuration = 0.35,
	curveOffsetMin = 25,
	curveOffsetMax = 45,
	burstCount = 22,
	burstSizeMin = 20,
	burstSizeMax = 36,
	burstTravelDuration = 0.7,
	burstDistanceMax = 2.2,
	trailSparkleInterval = 0.05,
	trailSparkleCount = 1,
	trailSparkleSizeMin = 14,
	trailSparkleSizeMax = 24,
	shockwaveCount = 4,
	shockwaveStagger = 0.07,
	shockwaveExpandBase = 2.6,
	shockwaveExpandPerRing = 0.5,
	shockwaveDuration = 0.65,
	shockwaveThickness = 6,
	shockwaveColors = {
		Color3.fromRGB(255, 255, 240),
		Color3.fromRGB(240, 255, 205),
		Color3.fromRGB(215, 245, 160),
		Color3.fromRGB(215, 245, 160),
	},
	orbCount = 8,
	orbRadiusX = 1.05,
	orbRadiusY = 0.45,
	orbSizeScale = 0.18,
	orbSpeed = math.pi * 2.2,
	orbYAngleScale = 1,
	orbZAmp = 0.4,
	orbStrokeColor = Color3.fromRGB(215, 245, 160),
	orbOddIsGlow = true,
})

RARITY_CONFIGS.Secret = makeConfig({
	itemScale = 0.22,
	soundPitch = 0.6,
	soundVolume = 0.85,
	primary = Color3.fromRGB(0, 0, 0),
	secondary = Color3.fromRGB(160, 160, 160),
	glow = Color3.fromRGB(255, 255, 255),
	ringColor = Color3.fromRGB(255, 255, 255),
	shadowColor = Color3.fromRGB(0, 0, 0),
	starColor = Color3.fromRGB(0, 0, 0),
	trailColor = Color3.fromRGB(255, 255, 255),
	starSizeScale = 2.4,
	spinDuration = 1.6,
	popDuration = 0.4,
	holdDuration = 0.8,
	motionDuration = 0.75,
	shadowTransparency = 0.2,
	shadowStartOffset = 5,
	shadowOffsetScale = 0.045,
	shadowOffsetMax = 6,
	trailThicknessScale = 0.32,
	trailThicknessMin = 6,
	trailThicknessMax = 18,
	trailFadeDuration = 0.35,
	curveOffsetMin = 25,
	curveOffsetMax = 45,
	burstCount = 26,
	burstSizeMin = 20,
	burstSizeMax = 36,
	burstTravelDuration = 0.7,
	burstDistanceMax = 2.2,
	trailSparkleInterval = 0.05,
	trailSparkleCount = 1,
	trailSparkleSizeMin = 14,
	trailSparkleSizeMax = 24,
	shockwaveCount = 4,
	shockwaveStagger = 0.07,
	shockwaveExpandBase = 2.6,
	shockwaveExpandPerRing = 0.5,
	shockwaveDuration = 0.65,
	shockwaveThickness = 5,
	shockwaveColors = {
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(0, 0, 0),
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(0, 0, 0),
	},
	orbCount = 8,
	orbRadiusX = 1.05,
	orbRadiusY = 0.45,
	orbSizeScale = 0.18,
	orbSpeed = math.pi * 2.2,
	orbYAngleScale = 1,
	orbZAmp = 0.4,
	orbStrokeColor = Color3.fromRGB(0, 0, 0),
	orbOddIsGlow = true,
	orbAlternateStroke = true,
	flareEntrance = true,
})

local finishPlayback: (playbackId: number) -> ()
local startHoldPhase: (playbackId: number) -> ()
local startMotionPhase: (playbackId: number) -> ()

local function getViewportSize(): Vector2
	local camera = Workspace.CurrentCamera
	if camera then
		return camera.ViewportSize
	end
	return playerGui.AbsoluteSize
end

local function getBezierPoint(t: number, p0: Vector2, p1: Vector2, p2: Vector2): Vector2
	local inv = 1 - t
	return inv * inv * p0 + 2 * inv * t * p1 + t * t * p2
end

local function toParentOffset(absPos: Vector2, parent: GuiObject): Vector2
	return absPos - parent.AbsolutePosition
end

local function trackFrame(state: PlaybackState, guiObject: GuiObject): ()
	guiObject:SetAttribute("PlaybackId", state.playbackId)
	table.insert(state.trackedFrames, guiObject)
end

local function trackDelay(state: PlaybackState, delayThread: thread): ()
	table.insert(state.delayThreads, delayThread)
end

local function asImageLabel(guiObject: GuiObject?): ImageLabel?
	if guiObject and guiObject:IsA("ImageLabel") then
		return guiObject
	end
	return nil
end

local function asFrame(guiObject: GuiObject?): Frame?
	if guiObject and guiObject:IsA("Frame") then
		return guiObject
	end
	return nil
end

local function getConfig(rarity: string): RarityFxConfig
	local config = RARITY_CONFIGS[rarity]
	if config then
		return config
	end

	warn(`[LootPickupFx] No pickup FX config for rarity "{rarity}", using Common`)
	return RARITY_CONFIGS.Common
end

local function resolveSoundTemplate(): Sound?
	return LootPickupFxPool.getPickupSoundTemplate()
end

local function playPickupSound(config: RarityFxConfig): ()
	local template = pickupSoundTemplate
	if template == nil then
		return
	end

	SoundPool.play2DWithVariation(template, config.soundPitch, config.soundVolume)
end

local function disconnectConnection(connection: RBXScriptConnection?): ()
	if connection and connection.Connected then
		connection:Disconnect()
	end
end

finishPlayback = function(playbackId: number)
	local state = playbackStates[playbackId]
	if state == nil or state.phase == PHASE_DONE then
		return
	end

	state.phase = PHASE_DONE
	disconnectConnection(state.holdConnection)
	disconnectConnection(state.motionConnection)
	state.holdConnection = nil
	state.motionConnection = nil

	if state.spinTween then
		state.spinTween:Cancel()
		state.spinTween = nil
	end

	for _, delayThread in state.delayThreads do
		if delayThread ~= coroutine.running() then
			pcall(task.cancel, delayThread)
		end
	end
	table.clear(state.delayThreads)

	for _, guiObject in state.trackedFrames do
		if guiObject:GetAttribute("PlaybackId") == playbackId then
			LootPickupFxPool.release(guiObject)
		end
	end
	table.clear(state.trackedFrames)
	table.clear(state.orbs)

	if state.container:GetAttribute("PlaybackId") == playbackId then
		LootPickupFxPool.release(state.container)
	end
	if state.burstHolder:GetAttribute("PlaybackId") == playbackId then
		LootPickupFxPool.release(state.burstHolder)
	end
	if state.trailHolder:GetAttribute("PlaybackId") == playbackId then
		LootPickupFxPool.release(state.trailHolder)
	end
	playbackStates[playbackId] = nil
end

local function scheduleFinish(playbackId: number): ()
	local state = playbackStates[playbackId]
	if state == nil then
		return
	end

	local delayThread = task.delay(CLEANUP_TRAIL_FADE_BUFFER, function()
		finishPlayback(playbackId)
	end)
	trackDelay(state, delayThread)
end

local function tweenAndRelease(guiObject: GuiObject, tween: Tween, playbackId: number): ()
	tween:Play()
	tween.Completed:Once(function()
		local state = playbackStates[playbackId]
		if state == nil or state.phase == PHASE_DONE then
			LootPickupFxPool.release(guiObject)
			return
		end
		LootPickupFxPool.release(guiObject)
	end)
end

local function playSparkBurst(playbackId: number, centerPos: Vector2, maxRadius: number): ()
	local state = playbackStates[playbackId]
	if state == nil then
		return
	end

	local config = state.config
	local overlay = overlayGui
	if overlay == nil or overlay.Parent == nil then
		return
	end

	for index = 1, config.burstCount do
		local spark = LootPickupFxPool.acquireSpark()
		if spark == nil then
			continue
		end

		trackFrame(state, spark)

		local angle = ((index / config.burstCount) * math.pi * 2) + math.rad(math.random(-15, 15))
		local distance = maxRadius * (math.random(config.burstDistanceMin * 100, config.burstDistanceMax * 100) / 100)
		local sparkSize = math.random(config.burstSizeMin, config.burstSizeMax)
		local sparkColor = if index % 2 == 0 then config.primary else config.glow
		local localCenter = toParentOffset(centerPos, overlay)

		local vLine = asFrame(LootPickupFxPool.getNamedChild(spark, LootPickupFxPool.VLINE_NAME))
		local hLine = asFrame(LootPickupFxPool.getNamedChild(spark, LootPickupFxPool.HLINE_NAME))
		if vLine then
			vLine.BackgroundColor3 = sparkColor
		end
		if hLine then
			hLine.BackgroundColor3 = sparkColor
		end

		spark.Size = UDim2.fromOffset(sparkSize, sparkSize)
		spark.Position = UDim2.fromOffset(localCenter.X, localCenter.Y)
		spark.Rotation = math.random(0, 90)
		spark.ZIndex = 25
		spark.Visible = true
		spark.Parent = state.burstHolder

		local travelInfo = TweenInfo.new(config.burstTravelDuration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
		local tween = TweenService:Create(spark, travelInfo, {
			Position = UDim2.fromOffset(
				localCenter.X + math.cos(angle) * distance,
				localCenter.Y + math.sin(angle) * distance
			),
			Size = UDim2.fromOffset(0, 0),
			Rotation = spark.Rotation + math.random(90, 240),
		})
		tweenAndRelease(spark, tween, playbackId)
	end
end

local function playTrailSparkle(playbackId: number, absPos: Vector2): ()
	local state = playbackStates[playbackId]
	if state == nil then
		return
	end

	local config = state.config
	local overlay = overlayGui
	if overlay == nil or overlay.Parent == nil then
		return
	end

	local spark = LootPickupFxPool.acquireSpark()
	if spark == nil then
		return
	end

	trackFrame(state, spark)

	local sparkSize = math.random(config.trailSparkleSizeMin, config.trailSparkleSizeMax)
	local sparkColor = if math.random(1, 2) == 1 then config.glow else config.primary
	local localPos = toParentOffset(
		Vector2.new(absPos.X + math.random(-16, 16), absPos.Y + math.random(-16, 16)),
		overlay
	)

	local vLine = asFrame(LootPickupFxPool.getNamedChild(spark, LootPickupFxPool.VLINE_NAME))
	local hLine = asFrame(LootPickupFxPool.getNamedChild(spark, LootPickupFxPool.HLINE_NAME))
	if vLine then
		vLine.BackgroundColor3 = sparkColor
	end
	if hLine then
		hLine.BackgroundColor3 = sparkColor
	end

	spark.Size = UDim2.fromOffset(sparkSize, sparkSize)
	spark.Position = UDim2.fromOffset(localPos.X, localPos.Y)
	spark.ZIndex = 25
	spark.Visible = true
	spark.Parent = state.burstHolder

	local tween = TweenService:Create(spark, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromOffset(localPos.X + math.random(-25, 25), localPos.Y + math.random(-30, 10)),
		Size = UDim2.fromOffset(0, 0),
		Rotation = math.random(45, 180),
	})
	tweenAndRelease(spark, tween, playbackId)
end

local function playShockwaveRing(playbackId: number, ringIndex: number, centerPos: Vector2, startSize: number): ()
	local state = playbackStates[playbackId]
	if state == nil or state.phase == PHASE_DONE then
		return
	end

	local config = state.config
	local overlay = overlayGui
	if overlay == nil or overlay.Parent == nil then
		return
	end

	local ring = LootPickupFxPool.acquireRing()
	if ring == nil then
		return
	end

	trackFrame(state, ring)

	local stroke = LootPickupFxPool.getStroke(ring)
	local color = config.shockwaveColors[ringIndex] or config.ringColor
	if stroke then
		stroke.Color = color
		stroke.Thickness = config.shockwaveThickness
		stroke.Transparency = 0
	end

	local localCenter = toParentOffset(centerPos, overlay)
	local startPx = startSize * config.shockwaveStartScale
	local endPx = startSize * (config.shockwaveExpandBase + ringIndex * config.shockwaveExpandPerRing)

	ring.Size = UDim2.fromOffset(startPx, startPx)
	ring.Position = UDim2.fromOffset(localCenter.X, localCenter.Y)
	ring.ZIndex = 15
	ring.Visible = true
	ring.Parent = state.burstHolder

	local expandInfo = TweenInfo.new(config.shockwaveDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(ring, expandInfo, {
		Size = UDim2.fromOffset(endPx, endPx),
	})
	if stroke then
		TweenService:Create(stroke, expandInfo, {
			Transparency = 1,
			Thickness = 1,
		}):Play()
	end
	tweenAndRelease(ring, tween, playbackId)
end

local function playShockwaves(playbackId: number, centerPos: Vector2, startSize: number): ()
	local state = playbackStates[playbackId]
	if state == nil then
		return
	end

	local config = state.config
	for ringIndex = 1, config.shockwaveCount do
		local delaySeconds = (ringIndex - 1) * config.shockwaveStagger
		if delaySeconds <= 0 then
			playShockwaveRing(playbackId, ringIndex, centerPos, startSize)
		else
			local delayThread = task.delay(delaySeconds, function()
				playShockwaveRing(playbackId, ringIndex, centerPos, startSize)
			end)
			trackDelay(state, delayThread)
		end
	end
end

local function playFlareEntrance(playbackId: number, centerPos: Vector2, size: number): ()
	local state = playbackStates[playbackId]
	if state == nil then
		return
	end

	local overlay = overlayGui
	if overlay == nil or overlay.Parent == nil then
		return
	end

	local flash = LootPickupFxPool.acquireFlash()
	if flash then
		trackFrame(state, flash)
		flash.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		flash.BackgroundTransparency = 0.2
		flash.Visible = true
		local flashTween = TweenService:Create(flash, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 1,
		})
		tweenAndRelease(flash, flashTween, playbackId)
	end

	local localCenter = toParentOffset(centerPos, overlay)
	for rayIndex = 1, 2 do
		local flareRay = LootPickupFxPool.acquireFlareRay()
		if flareRay == nil then
			continue
		end

		trackFrame(state, flareRay)
		flareRay.Size = UDim2.fromOffset(size * 6, size * 0.12)
		flareRay.Position = UDim2.fromOffset(localCenter.X, localCenter.Y)
		flareRay.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		flareRay.Rotation = (rayIndex - 1) * 90
		flareRay.ZIndex = 30
		flareRay.Visible = true
		flareRay.Parent = state.burstHolder

		local rayTween = TweenService:Create(flareRay, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Size = UDim2.fromOffset(size * 8, 0),
			Rotation = flareRay.Rotation + 90,
		})
		tweenAndRelease(flareRay, rayTween, playbackId)
	end
end

local function spawnTrailSegment(playbackId: number, lastPos: Vector2, currentPos: Vector2, currentPx: number): ()
	local state = playbackStates[playbackId]
	if state == nil then
		return
	end

	local config = state.config
	local overlay = overlayGui
	if overlay == nil or overlay.Parent == nil then
		return
	end

	local segment = LootPickupFxPool.acquireTrailSegment()
	if segment == nil then
		return
	end

	trackFrame(state, segment)

	local distance = (currentPos - lastPos).Magnitude
	local angle = math.deg(math.atan2(currentPos.Y - lastPos.Y, currentPos.X - lastPos.X))
	local thickness = math.clamp(currentPx * config.trailThicknessScale, config.trailThicknessMin, config.trailThicknessMax)
	local mid = toParentOffset((lastPos + currentPos) / 2, overlay)

	segment.Size = UDim2.new(0, distance, 0, thickness)
	segment.Position = UDim2.fromOffset(mid.X, mid.Y)
	segment.Rotation = angle
	segment.BackgroundColor3 = config.trailColor
	segment.BackgroundTransparency = 0
	segment.ZIndex = 1
	segment.Visible = true
	segment.Parent = state.trailHolder

	local fadeTween = TweenService:Create(segment, TweenInfo.new(config.trailFadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
		Size = UDim2.new(0, distance, 0, 0),
	})
	tweenAndRelease(segment, fadeTween, playbackId)
end

local function getOrbFillColor(config: RarityFxConfig, orbIndex: number): Color3
	if config.orbUseRingAsPrimary then
		return if orbIndex == 1 then config.ringColor else config.glow
	end

	if config.orbOddIsGlow then
		return if orbIndex % 2 == 1 then config.glow else config.primary
	end

	return if orbIndex % 2 == 1 then config.primary else config.glow
end

local function getOrbStrokeColor(config: RarityFxConfig, orbIndex: number): Color3
	if config.orbAlternateStroke then
		return if orbIndex % 2 == 1 then config.primary else config.glow
	end

	return config.orbStrokeColor
end

local function shrinkOrbs(playbackId: number): ()
	local state = playbackStates[playbackId]
	if state == nil then
		return
	end

	for _, orb in state.orbs do
		local shrink = TweenService:Create(orb, TweenInfo.new(0.15), { Size = UDim2.fromOffset(0, 0) })
		tweenAndRelease(orb, shrink, playbackId)
	end
	table.clear(state.orbs)
end

startMotionPhase = function(playbackId: number)
	local state = playbackStates[playbackId]
	if state == nil or state.phase ~= PHASE_HOLD then
		return
	end

	state.phase = PHASE_MOTION

	local overlay = overlayGui
	local counter = backpackCounter
	if overlay == nil or overlay.Parent == nil or counter == nil or counter.Parent == nil then
		finishPlayback(playbackId)
		return
	end

	local config = state.config
	local screenSize = getViewportSize()
	local centerPxSize = screenSize.Y * config.itemScale
	local endPxSize = screenSize.Y * END_SIZE_VIEWPORT_FRACTION

	TweenService:Create(state.starImage, TweenInfo.new(0.2), { ImageTransparency = 1 }):Play()

	local containerAbs = state.container.AbsolutePosition
	local containerSize = state.container.AbsoluteSize
	local startPos = Vector2.new(containerAbs.X + containerSize.X / 2, containerAbs.Y + containerSize.Y / 2)
	local endPos = Vector2.new(
		counter.AbsolutePosition.X + (counter.AbsoluteSize.X / 2),
		counter.AbsolutePosition.Y + (counter.AbsoluteSize.Y / 2)
	)

	local delta = endPos - startPos
	local perpendicular = Vector2.new(1, 0)
	if delta.Magnitude > 0.001 then
		perpendicular = Vector2.new(-delta.Y, delta.X).Unit
	end

	local sideMultiplier = if math.random(1, 2) == 1 then 1 else -1
	local curveOffset = screenSize.Y * (math.random(config.curveOffsetMin, config.curveOffsetMax) / 100) * sideMultiplier
	local backOffset = delta * (math.random(15, 35) / 100)
	local controlPos = (startPos + backOffset) + (perpendicular * curveOffset)

	state.motionStartClock = os.clock()
	state.motionStartPos = startPos
	state.motionControlPos = controlPos
	state.motionCenterPxSize = centerPxSize
	state.motionEndPxSize = endPxSize
	state.motionLastPos = startPos
	state.sparkleTimer = 0

	state.motionConnection = RunService.Heartbeat:Connect(function()
		local current = playbackStates[playbackId]
		if current == nil or current.phase ~= PHASE_MOTION then
			return
		end

		local liveOverlay = overlayGui
		local liveCounter = backpackCounter
		if liveOverlay == nil or liveOverlay.Parent == nil or liveCounter == nil or liveCounter.Parent == nil then
			finishPlayback(playbackId)
			return
		end

		local cfg = current.config
		local elapsed = os.clock() - current.motionStartClock
		local t = math.clamp(elapsed / cfg.motionDuration, 0, 1)
		local easedT = math.sin(t * (math.pi / 2))
		local currentPos = getBezierPoint(easedT, current.motionStartPos, current.motionControlPos, Vector2.new(
			liveCounter.AbsolutePosition.X + (liveCounter.AbsoluteSize.X / 2),
			liveCounter.AbsolutePosition.Y + (liveCounter.AbsoluteSize.Y / 2)
		))
		local currentPx = (1 - easedT) * current.motionCenterPxSize + easedT * current.motionEndPxSize
		local localPos = toParentOffset(currentPos, liveOverlay)

		current.container.Position = UDim2.fromOffset(localPos.X, localPos.Y)
		current.container.Size = UDim2.new(0, currentPx, 0, currentPx)

		local shadowOffset = math.clamp(currentPx * cfg.shadowOffsetScale, 1, cfg.shadowOffsetMax)
		current.itemShadow.Position = UDim2.new(0.5, shadowOffset, 0.5, shadowOffset)

		if (currentPos - current.motionLastPos).Magnitude > 2 then
			spawnTrailSegment(playbackId, current.motionLastPos, currentPos, currentPx)

			if cfg.trailSparkleInterval > 0 and elapsed - current.sparkleTimer > cfg.trailSparkleInterval then
				current.sparkleTimer = elapsed
				for _ = 1, cfg.trailSparkleCount do
					playTrailSparkle(playbackId, currentPos)
				end
				if cfg.trailSparkleExtraChance > 0 and math.random() < cfg.trailSparkleExtraChance then
					playTrailSparkle(playbackId, currentPos)
				end
			end
		end

		current.motionLastPos = currentPos

		if t >= 1 then
			disconnectConnection(current.motionConnection)
			current.motionConnection = nil
			if current.spinTween then
				current.spinTween:Cancel()
				current.spinTween = nil
			end
			if current.container:GetAttribute("PlaybackId") == playbackId then
				LootPickupFxPool.release(current.container)
			end
			scheduleFinish(playbackId)
		end
	end)
end

startHoldPhase = function(playbackId: number)
	local state = playbackStates[playbackId]
	if state == nil or state.phase ~= PHASE_POP then
		return
	end

	state.phase = PHASE_HOLD

	local overlay = overlayGui
	if overlay == nil or overlay.Parent == nil then
		finishPlayback(playbackId)
		return
	end

	local config = state.config
	local screenSize = getViewportSize()
	local centerPxSize = screenSize.Y * config.itemScale
	local centerPos = Vector2.new(screenSize.X / 2, screenSize.Y / 2)
	local localCenter = toParentOffset(centerPos, overlay)
	state.holdStartClock = os.clock()
	state.holdCenterPxSize = centerPxSize

	if config.orbCount > 0 then
		local orbBaseSize = centerPxSize * config.orbSizeScale
		for orbIndex = 1, config.orbCount do
			local orb = LootPickupFxPool.acquireOrb()
			if orb == nil then
				continue
			end

			trackFrame(state, orb)
			table.insert(state.orbs, orb)

			orb.BackgroundColor3 = getOrbFillColor(config, orbIndex)
			local stroke = LootPickupFxPool.getStroke(orb)
			if stroke then
				stroke.Color = getOrbStrokeColor(config, orbIndex)
				stroke.Thickness = 2
				stroke.Transparency = 0
			end

			orb.Size = UDim2.fromOffset(orbBaseSize, orbBaseSize)
			orb.Position = UDim2.fromOffset(localCenter.X, localCenter.Y)
			orb.Visible = true
			orb.Parent = state.burstHolder
		end
	end

	state.holdConnection = RunService.Heartbeat:Connect(function()
		local current = playbackStates[playbackId]
		if current == nil or current.phase ~= PHASE_HOLD then
			return
		end

		local liveOverlay = overlayGui
		if liveOverlay == nil or liveOverlay.Parent == nil then
			finishPlayback(playbackId)
			return
		end

		local cfg = current.config
		local elapsed = os.clock() - current.holdStartClock
		local liveCenter = toParentOffset(Vector2.new(getViewportSize().X / 2, getViewportSize().Y / 2), liveOverlay)
		local angle = elapsed * cfg.orbSpeed
		local holdSize = current.holdCenterPxSize
		local radiusX = holdSize * cfg.orbRadiusX
		local radiusY = holdSize * cfg.orbRadiusY

		for orbIndex, orb in current.orbs do
			local offsetAngle = angle + ((orbIndex - 1) * (math.pi * 2 / math.max(cfg.orbCount, 1)))
			local zScale = cfg.orbZBase + (math.sin(offsetAngle) * cfg.orbZAmp)
			local currentSize = (holdSize * cfg.orbSizeScale) * zScale
			orb.Position = UDim2.fromOffset(
				liveCenter.X + math.cos(offsetAngle) * radiusX,
				liveCenter.Y + math.sin(offsetAngle * cfg.orbYAngleScale) * radiusY
			)
			orb.Size = UDim2.fromOffset(currentSize, currentSize)
			orb.ZIndex = if zScale > 1 then 18 else 8
		end

		if elapsed >= cfg.holdDuration then
			disconnectConnection(current.holdConnection)
			current.holdConnection = nil
			shrinkOrbs(playbackId)
			startMotionPhase(playbackId)
		end
	end)
end

local function playPickup(rarity: string, lootId: string): ()
	local overlay = overlayGui
	if overlay == nil or overlay.Parent == nil then
		return
	end

	if not LootPickupFxPool.initialize() then
		warn("[LootPickupFx] FX pool failed to initialize")
		return
	end

	local config = getConfig(rarity)
	local itemEntry = LootConfig.GetItem(lootId)
	local itemIconId = if itemEntry ~= nil then itemEntry.IconId else ITEM_IMAGE_ID
	local burstHolder = LootPickupFxPool.acquireHolder()
	local trailHolder = LootPickupFxPool.acquireHolder()
	local container = LootPickupFxPool.acquireContainer()
	if burstHolder == nil or trailHolder == nil or container == nil then
		if burstHolder then
			LootPickupFxPool.release(burstHolder)
		end
		if trailHolder then
			LootPickupFxPool.release(trailHolder)
		end
		if container then
			LootPickupFxPool.release(container)
		end
		return
	end

	local starImage = asImageLabel(LootPickupFxPool.getNamedChild(container, LootPickupFxPool.STAR_NAME))
	local itemShadow = asImageLabel(LootPickupFxPool.getNamedChild(container, LootPickupFxPool.SHADOW_NAME))
	local itemImage = asImageLabel(LootPickupFxPool.getNamedChild(container, LootPickupFxPool.ITEM_NAME))
	if starImage == nil or itemShadow == nil or itemImage == nil then
		LootPickupFxPool.release(burstHolder)
		LootPickupFxPool.release(trailHolder)
		LootPickupFxPool.release(container)
		return
	end

	local playbackId = nextPlaybackId()
	burstHolder:SetAttribute("PlaybackId", playbackId)
	trailHolder:SetAttribute("PlaybackId", playbackId)
	container:SetAttribute("PlaybackId", playbackId)

	local zero = Vector2.new(0, 0)
	local state: PlaybackState = {
		playbackId = playbackId,
		config = config,
		container = container,
		burstHolder = burstHolder,
		trailHolder = trailHolder,
		starImage = starImage,
		itemShadow = itemShadow,
		trackedFrames = table.create(32),
		delayThreads = table.create(4),
		orbs = table.create(config.orbCount),
		holdConnection = nil,
		motionConnection = nil,
		spinTween = nil,
		phase = PHASE_POP,
		holdStartClock = 0,
		holdCenterPxSize = 0,
		motionStartClock = 0,
		motionStartPos = zero,
		motionControlPos = zero,
		motionCenterPxSize = 0,
		motionEndPxSize = 0,
		motionLastPos = zero,
		sparkleTimer = 0,
	}
	playbackStates[playbackId] = state

	playPickupSound(config)

	local screenSize = getViewportSize()
	local centerPxSize = screenSize.Y * config.itemScale
	local centerPos = Vector2.new(screenSize.X / 2, screenSize.Y / 2)

	burstHolder.Size = UDim2.new(1, 0, 1, 0)
	burstHolder.ZIndex = 20
	burstHolder.Visible = true
	burstHolder.Parent = overlay

	trailHolder.Size = UDim2.new(1, 0, 1, 0)
	trailHolder.ZIndex = 1
	trailHolder.Visible = true
	trailHolder.Parent = overlay

	starImage.Image = STAR_IMAGE_ID
	starImage.ImageColor3 = config.starColor
	starImage.ImageTransparency = 0
	starImage.Size = UDim2.new(config.starSizeScale, 0, config.starSizeScale, 0)

	itemShadow.Image = itemIconId
	itemShadow.ImageColor3 = config.shadowColor
	itemShadow.ImageTransparency = config.shadowTransparency
	itemShadow.Position = UDim2.new(0.5, config.shadowStartOffset, 0.5, config.shadowStartOffset)

	itemImage.Image = itemIconId
	itemImage.ImageColor3 = Color3.new(1, 1, 1)
	itemImage.ImageTransparency = 0

	container.Size = UDim2.new(0, 0, 0, 0)
	container.Position = UDim2.new(0.5, 0, 0.5, 0)
	container.ZIndex = 10
	container.Visible = true
	container.Parent = overlay

	local spinInfo = TweenInfo.new(config.spinDuration, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1)
	state.spinTween = TweenService:Create(starImage, spinInfo, { Rotation = 360 })
	state.spinTween:Play()

	local popInfo = TweenInfo.new(config.popDuration, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local popTween = TweenService:Create(container, popInfo, {
		Size = UDim2.new(0, centerPxSize, 0, centerPxSize),
	})
	popTween:Play()

	if config.burstCount > 0 then
		playSparkBurst(playbackId, centerPos, centerPxSize * config.burstRadiusScale)
	end
	if config.shockwaveCount > 0 then
		playShockwaves(playbackId, centerPos, centerPxSize)
	end
	if config.flareEntrance then
		playFlareEntrance(playbackId, centerPos, centerPxSize)
	end

	popTween.Completed:Once(function()
		local current = playbackStates[playbackId]
		if current == nil or current.phase ~= PHASE_POP then
			return
		end
		startHoldPhase(playbackId)
	end)
end

local function disconnectHudButtonsWait(): ()
	local connection = hudButtonsAddedConnection
	if connection == nil then
		return
	end

	connection:Disconnect()
	hudButtonsAddedConnection = nil
end

local function wireHudAndRemote(hudButtons: ScreenGui): ()
	if remoteConnected or hudWireStarted then
		return
	end

	hudWireStarted = true
	disconnectHudButtonsWait()

	overlayGui = hudButtons

	local currencyCounters = hudButtons:WaitForChild(CURRENCY_COUNTERS_NAME, UI_WAIT_TIMEOUT)
	if currencyCounters == nil then
		warn(`[LootPickupFx] {CURRENCY_COUNTERS_NAME} not found within {UI_WAIT_TIMEOUT}s`)
		return
	end

	local counter = currencyCounters:WaitForChild(BACKPACK_COUNTER_NAME, UI_WAIT_TIMEOUT)
	if counter == nil or not counter:IsA("GuiObject") then
		warn(`[LootPickupFx] {BACKPACK_COUNTER_NAME} not found within {UI_WAIT_TIMEOUT}s`)
		return
	end

	backpackCounter = counter

	hudButtons.Destroying:Once(function()
		local playbackIds = table.create(4)
		for playbackId in playbackStates do
			table.insert(playbackIds, playbackId)
		end
		for _, playbackId in playbackIds do
			finishPlayback(playbackId)
		end
		overlayGui = nil
		backpackCounter = nil
	end)

	local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME, UI_WAIT_TIMEOUT)
	if remotesFolder == nil then
		warn(`[LootPickupFx] Remotes folder not found within {UI_WAIT_TIMEOUT}s`)
		return
	end

	local lootCollectedRemote = remotesFolder:WaitForChild(LOOT_COLLECTED_REMOTE_NAME, UI_WAIT_TIMEOUT)
	if lootCollectedRemote == nil or not lootCollectedRemote:IsA("RemoteEvent") then
		warn(`[LootPickupFx] {LOOT_COLLECTED_REMOTE_NAME} RemoteEvent not found within {UI_WAIT_TIMEOUT}s`)
		return
	end

	lootCollectedRemote.OnClientEvent:Connect(function(lootId: unknown, rarity: unknown)
		if typeof(lootId) ~= "string" or typeof(rarity) ~= "string" then
			return
		end
		playPickup(rarity, lootId)
	end)
	remoteConnected = true
end

local function onHudButtonsAdded(child: Instance): ()
	if child.Name == HUD_BUTTONS_NAME and child:IsA("ScreenGui") then
		wireHudAndRemote(child)
	end
end

local function initialize(): ()
	if remoteConnected then
		return
	end

	if not game:IsLoaded() then
		game.Loaded:Wait()
	end

	LootPickupFxPool.initialize()
	pickupSoundTemplate = resolveSoundTemplate()

	local existing = playerGui:FindFirstChild(HUD_BUTTONS_NAME)
	if existing and existing:IsA("ScreenGui") then
		wireHudAndRemote(existing)
		return
	end

	hudButtonsAddedConnection = playerGui.ChildAdded:Connect(onHudButtonsAdded)

	local waited = playerGui:WaitForChild(HUD_BUTTONS_NAME, UI_WAIT_TIMEOUT)
	if waited and waited:IsA("ScreenGui") then
		wireHudAndRemote(waited)
		return
	end

	warn(`[LootPickupFx] {HUD_BUTTONS_NAME} ScreenGui not found within {UI_WAIT_TIMEOUT}s; waiting for it to appear`)
end

initialize()

--[[
	SELF-AUDIT (Section 7):
	- LootCollected OnClientEvent:Connect — script-lifetime singleton in wireHudAndRemote(),
	  guarded by remoteConnected. OK.
	- PlayerGui.ChildAdded:Connect — stored in hudButtonsAddedConnection if HUDButtons is
	  missing at load; disconnected in wireHudAndRemote. OK.
	- hudButtons.Destroying:Once — one-shot; finishes remaining playbacks and clears HUD refs. OK.
	- popTween.Completed:Once — starts hold phase or bails if playback already finished. OK.
	- RunService.Heartbeat:Connect (hold/orbit) — stored in playbackStates[playbackId].holdConnection,
	  disconnected when hold ends / HUD gone / finishPlayback; closes over playbackId only. OK.
	- RunService.Heartbeat:Connect (motion) — stored in playbackStates[playbackId].motionConnection,
	  disconnected when t>=1 / HUD gone / finishPlayback; closes over playbackId only. OK.
	- Tween Completed:Once (sparks, trails, rings, orbs, flares, flash) — LootPickupFxPool.release. OK.
	- task.delay (shockwave stagger) — stored in playbackStates[playbackId].delayThreads; finishPlayback skips coroutine.running() and pcall(task.cancel) for finished threads. OK.
	- task.delay (cleanup buffer after motion) — same delayThreads list; the running cleanup thread is not cancelled. OK.
	- SoundPool.play2DWithVariation — Ended:Once release inside SoundPool. OK.
	- PlaybackId attribute on acquired frames — finishPlayback only releases instances still owned by that playbackId. OK.
	- No Instance.new() / :Destroy() in this script; all HUD FX instances from LootPickupFxPool. OK.
	- No while-true polling; hold and motion are Heartbeat-driven. OK.
]]
