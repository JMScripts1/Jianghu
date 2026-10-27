--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local AttackDefs = require(script.Parent.AttackDefs)
local Config = require(script.Parent.Parent.Config)
local MoveDefs = require(script.Parent.Parent.Movement.MoveDefs)
local Types = require(script.Parent.Parent.Types)
local WeaponDefs = require(script.Parent.WeaponDefs)

type Target = Types.MoveState | "Dash"

-- every character starts with it, and the client reads it until the Weapon attribute arrives
local DEFAULT_WEAPON: Types.WeaponId = "fist"

-- typed so the old solver takes them as keys of a cooldown table
local HEAVY: Types.CombatCooldown = "Heavy"
local RUN: Types.CombatCooldown = "Run"
local LIGHT: Types.CombatCooldown = "Light"
local LAUNCH: Types.CombatCooldown = "Launch"

local COOLDOWNS: { [Types.CombatCooldown]: number } = {
	Parry = Config.PARRY_COOLDOWN,
	Heavy = Config.HEAVY_COOLDOWN,
	Delay = Config.DELAY_COOLDOWN,
	Run = Config.RUN_ATTACK_COOLDOWN,
	Launch = Config.LAUNCH_COOLDOWN,
	Light = Config.STRING_ENDLAG,
}

-- the most a character walks at in each state, anything not listed walks at its move state's own speed. both sides
-- cap with it, the client for players and the bot's motor for itself
local SPEED_CAPS: { [Types.CombatState]: number } = {
	Attacking = Config.ATTACK_WALK_SPEED,
	Parrying = Config.BLOCK_WALK_SPEED,
	Blocking = Config.BLOCK_WALK_SPEED,
	Stunned = Config.STUN_WALK_SPEED,
	PostureBroken = 0,
	WallStunned = 0,
	FloorStunned = 0,
	Downed = 0,
	Gripping = 0,
	Gripped = 0,
}

-- a pin holds its own pose, so it cuts a one shot still playing, like the knockback's, and none plays over it. the
-- pose stops on its last frame, so an animation shorter than the pin still covers all of it. both sides play by it,
-- the client for its own character and NpcAnimator for NPCs
local HOLDS_POSE: { [Types.CombatState]: true } = { WallStunned = true, FloorStunned = true }

type Row = {
	actions: { Types.CombatAction },
	-- nil allows every move state
	moves: { Target }?,
}

-- these only set or clear a held flag, so they're taken in every state and the client's flags never drift from the
-- server's. a block press opens a parry window only from Idle or a stun, see CombatService
local ALWAYS: { Types.CombatAction } = { "Release", "Block", "Unblock" }

local SLOWED: { Target } = { "Idle", "Walk", "Fall" }
local GUARDED: { Target } = { "Idle", "Walk", "Fall", "Dash" }

local rows: { [Types.CombatState]: Row } = {
	-- a grip is only started standing free, see CombatService
	Idle = { actions = { "Light", "Heavy", "Grip", "Slam" } },
	-- a light is only taken near the end of the swing
	Attacking = { actions = { "Light", "Slam" }, moves = SLOWED },
	Parrying = { actions = {}, moves = GUARDED },
	-- the swing wins while it runs, the block comes back after if still held
	Blocking = { actions = { "Light", "Heavy", "Slam" }, moves = GUARDED },
	Stunned = { actions = {}, moves = SLOWED },
	PostureBroken = { actions = {}, moves = SLOWED },
	-- the client anchors itself to the wall for the length of it
	WallStunned = { actions = {}, moves = SLOWED },
	FloorStunned = { actions = {}, moves = SLOWED },
	-- standing still is allowed, the walk speed of 0 is what keeps it down
	Downed = { actions = {}, moves = SLOWED },
	-- both bodies are anchored for the length of it. Grip again lets go
	Gripping = { actions = { "Grip" }, moves = SLOWED },
	Gripped = { actions = {}, moves = SLOWED },
}

local GROUND: { Target } = { "Idle", "Walk", "Run" }
local AIR: { Target } = { "Jump", "DoubleJump", "SlideJump", "LedgeLeap", "Fall" }
local CROUCHED: { Target } = { "CrouchIdle", "CrouchWalk" }

-- the move states each action can start in. nothing starts sliding, on a wall, mantling or dashing. a light crouched
-- is the uppercut, one out of Run is the running attack, and a heavy in the air only comes out of a juggle, see pick
local FROM: { [Types.CombatAction]: { { Target } } } = {
	Light = { GROUND, AIR, CROUCHED },
	Heavy = { GROUND, AIR },
	Slam = { AIR },
	Grip = { GROUND },
}

-- where a held block works and a block press opens a parry window. held anywhere else, it waits
local GUARD: { { Target } } = { GROUND, AIR }

local function expand(lists: { { Target } }?, owner: string): { [Types.MoveState]: true }
	local moves: { [Types.MoveState]: true } = {}
	if not lists then
		for move: Types.MoveState in MoveDefs do
			moves[move] = true
		end
		return table.freeze(moves)
	end

	for _, list in lists do
		for _, target: Target in list do
			if target == "Dash" then
				for move: Types.MoveState, def in MoveDefs do
					if def.isDash then
						moves[move] = true
					end
				end
			else
				assert(MoveDefs[target], `{owner} allows {target}, which has no row in MoveDefs`)
				moves[target] = true
			end
		end
	end
	return table.freeze(moves)
end

local states: { [Types.CombatState]: Types.CombatDef } = {}

-- loop vars are annotated because the old solver widens them to string
for state: Types.CombatState, row in rows do
	local actions: { [Types.CombatAction]: true } = {}
	for _, action: Types.CombatAction in row.actions do
		actions[action] = true
	end
	for _, action: Types.CombatAction in ALWAYS do
		actions[action] = true
	end
	table.freeze(actions)

	-- frozen in place, the new solver's read only freeze type doesn't fit CombatDef
	local def: Types.CombatDef = { actions = actions, moves = expand(if row.moves then { row.moves } else nil, state) }
	states[state] = def
	table.freeze(def)
end

local ACTIONS: { Types.CombatAction } = { "Light", "Heavy", "Release", "Block", "Unblock", "Grip", "Slam" }

-- Release, Unblock and Block are taken anywhere, a block press only sets the held flag
local from: { [Types.CombatAction]: { [Types.MoveState]: true } } = {}
for _, action: Types.CombatAction in ACTIONS do
	from[action] = expand(FROM[action], action)
end

local guard = expand(GUARD, "guard")

-- a fresh block press parries from Idle, or out of a stun that isn't a heavy stun, where a block works and off
-- cooldown. both sides call it, so the client never predicts a parry the server refuses
local function canParry(state: Types.CombatState, isLocked: boolean, move: Types.MoveState, isReady: boolean): boolean
	return (state == "Idle" or (state == "Stunned" and not isLocked)) and guard[move] == true and isReady
end

type Sides = { attacker: Types.Reaction?, target: Types.Reaction? }

-- what each side of a hit plays, each from its own weapon. anything not listed plays nothing extra, a posture break
-- shows through its state's loop
local ON_HIT: { [Types.CombatFx]: Sides } = {
	Parried = { attacker = "Deflected", target = "Parry" },
	Blocked = { target = "BlockHit" },
	Hit = { target = "Hurt" },
	Knocked = { target = "Knockback" },
}

local function reaction(result: Types.CombatFx, isAttacker: boolean): Types.Reaction?
	local sides = ON_HIT[result]
	if not sides then
		return nil
	end
	return if isAttacker then sides.attacker else sides.target
end

-- a heavy, running or air attack with no animation yet doesn't exist, so a weapon gets each one as its moveset does
local function has(id: Types.AttackId): boolean
	return AttackDefs[id].anim ~= ""
end

-- which attack an action is, the same rules on both sides so the client's prediction and the server never drift:
-- the heavy, the slam out of a juggle, the uppercut crouched, the air attack in the air outside a juggle,
-- the running attack out of Run, otherwise the next hit of the string.
-- nil when it can't happen. it changes nothing, the caller applies the result
local function pick(
	weapon: Types.WeaponId,
	action: Types.CombatAction,
	move: Types.MoveState,
	combo: number,
	sinceLast: number,
	hasAirAttacked: boolean,
	isJuggling: boolean,
	isReady: (Types.CombatCooldown) -> boolean
): Types.Pick?
	local def = WeaponDefs[weapon]
	local isAir = MoveDefs[move].group == "Airborne"
	if action == "Heavy" then
		return if isReady(HEAVY)
				and has(def.heavy)
				and (isJuggling or not isAir)
			then { id = def.heavy, kind = "Heavy", combo = 0, cooldown = HEAVY }
			else nil
	elseif action == "Slam" then
		-- it's the juggle's air attack, one per airtime, so a slam that misses or is blocked can't be thrown again
		return if isJuggling
				and not hasAirAttacked
				and has(def.slam)
			then { id = def.slam, kind = "Slam", combo = 0 }
			else nil
	elseif move == "CrouchIdle" or move == "CrouchWalk" then
		return if isReady(LAUNCH) and has(def.launch)
			then { id = def.launch, kind = "Launch", combo = 0, cooldown = LAUNCH }
			else nil
	elseif isAir and not isJuggling then
		-- the uppercut is the one way into air combat, outside a juggle only a weapon's own air attack swings up there
		return if hasAirAttacked or not has(def.air) then nil else { id = def.air, kind = "Air", combo = 0 }
	elseif move == "Run" and isReady(RUN) and has(def.run) then
		return { id = def.run, kind = "Run", combo = 0, cooldown = RUN }
	end

	if not isReady(LIGHT) then
		return nil
	end
	local count = if sinceLast > Config.COMBO_RESET or combo >= #def.light then 1 else combo + 1
	return { id = def.light[count], kind = "Light", combo = count }
end

-- the last hit of its string, the one with endlag after it
local function isFinisher(weapon: Types.WeaponId, id: Types.AttackId): boolean
	local light = WeaponDefs[weapon].light
	return light[#light] == id
end

-- an attribute or a remote's string back to a weapon, nil when it names none
local WEAPONS: { [string]: Types.WeaponId } = {}
for id: Types.WeaponId in WeaponDefs do
	WEAPONS[id] = id
end

local function weapon(value: unknown): Types.WeaponId?
	return if typeof(value) == "string" then WEAPONS[value] else nil
end

return table.freeze({
	states = table.freeze(states),
	from = table.freeze(from),
	guard = guard,
	cooldowns = table.freeze(COOLDOWNS),
	speedCaps = table.freeze(SPEED_CAPS),
	holdsPose = table.freeze(HOLDS_POSE),
	defaultWeapon = DEFAULT_WEAPON,
	weapon = weapon,
	pick = pick,
	canParry = canParry,
	reaction = reaction,
	isFinisher = isFinisher,
})
