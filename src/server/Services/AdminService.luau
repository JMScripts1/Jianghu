--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CombatDefs = require(ReplicatedStorage.Shared.Combat.CombatDefs)
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local RateLimit = require(script.Parent.Parent.RateLimit)
local CombatService = require(script.Parent.CombatService)

local MAX_WEAPON_LEN = 16

local AdminService = {}

-- everyone in Studio, only the listed user ids on a live server
local function isAdmin(plr: Player): boolean
	return RunService:IsStudio() or table.find(Config.ADMINS, plr.UserId) ~= nil
end

local function onEquip(plr: Player, weapon: unknown)
	if not RateLimit.check(plr, "Equip") then
		return
	end
	if typeof(weapon) ~= "string" or #weapon > MAX_WEAPON_LEN then
		return
	end

	local id: Types.WeaponId? = CombatDefs.weapon(weapon)
	local char = plr.Character
	if id and char and isAdmin(plr) and not CombatService.equip(char, id) and Config.DEBUG then
		print("equip refused", plr.Name, id, char:GetAttribute("CombatState"))
	end
end

Remotes.Equip.OnServerEvent:Connect(onEquip)

return AdminService
