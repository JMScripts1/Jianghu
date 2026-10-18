--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MoveDefs = require(ReplicatedStorage.Shared.MoveDefs)
local Probes = require(ReplicatedStorage.Shared.Probes)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local RateLimit = require(script.Parent.Parent.RateLimit)
local StateService = require(script.Parent.StateService)

local MAX_WIRE_LEN = 16

local DASH_DIRS: { [string]: Types.DashDir } = { F = "F", B = "B", L = "L", R = "R" }

-- the back dash's burst can outrun the other dashes
local DASH_CAP = math.max(Config.DASH_SPEED, Config.BACK_DASH_SPEED * Config.BACK_DASH_BOOST)
-- the burst comes at its animation's marker, which is never later than the end of the backstep
local BACK_DASH_TIME = Config.BACK_DASH_TIME + Config.BACK_DASH_BOOST_TIME

local MovementService = {}

-- what the client may send, Idle and CrouchIdle ride on Walk and CrouchWalk
local WIRES: { [string]: Types.MoveState } = {}
for state: Types.MoveState, def in MoveDefs do
	if def.wire == state then
		WIRES[state] = state
	end
end

-- a place saved with the groups already has them
for _, name in { "Characters", "MoveProbe" } do
	if not PhysicsService:IsCollisionGroupRegistered(name) then
		PhysicsService:RegisterCollisionGroup(name)
	end
end
PhysicsService:CollisionGroupSetCollidable("MoveProbe", "Characters", false)

local function setGroup(inst: Instance)
	if inst:IsA("BasePart") then
		inst.CollisionGroup = "Characters"
	end
end

-- accessories load in after CharacterAdded
local function onCharacter(char: Model)
	for _, inst in char:GetDescendants() do
		setGroup(inst)
	end
	char.DescendantAdded:Connect(setGroup)
end

local function onPlayer(plr: Player)
	plr.CharacterAdded:Connect(onCharacter)
	if plr.Character then
		onCharacter(plr.Character)
	end
end

local function deny(plr: Player, intent: string)
	Remotes.MoveDeny:FireClient(plr, intent)
end

local function onMove(plr: Player, wire: unknown)
	if not RateLimit.check(plr, "Move") then
		return
	end
	if typeof(wire) ~= "string" or #wire > MAX_WIRE_LEN then
		return
	end
	local to: Types.MoveState? = WIRES[wire]
	if not to then
		return
	end

	local char = plr.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char.PrimaryPart
	local state = char and StateService.get(char)
	if not char or not hum or hum.Health <= 0 or not root or not state then
		return
	end

	local now = workspace:GetServerTimeNow()
	local move = state.move
	local from = MoveDefs[StateService.current(char)]
	local def = MoveDefs[to]

	-- already there, usually a timed state both sides ended on their own
	if from.wire == to then
		char:SetAttribute("MoveState", to)
		return
	end

	if
		not StateService.canMove(char)
		or not from.to[to]
		or now < (move.cooldownUntil[to] or 0) - Config.COOLDOWN_SLACK
	then
		deny(plr, to)
		return
	end

	local landing = def.group == "Grounded" and from.group ~= "Grounded"
	local slack =
		math.min(Config.PROBE_SLACK + root.AssemblyLinearVelocity.Magnitude * Config.PROBE_LAG, Config.PROBE_SLACK_MAX)
	local wallHit: Types.WallHit? = nil
	local ok = true
	if landing then
		ok = Probes.ground(root, slack) ~= nil
	elseif to == "Jump" or to == "SlideJump" then
		ok = now - move.groundedAt <= Config.GROUND_GRACE or Probes.ground(root, slack) ~= nil
	elseif to == "DoubleJump" then
		ok = move.airJumps < Config.MAX_AIR_JUMPS
	elseif to == "WallRun" or to == "WallCling" then
		-- any kind of wall will do, near the facing split the server's older view can read it the other way,
		-- and the wall run speed rule is the client's since the server can't know momentum
		wallHit = Probes.wall(root, math.huge, slack)
		ok = wallHit ~= nil and wallHit.part ~= move.lastWallPart
	elseif to == "VaultLow" then
		ok = Probes.ground(root, slack) ~= nil and Probes.vaultLow(root, slack) ~= nil
	elseif to == "VaultMid" then
		ok = Probes.vaultMid(root, slack) ~= nil
	end
	if not ok then
		deny(plr, to)
		return
	end

	move.state = to
	move.since = now
	move.endsAt = if def.duration then now + def.duration else nil
	move.cooldownUntil[to] = now + def.cooldown
	if landing then
		move.airJumps = 0
		move.lastWallPart = nil
		move.groundedAt = now
	elseif to == "DoubleJump" then
		move.airJumps += 1
	elseif wallHit then
		move.lastWallPart = wallHit.part
	elseif to == "VaultMid" then
		-- it ends standing on the ledge, so it counts as a landing
		move.airJumps = 0
		move.lastWallPart = nil
	end
	state.speed.windowCap = math.max(state.speed.windowCap, def.cap)
	char:SetAttribute("MoveState", to)
end

local function onDash(plr: Player, dir: unknown)
	if not RateLimit.check(plr, "Dash") then
		return
	end
	if typeof(dir) ~= "string" or #dir ~= 1 then
		return
	end
	local dashDir = DASH_DIRS[dir]
	if not dashDir then
		return
	end

	local char = plr.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local state = char and StateService.get(char)
	if not char or not hum or hum.Health <= 0 or not state then
		return
	end

	local now = workspace:GetServerTimeNow()
	local dash = state.dash
	if
		not StateService.canDash(char)
		or not MoveDefs[StateService.current(char)].dash
		or now < dash.dashCooldownUntil - Config.COOLDOWN_SLACK
	then
		deny(plr, "Dash")
		return
	end

	dash.dashUntil = now + if dashDir == "B" then BACK_DASH_TIME else Config.DASH_TIME
	dash.dodgeUntil = now + Config.DODGE_TIME
	dash.dashCooldownUntil = now + Config.DASH_COOLDOWN
	state.speed.windowCap = math.max(state.speed.windowCap, DASH_CAP)

	for _, other in Players:GetPlayers() do
		if other ~= plr then
			Remotes.DashFx:FireClient(other, char, dashDir)
		end
	end
end

local function sample(char: Model, root: BasePart, state: StateService.State, now: number)
	local speed = state.speed
	if Probes.ground(root) then
		state.move.groundedAt = now
	end

	local last = speed.samplePos
	if not last or now < speed.exemptUntil then
		speed.lastGoodCFrame = char:GetPivot()
	else
		local dt = now - speed.sampleAt
		local pos = root.Position
		local moved = Vector3.new(pos.X - last.X, 0, pos.Z - last.Z).Magnitude
		local allowed = speed.windowCap * Config.SPEED_TOLERANCE * dt + Config.SPEED_LAG_STUDS

		speed.bucket = math.max(0, speed.bucket - Config.SPEED_BUCKET_DRAIN * dt)
		if moved > allowed then
			speed.bucket += moved / allowed - 1
		else
			speed.lastGoodCFrame = char:GetPivot()
		end

		local good = speed.lastGoodCFrame
		if speed.bucket >= Config.SPEED_BUCKET_MAX and good then
			char:PivotTo(good)
			speed.bucket = 0
		end
	end

	-- the next window starts at whatever is recorded now
	local cap = MoveDefs[StateService.current(char)].cap
	speed.windowCap = if now < state.dash.dashUntil then math.max(cap, DASH_CAP) else cap
	speed.samplePos = root.Position
	speed.sampleAt = now
end

Players.PlayerAdded:Connect(onPlayer)
for _, plr in Players:GetPlayers() do
	onPlayer(plr)
end

Remotes.Move.OnServerEvent:Connect(onMove)
Remotes.Dash.OnServerEvent:Connect(onDash)

task.spawn(function()
	while true do
		task.wait(Config.SPEED_SAMPLE_INTERVAL)
		local now = workspace:GetServerTimeNow()
		for _, plr in Players:GetPlayers() do
			local char = plr.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local root = char and char.PrimaryPart
			local state = char and StateService.get(char)
			if char and hum and hum.Health > 0 and root and state then
				sample(char, root, state, now)
			end
		end
	end
end)

return MovementService
