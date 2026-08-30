--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local MUSIC_PATH = { "Assets", "Sounds", "BackgroundMusic" }
local WAIT_TIMEOUT = 5
local LOAD_TIMEOUT = 8

local function collectAndSortSounds(folder: Folder): { Sound }
	local templates: { Sound } = {}
	for _, child in folder:GetChildren() do
		if child:IsA("Sound") then
			table.insert(templates, child)
		end
	end

	table.sort(templates, function(a: Sound, b: Sound): boolean
		return a.Name < b.Name
	end)

	return templates
end

local function resolveMusicTemplates(): { Sound }?
	local current: Instance = ReplicatedStorage
	for _, childName in MUSIC_PATH do
		local child = current:WaitForChild(childName, WAIT_TIMEOUT)
		if child == nil then
			warn("[BackgroundMusic] Not found at ReplicatedStorage.Assets.Sounds.BackgroundMusic")
			return nil
		end
		current = child
	end

	if current:IsA("Folder") then
		return collectAndSortSounds(current)
	end

	if current:IsA("Sound") then
		warn(
			"[BackgroundMusic] BackgroundMusic is still a single Sound in Studio. "
				.. "Delete ReplicatedStorage.Assets.Sounds.BackgroundMusic, then re-sync Rojo to enable multi-track shuffle."
		)
		return { current }
	end

	warn("[BackgroundMusic] BackgroundMusic must be a Folder of Sound tracks")
	return nil
end

local function buildShuffledDeck(trackCount: number, avoidFirst: number?): { number }
	local deck: { number } = table.create(trackCount)
	for index = 1, trackCount do
		deck[index] = index
	end

	for index = trackCount, 2, -1 do
		local swapIndex = math.random(1, index)
		deck[index], deck[swapIndex] = deck[swapIndex], deck[index]
	end

	if avoidFirst ~= nil and trackCount > 1 and deck[1] == avoidFirst then
		deck[1], deck[2] = deck[2], deck[1]
	end

	return deck
end

local function applyTemplate(player: Sound, template: Sound): ()
	player.SoundId = template.SoundId
	player.Volume = template.Volume
	player.PlaybackSpeed = template.PlaybackSpeed
	player.RollOffMode = template.RollOffMode
	player.Looped = false
end

local function waitForLoadThenPlay(
	music: Sound,
	templateName: string,
	onReady: () -> (),
	onFailed: () -> ()
): ()
	if music.IsLoaded and music.TimeLength > 0 then
		onReady()
		return
	end

	local finished = false

	local function finishFailed(): ()
		if finished then
			return
		end
		finished = true
		warn(`[BackgroundMusic] Skipping track "{templateName}" — failed to load (check SoundId)`)
		onFailed()
	end

	music.Loaded:Once(function()
		if finished then
			return
		end
		finished = true
		if music.TimeLength > 0 then
			onReady()
		else
			finishFailed()
		end
	end)

	task.delay(LOAD_TIMEOUT, function()
		if not finished and not music.IsLoaded then
			finishFailed()
		end
	end)
end

local templates = resolveMusicTemplates()
if templates == nil then
	return
end

if #templates == 0 then
	warn("[BackgroundMusic] No Sound tracks found in BackgroundMusic folder")
	return
end

local player = templates[1]:Clone()
player.Name = "BackgroundMusic"
player.Looped = false
player.Parent = SoundService

local deck = buildShuffledDeck(#templates, nil)
local deckIndex = 1
local lastPlayedIndex: number? = nil

local playCurrent: () -> ()

local function moveToNextTrack(countAsPlayed: boolean): ()
	if countAsPlayed then
		lastPlayedIndex = deck[deckIndex]
	end

	deckIndex += 1
	if deckIndex > #deck then
		deck = buildShuffledDeck(#templates, lastPlayedIndex)
		deckIndex = 1
	end
	playCurrent()
end

playCurrent = function()
	local templateIndex = deck[deckIndex]
	local template = templates[templateIndex]

	player:Stop()
	applyTemplate(player, template)

	waitForLoadThenPlay(
		player,
		template.Name,
		function()
			player:Play()
			player.Ended:Once(function()
				moveToNextTrack(true)
			end)
		end,
		function()
			moveToNextTrack(false)
		end
	)
end

playCurrent()

--[[
	SELF-AUDIT (Section 7):
	- player.Ended:Once per successfully loaded track — self-cleaning, chains to next shuffled track. OK.
	- Loaded:Once + one-shot task.delay timeout for failed assets — no polling loops. OK.
	- Single player:Clone() at startup — permanent BGM instance, not per-track churn. OK.
	- Shuffle deck rebuilt only when deck exhausted — not every frame. OK.
	- No server involvement, no long-lived :Connect(). OK.
]]
