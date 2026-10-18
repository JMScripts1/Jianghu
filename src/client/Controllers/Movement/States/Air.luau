--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MoveDefs = require(ReplicatedStorage.Shared.MoveDefs)
local Probes = require(ReplicatedStorage.Shared.Probes)
local Types = require(ReplicatedStorage.Shared.Types)
local Context = require(script.Parent.Parent.Context)

-- still going up faster than this means the ground under us is the one we just left. a humanoid at rest
-- never reads exactly 0, so stepping up onto a ledge without falling first would never land against 0
local RISING = 1

local Air = {}

-- the carried direction, steering turns it but never adds speed
local airDir = Vector3.zero

-- whichever grounded state input and momentum call for, nil while still in the air
function Air.landing(ctx: Context.Context): Types.MoveState?
	if ctx.root.AssemblyLinearVelocity.Y > RISING or not Probes.ground(ctx.root) then
		return nil
	end

	local input = ctx.input
	local moving = ctx.hum.MoveDirection.Magnitude > 0
	if input.crouch and ctx.momentum >= Config.SLIDE_MIN_SPEED and Context.ready(ctx, "Slide") then
		return "Slide"
	elseif input.sprint and moving then
		return "Run"
	elseif input.crouch then
		return if moving then "CrouchWalk" else "CrouchIdle"
	end
	return if moving then "Walk" else "Idle"
end

function Air.enter(ctx: Context.Context)
	local state = ctx.state
	local root = ctx.root
	ctx.hum.AutoRotate = true

	if MoveDefs[ctx.prev].group ~= "Airborne" then
		local v = root.AssemblyLinearVelocity
		local flat = Vector3.new(v.X, 0, v.Z)
		airDir = if flat.Magnitude > 1 then flat.Unit else Vector3.zero
	end

	if state == "SlideJump" then
		ctx.momentum += Context.gain(ctx, "SlideJump", Config.SLIDE_JUMP_GAIN)
	end

	if state ~= "Fall" then
		local power = if state == "DoubleJump" then Config.DOUBLE_JUMP_POWER else Config.JUMP_POWER
		local v = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(v.X, power, v.Z)
		ctx.hum:ChangeState(Enum.HumanoidStateType.Freefall)
	end
end

function Air.update(ctx: Context.Context, dt: number): Types.MoveState?
	local land: Types.MoveState? = Air.landing(ctx)
	if land then
		return land
	end

	ctx.momentum = math.max(Config.WALK_SPEED, ctx.momentum - Config.MOMENTUM_AIR_DECAY * dt)

	local wish = ctx.hum.MoveDirection
	if wish.Magnitude > 0 then
		airDir = if airDir == Vector3.zero
			then wish
			else Context.turn(airDir, wish, math.rad(Config.AIR_TURN_RATE) * dt)
	end

	-- runs after the default controls each frame, so this is the direction physics uses
	ctx.hum.WalkSpeed = ctx.momentum
	ctx.hum:Move(airDir)
	return nil
end

function Air.exit(_: Context.Context) end

return Air
