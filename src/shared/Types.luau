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
	| "VaultLow"
	| "Jump"
	| "DoubleJump"
	| "SlideJump"
	| "Fall"
	| "WallRun"
	| "WallLeap"
	| "WallCling"
	| "WallBoost"
	| "VaultMid"

export type MoveGroup = "Grounded" | "Airborne" | "Wall"

export type DashDir = "F" | "B" | "L" | "R"

-- WallRun plays one side, R6 animations can't be mirrored at runtime
export type AnimName =
	"Idle"
	| "Walk"
	| "Run"
	| "Slide"
	| "CrouchIdle"
	| "CrouchWalk"
	| "VaultLow"
	| "Jump"
	| "DoubleJump"
	| "SlideJump"
	| "Fall"
	| "WallRunLeft"
	| "WallRunRight"
	| "WallLeap"
	| "WallCling"
	| "WallBoost"
	| "VaultMid"
	| "DashF"
	| "DashB"
	| "DashL"
	| "DashR"

export type MoveDef = {
	group: MoveGroup,
	wire: MoveState,
	cap: number,
	cost: number,
	cooldown: number,
	duration: number?,
	after: MoveState?,
	dash: boolean,
	to: { [MoveState]: true },
}

export type WallHit = {
	kind: "Run" | "Cling",
	side: ("Left" | "Right")?,
	normal: Vector3,
	part: BasePart,
}

export type VaultHit = {
	kind: "Low" | "Mid",
	part: BasePart,
	point: Vector3,
	normal: Vector3,
}

return {}
