--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.

export type MoveState =
	"Idle"
	| "Walk"
	| "Run"
	| "Slide"
	| "CrouchIdle"
	| "CrouchWalk"
	| "Jump"
	| "DoubleJump"
	| "SlideJump"
	| "LedgeLeap"
	| "Fall"
	| "WallRun"
	| "WallLeap"
	| "WallCling"
	| "WallBoost"
	| "Mantle"
	| "DashF"
	| "DashB"
	| "DashL"
	| "DashR"

export type MoveGroup = "Grounded" | "Airborne" | "Wall"

-- WallRun and WallLeap play one of their sides, R6 can't mirror at runtime
export type AnimName =
	MoveState
	| "WallRunLeft"
	| "WallRunRight"
	| "WallLeapLeft"
	| "WallLeapRight"
	| "Roll"
	| "LedgeLeap2"
	| "LedgeLeap3"
	| "LedgeLeap4"
	| "RampLeap"
	| "AirDash"

-- states play the slot named after them, the four dashes share Dash and any landing plays Land
export type SoundName = MoveState | "Dash" | "Land"

export type MoveDef = {
	group: MoveGroup,
	wire: MoveState,
	cap: number,
	cost: number,
	cooldown: number,
	duration: number?,
	after: MoveState?,
	-- the other state on the same cooldown
	shares: MoveState?,
	isDash: boolean,
	-- holds onto a wall part, and each part takes every attached state once before landing
	isAttached: boolean,
	-- gives the air dash back
	isDashReset: boolean,
	to: { [MoveState]: true },
}

export type WallHit = {
	kind: "Run" | "Cling",
	side: ("Left" | "Right")?,
	normal: Vector3,
	part: BasePart,
}

export type LedgeHit = {
	part: BasePart,
	point: Vector3,
	normal: Vector3,
}

-- worked out from end times when read, never stored, see StateService.combatState
export type CombatState = "Idle" | "Attacking" | "Parrying" | "Blocking" | "Stunned" | "PostureBroken" | "Downed"

export type CombatAction = "Light" | "Heavy" | "Release" | "Block" | "Unblock"

export type CombatCooldown = "Parry" | "Heavy" | "Delay" | "Run"

export type WeaponId = "fist"

-- one per weapon type, see Movesets
export type MovesetId = "fist"

-- made by WeaponDefs from the weapon and the slot, like fist_light_3, so none is ever typed by hand
export type AttackId = string

export type HitResult = "Dodged" | "Parried" | "Blocked" | "Broken" | "Hit"

-- which slot of the weapon an attack came from
export type AttackKind = "Light" | "Heavy" | "Run" | "Air"

-- what CombatDefs.pick decided. combo is the string count after this attack, 0 for anything but a light
export type Pick = {
	id: AttackId,
	kind: AttackKind,
	combo: number,
	cooldown: CombatCooldown?,
}

export type AttackDef = {
	anim: string,
	-- the rate its animation plays at, the weapon's speed. the timings below are already divided by it
	speed: number,
	windup: number,
	-- seconds into the windup where a held button delays it, nil can't be delayed
	delayAt: number?,
	active: number,
	recovery: number,
	damage: number,
	posture: number,
	-- share of damage that goes through a block
	chip: number,
	stun: number,
	-- width, height, depth
	box: Vector3,
	lunge: number?,
	knockback: number?,
	canParry: boolean,
	canBlock: boolean,
	canDodge: boolean,
	isGuardBreak: boolean,
	-- can't be parried out of
	isHeavyStun: boolean,
}

-- what an attack in a moveset states for itself, anything it leaves out comes from its kind
export type AttackSpec = {
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

-- every weapon of a type swings the same moveset. an attack's kind is the slot it sits in
export type Moveset = {
	light: { AttackSpec },
	heavy: AttackSpec,
	run: AttackSpec,
	air: AttackSpec,
	-- this weapon type's own reactions, anything empty or left out plays the one in CombatAnims
	reactions: { [CombatState]: string }?,
}

-- damage multiplies every hit, speed runs the whole swing and its animation faster, reach makes the box longer.
-- the attack ids and reactions are filled in by WeaponDefs from the moveset
export type WeaponDef = {
	moveset: MovesetId,
	damage: number,
	speed: number,
	reach: number,
	light: { AttackId },
	heavy: AttackId,
	run: AttackId,
	air: AttackId,
	reactions: { [CombatState]: string },
}

export type CombatDef = {
	actions: { [CombatAction]: true },
	-- landings are allowed whatever this says, see StateService.canMove
	moves: { [MoveState]: true },
}

return {}
