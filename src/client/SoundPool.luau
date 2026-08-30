--!strict

--[[
	Section 6 pool for one-shot impact/break sounds.
	Instance.new/Clone churn is confined to warm-up; runtime play cycles acquire/release.
]]

local SoundService = game:GetService("SoundService")

local POOL_SIZE = 4
local STORAGE_FOLDER_NAME = "SoundPoolStorage"

local storageFolder = Instance.new("Folder")
storageFolder.Name = STORAGE_FOLDER_NAME
storageFolder.Parent = script

type PooledSoundEntry = {
	sound: Sound,
	inUse: boolean,
}

local poolsByTemplate: { [Sound]: { PooledSoundEntry } } = {}

local function getOrCreatePool(template: Sound): { PooledSoundEntry }
	local pool = poolsByTemplate[template]
	if pool == nil then
		pool = {}
		poolsByTemplate[template] = pool

		for _ = 1, POOL_SIZE do
			local sound = template:Clone()
			sound.Parent = storageFolder
			table.insert(pool, {
				sound = sound,
				inUse = false,
			})
		end
	end

	return pool
end

local function acquire(template: Sound): Sound?
	local pool = getOrCreatePool(template)

	for _, entry in pool do
		if not entry.inUse then
			entry.inUse = true
			return entry.sound
		end
	end

	local sound = template:Clone()
	sound.Parent = storageFolder
	table.insert(pool, {
		sound = sound,
		inUse = true,
	})

	return sound
end

local function release(sound: Sound): ()
	sound:Stop()
	sound.Parent = storageFolder

	for template, pool in poolsByTemplate do
		for _, entry in pool do
			if entry.sound == sound then
				sound.PlaybackSpeed = template.PlaybackSpeed
				sound.Volume = template.Volume
				entry.inUse = false
				return
			end
		end
	end
end

local function playAt(template: Sound, parent: Instance): ()
	local sound = acquire(template)
	if sound == nil then
		return
	end

	sound.Parent = parent
	sound:Play()
	sound.Ended:Once(function()
		release(sound)
	end)
end

local function play2D(template: Sound): ()
	local sound = acquire(template)
	if sound == nil then
		return
	end

	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		release(sound)
	end)
end

local function play2DWithPlaybackSpeed(template: Sound, playbackSpeed: number): ()
	local sound = acquire(template)
	if sound == nil then
		return
	end

	sound.PlaybackSpeed = playbackSpeed
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		release(sound)
	end)
end

local function play2DWithVariation(template: Sound, playbackSpeed: number, volume: number): ()
	local sound = acquire(template)
	if sound == nil then
		return
	end

	sound.PlaybackSpeed = playbackSpeed
	sound.Volume = volume
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		release(sound)
	end)
end

return {
	playAt = playAt,
	play2D = play2D,
	play2DWithPlaybackSpeed = play2DWithPlaybackSpeed,
	play2DWithVariation = play2DWithVariation,
}
