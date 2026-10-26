--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Types = require(ReplicatedStorage.Shared.Types)

-- the old solver can't match Trove's generic methods against the exported Trove type
type Trove = typeof(Trove.new())

local MOVER_FORCE = 1e5
-- slower than this there is no direction of travel worth keeping
local MIN_TRAVEL = 1

local UNUSED_STATES = {
	Enum.HumanoidStateType.Climbing,
	Enum.HumanoidStateType.FallingDown,
	Enum.HumanoidStateType.Ragdoll,
	Enum.HumanoidStateType.GettingUp,
}

export type DashRun = {
	isAir: boolean,
	-- a forward dash in the air, it builds momentum and carries on where it went
	isAirDash: boolean,
	-- the back dash keeps the direction it started in, and boostedAt is set by its animation's Boost marker
	back: Vector3?,
	boostedAt: number?,
	-- every speed is this times its usual one, shorter inside a juggle so it can get round the target
	scale: number,
}

export type MantleRun = {
	trove: Trove,
	mover: AlignPosition,
	-- 0 to 1 through the mantle, to where the root should be
	at: (number) -> Vector3,
}

export type Ctx = {
	char: Model,
	hum: Humanoid,
	root: BasePart,
	rootJoint: Motor6D,
	attach: Attachment,
	lv: LinearVelocity,
	align: AlignOrientation,
	-- holds height through a juggle, the up axis only, see CombatController
	hold: AlignPosition,
	trove: Trove,

	state: Types.MoveState,
	prev: Types.MoveState,
	since: number,
	-- the length of the animation the state started with, for a state that lasts exactly as long
	animLength: number,
	momentum: number,
	heading: Vector3,
	airJumps: number,
	hasAirDashed: boolean,
	landedAt: number,
	takeoffY: number,
	rollUntil: number,
	lastWallPart: BasePart?,
	-- the wall states already used on lastWallPart, a wall takes one cling and one run
	wallGrabs: { [Types.MoveState]: true },
	cooldownUntil: { [Types.MoveState]: number },
	-- uses in a row of each move that gains momentum, see Context.gain
	repeats: { [Types.MoveState]: number },
	usedAt: { [Types.MoveState]: number },
	-- the slide's floor along its heading, see Probes.slope
	slope: number,
	-- a juggle is holding the body up, set by CombatController each step
	isHeldUp: boolean,
	isRampLeap: boolean,
	lean: Vector2,
	leanBase: CFrame,
	leanSet: CFrame,

	wall: Types.WallHit?,
	ledge: Types.LedgeHit?,
	mantling: MantleRun?,
	dash: DashRun?,
}

local Context = {}

function Context.new(char: Model): Ctx
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	local root = char:WaitForChild("HumanoidRootPart") :: BasePart
	local rootJoint = root:WaitForChild("RootJoint") :: Motor6D
	local trove = Trove.new()

	hum.UseJumpPower = true
	hum.JumpPower = Config.JUMP_POWER
	for _, state in UNUSED_STATES do
		hum:SetStateEnabled(state, false)
	end

	local attach = Instance.new("Attachment")
	attach.Parent = root
	trove:Add(attach)

	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = attach
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.MaxForce = MOVER_FORCE
	lv.PrimaryTangentAxis = Vector3.xAxis
	lv.SecondaryTangentAxis = Vector3.zAxis
	lv.Enabled = false
	lv.Parent = root
	trove:Add(lv)

	local align = Instance.new("AlignOrientation")
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attach
	align.RigidityEnabled = true
	align.Enabled = false
	align.Parent = root
	trove:Add(align)

	local hold = Instance.new("AlignPosition")
	hold.Mode = Enum.PositionAlignmentMode.OneAttachment
	hold.Attachment0 = attach
	hold.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	hold.MaxAxesForce = Vector3.new(0, Config.JUGGLE_FORCE, 0)
	hold.MaxVelocity = Config.LAUNCH_RISE / Config.LAUNCH_TIME
	hold.Responsiveness = Config.JUGGLE_RESPONSIVENESS
	hold.Enabled = false
	hold.Parent = root
	trove:Add(hold)

	return {
		char = char,
		hum = hum,
		root = root,
		rootJoint = rootJoint,
		attach = attach,
		lv = lv,
		align = align,
		hold = hold,
		trove = trove,

		state = "Idle",
		prev = "Idle",
		since = os.clock(),
		animLength = 0,
		momentum = Config.WALK_SPEED,
		heading = Vector3.zero,
		airJumps = 0,
		hasAirDashed = false,
		landedAt = 0,
		takeoffY = 0,
		rollUntil = 0,
		wallGrabs = {},
		cooldownUntil = {},
		repeats = {},
		usedAt = {},
		slope = 0,
		isHeldUp = false,
		isRampLeap = false,
		lean = Vector2.zero,
		leanBase = CFrame.identity,
		leanSet = CFrame.identity,
	}
end

function Context.isReady(c: Ctx, state: Types.MoveState): boolean
	return os.clock() >= (c.cooldownUntil[state] or 0)
end

-- raises momentum toward `to`, capped, and a move used again before REPEAT_RESET gets less of the gap each time
function Context.gain(c: Ctx, move: Types.MoveState, to: number)
	local now = os.clock()
	local last = c.usedAt[move]
	local count = if last and now - last < Config.REPEAT_RESET then (c.repeats[move] or 0) + 1 else 0
	c.repeats[move] = count
	c.usedAt[move] = now

	local target = math.min(Config.MOMENTUM_MAX, to)
	if target > c.momentum then
		c.momentum += (target - c.momentum) * Config.REPEAT_FALLOFF ^ count
	end
end

function Context.look(c: Ctx): Vector3
	local look = c.root.CFrame.LookVector
	return Vector3.new(look.X, 0, look.Z).Unit
end

function Context.travel(c: Ctx): Vector3
	local v = c.root.AssemblyLinearVelocity
	local flat = Vector3.new(v.X, 0, v.Z)
	return if flat.Magnitude > MIN_TRAVEL then flat.Unit else Vector3.zero
end

-- both flat and unit, turns around Y by at most maxAngle radians
function Context.turn(from: Vector3, to: Vector3, maxAngle: number): Vector3
	local angle = math.acos(math.clamp(from:Dot(to), -1, 1))
	if angle <= maxAngle then
		return to
	end
	local sign = if from:Cross(to).Y < 0 then -1 else 1
	return CFrame.Angles(0, sign * maxAngle, 0) * from
end

-- drives X and Z only, gravity keeps Y
function Context.glide(c: Ctx, velocity: Vector3)
	local lv = c.lv
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	lv.PlaneVelocity = Vector2.new(velocity.X, velocity.Z)
	lv.Enabled = true
end

function Context.drive(c: Ctx, velocity: Vector3)
	local lv = c.lv
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.VectorVelocity = velocity
	lv.Enabled = true
end

function Context.face(c: Ctx, dir: Vector3)
	c.align.CFrame = CFrame.lookAt(Vector3.zero, dir)
	c.align.Enabled = true
	c.hum.AutoRotate = false
end

function Context.release(c: Ctx)
	c.lv.Enabled = false
	c.align.Enabled = false
	c.hum.AutoRotate = true
end

return Context
