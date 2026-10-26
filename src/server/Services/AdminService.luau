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
local BotService = require(script.Parent.BotService)
local CombatService = require(script.Parent.CombatService)
local StateService = require(script.Parent.StateService)

local MAX_WEAPON_LEN = 16
local MAX_BOT_ARG_LEN = 16

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

-- Spawn puts one in front of the admin facing them, Clear takes every menu bot away, Difficulty and Weapon set what
-- every bot fights with
local function onBot(plr: Player, action: unknown, value: unknown)
	if not RateLimit.check(plr, "Bot") then
		return
	end
	if typeof(action) ~= "string" or #action > MAX_BOT_ARG_LEN or not isAdmin(plr) then
		return
	end
	if value ~= nil and (typeof(value) ~= "string" or #value > MAX_BOT_ARG_LEN) then
		return
	end

	if action == "Spawn" then
		local root = if plr.Character then StateService.liveRoot(plr.Character) else nil
		if not root then
			return
		end
		local look = root.CFrame.LookVector
		local at = root.Position + Vector3.new(look.X, 0, look.Z).Unit * Config.BOT_SPAWN_DISTANCE
		BotService.spawn(CFrame.lookAt(at, Vector3.new(root.Position.X, at.Y, root.Position.Z)))
	elseif action == "Clear" then
		BotService.clear()
	elseif action == "Difficulty" then
		local level: Types.BotLevel? = BotService.level(value)
		if level then
			BotService.setDifficulty(level)
		end
	elseif action == "Weapon" then
		local weapon: Types.WeaponId? = CombatDefs.weapon(value)
		if weapon then
			BotService.setWeapon(weapon)
		end
	end
end

Remotes.Equip.OnServerEvent:Connect(onEquip)
Remotes.Bot.OnServerEvent:Connect(onBot)

return AdminService
