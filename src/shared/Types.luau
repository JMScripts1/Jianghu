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
	| "DashCancelLeft"
	| "DashCancelRight"
	| "Sprint"

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
	-- where the ray met the wall
	point: Vector3,
}

export type LedgeHit = {
	part: BasePart,
	point: Vector3,
	normal: Vector3,
}

-- worked out from end times when read, never stored, see StateService.combatState
export type CombatState =
	"Idle"
	| "Attacking"
	| "Parrying"
	| "Blocking"
	| "Stunned"
	| "PostureBroken"
	-- pinned to a wall a knockback threw it into
	| "WallStunned"
	-- pinned to the floor a slam drove it into
	| "FloorStunned"
	| "Downed"
	| "Gripping"
	-- a downed body in someone's grip
	| "Gripped"

-- what a character plays from its own weapon: a loop while it's in a combat state, or a one shot when a hit it took
-- part in resolves, see CombatDefs.reaction
-- GripPose is the pose a downed body is held in during a grip, unless the gripper's weapon has its own
export type Reaction = CombatState | "Parry" | "Deflected" | "BlockHit" | "Hurt" | "Knockback" | "GripPose"

-- one animation, or several that take turns
export type ReactionAnims = string | { string }

-- Slam is a light pressed with jump held, in the air
export type CombatAction = "Light" | "Heavy" | "Release" | "Block" | "Unblock" | "Grip" | "Slam"

-- a paired animation on a downed body. both halves start on the same server frame, and the victim's root is held at
-- offset from the gripper's, the way the two rigs stood when it was animated. the kill lands killAt seconds in
export type GripSpec = {
	anim: string,
	-- the victim's half, the GripPose in CombatAnims when left out
	victim: string?,
	offset: CFrame,
	killAt: number,
}

export type Grip = {
	anim: string,
	victim: string,
	offset: CFrame,
	killAt: number,
}

-- Light is the endlag after a string's last hit, started when that swing ends
export type CombatCooldown = "Parry" | "Heavy" | "Delay" | "Run" | "Light" | "Launch"

export type WeaponId = "fist" | "dagger"

-- a sparring bot's difficulty, see Bot.Brain. the admin menu lists them too
export type BotLevel = "Easy" | "Normal" | "Hard"

-- one per weapon type, see Movesets
export type MovesetId = "fist" | "dagger"

-- made by WeaponDefs from the weapon and the slot, like fist_light_3, so none is ever typed by hand
export type AttackId = string

-- Knocked is a hit that knocked its target back
export type HitResult = "Dodged" | "Parried" | "Blocked" | "Broken" | "Hit" | "Knocked"

-- what CombatFx carries: a hit's result, a swing being delayed or coming through, or a knockback pinning its body to a
-- wall or the floor
export type CombatFx = HitResult | "Delay" | "Swing" | "WallSlam" | "FloorSlam"

-- the attacking weapon's kind of hit, it picks the effects and sounds of every hit it lands, blocked and parried ones too
export type HitType = "Blunt" | "Slash"

-- the hand an attack swings with, where its delay's glare shows
export type Hand = "Right" | "Left" | "Both"

-- each hit type has its own of these, and every weapon shares the rest
export type HitFx = "Hit" | "HeavyHit" | "Block" | "Parry"
export type SharedFx = "Break" | "WallSlam" | "FloorSlam" | "Delay"

-- the tilts a swing effect comes in, seen from behind the attacker. Right and Left are the side held high, so
-- DiagonalRight runs / and DiagonalLeft runs \. see CombatFx for the angles
export type SwingAngle = "Horizontal" | "DiagonalRight" | "DiagonalLeft" | "Vertical"

-- the arc an attack cuts through the air as it comes through. fx names a template in Vfx/Swing, angle tilts it, and
-- at is where it sits on the root and any fine turn on top, lined up with the animation in Studio. left out they sit
-- it level on the root's centre.
-- a flat slash faces along its emission direction, so turning it about that axis does nothing. spin is the degrees
-- added to every emitter's Rotation, which is what turns it round in its own plane
export type SwingFx = {
	fx: string,
	angle: SwingAngle?,
	at: CFrame?,
	spin: number?,
}

-- which slot of the weapon an attack came from
-- Launch is the crouched uppercut that starts a juggle, Slam the jump held light in one
export type AttackKind = "Light" | "Heavy" | "Run" | "Air" | "Launch" | "Slam"

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
	hitType: HitType,
	hand: Hand,
	swing: SwingFx?,
	-- the strike that starts when this one ends, in the same animation, see AttackSpec.follow
	follow: AttackId?,
}

-- what an attack in a moveset states for itself, anything it leaves out comes from its kind
export type AttackSpec = {
	-- a follow plays on in its first strike's animation and leaves this out
	anim: string?,
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
	-- a stab in a slashing moveset, say. left out it's the moveset's, or a follow's first strike's
	hitType: HitType?,
	-- left out, a string's lights alternate starting on the right and everything else is the right. a follow takes its
	-- first strike's
	hand: Hand?,
	-- left out it has no swing effect. a follow's is its own, it cuts its own arc
	swing: SwingFx?,
	-- another strike in the same animation, starting the moment this one's recovery ends, with its own hit and its own
	-- parry or block. it can't be delayed, it carries the first strike's delay instead
	follow: AttackSpec?,
}

-- every weapon of a type swings the same moveset. an attack's kind is the slot it sits in
export type Moveset = {
	light: { AttackSpec },
	heavy: AttackSpec,
	run: AttackSpec,
	-- a single air attack in place of the string in the air outside a juggle, an empty one leaves the string
	air: AttackSpec,
	-- the crouched uppercut that throws both fighters up into a juggle
	launch: AttackSpec,
	-- the jump held light in a juggle, it spikes the target down
	slam: AttackSpec,
	-- every attack's unless it says otherwise, left out it's the kind's, Blunt like the fist
	hitType: HitType?,
	-- this weapon type's own reactions, anything empty or left out plays the one in CombatAnims
	reactions: { [Reaction]: ReactionAnims }?,
	-- a weapon type without one can't grip
	grip: GripSpec?,
	-- state animations played instead of the shared ones in Anims while it's held, like its own Idle and Walk. an empty
	-- one keeps the shared one, and a dash, its cancel or the roll always plays the shared one
	movement: { [AnimName]: string }?,
}

-- damage multiplies every hit, speed runs the whole swing and its animation faster, reach makes the box longer.
-- the attack ids and reactions are filled in by WeaponDefs from the moveset
export type WeaponDef = {
	moveset: MovesetId,
	damage: number,
	speed: number,
	reach: number,
	-- its model in ServerStorage.Weapons, nil is held in the bare hand
	model: string?,
	light: { AttackId },
	heavy: AttackId,
	run: AttackId,
	air: AttackId,
	launch: AttackId,
	slam: AttackId,
	-- every slot as a list, empty when it has no animation
	reactions: { [Reaction]: { string } },
	grip: Grip?,
	-- only the ones it has its own of, see Moveset.movement
	movement: { [AnimName]: string },
}

export type CombatDef = {
	actions: { [CombatAction]: true },
	-- landings are allowed whatever this says, see StateService.canMove
	moves: { [MoveState]: true },
}

return {}
