--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local Types = require(script.Parent.Types)

-- played by a character's own client from its CombatState, everyone else sees them through replication.
-- attacks play their own anim from AttackDefs. an empty id plays nothing
local CombatAnims: { [Types.CombatState]: string } = {
	Parrying = "",
	Blocking = "",
	Stunned = "",
	PostureBroken = "",
	Downed = "",
}

return table.freeze(CombatAnims)
