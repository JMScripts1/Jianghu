--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local WeaponDefs = require(ReplicatedStorage.Shared.Combat.WeaponDefs)
local StateService = require(script.Parent.Parent.Services.StateService)
local Ragdoll = require(script.Parent.Ragdoll)

type CharState = StateService.CharState

local Grip = {}

local animations: { [string]: Animation } = {}
-- by character, then animation id, so each half loads once per character
local tracks: { [Model]: { [string]: AnimationTrack } } = {}

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

-- the server plays both halves on the same frame, so the two bodies stay together on every client
local function play(char: Model, id: string): AnimationTrack?
	local hum = char:FindFirstChildOfClass("Humanoid")
	local animator = if hum then hum:FindFirstChildOfClass("Animator") else nil
	if id == "" or not animator then
		return nil
	end
	local loaded = tracks[char] or {}
	tracks[char] = loaded
	local t = loaded[id] or animator:LoadAnimation(animation(id))
	loaded[id] = t
	t:Play(Config.ANIM_FADE)
	return t
end

-- the nearest downed body in reach that nobody else holds, by the server's own positions
local function findDowned(char: Model, root: BasePart, candidates: { [Model]: true }): Model?
	local best: Model? = nil
	local bestDist = Config.GRIP_RANGE
	for other in candidates do
		local st = StateService.get(other)
		local otherRoot = StateService.liveRoot(other)
		if other == char or not st or not otherRoot or not st.combat.downed or st.combat.grippedBy then
			continue
		end
		local dist = (otherRoot.Position - root.Position).Magnitude
		if dist <= bestDist then
			best = other
			bestDist = dist
		end
	end
	return best
end

local function unanchor(char: Model)
	local root = char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.Anchored = false
	end
end

-- both bodies are anchored, and the victim comes out of its ragdoll held at the grip's offset from the gripper
function Grip.start(char: Model, st: CharState, now: number, candidates: { [Model]: true }): boolean
	local def = WeaponDefs[st.combat.weapon].grip
	local root = StateService.liveRoot(char)
	local victim = if root then findDowned(char, root, candidates) else nil
	local vst = if victim then StateService.get(victim) else nil
	local vroot = if victim then StateService.liveRoot(victim) else nil
	if not def or not root or not victim or not vst or not vroot then
		return false
	end

	-- turned to face the body, so the grip plays at it and not where the gripper was looking. the server sees turns
	-- late, so this is set here for everyone instead of trusting the gripper's own facing
	local to = vroot.Position - root.Position
	local flat = Vector3.new(to.X, 0, to.Z)
	local facing = if flat.Magnitude > 1e-3 then CFrame.lookAt(root.Position, root.Position + flat) else root.CFrame
	Ragdoll.set(victim, false)
	root.Anchored = true
	vroot.Anchored = true
	char:PivotTo(facing)
	victim:PivotTo(facing * def.offset)
	StateService.exempt(victim, def.killAt)

	local halves: { AnimationTrack } = {}
	local mine = play(char, def.anim)
	local theirs = play(victim, def.victim)
	if mine then
		table.insert(halves, mine)
	end
	if theirs then
		table.insert(halves, theirs)
	end
	st.combat.grip = { victim = victim, endsAt = now + def.killAt, tracks = halves }
	vst.combat.grippedBy = char
	StateService.publish(victim)
	return true
end

-- finished, the victim dies and stays a ragdoll instead of falling apart. cut short, it lies back down where it is
function Grip.release(char: Model, st: CharState, isFinished: boolean)
	local run = st.combat.grip
	if not run then
		return
	end
	st.combat.grip = nil
	for _, t in run.tracks do
		t:Stop(Config.ANIM_FADE)
	end
	unanchor(char)

	local victim = run.victim
	local vst = StateService.get(victim)
	unanchor(victim)
	if vst then
		vst.combat.grippedBy = nil
		Ragdoll.set(victim, true)
		local hum = victim:FindFirstChildOfClass("Humanoid")
		if isFinished and hum then
			hum.Health = 0
		end
		StateService.publish(victim)
	end
	StateService.publish(char)
end

-- a hit on the gripper lets go in CombatService's resolve, so here it's only the kill landing, or the victim leaving
-- or dying some other way
function Grip.step(char: Model, st: CharState, now: number)
	local run = st.combat.grip
	if not run then
		return
	elseif not StateService.get(run.victim) or not StateService.liveRoot(run.victim) then
		Grip.release(char, st, false)
	elseif now >= run.endsAt then
		Grip.release(char, st, true)
	end
end

-- a gripper leaving lets its victim go. a victim leaving is caught by the gripper's step
function Grip.remove(char: Model)
	local st = StateService.get(char)
	if st then
		Grip.release(char, st, false)
	end
	tracks[char] = nil
end

return Grip
