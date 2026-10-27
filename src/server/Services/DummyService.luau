--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AttackDefs = require(ReplicatedStorage.Shared.Combat.AttackDefs)
local Config = require(ReplicatedStorage.Shared.Config)
local Hitbox = require(script.Parent.Parent.Combat.Hitbox)
local Npc = require(script.Parent.Parent.Npc)
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

local function check(model: Model)
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

		local def = AttackDefs[swing.id]
		if hitAt > now and hitAt - now <= PARRY_LEAD and Hitbox.reaches(root, def.box, def.lunge or 0, model) then
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
	Npc.equip(model, st)
	local releaseAt = d.releaseAt
	if releaseAt and now >= releaseAt then
		d.releaseAt = nil
		CombatService.act(model, "Release")
	end
	-- turning a ragdoll to face someone would stand it back up, and a broken guard or a pinned body stays put
	if
		m == "Idle"
		or combat.downed
		or now < combat.brokenUntil
		or now < combat.wallUntil
		or now < combat.floorUntil
	then
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
	local parts = Npc.add(inst, "dummy", Config.DUMMY_RESPAWN, { "Mode" })
	if not parts then
		return
	end
	local model = parts.model
	check(model)
	model:GetAttributeChangedSignal("Mode"):Connect(function()
		check(model)
	end)

	dummies[model] = {
		root = parts.root,
		hum = parts.hum,
		-- staggered, so a row of attack dummies doesn't swing in step
		nextAttackAt = workspace:GetServerTimeNow() + math.random() * Config.DUMMY_INTERVAL,
		isDelayNext = false,
	}
end

local function remove(inst: Instance)
	if inst:IsA("Model") and dummies[inst] then
		dummies[inst] = nil
		Npc.remove(inst)
	end
end

CollectionService:GetInstanceAddedSignal(Config.DUMMY_TAG):Connect(add)
CollectionService:GetInstanceRemovedSignal(Config.DUMMY_TAG):Connect(remove)
for _, inst in CollectionService:GetTagged(Config.DUMMY_TAG) do
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
