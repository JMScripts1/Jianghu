--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local Movesets = require(script.Parent.Movesets)
local Types = require(script.Parent.Parent.Types)
local WeaponDefs = require(script.Parent.WeaponDefs)

-- an attack's contact and length are frames of its animation at this rate. the server starts a swing half a ping late,
-- so the box opens HIT_LEAD before the contact frame and stays open HIT_ACTIVE, through just after it
local FPS = 60
local HIT_LEAD = 3 / FPS
local HIT_ACTIVE = 4 / FPS

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
	hitType = "Blunt",
	hand = "Right",
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
	hitType = "Blunt",
	hand = "Right",
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
	hitType = "Blunt",
	hand = "Right",
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
	hitType = "Blunt",
	hand = "Right",
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
	hitType = "Blunt",
	hand = "Right",
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
	hitType = "Blunt",
	hand = "Right",
}

-- windup, active and recovery in seconds at a speed of 1. from a contact frame the box opens HIT_LEAD before it and
-- the rest of the animation up to length is recovery, so the three add up to the whole anim. a strike with a follow ends
-- as its box closes, the follow's windup runs on from there, and only the last strike needs a length. from is where in
-- the animation this strike starts. any of the three set by hand wins
local function timing(
	kind: Types.AttackDef,
	spec: Types.AttackSpec,
	id: Types.AttackId,
	from: number
): (number, number, number)
	local contact = spec.contact
	if not contact then
		return spec.windup or kind.windup, spec.active or kind.active, spec.recovery or kind.recovery
	end
	local windup = spec.windup or contact / FPS - HIT_LEAD - from
	local active = spec.active or HIT_ACTIVE
	local length = spec.length
	assert(spec.recovery or spec.follow or length, `{id} has a contact frame but no length`)
	local recovery = spec.recovery or if spec.follow or not length then 0 else length / FPS - from - windup - active
	return windup, active, recovery
end

-- the weapon's stats go in here, so every number downstream is already that weapon's own.
-- booleans go through ~= nil, `or` would turn a false back into the kind's true
local function build(
	kind: Types.AttackDef,
	spec: Types.AttackSpec,
	weapon: Types.WeaponDef,
	hitType: Types.HitType?,
	hand: Types.Hand?,
	id: Types.AttackId,
	from: number
): Types.AttackDef
	local delayAt = spec.delayAt or kind.delayAt
	local box = spec.box or kind.box
	local knockback = spec.knockback or kind.knockback
	local windup, active, recovery = timing(kind, spec, id, from)
	return {
		anim = spec.anim or "",
		speed = weapon.speed,
		windup = windup / weapon.speed,
		delayAt = if delayAt then delayAt / weapon.speed else nil,
		active = active / weapon.speed,
		recovery = recovery / weapon.speed,
		damage = (spec.damage or kind.damage) * weapon.damage,
		posture = spec.posture or kind.posture,
		chip = spec.chip or kind.chip,
		-- a stun is there to reach the next hit, so it shrinks with the swing. unscaled, a faster weapon's string holds
		-- its target through the gaps after it and a delayed hit locks out more than the one hit after it
		stun = (spec.stun or kind.stun) / weapon.speed,
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
		hitType = spec.hitType or hitType or kind.hitType,
		hand = spec.hand or hand or kind.hand,
		swing = spec.swing,
	}
end

local AttackDefs: { [Types.AttackId]: Types.AttackDef } = {}

-- a follow goes in under its first strike's id and its number, like dagger_heavy_2, plays in that strike's animation,
-- can't be delayed, and hits and swings the way that strike does unless it says otherwise
local function add(
	base: Types.AttackId,
	n: number,
	kind: Types.AttackDef,
	spec: Types.AttackSpec,
	weapon: Types.WeaponDef,
	hand: Types.Hand?,
	first: Types.AttackDef?,
	from: number?
)
	local id = if n == 1 then base else `{base}_{n}`
	local startsAt = from or 0
	local def = build(
		kind,
		spec,
		weapon,
		if first then first.hitType else Movesets[weapon.moveset].hitType,
		if first then first.hand else hand,
		id,
		startsAt
	)
	if first then
		def.anim = first.anim
		def.delayAt = nil
	end
	AttackDefs[id] = def
	local follow = spec.follow
	if follow then
		def.follow = `{base}_{n + 1}`
		-- back to a speed of 1, where the follow's frames are
		local endsAt = startsAt + (def.windup + def.active + def.recovery) * weapon.speed
		add(base, n + 1, kind, follow, weapon, def.hand, def, endsAt)
	end
end

-- every weapon gets its own copy of its moveset's attacks, under the ids WeaponDefs made for it. a string's lights
-- swing right, left, right and on, everything else with the kind's hand
for _, weapon in WeaponDefs do
	local moveset = Movesets[weapon.moveset]
	for i, id in weapon.light do
		add(id, 1, LIGHT, moveset.light[i], weapon, if i % 2 == 1 then "Right" else "Left")
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
