--!strict

local SellService = require(script.Parent.SellService)

SellService.InitRemotes()

--[[
	SELF-AUDIT (Section 7):
	- SellItem / SellAll OnServerEvent:Connect — permanent game-lifetime listeners wired once in InitRemotes. OK.
	- Players.PlayerRemoving:Connect (clearPlayerSellState) — registered inside InitRemotes. OK.
]]
