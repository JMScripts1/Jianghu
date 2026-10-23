--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AttackDefs = require(ReplicatedStorage.Shared.AttackDefs)
local Config = require(ReplicatedStorage.Shared.Config)
local Hitbox = require(script.Parent.Parent.Hitbox)
local NpcAnimator = require(script.Parent.Parent.NpcAnimator)
local CharacterService = require(script.Parent.CharacterService)
local CombatService = require(script.Parent.CombatService)
local StateService = require(script.Parent.StateService)

type Mode = "Idle" | "Block" | "Parry" | "Attack" | "Delay" | "Heavy"

type Dummy = {
	root: BasePart,
	hum: Humanoid,
	nextAttackAt: number,
	-- one press per swing, so a parry dummy never presses twice for the same hit
	parried: StateService.Swing?,
	-- Delay mode holds every other swing and lets go here
	releaseAt: number?,
	isDelayNext: boolean,
}

local TAG = "Dummy"
local TICK = 1 / 20
-- pressed this far ahead, the hit lands in the middle of the parry window
local PARRY_LEAD = Config.PARRY_WINDOW / 2

local MODES: { [string]: Mode } = {
	Idle = "Idle",
	Block = "Block",
	Parry = "Parry",
	Attack = "Attack",
	Delay = "Delay",
	Heavy = "Heavy",
}

local DummyService = {}

local dummies: { [Model]: Dummy } = {}

-- read every tick, so the mode can be changed in Studio while it runs
local function mode(model: Model): Mode
	local value = model:GetAttribute("Mode")
	return if typeof(value) == "string" and MODES[value] then MODES[value] else "Idle"
end

local function checkMode(model: Model)
	local value = model:GetAttribute("Mode")
	if value ~= nil and not (typeof(value) == "string" and MODES[value]) then
		warn("no dummy mode called", value, model:GetFullName())
	end
end

local function nearestPlayer(root: BasePart): BasePart?
	local best: BasePart? = nil
	local bestDist = Config.DUMMY_RANGE
	for _, plr in Players:GetPlayers() do
		local other = if plr.Character then StateService.liveRoot(plr.Character) else nil
		local dist = if other then (other.Position - root.Position).Magnitude else math.huge
		if other and dist < bestDist then
			best = other
			bestDist = dist
		end
	end
	return best
end

-- block and parry only work from the front, so a guarding dummy keeps turning to whoever is closest
local function face(root: BasePart, target: BasePart)
	local pos = root.Position
	local at = Vector3.new(target.Position.X, pos.Y, target.Position.Z)
	if (at - pos).Magnitude > 0.1 then
		root.CFrame = CFrame.lookAt(pos, at)
	end
end

local function isAimedAt(model: Model, attacker: BasePart, swing: StateService.Swing): boolean
	return table.find(Hitbox.query(attacker, AttackDefs[swing.id].box), model) ~= nil
end

-- every swing about to land on this dummy, from players and the other dummies. a press for a swing aimed at
-- someone else would only put the parry on cooldown
local function parry(model: Model, d: Dummy, st: StateService.CharState, now: number)
	local attackers: { Model } = {}
	for _, plr in Players:GetPlayers() do
		if plr.Character then
			table.insert(attackers, plr.Character)
		end
	end
	for other in dummies do
		if other ~= model then
			table.insert(attackers, other)
		end
	end

	for _, char in attackers do
		local attackerSt = StateService.get(char)
		local root = StateService.liveRoot(char)
		local swing = if attackerSt then attackerSt.combat.swing else nil
		-- on rhythm, from when the hit would land undelayed, the way a player reads a windup, so a delay beats it
		local hitAt = if swing then swing.startedAt + AttackDefs[swing.id].windup else nil
		if not swing or not hitAt or not root or swing == d.parried then
			continue
		elseif (root.Position - d.root.Position).Magnitude > Config.DUMMY_RANGE then
			continue
		end

		if hitAt > now and hitAt - now <= PARRY_LEAD and isAimedAt(model, root, swing) then
			d.parried = swing
			-- a tap: letting go doesn't cut the window short
			CombatService.act(model, "Block")
			CombatService.act(model, "Unblock")
			if Config.DEBUG then
				print("dummy parry", model.Name, now < st.combat.parryUntil, hitAt - now)
			end
			return
		end
	end
end

local function step(model: Model, d: Dummy, now: number)
	local st = StateService.get(model)
	if not st then
		return
	end
	local combat = st.combat
	local m = mode(model)

	-- full again whenever it isn't stunned or down, so a string's damage shows and then resets
	if now >= combat.stunnedUntil and not combat.downed then
		d.hum.Health = d.hum.MaxHealth
	end
	if m ~= "Block" and combat.isBlockHeld then
		CombatService.act(model, "Unblock")
	end
	local releaseAt = d.releaseAt
	if releaseAt and now >= releaseAt then
		d.releaseAt = nil
		CombatService.act(model, "Release")
	end
	-- turning a ragdoll to face someone would stand it back up
	if m == "Idle" or combat.downed then
		return
	end

	local target = nearestPlayer(d.root)
	if target then
		face(d.root, target)
	end

	if m == "Block" then
		if not combat.isBlockHeld then
			CombatService.act(model, "Block")
		end
	elseif m == "Parry" then
		parry(model, d, st, now)
	elseif target and now >= d.nextAttackAt then
		d.nextAttackAt = now + Config.DUMMY_INTERVAL
		local isStarted = CombatService.act(model, if m == "Heavy" then "Heavy" else "Light")
		local swing = combat.swing
		-- every other swing in Delay mode holds through its delay point for a random time, the rest let go at once
		if isStarted and swing and m == "Delay" and d.isDelayNext then
			d.releaseAt = now + (AttackDefs[swing.id].delayAt or 0) + math.random() * Config.DELAY_MAX
		else
			CombatService.act(model, "Release")
		end
		d.isDelayNext = m == "Delay" and not d.isDelayNext
	end
end

local function add(inst: Instance)
	if not inst:IsA("Model") or not inst:IsDescendantOf(workspace) then
		return
	end
	local hum = inst:FindFirstChildOfClass("Humanoid")
	local root = StateService.liveRoot(inst)
	if not hum or not root then
		warn("dummy needs a living Humanoid and a HumanoidRootPart", inst:GetFullName())
		return
	end

	-- owned by the server, or a player standing next to it could take it over and fling it
	if root:CanSetNetworkOwnership() then
		root:SetNetworkOwner(nil)
	end

	CharacterService.add(inst)
	NpcAnimator.add(inst, hum)
	checkMode(inst)
	inst:GetAttributeChangedSignal("Mode"):Connect(function()
		checkMode(inst)
	end)

	dummies[inst] = {
		root = root,
		hum = hum,
		-- staggered, so a row of attack dummies doesn't swing in step
		nextAttackAt = workspace:GetServerTimeNow() + math.random() * Config.DUMMY_INTERVAL,
		isDelayNext = false,
	}
end

local function remove(inst: Instance)
	if inst:IsA("Model") and dummies[inst] then
		dummies[inst] = nil
		NpcAnimator.remove(inst)
		CharacterService.remove(inst)
	end
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(add)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(remove)
for _, inst in CollectionService:GetTagged(TAG) do
	add(inst)
end

task.spawn(function()
	while true do
		task.wait(TICK)
		local now = workspace:GetServerTimeNow()
		for model, d in dummies do
			step(model, d, now)
		end
	end
end)

return DummyService
