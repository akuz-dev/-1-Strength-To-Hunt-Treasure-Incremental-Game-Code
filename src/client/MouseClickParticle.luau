--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local MouseClickParticlePool = require(script.Parent.MouseClickParticlePool)

local PARTICLE_TEMPLATE_NAME = "mouseParticle"
local OVERLAY_GUI_NAME = "MouseParticleScreenGui"
local OVERLAY_DISPLAY_ORDER = 999990
local PLAYER_GUI_WAIT_TIMEOUT = 5
local TEMPLATE_WAIT_TIMEOUT = 5

local TWEEN_TIME = 0.12
local TARGET_SIZE = UDim2.fromOffset(50, 50)
local START_SIZE = UDim2.fromOffset(0, 0)
local TWEEN_INFO = TweenInfo.new(TWEEN_TIME, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
local FADE_GOAL = {
	ImageTransparency = 1,
	Size = TARGET_SIZE,
}

local player = Players.LocalPlayer
local overlayGui: ScreenGui? = nil
local ready = false

local function resolveOverlayGui(): ScreenGui?
	local playerGui = player:WaitForChild("PlayerGui", PLAYER_GUI_WAIT_TIMEOUT)
	if playerGui == nil or not playerGui:IsA("PlayerGui") then
		warn(`[MouseClickParticle] PlayerGui not found within {PLAYER_GUI_WAIT_TIMEOUT}s`)
		return nil
	end

	local existing = playerGui:FindFirstChild(OVERLAY_GUI_NAME)
	if existing and existing:IsA("ScreenGui") then
		existing.DisplayOrder = OVERLAY_DISPLAY_ORDER
		existing.IgnoreGuiInset = true
		existing.ResetOnSpawn = false
		return existing
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = OVERLAY_GUI_NAME
	screenGui.DisplayOrder = OVERLAY_DISPLAY_ORDER
	screenGui.IgnoreGuiInset = true
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui
	return screenGui
end

local function resolveParticleTemplate(): ImageLabel?
	local template = ReplicatedStorage:WaitForChild(PARTICLE_TEMPLATE_NAME, TEMPLATE_WAIT_TIMEOUT)
	if template == nil then
		warn(`[MouseClickParticle] {PARTICLE_TEMPLATE_NAME} not found within {TEMPLATE_WAIT_TIMEOUT}s`)
		return nil
	end

	if not template:IsA("ImageLabel") then
		warn(`[MouseClickParticle] {PARTICLE_TEMPLATE_NAME} must be an ImageLabel`)
		return nil
	end

	return template
end

local function ensureReady(): boolean
	if ready then
		return true
	end

	local gui = resolveOverlayGui()
	if gui == nil then
		return false
	end

	local template = resolveParticleTemplate()
	if template == nil then
		return false
	end

	overlayGui = gui
	MouseClickParticlePool.initialize(template)
	ready = true
	return true
end

local function resolveScreenPosition(input: InputObject): Vector2
	if input.UserInputType == Enum.UserInputType.Touch then
		return Vector2.new(input.Position.X, input.Position.Y)
	end

	return UserInputService:GetMouseLocation()
end

local function play(screenPos: Vector2): ()
	if not ensureReady() then
		return
	end

	local parentGui = overlayGui
	if parentGui == nil then
		return
	end

	local particle = MouseClickParticlePool.acquire()
	if particle == nil then
		return
	end

	particle.Position = UDim2.fromOffset(screenPos.X, screenPos.Y)
	particle.Size = START_SIZE
	particle.ImageTransparency = 0
	particle.Visible = true
	particle.Parent = parentGui

	local fadeTween = TweenService:Create(particle, TWEEN_INFO, FADE_GOAL)
	MouseClickParticlePool.setFadeTween(particle, fadeTween)
	fadeTween:Play()

	fadeTween.Completed:Once(function()
		if particle.ImageTransparency >= 0.99 then
			MouseClickParticlePool.release(particle)
		end
	end)
end

local function playFromInput(input: InputObject): ()
	play(resolveScreenPosition(input))
end

return {
	play = play,
	playFromInput = playFromInput,
}

--[[
	SELF-AUDIT (Section 7):
	- Instance.new("ScreenGui") overlay — once in resolveOverlayGui when Studio gui absent. OK.
	- Pooled ImageLabel particles cloned from ReplicatedStorage.mouseParticle via pool; no hot-path Instance.new. OK.
	- Tween Completed:Once → pool release; no polling loops. OK.
]]
