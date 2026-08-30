--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local UIJuice = require(script.Parent.UIJuice)

local UI_WAIT_TIMEOUT = 5
local HUD_BUTTONS_NAME = "HUDButtons"
local CURRENCY_COUNTERS_NAME = "CurrencyCounters"
local BACKPACK_COUNTER_NAME = "BackpackCounter"
local BACKPACK_COUNTER_AMOUNT_NAME = "BackpackCounterAmount"
local CASH_COUNTER_NAME = "CashCounter"
local CASH_COUNTER_AMOUNT_NAME = "CashCounterAmount"
local REBIRTH_COUNTER_NAME = "RebirthCounter"
local REBIRTH_COUNTER_AMOUNT_NAME = "RebirthCounterAmount"

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function getStatValue(attributeName: string): number?
	local value = player:GetAttribute(attributeName)
	if typeof(value) == "number" then
		return value
	end

	return nil
end

local function findHudButtons(root: Instance): ScreenGui?
	local directChild = root:FindFirstChild(HUD_BUTTONS_NAME)
	if directChild and directChild:IsA("ScreenGui") then
		return directChild
	end

	for _, descendant in root:GetDescendants() do
		if descendant.Name == HUD_BUTTONS_NAME and descendant:IsA("ScreenGui") then
			return descendant
		end
	end

	return nil
end

local function waitForHudButtons(): ScreenGui
	while true do
		local existing = findHudButtons(playerGui)
		if existing then
			return existing
		end

		playerGui.ChildAdded:Wait()
	end
end

local hudButtons = waitForHudButtons()

local currencyCounters = hudButtons:WaitForChild(CURRENCY_COUNTERS_NAME, UI_WAIT_TIMEOUT)
if currencyCounters == nil then
	warn(`[CurrencyCounters] {CURRENCY_COUNTERS_NAME} not found within {UI_WAIT_TIMEOUT}s`)
	return
end

local backpackCounter = currencyCounters:WaitForChild(BACKPACK_COUNTER_NAME, UI_WAIT_TIMEOUT)
local cashCounter = currencyCounters:WaitForChild(CASH_COUNTER_NAME, UI_WAIT_TIMEOUT)
local rebirthCounter = currencyCounters:WaitForChild(REBIRTH_COUNTER_NAME, UI_WAIT_TIMEOUT)

if backpackCounter == nil or cashCounter == nil or rebirthCounter == nil then
	warn(`[CurrencyCounters] One or more counter frames not found within {UI_WAIT_TIMEOUT}s`)
	return
end

local backpackCounterAmount = backpackCounter:WaitForChild(BACKPACK_COUNTER_AMOUNT_NAME, UI_WAIT_TIMEOUT)
local cashCounterAmount = cashCounter:WaitForChild(CASH_COUNTER_AMOUNT_NAME, UI_WAIT_TIMEOUT)
local rebirthCounterAmount = rebirthCounter:WaitForChild(REBIRTH_COUNTER_AMOUNT_NAME, UI_WAIT_TIMEOUT)

if backpackCounterAmount == nil or cashCounterAmount == nil or rebirthCounterAmount == nil then
	warn(`[CurrencyCounters] One or more counter amount labels not found within {UI_WAIT_TIMEOUT}s`)
	return
end

if
	not backpackCounterAmount:IsA("TextLabel")
	or not cashCounterAmount:IsA("TextLabel")
	or not rebirthCounterAmount:IsA("TextLabel")
then
	warn("[CurrencyCounters] One or more counter amount labels is not a TextLabel")
	return
end

local lastCash = getStatValue("Cash") or 0
local lastTripCarryCount = getStatValue("TripCarryCount") or 0

local function getMaxCapacity(): number
	return getStatValue("MaxCapacity") or 2
end

local function updateBackpackCounter(pulseOnIncrease: boolean): ()
	local tripCount = getStatValue("TripCarryCount") or 0
	backpackCounterAmount.Text = `{tripCount}/{getMaxCapacity()}`

	if pulseOnIncrease and tripCount > lastTripCarryCount and backpackCounter:IsA("GuiObject") then
		UIJuice.PulseGui(backpackCounter)
	end

	lastTripCarryCount = tripCount
end

local function updateCashCounter(pulseOnIncrease: boolean): ()
	local cash = getStatValue("Cash") or 0
	cashCounterAmount.Text = NumberFormatter.Format(cash)

	if pulseOnIncrease and cash > lastCash and cashCounter:IsA("GuiObject") then
		UIJuice.PulseGui(cashCounter)
	end

	lastCash = cash
end

local function updateRebirthCounter(): ()
	local rebirths = getStatValue("Rebirths") or 0
	rebirthCounterAmount.Text = tostring(rebirths)
end

local function onCashChanged(): ()
	updateCashCounter(true)
end

local function onRebirthsChanged(): ()
	updateRebirthCounter()
end

local function onTripCarryCountChanged(): ()
	updateBackpackCounter(true)
end

local function onMaxCapacityChanged(): ()
	updateBackpackCounter(false)
end

player:GetAttributeChangedSignal("Cash"):Connect(onCashChanged)
player:GetAttributeChangedSignal("Rebirths"):Connect(onRebirthsChanged)
player:GetAttributeChangedSignal("TripCarryCount"):Connect(onTripCarryCountChanged)
player:GetAttributeChangedSignal("MaxCapacity"):Connect(onMaxCapacityChanged)

updateCashCounter(false)
updateRebirthCounter()
updateBackpackCounter(false)

--[[ SELF-AUDIT (Section 7):
  GetAttributeChangedSignal Cash/Rebirths/TripCarryCount/MaxCapacity — permanent player-lifetime
  connections. OK.
  waitForHudButtons ChildAdded:Wait loop exits once HUDButtons exists; no polling of stats. OK. ]]
