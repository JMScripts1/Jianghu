--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AttackDefs = require(ReplicatedStorage.Shared.AttackDefs)
local CombatDefs = require(ReplicatedStorage.Shared.CombatDefs)
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local Hitbox = require(script.Parent.Parent.Hitbox)
local NpcAnimator = require(script.Parent.Parent.NpcAnimator)
local RateLimit = require(script.Parent.Parent.RateLimit)
local StateService = require(script.Parent.StateService)

type CharState = StateService.CharState
type Swing = StateService.Swing

-- typed so the old solver takes them as keys of cooldownUntil
local PARRY: Types.CombatCooldown = "Parry"
local DELAY: Types.CombatCooldown = "Delay"

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
}

local CombatService = {}

-- players and NPCs alike, everything regen looks after
local characters: { [Model]: true } = {}
-- characters with a live swing, a held block or an end time still ahead. the step only looks at these
local active: { [Model]: true } = {}

local function isReady(st: CharState, name: Types.CombatCooldown, now: number): boolean
	return now + Config.COOLDOWN_TOLERANCE >= (st.combat.cooldownUntil[name] or 0)
end

local function publish(char: Model)
	local state = StateService.combatState(char)
	if char:GetAttribute("CombatState") ~= state then
		char:SetAttribute("CombatState", state)
	end
end

local function changePosture(char: Model, amount: number, wait: number?): number
	local value = StateService.addPosture(char, amount, wait)
	char:SetAttribute("Posture", value)
	return value
end

-- health floors at 1, combat never kills
local function damage(char: Model, amount: number)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum and amount > 0 then
		hum.Health = math.max(1, hum.Health - amount)
	end
end

-- a stun interrupts whatever the character was doing, and the later of two stuns wins
local function stun(st: CharState, untilTime: number)
	local combat = st.combat
	combat.stunnedUntil = math.max(combat.stunnedUntil, untilTime)
	combat.swing = nil
	combat.combo = 0
	combat.parryUntil = 0
end

-- the swing's end is what the next light's combo counts from
local function settle(st: CharState, now: number)
	local swing = st.combat.swing
	if swing and swing.endsAt and now >= swing.endsAt then
		st.combat.comboAt = swing.endsAt
		st.combat.swing = nil
	end
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

-- the server owns NPCs, so it pushes them itself. the mover only lives as long as the push
local function push(root: BasePart, velocity: Vector3, duration: number)
	local attach = Instance.new("Attachment")
	attach.Parent = root

	local mover = Instance.new("LinearVelocity")
	mover.Attachment0 = attach
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	mover.PrimaryTangentAxis = Vector3.xAxis
	mover.SecondaryTangentAxis = Vector3.zAxis
	mover.PlaneVelocity = Vector2.new(velocity.X, velocity.Z)
	mover.MaxForce = PUSH_FORCE
	mover.Parent = attach

	task.delay(duration, function()
		attach:Destroy()
	end)
end

-- a player's own client moves its character, so the server can only exempt it and ask it to fly
local function knockback(target: Model, root: BasePart, from: BasePart, speed: number)
	local look = from.CFrame.LookVector
	local dir = Vector3.new(look.X, 0, look.Z).Unit
	local plr = Players:GetPlayerFromCharacter(target)
	if plr then
		StateService.exempt(target, KNOCKBACK_EXEMPT)
		Remotes.Knockback:FireClient(plr, dir, speed)
	elseif not root.Anchored then
		push(root, dir * speed, Config.KNOCKBACK_TIME)
	end
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

-- each client makes its own effects from these, the server never builds any
local function fx(attacker: Model, target: Model, id: Types.AttackId, result: Types.HitResult)
	local at = target:GetPivot().Position
	for _, plr in Players:GetPlayers() do
		local char = plr.Character
		if char and (char:GetPivot().Position - at).Magnitude <= Config.FX_RANGE then
			Remotes.CombatFx:FireClient(plr, attacker, target, id, result)
		end
	end
end

local function resolve(
	attacker: Model,
	attackerSt: CharState,
	target: Model,
	def: Types.AttackDef,
	swing: Swing,
	now: number
): Types.HitResult?
	local st = StateService.get(target)
	local from = StateService.liveRoot(attacker)
	local root = StateService.liveRoot(target)
	if not st or not from or not root or st.combat.downed then
		return nil
	end
	local combat = st.combat

	if def.canDodge and now < st.dash.dodgeUntil then
		return "Dodged"
	end
	combat.taggedUntil = now + Config.COMBAT_TAG
	attackerSt.combat.taggedUntil = now + Config.COMBAT_TAG
	active[target] = true

	local front = isFront(root, from)
	if front and def.canParry and now < combat.parryUntil then
		-- a good parry is never locked out, the cooldown starts over
		combat.cooldownUntil[PARRY] = 0
		changePosture(target, Config.PARRY_POSTURE)
		stun(attackerSt, now + Config.PARRIED_STUN)
		return "Parried"
	end

	if front and def.canBlock and StateService.isBlocking(target) then
		-- a delayed hit takes more posture and holds its regen off longer
		local cost = def.posture * (if swing.isDelayed then Config.DELAY_POSTURE else 1)
		local wait = if swing.isDelayed then Config.DELAY_EXHAUST else Config.POSTURE_REGEN_DELAY
		if not def.isGuardBreak and changePosture(target, -cost, wait) > 0 then
			damage(target, def.damage * def.chip * swing.power)
			shove(target, root, from, swing.lunge)
			return "Blocked"
		end
		combat.brokenUntil = now + Config.POSTURE_BREAK_TIME
		stun(st, combat.brokenUntil)
		changePosture(target, Config.POSTURE_MAX, Config.POSTURE_BREAK_TIME)
		damage(target, def.damage * swing.power)
		shove(target, root, from, swing.lunge)
		return "Broken"
	end

	-- a delayed hit can't be parried out of, and stuns longer the longer it was held
	local bonus = if swing.isDelayed then Config.DELAY_STUN * math.min(1, swing.held / Config.DELAY_FULL) else 0
	stun(st, now + def.stun + bonus)
	if def.isHeavyStun or swing.isDelayed then
		combat.lockedUntil = math.max(combat.lockedUntil, now + def.stun + bonus)
		-- the client predicts its own parries, so it has to know which stuns it can't parry out of
		target:SetAttribute("LockedUntil", combat.lockedUntil)
	end
	damage(target, def.damage * swing.power)
	-- a delayed light doesn't knock back, so a delayed finisher carries the string on
	if def.knockback and not (swing.isDelayed and swing.kind == "Light") then
		knockback(target, root, from, def.knockback)
		return "Knocked"
	end
	shove(target, root, from, swing.lunge)
	return "Hit"
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

		local result: Types.HitResult? = resolve(char, st, target, def, swing, now)
		publish(target)
		if result then
			fx(char, target, swing.id, result)
			NpcAnimator.result(char, target, result)
		end
		if Config.DEBUG then
			print(swing.id, target.Name, result)
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
		elseif not swing.isHeld or not isReady(st, DELAY, reachedAt) then
			setHit(char, swing, def, swing.startedAt + def.windup)
			return
		end
		swing.isDelayed = true
		swing.delayedAt = reachedAt
		st.combat.cooldownUntil[DELAY] = reachedAt + CombatDefs.cooldowns[DELAY]
		NpcAnimator.slow(char, true)
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

	-- a light that lands just before the swing ends is the next hit, and starts exactly when that one ends
	local start = now
	local current = combat.swing
	if current then
		local endsAt = current.endsAt
		local activeUntil = current.activeUntil
		if not endsAt or not activeUntil or now < activeUntil or endsAt - now > Config.COMBAT_TOLERANCE then
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
local function block(st: CharState, state: Types.CombatState, move: Types.MoveState, now: number)
	local combat = st.combat
	combat.isBlockHeld = true

	if CombatDefs.canParry(state, now < combat.lockedUntil, move, isReady(st, PARRY, now)) then
		combat.parryUntil = now + Config.PARRY_WINDOW
		combat.cooldownUntil[PARRY] = now + CombatDefs.cooldowns[PARRY]
	end
end

-- the one way in for players and NPCs. the remote handler does the rate limit and type checks before this
function CombatService.act(char: Model, action: Types.CombatAction): boolean
	local st = StateService.get(char)
	if not st or not StateService.liveRoot(char) then
		return false
	end

	local now = workspace:GetServerTimeNow()
	settle(st, now)
	local state: Types.CombatState = StateService.combatState(char)
	local move: Types.MoveState = StateService.current(char)
	if not CombatDefs.states[state].actions[action] or not CombatDefs.from[action][move] then
		return false
	end

	if action == "Light" or action == "Heavy" then
		if not attack(char, st, action, move, now) then
			return false
		end
	elseif action == "Block" then
		block(st, state, move, now)
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
	publish(char)
	return true
end

local function step()
	local now = workspace:GetServerTimeNow()
	-- resolving a hit brings the target in, so the set is walked from a copy
	for char in table.clone(active) do
		local st = StateService.get(char)
		if not st then
			active[char] = nil
			continue
		end

		local swing = st.combat.swing
		if swing then
			advance(char, st, swing, now)
		end
		local queryAt = if swing then swing.nextQueryAt else nil
		if swing and queryAt and now >= queryAt then
			if queryAt == swing.hitAt and swing.lunge > 0 then
				lunge(char, swing.lunge)
			end
			query(char, st, swing, now)
			local nextAt = queryAt + Config.ACTIVE_STEP
			swing.nextQueryAt = if swing.activeUntil and nextAt <= swing.activeUntil then nextAt else nil
		end
		settle(st, now)
		publish(char)

		local combat = st.combat
		if
			not combat.swing
			and not combat.isBlockHeld
			and now >= combat.stunnedUntil
			and now >= combat.brokenUntil
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
	characters[char] = true
	Hitbox.add(char)
	char:SetAttribute("CombatState", "Idle")
	char:SetAttribute("Posture", Config.POSTURE_MAX)
	char:SetAttribute("LockedUntil", 0)
	-- the client picks its predicted attacks from this, the server's own copy is combat.weapon
	char:SetAttribute("Weapon", CombatDefs.defaultWeapon)
end

function CombatService.remove(char: Model)
	characters[char] = nil
	Hitbox.remove(char)
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
