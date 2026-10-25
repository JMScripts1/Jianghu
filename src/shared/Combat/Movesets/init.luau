--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local Types = require(script.Parent.Parent.Types)

-- every weapon of a type swings the same moveset, see WeaponDefs. a new one needs its id in MovesetId too
local Movesets: { [Types.MovesetId]: Types.Moveset } = {
	fist = require(script.Fist),
	dagger = require(script.Dagger),
}

return table.freeze(Movesets)
