--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local RunService = game:GetService("RunService")

local function remote(name: string): RemoteEvent
	if RunService:IsServer() then
		local event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = script
		return event
	end
	return script:WaitForChild(name) :: RemoteEvent
end

-- for effects only, a dropped one loses a spark and never state
local function unreliable(name: string): UnreliableRemoteEvent
	if RunService:IsServer() then
		local event = Instance.new("UnreliableRemoteEvent")
		event.Name = name
		event.Parent = script
		return event
	end
	return script:WaitForChild(name) :: UnreliableRemoteEvent
end

return table.freeze({
	Move = remote("Move"),
	MoveDeny = remote("MoveDeny"),
	Combat = remote("Combat"),
	CombatDeny = remote("CombatDeny"),
	Knockback = remote("Knockback"),
	Shove = remote("Shove"),
	Pin = remote("Pin"),
	Juggle = remote("Juggle"),
	Equip = remote("Equip"),
	Bot = remote("Bot"),
	Ping = remote("Ping"),
	CombatFx = unreliable("CombatFx"),
})
