--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local StateService = require(script.Parent.Parent.Services.StateService)

-- what the bot has seen of its target, each thing only once its reaction time has passed. it keeps the state before
-- the last change, so until the change is seen it still acts on the old one
export type Sight = {
	target: Model?,
	state: Types.CombatState,
	before: Types.CombatState,
	seenAt: number,
	swing: StateService.Swing?,
	swingSeenAt: number,
	-- when the swing's delay is seen, its animation visibly slowing down
	delaySeenAt: number?,
}

-- a reaction is never exactly the same twice
local JITTER = 0.2

local Sight = {}

local function late(reaction: number): number
	return reaction * (1 - JITTER + math.random() * JITTER * 2)
end

function Sight.new(): Sight
	return { state = "Idle", before = "Idle", seenAt = 0, swingSeenAt = 0 }
end

function Sight.update(sight: Sight, target: Model?, reaction: number, now: number)
	local st = if target then StateService.get(target) else nil
	if not target or not st then
		sight.target = nil
		sight.swing = nil
		return
	end
	local state: Types.CombatState = StateService.combatState(target)
	if target ~= sight.target then
		sight.target = target
		sight.state, sight.before, sight.seenAt = state, state, 0
		sight.swing = nil
	elseif state ~= sight.state then
		sight.before = sight.state
		sight.state = state
		sight.seenAt = now + late(reaction)
	end

	-- a swing is seen from when its animation starts, the server starts it on arrival like a player's screen would
	local swing = st.combat.swing
	if swing ~= sight.swing then
		sight.swing = swing
		sight.swingSeenAt = if swing then swing.startedAt + late(reaction) else 0
		sight.delaySeenAt = nil
	end
	local delayedAt = if swing then swing.delayedAt else nil
	if delayedAt and not sight.delaySeenAt then
		sight.delaySeenAt = delayedAt + late(reaction)
	end
end

function Sight.state(sight: Sight, now: number): Types.CombatState
	return if now >= sight.seenAt then sight.state else sight.before
end

-- the target's swing once the bot has noticed it
function Sight.swing(sight: Sight, now: number): StateService.Swing?
	return if sight.swing and now >= sight.swingSeenAt then sight.swing else nil
end

function Sight.isDelaySeen(sight: Sight, now: number): boolean
	local seenAt = sight.delaySeenAt
	return seenAt ~= nil and now >= seenAt
end

return Sight
