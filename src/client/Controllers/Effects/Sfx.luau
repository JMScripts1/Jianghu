--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Footsteps = require(ReplicatedStorage.Shared.Movement.Footsteps)
local MoveDefs = require(ReplicatedStorage.Shared.Movement.MoveDefs)
local Probes = require(ReplicatedStorage.Shared.Movement.Probes)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local Types = require(ReplicatedStorage.Shared.Types)

-- sinceStep counts seconds of moving toward the next footstep
type Walker = { root: BasePart, state: () -> Types.MoveState?, sinceStep: number }

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

-- movement sounds for every character in range of hearing, played on its root so they come from where it happened
local Sfx = {}

local walkers: { [Model]: Walker } = {}

local function slot(state: Types.MoveState): Types.SoundName
	return if MoveDefs[state].isDash then "Dash" else state
end

-- a ground dash is airborne on paper and a mantle ends standing, neither is a landing you'd hear
local function isLanding(from: Types.MoveState, to: Types.MoveState): boolean
	local def = MoveDefs[from]
	return MoveDefs[to].group == "Grounded" and def.group ~= "Grounded" and not def.isDash and from ~= "Mantle"
end

-- made once per character and kept on its root
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

function Sfx.state(root: BasePart, from: Types.MoveState, to: Types.MoveState)
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

function Sfx.add(char: Model, root: BasePart, state: () -> Types.MoveState?)
	walkers[char] = { root = root, state = state, sinceStep = 0 }
end

function Sfx.remove(char: Model)
	walkers[char] = nil
end

-- steps keep time with the animation, not the speed, and the floor is only read when one is due
function Sfx.step(dt: number)
	for _, walker in walkers do
		local state: Types.MoveState? = walker.state()
		local interval = if state then STEP_TIMES[MoveDefs[state].wire] else nil
		local v = walker.root.AssemblyLinearVelocity
		if not interval or Vector3.new(v.X, 0, v.Z).Magnitude < MIN_STEP_SPEED then
			walker.sinceStep = 0
			continue
		end

		walker.sinceStep += dt
		if walker.sinceStep < interval then
			continue
		end
		walker.sinceStep -= interval

		local floor = Probes.ground(walker.root)
		if floor then
			footstep(walker.root, floor.Material):Play()
		end
	end
end

return Sfx
