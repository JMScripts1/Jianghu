--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local Players = game:GetService("Players")

local Collision = require(script.Parent.Parent.Collision)
local CombatService = require(script.Parent.CombatService)
local MovementService = require(script.Parent.MovementService)
local StateService = require(script.Parent.StateService)

local CharacterService = {}

-- every character comes in and goes out through here, players and NPCs alike, so the services always set up in the
-- same order and tear down in reverse
function CharacterService.add(char: Model)
	Collision.add(char)
	StateService.add(char)
	MovementService.add(char)
	CombatService.add(char)
end

-- safe to run twice, a player leaving can remove its character from both signals
function CharacterService.remove(char: Model)
	CombatService.remove(char)
	StateService.remove(char)
end

local function onPlayerAdded(plr: Player)
	plr.CharacterAdded:Connect(CharacterService.add)
	plr.CharacterRemoving:Connect(CharacterService.remove)

	local char = plr.Character
	if char then
		CharacterService.add(char)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(plr)
	local char = plr.Character
	if char then
		CharacterService.remove(char)
	end
end)
for _, plr in Players:GetPlayers() do
	onPlayerAdded(plr)
end

return CharacterService
