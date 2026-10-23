--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Probes = require(ReplicatedStorage.Shared.Probes)
local Types = require(ReplicatedStorage.Shared.Types)
local CombatController = require(script.Parent.Parent.Parent.CombatController)
local Context = require(script.Parent.Parent.Context)
local InputController = require(script.Parent.Parent.Parent.InputController)

type Ctx = Context.Ctx

local SPEEDS: { [Types.MoveState]: number } = {
	Idle = Config.WALK_SPEED,
	Walk = Config.WALK_SPEED,
	CrouchIdle = Config.CROUCH_SPEED,
	CrouchWalk = Config.CROUCH_SPEED,
}

local LOW: { [Types.MoveState]: true } = { Slide = true, CrouchIdle = true, CrouchWalk = true }

local Ground = {}

-- either one seeing floor is enough, so a bump or a slope at speed doesn't drop into Fall for a frame
function Ground.isGrounded(c: Ctx): boolean
	return c.hum.FloorMaterial ~= Enum.Material.Air or Probes.ground(c.root) ~= nil
end

function Ground.canSlide(c: Ctx): boolean
	return c.momentum >= Config.SLIDE_MIN_SPEED and Context.isReady(c, "Slide")
end

function Ground.pick(c: Ctx): Types.MoveState
	local isMoving = c.hum.MoveDirection.Magnitude > 0
	local isStuck = LOW[c.state] and Probes.ceiling(c.root) ~= nil
	local standing: Types.MoveState = if isMoving then "Walk" else "Idle"
	local want: Types.MoveState = standing
	if InputController.isDown("Crouch") or isStuck then
		want = if isMoving then "CrouchWalk" else "CrouchIdle"
	elseif isMoving and InputController.isDown("Sprint") then
		want = "Run"
	end
	-- a swing, a block or a stun rules out a run or a crouch, standing is always left
	return if CombatController.allows(c, want) then want else standing
end

function Ground.update(c: Ctx, dt: number): Types.MoveState?
	local state: Types.MoveState = c.state
	local hum = c.hum

	if state == "Run" then
		-- only parkour builds momentum, a plain run lets it go once the hold is up
		if os.clock() - c.since >= Config.RUN_HOLD then
			c.momentum -= Config.RUN_DECAY * dt
		end
		c.momentum = math.max(c.momentum, Config.RUN_SPEED)
	else
		-- walking and crouching drop to their own speed at once, a landing holds on so it can still go into a run or slide
		local target = SPEEDS[state]
		if c.momentum < target or os.clock() - c.landedAt > Config.LAND_GRACE then
			c.momentum = target
		end
	end

	local isHurt = hum.Health <= hum.MaxHealth * Config.HURT_THRESHOLD
	hum.WalkSpeed = if state == "Run" and isHurt then c.momentum - Config.HURT_SPEED_PENALTY else c.momentum
	-- the landing roll carries on forward with no keys held
	if os.clock() < c.rollUntil then
		hum:Move(Context.look(c))
		hum.WalkSpeed = math.max(hum.WalkSpeed, Config.ROLL_SPEED)
	end
	hum.WalkSpeed = math.min(hum.WalkSpeed, CombatController.speedCap(c))

	local isCrouched = state == "CrouchIdle" or state == "CrouchWalk"
	if not Ground.isGrounded(c) then
		return "Fall"
	elseif InputController.take("Jump") and not isCrouched then
		-- from a crouch the press only stands up, it already turned crouch off and the pick below does the rest
		return "Jump"
	elseif state == "Run" and InputController.isDown("Crouch") then
		-- Run can't go straight to CrouchWalk, so a slide on cooldown stands up for one step first
		return if Ground.canSlide(c) then "Slide" else "Walk"
	end

	local nextState: Types.MoveState = Ground.pick(c)
	return if nextState ~= state then nextState else nil
end

return Ground
