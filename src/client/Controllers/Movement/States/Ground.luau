--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Probes = require(ReplicatedStorage.Shared.Probes)
local Types = require(ReplicatedStorage.Shared.Types)
local Context = require(script.Parent.Parent.Context)

local Ground = {}

local leftGroundAt: number? = nil

function Ground.enter(ctx: Context.Context)
	ctx.hum.AutoRotate = true
	leftGroundAt = nil
end

function Ground.update(ctx: Context.Context, dt: number): Types.MoveState?
	local now = os.clock()
	if Probes.ground(ctx.root) then
		leftGroundAt = nil
	else
		local left = leftGroundAt or now
		leftGroundAt = left
		if now - left >= Config.COYOTE then
			return "Fall"
		end
	end

	local state = ctx.state
	local crouched = state == "CrouchIdle" or state == "CrouchWalk"
	local move = ctx.hum.MoveDirection
	local moving = move.Magnitude > 0

	if state == "Run" then
		ctx.momentum = math.max(ctx.momentum, Config.RUN_SPEED)
		local look = ctx.root.CFrame.LookVector
		if move:Dot(Vector3.new(look.X, 0, look.Z).Unit) >= Config.RUN_STRAIGHT then
			ctx.momentum += Config.RUN_BUILD * dt
		end
	elseif now - ctx.landedAt >= Config.LAND_GRACE then
		local base = if crouched then Config.CROUCH_SPEED else Config.WALK_SPEED
		ctx.momentum = math.max(base, ctx.momentum - Config.MOMENTUM_GROUND_DECAY * dt)
	end
	ctx.hum.WalkSpeed = ctx.momentum

	if (state == "Walk" or state == "Run") and moving then
		local hit = Probes.vaultLow(ctx.root)
		if hit and -hit.normal:Dot(move) >= Config.VAULT_TOWARD then
			ctx.vaultHit = hit
			return "VaultLow"
		end
	end

	local want: Types.MoveState = if ctx.input.sprint and moving
		then "Run"
		elseif crouched then (if moving then "CrouchWalk" else "CrouchIdle")
		elseif moving then "Walk"
		else "Idle"
	return if want ~= state then want else nil
end

function Ground.exit(_: Context.Context) end

return Ground
