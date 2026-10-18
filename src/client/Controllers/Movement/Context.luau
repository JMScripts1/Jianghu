--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Trove = require(ReplicatedStorage.Packages.Trove)

local SPAWN_STATE: Types.MoveState = "Idle"

-- typed from the constructor, the exported Trove type doesn't compare equal to itself in the old solver
type Trove = typeof(Trove.new())

-- jumps are applied by hand and wall movement replaces climbing
local UNUSED_STATES = {
	Enum.HumanoidStateType.Jumping,
	Enum.HumanoidStateType.Climbing,
	Enum.HumanoidStateType.FallingDown,
	Enum.HumanoidStateType.Ragdoll,
}

export type Input = {
	sprint: boolean,
	crouch: boolean,
}

export type Context = {
	char: Model,
	hum: Humanoid,
	root: BasePart,
	animator: Animator,
	attachment: Attachment,
	velocity: LinearVelocity,
	align: AlignOrientation,
	trove: Trove,
	input: Input,

	state: Types.MoveState,
	prev: Types.MoveState,
	since: number,
	endsAt: number?,
	cooldownUntil: { [Types.MoveState]: number },

	momentum: number,
	repeats: { [Types.MoveState]: { count: number, at: number } },
	landedAt: number,
	airJumps: number,
	wallHit: Types.WallHit?,
	lastWallPart: BasePart?,
	leftWallAt: number,
	vaultHit: Types.VaultHit?,
	dashUntil: number,
	dashReadyAt: number,
}

export type StateModule = {
	enter: (ctx: Context) -> (),
	update: (ctx: Context, dt: number) -> Types.MoveState?,
	exit: (ctx: Context) -> (),
}

local Context = {}

function Context.new(char: Model, input: Input): Context
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	local root = char:WaitForChild("HumanoidRootPart") :: BasePart
	-- the one the server made, so the tracks replicate to everyone else
	local animator = hum:WaitForChild("Animator") :: Animator
	local trove = Trove.new()

	for _, state in UNUSED_STATES do
		hum:SetStateEnabled(state, false)
	end

	local attachment = trove:Add(Instance.new("Attachment"))
	attachment.Parent = root

	local velocity = trove:Add(Instance.new("LinearVelocity"))
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.PrimaryTangentAxis = Vector3.xAxis
	velocity.SecondaryTangentAxis = Vector3.zAxis
	velocity.MaxForce = math.huge
	velocity.Enabled = false
	velocity.Parent = root

	local align = trove:Add(Instance.new("AlignOrientation"))
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.MaxTorque = math.huge
	align.Responsiveness = Config.MOVER_RESPONSIVENESS
	align.Enabled = false
	align.Parent = root

	local now = os.clock()
	return {
		char = char,
		hum = hum,
		root = root,
		animator = animator,
		attachment = attachment,
		velocity = velocity,
		align = align,
		trove = trove,
		input = input,

		state = SPAWN_STATE,
		prev = SPAWN_STATE,
		since = now,
		cooldownUntil = {},

		momentum = Config.WALK_SPEED,
		repeats = {},
		landedAt = 0,
		airJumps = 0,
		leftWallAt = 0,
		dashUntil = 0,
		dashReadyAt = 0,
	}
end

function Context.ready(ctx: Context, state: Types.MoveState): boolean
	return os.clock() >= (ctx.cooldownUntil[state] or 0)
end

-- holdY false leaves the vertical to gravity
function Context.setVelocity(ctx: Context, v: Vector3, holdY: boolean)
	local mover = ctx.velocity
	if holdY then
		mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
		mover.VectorVelocity = v
	else
		mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
		mover.PlaneVelocity = Vector2.new(v.X, v.Z)
	end
	mover.Enabled = true
end

function Context.face(ctx: Context, dir: Vector3)
	ctx.hum.AutoRotate = false
	ctx.align.CFrame = CFrame.lookAt(Vector3.zero, dir)
	ctx.align.Enabled = true
end

function Context.release(ctx: Context)
	ctx.velocity.Enabled = false
	ctx.align.Enabled = false
	ctx.hum.AutoRotate = true
end

-- the same move gains less each time in a row, until REPEAT_RESET passes without it
function Context.gain(ctx: Context, move: Types.MoveState, amount: number): number
	local now = os.clock()
	local streak = ctx.repeats[move]
	local count = if streak and now - streak.at < Config.REPEAT_RESET then streak.count + 1 else 0
	ctx.repeats[move] = { count = count, at = now }
	return amount * Config.REPEAT_FALLOFF ^ count
end

return Context
