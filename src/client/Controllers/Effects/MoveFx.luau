--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MoveDefs = require(ReplicatedStorage.Shared.Movement.MoveDefs)
local Probes = require(ReplicatedStorage.Shared.Movement.Probes)
local Types = require(ReplicatedStorage.Shared.Types)
local Vfx = require(script.Parent.Vfx)

local FEET = Vector3.new(0, -Config.ROOT_HEIGHT, 0)
-- the body is already pushing off a wall when its state starts, so the probe reaches further than a grab's
local WALL_REACH = Config.WALL_REACH * 2
local LOOP_PREFIX = "Vfx"

local AT_FEET: { [Types.MoveState]: true } = {
	Jump = true,
	DoubleJump = true,
	SlideJump = true,
	LedgeLeap = true,
	Mantle = true,
}
local AT_WALL: { [Types.MoveState]: true } = { WallLeap = true, WallBoost = true, WallCling = true }
-- on for the whole state, made once per character and kept on its root like the looping sounds
local LOOPS: { [Types.MoveState]: true } = { Slide = true, WallRun = true }
-- the four dashes share one effect turned the way each goes, forward is -Z
local DASH_TURNS: { [Types.MoveState]: CFrame } = {
	DashF = CFrame.identity,
	DashB = CFrame.Angles(0, math.pi, 0),
	DashL = CFrame.Angles(0, math.pi / 2, 0),
	DashR = CFrame.Angles(0, -math.pi / 2, 0),
}

-- the movement effects, from Vfx/Movement, for every character near the camera as its state changes
local MoveFx = {}

local function isNear(root: BasePart): boolean
	return (root.Position - workspace.CurrentCamera.CFrame.Position).Magnitude <= Config.VFX_RANGE
end

local function feet(root: BasePart): CFrame
	local look = root.CFrame.LookVector
	local floor = Probes.ground(root)
	if floor then
		return Vfx.surface(floor.Position, floor.Normal, look)
	end
	return Vfx.surface(root.Position + FEET, Vector3.yAxis, look)
end

-- probed here for every character, other players' clients only know the state. nil once the wall is out of reach
local function wall(root: BasePart): CFrame?
	local hit = Probes.wall(root, math.huge, WALL_REACH)
	return if hit then Vfx.surface(hit.point, hit.normal, Vector3.yAxis) else nil
end

function MoveFx.state(root: BasePart, from: Types.MoveState, to: Types.MoveState, isLanding: boolean)
	if LOOPS[from] then
		Vfx.stopLoop(root, `{LOOP_PREFIX}{from}`)
	end
	if not isNear(root) then
		return
	end

	if isLanding then
		Vfx.at(Vfx.template("Movement", "Land"), feet(root))
	end
	if MoveDefs[to].isDash then
		Vfx.on(Vfx.template("Movement", "Dash"), root, DASH_TURNS[to] or CFrame.identity)
	elseif AT_FEET[to] then
		Vfx.at(Vfx.template("Movement", to), feet(root))
	elseif AT_WALL[to] then
		Vfx.at(Vfx.template("Movement", to), wall(root) or root.CFrame)
	elseif to == "Slide" then
		Vfx.loop(Vfx.template("Movement", to), root, `{LOOP_PREFIX}{to}`, CFrame.new(FEET))
	elseif to == "WallRun" then
		local at = wall(root)
		local offset = if at then root.CFrame:ToObjectSpace(at) else CFrame.identity
		Vfx.loop(Vfx.template("Movement", to), root, `{LOOP_PREFIX}{to}`, offset)
	end
end

return MoveFx
