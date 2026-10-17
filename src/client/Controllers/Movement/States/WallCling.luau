--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Probes = require(ReplicatedStorage.Shared.Probes)
local Types = require(ReplicatedStorage.Shared.Types)
local Context = require(script.Parent.Parent.Context)
local Air = require(script.Parent.Air)

local WallCling = {}

function WallCling.enter(ctx: Context.Context)
	local hit = ctx.wallHit :: Types.WallHit
	Context.face(ctx, -hit.normal)

	if ctx.state == "WallCling" then
		ctx.lastWallPart = hit.part
		ctx.momentum = Config.WALK_SPEED
		Context.setVelocity(ctx, -Vector3.yAxis * Config.CLING_SLIDE_SPEED, true)
	else
		ctx.root.AssemblyLinearVelocity = Vector3.yAxis * Config.BOOST_UP
		Context.setVelocity(ctx, Vector3.zero, false)
	end
end

function WallCling.update(ctx: Context.Context, _: number): Types.MoveState?
	local land: Types.MoveState? = Air.landing(ctx)
	if land then
		return land
	elseif ctx.state == "WallBoost" then
		return nil
	end

	local hit = Probes.wall(ctx.root, 0)
	if not hit or hit.kind ~= "Cling" then
		return "Fall"
	end
	return nil
end

function WallCling.exit(ctx: Context.Context)
	Context.release(ctx)
end

return WallCling
