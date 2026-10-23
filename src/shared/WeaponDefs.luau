--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local AttackDefs = require(script.Parent.AttackDefs)
local Types = require(script.Parent.Types)

local WeaponDefs: { [Types.WeaponId]: Types.WeaponDef } = {
	fist = {
		light = { "fist_light_1", "fist_light_2", "fist_light_3", "fist_light_4" },
		heavy = "fist_heavy",
		run = "fist_run",
		air = "fist_air",
	},
}

local used: { [Types.AttackId]: true } = {}

-- the old solver doesn't check these strings against AttackId, so a typo would just never swing.
-- loop vars are annotated because it widens them to string
for id, def in WeaponDefs do
	assert(#def.light > 0, `{id} has no light chain`)
	for _, attack: Types.AttackId in def.light do
		assert(AttackDefs[attack], `{id} has no attack called {attack}`)
		used[attack] = true
	end
	for _, attack: Types.AttackId in { def.heavy, def.run, def.air } do
		assert(AttackDefs[attack], `{id} has no attack called {attack}`)
		used[attack] = true
	end
	table.freeze(def.light)
	table.freeze(def)
end

-- an attack no weapon names can never be swung, which is always a mistake
for attack: Types.AttackId in AttackDefs do
	assert(used[attack], `no weapon uses {attack}`)
end

return table.freeze(WeaponDefs)
