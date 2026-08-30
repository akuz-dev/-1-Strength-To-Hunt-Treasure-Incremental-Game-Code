--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundPool = require(script.Parent.SoundPool)
local VfxPlayer = require(script.Parent.VfxPlayer)

local SOUND_WAIT_TIMEOUT = 5
local LEVEL_UP_SOUND_PATH = { "Assets", "Sounds", "LevelUp" }

local player = Players.LocalPlayer

local levelUpSoundTemplate: Sound? = nil

local function resolveLevelUpSound(): Sound?
	if levelUpSoundTemplate then
		return levelUpSoundTemplate
	end

	local current: Instance = ReplicatedStorage
	for _, childName in LEVEL_UP_SOUND_PATH do
		local child = current:WaitForChild(childName, SOUND_WAIT_TIMEOUT)
		if child == nil then
			warn(`[PlayerVfx] Sound path missing "{childName}" within {SOUND_WAIT_TIMEOUT}s`)
			return nil
		end
		current = child
	end

	if not current:IsA("Sound") then
		warn("[PlayerVfx] LevelUp sound asset is not a Sound")
		return nil
	end

	levelUpSoundTemplate = current
	return levelUpSoundTemplate
end

local function playLevelUpSound(): ()
	local template = resolveLevelUpSound()
	if template == nil then
		return
	end

	SoundPool.play2D(template)
end

local lastLevel = if typeof(player:GetAttribute("Level")) == "number"
	then player:GetAttribute("Level") :: number
	else 0
local lastRebirths = if typeof(player:GetAttribute("Rebirths")) == "number"
	then player:GetAttribute("Rebirths") :: number
	else 0

local function playOnCharacterWhenReady(vfxName: string): ()
	local character = player.Character
	if character then
		VfxPlayer.playOnCharacter(vfxName, character)
		return
	end

	local userId = player.UserId
	local connection: RBXScriptConnection? = nil
	connection = player.CharacterAdded:Connect(function(addedCharacter: Model)
		if connection then
			connection:Disconnect()
			connection = nil
		end

		if player.UserId ~= userId then
			return
		end

		VfxPlayer.playOnCharacter(vfxName, addedCharacter)
	end)
end

player:GetAttributeChangedSignal("Level"):Connect(function()
	local newLevel = player:GetAttribute("Level")
	if typeof(newLevel) ~= "number" then
		return
	end

	if newLevel > lastLevel then
		playLevelUpSound()
		playOnCharacterWhenReady("LevelUp")
	end

	lastLevel = newLevel
end)

player:GetAttributeChangedSignal("Rebirths"):Connect(function()
	local newRebirths = player:GetAttribute("Rebirths")
	if typeof(newRebirths) ~= "number" then
		return
	end

	if newRebirths > lastRebirths then
		playOnCharacterWhenReady("Rebirth")
	end

	lastRebirths = newRebirths
end)

--[[
	SELF-AUDIT (Section 7):
	- GetAttributeChangedSignal Level/Rebirths — player-lifetime singleton connections. OK.
	- CharacterAdded:Connect — one-shot via immediate Disconnect inside handler. OK.
	- Closure holds userId (number), not Player instance, for CharacterAdded guard. OK.
	- No polling loops. OK.
	- LevelUp sound — SoundPool.play2D; Ended:Once release inside SoundPool. OK.
]]
