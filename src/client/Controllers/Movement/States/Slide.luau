--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Probes = require(ReplicatedStorage.Shared.Probes)
local Types = require(ReplicatedStorage.Shared.Types)
local Context = require(script.Parent.Parent.Context)

local Slide = {}

local slideDir = Vector3.zAxis

function Slide.enter(ctx: Context.Context)
	local v = ctx.root.AssemblyLinearVelocity
	local flat = Vector3.new(v.X, 0, v.Z)
	local look = ctx.root.CFrame.LookVector
	slideDir = if flat.Magnitude > 1 then flat.Unit else Vector3.new(look.X, 0, look.Z).Unit

	ctx.momentum += Context.gain(ctx, "Slide", ctx.momentum * (Config.SLIDE_BOOST - 1))
	Context.face(ctx, slideDir)
end

function Slide.update(ctx: Context.Context, dt: number): Types.MoveState?
	local floor = Probes.ground(ctx.root)
	if not floor then
		return "Fall"
	end

	local n = floor.Normal
	if n.Y < Config.SLOPE_MIN_Y then
		-- the flat part of the normal points downhill, so this adds going down and drains going up
		ctx.momentum += Config.SLOPE_GAIN * Vector3.new(n.X, 0, n.Z):Dot(slideDir) * dt
	else
		ctx.momentum -= Config.SLIDE_DECAY * dt
	end

	if ctx.momentum < Config.SLIDE_END_SPEED then
		return if ctx.input.sprint then "Run" else "CrouchWalk"
	end
	Context.setVelocity(ctx, slideDir * ctx.momentum, false)
	return nil
end

function Slide.exit(ctx: Context.Context)
	Context.release(ctx)
end

return Slide
