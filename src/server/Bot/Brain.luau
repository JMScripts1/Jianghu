--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AttackDefs = require(ReplicatedStorage.Shared.Combat.AttackDefs)
local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local WeaponDefs = require(ReplicatedStorage.Shared.Combat.WeaponDefs)
local Hitbox = require(script.Parent.Parent.Combat.Hitbox)
local CombatService = require(script.Parent.Parent.Services.CombatService)
local StateService = require(script.Parent.Parent.Services.StateService)
local Motor = require(script.Parent.Motor)
local Sight = require(script.Parent.Sight)

type Swing = StateService.Swing

export type Level = Types.BotLevel

-- the chances are rolled once per swing or opening. air is how often it opens with the uppercut, pace the wait
-- between its own strings
export type Skill = {
	reaction: number,
	parry: number,
	block: number,
	dash: number,
	mixup: number,
	punish: number,
	escape: number,
	air: number,
	pace: NumberRange,
}

type Answer = "Parry" | "Block" | "Dash" | "Take"
-- where it wants to be: in to hit, just out of reach, or backing away
type Goal = "In" | "Hover" | "Out"

export type Mind = {
	body: Motor.Body,
	sight: Sight.Sight,
	-- the swing coming at it and the answer rolled for it
	threat: Swing?,
	answer: Answer,
	isAnswered: boolean,
	-- the block is held until this swing has landed or gone
	blockFor: Swing?,
	-- then it lingers until this, so a string's next swing finds it still up. pressing it again from Idle would open a
	-- parry window on every hit
	dropBlockAt: number?,
	-- its own swing held through the delay point lets go at this
	releaseAt: number?,
	-- lights still to come in the string it's throwing
	stringLeft: number,
	nextAttackAt: number,
	-- the opening it last rolled a punish for, each one is rolled once
	punishFor: number,
	isPunishing: boolean,
	-- its own uppercut started this juggle, so it strings in the air and slams. a juggle it's the target of is only
	-- escaped, see choose
	isAirAttacker: boolean,
	-- air hits still to come before the slam
	airLeft: number,
	strafe: number,
	nextStrafeAt: number,
	nextDashAt: number,
}

-- the starting table from the bot outline, tuned by playing
local LEVELS: { [Level]: Skill } = {
	Easy = {
		reaction = 0.45,
		parry = 0.1,
		block = 0.4,
		dash = 0.05,
		mixup = 0.1,
		punish = 0.3,
		escape = 0.1,
		air = 0.1,
		pace = NumberRange.new(1, 2),
	},
	Normal = {
		reaction = 0.3,
		parry = 0.35,
		block = 0.35,
		dash = 0.15,
		mixup = 0.3,
		punish = 0.6,
		escape = 0.35,
		air = 0.25,
		pace = NumberRange.new(0.5, 1.2),
	},
	Hard = {
		reaction = 0.2,
		parry = 0.65,
		block = 0.2,
		dash = 0.3,
		mixup = 0.5,
		punish = 0.9,
		escape = 0.65,
		air = 0.4,
		pace = NumberRange.new(0.2, 0.7),
	},
}
local DEFAULT_LEVEL: Level = "Normal"

-- typed so the old solver takes it as a key of cooldownUntil
local LAUNCH: Types.CombatCooldown = "Launch"

-- pressed so the hit lands in the middle of the parry window, and dashed so the dodge frames cover it
local PARRY_LEAD = Config.PARRY_WINDOW / 2
local DODGE_LEAD = Config.DODGE_TIME * 0.6
-- the block stays up this long past the hit, then lingers past the gap to a string's next swing being seen
local BLOCK_AFTER = 0.15
local BLOCK_LINGER = 0.6
-- its own swing lets go this early before the delay point, a tick late would delay it by accident
local RELEASE_EARLY = Config.BOT_TICK * 1.5
-- a feint holds the delay this long
local FEINT_HOLD = NumberRange.new(0.1, Config.DELAY_MAX)
-- the next light goes in this close to the end of the last, inside CombatService's queue
local QUEUE = Config.COMBAT_TOLERANCE * 0.6
-- air hits before the slam. the juggle's stun shrinks with every hit, so past a few the target can parry out
local AIR_HITS_MIN = 2
local AIR_HITS_MAX = 4
-- low on posture it backs off and stops blocking as much
local LOW_POSTURE = 30
local LOW_POSTURE_BLOCK = 0.3
-- just out of its own reach, where it waits between strings
local HOVER_SLACK = 2.5
local RUN_GAP = 20
local DASH_IN_EVERY = NumberRange.new(2, 4)
local STRAFE_EVERY = NumberRange.new(1.5, 3.5)

local Brain = {}

local function roll(range: NumberRange): number
	return range.Min + math.random() * (range.Max - range.Min)
end

-- the box's far edge, the same box the server checks a swing with
local function reach(box: Vector3): number
	return box.Z + Config.HIT_SLACK * 2 - Config.BOX_BACK
end

function Brain.skill(model: Model): Skill
	local value = model:GetAttribute("Difficulty")
	return LEVELS[if typeof(value) == "string" and LEVELS[value :: Level] then value :: Level else DEFAULT_LEVEL]
end

function Brain.isLevel(value: unknown): boolean
	return typeof(value) == "string" and LEVELS[value :: Level] ~= nil
end

function Brain.new(body: Motor.Body, now: number): Mind
	return {
		body = body,
		sight = Sight.new(),
		answer = "Take",
		isAnswered = true,
		stringLeft = 0,
		nextAttackAt = now,
		punishFor = 0,
		isPunishing = false,
		isAirAttacker = false,
		airLeft = 0,
		strafe = if math.random() < 0.5 then 1 else -1,
		nextStrafeAt = now + roll(STRAFE_EVERY),
		nextDashAt = now + roll(DASH_IN_EVERY),
	}
end

-- a parry is a tap. from a held block it has to let go first, then it keeps holding
local function parry(model: Model, st: StateService.CharState)
	local wasHeld = st.combat.isBlockHeld
	if wasHeld then
		CombatService.act(model, "Unblock")
	end
	CombatService.act(model, "Block")
	if not wasHeld then
		CombatService.act(model, "Unblock")
	end
end

local function choose(
	state: Types.CombatState,
	def: Types.AttackDef,
	skill: Skill,
	posture: number,
	isLocked: boolean
): Answer
	-- only a parry gets out of a stun, and not a heavy one. mid swing there's nothing to answer with
	if state == "Stunned" then
		return if def.canParry and not isLocked and math.random() < skill.escape then "Parry" else "Take"
	elseif state ~= "Idle" and state ~= "Blocking" then
		return "Take"
	end
	local block = if def.isGuardBreak or not def.canBlock then 0 else skill.block
	if posture < LOW_POSTURE then
		block *= LOW_POSTURE_BLOCK
	end
	local chances: { { answer: Answer, chance: number } } = {
		{ answer = "Parry", chance = if def.canParry then skill.parry else 0 },
		{ answer = "Block", chance = block },
		{ answer = "Dash", chance = if def.canDodge then skill.dash else 0 },
	}
	local r = math.random()
	for _, option in chances do
		if r < option.chance then
			return option.answer
		end
		r -= option.chance
	end
	return "Take"
end

-- its own swing is held from the press, so it decides at the delay point: let go, or hold it as a feint. a parry it
-- can see coming gets baited more often
local function release(
	model: Model,
	mind: Mind,
	st: StateService.CharState,
	seen: Types.CombatState,
	skill: Skill,
	now: number
)
	local swing = st.combat.swing
	if not swing or not swing.isHeld then
		mind.releaseAt = nil
		return
	end
	local releaseAt = mind.releaseAt
	if releaseAt then
		if now >= releaseAt then
			mind.releaseAt = nil
			CombatService.act(model, "Release")
		end
		return
	end
	local delayAt = AttackDefs[swing.id].delayAt
	if delayAt and now < swing.startedAt + delayAt - RELEASE_EARLY then
		return
	end
	-- a held slam only gains, it hits harder for up to DELAY_FULL of hold
	if delayAt and swing.kind == "Slam" then
		if math.random() < skill.mixup then
			mind.releaseAt = now + Config.DELAY_FULL
		else
			CombatService.act(model, "Release")
		end
		return
	end
	local chance = if seen == "Parrying" then skill.mixup else skill.mixup / 3
	if delayAt and math.random() < chance then
		mind.releaseAt = now + roll(FEINT_HOLD)
	else
		CombatService.act(model, "Release")
	end
end

-- the target's swing it has seen coming at it, answered once. returns what it's doing, nil when nothing is coming
local function defend(
	model: Model,
	mind: Mind,
	st: StateService.CharState,
	state: Types.CombatState,
	from: BasePart,
	skill: Skill,
	now: number
): string?
	local sight = mind.sight
	local swing = Sight.swing(sight, now)
	if swing and swing ~= mind.threat and Hitbox.reaches(from, AttackDefs[swing.id].box, model) then
		local isLocked = now < st.combat.lockedUntil
		mind.threat = swing
		mind.answer = choose(state, AttackDefs[swing.id], skill, StateService.posture(model), isLocked)
		mind.isAnswered = mind.answer == "Take"
		if Config.DEBUG then
			print("bot", model.Name, mind.answer, swing.id)
		end
	end

	-- the block comes down once the hit it was held for has landed, or the swing is gone
	local blockFor = mind.blockFor
	if blockFor then
		local activeUntil = blockFor.activeUntil
		if sight.swing ~= blockFor or (activeUntil and now > activeUntil + BLOCK_AFTER) then
			mind.blockFor = nil
			mind.dropBlockAt = now + BLOCK_LINGER
		end
	end
	local dropBlockAt = mind.dropBlockAt
	if dropBlockAt and now >= dropBlockAt then
		mind.dropBlockAt = nil
		CombatService.act(model, "Unblock")
	end

	local threat = mind.threat
	if threat and sight.swing ~= threat then
		mind.threat = nil
		threat = nil
	end
	if not threat or mind.answer == "Take" then
		return if mind.blockFor then "Block" else nil
	end

	-- on rhythm, the way a player reads a windup, so a delay beats it unless it sees the slowdown and holds a block
	-- through it instead
	local def = AttackDefs[threat.id]
	local hitAt = threat.startedAt + def.windup
	if
		not mind.isAnswered
		and mind.answer == "Parry"
		and Sight.isDelaySeen(sight, now)
		and math.random() < skill.parry
	then
		mind.answer = if def.canBlock and not def.isGuardBreak then "Block" else "Dash"
	end
	if mind.isAnswered then
		return mind.answer
	end

	if mind.answer == "Parry" and hitAt - now <= PARRY_LEAD then
		parry(model, st)
		mind.isAnswered = true
	elseif mind.answer == "Block" then
		if not st.combat.isBlockHeld then
			CombatService.act(model, "Block")
		end
		mind.blockFor = threat
		mind.dropBlockAt = nil
		mind.isAnswered = true
	elseif mind.answer == "Dash" and hitAt - now <= DODGE_LEAD then
		local dash: Types.MoveState = if math.random() < 0.5 then "DashL" else "DashR"
		if not Motor.dash(mind.body, if math.random() < 0.3 then "DashB" else dash, now) and def.canBlock then
			CombatService.act(model, "Block")
			mind.blockFor = threat
			mind.dropBlockAt = nil
		end
		mind.isAnswered = true
	end
	return mind.answer
end

-- an opening it can punish, as a key so each is rolled once: a parried, broken or pinned target, or a swing that
-- missed it and is still recovering
local function opening(model: Model, mind: Mind, now: number): number?
	local sight = mind.sight
	local seen: Types.CombatState = Sight.state(sight, now)
	if seen == "Stunned" or seen == "PostureBroken" or seen == "WallStunned" or seen == "FloorStunned" then
		return sight.seenAt
	end
	local swing = Sight.swing(sight, now)
	local activeUntil = if swing then swing.activeUntil else nil
	local endsAt = if swing then swing.endsAt else nil
	if swing and activeUntil and endsAt and now > activeUntil and now < endsAt and not swing.hit[model] then
		return swing.startedAt
	end
	return nil
end

-- the crouched light, the one way into air combat. a block would just take it, and it stands back up if the press
-- doesn't go through
local function launch(model: Model, mind: Mind, st: StateService.CharState, skill: Skill, now: number): boolean
	if now < (st.combat.cooldownUntil[LAUNCH] or 0) or math.random() >= skill.air then
		return false
	end
	if not Motor.crouch(mind.body, true) then
		return false
	end
	if not CombatService.act(model, "Light") then
		Motor.crouch(mind.body, false)
		return false
	end
	mind.isAirAttacker = true
	mind.airLeft = math.random(AIR_HITS_MIN, AIR_HITS_MAX)
	mind.stringLeft = 0
	return true
end

-- strings, heavies and punishes, then where it wants to stand
local function offend(
	model: Model,
	mind: Mind,
	st: StateService.CharState,
	state: Types.CombatState,
	root: BasePart,
	target: Model,
	skill: Skill,
	now: number
): (string, Goal)
	local seen: Types.CombatState = Sight.state(mind.sight, now)
	local swing = st.combat.swing
	if not swing then
		mind.stringLeft = 0
		if mind.nextAttackAt == math.huge then
			mind.nextAttackAt = now + roll(skill.pace)
		end
	end
	-- a body that's down is left alone until the grip comes in
	if seen == "Downed" or seen == "Gripped" or seen == "Gripping" then
		return "Wait", "Hover"
	elseif state ~= "Idle" and state ~= "Attacking" then
		return state, "Hover"
	end

	-- its own juggle: the air string, then the slam. both swing as the last one ends, like a string on the ground
	local isJuggling = now < st.combat.juggleUntil
	if mind.isAirAttacker and not isJuggling and not swing then
		mind.isAirAttacker = false
	end
	if mind.isAirAttacker and isJuggling then
		local endsAt = if swing then swing.endsAt else nil
		local activeUntil = if swing then swing.activeUntil else nil
		local isReady = not swing or (endsAt and activeUntil and now >= activeUntil and endsAt - now <= QUEUE)
		local action: Types.CombatAction = if mind.airLeft <= 0 then "Slam" else "Light"
		if isReady and CombatService.act(model, action) then
			mind.airLeft -= 1
		end
		return if action == "Slam" then "Slam" else "Air", "In"
	end

	local key = opening(model, mind, now)
	if key and key ~= mind.punishFor then
		mind.punishFor = key
		mind.isPunishing = math.random() < skill.punish
	elseif not key then
		mind.isPunishing = false
	end

	local light = WeaponDefs[st.combat.weapon].light
	if swing then
		local endsAt = swing.endsAt
		local activeUntil = swing.activeUntil
		local isEnding = endsAt and activeUntil and now >= activeUntil and endsAt - now <= QUEUE
		if mind.stringLeft > 0 and isEnding and CombatService.act(model, "Light") then
			mind.stringLeft -= 1
		end
		return if mind.isPunishing then "Punish" else "Pressure", "In"
	end

	if StateService.posture(model) < LOW_POSTURE and not mind.isPunishing then
		return "Back off", "Out"
	elseif now < mind.nextAttackAt and not mind.isPunishing then
		return "Footsies", "Hover"
	end
	local targetRoot = StateService.liveRoot(target)
	local box = AttackDefs[light[1]].box
	if not targetRoot or not Hitbox.reaches(root, box, target) then
		return if mind.isPunishing then "Punish" else "Close", "In"
	end

	-- a broken guard takes the heavy, and a block sometimes gets one to break it. otherwise a string, cut short now and
	-- then to bait a counter, or the whole thing on a punish
	if seen ~= "Blocking" and seen ~= "PostureBroken" and launch(model, mind, st, skill, now) then
		mind.nextAttackAt = math.huge
		return "Uppercut", "In"
	end
	local wantsHeavy = seen == "PostureBroken" or (seen == "Blocking" and math.random() < skill.mixup)
	if wantsHeavy and CombatService.act(model, "Heavy") then
		mind.stringLeft = 0
	elseif CombatService.act(model, "Light") then
		mind.stringLeft = if mind.isPunishing then #light - 1 else math.random(1, #light - 1)
	else
		return "Footsies", "Hover"
	end
	mind.nextAttackAt = math.huge
	return if mind.isPunishing then "Punish" else "Pressure", "In"
end

-- in to hit, just out of its reach between strings, circling, or backing off, and a dash in now and then from far out
local function space(mind: Mind, st: StateService.CharState, root: BasePart, to: BasePart, goal: Goal, now: number)
	local body = mind.body
	local gap = to.Position - root.Position
	local dist = Vector3.new(gap.X, 0, gap.Z).Magnitude
	local toward = Vector3.new(gap.X, 0, gap.Z).Unit
	local hover = reach(AttackDefs[WeaponDefs[st.combat.weapon].light[1]].box) + HOVER_SLACK

	if now >= mind.nextStrafeAt then
		mind.strafe = -mind.strafe
		mind.nextStrafeAt = now + roll(STRAFE_EVERY)
	end
	if goal == "Out" then
		Motor.walk(body, -toward + toward:Cross(Vector3.yAxis) * mind.strafe, false)
	elseif goal == "In" or dist > hover + 1 then
		Motor.walk(body, toward, dist > RUN_GAP)
	elseif dist < hover - 1.5 then
		Motor.walk(body, -toward, false)
	else
		Motor.walk(body, toward:Cross(Vector3.yAxis) * mind.strafe, false)
	end

	if dist > RUN_GAP and now >= mind.nextDashAt and Motor.dash(body, "DashF", now) then
		mind.nextDashAt = now + roll(DASH_IN_EVERY)
	end
end

local function intent(model: Model, name: string)
	if model:GetAttribute("Intent") ~= name then
		model:SetAttribute("Intent", name)
	end
end

function Brain.step(model: Model, mind: Mind, target: Model?, skill: Skill, now: number)
	local body = mind.body
	local st = StateService.get(model)
	local root = StateService.liveRoot(model)
	Sight.update(mind.sight, target, skill.reaction, now)
	local to = if target then StateService.liveRoot(target) else nil
	if not st or not root or not target or not to then
		if st and st.combat.isBlockHeld then
			CombatService.act(model, "Unblock")
		end
		mind.blockFor = nil
		mind.dropBlockAt = nil
		Motor.walk(body, Vector3.zero, false)
		Motor.face(body, nil)
		intent(model, "Idle")
		return
	end
	Motor.face(body, to.Position)

	local state: Types.CombatState = StateService.combatState(model)
	release(model, mind, st, Sight.state(mind.sight, now), skill, now)
	local guard = defend(model, mind, st, state, to, skill, now)
	-- a parry or a dash still waiting for its moment, or a held block, comes before swinging
	local isGuarding = mind.blockFor ~= nil or (mind.threat ~= nil and not mind.isAnswered)
	local name: string, goal: Goal = guard or "Guard", "Hover"
	if not isGuarding then
		name, goal = offend(model, mind, st, state, root, target, skill, now)
		if guard and guard ~= "Take" then
			name = guard
		end
	end
	space(mind, st, root, to, goal, now)
	intent(model, name)
end

return Brain
