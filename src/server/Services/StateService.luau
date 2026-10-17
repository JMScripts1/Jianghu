--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MoveDefs = require(ReplicatedStorage.Shared.MoveDefs)
local Types = require(ReplicatedStorage.Shared.Types)

export type State = {
	move: {
		state: Types.MoveState,
		since: number,
		endsAt: number?,
		airJumps: number,
		groundedAt: number,
		lastWallPart: BasePart?,
		cooldownUntil: { [Types.MoveState]: number },
	},
	dash: {
		dashUntil: number,
		dodgeUntil: number,
		dashCooldownUntil: number,
	},
	speed: {
		windowCap: number,
		lastGoodCFrame: CFrame?,
		bucket: number,
		exemptUntil: number,
		samplePos: Vector3?,
		sampleAt: number,
	},
	combat: {
		stunnedUntil: number,
		parryUntil: number,
		downed: boolean,
	},
	stamina: {
		value: number,
		stamp: number,
	},
}

local StateService = {}

local SPAWN_STATE: Types.MoveState = "Idle"

local states: { [Model]: State } = {}

local function add(char: Model)
	local now = workspace:GetServerTimeNow()
	states[char] = {
		move = { state = SPAWN_STATE, since = now, airJumps = 0, groundedAt = now, cooldownUntil = {} },
		dash = { dashUntil = 0, dodgeUntil = 0, dashCooldownUntil = 0 },
		speed = {
			windowCap = MoveDefs[SPAWN_STATE].cap,
			bucket = 0,
			exemptUntil = now + Config.SPAWN_EXEMPT,
			sampleAt = now,
		},
		combat = { stunnedUntil = 0, parryUntil = 0, downed = false },
		stamina = { value = Config.STAMINA_MAX, stamp = now },
	}
end

function StateService.get(char: Model): State?
	return states[char]
end

-- MoveDefs makes sure an after state is never timed, so one step resolves it
function StateService.current(char: Model): Types.MoveState
	local move = states[char].move
	local endsAt = move.endsAt
	local after: Types.MoveState? = MoveDefs[move.state].after
	if endsAt and after and workspace:GetServerTimeNow() >= endsAt then
		move.state = after
		move.since = endsAt
		move.endsAt = nil
	end
	return move.state
end

function StateService.canMove(char: Model): boolean
	local combat = states[char].combat
	return not combat.downed and workspace:GetServerTimeNow() >= combat.stunnedUntil
end

-- TODO: attacking and blocking once combat adds them
function StateService.canDash(char: Model): boolean
	return StateService.canMove(char) and workspace:GetServerTimeNow() >= states[char].combat.parryUntil
end

function StateService.exempt(char: Model, seconds: number)
	local speed = states[char].speed
	speed.exemptUntil = math.max(speed.exemptUntil, workspace:GetServerTimeNow() + seconds)
end

-- CharacterRemoving also fires when the player leaves
local function onPlayer(plr: Player)
	plr.CharacterAdded:Connect(add)
	plr.CharacterRemoving:Connect(function(char)
		states[char] = nil
	end)
	if plr.Character then
		add(plr.Character)
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, plr in Players:GetPlayers() do
	onPlayer(plr)
end

return StateService
