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

export type AttackId =
	"fist_light_1"
	| "fist_light_2"
	| "fist_light_3"
	| "fist_light_4"
	| "fist_heavy"
	| "fist_run"
	| "fist_air"

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

export type WeaponDef = {
	light: { AttackId },
	heavy: AttackId,
	run: AttackId,
	air: AttackId,
}

export type CombatDef = {
	actions: { [CombatAction]: true },
	-- landings are allowed whatever this says, see StateService.canMove
	moves: { [MoveState]: true },
}

return {}
