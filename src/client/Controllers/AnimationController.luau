--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Anims = require(ReplicatedStorage.Shared.Anims)
local Config = require(ReplicatedStorage.Shared.Config)
local MoveDefs = require(ReplicatedStorage.Shared.MoveDefs)
local Types = require(ReplicatedStorage.Shared.Types)
local Context = require(script.Parent.Movement.Context)
local Dash = require(script.Parent.Movement.Dash)

type Ctx = Context.Ctx

local BOOST_MARKER = "Boost"
local BACK_DASH: Types.AnimName = "DashB"
local RUN: Types.AnimName = "Run"
local ROLL: Types.AnimName = "Roll"
-- the leap takes these in turn, and lasts as long as whichever one plays
local LEAPS: { Types.AnimName } = { "LedgeLeap", "LedgeLeap2", "LedgeLeap3", "LedgeLeap4" }

-- these states outlast their one shot, so the fall loop takes over when it runs out
local THEN_FALL: { [Types.AnimName]: true } = {
	Jump = true,
	DoubleJump = true,
	SlideJump = true,
	WallLeapLeft = true,
	WallLeapRight = true,
	WallBoost = true,
}

local AnimationController = {}

local animations: { [Types.AnimName]: Animation } = {}
local tracks: { [Types.AnimName]: AnimationTrack } = {}
local current: AnimationTrack? = nil
local dashing: AnimationTrack? = nil
-- plays over the state track instead of taking over from it, the walk states keep going underneath
local rolling: AnimationTrack? = nil
local leaps = 0

for name: Types.AnimName, id in Anims do
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	animations[name] = anim
end

-- the air dash is DashF in the air with its own animation, and a cancel plays the way a dash does
local DASH_ANIMS: { Types.AnimName } = { "AirDash", "DashCancelLeft", "DashCancelRight" }
for state: Types.MoveState, def in MoveDefs do
	if def.isDash then
		table.insert(DASH_ANIMS, state)
	end
end

local function isThenFall(track: AnimationTrack): boolean
	for name: Types.AnimName in THEN_FALL do
		if tracks[name] == track then
			return true
		end
	end
	return false
end

-- while a dash plays the state track is only remembered, it starts when the dash ends
local function start(name: Types.AnimName)
	local track = tracks[name]
	-- the leap and boost can outlast their state, and they hand over to the fall loop themselves when they end
	if name == "Fall" and current and current.IsPlaying and isThenFall(current) then
		return
	end
	-- a running jump keeps the run going slowed down instead of cutting to the jump, landing in Run speeds it back up
	if current and current == tracks[RUN] and (name == "Jump" or name == "Run") then
		current:AdjustSpeed(if name == "Jump" then Config.RUN_JUMP_ANIM_SPEED else 1)
		return
	end
	if track == current then
		return
	end
	if current then
		current:Stop(Config.ANIM_FADE)
	end
	current = track
	if track and not dashing then
		track:Play(Config.ANIM_FADE)
	end
end

local function stopRoll()
	if rolling then
		rolling:Stop(Config.ANIM_FADE)
		rolling = nil
	end
end

function AnimationController.load(c: Ctx)
	local animator = c.hum:WaitForChild("Animator") :: Animator
	for name: Types.AnimName, anim in animations do
		local track = animator:LoadAnimation(anim)
		tracks[name] = track
		if THEN_FALL[name] then
			c.trove:Connect(track.Stopped, function()
				if current == track then
					start("Fall")
				end
			end)
		end
	end

	for _, name: Types.AnimName in DASH_ANIMS do
		local track = tracks[name]
		c.trove:Connect(track.Stopped, function()
			if dashing ~= track then
				return
			end
			dashing = nil
			if current then
				current:Play(Config.ANIM_FADE)
			end
		end)
	end

	-- the back dash's burst is keyed to its animation, and the animation slows back down from the quick backstep
	local backDash = tracks[BACK_DASH]
	c.trove:Connect(backDash:GetMarkerReachedSignal(BOOST_MARKER), function()
		Dash.boost(c)
		backDash:AdjustSpeed(backDash.Length / Config.BACK_DASH_ANIM_TIME)
	end)

	c.trove:Add(function()
		table.clear(tracks)
		current = nil
		dashing = nil
		rolling = nil
	end)
end

-- a dash takes over from the state track instead of blending with it, so it plays to the end even once the dash is over
local function dash(name: Types.AnimName)
	local track = tracks[name]
	-- a side dash chains into a front one before its animation is over, so the old one is cut instead of blending in
	if dashing and dashing ~= track then
		dashing:Stop(Config.ANIM_FADE)
	end
	dashing = track
	if current then
		current:Stop(Config.ANIM_FADE)
	end
	track:Play(Config.ANIM_FADE)
	if name == "DashB" then
		track:AdjustSpeed(Config.BACK_DASH_MARKER / Config.BACK_DASH_WINDUP)
	end
end

-- returns the length of the animation the state plays, 0 until it has loaded
function AnimationController.play(c: Ctx): number
	-- a leap keeps the wall it left, so its side is the run's side
	local isLeft = c.wall ~= nil and c.wall.side == "Left"
	if MoveDefs[c.state].isDash then
		dash(if (c.dash :: Context.DashRun).isAirDash then "AirDash" else c.state)
	elseif c.state == "WallRun" then
		start(if isLeft then "WallRunLeft" else "WallRunRight")
	elseif c.state == "WallLeap" then
		start(if isLeft then "WallLeapLeft" else "WallLeapRight")
	elseif c.state == "LedgeLeap" and c.isRampLeap then
		start("RampLeap")
	elseif c.state == "LedgeLeap" then
		leaps = leaps % #LEAPS + 1
		start(LEAPS[leaps])
	else
		start(c.state)
	end

	-- the mantle's path is keyed to its animation, so the animation is stretched to the mantle's length
	if c.mantling and current and current.Length > 0 then
		current:AdjustSpeed(current.Length / Config.MANTLE_TIME)
	end

	if os.clock() >= c.rollUntil then
		stopRoll()
	end

	local playing = if MoveDefs[c.state].isDash then dashing else current
	return if playing then playing.Length else 0
end

-- a dash animation plays out after its dash, so a swing that starts in its tail cuts it instead of blending in.
-- the state track comes back from the Stopped handler in load
function AnimationController.stopDash()
	if dashing then
		dashing:Stop(Config.ANIM_FADE)
	end
end

-- the dash's animation hands over to the cancel's, which a swing cuts like any dash animation, see stopDash
function AnimationController.cancelDash(isLeft: boolean)
	dash(if isLeft then "DashCancelLeft" else "DashCancelRight")
end

function AnimationController.roll()
	local track = tracks[ROLL]
	rolling = track
	track:Play(Config.ANIM_FADE)
	if track.Length > 0 then
		track:AdjustSpeed(track.Length / Config.ROLL_TIME)
	end
end

return AnimationController
