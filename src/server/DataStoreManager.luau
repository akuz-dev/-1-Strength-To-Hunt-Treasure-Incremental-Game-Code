--!strict
-- src/server/DataStoreManager.luau
--
-- Owns all DataStore read/write traffic. Nothing else in the codebase
-- should call DataStoreService directly — route through here so retry
-- logic, migration, and idempotency stay in one place (GDD Section 5
-- "single source of truth" pattern, same reasoning as Section 2.6's
-- single ProcessReceipt handler).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerDataSchema = require(ReplicatedStorage.Shared.PlayerDataSchema)
local PlayerDataService = require(ReplicatedStorage.Shared.PlayerDataService)

type PlayerData = PlayerDataSchema.PlayerData

local PLAYER_STORE_NAME = "PlayerData_v1" -- bump this if you ever need a hard data wipe
local playerStore = DataStoreService:GetDataStore(PLAYER_STORE_NAME)

local MAX_RETRIES = 5
local BASE_BACKOFF_SECONDS = 1
local AUTOSAVE_INTERVAL_SECONDS = 120

local started = false

-- Fired with (player, data) once a player's save has been loaded and
-- merged into PlayerDataService. Gate character spawn / stat UI on this
-- instead of assuming data is ready immediately on PlayerAdded.
local PlayerDataLoaded = Instance.new("BindableEvent")
local PlayerDataSaved = Instance.new("BindableEvent")
local DataStoreManagerEvents = {
	PlayerDataLoaded = PlayerDataLoaded,
	PlayerDataSaved = PlayerDataSaved,
}

-- Section 7.2A: keyed by userId, never by Player instance, so these
-- tables never keep a departed player's Instance reachable.
local saveInProgress: { [number]: boolean } = {}
local autosaveActive: { [number]: boolean } = {}
-- Fired when an in-flight save for userId finishes; leave-save waits on this
-- instead of polling saveInProgress (GDD Section 5.2 signal-driven).
local activeSaveDone: { [number]: BindableEvent } = {}

local function retryAsync<T...>(description: string, fn: (T...) -> any, ...: T...): (boolean, any)
	local args = { ... }
	local lastError: any = nil

	for attempt = 1, MAX_RETRIES do
		local ok, result = pcall(fn, table.unpack(args))
		if ok then
			return true, result
		end

		lastError = result
		warn(string.format("[DataStoreManager] %s failed (attempt %d/%d): %s", description, attempt, MAX_RETRIES, tostring(result)))

		if attempt < MAX_RETRIES then
			local jitter = 0.5 + math.random()
			local backoff = BASE_BACKOFF_SECONDS * (2 ^ (attempt - 1)) * jitter
			task.wait(backoff)
		end
	end

	warn(string.format("[DataStoreManager] %s permanently failed after %d attempts: %s", description, MAX_RETRIES, tostring(lastError)))
	return false, lastError
end

local function loadPlayerData(player: Player): PlayerData
	local key = "Player_" .. player.UserId

	local ok, result = retryAsync("GetAsync(" .. key .. ")", function()
		return playerStore:GetAsync(key)
	end)

	if not ok then
		warn(string.format("[DataStoreManager] Falling back to default data for %s after load failure", player.Name))
		return PlayerDataSchema.CloneDefaults()
	end

	if result == nil then
		return PlayerDataSchema.CloneDefaults()
	end

	local okMigrate, migrated = pcall(PlayerDataSchema.Migrate, result)
	if not okMigrate then
		warn(string.format("[DataStoreManager] Corrupt save detected for %s, resetting to defaults: %s", player.Name, tostring(migrated)))
		return PlayerDataSchema.CloneDefaults()
	end

	return migrated
end

local function savePlayerDataForPlayer(player: Player, userId: number): boolean
	if saveInProgress[userId] then
		return false
	end

	if PlayerDataService.GetData(player) == nil then
		return false
	end

	saveInProgress[userId] = true
	local saveDone = Instance.new("BindableEvent")
	activeSaveDone[userId] = saveDone
	local key = "Player_" .. userId

	local ok = retryAsync("UpdateAsync(" .. key .. ")", function()
		print("[DEBUG] Attempting save for", userId)

		local memoryData = PlayerDataService.GetData(player)
		if memoryData == nil then
			error("[DataStoreManager] No in-memory data before UpdateAsync")
		end

		memoryData.SaveVersion += 1
		PlayerDataService.SetData(player, memoryData)

		playerStore:UpdateAsync(key, function(storedValue: any): any
			local currentMemory = PlayerDataService.GetData(player)
			if currentMemory == nil then
				error("[DataStoreManager] No in-memory data inside UpdateAsync transform")
			end

			if storedValue ~= nil and type(storedValue) == "table" then
				local storedVersion = storedValue.SaveVersion
				if type(storedVersion) == "number" and storedVersion >= currentMemory.SaveVersion then
					warn(string.format(
						"[DataStoreManager] Stored save for userId %d has SaveVersion %d >= in-memory %d; keeping stored data (multi-server conflict)",
						userId,
						storedVersion,
						currentMemory.SaveVersion
					))
					return storedValue
				end
			end

			return currentMemory
		end)
	end)

	saveInProgress[userId] = nil
	activeSaveDone[userId] = nil
	saveDone:Fire()
	saveDone:Destroy()
	return ok
end

local function savePlayerDataByUserId(userId: number): boolean
	local player = Players:GetPlayerByUserId(userId)
	if player == nil then
		return false
	end

	return savePlayerDataForPlayer(player, userId)
end

local function waitForSaveInProgress(userId: number)
	local saveDone = activeSaveDone[userId]
	if saveDone == nil then
		return
	end
	saveDone.Event:Wait()
end

local function startAutosaveLoop(userId: number)
	autosaveActive[userId] = true

	task.spawn(function()
		while autosaveActive[userId] do
			task.wait(AUTOSAVE_INTERVAL_SECONDS)
			if not autosaveActive[userId] then
				break
			end
			local currentPlayer = Players:GetPlayerByUserId(userId)
			if currentPlayer == nil then
				break
			end
			savePlayerDataByUserId(userId)
		end
	end)
end

local function onPlayerAdded(player: Player)
	local data = loadPlayerData(player)
	PlayerDataService.SetData(player, data)

	PlayerDataLoaded:Fire(player, data)
	startAutosaveLoop(player.UserId)
end

local function onPlayerRemoving(player: Player)
	print("[DEBUG] onPlayerRemoving fired for", player.Name)

	local userId = player.UserId
	autosaveActive[userId] = nil
	waitForSaveInProgress(userId)
	savePlayerDataForPlayer(player, userId)
	PlayerDataSaved:Fire(player)
end

local function start()
	if started then
		return
	end
	started = true

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	game:BindToClose(function()
		if RunService:IsStudio() then
			return
		end

		local players = Players:GetPlayers()
		local remaining = #players

		if remaining == 0 then
			return
		end

		for _, player in players do
			local userId = player.UserId
			task.spawn(function()
				savePlayerDataByUserId(userId)
				remaining -= 1
			end)
		end

		while remaining > 0 do
			task.wait(0.1)
		end
	end)

	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

start()

--[[
	SELF-AUDIT (Section 7.3):
	- Players.PlayerAdded:Connect (onPlayerAdded) — permanent, game-lifetime
	  listener, never disconnected by design. OK (same category as other
	  top-level PlayerAdded/PlayerRemoving hooks elsewhere in the codebase).
	- Players.PlayerRemoving:Connect (onPlayerRemoving) — permanent,
	  game-lifetime listener. OK, same reasoning.
	- task.spawn autosave loop (startAutosaveLoop) — closes over userId
	  only, not Player; re-resolves via Players:GetPlayerByUserId() each
	  tick; self-terminates when autosaveActive[userId] is cleared in
	  onPlayerRemoving or when the player can no longer be resolved. OK.
	- task.spawn per-player save in BindToClose — one-shot, closes over
	  userId only, no long-lived capture; server is tearing down
	  immediately after regardless. OK.
	- Instance.new("BindableEvent") (PlayerDataLoaded, PlayerDataSaved) —
	  single instances created once at module load, held for the server's
	  lifetime as the module's public event surface. Not a hot path. OK.
	- waitForSaveInProgress in onPlayerRemoving — blocks on activeSaveDone
	  BindableEvent.Event:Wait(), not a polling loop on saveInProgress. OK.
	- savePlayerDataForPlayer(player, userId) — used from onPlayerRemoving
	  only; takes the live player from the synchronous handler (same frame,
	  not a stored/deferred closure). GetData snapshots inside the retry
	  callback use that player directly — no GetPlayerByUserId re-resolve.
	  OK.
	- savePlayerDataByUserId(userId) — thin wrapper for deferred call sites
	  (autosave loop, BindToClose); re-resolves via GetPlayerByUserId at
	  call time, then delegates to savePlayerDataForPlayer. OK.
	- activeSaveDone BindableEvent — created per save attempt, fired and
	  destroyed when save completes; one-shot leave-save waiter. OK.
	- PlayerDataSaved:Fire in onPlayerRemoving — fires only after leave
	  save attempt completes; PlayerDataManager clears in-memory data on
	  this signal so cleanup never races ahead of the leave save. OK.
	- UpdateAsync transform (savePlayerDataForPlayer) — closes over player
	  and userId from savePlayerDataForPlayer parameters only (7.2A); pure
	  SaveVersion comparison and data return, no Instance access or mutation.
	  OK.
	- UpdateAsync snapshot — SaveVersion increment and GetData run inside
	  the retry callback before each UpdateAsync attempt, not before
	  retryAsync yields, so concurrent SetField mutations are included in
	  the written blob. OK.
	- saveInProgress / autosaveActive tables — keyed by number (userId),
	  not Player. Both fully delete their key (= nil) on completion/
	  teardown rather than setting false, so no departed userId lingers.
]]

return {
	PlayerDataLoaded = PlayerDataLoaded,
	PlayerDataSaved = PlayerDataSaved,
	SavePlayerData = function(player: Player): boolean
		return savePlayerDataByUserId(player.UserId)
	end,
}
