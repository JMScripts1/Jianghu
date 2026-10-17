--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Context = require(script.Parent.Context)

local Dash = {}

-- from the movement keys held, relative to the character, forward with none held
function Dash.direction(ctx: Context.Context): Types.DashDir
	local move = ctx.hum.MoveDirection
	if move.Magnitude == 0 then
		return "F"
	end

	local cf = ctx.root.CFrame
	local forward = move:Dot(cf.LookVector)
	local right = move:Dot(cf.RightVector)
	if math.abs(forward) >= math.abs(right) then
		return if forward >= 0 then "F" else "B"
	end
	return if right > 0 then "R" else "L"
end

function Dash.start(ctx: Context.Context, dir: Types.DashDir)
	local cf = ctx.root.CFrame
	local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z).Unit
	local right = Vector3.new(cf.RightVector.X, 0, cf.RightVector.Z).Unit
	local v = if dir == "F" then look elseif dir == "B" then -look elseif dir == "R" then right else -right

	Context.setVelocity(ctx, v * Config.DASH_SPEED, false)
	ctx.dashUntil = os.clock() + Config.DASH_TIME
end

function Dash.update(ctx: Context.Context)
	if os.clock() >= ctx.dashUntil then
		Dash.stop(ctx)
	end
end

function Dash.stop(ctx: Context.Context)
	ctx.dashUntil = 0
	ctx.velocity.Enabled = false
end

return Dash
