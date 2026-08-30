--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StatUpgradeConfig = require(ReplicatedStorage.Shared.StatUpgradeConfig)
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)

local DIG_ANIMATION_FADE_TIME = 0.1

type CharacterAnimationState = {
	digTrack: AnimationTrack?,
	weaponId: string?,
	isDigging: boolean,
	pendingStopAfterCycle: boolean,
	didLoopConnection: RBXScriptConnection?,
	equippedWeaponConnection: RBXScriptConnection?,
	isDiggingConnection: RBXScriptConnection?,
	agilityConnection: RBXScriptConnection?,
}

local animationStateByCharacter: { [Model]: CharacterAnimationState } = {}

local function getAnimator(character: Model): Animator?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return nil
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		return animator
	end

	local newAnimator = Instance.new("Animator")
	newAnimator.Parent = humanoid
	return newAnimator
end

local function resolveWeaponId(player: Player): string
	local equippedWeaponId = player:GetAttribute("EquippedWeaponId")
	if typeof(equippedWeaponId) == "string" and equippedWeaponId ~= "" then
		return equippedWeaponId
	end

	return WeaponConfig.GetDefaultWeaponId()
end

local function resolveAgilityLevel(player: Player): number
	local agilityLevel = player:GetAttribute("AgilityLevel")
	if typeof(agilityLevel) == "number" then
		return agilityLevel
	end

	return 0
end

local function resolveIsDigging(player: Player): boolean
	return player:GetAttribute("IsDigging") == true
end

local function getDigAnimationSpeed(track: AnimationTrack, agilityLevel: number): number
	local tickInterval = StatUpgradeConfig.GetDamageTickInterval(agilityLevel)
	if tickInterval <= 0 then
		return 1
	end

	local animLength = track.Length
	if animLength > 0 then
		return animLength / tickInterval
	end

	return StatUpgradeConfig.GetDamageTickInterval(0) / tickInterval
end

local function applyDigTrackSpeed(track: AnimationTrack, agilityLevel: number): ()
	track:AdjustSpeed(getDigAnimationSpeed(track, agilityLevel))
end

local function disconnectDidLoopConnection(state: CharacterAnimationState): ()
	if state.didLoopConnection then
		state.didLoopConnection:Disconnect()
		state.didLoopConnection = nil
	end
end

local function stopDigAnimationImmediate(state: CharacterAnimationState): ()
	state.pendingStopAfterCycle = false
	if state.digTrack and state.digTrack.IsPlaying then
		state.digTrack:Stop(DIG_ANIMATION_FADE_TIME)
	end
	state.isDigging = false
end

local function bindDigTrackDidLoop(state: CharacterAnimationState): ()
	disconnectDidLoopConnection(state)

	local digTrack = state.digTrack
	if digTrack == nil then
		return
	end

	state.didLoopConnection = digTrack.DidLoop:Connect(function()
		if not state.pendingStopAfterCycle then
			return
		end

		stopDigAnimationImmediate(state)
	end)
end

local function clearCharacterAnimationState(character: Model): ()
	local state = animationStateByCharacter[character]
	if state == nil then
		return
	end

	if state.equippedWeaponConnection then
		state.equippedWeaponConnection:Disconnect()
		state.equippedWeaponConnection = nil
	end

	if state.isDiggingConnection then
		state.isDiggingConnection:Disconnect()
		state.isDiggingConnection = nil
	end

	if state.agilityConnection then
		state.agilityConnection:Disconnect()
		state.agilityConnection = nil
	end

	disconnectDidLoopConnection(state)

	if state.digTrack then
		state.digTrack:Stop(DIG_ANIMATION_FADE_TIME)
		state.digTrack:Destroy()
		state.digTrack = nil
	end

	animationStateByCharacter[character] = nil
end

local function loadDigTrack(character: Model, player: Player): AnimationTrack?
	local weaponId = resolveWeaponId(player)
	local weaponDef = WeaponConfig.GetWeapon(weaponId)
	if weaponDef == nil then
		return nil
	end

	if weaponDef.DigAnimationId == "rbxassetid://0" then
		return nil
	end

	local animator = getAnimator(character)
	if animator == nil then
		return nil
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = weaponDef.DigAnimationId

	local track = animator:LoadAnimation(animation)
	animation:Destroy()

	track.Looped = true
	track.Priority = Enum.AnimationPriority.Action
	applyDigTrackSpeed(track, resolveAgilityLevel(player))

	return track
end

local function stopDigAnimation(state: CharacterAnimationState): ()
	local digTrack = state.digTrack
	if digTrack and digTrack.IsPlaying then
		state.pendingStopAfterCycle = true
		return
	end

	stopDigAnimationImmediate(state)
end

local function startDigAnimation(player: Player, state: CharacterAnimationState): ()
	local digTrack = state.digTrack
	if digTrack == nil then
		return
	end

	state.pendingStopAfterCycle = false
	applyDigTrackSpeed(digTrack, resolveAgilityLevel(player))

	if not digTrack.IsPlaying then
		digTrack:Play(DIG_ANIMATION_FADE_TIME)
	end

	state.isDigging = true
end

local function syncDigAnimationPlayback(player: Player, character: Model, state: CharacterAnimationState): ()
	local shouldDig = resolveIsDigging(player)
	if shouldDig then
		startDigAnimation(player, state)
	else
		stopDigAnimation(state)
	end
end

local function reloadDigTrack(player: Player, character: Model, state: CharacterAnimationState): ()
	local wasDigging = state.isDigging

	disconnectDidLoopConnection(state)
	state.pendingStopAfterCycle = false

	if state.digTrack then
		state.digTrack:Stop(0)
		state.digTrack:Destroy()
		state.digTrack = nil
	end

	state.weaponId = resolveWeaponId(player)
	state.digTrack = loadDigTrack(character, player)
	bindDigTrackDidLoop(state)

	if wasDigging or resolveIsDigging(player) then
		startDigAnimation(player, state)
	else
		stopDigAnimation(state)
	end
end

local function bindCharacterWeaponAnimation(player: Player, character: Model): ()
	clearCharacterAnimationState(character)

	local state: CharacterAnimationState = {
		digTrack = loadDigTrack(character, player),
		weaponId = resolveWeaponId(player),
		isDigging = false,
		pendingStopAfterCycle = false,
		didLoopConnection = nil,
		equippedWeaponConnection = nil,
		isDiggingConnection = nil,
		agilityConnection = nil,
	}

	bindDigTrackDidLoop(state)

	state.equippedWeaponConnection = player:GetAttributeChangedSignal("EquippedWeaponId"):Connect(function()
		reloadDigTrack(player, character, state)
	end)

	state.isDiggingConnection = player:GetAttributeChangedSignal("IsDigging"):Connect(function()
		syncDigAnimationPlayback(player, character, state)
	end)

	state.agilityConnection = player:GetAttributeChangedSignal("AgilityLevel"):Connect(function()
		local digTrack = state.digTrack
		if digTrack then
			applyDigTrackSpeed(digTrack, resolveAgilityLevel(player))
		end
	end)

	animationStateByCharacter[character] = state
	syncDigAnimationPlayback(player, character, state)
end

local function onCharacterAdded(player: Player, character: Model): ()
	bindCharacterWeaponAnimation(player, character)

	character.Destroying:Once(function()
		clearCharacterAnimationState(character)
	end)
end

local function hookPlayer(player: Player): ()
	player.CharacterAdded:Connect(function(character: Model)
		onCharacterAdded(player, character)
	end)

	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end

local localPlayer = Players.LocalPlayer
if localPlayer then
	hookPlayer(localPlayer)
end

Players.PlayerAdded:Connect(function(player: Player)
	if player == Players.LocalPlayer then
		hookPlayer(player)
	end
end)

--[[
	SELF-AUDIT (Section 7):
	- EquippedWeaponId / IsDigging / AgilityLevel GetAttributeChangedSignal:Connect — stored per
	  character in animationStateByCharacter; disconnected in clearCharacterAnimationState. OK.
	- digTrack.DidLoop:Connect — stored per character; disconnected in clearCharacterAnimationState
	  and before track reload. OK.
	- player.CharacterAdded:Connect — local player only; binds dig loop state per character. OK.
	- character.Destroying:Once — clears animation state for that character. OK.
	- Instance.new (Animation, Animator) — Animator once per character if missing; Animation per track load. OK.
	- task.spawn — none. OK.
]]
