--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Footsteps = require(ReplicatedStorage.Shared.Footsteps)
local MoveDefs = require(ReplicatedStorage.Shared.MoveDefs)
local Probes = require(ReplicatedStorage.Shared.Probes)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local Types = require(ReplicatedStorage.Shared.Types)
local Context = require(script.Parent.Movement.Context)

type Ctx = Context.Ctx

-- sinceStep counts seconds of moving toward the next footstep
type Walker = { root: BasePart, state: () -> Types.MoveState?, sinceStep: number }

local FOV_RANGE = Config.MOMENTUM_MAX - Config.WALK_SPEED
-- newer materials and terrain types that have no sound of their own
local FALLBACK_STEP = Footsteps[Enum.Material.Concrete]

local LOOPS: { [Types.SoundName]: true } = { Slide = true, WallRun = true }

-- seconds between footsteps by wire state, anything not listed is silent
local STEP_TIMES: { [Types.MoveState]: number } = {
	Walk = Config.WALK_STEP_TIME,
	Run = Config.RUN_STEP_TIME,
	CrouchWalk = Config.CROUCH_STEP_TIME,
}
-- Idle and CrouchIdle share their wire with the walks, standing still is what keeps them silent
local MIN_STEP_SPEED = 1

-- turns the attribute back into a state, anything else is ignored
local BY_NAME: { [string]: Types.MoveState } = {}
for state: Types.MoveState in MoveDefs do
	BY_NAME[state] = state
end

local player = Players.LocalPlayer

local EffectController = {}

local walkers: { [Model]: Walker } = {}

local function slot(state: Types.MoveState): Types.SoundName
	return if MoveDefs[state].isDash then "Dash" else state
end

-- a ground dash is airborne on paper and a mantle ends standing, neither is a landing you'd hear
local function isLanding(from: Types.MoveState, to: Types.MoveState): boolean
	local def = MoveDefs[from]
	return MoveDefs[to].group == "Grounded" and def.group ~= "Grounded" and not def.isDash and from ~= "Mantle"
end

-- made once per character and kept on its root, so other players hear it from where it happened
local function sound(root: BasePart, name: Types.SoundName): Sound?
	local id = Sounds[name]
	if not id or id == "" then
		return nil
	end
	local made = root:FindFirstChild(name)
	if made and made:IsA("Sound") then
		return made
	end

	local new = Instance.new("Sound")
	new.Name = name
	new.SoundId = id
	new.Looped = LOOPS[name] == true
	new.Parent = root
	return new
end

local function onState(root: BasePart, from: Types.MoveState, to: Types.MoveState)
	local left: Types.SoundName = slot(from)
	if LOOPS[left] then
		local loop = root:FindFirstChild(left)
		if loop and loop:IsA("Sound") then
			loop:Stop()
		end
	end

	if isLanding(from, to) then
		local land = sound(root, "Land")
		if land then
			land:Play()
		end
	end
	local entered = sound(root, slot(to))
	if entered then
		entered:Play()
	end
end

local function footstep(root: BasePart, material: Enum.Material): Sound
	local name = `Footstep{material.Name}`
	local made = root:FindFirstChild(name)
	if made and made:IsA("Sound") then
		return made
	end

	local new = Instance.new("Sound")
	new.Name = name
	new.SoundId = Footsteps[material] or FALLBACK_STEP
	new.RollOffMaxDistance = Config.FOOTSTEP_RANGE
	new.Parent = root
	return new
end

-- steps keep time with the animation, not the speed, and the floor is only read when one is due
local function step(walker: Walker, dt: number)
	local state: Types.MoveState? = walker.state()
	local interval = if state then STEP_TIMES[MoveDefs[state].wire] else nil
	local v = walker.root.AssemblyLinearVelocity
	if not interval or Vector3.new(v.X, 0, v.Z).Magnitude < MIN_STEP_SPEED then
		walker.sinceStep = 0
		return
	end

	walker.sinceStep += dt
	if walker.sinceStep < interval then
		return
	end
	walker.sinceStep -= interval

	local floor = Probes.ground(walker.root)
	if floor then
		footstep(walker.root, floor.Material):Play()
	end
end

local function stateOf(char: Model): Types.MoveState?
	local value = char:GetAttribute("MoveState")
	return if typeof(value) == "string" then BY_NAME[value] else nil
end

-- the local character plays straight from the state machine, the attribute comes back a round trip later
local function watch(char: Model)
	local root = char:WaitForChild("HumanoidRootPart") :: BasePart
	local last: Types.MoveState = stateOf(char) or "Walk"
	char:GetAttributeChangedSignal("MoveState"):Connect(function()
		local state: Types.MoveState? = stateOf(char)
		if state then
			onState(root, last, state)
			last = state
		end
	end)

	walkers[char] = {
		root = root,
		state = function()
			return stateOf(char)
		end,
		sinceStep = 0,
	}
	char.Destroying:Connect(function()
		walkers[char] = nil
	end)
end

local function onPlayerAdded(plr: Player)
	if plr == player then
		return
	end
	plr.CharacterAdded:Connect(watch)
	if plr.Character then
		task.spawn(watch, plr.Character)
	end
end

function EffectController.load(c: Ctx)
	local camera = workspace.CurrentCamera
	-- speed alone tops out quickly on a ramp, so a downhill slide widens past it on its own slower ease
	local downhill = 0
	c.trove:Connect(RunService.PreRender, function(dt: number)
		local v = c.root.AssemblyLinearVelocity
		local t = math.clamp((Vector3.new(v.X, 0, v.Z).Magnitude - Config.WALK_SPEED) / FOV_RANGE, 0, 1)
		local slope = if c.state == "Slide" then math.max(0, c.slope) else 0
		downhill += (slope * Config.FOV_SLOPE - downhill) * (1 - math.exp(-dt / Config.FOV_SLOPE_TIME))

		local target = Config.FOV_BASE + (Config.FOV_MAX - Config.FOV_BASE) * t + downhill
		camera.FieldOfView += (target - camera.FieldOfView) * (1 - math.exp(-dt / Config.FOV_TIME))
	end)
	c.trove:Add(function()
		camera.FieldOfView = Config.FOV_BASE
	end)

	walkers[c.char] = {
		root = c.root,
		state = function()
			return c.state
		end,
		sinceStep = 0,
	}
	c.trove:Add(function()
		walkers[c.char] = nil
	end)
end

function EffectController.play(c: Ctx)
	onState(c.root, c.prev, c.state)
end

RunService.PreRender:Connect(function(dt: number)
	for _, walker in walkers do
		step(walker, dt)
	end
end)

Players.PlayerAdded:Connect(onPlayerAdded)
for _, plr in Players:GetPlayers() do
	onPlayerAdded(plr)
end

return EffectController
