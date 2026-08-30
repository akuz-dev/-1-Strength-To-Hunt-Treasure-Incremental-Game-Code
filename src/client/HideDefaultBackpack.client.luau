--!strict

local StarterGui = game:GetService("StarterGui")

StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

--[[
	SELF-AUDIT (Section 7):
	- SetCoreGuiEnabled once at load — hides default Roblox tool hotbar; weapons are
	  welded visuals only, not inventory Tools. OK.
]]
