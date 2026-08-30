--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local VfxPool = require(script.Parent.VfxPool)

local ASSETS_WAIT_TIMEOUT = 5
local HITBOX_NAME = "Hitbox"
local BLOCKER_NAME = "Blocker"
local VISUAL_NAME = "Visual"
local DEFAULT_EMIT_COUNT = 16

local VFX_LIFETIME_BY_NAME: { [string]: number } = {
	ObstacleHit = 1.5,
	LevelUp = 1,
	Rebirth = 2,
}

local POOL_LIFETIME_BUFFER = 0.15

local EMIT_COUNT_BY_VFX: { [string]: number } = {
	LevelUp = 1,
	Rebirth = 1,
	ObstacleHit = 1,
}

local DEFAULT_VFX_LIFETIME = 1

local vfxFolder: Folder? = nil

local function getVfxFolder(): Folder?
	if vfxFolder and vfxFolder.Parent then
		return vfxFolder
	end

	local assets = ReplicatedStorage:WaitForChild("Assets", ASSETS_WAIT_TIMEOUT)
	if assets == nil then
		warn(`[VfxPlayer] Assets folder not found within {ASSETS_WAIT_TIMEOUT}s`)
		return nil
	end

	local folder = assets:WaitForChild("VFX", ASSETS_WAIT_TIMEOUT)
	if folder == nil or not folder:IsA("Folder") then
		warn(`[VfxPlayer] VFX folder not found within {ASSETS_WAIT_TIMEOUT}s`)
		return nil
	end

	vfxFolder = folder
	return folder
end

local function resolveTemplate(vfxName: string): BasePart?
	local folder = getVfxFolder()
	if folder == nil then
		return nil
	end

	local template = folder:FindFirstChild(vfxName)
	if template == nil or not template:IsA("BasePart") then
		warn(`[VfxPlayer] VFX template "{vfxName}" not found or not a BasePart`)
		return nil
	end

	return template
end

local function getVfxLifetime(vfxName: string): number
	return VFX_LIFETIME_BY_NAME[vfxName] or DEFAULT_VFX_LIFETIME
end

local function getEmitDelay(emitter: ParticleEmitter): number
	local emitDelay = emitter:GetAttribute("EmitDelay")
	if typeof(emitDelay) == "number" and emitDelay >= 0 then
		return emitDelay
	end

	return 0
end

local function computePoolLifetime(anchorPart: BasePart, vfxName: string): number
	local maxDuration = 0

	for _, descendant in anchorPart:GetDescendants() do
		if not descendant:IsA("ParticleEmitter") then
			continue
		end

		local emitter = descendant
		local emitDelay = getEmitDelay(emitter)
		local particleLifetime = emitter.Lifetime.Max
		local duration = emitDelay + particleLifetime
		if duration > maxDuration then
			maxDuration = duration
		end
	end

	if maxDuration > 0 then
		return maxDuration + POOL_LIFETIME_BUFFER
	end

	return getVfxLifetime(vfxName)
end

local function schedulePoolRelease(anchorPart: BasePart, vfxName: string): ()
	local lifetime = computePoolLifetime(anchorPart, vfxName)
	task.delay(lifetime, function()
		VfxPool.release(anchorPart)
	end)
end

local function getEmitCount(emitter: ParticleEmitter, vfxName: string): number
	local vfxEmitCount = EMIT_COUNT_BY_VFX[vfxName]
	if vfxEmitCount ~= nil then
		return vfxEmitCount
	end

	local emitCount = emitter:GetAttribute("EmitCount")
	if typeof(emitCount) == "number" and emitCount > 0 then
		return math.floor(emitCount)
	end

	return DEFAULT_EMIT_COUNT
end

local function emitAll(anchorPart: BasePart, vfxName: string): ()
	for _, descendant in anchorPart:GetDescendants() do
		if not descendant:IsA("ParticleEmitter") then
			continue
		end

		local emitter = descendant
		local emitCount = getEmitCount(emitter, vfxName)
		local emitDelay = getEmitDelay(emitter)

		task.delay(emitDelay, function()
			if not emitter.Parent then
				return
			end

			emitter:Emit(emitCount)
		end)
	end
end

local function playAtPart(vfxName: string, targetPart: BasePart, offsetCFrame: CFrame?): ()
	local template = resolveTemplate(vfxName)
	if template == nil then
		return
	end

	local anchorPart = VfxPool.acquire(template)
	if anchorPart == nil then
		return
	end

	local offset = offsetCFrame or CFrame.identity
	anchorPart.CFrame = targetPart.CFrame * offset
	anchorPart.Parent = Workspace

	emitAll(anchorPart, vfxName)
	schedulePoolRelease(anchorPart, vfxName)
end

local function findHumanoidRootPart(character: Model): BasePart?
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end

	return nil
end

local function playOnCharacter(vfxName: string, character: Model): ()
	local rootPart = findHumanoidRootPart(character)
	if rootPart == nil then
		return
	end

	playAtPart(vfxName, rootPart)
end

local function findObstacleTargetPart(obstacle: Instance): BasePart?
	if obstacle:IsA("BasePart") then
		local parent = obstacle.Parent
		if parent then
			local visual = parent:FindFirstChild(VISUAL_NAME)
			if visual and visual:IsA("BasePart") then
				return visual
			end

			local legacyVisual = parent:FindFirstChild("default")
			if legacyVisual and legacyVisual:IsA("BasePart") then
				return legacyVisual
			end
		end

		return obstacle
	end

	if not obstacle:IsA("Model") then
		return nil
	end

	local visual = obstacle:FindFirstChild(VISUAL_NAME)
	if visual and visual:IsA("BasePart") then
		return visual
	end

	local legacyVisual = obstacle:FindFirstChild("default")
	if legacyVisual and legacyVisual:IsA("BasePart") then
		return legacyVisual
	end

	local hitbox = obstacle:FindFirstChild(HITBOX_NAME)
	if hitbox and hitbox:IsA("BasePart") then
		return hitbox
	end

	local blocker = obstacle:FindFirstChild(BLOCKER_NAME)
	if blocker and blocker:IsA("BasePart") then
		return blocker
	end

	return nil
end

local function playObstacleHit(obstacle: Instance): ()
	local targetPart = findObstacleTargetPart(obstacle)
	if targetPart == nil then
		if obstacle:IsA("Model") then
			local pivot = obstacle:GetPivot()
			local template = resolveTemplate("ObstacleHit")
			if template == nil then
				return
			end

			local anchorPart = VfxPool.acquire(template)
			if anchorPart == nil then
				return
			end

			anchorPart.CFrame = pivot
			anchorPart.Parent = Workspace
			emitAll(anchorPart, "ObstacleHit")
			schedulePoolRelease(anchorPart, "ObstacleHit")
		end
		return
	end

	playAtPart("ObstacleHit", targetPart)
end

return {
	playAtPart = playAtPart,
	playOnCharacter = playOnCharacter,
	playObstacleHit = playObstacleHit,
}

--[[
	SELF-AUDIT (Section 7):
	- task.delay per emitter (EmitDelay) — one-shot, no captured long-lived instances. OK.
	- task.delay per play (pool release) — one-shot, releases anchorPart by reference. OK.
	- No :Connect() — attribute/event wiring lives in PlayerVfx.client. OK.
	- Instance.new only for VfxPool storage folder at module load. OK.
	- Hot-path acquire/release via VfxPool; no per-hit Instance.new(). OK.
]]
