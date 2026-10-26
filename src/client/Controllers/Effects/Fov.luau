--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Context = require(script.Parent.Parent.Movement.Context)

type Ctx = Context.Ctx

local RANGE = Config.MOMENTUM_MAX - Config.WALK_SPEED

-- the camera widens with speed, only for the local character
local Fov = {}

function Fov.load(c: Ctx)
	local camera = workspace.CurrentCamera
	-- speed alone tops out quickly on a ramp, so a downhill slide widens past it on its own slower ease
	local downhill = 0
	c.trove:Connect(RunService.PreRender, function(dt: number)
		local v = c.root.AssemblyLinearVelocity
		local t = math.clamp((Vector3.new(v.X, 0, v.Z).Magnitude - Config.WALK_SPEED) / RANGE, 0, 1)
		local slope = if c.state == "Slide" then math.max(0, c.slope) else 0
		downhill += (slope * Config.FOV_SLOPE - downhill) * (1 - math.exp(-dt / Config.FOV_SLOPE_TIME))

		local target = Config.FOV_BASE + (Config.FOV_MAX - Config.FOV_BASE) * t + downhill
		camera.FieldOfView += (target - camera.FieldOfView) * (1 - math.exp(-dt / Config.FOV_TIME))
	end)
	c.trove:Add(function()
		camera.FieldOfView = Config.FOV_BASE
	end)
end

return Fov
