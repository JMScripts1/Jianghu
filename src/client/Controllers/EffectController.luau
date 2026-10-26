--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local MoveDefs = require(ReplicatedStorage.Shared.Movement.MoveDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Types = require(ReplicatedStorage.Shared.Types)
local CombatFx = require(script.Parent.Effects.CombatFx)
local Fov = require(script.Parent.Effects.Fov)
local MoveFx = require(script.Parent.Effects.MoveFx)
local Sfx = require(script.Parent.Effects.Sfx)
local Context = require(script.Parent.Movement.Context)

type Ctx = Context.Ctx
-- the old solver can't match Trove's generic methods against the exported Trove type
type Trove = typeof(Trove.new())

-- turns the attribute back into a state, anything else is ignored
local BY_NAME: { [string]: Types.MoveState } = {}
for state: Types.MoveState in MoveDefs do
	BY_NAME[state] = state
end

local player = Players.LocalPlayer

-- which characters get effects and when their state changes. the local one plays straight from the state machine,
-- everyone else from the MoveState attribute a round trip later. what plays is in Effects
local EffectController = {}

-- everyone but the local character, each cleaned up when its character goes
local watched: { [Model]: Trove } = {}

local function stateOf(char: Model): Types.MoveState?
	local value = char:GetAttribute("MoveState")
	return if typeof(value) == "string" then BY_NAME[value] else nil
end

-- a ground dash is airborne on paper and a mantle ends standing, neither is a landing you'd hear or see
local function isLanding(from: Types.MoveState, to: Types.MoveState): boolean
	local def = MoveDefs[from]
	return MoveDefs[to].group == "Grounded" and def.group ~= "Grounded" and not def.isDash and from ~= "Mantle"
end

local function play(root: BasePart, from: Types.MoveState, to: Types.MoveState)
	local landed = isLanding(from, to)
	Sfx.state(root, from, to, landed)
	MoveFx.state(root, from, to, landed)
end

local function unwatch(char: Model)
	local trove = watched[char]
	if trove then
		watched[char] = nil
		trove:Clean()
	end
end

local function watch(char: Model)
	unwatch(char)
	local trove = Trove.new()
	watched[char] = trove
	local root = char:WaitForChild("HumanoidRootPart") :: BasePart
	-- gone again while its root was on the way
	if watched[char] ~= trove then
		return
	end

	local last: Types.MoveState = stateOf(char) or "Walk"
	trove:Connect(char:GetAttributeChangedSignal("MoveState"), function()
		local state: Types.MoveState? = stateOf(char)
		if state then
			play(root, last, state)
			last = state
		end
	end)
	Sfx.add(char, root, function()
		return stateOf(char)
	end)
	trove:Add(function()
		Sfx.remove(char)
	end)
	trove:Connect(char.Destroying, function()
		unwatch(char)
	end)
end

local function onPlayerAdded(plr: Player)
	if plr == player then
		return
	end
	plr.CharacterAdded:Connect(watch)
	plr.CharacterRemoving:Connect(unwatch)
	if plr.Character then
		task.spawn(watch, plr.Character)
	end
end

local function onBot(inst: Instance)
	if inst:IsA("Model") then
		watch(inst)
	end
end

function EffectController.load(c: Ctx)
	Fov.load(c)
	Sfx.add(c.char, c.root, function()
		return c.state
	end)
	c.trove:Add(function()
		Sfx.remove(c.char)
	end)
end

function EffectController.play(c: Ctx)
	play(c.root, c.prev, c.state)
end

RunService.PreRender:Connect(Sfx.step)
Remotes.CombatFx.OnClientEvent:Connect(CombatFx.play)

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(plr: Player)
	if plr.Character then
		unwatch(plr.Character)
	end
end)
for _, plr in Players:GetPlayers() do
	onPlayerAdded(plr)
end

-- bots move on the server and publish MoveState the same way a player's client does
CollectionService:GetInstanceAddedSignal(Config.BOT_TAG):Connect(onBot)
CollectionService:GetInstanceRemovedSignal(Config.BOT_TAG):Connect(function(inst: Instance)
	if inst:IsA("Model") then
		unwatch(inst)
	end
end)
for _, inst in CollectionService:GetTagged(Config.BOT_TAG) do
	task.spawn(onBot, inst)
end

return EffectController
