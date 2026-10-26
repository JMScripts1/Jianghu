--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AttackDefs = require(ReplicatedStorage.Shared.Combat.AttackDefs)
local CombatDefs = require(ReplicatedStorage.Shared.Combat.CombatDefs)
local Config = require(ReplicatedStorage.Shared.Config)
local MoveDefs = require(ReplicatedStorage.Shared.Movement.MoveDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local Grip = require(script.Parent.Parent.Combat.Grip)
local Hitbox = require(script.Parent.Parent.Combat.Hitbox)
local Juggle = require(script.Parent.Parent.Combat.Juggle)
local Knockback = require(script.Parent.Parent.Combat.Knockback)
local NpcAnimator = require(script.Parent.Parent.Combat.NpcAnimator)
local Ping = require(script.Parent.Parent.Combat.Ping)
local Ragdoll = require(script.Parent.Parent.Combat.Ragdoll)
local WeaponModels = require(script.Parent.Parent.Combat.WeaponModels)
local RateLimit = require(script.Parent.Parent.RateLimit)
local StateService = require(script.Parent.StateService)

type CharState = StateService.CharState
type Swing = StateService.Swing

-- typed so the old solver takes them as keys of cooldownUntil
local PARRY: Types.CombatCooldown = "Parry"
local DELAY: Types.CombatCooldown = "Delay"
local LIGHT: Types.CombatCooldown = "Light"

local RUN_CAP = Config.MOMENTUM_MAX * Config.RUN_ATTACK_LUNGE
local RUN_RANGE = Config.MOMENTUM_MAX - Config.RUN_SPEED
-- the push reaches the victim's client a ping later, and the server sees it move later still
local KNOCKBACK_EXEMPT = Config.KNOCKBACK_TIME + Config.SPEED_SAMPLE_INTERVAL * 2
local PUSH_FORCE = 1e5
local MAX_ACTION_LEN = 8

-- the client only ever sends these names
local ACTIONS: { [string]: Types.CombatAction } = {
	Light = "Light",
	Heavy = "Heavy",
	Release = "Release",
	Block = "Block",
	Unblock = "Unblock",
	Grip = "Grip",
	Slam = "Slam",
}

local CombatService = {}

-- players and NPCs alike, everything regen looks after and a grip can find
local characters: { [Model]: true } = {}
-- characters with a live swing, a held block or an end time still ahead. the step only looks at these
local active: { [Model]: true } = {}
-- hits on players wait out the target's rewind before they land, so a parry pressed in time on its screen can still
-- arrive. oldest first
local held: { { attacker: Model, target: Model, swing: Swing, hitAt: number, landsAt: number } } = {}

local function isReady(st: CharState, name: Types.CombatCooldown, now: number): boolean
	return now + Config.COOLDOWN_TOLERANCE >= (st.combat.cooldownUntil[name] or 0)
end

local function changePosture(char: Model, amount: number, wait: number?): number
	local value = StateService.addPosture(char, amount, wait)
	char:SetAttribute("Posture", value)
	return value
end

-- health floors at 1, combat never kills
-- everything the character was doing stops. a held block stays held, so it comes back on getting up like after a stun
local function down(char: Model, st: CharState, now: number)
	local combat = st.combat
	combat.downed = true
	combat.downedAt = now
	combat.swing = nil
	combat.combo = 0
	combat.parryUntil = 0
	combat.parryFrom = 0
	active[char] = true
	Juggle.release(char, st)
	Ragdoll.set(char, true)
end

-- health floors at 1 so the Humanoid never dies. a hit that takes it there downs the character, chip through a block
-- only floors it
local function damage(char: Model, st: CharState, amount: number, canDown: boolean, now: number)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or amount <= 0 then
		return
	end
	hum.Health = math.max(1, hum.Health - amount)
	if canDown and hum.Health <= 1 then
		down(char, st, now)
	end
end

local function getUp(char: Model, st: CharState)
	st.combat.downed = false
	Ragdoll.set(char, false)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.Health = math.max(hum.Health, hum.MaxHealth * Config.DOWNED_HEALTH)
	end
	changePosture(char, Config.POSTURE_MAX)
end

-- a stun interrupts whatever the character was doing, and the later of two stuns wins
local function stun(st: CharState, untilTime: number)
	local combat = st.combat
	combat.stunnedUntil = math.max(combat.stunnedUntil, untilTime)
	combat.swing = nil
	combat.combo = 0
	combat.parryUntil = 0
	combat.parryFrom = 0
end

-- in the air by its move state, or held there by a juggle
local function isAloft(char: Model, st: CharState, now: number): boolean
	return now < st.combat.juggleUntil or MoveDefs[StateService.current(char)].group == "Airborne"
end

-- judged against where the window opened on the player's own screen, see Ping
local function isInParry(st: CharState, at: number): boolean
	return at >= st.combat.parryFrom and at < st.combat.parryFrom + Config.PARRY_WINDOW
end

local function isFront(target: BasePart, attacker: BasePart): boolean
	local look = target.CFrame.LookVector
	local to = attacker.Position - target.Position
	local flatTo = Vector3.new(to.X, 0, to.Z)
	if flatTo.Magnitude < 1e-3 then
		return true
	end
	return Vector3.new(look.X, 0, look.Z).Unit:Dot(flatTo.Unit) >= Config.GUARD_FACING
end

-- the server owns NPCs, so it pushes them itself. the mover only lives as long as the push. a flat push leaves the
-- fall alone, one with height drives it too
local function push(root: BasePart, velocity: Vector3, duration: number): Attachment
	local attach = Instance.new("Attachment")
	attach.Parent = root

	local mover = Instance.new("LinearVelocity")
	mover.Attachment0 = attach
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	if velocity.Y == 0 then
		mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
		mover.PrimaryTangentAxis = Vector3.xAxis
		mover.SecondaryTangentAxis = Vector3.zAxis
		mover.PlaneVelocity = Vector2.new(velocity.X, velocity.Z)
	else
		mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
		mover.VectorVelocity = velocity
	end
	mover.MaxForce = PUSH_FORCE
	mover.Parent = attach

	task.delay(duration, function()
		attach:Destroy()
	end)
	return attach
end

-- a player's own client moves its character, so the server can only exempt it and ask it to fly. either way the
-- server follows the path itself for a wall and the floor, see Knockback. drop angles it down, for the slam
local function knockback(target: Model, root: BasePart, from: BasePart, speed: number, now: number, drop: number)
	local look = from.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z).Unit
	local dir = flat * math.cos(drop) - Vector3.yAxis * math.sin(drop)
	local plr = Players:GetPlayerFromCharacter(target)
	local mover: Attachment? = nil
	if plr then
		StateService.exempt(target, KNOCKBACK_EXEMPT)
		Remotes.Knockback:FireClient(plr, dir, speed)
	elseif not root.Anchored then
		mover = push(root, dir * speed, Config.KNOCKBACK_TIME)
	end
	Knockback.start(target, root, dir * speed, now, mover)
end

-- a hit that doesn't knock back still moves its target along the attacker's step, as far as the attacker came in, so
-- a string doesn't walk the attacker into it
local function shove(target: Model, root: BasePart, from: BasePart, speed: number)
	if speed <= 0 then
		return
	end
	local look = from.CFrame.LookVector
	local dir = Vector3.new(look.X, 0, look.Z).Unit
	StateService.raiseCap(target, speed)
	local plr = Players:GetPlayerFromCharacter(target)
	if plr then
		Remotes.Shove:FireClient(plr, dir, speed)
	elseif not root.Anchored then
		push(root, dir * speed, Config.LUNGE_TIME)
	end
end

-- each client makes its own effects from these, the server never builds any. a wall or floor pin sends where its path
-- met the surface, the one thing only the server knows
local function fx(
	attacker: Model,
	target: Model,
	id: Types.AttackId,
	result: Types.CombatFx,
	point: Vector3?,
	normal: Vector3?
)
	local at = target:GetPivot().Position
	for _, plr in Players:GetPlayers() do
		local char = plr.Character
		if char and (char:GetPivot().Position - at).Magnitude <= Config.FX_RANGE then
			Remotes.CombatFx:FireClient(plr, attacker, target, id, result, point, normal)
		end
	end
end

local function resolve(
	attacker: Model,
	attackerSt: CharState,
	target: Model,
	def: Types.AttackDef,
	swing: Swing,
	hitAt: number,
	now: number
): Types.HitResult?
	local st = StateService.get(target)
	local from = StateService.liveRoot(attacker)
	local root = StateService.liveRoot(target)
	if not st or not from or not root or st.combat.downed then
		return nil
	end
	local combat = st.combat

	-- judged at the hit, so a dash that started while the hit was held counts too
	if def.canDodge and hitAt < st.dash.dodgeUntil then
		return "Dodged"
	end
	-- a gripper can't guard, so a hit lets go first and lands on a body that's free to be pushed
	Grip.release(target, st, false)
	combat.taggedUntil = now + Config.COMBAT_TAG
	attackerSt.combat.taggedUntil = now + Config.COMBAT_TAG
	active[target] = true

	local front = isFront(root, from)
	if front and def.canParry and isInParry(st, hitAt) then
		-- a good parry is never locked out, the cooldown starts over
		combat.cooldownUntil[PARRY] = 0
		changePosture(target, Config.PARRY_POSTURE)
		stun(attackerSt, now + Config.PARRIED_STUN)
		-- the parrier faces the attacker, so its look sends the attacker back a step instead of on through its lunge
		shove(attacker, from, root, Config.PARRY_RECOIL)
		return "Parried"
	end

	if front and def.canBlock and StateService.isBlocking(target) then
		-- a delayed hit takes more posture and holds its regen off longer
		local cost = def.posture * (if swing.isDelayed then Config.DELAY_POSTURE else 1)
		local wait = if swing.isDelayed then Config.DELAY_EXHAUST else Config.POSTURE_REGEN_DELAY
		if not def.isGuardBreak and changePosture(target, -cost, wait) > 0 then
			damage(target, st, def.damage * def.chip * swing.power, false, now)
			shove(target, root, from, swing.lunge)
			return "Blocked"
		end
		combat.brokenUntil = now + Config.POSTURE_BREAK_TIME
		stun(st, combat.brokenUntil)
		changePosture(target, Config.POSTURE_MAX, Config.POSTURE_BREAK_TIME)
		damage(target, st, def.damage * swing.power, true, now)
		shove(target, root, from, swing.lunge)
		return "Broken"
	end

	-- the first hit on a broken guard ends the break and sends the body flying, so the fight picks back up from range
	local isBreakHit = now < combat.brokenUntil
	if isBreakHit then
		combat.brokenUntil = now
		combat.stunnedUntil = now
	end

	-- a delayed hit can't be parried out of, and stuns longer the longer it was held
	local hold = if swing.isDelayed then math.min(1, swing.held / Config.DELAY_FULL) else 0
	local bonus = Config.DELAY_STUN * hold
	-- the reference's diminishing returns made gentler in the air (R7.5): each hit in a row on a juggled body stuns
	-- for JUGGLE_DECAY over its count of the full stun, so a juggle soon leaves a gap to parry out of. it counts from 1
	-- again once the body was free
	local scale = 1
	if now < combat.juggleUntil then
		combat.juggleHits = if now < combat.stunnedUntil then combat.juggleHits + 1 else 1
		scale = math.min(1, Config.JUGGLE_DECAY / combat.juggleHits)
	end
	local stunFor = (def.stun + bonus) * scale
	stun(st, now + stunFor)
	if def.isHeavyStun or swing.isDelayed then
		combat.lockedUntil = math.max(combat.lockedUntil, now + stunFor)
		-- the client predicts its own parries, so it has to know which stuns it can't parry out of
		target:SetAttribute("LockedUntil", combat.lockedUntil)
	end
	-- a delayed slam lands harder the longer it was held, the way a delayed hit stuns longer
	local boost = if isBreakHit
		then Config.BREAK_HIT_DAMAGE
		elseif swing.kind == "Slam" then 1 + Config.SLAM_DELAY_DAMAGE * hold
		else 1
	damage(target, st, def.damage * swing.power * boost, true, now)
	-- a delayed light doesn't knock back, so a delayed finisher carries the string on. nor does one in the air, so a
	-- juggle goes on until the slam or a heavy ends it
	local speed = if isBreakHit
		then Config.BREAK_KNOCKBACK
		elseif swing.kind == "Light" and (swing.isDelayed or isAloft(attacker, attackerSt, now)) then nil
		else def.knockback
	if speed then
		-- the slam spikes its target down, into the floor pin
		knockback(target, root, from, speed, now, if swing.kind == "Slam" then math.rad(Config.SLAM_ANGLE) else 0)
		return "Knocked"
	end
	shove(target, root, from, swing.lunge)
	return "Hit"
end

-- sets the body where the server's path met a wall or the floor. a player's own client moves its character, so that
-- client is told where
local function pin(char: Model, root: BasePart, pose: CFrame)
	local plr = Players:GetPlayerFromCharacter(char)
	if plr then
		Remotes.Pin:FireClient(plr, pose)
	elseif not root.Anchored then
		root.CFrame = pose
	end
	StateService.publish(char)
end

-- a knockback that meets a wall pins the body to it with its back to the wall, a true stun that also takes posture and
-- a little damage, so the attacker has time to close in. another before WALL_IMMUNITY only stops there, the way the
-- reference keeps a wall from pinning someone for good (R10.3)
local function wallSlam(char: Model, hit: RaycastResult)
	local st = StateService.get(char)
	local root = StateService.liveRoot(char)
	local now = workspace:GetServerTimeNow()
	if not st or not root or st.combat.downed or now < st.combat.wallImmuneUntil then
		return
	end
	-- before the damage, a slam that downs the body still hit the wall
	fx(char, char, "", "WallSlam", hit.Position, hit.Normal)
	local combat = st.combat
	changePosture(char, -Config.WALL_POSTURE)
	damage(char, st, Config.WALL_DAMAGE, true, now)
	if combat.downed then
		return
	end
	combat.wallImmuneUntil = now + Config.WALL_IMMUNITY
	combat.wallUntil = now + Config.WALL_STUN
	stun(st, combat.wallUntil)
	active[char] = true

	local out = Vector3.new(hit.Normal.X, 0, hit.Normal.Z).Unit
	local at = hit.Position + out * Config.WALL_SLAM_OFFSET
	at = Vector3.new(at.X, root.Position.Y, at.Z)
	pin(char, root, CFrame.lookAt(at, at + out))
	if Config.DEBUG then
		print("wall slam", char.Name)
	end
end

-- a slam that drives its target into the floor pins it there for SLAM_STUN, the way a wall pins, facing where it
-- faced. set at its root's height over the floor where the server's path met it
local function floorSlam(char: Model, hit: RaycastResult)
	local st = StateService.get(char)
	local root = StateService.liveRoot(char)
	local now = workspace:GetServerTimeNow()
	if not st or not root or st.combat.downed then
		return
	end
	fx(char, char, "", "FloorSlam", hit.Position, hit.Normal)
	st.combat.floorUntil = now + Config.SLAM_STUN
	stun(st, st.combat.floorUntil)
	active[char] = true

	local look = root.CFrame.LookVector
	local at = hit.Position + Vector3.new(0, Config.ROOT_HEIGHT, 0)
	pin(char, root, CFrame.lookAt(at, at + Vector3.new(look.X, 0, look.Z)))
	if Config.DEBUG then
		print("floor slam", char.Name)
	end
end

-- the uppercut throws both up into a juggle, the one way in for now, and a hit between the two of them in it holds
-- both where they are, the way the reference's aerials work (R10.1). a knockback ends it: the slam spikes the target
-- down, anything else out of the air sends it off at height. a parry drops both, and a hit from outside drops whoever
-- it lands on
local function juggle(
	attacker: Model,
	attackerSt: CharState,
	target: Model,
	swing: Swing,
	result: Types.HitResult,
	now: number
)
	local st = StateService.get(target)
	local root = StateService.liveRoot(target)
	local from = StateService.liveRoot(attacker)
	if not st or not root or not from then
		return
	end

	if result == "Parried" then
		Juggle.release(attacker, attackerSt)
		Juggle.release(target, st)
	elseif result ~= "Hit" and result ~= "Knocked" then
		return
	-- a body pinned to a wall or the floor stays there
	elseif now < st.combat.wallUntil or now < st.combat.floorUntil then
		return
	elseif swing.kind == "Launch" then
		Juggle.hold(attacker, attackerSt, from, now, Config.LAUNCH_RISE, Config.JUGGLE_HOLD)
		Juggle.hold(target, st, root, now, Config.LAUNCH_RISE, Config.JUGGLE_HOLD)
	elseif result == "Knocked" then
		-- the slam spikes it down, and anything else out of the air sends it off at height
		local wasAloft = isAloft(attacker, attackerSt, now)
		Juggle.release(attacker, attackerSt)
		if wasAloft and swing.kind ~= "Slam" then
			Juggle.hold(target, st, root, now, 0, Config.KNOCKBACK_TIME)
		else
			Juggle.release(target, st)
		end
	elseif now < attackerSt.combat.juggleUntil and now < st.combat.juggleUntil then
		Juggle.hold(attacker, attackerSt, from, now, 0, Config.JUGGLE_HOLD)
		Juggle.hold(target, st, root, now, 0, Config.JUGGLE_HOLD)
	else
		Juggle.release(target, st)
	end
end

-- stuns and damage run from when it lands, so a held string keeps its rhythm. only the dodge and parry look back
local function land(attacker: Model, target: Model, swing: Swing, hitAt: number, now: number)
	local st = StateService.get(attacker)
	if not st then
		return
	end
	local result: Types.HitResult? = resolve(attacker, st, target, AttackDefs[swing.id], swing, hitAt, now)
	StateService.publish(target)
	if result then
		juggle(attacker, st, target, swing, result, now)
		fx(attacker, target, swing.id, result)
		NpcAnimator.result(attacker, target, result)
	end
	if Config.DEBUG then
		print(swing.id, target.Name, result, math.round((now - hitAt) * 1000), "ms held")
	end
end

local function query(char: Model, st: CharState, swing: Swing, now: number)
	local root = StateService.liveRoot(char)
	if not root then
		return
	end
	local def = AttackDefs[swing.id]

	local count = 0
	for _ in swing.hit do
		count += 1
	end
	for _, target in Hitbox.query(root, def.box) do
		-- a parry clears the swing, so nothing after it lands
		if st.combat.swing ~= swing or count >= Config.MAX_TARGETS then
			break
		elseif swing.hit[target] then
			continue
		end
		swing.hit[target] = true
		count += 1

		-- one already inside the target's parry window has nothing left to wait for, so a clean parry lands at once
		local rewind = Ping.rewind(target)
		local targetSt = StateService.get(target)
		local isParried = def.canParry and targetSt ~= nil and isInParry(targetSt, now)
		if rewind > 0 and not isParried then
			table.insert(held, { attacker = char, target = target, swing = swing, hitAt = now, landsAt = now + rewind })
		else
			land(char, target, swing, now, now)
		end
	end
end

-- once the hit time is known so is the rest of the swing. a lunge goes past what the move state allows, so the speed
-- check is told now
local function setHit(char: Model, swing: Swing, def: Types.AttackDef, hitAt: number)
	swing.hitAt = hitAt
	swing.activeUntil = hitAt + def.active
	swing.nextQueryAt = hitAt
	swing.endsAt = hitAt + def.active + def.recovery
	if def.lunge then
		-- a delayed heavy lunges harder the longer it was held
		local bonus = if swing.kind == "Heavy" then Config.DELAY_LUNGE * swing.held / Config.DELAY_MAX else 0
		swing.lunge = def.lunge + bonus
		StateService.raiseCap(char, swing.lunge)
	end
end

-- the swing's end is what the next light's combo counts from. a strike with a follow hands straight on to it instead,
-- in the same animation, carrying its delay so the second strike keeps the bonus and lands that much later too
local function settle(char: Model, st: CharState, now: number)
	local swing = st.combat.swing
	local endsAt = if swing then swing.endsAt else nil
	if not swing or not endsAt or now < endsAt then
		return
	end
	local id = AttackDefs[swing.id].follow
	if not id then
		st.combat.comboAt = endsAt
		st.combat.swing = nil
		-- in the air the string runs on, see resolve
		if CombatDefs.isFinisher(st.combat.weapon, swing.id) and not isAloft(char, st, now) then
			st.combat.cooldownUntil[LIGHT] = endsAt + CombatDefs.cooldowns[LIGHT]
		end
		return
	end

	local nextSwing: Swing = {
		id = id,
		kind = swing.kind,
		startedAt = endsAt,
		isHeld = false,
		isDelayed = swing.isDelayed,
		held = swing.held,
		power = swing.power,
		lunge = 0,
		hit = {},
	}
	st.combat.swing = nextSwing
	setHit(char, nextSwing, AttackDefs[id], endsAt + AttackDefs[id].windup)
end

-- a player's own client pushes its lunge, the server only moves NPCs
local function lunge(char: Model, speed: number)
	local root = StateService.liveRoot(char)
	if root and not root.Anchored and not Players:GetPlayerFromCharacter(char) then
		local look = root.CFrame.LookVector
		push(root, Vector3.new(look.X, 0, look.Z).Unit * speed, Config.LUNGE_TIME)
	end
end

-- a swing that can be delayed has no hit time until it reaches its delay point. held through it with Delay ready,
-- the windup runs at DELAY_SPEED until Release or DELAY_MAX, and the hit lands that much later. both ends of the
-- hold are arrivals here, so the attacker's ping mostly cancels out of how long it was
local function advance(char: Model, st: CharState, swing: Swing, now: number)
	local def = AttackDefs[swing.id]
	local delayAt = def.delayAt
	if swing.hitAt or not delayAt then
		return
	end

	if not swing.delayedAt then
		local reachedAt = swing.startedAt + delayAt
		if now < reachedAt then
			return
		-- no tolerance here, the client makes the same call to slow its animation and has none. with give the server
		-- would delay a swing the client played on time
		elseif not swing.isHeld or reachedAt < (st.combat.cooldownUntil[DELAY] or 0) then
			setHit(char, swing, def, swing.startedAt + def.windup)
			return
		end
		swing.isDelayed = true
		swing.delayedAt = reachedAt
		st.combat.cooldownUntil[DELAY] = reachedAt + CombatDefs.cooldowns[DELAY]
		NpcAnimator.slow(char, true)
		-- the glint and charge a defender reads a delay by. a client's own parts never replicate, so it comes from here
		fx(char, char, swing.id, "Delay")
	end

	local delayedAt = swing.delayedAt
	if not delayedAt then
		return
	end
	local endsAt = delayedAt + Config.DELAY_MAX
	if not swing.isHeld or now >= endsAt then
		swing.held = math.min(now, endsAt) - delayedAt
		NpcAnimator.slow(char, false)
		setHit(char, swing, def, swing.startedAt + def.windup + swing.held * (1 - Config.DELAY_SPEED))
	end
end

local function attack(
	char: Model,
	st: CharState,
	action: Types.CombatAction,
	move: Types.MoveState,
	now: number
): boolean
	local combat = st.combat

	-- a light that lands just before the swing ends is the next hit, and starts exactly when that one ends. a strike
	-- with a follow isn't really ending, and a string's last hit has endlag after it on the ground, so nothing queues
	-- behind either
	local start = now
	local current = combat.swing
	if current then
		local endsAt = current.endsAt
		local activeUntil = current.activeUntil
		if
			not endsAt
			or not activeUntil
			or now < activeUntil
			or endsAt - now > Config.COMBAT_TOLERANCE
			or AttackDefs[current.id].follow
			or (CombatDefs.isFinisher(combat.weapon, current.id) and not isAloft(char, st, now))
		then
			return false
		end
		start = endsAt
	end

	-- a queued light carries the string on from the swing it follows
	local lastEnd = if current then start else combat.comboAt
	local picked: Types.Pick? = CombatDefs.pick(
		combat.weapon,
		action,
		move,
		combat.combo,
		start - lastEnd,
		combat.hasAirAttacked,
		now < combat.juggleUntil,
		function(name: Types.CombatCooldown): boolean
			return isReady(st, name, now)
		end
	)
	if not picked then
		return false
	end
	local id: Types.AttackId = picked.id
	local def = AttackDefs[id]
	combat.combo = picked.combo
	if picked.cooldown then
		combat.cooldownUntil[picked.cooldown] = start + CombatDefs.cooldowns[picked.cooldown]
	end
	if picked.kind == "Air" then
		combat.hasAirAttacked = true
	end

	-- the running attack hits harder the faster the server saw it come in, never from the client's momentum
	local power = 1
	if picked.kind == "Run" then
		power += Config.RUN_ATTACK_BONUS * math.clamp((st.speed.measured - Config.RUN_SPEED) / RUN_RANGE, 0, 1)
		StateService.raiseCap(char, RUN_CAP)
	end

	local swing: Swing = {
		id = id,
		kind = picked.kind,
		startedAt = start,
		isHeld = true,
		isDelayed = false,
		held = 0,
		power = power,
		lunge = 0,
		hit = {},
	}
	combat.swing = swing
	-- one that can be delayed gets its hit time at its delay point, see advance
	if not def.delayAt then
		setHit(char, swing, def, start + def.windup)
	end
	NpcAnimator.swing(char, id)
	return true
end

-- a press CombatDefs.canParry allows opens the parry window, anywhere else it's only held
local function block(char: Model, st: CharState, state: Types.CombatState, move: Types.MoveState, now: number)
	local combat = st.combat
	combat.isBlockHeld = true

	if CombatDefs.canParry(state, now < combat.lockedUntil, move, isReady(st, PARRY, now)) then
		combat.parryUntil = now + Config.PARRY_WINDOW
		-- the press arrived a rewind after it was made against what the player saw
		combat.parryFrom = now - Ping.rewind(char)
		combat.cooldownUntil[PARRY] = now + CombatDefs.cooldowns[PARRY]
	end
end

-- refused mid swing, in a grip or anything worse than standing or blocking. the combo starts over, and the cooldowns
-- stay with the character so a swap can't skip one
function CombatService.equip(char: Model, weapon: Types.WeaponId): boolean
	local st = StateService.get(char)
	if not st or not StateService.liveRoot(char) then
		return false
	end
	local state: Types.CombatState = StateService.combatState(char)
	if state ~= "Idle" and state ~= "Blocking" then
		return false
	end
	st.combat.weapon = weapon
	st.combat.combo = 0
	char:SetAttribute("Weapon", weapon)
	WeaponModels.hold(char, weapon)
	return true
end

-- the one way in for players and NPCs. the remote handler does the rate limit and type checks before this
function CombatService.act(char: Model, action: Types.CombatAction): boolean
	local st = StateService.get(char)
	if not st or not StateService.liveRoot(char) then
		return false
	end

	local now = workspace:GetServerTimeNow()
	settle(char, st, now)
	local state: Types.CombatState = StateService.combatState(char)
	local move: Types.MoveState = StateService.current(char)
	if not CombatDefs.states[state].actions[action] or not CombatDefs.from[action][move] then
		return false
	end

	if action == "Light" or action == "Heavy" or action == "Slam" then
		if not attack(char, st, action, move, now) then
			return false
		end
	elseif action == "Grip" then
		-- pressed again mid grip, it lets go the same as being cut short
		if st.combat.grip then
			Grip.release(char, st, false)
		elseif not Grip.start(char, st, now, characters) then
			return false
		end
	elseif action == "Block" then
		block(char, st, state, move, now)
	elseif action == "Unblock" then
		-- a parry window already open runs out on its own, so a quick tap still parries
		st.combat.isBlockHeld = false
	else
		local swing = st.combat.swing
		if swing then
			-- a delay point the step hasn't reached yet this frame was passed still held, then the hold ends here
			advance(char, st, swing, now)
			swing.isHeld = false
			advance(char, st, swing, now)
		end
	end

	active[char] = true
	StateService.publish(char)
	return true
end

local function step()
	local now = workspace:GetServerTimeNow()
	Knockback.step(now, wallSlam, floorSlam)
	NpcAnimator.step()
	Juggle.step(now)
	local i = 1
	while i <= #held do
		local h = held[i]
		if now >= h.landsAt then
			table.remove(held, i)
			land(h.attacker, h.target, h.swing, h.hitAt, now)
		else
			i += 1
		end
	end
	-- resolving a hit brings the target in, so the set is walked from a copy
	for char in table.clone(active) do
		-- a body a grip finished is left lying, its downed timer never stands it back up
		local st = StateService.get(char)
		if not st or not StateService.liveRoot(char) then
			active[char] = nil
			continue
		end
		local combat = st.combat
		Grip.step(char, st, now)
		if combat.downed and not combat.grippedBy and now >= combat.downedAt + Config.DOWNED_TIME then
			getUp(char, st)
		end

		local swing = combat.swing
		if swing then
			advance(char, st, swing, now)
		end
		local queryAt = if swing then swing.nextQueryAt else nil
		if swing and queryAt and now >= queryAt then
			if queryAt == swing.hitAt then
				if swing.lunge > 0 then
					lunge(char, swing.lunge)
				end
				-- the arc it cuts, for everyone but the attacker's own client, which played it already
				if AttackDefs[swing.id].swing then
					fx(char, char, swing.id, "Swing")
				end
			end
			query(char, st, swing, now)
			local nextAt = queryAt + Config.ACTIVE_STEP
			swing.nextQueryAt = if swing.activeUntil and nextAt <= swing.activeUntil then nextAt else nil
		end
		settle(char, st, now)
		StateService.publish(char)

		if
			not combat.downed
			and not combat.grip
			and not combat.swing
			and not combat.isBlockHeld
			and now >= combat.stunnedUntil
			and now >= combat.brokenUntil
			and now >= combat.wallUntil
			and now >= combat.floorUntil
			and now >= combat.parryUntil
		then
			active[char] = nil
		end
	end
end

local function onCombat(plr: Player, action: unknown)
	if not RateLimit.check(plr, "Combat") then
		return
	end
	if typeof(action) ~= "string" or #action > MAX_ACTION_LEN then
		return
	end

	local name: Types.CombatAction? = ACTIONS[action]
	local char = plr.Character
	if name and char and not CombatService.act(char, name) then
		Remotes.CombatDeny:FireClient(plr, name)
		if Config.DEBUG then
			print("combat refused", plr.Name, name, char:GetAttribute("CombatState"), char:GetAttribute("MoveState"))
		end
	end
end

-- health only comes back once nobody has hit or been hit for COMBAT_TAG, and posture's attribute catches up with its regen
local function regen(dt: number)
	local now = workspace:GetServerTimeNow()
	for char in characters do
		local st = StateService.get(char)
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not st or not hum or hum.Health <= 0 then
			continue
		end

		if now >= st.combat.taggedUntil and not st.combat.downed and hum.Health < hum.MaxHealth then
			hum.Health = math.min(hum.MaxHealth, hum.Health + Config.HEALTH_REGEN * dt)
		end
		local posture = StateService.posture(char)
		if char:GetAttribute("Posture") ~= posture then
			char:SetAttribute("Posture", posture)
		end
	end
end

-- players and NPCs alike, after StateService.add
function CombatService.add(char: Model)
	-- downed is a ragdoll and a grip kills one, neither may take the joints apart
	local hum = char:FindFirstChildOfClass("Humanoid") :: Humanoid
	hum.BreakJointsOnDeath = false
	hum.RequiresNeck = false
	characters[char] = true
	Hitbox.add(char)
	Ragdoll.add(char)
	char:SetAttribute("CombatState", "Idle")
	char:SetAttribute("Posture", Config.POSTURE_MAX)
	char:SetAttribute("LockedUntil", 0)
	-- the client picks its predicted attacks from this, the server's own copy is combat.weapon
	char:SetAttribute("Weapon", CombatDefs.defaultWeapon)
	WeaponModels.hold(char, CombatDefs.defaultWeapon)
end

-- before StateService.remove, a gripper leaving still has to let its victim go
function CombatService.remove(char: Model)
	Grip.remove(char)
	Knockback.stop(char)
	Juggle.remove(char)
	characters[char] = nil
	Hitbox.remove(char)
	Ragdoll.remove(char)
	WeaponModels.remove(char)
	active[char] = nil
end

Remotes.Combat.OnServerEvent:Connect(onCombat)
RunService.Heartbeat:Connect(step)

task.spawn(function()
	while true do
		regen(task.wait(Config.REGEN_INTERVAL))
	end
end)

return CombatService
