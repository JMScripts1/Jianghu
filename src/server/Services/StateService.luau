--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatDefs = require(ReplicatedStorage.Shared.CombatDefs)
local Config = require(ReplicatedStorage.Shared.Config)
local MoveDefs = require(ReplicatedStorage.Shared.MoveDefs)
local Types = require(ReplicatedStorage.Shared.Types)

-- hitAt is nil while a delay is being held, and the times after it wait on it
export type Swing = {
	id: Types.AttackId,
	startedAt: number,
	isHeld: boolean,
	isDelayed: boolean,
	delayedAt: number?,
	hitAt: number?,
	activeUntil: number?,
	nextQueryAt: number?,
	endsAt: number?,
	-- damage multiplier, above 1 for a running attack
	power: number,
	hit: { [Model]: true },
}

export type CharState = {
	move: {
		state: Types.MoveState,
		since: number,
		endsAt: number?,
		airJumps: number,
		hasAirDashed: boolean,
		lastWallPart: BasePart?,
		wallGrabs: { [Types.MoveState]: true },
		groundedAt: number,
		cooldownUntil: { [Types.MoveState]: number },
	},
	dash: {
		dodgeUntil: number,
	},
	speed: {
		windowCap: number,
		lastGoodCFrame: CFrame,
		bucket: number,
		exemptUntil: number,
		lastPos: Vector3,
		sampledAt: number,
		measured: number,
	},
	combat: {
		weapon: Types.WeaponId,
		swing: Swing?,
		combo: number,
		comboAt: number,
		stunnedUntil: number,
		-- no parry out of stun until this, set by heavy stuns
		lockedUntil: number,
		brokenUntil: number,
		parryUntil: number,
		cooldownUntil: { [Types.CombatCooldown]: number },
		isBlockHeld: boolean,
		hasAirAttacked: boolean,
		downed: boolean,
		downedAt: number,
		taggedUntil: number,
	},
	posture: {
		value: number,
		stamp: number,
		regenAt: number,
	},
	stamina: {
		value: number,
		stamp: number,
	},
}

local SPAWN_STATE: Types.MoveState = "Walk"

local StateService = {}

local states: { [Model]: CharState } = {}

-- a swing past its end is over even before CombatService clears it
local function isSwinging(swing: Swing?, now: number): boolean
	return swing ~= nil and not (swing.endsAt and now >= swing.endsAt)
end

function StateService.add(char: Model)
	local now = workspace:GetServerTimeNow()
	local pivot = char:GetPivot()
	states[char] = {
		move = {
			state = SPAWN_STATE,
			since = now,
			airJumps = 0,
			hasAirDashed = false,
			wallGrabs = {},
			groundedAt = 0,
			cooldownUntil = {},
		},
		dash = { dodgeUntil = 0 },
		speed = {
			windowCap = MoveDefs[SPAWN_STATE].cap,
			lastGoodCFrame = pivot,
			bucket = 0,
			exemptUntil = 0,
			lastPos = pivot.Position,
			sampledAt = now,
			measured = 0,
		},
		combat = {
			weapon = CombatDefs.defaultWeapon,
			combo = 0,
			comboAt = 0,
			stunnedUntil = 0,
			lockedUntil = 0,
			brokenUntil = 0,
			parryUntil = 0,
			cooldownUntil = {},
			isBlockHeld = false,
			hasAirAttacked = false,
			downed = false,
			downedAt = 0,
			taggedUntil = 0,
		},
		posture = { value = Config.POSTURE_MAX, stamp = now, regenAt = 0 },
		stamina = { value = Config.STAMINA_MAX, stamp = now },
	}
end

function StateService.remove(char: Model)
	states[char] = nil

	if Config.DEBUG then
		local count = 0
		for _ in states do
			count += 1
		end
		print("state tables", count)
	end
end

function StateService.get(char: Model): CharState?
	return states[char]
end

-- the owner can delete parts of its own character, so nothing in it is assumed
function StateService.liveRoot(char: Model): BasePart?
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	if hum and hum.Health > 0 and root and root:IsA("BasePart") then
		return root
	end
	return nil
end

function StateService.land(char: Model, at: number)
	local move = states[char].move
	move.airJumps = 0
	move.hasAirDashed = false
	move.lastWallPart = nil
	move.groundedAt = at
	states[char].combat.hasAirAttacked = false
end

function StateService.current(char: Model): Types.MoveState
	local move = states[char].move
	local endsAt = move.endsAt
	local after: Types.MoveState? = MoveDefs[move.state].after

	-- every timed state ends in an untimed one, so one step is enough
	if endsAt and after and workspace:GetServerTimeNow() >= endsAt then
		-- Mantle runs out standing on the ledge, which is a landing nobody sends
		if MoveDefs[after].group == "Grounded" and MoveDefs[move.state].group ~= "Grounded" then
			StateService.land(char, endsAt)
		end
		move.state = after
		move.since = endsAt
		move.endsAt = nil
	end
	return move.state
end

-- worked out from the end times every time, so nothing can be left stuck in a state
function StateService.combatState(char: Model): Types.CombatState
	local combat = states[char].combat
	local now = workspace:GetServerTimeNow()

	if combat.downed then
		return "Downed"
	elseif now < combat.brokenUntil then
		return "PostureBroken"
	elseif now < combat.parryUntil then
		return "Parrying"
	elseif now < combat.stunnedUntil then
		return "Stunned"
	elseif isSwinging(combat.swing, now) then
		return "Attacking"
	elseif combat.isBlockHeld and CombatDefs.guard[StateService.current(char)] then
		return "Blocking"
	end
	return "Idle"
end

-- a landing is never refused, a character stunned in the air still has to come down and get its jumps back
function StateService.canMove(char: Model, to: Types.MoveState): boolean
	if MoveDefs[to].group == "Grounded" and MoveDefs[StateService.current(char)].group ~= "Grounded" then
		return true
	end
	-- a parry out of stun shows as Parrying, but it's still a stun to movement, so it can't dash out
	local state: Types.CombatState = StateService.combatState(char)
	if state == "Parrying" and workspace:GetServerTimeNow() < states[char].combat.stunnedUntil then
		state = "Stunned"
	end
	return CombatDefs.states[state].moves[to] == true
end

-- held only counts where a block works, and never through a stun or a swing
function StateService.isBlocking(char: Model): boolean
	local combat = states[char].combat
	local now = workspace:GetServerTimeNow()
	return combat.isBlockHeld
		and not combat.downed
		and now >= combat.stunnedUntil
		and now >= combat.brokenUntil
		and not isSwinging(combat.swing, now)
		and CombatDefs.guard[StateService.current(char)] == true
end

function StateService.posture(char: Model): number
	local posture = states[char].posture
	local now = workspace:GetServerTimeNow()
	local regenFrom = math.max(posture.stamp, posture.regenAt)
	return math.min(Config.POSTURE_MAX, posture.value + math.max(0, now - regenFrom) * Config.POSTURE_REGEN)
end

-- negative takes posture off. regen waits at least `wait` seconds from now
function StateService.addPosture(char: Model, amount: number, wait: number?): number
	local posture = states[char].posture
	local now = workspace:GetServerTimeNow()
	posture.value = math.clamp(StateService.posture(char) + amount, 0, Config.POSTURE_MAX)
	posture.stamp = now
	if wait then
		posture.regenAt = math.max(posture.regenAt, now + wait)
	end
	return posture.value
end

-- a lunge goes past what the move state allows, so the speed check is told first
function StateService.raiseCap(char: Model, cap: number)
	local speed = states[char].speed
	speed.windowCap = math.max(speed.windowCap, cap)
end

function StateService.exempt(char: Model, seconds: number)
	local speed = states[char].speed
	speed.exemptUntil = math.max(speed.exemptUntil, workspace:GetServerTimeNow() + seconds)
end

function StateService.spend(char: Model, cost: number): boolean
	local stamina = states[char].stamina
	local now = workspace:GetServerTimeNow()
	local value = math.min(Config.STAMINA_MAX, stamina.value + (now - stamina.stamp) * Config.STAMINA_REGEN)
	if value < cost then
		return false
	end
	stamina.value = value - cost
	stamina.stamp = now
	return true
end

return StateService
