--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AttackDefs = require(ReplicatedStorage.Shared.Combat.AttackDefs)
local CombatDefs = require(ReplicatedStorage.Shared.Combat.CombatDefs)
local Config = require(ReplicatedStorage.Shared.Config)
local MoveDefs = require(ReplicatedStorage.Shared.Movement.MoveDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local WeaponDefs = require(ReplicatedStorage.Shared.Combat.WeaponDefs)
local Context = require(script.Parent.Movement.Context)
local InputController = require(script.Parent.InputController)

type Ctx = Context.Ctx

-- the client's copy of its own swing, on its own clock
type Swing = {
	id: Types.AttackId,
	button: InputController.Action,
	startedAt: number,
	-- these move later while a delay is held, see delay
	hitAt: number,
	endsAt: number,
	isHeld: boolean,
	-- when it reaches its delay point, nil once it's past it or for one that can't be delayed
	delayAt: number?,
	delayedAt: number?,
	isHolding: boolean,
	-- seconds the delay was held for, carried into a follow so it lunges the same way the server's does
	held: number,
	-- studs a second pushed forward at the hit, 0 once it has gone
	lunge: number,
	kind: Types.AttackKind,
	track: AnimationTrack?,
}

type Push = { velocity: Vector3, untilAt: number }

-- typed so the old solver takes them as keys of cooldownUntil
local PARRY: Types.CombatCooldown = "Parry"
local DELAY: Types.CombatCooldown = "Delay"
local LIGHT: Types.CombatCooldown = "Light"
local GRIP: Types.CombatAction = "Grip"

-- being hit can't be predicted, these only ever come from the server
local FROM_SERVER: { [Types.CombatState]: true } =
	{ Stunned = true, PostureBroken = true, WallStunned = true, Downed = true, Gripping = true, Gripped = true }

-- a pin holds its own pose, so it cuts a one shot still playing, like the knockback's, and none plays over it
local HOLDS_POSE: { [Types.CombatState]: true } = { WallStunned = true }

local SPEED_CAPS: { [Types.CombatState]: number } = {
	Attacking = Config.ATTACK_WALK_SPEED,
	Parrying = Config.BLOCK_WALK_SPEED,
	Blocking = Config.BLOCK_WALK_SPEED,
	Stunned = Config.STUN_WALK_SPEED,
	PostureBroken = 0,
	WallStunned = 0,
	Downed = 0,
	Gripping = 0,
	Gripped = 0,
}

-- turn the attributes back into names, anything else is ignored
local BY_NAME: { [string]: Types.CombatState } = {}
for state: Types.CombatState in CombatDefs.states do
	BY_NAME[state] = state
end
local BY_WEAPON: { [string]: Types.WeaponId } = {}
for weapon: Types.WeaponId in WeaponDefs do
	BY_WEAPON[weapon] = weapon
end

local player = Players.LocalPlayer

local CombatController = {}

local animations: { [string]: Animation } = {}
-- by animation id, so every weapon on the same moveset shares one track
local tracks: { [string]: AnimationTrack } = {}
local reacting: AnimationTrack? = nil
-- a one shot reaction, a swing or a dash cuts it
local oneShot: AnimationTrack? = nil

local swing: Swing? = nil
local isQueued = false
-- a swap starts the string over on the server, so it does here too
local equipped: Types.WeaponId? = nil
local combo = 0
local comboAt = 0
local cooldownUntil: { [Types.CombatCooldown]: number } = {}
local hasAirAttacked = false
local isBlockHeld = false
local parryUntil = 0
-- a parry pressed while stunned is still a stun to movement, see StateService.canMove
local isParryOutOfStun = false
local isRagdolled = false
-- held still through a grip or a wall pin, see body
local isAnchored = false
-- a broken guard can't turn, see body
local isRooted = false
local push: Push? = nil
-- where the server put this body against a wall, set on the next step
local pinAt: CFrame? = nil
-- from CombatFx, played on the next step
local pending: Types.Reaction? = nil
-- which of a reaction's animations played last
local turns: { [Types.Reaction]: number } = {}

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

local function serverState(c: Ctx): Types.CombatState
	local value = c.char:GetAttribute("CombatState")
	return if typeof(value) == "string" and BY_NAME[value] then BY_NAME[value] else "Idle"
end

-- the client's own swings and blocks are predicted, being hit only comes from the server
local function state(c: Ctx): Types.CombatState
	local server: Types.CombatState = serverState(c)
	if FROM_SERVER[server] then
		return server
	elseif os.clock() < parryUntil then
		return "Parrying"
	elseif swing then
		return "Attacking"
	elseif isBlockHeld and CombatDefs.guard[c.state] then
		return "Blocking"
	end
	return "Idle"
end

-- what movement and walk speed go by, where a parry out of stun is still a stun
local function rowState(c: Ctx): Types.CombatState
	local current: Types.CombatState = state(c)
	return if current == "Parrying" and isParryOutOfStun then "Stunned" else current
end

local function stopOneShot()
	if oneShot then
		oneShot:Stop(Config.COMBAT_FADE)
		oneShot = nil
	end
end

local function cancel()
	local current = swing
	if current and current.track then
		current.track:Stop(Config.COMBAT_FADE)
	end
	swing = nil
	isQueued = false
	combo = 0
end

-- the server's copy is the truth, this only picks which attack to predict
local function weaponOf(c: Ctx): Types.WeaponId
	local value = c.char:GetAttribute("Weapon")
	return if typeof(value) == "string" and BY_WEAPON[value] then BY_WEAPON[value] else CombatDefs.defaultWeapon
end

local function attack(c: Ctx, action: Types.CombatAction, button: InputController.Action, now: number)
	if not CombatDefs.states[state(c)].actions[action] or not CombatDefs.from[action][c.state] then
		return
	end
	local picked: Types.Pick? = CombatDefs.pick(
		weaponOf(c),
		action,
		c.state,
		combo,
		now - comboAt,
		hasAirAttacked,
		function(name: Types.CombatCooldown): boolean
			return now >= (cooldownUntil[name] or 0)
		end
	)
	if not picked then
		return
	end
	local id: Types.AttackId = picked.id
	combo = picked.combo
	if picked.cooldown then
		cooldownUntil[picked.cooldown] = now + CombatDefs.cooldowns[picked.cooldown]
	end
	if picked.kind == "Air" then
		hasAirAttacked = true
	end

	local def = AttackDefs[id]
	local track = tracks[def.anim]
	stopOneShot()
	if track then
		track:Play(Config.COMBAT_FADE, 1, def.speed)
	end

	local hitAt = now + def.windup
	swing = {
		id = id,
		button = button,
		startedAt = now,
		hitAt = hitAt,
		endsAt = hitAt + def.active + def.recovery,
		isHeld = true,
		delayAt = if def.delayAt then now + def.delayAt else nil,
		isHolding = false,
		held = 0,
		-- the run drops to a walk as the swing starts, so the lunge keeps the momentum it came in with
		lunge = if picked.kind == "Run" then c.momentum * Config.RUN_ATTACK_LUNGE else def.lunge or 0,
		kind = picked.kind,
		track = track,
	}
	Remotes.Combat:FireServer(action)
end

-- the same handover to a follow CombatService makes. the animation is already playing it, so nothing new starts
local function follow(current: Swing, id: Types.AttackId)
	local def = AttackDefs[id]
	local hitAt = current.endsAt + def.windup
	local bonus = if current.kind == "Heavy" then Config.DELAY_LUNGE * current.held / Config.DELAY_MAX else 0
	swing = {
		id = id,
		button = current.button,
		startedAt = current.endsAt,
		hitAt = hitAt,
		endsAt = hitAt + def.active + def.recovery,
		isHeld = false,
		isHolding = false,
		held = current.held,
		lunge = if def.lunge then def.lunge + bonus else 0,
		kind = current.kind,
		track = current.track,
	}
end

-- the swing's end is what the next light's combo counts from, and a light pressed near it starts right then
local function settle(c: Ctx, now: number)
	local current = swing
	if not current or now < current.endsAt then
		return
	end
	local id = AttackDefs[current.id].follow
	if id then
		follow(current, id)
		return
	end
	swing = nil
	comboAt = current.endsAt
	if CombatDefs.isFinisher(weaponOf(c), current.id) then
		cooldownUntil[LIGHT] = current.endsAt + CombatDefs.cooldowns[LIGHT]
	end
	if isQueued then
		isQueued = false
		attack(c, "Light", "Light", now)
	end
end

-- the same CombatDefs.canParry call CombatService makes, with the lock the server published
local function block(c: Ctx, now: number)
	local held = InputController.isDown("Block")
	if held == isBlockHeld then
		return
	end
	local before: Types.CombatState = state(c)
	isBlockHeld = held
	if not held then
		Remotes.Combat:FireServer("Unblock")
		return
	end

	local lockedUntil = c.char:GetAttribute("LockedUntil")
	local isLocked = typeof(lockedUntil) == "number" and workspace:GetServerTimeNow() < lockedUntil
	if CombatDefs.canParry(before, isLocked, c.state, now >= (cooldownUntil[PARRY] or 0)) then
		parryUntil = now + Config.PARRY_WINDOW
		cooldownUntil[PARRY] = now + CombatDefs.cooldowns[PARRY]
		isParryOutOfStun = before == "Stunned"
	end
	Remotes.Combat:FireServer("Block")
end

-- the same delay CombatService runs, on the client's own clock. held through the delay point with Delay ready, the
-- windup and the animation run at DELAY_SPEED until the button comes up or DELAY_MAX, and the hit moves later
local function hold(now: number)
	local current = swing
	if not current then
		return
	end
	local def = AttackDefs[current.id]

	local reachedAt = current.delayAt
	if reachedAt and now >= reachedAt then
		current.delayAt = nil
		if current.isHeld and reachedAt >= (cooldownUntil[DELAY] or 0) then
			current.delayedAt = reachedAt
			current.isHolding = true
			cooldownUntil[DELAY] = reachedAt + CombatDefs.cooldowns[DELAY]
			if current.track then
				current.track:AdjustSpeed(def.speed * Config.DELAY_SPEED)
			end
		end
	end

	local delayedAt = current.delayedAt
	if not delayedAt or not current.isHolding then
		return
	end
	local endsAt = delayedAt + Config.DELAY_MAX
	local held = math.min(now, endsAt) - delayedAt
	current.hitAt = current.startedAt + def.windup + held * (1 - Config.DELAY_SPEED)
	current.endsAt = current.hitAt + def.active + def.recovery
	if not current.isHeld or now >= endsAt then
		current.isHolding = false
		current.held = held
		if current.track then
			current.track:AdjustSpeed(def.speed)
		end
		-- a delayed heavy lunges harder the longer it was held
		if def.lunge and current.kind == "Heavy" then
			current.lunge = def.lunge + Config.DELAY_LUNGE * held / Config.DELAY_MAX
		end
	end
end

-- the lunge, the air attack's height hold and knockback all drive the root through the movement mover
local function move(c: Ctx, now: number)
	-- the knockback ends at the wall, and the body is set where the server says it hit
	local pin = pinAt
	if pin then
		pinAt = nil
		push = nil
		c.lv.Enabled = false
		c.root.AssemblyLinearVelocity = Vector3.zero
		c.root.CFrame = pin
	end

	local current = swing
	if current and current.lunge > 0 and now >= current.hitAt then
		push = { velocity = Context.look(c) * current.lunge, untilAt = now + Config.LUNGE_TIME }
		current.lunge = 0
	end
	if current and current.kind == "Air" and now < current.hitAt then
		local v = c.root.AssemblyLinearVelocity
		c.root.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z)
	end

	local p = push
	if p and now < p.untilAt then
		Context.glide(c, p.velocity)
	elseif p then
		push = nil
		-- a dash out of a block owns the mover by now
		if not MoveDefs[c.state].isDash then
			c.lv.Enabled = false
		end
	end
end

local function react(c: Ctx)
	local current: Types.CombatState = state(c)
	-- Idle and Attacking have no slot at all
	local ids = WeaponDefs[weaponOf(c)].reactions[current]
	local id = if ids then ids[1] else nil
	local track = if id then tracks[id] else nil
	if track == reacting then
		return
	end
	if reacting then
		reacting:Stop(Config.COMBAT_FADE)
	end
	reacting = track
	if track and HOLDS_POSE[current] then
		stopOneShot()
	end
	if track then
		track:Play(Config.COMBAT_FADE)
	end
end

-- a one shot over the loop, from this character's own weapon. a reaction with several animations takes turns
local function respond(c: Ctx)
	local name: Types.Reaction? = pending
	pending = nil
	if MoveDefs[c.state].isDash or HOLDS_POSE[state(c)] then
		stopOneShot()
		return
	end
	local ids = if name then WeaponDefs[weaponOf(c)].reactions[name] else nil
	local id: string? = nil
	if name and ids and #ids > 0 then
		local turn = (turns[name] or 0) % #ids + 1
		turns[name] = turn
		id = ids[turn]
	end
	local track = if id then tracks[id] else nil
	if track then
		stopOneShot()
		oneShot = track
		track:Play(Config.COMBAT_FADE)
	end
end

-- downed is a ragdoll, and a grip holds both bodies still. the server frees the limbs and anchors the roots, but this
-- client owns the character's physics, so the Humanoid state, the push that tips it over and its own copy of the
-- anchor are set here. a body let go of mid grip goes back to Downed and tips over again. a wall pin is held the same
-- way. a broken guard already can't walk, and AutoRotate off stops shift lock turning it with the camera
local function body(c: Ctx)
	local server: Types.CombatState = serverState(c)
	local isDowned = server == "Downed"
	local isHeld = server == "Gripping" or server == "Gripped" or server == "WallStunned"
	local isBroken = server == "PostureBroken"
	if isDowned == isRagdolled and isHeld == isAnchored and isBroken == isRooted then
		return
	end
	-- unanchored before the push, an anchored root doesn't take one
	c.root.Anchored = isHeld
	c.hum.AutoRotate = not isDowned and not isHeld and not isBroken
	if isDowned ~= isRagdolled then
		c.hum:ChangeState(if isDowned then Enum.HumanoidStateType.Physics else Enum.HumanoidStateType.Running)
		if isDowned then
			c.root:ApplyAngularImpulse(c.root.CFrame.RightVector * Config.RAGDOLL_TIP)
		end
	end
	isRagdolled = isDowned
	isAnchored = isHeld
	isRooted = isBroken
end

-- a landing is never refused, see StateService.canMove
function CombatController.allows(c: Ctx, to: Types.MoveState): boolean
	if MoveDefs[to].group == "Grounded" and MoveDefs[c.state].group ~= "Grounded" then
		return true
	end
	return CombatDefs.states[rowState(c)].moves[to] == true
end

function CombatController.speedCap(c: Ctx): number
	local current = swing
	if current and current.isHolding then
		return Config.DELAY_WALK_SPEED
	end
	return SPEED_CAPS[rowState(c)] or math.huge
end

function CombatController.load(c: Ctx)
	swing = nil
	isQueued = false
	equipped = nil
	combo = 0
	comboAt = 0
	table.clear(cooldownUntil)
	hasAirAttacked = false
	isBlockHeld = false
	parryUntil = 0
	isParryOutOfStun = false
	isRagdolled = false
	isAnchored = false
	isRooted = false
	push = nil
	pinAt = nil

	local animator = c.hum:WaitForChild("Animator") :: Animator
	local function loadTrack(id: string)
		if id ~= "" and not tracks[id] then
			tracks[id] = animator:LoadAnimation(animation(id))
		end
	end
	for _, def in AttackDefs do
		loadTrack(def.anim)
	end
	for _, weapon in WeaponDefs do
		for _, ids in weapon.reactions do
			for _, id in ids do
				loadTrack(id)
			end
		end
	end

	c.trove:Add(function()
		table.clear(tracks)
		reacting = nil
		oneShot = nil
		pending = nil
		swing = nil
		push = nil
	end)
end

-- true when a swing started this step
function CombatController.step(c: Ctx): boolean
	local now = os.clock()
	local was = swing
	if FROM_SERVER[serverState(c)] and swing then
		cancel()
	end
	if now >= parryUntil then
		isParryOutOfStun = false
	end
	if MoveDefs[c.state].group == "Grounded" then
		hasAirAttacked = false
	end
	local weapon: Types.WeaponId = weaponOf(c)
	if weapon ~= equipped then
		equipped = weapon
		combo = 0
	end
	settle(c, now)

	if InputController.take("Light") then
		local current = swing
		if not current then
			attack(c, "Light", "Light", now)
		-- a strike with a follow isn't really ending, so the buffer waits for the last one
		elseif current.endsAt - now <= Config.INPUT_BUFFER and not AttackDefs[current.id].follow then
			isQueued = true
		end
	end
	if InputController.take("Heavy") then
		attack(c, "Heavy", "Heavy", now)
	end
	-- the server picks the body, the client only asks. nothing is predicted, Gripping comes back as the state
	if
		InputController.take("Grip")
		and CombatDefs.states[state(c)].actions[GRIP]
		and CombatDefs.from[GRIP][c.state]
	then
		Remotes.Combat:FireServer("Grip")
	end

	local current = swing
	if current and current.isHeld and not InputController.isDown(current.button) then
		current.isHeld = false
		Remotes.Combat:FireServer("Release")
	end
	hold(now)

	block(c, now)
	move(c, now)
	react(c)
	respond(c)
	body(c)
	return swing ~= nil and swing ~= was
end

-- a denial for an action the client already replaced is for one the server judged on its own, so only the live
-- swing is undone
Remotes.CombatDeny.OnClientEvent:Connect(function(action: string)
	if Config.DEBUG then
		print("combat denied", action)
	end
	local current = swing
	if current and current.button == action then
		cancel()
	end
end)

-- the server times this round trip to judge parries and hits from this screen, so it goes straight back
Remotes.Ping.OnClientEvent:Connect(function()
	Remotes.Ping:FireServer()
end)

-- the victim's own client moves its character, so the server asks it to fly
Remotes.Knockback.OnClientEvent:Connect(function(dir: Vector3, speed: number)
	push = { velocity = dir * speed, untilAt = os.clock() + Config.KNOCKBACK_TIME }
end)

-- the server follows the knockback's path and tells the victim where it hit a wall, see CombatService.slam
Remotes.WallSlam.OnClientEvent:Connect(function(pose: CFrame)
	pinAt = pose
end)

-- a hit that doesn't knock back moves the victim along the attacker's step, see CombatService
Remotes.Shove.OnClientEvent:Connect(function(dir: Vector3, speed: number)
	push = { velocity = dir * speed, untilAt = os.clock() + Config.LUNGE_TIME }
end)

-- a good parry starts the cooldown over on the server, so it does here too. either side of a hit plays its reaction.
-- a parried swing is over on the server already, so it stops here without waiting for the Stunned attribute, or it
-- keeps playing under the deflect
Remotes.CombatFx.OnClientEvent:Connect(function(attacker: Model, target: Model, _id: string, result: Types.HitResult)
	local char = player.Character
	if result == "Parried" and target == char then
		cooldownUntil[PARRY] = 0
	elseif result == "Parried" and attacker == char then
		cancel()
	end
	if char and (attacker == char or target == char) then
		-- a result with nothing to play never clears one still waiting for the step
		pending = CombatDefs.reaction(result, attacker == char) or pending
	end
end)

return CombatController
