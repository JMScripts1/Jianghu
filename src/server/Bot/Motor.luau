--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatDefs = require(ReplicatedStorage.Shared.Combat.CombatDefs)
local Config = require(ReplicatedStorage.Shared.Config)
local MoveDefs = require(ReplicatedStorage.Shared.Movement.MoveDefs)
local Probes = require(ReplicatedStorage.Shared.Movement.Probes)
local Types = require(ReplicatedStorage.Shared.Types)
local MovementService = require(script.Parent.Parent.Services.MovementService)
local StateService = require(script.Parent.Parent.Services.StateService)

-- a dash in progress, run the way the client's Dash runs a player's
type DashRun = {
	state: Types.MoveState,
	startedAt: number,
	isAir: boolean,
	isAirDash: boolean,
	-- the back dash keeps the direction it started in
	back: Vector3,
	-- shorter inside a juggle, so it can get round the target
	scale: number,
	-- the speed it brakes back onto, what it was walking or running at
	momentum: number,
}

export type Body = {
	char: Model,
	hum: Humanoid,
	root: BasePart,
	attach: Attachment,
	lv: LinearVelocity,
	align: AlignOrientation,
	-- flat and unit, or zero to stand
	heading: Vector3,
	isRunning: boolean,
	-- where it keeps its front pointed, nil leaves it as it is
	facing: Vector3?,
	dash: DashRun?,
}

local MOVER_FORCE = 1e5
-- turns quickly but not in one frame, a snap reads as a bot
local TURN_RESPONSIVENESS = 40
local TURN_TORQUE = 1e6
-- the same lines the client lands on, see Air
local RISING = 1
local MIN_FACING = 0.1
local HOLD = Config.DASH_TIME * (1 - Config.DASH_TAIL)
local BACK_DASH_END = Config.BACK_DASH_WINDUP + Config.BACK_DASH_BOOST_TIME

-- every enabled Humanoid state is checked every frame, so the ones a bot never uses are off. ChangeState ignores
-- this, and Ragdoll and Juggle only ever change to Physics, Running and Freefall
local UNUSED_STATES = {
	Enum.HumanoidStateType.Climbing,
	Enum.HumanoidStateType.FallingDown,
	Enum.HumanoidStateType.Ragdoll,
	Enum.HumanoidStateType.GettingUp,
	Enum.HumanoidStateType.Swimming,
	Enum.HumanoidStateType.Seated,
	Enum.HumanoidStateType.Flying,
	Enum.HumanoidStateType.StrafingNoPhysics,
}

-- held where it is by a pin, a grip or the ragdoll. turning would stand a ragdoll back up, and a broken guard can't turn
local STILL: { [Types.CombatState]: true } = {
	Downed = true,
	Gripped = true,
	Gripping = true,
	WallStunned = true,
	FloorStunned = true,
	PostureBroken = true,
}

-- the server owns the bot, so it moves the body the way a player's client moves its own, and records every move
-- through MovementService.act with the same checks a player's get
local Motor = {}

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > MIN_FACING then f.Unit else Vector3.zero
end

local function isGrounded(body: Body): boolean
	return body.hum.FloorMaterial ~= Enum.Material.Air or Probes.ground(body.root) ~= nil
end

local function glide(body: Body, velocity: Vector3)
	local lv = body.lv
	lv.PlaneVelocity = Vector2.new(velocity.X, velocity.Z)
	lv.Enabled = true
end

local function rise(body: Body, speed: number)
	local v = body.root.AssemblyLinearVelocity
	body.root.AssemblyLinearVelocity = Vector3.new(v.X, speed, v.Z)
end

-- re-read every step like the client's, so turning to keep facing the target bends a side dash round it
local function direction(body: Body, run: DashRun): Vector3
	if run.state == "DashB" then
		return run.back
	end
	local look = flat(body.root.CFrame.LookVector)
	if run.state == "DashF" then
		return look
	end
	local right = look:Cross(Vector3.yAxis)
	return if run.state == "DashR" then right else -right
end

-- a dash ends on its own, or early when a stun or a pin cuts it, and hands over to the ground or the fall
local function endDash(body: Body)
	body.dash = nil
	body.lv.Enabled = false
	MovementService.act(body.char, if isGrounded(body) then "Walk" else "Fall")
end

-- the client's burst and back dash, see Dash. the back dash's burst comes at BACK_DASH_WINDUP, where the client's
-- animation reaches its Boost marker
local function stepDash(body: Body, run: DashRun, now: number)
	local elapsed = now - run.startedAt
	local speed
	if run.state == "DashB" then
		if elapsed >= BACK_DASH_END then
			endDash(body)
			return
		end
		local boost = if elapsed >= Config.BACK_DASH_WINDUP then Config.BACK_DASH_BOOST else Config.BACK_DASH_DRIFT
		speed = Config.BACK_DASH_SPEED * boost * run.scale
	else
		if elapsed >= Config.DASH_TIME then
			endDash(body)
			return
		end
		local fade = if run.isAirDash then 0 else math.max(0, elapsed - HOLD) / (Config.DASH_TIME - HOLD)
		local peak = math.max(if run.isAirDash then Config.AIR_DASH_SPEED else Config.DASH_SPEED, run.momentum)
			* run.scale
		speed = peak + (run.momentum - peak) * fade
		if run.isAir and elapsed < Config.DASH_AIR_HOLD then
			rise(body, if run.isAirDash then Config.AIR_DASH_LIFT else 0)
		end
	end
	glide(body, direction(body, run) * speed)
end

-- the walk speed a player in the same state would have, a held delay slows it right down like the client's
local function walkSpeed(
	body: Body,
	st: StateService.CharState,
	combat: Types.CombatState,
	move: Types.MoveState
): number
	local speed = if move == "CrouchWalk"
		then Config.CROUCH_SPEED
		elseif body.isRunning then Config.RUN_SPEED
		else Config.WALK_SPEED
	local swing = st.combat.swing
	local cap = if swing
			and swing.delayedAt
			and not swing.hitAt
		then Config.DELAY_WALK_SPEED
		else CombatDefs.speedCaps[combat] or math.huge
	return math.min(speed, cap)
end

function Motor.new(char: Model, hum: Humanoid, root: BasePart): Body
	for _, state in UNUSED_STATES do
		hum:SetStateEnabled(state, false)
	end
	-- it faces with the align instead, so it can strafe
	hum.AutoRotate = false

	local attach = Instance.new("Attachment")
	attach.Parent = root

	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = attach
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	lv.PrimaryTangentAxis = Vector3.xAxis
	lv.SecondaryTangentAxis = Vector3.zAxis
	lv.MaxForce = MOVER_FORCE
	lv.Enabled = false
	lv.Parent = attach

	local align = Instance.new("AlignOrientation")
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attach
	align.Responsiveness = TURN_RESPONSIVENESS
	align.MaxTorque = TURN_TORQUE
	align.Enabled = false
	align.Parent = attach

	return {
		char = char,
		hum = hum,
		root = root,
		attach = attach,
		lv = lv,
		align = align,
		heading = Vector3.zero,
		isRunning = false,
	}
end

-- the movers hang off the attachment, so this takes all three
function Motor.remove(body: Body)
	body.attach:Destroy()
end

function Motor.walk(body: Body, dir: Vector3, isRunning: boolean)
	body.heading = flat(dir)
	body.isRunning = isRunning
end

function Motor.face(body: Body, at: Vector3?)
	body.facing = if at then flat(at - body.root.Position) else nil
end

-- off the ground it's the double jump
function Motor.jump(body: Body): boolean
	local from: Types.MoveState = StateService.current(body.char)
	local isGround = MoveDefs[from].group == "Grounded"
	if not MovementService.act(body.char, if isGround then "Jump" else "DoubleJump") then
		return false
	end
	if isGround then
		body.hum:ChangeState(Enum.HumanoidStateType.Jumping)
	end
	rise(body, if isGround then Config.JUMP_POWER else Config.DOUBLE_JUMP_POWER)
	return true
end

function Motor.dash(body: Body, state: Types.MoveState, now: number): boolean
	local st = StateService.get(body.char)
	local from: Types.MoveState = StateService.current(body.char)
	if not st or body.dash or not MovementService.act(body.char, state) then
		return false
	end
	local isAir = MoveDefs[from].group == "Airborne"
	local isJuggled = now < st.combat.juggleUntil
	body.dash = {
		state = state,
		startedAt = now,
		isAir = isAir,
		-- inside a juggle every dash is a plain one for getting round the target, the same as the client's
		isAirDash = isAir and state == "DashF" and not isJuggled,
		back = -flat(body.root.CFrame.LookVector),
		scale = if isJuggled then Config.JUGGLE_DASH_SCALE else 1,
		momentum = if body.isRunning then Config.RUN_SPEED else Config.WALK_SPEED,
	}
	return true
end

function Motor.crouch(body: Body, isOn: boolean): boolean
	return MovementService.act(body.char, if isOn then "CrouchWalk" else "Walk")
end

function Motor.step(body: Body, now: number)
	local char = body.char
	local st = StateService.get(char)
	if not st then
		return
	end
	local combat: Types.CombatState = StateService.combatState(char)
	local move: Types.MoveState = StateService.current(char)
	local isStill = STILL[combat] == true

	-- a stun cuts a dash short the way it does a player's
	local run = body.dash
	if run and (isStill or not StateService.canMove(char, run.state)) then
		endDash(body)
		run = nil
	elseif run then
		stepDash(body, run, now)
		run = body.dash
	end

	local facing = body.facing
	local canTurn = not isStill and facing ~= nil and facing ~= Vector3.zero
	if canTurn then
		body.align.CFrame = CFrame.lookAt(Vector3.zero, facing :: Vector3)
	end
	if body.align.Enabled ~= canTurn then
		body.align.Enabled = canTurn
	end

	local heading = if isStill or run then Vector3.zero else body.heading
	body.hum.WalkSpeed = walkSpeed(body, st, combat, move)
	body.hum:Move(heading)

	-- the same bookkeeping the client's state machine does, so the server's move state stays true to the body
	local group = MoveDefs[move].group
	if run then
		return
	elseif group == "Airborne" then
		if body.root.AssemblyLinearVelocity.Y <= RISING and Probes.ground(body.root) then
			MovementService.act(char, if body.isRunning and heading ~= Vector3.zero then "Run" else "Walk")
		end
	elseif not isGrounded(body) then
		MovementService.act(char, "Fall")
	elseif
		not StateService.canMove(char, move) or (move == "Run" and (not body.isRunning or heading == Vector3.zero))
	then
		-- a swing, a block or a stun can rule out a run or a crouch, so it drops to a walk like a player's client does
		MovementService.act(char, "Walk")
	elseif move == "Walk" and body.isRunning and heading ~= Vector3.zero and StateService.canMove(char, "Run") then
		MovementService.act(char, "Run")
	end
end

return Motor
