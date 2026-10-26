--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local Movesets = require(script.Parent.Movesets)
local Types = require(script.Parent.Parent.Types)
local WeaponDefs = require(script.Parent.WeaponDefs)

-- the starting numbers every moveset tunes from. a light with an empty anim swings with nothing to see, a heavy,
-- running or air attack with one is never picked, see CombatDefs.pick
local LIGHT: Types.AttackDef = {
	anim = "",
	speed = 1,
	windup = 0.35,
	delayAt = 0.15,
	active = 0,
	recovery = 0.15,
	damage = 4,
	posture = 10,
	chip = 0,
	stun = 0.55,
	box = Vector3.new(5, 6, 6),
	-- a small step in with every swing
	lunge = 30,
	canParry = true,
	canBlock = true,
	canDodge = true,
	isGuardBreak = false,
	isHeavyStun = false,
}

-- guard break, so blocking it breaks posture and its posture number is never used
local HEAVY: Types.AttackDef = {
	anim = "",
	speed = 1,
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
	speed = 1,
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
	speed = 1,
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

-- the stun lasts through the rise and the swing up after it, so the first hit in the air connects
local LAUNCH: Types.AttackDef = {
	anim = "",
	speed = 1,
	windup = 0.3,
	active = 0,
	recovery = 0.3,
	damage = 5,
	posture = 10,
	chip = 0,
	stun = 0.9,
	box = Vector3.new(5, 7, 6),
	lunge = 20,
	canParry = true,
	canBlock = true,
	canDodge = true,
	isGuardBreak = false,
	isHeavyStun = false,
}

-- taller than a light, the target is often under it. its knockback goes down at SLAM_ANGLE, see CombatService
local SLAM: Types.AttackDef = {
	anim = "",
	speed = 1,
	windup = 0.35,
	delayAt = 0.15,
	active = 0,
	recovery = 0.15,
	damage = 6,
	posture = 15,
	chip = 0,
	stun = 0.8,
	box = Vector3.new(5, 9, 6),
	lunge = 30,
	knockback = 80,
	canParry = true,
	canBlock = true,
	canDodge = true,
	isGuardBreak = false,
	isHeavyStun = false,
}

-- the weapon's stats go in here, so every number downstream is already that weapon's own.
-- booleans go through ~= nil, `or` would turn a false back into the kind's true
local function build(kind: Types.AttackDef, spec: Types.AttackSpec, weapon: Types.WeaponDef): Types.AttackDef
	local delayAt = spec.delayAt or kind.delayAt
	local box = spec.box or kind.box
	local knockback = spec.knockback or kind.knockback
	return {
		anim = spec.anim or "",
		speed = weapon.speed,
		windup = (spec.windup or kind.windup) / weapon.speed,
		delayAt = if delayAt then delayAt / weapon.speed else nil,
		active = (spec.active or kind.active) / weapon.speed,
		recovery = (spec.recovery or kind.recovery) / weapon.speed,
		damage = (spec.damage or kind.damage) * weapon.damage,
		posture = spec.posture or kind.posture,
		chip = spec.chip or kind.chip,
		stun = spec.stun or kind.stun,
		-- reach is depth only, a longer weapon doesn't swing any wider
		box = Vector3.new(box.X, box.Y, box.Z * weapon.reach),
		lunge = spec.lunge or kind.lunge,
		-- 0 takes away a knockback the kind has
		knockback = if knockback and knockback > 0 then knockback else nil,
		canParry = if spec.canParry ~= nil then spec.canParry else kind.canParry,
		canBlock = if spec.canBlock ~= nil then spec.canBlock else kind.canBlock,
		canDodge = if spec.canDodge ~= nil then spec.canDodge else kind.canDodge,
		isGuardBreak = if spec.isGuardBreak ~= nil then spec.isGuardBreak else kind.isGuardBreak,
		isHeavyStun = if spec.isHeavyStun ~= nil then spec.isHeavyStun else kind.isHeavyStun,
	}
end

local AttackDefs: { [Types.AttackId]: Types.AttackDef } = {}

-- a follow goes in under its first strike's id and its number, like dagger_heavy_2, plays in that strike's animation,
-- and can't be delayed
local function add(
	base: Types.AttackId,
	n: number,
	kind: Types.AttackDef,
	spec: Types.AttackSpec,
	weapon: Types.WeaponDef,
	anim: string?
)
	local def = build(kind, spec, weapon)
	if anim then
		def.anim = anim
		def.delayAt = nil
	end
	AttackDefs[if n == 1 then base else `{base}_{n}`] = def
	local follow = spec.follow
	if follow then
		def.follow = `{base}_{n + 1}`
		add(base, n + 1, kind, follow, weapon, def.anim)
	end
end

-- every weapon gets its own copy of its moveset's attacks, under the ids WeaponDefs made for it
for _, weapon in WeaponDefs do
	local moveset = Movesets[weapon.moveset]
	for i, id in weapon.light do
		add(id, 1, LIGHT, moveset.light[i], weapon)
	end
	add(weapon.heavy, 1, HEAVY, moveset.heavy, weapon)
	add(weapon.run, 1, RUN, moveset.run, weapon)
	add(weapon.air, 1, AIR, moveset.air, weapon)
	add(weapon.launch, 1, LAUNCH, moveset.launch, weapon)
	add(weapon.slam, 1, SLAM, moveset.slam, weapon)
end

for id, def in AttackDefs do
	assert(def.windup > 0, `{id} has no windup`)
	assert(not def.delayAt or (def.delayAt > 0 and def.delayAt < def.windup), `{id} delays outside its windup`)
	table.freeze(def)
end

return table.freeze(AttackDefs)
