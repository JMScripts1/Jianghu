--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local Anims = require(script.Parent.Parent.Movement.Anims)
local CombatAnims = require(script.Parent.CombatAnims)
local Movesets = require(script.Parent.Movesets)
local Types = require(script.Parent.Parent.Types)

type Row = {
	moveset: Types.MovesetId,
	damage: number,
	speed: number,
	reach: number,
	model: string?,
}

-- typed so the old solver takes it as a key of the reactions
local GRIP_POSE: Types.Reaction = "GripPose"

-- a weapon of a type that already has a moveset is one row here
local rows: { [Types.WeaponId]: Row } = {
	fist = { moveset = "fist", damage = 1, speed = 1.15, reach = 1 },
	-- quicker and weaker than the fist, and it has to get closer
	dagger = { moveset = "dagger", damage = 0.8, speed = 1.3, reach = 0.8, model = "Dagger" },
}

local WeaponDefs: { [Types.WeaponId]: Types.WeaponDef } = {}
local used: { [Types.MovesetId]: true } = {}

-- one id or several become a list, and an empty id is no animation
local function ids(anims: Types.ReactionAnims): { string }
	local given: { string } = if typeof(anims) == "string" then { anims } else anims
	local list: { string } = {}
	for _, id in given do
		if id ~= "" then
			table.insert(list, id)
		end
	end
	return table.freeze(list)
end

-- the old solver doesn't check these strings against MovesetId, so a typo would just never swing.
-- loop vars are annotated because it widens them to string
for weapon: Types.WeaponId, row in rows do
	local moveset = Movesets[row.moveset]
	assert(moveset, `{weapon} swings {row.moveset}, which has no moveset`)
	assert(#moveset.light > 0, `{row.moveset} has no light chain`)
	assert(row.damage > 0 and row.speed > 0 and row.reach > 0, `{weapon} has a stat at or under 0`)
	used[row.moveset] = true

	local light: { Types.AttackId } = {}
	for i in moveset.light do
		table.insert(light, `{weapon}_light_{i}`)
	end

	-- the moveset's own reactions over CombatAnims, an empty one keeps the default
	local reactions: { [Types.Reaction]: { string } } = {}
	for name: Types.Reaction, anims in CombatAnims do
		reactions[name] = ids(anims)
	end
	local own = moveset.reactions
	if own then
		for name: Types.Reaction, anims in own do
			local list = ids(anims)
			if #list > 0 then
				reactions[name] = list
			end
		end
	end

	-- the victim lies in the generic pose unless the moveset has its own half
	local spec = moveset.grip
	local grip: Types.Grip? = if spec
		then {
			anim = spec.anim,
			victim = spec.victim or reactions[GRIP_POSE][1] or "",
			offset = spec.offset,
			killAt = spec.killAt,
		}
		else nil
	if grip then
		table.freeze(grip)
	end

	-- only a slot that has a shared animation can be swapped, so a typo fails here instead of never playing
	local movement: { [Types.AnimName]: string } = {}
	local ownMoves = moveset.movement
	if ownMoves then
		for name: Types.AnimName, id in ownMoves do
			assert(Anims[name], `{row.moveset} has its own {name}, which isn't a movement animation`)
			if id ~= "" then
				movement[name] = id
			end
		end
	end

	-- frozen in place, the new solver's read only freeze type doesn't fit WeaponDef
	local def: Types.WeaponDef = {
		moveset = row.moveset,
		damage = row.damage,
		speed = row.speed,
		reach = row.reach,
		model = row.model,
		light = light,
		heavy = `{weapon}_heavy`,
		run = `{weapon}_run`,
		air = `{weapon}_air`,
		reactions = reactions,
		grip = grip,
		movement = movement,
	}
	WeaponDefs[weapon] = def
	table.freeze(light)
	table.freeze(reactions)
	table.freeze(movement)
	table.freeze(def)
end

-- a moveset no weapon swings is always a mistake
for moveset: Types.MovesetId in Movesets do
	assert(used[moveset], `no weapon swings the {moveset} moveset`)
end

return table.freeze(WeaponDefs)
