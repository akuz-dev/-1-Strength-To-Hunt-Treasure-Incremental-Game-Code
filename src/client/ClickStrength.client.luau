--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local ClickEffect = require(script.Parent.ClickEffect)
local MouseClickParticle = require(script.Parent.MouseClickParticle)

local REMOTES_FOLDER_NAME = "Remotes"
local CLICK_STRENGTH_REMOTE_NAME = "ClickStrength"
local REMOTE_WAIT_TIMEOUT = 5

local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME, REMOTE_WAIT_TIMEOUT)
if remotesFolder == nil then
	warn(`[ClickStrength] Remotes folder not found within {REMOTE_WAIT_TIMEOUT}s`)
	return
end

local clickStrengthRemote = remotesFolder:WaitForChild(CLICK_STRENGTH_REMOTE_NAME, REMOTE_WAIT_TIMEOUT)
if clickStrengthRemote == nil or not clickStrengthRemote:IsA("RemoteEvent") then
	warn(`[ClickStrength] ClickStrength RemoteEvent not found within {REMOTE_WAIT_TIMEOUT}s`)
	return
end

local function onInputBegan(input: InputObject, gameProcessedEvent: boolean): ()
	if gameProcessedEvent then
		return
	end

	local isClickInput = input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch

	if not isClickInput then
		return
	end

	MouseClickParticle.playFromInput(input)
	ClickEffect.play(input.Position)
	clickStrengthRemote:FireServer()
end

UserInputService.InputBegan:Connect(onInputBegan)

--[[
	SELF-AUDIT (Section 7):
	- UserInputService.InputBegan:Connect — script-lifetime singleton; fires ClickStrength
	  remote and client VFX only, no Instance capture beyond LocalPlayer services. OK.
	- MouseClickParticle.play / ClickEffect.play — pooled client VFX, no local Instance churn. OK.
]]
