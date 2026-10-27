--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MoveDefs = require(ReplicatedStorage.Shared.Movement.MoveDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local Context = require(script.Parent.Parent.Movement.Context)

type Ctx = Context.Ctx

type Push = { velocity: Vector3, untilAt: number }

-- the juggle hold on the up axis only, or every axis for a pinned body
local UP = Vector3.new(0, Config.JUGGLE_FORCE, 0)
local PINNED = Vector3.one * Config.JUGGLE_FORCE

-- whatever the server does to this body: knockback, shoves, pins, the juggle hold, the ragdoll. this client owns the
-- character's physics, so the server asks and this carries it out
local Body = {}

local push: Push? = nil
-- where the server put this body against a wall or the floor, set on the next step
local pinAt: CFrame? = nil
-- held in the air by a juggle until this. riseUntil lets the hold work off the ground while the uppercut lifts, see Juggle
local juggleUntil = 0
local riseUntil = 0
-- a rise and a step the server asked for, taken on the next step where the body's position is known
local pendingRise: number? = nil
local pendingStep: Vector3? = nil
-- the height the juggle settled at, read on its first held step
local holdY: number? = nil
-- where a hit pinned the body on the flat, held on every axis until pinUntil
local holdFlat: Vector3? = nil
local pinUntil = 0
local isRagdolled = false
-- held still through a grip or a pin, see pose
local isAnchored = false
-- a broken guard can't turn, see pose
local isRooted = false

-- the lunge, knockback and shoves all drive the root through the movement mover
function Body.push(velocity: Vector3, duration: number)
	push = { velocity = velocity, untilAt = os.clock() + duration }
end

function Body.isJuggled(now: number): boolean
	return now < juggleUntil
end

local function move(c: Ctx, now: number)
	-- the knockback ends at the wall or the floor, and the body is set where the server says it hit
	local pin = pinAt
	if pin then
		pinAt = nil
		push = nil
		c.lv.Enabled = false
		c.root.AssemblyLinearVelocity = Vector3.zero
		c.root.CFrame = pin
	end

	-- a push with height, the slam's, drives the fall too
	local p = push
	if p and now < p.untilAt then
		if p.velocity.Y == 0 then
			Context.glide(c, p.velocity)
		else
			Context.drive(c, p.velocity)
		end
	elseif p then
		push = nil
		-- a dash out of a block owns the mover by now
		if not MoveDefs[c.state].isDash then
			c.lv.Enabled = false
		end
	end

	-- the uppercut moves the hold up by its rise, then a juggle keeps the body at that height with the hold mover,
	-- which a lunge into the target can't push past. the rise works from the ground, after it only in Fall or a dash,
	-- so a dash round the target stays level and a jump or a wall takes over. so does the slam's push. a hit's target
	-- is pinned on the flat too through its stun, moved along by the attacker's step, see Juggle
	local rise = pendingRise
	if rise then
		pendingRise = nil
		holdY = c.root.Position.Y + rise
		riseUntil = now + Config.LAUNCH_TIME
	end
	local step = pendingStep
	if step then
		pendingStep = nil
		holdFlat = c.root.Position + step
	end
	if now >= juggleUntil then
		holdY = nil
	end
	if now >= pinUntil then
		holdFlat = nil
	end
	local isDriven = push ~= nil and (push :: Push).velocity.Y ~= 0
	local isHolding = now < juggleUntil
		and (now < riseUntil or c.state == "Fall" or MoveDefs[c.state].isDash)
		and not isDriven
	if isHolding and not holdY then
		holdY = c.root.Position.Y
	end
	local y = holdY
	local flat = if isHolding then holdFlat else nil
	if isHolding and y then
		c.hold.Position = if flat then Vector3.new(flat.X, y, flat.Z) else Vector3.new(0, y, 0)
	end
	local axes = if flat then PINNED else UP
	if c.hold.MaxAxesForce ~= axes then
		c.hold.MaxAxesForce = axes
	end
	if c.hold.Enabled ~= isHolding then
		c.hold.Enabled = isHolding
	end
	c.isHeldUp = now < juggleUntil
end

-- downed is a ragdoll, and a grip holds both bodies still. the server frees the limbs and anchors the roots, but this
-- client owns the character's physics, so the Humanoid state, the push that tips it over and its own copy of the
-- anchor are set here. a body let go of mid grip goes back to Downed and tips over again. a pin is held the same
-- way. a broken guard already can't walk, and AutoRotate off stops shift lock turning it with the camera
local function pose(c: Ctx, server: Types.CombatState)
	local isDowned = server == "Downed"
	local isHeld = server == "Gripping" or server == "Gripped" or server == "WallStunned" or server == "FloorStunned"
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

function Body.step(c: Ctx, server: Types.CombatState, now: number)
	move(c, now)
	pose(c, server)
end

function Body.load(c: Ctx)
	push = nil
	pinAt = nil
	juggleUntil = 0
	riseUntil = 0
	pendingRise = nil
	pendingStep = nil
	holdY = nil
	holdFlat = nil
	pinUntil = 0
	isRagdolled = false
	isAnchored = false
	isRooted = false
	c.trove:Add(function()
		push = nil
	end)
end

-- the victim's own client moves its character, so the server asks it to fly
Remotes.Knockback.OnClientEvent:Connect(function(dir: Vector3, speed: number)
	Body.push(dir * speed, Config.KNOCKBACK_TIME)
end)

-- a hit that doesn't knock back moves the victim along the attacker's step, see CombatService
Remotes.Shove.OnClientEvent:Connect(function(dir: Vector3, speed: number)
	Body.push(dir * speed, Config.LUNGE_TIME)
end)

-- the server follows the knockback's path and tells the victim where it hit a wall or the floor, see CombatService
Remotes.Pin.OnClientEvent:Connect(function(at: CFrame)
	pinAt = at
end)

-- the server holds both fighters in a juggle, see Juggle. a rise throws the body up first, a step pins a hit's target
-- for pinFor, and 0 for both times lets go
Remotes.Juggle.OnClientEvent:Connect(function(rise: number, duration: number, step: Vector3?, pinFor: number)
	local now = os.clock()
	juggleUntil = now + duration
	pinUntil = now + pinFor
	if rise > 0 then
		pendingRise = rise
	end
	pendingStep = step
end)

return Body
