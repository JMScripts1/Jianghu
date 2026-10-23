--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local Types = require(script.Parent.Types)

-- what an attack states for itself, anything it leaves out comes from its kind
type Spec = {
	anim: string,
	windup: number?,
	delayAt: number?,
	active: number?,
	recovery: number?,
	damage: number?,
	posture: number?,
	chip: number?,
	stun: number?,
	box: Vector3?,
	lunge: number?,
	knockback: number?,
	canParry: boolean?,
	canBlock: boolean?,
	canDodge: boolean?,
	isGuardBreak: boolean?,
	isHeavyStun: boolean?,
}

-- the fist's numbers, which every other weapon tunes from. an empty anim is an attack with no animation yet
local LIGHT: Types.AttackDef = {
	anim = "",
	windup = 0.35,
	delayAt = 0.15,
	active = 0,
	recovery = 0.15,
	damage = 4,
	posture = 10,
	chip = 0,
	stun = 0.55,
	box = Vector3.new(5, 6, 6),
	canParry = true,
	canBlock = true,
	canDodge = true,
	isGuardBreak = false,
	isHeavyStun = false,
}

-- guard break, so blocking it breaks posture and its posture number is never used
local HEAVY: Types.AttackDef = {
	anim = "",
	windup = 0.7,
	delayAt = 0.3,
	active = 0,
	recovery = 0.35,
	damage = 10,
	posture = 0,
	chip = 0,
	stun = 0.75,
	box = Vector3.new(7, 6, 5),
	lunge = 60,
	knockback = 70,
	canParry = true,
	canBlock = true,
	canDodge = false,
	isGuardBreak = true,
	isHeavyStun = true,
}

-- the lunge comes from momentum, see RUN_ATTACK_LUNGE
local RUN: Types.AttackDef = {
	anim = "",
	windup = 0.3,
	active = 0,
	recovery = 0.35,
	damage = 5,
	posture = 15,
	chip = 0,
	stun = 0.4,
	box = Vector3.new(5, 6, 7),
	canParry = true,
	canBlock = true,
	canDodge = true,
	isGuardBreak = false,
	isHeavyStun = false,
}

local AIR: Types.AttackDef = {
	anim = "",
	windup = 0.3,
	active = 0,
	recovery = 0.2,
	damage = 4,
	posture = 10,
	chip = 0,
	stun = 0.55,
	box = Vector3.new(5, 7, 6),
	canParry = true,
	canBlock = true,
	canDodge = true,
	isGuardBreak = false,
	isHeavyStun = false,
}

-- booleans go through ~= nil, `or` would turn a false back into the kind's true
local function build(kind: Types.AttackDef, spec: Spec): Types.AttackDef
	return {
		anim = spec.anim,
		windup = spec.windup or kind.windup,
		delayAt = spec.delayAt or kind.delayAt,
		active = spec.active or kind.active,
		recovery = spec.recovery or kind.recovery,
		damage = spec.damage or kind.damage,
		posture = spec.posture or kind.posture,
		chip = spec.chip or kind.chip,
		stun = spec.stun or kind.stun,
		box = spec.box or kind.box,
		lunge = spec.lunge or kind.lunge,
		knockback = spec.knockback or kind.knockback,
		canParry = if spec.canParry ~= nil then spec.canParry else kind.canParry,
		canBlock = if spec.canBlock ~= nil then spec.canBlock else kind.canBlock,
		canDodge = if spec.canDodge ~= nil then spec.canDodge else kind.canDodge,
		isGuardBreak = if spec.isGuardBreak ~= nil then spec.isGuardBreak else kind.isGuardBreak,
		isHeavyStun = if spec.isHeavyStun ~= nil then spec.isHeavyStun else kind.isHeavyStun,
	}
end

local AttackDefs: { [Types.AttackId]: Types.AttackDef } = {
	fist_light_1 = build(LIGHT, { anim = "rbxassetid://120569367050205" }),
	fist_light_2 = build(LIGHT, { anim = "rbxassetid://121297357737920" }),
	fist_light_3 = build(LIGHT, { anim = "rbxassetid://86517120998857" }),
	-- the finisher, it knocks back unless delayed
	fist_light_4 = build(
		LIGHT,
		{ anim = "rbxassetid://100220503224779", recovery = 0.3, damage = 5, posture = 15, stun = 0.6, knockback = 50 }
	),
	fist_heavy = build(HEAVY, { anim = "" }),
	fist_run = build(RUN, { anim = "" }),
	fist_air = build(AIR, { anim = "" }),
}

for id, def in AttackDefs do
	assert(def.windup > 0, `{id} has no windup`)
	assert(not def.delayAt or (def.delayAt > 0 and def.delayAt < def.windup), `{id} delays outside its windup`)
	table.freeze(def)
end

return table.freeze(AttackDefs)
