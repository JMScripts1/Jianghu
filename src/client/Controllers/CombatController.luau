--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AttackDefs = require(ReplicatedStorage.Shared.AttackDefs)
local CombatDefs = require(ReplicatedStorage.Shared.CombatDefs)
local Config = require(ReplicatedStorage.Shared.Config)
local MoveDefs = require(ReplicatedStorage.Shared.MoveDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local WeaponDefs = require(ReplicatedStorage.Shared.WeaponDefs)
local Context = require(script.Parent.Movement.Context)
local InputController = require(script.Parent.InputController)

type Ctx = Context.Ctx

-- the client's copy of its own swing, on its own clock
type Swing = {
	id: Types.AttackId,
	button: InputController.Action,
	hitAt: number,
	endsAt: number,
	isHeld: boolean,
	-- studs a second pushed forward at the hit, 0 once it has gone
	lunge: number,
	isAir: boolean,
	track: AnimationTrack?,
}

type Push = { velocity: Vector3, untilAt: number }

-- typed so the old solver takes it as a key of cooldownUntil
local PARRY: Types.CombatCooldown = "Parry"

-- being hit can't be predicted, these only ever come from the server
local FROM_SERVER: { [Types.CombatState]: true } = { Stunned = true, PostureBroken = true, Downed = true }

local SPEED_CAPS: { [Types.CombatState]: number } = {
	Attacking = Config.ATTACK_WALK_SPEED,
	Parrying = Config.BLOCK_WALK_SPEED,
	Blocking = Config.BLOCK_WALK_SPEED,
	Stunned = Config.STUN_WALK_SPEED,
	PostureBroken = 0,
	Downed = 0,
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
local combo = 0
local comboAt = 0
local cooldownUntil: { [Types.CombatCooldown]: number } = {}
local hasAirAttacked = false
local isBlockHeld = false
local parryUntil = 0
-- a parry pressed while stunned is still a stun to movement, see StateService.canMove
local isParryOutOfStun = false
local push: Push? = nil
-- from CombatFx, played on the next step
local pending: Types.Reaction? = nil

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
		oneShot:Stop(Config.ANIM_FADE)
		oneShot = nil
	end
end

local function cancel()
	local current = swing
	if current and current.track then
		current.track:Stop(Config.ANIM_FADE)
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
		track:Play(Config.ANIM_FADE, 1, def.speed)
	end

	local hitAt = now + def.windup
	swing = {
		id = id,
		button = button,
		hitAt = hitAt,
		endsAt = hitAt + def.active + def.recovery,
		isHeld = true,
		-- the run drops to a walk as the swing starts, so the lunge keeps the momentum it came in with
		lunge = if picked.kind == "Run" then c.momentum * Config.RUN_ATTACK_LUNGE else def.lunge or 0,
		isAir = picked.kind == "Air",
		track = track,
	}
	Remotes.Combat:FireServer(action)
end

-- the swing's end is what the next light's combo counts from, and a light pressed near it starts right then
local function settle(c: Ctx, now: number)
	local current = swing
	if not current or now < current.endsAt then
		return
	end
	swing = nil
	comboAt = current.endsAt
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

-- the lunge, the air attack's height hold and knockback all drive the root through the movement mover
local function move(c: Ctx, now: number)
	local current = swing
	if current and current.lunge > 0 and now >= current.hitAt then
		push = { velocity = Context.look(c) * current.lunge, untilAt = now + Config.LUNGE_TIME }
		current.lunge = 0
	end
	if current and current.isAir and now < current.hitAt then
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
	local id = WeaponDefs[weaponOf(c)].reactions[state(c)]
	local track = if id then tracks[id] else nil
	if track == reacting then
		return
	end
	if reacting then
		reacting:Stop(Config.ANIM_FADE)
	end
	reacting = track
	if track then
		track:Play(Config.ANIM_FADE)
	end
end

-- a one shot over the loop, from this character's own weapon
local function respond(c: Ctx)
	local name: Types.Reaction? = pending
	pending = nil
	if MoveDefs[c.state].isDash then
		stopOneShot()
		return
	end
	local id = if name then WeaponDefs[weaponOf(c)].reactions[name] else nil
	local track = if id then tracks[id] else nil
	if track then
		stopOneShot()
		oneShot = track
		track:Play(Config.ANIM_FADE)
	end
end

-- a landing is never refused, see StateService.canMove
function CombatController.allows(c: Ctx, to: Types.MoveState): boolean
	if MoveDefs[to].group == "Grounded" and MoveDefs[c.state].group ~= "Grounded" then
		return true
	end
	return CombatDefs.states[rowState(c)].moves[to] == true
end

function CombatController.speedCap(c: Ctx): number
	return SPEED_CAPS[rowState(c)] or math.huge
end

function CombatController.load(c: Ctx)
	swing = nil
	isQueued = false
	combo = 0
	comboAt = 0
	table.clear(cooldownUntil)
	hasAirAttacked = false
	isBlockHeld = false
	parryUntil = 0
	isParryOutOfStun = false
	push = nil

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
		for _, id in weapon.reactions do
			loadTrack(id)
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
	settle(c, now)

	if InputController.take("Light") then
		local current = swing
		if not current then
			attack(c, "Light", "Light", now)
		elseif current.endsAt - now <= Config.INPUT_BUFFER then
			isQueued = true
		end
	end
	if InputController.take("Heavy") then
		attack(c, "Heavy", "Heavy", now)
	end

	local current = swing
	if current and current.isHeld and not InputController.isDown(current.button) then
		current.isHeld = false
		Remotes.Combat:FireServer("Release")
	end

	block(c, now)
	move(c, now)
	react(c)
	respond(c)
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

-- the victim's own client moves its character, so the server asks it to fly
Remotes.Knockback.OnClientEvent:Connect(function(dir: Vector3, speed: number)
	push = { velocity = dir * speed, untilAt = os.clock() + Config.KNOCKBACK_TIME }
	pending = "Knockback"
end)

-- a good parry starts the cooldown over on the server, so it does here too. either side of a hit plays its reaction
Remotes.CombatFx.OnClientEvent:Connect(function(attacker: Model, target: Model, _id: string, result: Types.HitResult)
	local char = player.Character
	if result == "Parried" and target == char then
		cooldownUntil[PARRY] = 0
	end
	if char and (attacker == char or target == char) then
		-- a plain hit has no reaction of its own, so it never clears a knockback that came in the same step
		pending = CombatDefs.reaction(result, attacker == char) or pending
	end
end)

return CombatController
