--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AttackDefs = require(ReplicatedStorage.Shared.AttackDefs)
local CombatDefs = require(ReplicatedStorage.Shared.CombatDefs)
local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local WeaponDefs = require(ReplicatedStorage.Shared.WeaponDefs)
local StateService = require(script.Parent.Services.StateService)

-- the server owns NPCs, so it plays their swings and reactions the way a player's client plays its own
type Npc = {
	animator: Animator,
	-- by animation id, loaded the first time each one plays
	tracks: { [string]: AnimationTrack },
	swinging: AnimationTrack?,
	-- the rate the swing plays at, its weapon's speed
	swingSpeed: number,
	looping: AnimationTrack?,
	oneShot: AnimationTrack?,
	-- which of a reaction's animations played last
	turns: { [Types.Reaction]: number },
	conn: RBXScriptConnection,
}

-- being hit cuts the swing short, the same states CombatController cancels its own on
local CUTS_SWING: { [Types.CombatState]: true } = { Stunned = true, PostureBroken = true, Downed = true }

local NpcAnimator = {}

local npcs: { [Model]: Npc } = {}
local animations: { [string]: Animation } = {}

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

local function track(npc: Npc, id: string): AnimationTrack?
	if id == "" then
		return nil
	end
	local loaded = npc.tracks[id] or npc.animator:LoadAnimation(animation(id))
	npc.tracks[id] = loaded
	return loaded
end

local function reactions(char: Model): { [Types.Reaction]: { string } }
	local st = StateService.get(char)
	return WeaponDefs[if st then st.combat.weapon else CombatDefs.defaultWeapon].reactions
end

local function stop(t: AnimationTrack?)
	if t then
		t:Stop(Config.ANIM_FADE)
	end
end

local function onState(char: Model)
	local npc = npcs[char]
	if not npc or not StateService.get(char) then
		return
	end
	local state: Types.CombatState = StateService.combatState(char)
	if CUTS_SWING[state] then
		stop(npc.swinging)
		npc.swinging = nil
	end

	-- Idle and Attacking have no slot at all
	local ids = reactions(char)[state]
	local loop = if ids then track(npc, ids[1] or "") else nil
	if loop == npc.looping then
		return
	end
	stop(npc.looping)
	npc.looping = loop
	if loop then
		loop:Play(Config.ANIM_FADE)
	end
end

-- after CharacterService.add. a rig made in Studio may have no Animator, a player's gets one from the engine
function NpcAnimator.add(char: Model, hum: Humanoid)
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = hum
	npcs[char] = {
		animator = animator,
		tracks = {},
		swingSpeed = 1,
		turns = {},
		conn = char:GetAttributeChangedSignal("CombatState"):Connect(function()
			onState(char)
		end),
	}
	onState(char)
end

function NpcAnimator.remove(char: Model)
	local npc = npcs[char]
	if npc then
		npc.conn:Disconnect()
		npcs[char] = nil
	end
end

-- a player's own client plays its swings and reactions, so anything not added here is skipped
function NpcAnimator.swing(char: Model, id: Types.AttackId)
	local npc = npcs[char]
	if not npc then
		return
	end
	local def = AttackDefs[id]
	stop(npc.oneShot)
	npc.oneShot = nil
	local t = track(npc, def.anim)
	npc.swinging = t
	npc.swingSpeed = def.speed
	if t then
		t:Play(Config.ANIM_FADE, 1, def.speed)
	end
end

-- a delayed windup runs at DELAY_SPEED, and the animation with it
function NpcAnimator.slow(char: Model, isSlowed: boolean)
	local npc = npcs[char]
	local t = if npc then npc.swinging else nil
	if npc and t then
		t:AdjustSpeed(npc.swingSpeed * (if isSlowed then Config.DELAY_SPEED else 1))
	end
end

-- a one shot over the loop, from the NPC's own weapon. a reaction with several animations takes turns
function NpcAnimator.react(char: Model, name: Types.Reaction)
	local npc = npcs[char]
	local ids = reactions(char)[name]
	if not npc or not ids or #ids == 0 then
		return
	end
	local turn = (npc.turns[name] or 0) % #ids + 1
	npc.turns[name] = turn
	local t = track(npc, ids[turn])
	if t then
		stop(npc.oneShot)
		npc.oneShot = t
		t:Play(Config.ANIM_FADE)
	end
end

function NpcAnimator.result(attacker: Model, target: Model, result: Types.HitResult)
	for _, char in { attacker, target } do
		local name: Types.Reaction? = CombatDefs.reaction(result, char == attacker)
		if name then
			NpcAnimator.react(char, name)
		end
	end
end

return NpcAnimator
