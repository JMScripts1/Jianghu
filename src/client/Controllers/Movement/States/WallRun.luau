--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Probes = require(ReplicatedStorage.Shared.Probes)
local Types = require(ReplicatedStorage.Shared.Types)
local Context = require(script.Parent.Parent.Context)
local Air = require(script.Parent.Air)

local WallRun = {}

local wallDir = Vector3.zAxis

function WallRun.enter(ctx: Context.Context)
	local hit = ctx.wallHit :: Types.WallHit

	if ctx.state == "WallRun" then
		local look = ctx.root.CFrame.LookVector
		local along = look - hit.normal * look:Dot(hit.normal)
		wallDir = Vector3.new(along.X, 0, along.Z).Unit
		ctx.lastWallPart = hit.part
		Context.face(ctx, wallDir)
	else
		ctx.momentum += Context.gain(ctx, "WallLeap", Config.LEAP_GAIN)
		local push = wallDir * ctx.momentum + hit.normal * Config.LEAP_OUT
		ctx.root.AssemblyLinearVelocity = Vector3.new(push.X, Config.LEAP_UP, push.Z)
		Context.setVelocity(ctx, push, false)
		Context.face(ctx, push.Unit)
	end
end

function WallRun.update(ctx: Context.Context, dt: number): Types.MoveState?
	local land: Types.MoveState? = Air.landing(ctx)
	if land then
		return land
	elseif ctx.state == "WallLeap" then
		return nil
	end

	ctx.momentum -= Config.WALLRUN_DECAY * dt
	local hit = Probes.wall(ctx.root, ctx.momentum)
	if not hit or hit.kind ~= "Run" then
		return "Fall"
	end
	Context.setVelocity(ctx, wallDir * ctx.momentum - Vector3.yAxis * Config.WALLRUN_FALL_SPEED, true)
	return nil
end

function WallRun.exit(ctx: Context.Context)
	Context.release(ctx)
end

return WallRun
