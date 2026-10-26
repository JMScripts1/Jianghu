--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Anims = require(ReplicatedStorage.Shared.Movement.Anims)
local AttackDefs = require(ReplicatedStorage.Shared.Combat.AttackDefs)
local CombatDefs = require(ReplicatedStorage.Shared.Combat.CombatDefs)
local Config = require(ReplicatedStorage.Shared.Config)
local MoveDefs = require(ReplicatedStorage.Shared.Movement.MoveDefs)
local Types = require(ReplicatedStorage.Shared.Types)
local WeaponDefs = require(ReplicatedStorage.Shared.Combat.WeaponDefs)
local StateService = require(script.Parent.Parent.Services.StateService)

-- the server owns NPCs, so it plays their movement, swings and reactions the way a player's client plays its own
type Npc = {
	animator: Animator,
	root: BasePart,
	-- by animation id, loaded the first time each one plays
	tracks: { [string]: AnimationTrack },
	swinging: AnimationTrack?,
	-- the rate the swing plays at, its weapon's speed
	swingSpeed: number,
	looping: AnimationTrack?,
	-- the loop is a pin's pose, held on its last frame, see step
	isPosing: boolean,
	oneShot: AnimationTrack?,
	-- which of a reaction's animations played last
	turns: { [Types.Reaction]: number },
	-- the movement track under everything else, and the id it plays, so a weapon's own one swaps in on a swap
	moving: AnimationTrack?,
	movingId: string,
	-- the back dash's burst, where its animation speeds up past the Boost marker the way the client's does
	boostAt: number?,
	conns: { RBXScriptConnection },
}

-- being hit cuts the swing short, the same states CombatController cancels its own on
local CUTS_SWING: { [Types.CombatState]: true } =
	{ Stunned = true, PostureBroken = true, WallStunned = true, FloorStunned = true, Downed = true }

-- a pin holds its own pose, so it cuts a one shot still playing, like the knockback's, and none plays over it. the
-- pose stops on its last frame, so an animation shorter than the pin still covers all of it
local HOLDS_POSE: { [Types.CombatState]: true } = { WallStunned = true, FloorStunned = true }
-- two frames at 60, a step never jumps past it
local LAST_FRAME = 2 / 60

-- slower than this flat it's standing, Walk and CrouchWalk cover standing still too
local MIN_MOVING = 1
-- these play once and the fall loop takes over, see AnimationController
local THEN_FALL: { [Types.MoveState]: true } = { Jump = true, DoubleJump = true }

-- turns the attribute back into a state, anything else is ignored
local BY_NAME: { [string]: Types.MoveState } = {}
for state: Types.MoveState in MoveDefs do
	BY_NAME[state] = state
end

local NpcAnimator = {}

local npcs: { [Model]: Npc } = {}
local animations: { [string]: Animation } = {}

local function animation(id: string): Animation
	local made = animations[id]
	if made then
		return made
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	animations[id] = anim
	return anim
end

local function track(npc: Npc, id: string): AnimationTrack?
	if id == "" then
		return nil
	end
	local loaded = npc.tracks[id] or npc.animator:LoadAnimation(animation(id))
	npc.tracks[id] = loaded
	return loaded
end

local function reactions(char: Model): { [Types.Reaction]: { string } }
	local st = StateService.get(char)
	return WeaponDefs[if st then st.combat.weapon else CombatDefs.defaultWeapon].reactions
end

local function stop(t: AnimationTrack?)
	if t then
		t:Stop(Config.COMBAT_FADE)
	end
end

-- the movement animation the state plays, nil for the parkour states an NPC never uses
local function moveName(npc: Npc, char: Model): Types.AnimName?
	local value = char:GetAttribute("MoveState")
	local state: Types.MoveState? = if typeof(value) == "string" then BY_NAME[value] else nil
	if not state then
		return nil
	end
	local v = npc.root.AssemblyLinearVelocity
	local isMoving = Vector3.new(v.X, 0, v.Z).Magnitude > MIN_MOVING
	if state == "Walk" then
		return if isMoving then "Walk" else "Idle"
	elseif state == "CrouchWalk" then
		return if isMoving then "CrouchWalk" else "CrouchIdle"
	elseif THEN_FALL[state] and npc.moving and not npc.moving.IsPlaying then
		return "Fall"
	elseif state == "Run" or state == "Fall" or THEN_FALL[state] or MoveDefs[state].isDash then
		return state
	end
	return nil
end

-- picked again every step, standing and walking share a state and a jump hands over to the fall without one
local function move(npc: Npc, char: Model)
	local name: Types.AnimName? = moveName(npc, char)
	local st = StateService.get(char)
	local own = if name and st then WeaponDefs[st.combat.weapon].movement[name] else nil
	local id = own or (if name then Anims[name] else nil) or ""
	if id == npc.movingId then
		return
	end
	npc.movingId = id
	if npc.moving then
		npc.moving:Stop(Config.ANIM_FADE)
	end
	local t = track(npc, id)
	npc.moving = t
	npc.boostAt = nil
	if not t then
		return
	end
	t:Play(Config.ANIM_FADE)
	if name == "DashB" then
		t:AdjustSpeed(Config.BACK_DASH_MARKER / Config.BACK_DASH_WINDUP)
		npc.boostAt = os.clock() + Config.BACK_DASH_WINDUP
	end
end

local function onState(char: Model)
	local npc = npcs[char]
	if not npc or not StateService.get(char) then
		return
	end
	local state: Types.CombatState = StateService.combatState(char)
	if CUTS_SWING[state] then
		stop(npc.swinging)
		npc.swinging = nil
	end
	npc.isPosing = HOLDS_POSE[state] == true
	if npc.isPosing then
		stop(npc.oneShot)
		npc.oneShot = nil
	end

	-- Idle and Attacking have no slot at all
	local ids = reactions(char)[state]
	local loop = if ids then track(npc, ids[1] or "") else nil
	if loop == npc.looping then
		return
	end
	stop(npc.looping)
	npc.looping = loop
	if loop then
		loop:Play(Config.COMBAT_FADE)
	end
end

-- after CharacterService.add. a rig made in Studio may have no Animator, a player's gets one from the engine
function NpcAnimator.add(char: Model, hum: Humanoid, root: BasePart)
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = hum
	local npc: Npc = {
		animator = animator,
		root = root,
		tracks = {},
		swingSpeed = 1,
		isPosing = false,
		turns = {},
		movingId = "",
		conns = {},
	}
	npcs[char] = npc
	table.insert(
		npc.conns,
		char:GetAttributeChangedSignal("CombatState"):Connect(function()
			onState(char)
		end)
	)
	-- a dash or a jump starts its animation the moment it's recorded, not on the next step
	table.insert(
		npc.conns,
		char:GetAttributeChangedSignal("MoveState"):Connect(function()
			move(npc, char)
		end)
	)
	onState(char)
	move(npc, char)
end

function NpcAnimator.remove(char: Model)
	local npc = npcs[char]
	if npc then
		for _, conn in npc.conns do
			conn:Disconnect()
		end
		npcs[char] = nil
	end
end

-- a player's own client plays its swings and reactions, so anything not added here is skipped
function NpcAnimator.swing(char: Model, id: Types.AttackId)
	local npc = npcs[char]
	if not npc then
		return
	end
	local def = AttackDefs[id]
	stop(npc.oneShot)
	npc.oneShot = nil
	local t = track(npc, def.anim)
	npc.swinging = t
	npc.swingSpeed = def.speed
	if t then
		t:Play(Config.COMBAT_FADE, 1, def.speed)
	end
end

-- a delayed windup runs at DELAY_SPEED, and the animation with it
function NpcAnimator.slow(char: Model, isSlowed: boolean)
	local npc = npcs[char]
	local t = if npc then npc.swinging else nil
	if npc and t then
		t:AdjustSpeed(npc.swingSpeed * (if isSlowed then Config.DELAY_SPEED else 1))
	end
end

-- a one shot over the loop, from the NPC's own weapon. a reaction with several animations takes turns
function NpcAnimator.react(char: Model, name: Types.Reaction)
	local npc = npcs[char]
	local ids = reactions(char)[name]
	if not npc or not ids or #ids == 0 or HOLDS_POSE[StateService.combatState(char)] then
		return
	end
	local turn = (npc.turns[name] or 0) % #ids + 1
	npc.turns[name] = turn
	local t = track(npc, ids[turn])
	if t then
		stop(npc.oneShot)
		npc.oneShot = t
		t:Play(Config.COMBAT_FADE)
	end
end

function NpcAnimator.step()
	local now = os.clock()
	for char, npc in npcs do
		local t = npc.looping
		if npc.isPosing and t and t.Length > 0 and t.TimePosition >= t.Length - LAST_FRAME then
			t:AdjustSpeed(0)
		end
		move(npc, char)
		local moving = npc.moving
		local boostAt = npc.boostAt
		if moving and boostAt and now >= boostAt and moving.Length > 0 then
			npc.boostAt = nil
			moving:AdjustSpeed(moving.Length / Config.BACK_DASH_ANIM_TIME)
		end
	end
end

function NpcAnimator.result(attacker: Model, target: Model, result: Types.HitResult)
	for _, char in { attacker, target } do
		local name: Types.Reaction? = CombatDefs.reaction(result, char == attacker)
		if name then
			NpcAnimator.react(char, name)
		end
	end
end

return NpcAnimator
