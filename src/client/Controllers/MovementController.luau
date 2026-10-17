--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local MoveDefs = require(ReplicatedStorage.Shared.MoveDefs)
local Probes = require(ReplicatedStorage.Shared.Probes)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local Context = require(script.Parent.Movement.Context)
local Dash = require(script.Parent.Movement.Dash)
local Air = require(script.Parent.Movement.States.Air)
local Ground = require(script.Parent.Movement.States.Ground)
local Slide = require(script.Parent.Movement.States.Slide)
local Vault = require(script.Parent.Movement.States.Vault)
local WallCling = require(script.Parent.Movement.States.WallCling)
local WallRun = require(script.Parent.Movement.States.WallRun)

export type Action = "Sprint" | "Crouch" | "Jump" | "Dash"

local MODULES: { [Types.MoveState]: Context.StateModule } = {
	Idle = Ground,
	Walk = Ground,
	Run = Ground,
	CrouchIdle = Ground,
	CrouchWalk = Ground,
	Slide = Slide,
	VaultLow = Vault,
	Jump = Air,
	DoubleJump = Air,
	SlideJump = Air,
	Fall = Air,
	WallRun = WallRun,
	WallLeap = WallRun,
	WallCling = WallCling,
	WallBoost = WallCling,
	VaultMid = Vault,
}

local MovementController = {}

local plr = Players.LocalPlayer
local input: Context.Input = { sprint = false, crouch = false }
local active: Context.Context? = nil
-- the server spawns everyone in Idle, which rides on Walk
local lastSent: Types.MoveState = "Walk"

-- switches without checking the transition table, MoveDeny uses it to snap back
local function switch(ctx: Context.Context, to: Types.MoveState)
	local from: Types.MoveState = ctx.state
	local def = MoveDefs[to]
	local now = os.clock()

	MODULES[from].exit(ctx)
	if ctx.dashUntil > 0 and not def.dash then
		Dash.stop(ctx)
	end

	if from == "WallRun" or from == "WallCling" then
		ctx.leftWallAt = now
	end
	if def.group == "Grounded" and MoveDefs[from].group ~= "Grounded" then
		ctx.airJumps = 0
		ctx.lastWallPart = nil
		ctx.landedAt = now
	elseif to == "DoubleJump" then
		ctx.airJumps += 1
	elseif to == "VaultMid" then
		-- it ends standing on the ledge, so it counts as a landing
		ctx.airJumps = 0
		ctx.lastWallPart = nil
	end

	ctx.prev = from
	ctx.state = to
	ctx.since = now
	ctx.endsAt = if def.duration then now + def.duration else nil
	ctx.cooldownUntil[to] = now + def.cooldown
	MODULES[to].enter(ctx)

	if Config.DEBUG then
		print("move", from, to)
	end
	if def.wire ~= lastSent then
		lastSent = def.wire
		Remotes.Move:FireServer(def.wire)
	end
end

local function request(ctx: Context.Context, to: Types.MoveState)
	if MoveDefs[ctx.state].to[to] and Context.ready(ctx, to) then
		switch(ctx, to)
	end
end

local function step(ctx: Context.Context, dt: number)
	ctx.momentum = math.min(ctx.momentum, Config.MOMENTUM_MAX)

	local nextState: Types.MoveState? = MODULES[ctx.state].update(ctx, dt)
	if not nextState and ctx.endsAt and os.clock() >= ctx.endsAt then
		nextState = MoveDefs[ctx.state].after
	end
	if nextState then
		request(ctx, nextState)
	end

	if ctx.dashUntil > 0 then
		Dash.update(ctx)
	end
end

local function onJump(ctx: Context.Context)
	local state: Types.MoveState = ctx.state
	local group = MoveDefs[state].group

	if group == "Grounded" then
		request(ctx, if state == "Slide" then "SlideJump" else "Jump")
	elseif state == "WallRun" then
		request(ctx, "WallLeap")
	elseif state == "WallCling" or state == "WallBoost" then
		local hit = Probes.vaultMid(ctx.root)
		if hit then
			ctx.vaultHit = hit
			request(ctx, "VaultMid")
		elseif state == "WallCling" then
			request(ctx, "WallBoost")
		end
	elseif group == "Airborne" or state == "WallLeap" then
		-- a wall wins over the double jump
		local hit = Probes.wall(ctx.root, ctx.momentum)
		if hit and hit.part ~= ctx.lastWallPart and os.clock() - ctx.leftWallAt >= Config.WALL_REGRAB then
			ctx.wallHit = hit
			request(ctx, if hit.kind == "Run" then "WallRun" else "WallCling")
		elseif ctx.airJumps < Config.MAX_AIR_JUMPS then
			request(ctx, "DoubleJump")
		end
	end
end

local function onCrouch(ctx: Context.Context)
	local state: Types.MoveState = ctx.state
	local moving = ctx.hum.MoveDirection.Magnitude > 0

	if state == "Run" then
		if ctx.momentum >= Config.SLIDE_MIN_SPEED then
			request(ctx, "Slide")
		end
	elseif state == "Slide" then
		request(ctx, if input.sprint then "Run" else "CrouchWalk")
	elseif state == "Idle" or state == "Walk" then
		request(ctx, if moving then "CrouchWalk" else "CrouchIdle")
	elseif state == "CrouchIdle" or state == "CrouchWalk" then
		request(ctx, if moving then "Walk" else "Idle")
	end
end

local function onDash(ctx: Context.Context)
	local now = os.clock()
	if not MoveDefs[ctx.state].dash or ctx.dashUntil > 0 or now < ctx.dashReadyAt then
		return
	end

	local dir: Types.DashDir = Dash.direction(ctx)
	Dash.start(ctx, dir)
	ctx.dashReadyAt = now + Config.DASH_COOLDOWN
	Remotes.Dash:FireServer(dir)
end

function MovementController.action(action: Action, down: boolean)
	if action == "Sprint" then
		input.sprint = down
		return
	elseif action == "Crouch" then
		input.crouch = down
	end

	local ctx = active
	if not down or not ctx then
		return
	end

	if action == "Crouch" then
		onCrouch(ctx)
	elseif action == "Jump" then
		onJump(ctx)
	else
		onDash(ctx)
	end
end

local function onCharacter(char: Model)
	local ctx = Context.new(char, input)
	active = ctx
	lastSent = "Walk"
	MODULES[ctx.state].enter(ctx)

	ctx.trove:Connect(RunService.PreSimulation, function(dt: number)
		step(ctx, dt)
	end)
	ctx.trove:Connect(ctx.hum.Died, function()
		ctx.trove:Destroy()
		if active == ctx then
			active = nil
		end
	end)
end

Remotes.MoveDeny.OnClientEvent:Connect(function(denied: string)
	local ctx = active
	if not ctx then
		return
	end
	if Config.DEBUG then
		print("denied", denied)
	end

	if denied == "Dash" then
		if ctx.dashUntil > 0 then
			Dash.stop(ctx)
		end
		return
	elseif MoveDefs[ctx.state].wire ~= denied then
		return
	end

	local moving = ctx.hum.MoveDirection.Magnitude > 0
	local fallback: Types.MoveState = if not Probes.ground(ctx.root) then "Fall" elseif moving then "Walk" else "Idle"
	if fallback ~= ctx.state then
		switch(ctx, fallback)
	end
end)

plr.CharacterAdded:Connect(onCharacter)
plr.CharacterRemoving:Connect(function(char: Model)
	local ctx = active
	if ctx and ctx.char == char then
		ctx.trove:Destroy()
		active = nil
	end
end)
if plr.Character then
	onCharacter(plr.Character)
end

return MovementController
