--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MoveDefs = require(ReplicatedStorage.Shared.Movement.MoveDefs)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Types = require(ReplicatedStorage.Shared.Types)
local Fov = require(script.Parent.Effects.Fov)
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
			Sfx.state(root, last, state)
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
	Sfx.state(c.root, c.prev, c.state)
end

RunService.PreRender:Connect(Sfx.step)

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(plr: Player)
	if plr.Character then
		unwatch(plr.Character)
	end
end)
for _, plr in Players:GetPlayers() do
	onPlayerAdded(plr)
end

return EffectController
