--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Anims = require(ReplicatedStorage.Shared.Movement.Anims)
local Config = require(ReplicatedStorage.Shared.Config)
local MoveDefs = require(ReplicatedStorage.Shared.Movement.MoveDefs)
local Types = require(ReplicatedStorage.Shared.Types)
local WeaponDefs = require(ReplicatedStorage.Shared.Combat.WeaponDefs)
local Context = require(script.Parent.Movement.Context)
local Dash = require(script.Parent.Movement.Dash)

type Ctx = Context.Ctx

local BOOST_MARKER = "Boost"
local BACK_DASH: Types.AnimName = "DashB"
local RUN: Types.AnimName = "Run"
local SPRINT: Types.AnimName = "Sprint"
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

-- turns the attribute back into a weapon, anything else is ignored
local BY_WEAPON: { [string]: Types.WeaponId } = {}
for weapon: Types.WeaponId in WeaponDefs do
	BY_WEAPON[weapon] = weapon
end

local AnimationController = {}

local animations: { [Types.AnimName]: Animation } = {}
local tracks: { [Types.AnimName]: AnimationTrack } = {}
-- each weapon's own movement animations, and the held weapon's, which play over the shared ones of the same name
local weaponAnimations: { [Types.WeaponId]: { [Types.AnimName]: Animation } } = {}
local weaponTracks: { [Types.WeaponId]: { [Types.AnimName]: AnimationTrack } } = {}
local overrides: { [Types.AnimName]: AnimationTrack } = {}
local current: AnimationTrack? = nil
-- what current was started for, so a weapon swap can start it again from the new weapon's own
local currentName: Types.AnimName? = nil
local dashing: AnimationTrack? = nil
-- plays over the state track instead of taking over from it, the walk states keep going underneath
local rolling: AnimationTrack? = nil
local leaps = 0
local isSprinting = false

for name: Types.AnimName, id in Anims do
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	animations[name] = anim
end
for weapon: Types.WeaponId, def in WeaponDefs do
	local own: { [Types.AnimName]: Animation } = {}
	for name: Types.AnimName, id in def.movement do
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		own[name] = anim
	end
	weaponAnimations[weapon] = own
end

local function trackOf(name: Types.AnimName): AnimationTrack
	return overrides[name] or tracks[name]
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
		if trackOf(name) == track then
			return true
		end
	end
	return false
end

-- while a dash plays the state track is only remembered, it starts when the dash ends
local function start(name: Types.AnimName, fade: number?)
	local track = trackOf(name)
	local time = fade or Config.ANIM_FADE
	local playing = current
	-- the leap and boost can outlast their state, and they hand over to the fall loop themselves when they end
	if name == "Fall" and playing and playing.IsPlaying and isThenFall(playing) then
		return
	end
	-- a running jump keeps the run or sprint going slowed down instead of cutting to the jump, landing back in the
	-- same one speeds it back up
	local isRunning = playing == trackOf(RUN) or playing == trackOf(SPRINT)
	if playing and isRunning and (name == "Jump" or track == playing) then
		playing:AdjustSpeed(if name == "Jump" then Config.RUN_JUMP_ANIM_SPEED else 1)
		return
	end
	if track == playing then
		return
	end
	if playing then
		playing:Stop(time)
	end
	current = track
	currentName = name
	if track and not dashing then
		track:Play(time)
	end
end

-- two lines, so momentum falling slowly through one doesn't flick between the two
local function runName(c: Ctx): Types.AnimName
	isSprinting = c.momentum >= if isSprinting then Config.SPRINT_ANIM_EXIT else Config.SPRINT_ANIM_ENTER
	return if isSprinting then SPRINT else RUN
end

local function stopRoll()
	if rolling then
		rolling:Stop(Config.ANIM_FADE)
		rolling = nil
	end
end

function AnimationController.load(c: Ctx)
	local animator = c.hum:WaitForChild("Animator") :: Animator
	local function loadTrack(name: Types.AnimName, anim: Animation): AnimationTrack
		local track = animator:LoadAnimation(anim)
		if THEN_FALL[name] then
			c.trove:Connect(track.Stopped, function()
				if current == track then
					start("Fall")
				end
			end)
		end
		return track
	end
	for name: Types.AnimName, anim in animations do
		tracks[name] = loadTrack(name, anim)
	end
	for weapon: Types.WeaponId, own in weaponAnimations do
		local loaded: { [Types.AnimName]: AnimationTrack } = {}
		for name: Types.AnimName, anim in own do
			loaded[name] = loadTrack(name, anim)
		end
		weaponTracks[weapon] = loaded
	end

	-- a swap starts the state's animation again from the new weapon's own, or the shared one
	local function onWeapon()
		local value = c.char:GetAttribute("Weapon")
		local weapon: Types.WeaponId? = if typeof(value) == "string" then BY_WEAPON[value] else nil
		overrides = if weapon then weaponTracks[weapon] else {}
		if currentName then
			start(currentName)
		end
	end
	c.trove:Connect(c.char:GetAttributeChangedSignal("Weapon"), onWeapon)
	onWeapon()

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
		table.clear(weaponTracks)
		overrides = {}
		current = nil
		currentName = nil
		dashing = nil
		rolling = nil
		isSprinting = false
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
	elseif c.state == "Run" then
		start(runName(c))
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

-- momentum moves all through a run without the state changing, so the run or sprint is picked again every step
function AnimationController.step(c: Ctx)
	if c.state ~= "Run" then
		return
	end
	local name: Types.AnimName = runName(c)
	if name ~= currentName then
		start(name, Config.SPRINT_ANIM_FADE)
	end
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
