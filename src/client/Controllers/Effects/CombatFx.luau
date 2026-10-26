--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AttackDefs = require(ReplicatedStorage.Shared.Combat.AttackDefs)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local Types = require(ReplicatedStorage.Shared.Types)
local Sfx = require(script.Parent.Sfx)
local Vfx = require(script.Parent.Vfx)

-- streaming can leave either character off this client, so both can arrive as nil
type Play = (attacker: Model?, target: Model?, id: string, point: Vector3?, normal: Vector3?) -> ()

-- the hand end of an R6 arm, where the weapon sits
local HAND = CFrame.new(0, -1, 0)
local ARMS: { [Types.Hand]: { string } } = {
	Right = { "Right Arm" },
	Left = { "Left Arm" },
	Both = { "Right Arm", "Left Arm" },
}
-- a block's effect sits out in front of the blocker, on its guard
local GUARD_OUT = 1
local MIN_GAP = 1e-3
-- a swing effect's tilt about the root's forward axis. a slash lies level, a positive roll lifts its right side
local ANGLES: { [Types.SwingAngle]: CFrame } = {
	Horizontal = CFrame.identity,
	DiagonalRight = CFrame.Angles(0, 0, math.rad(45)),
	DiagonalLeft = CFrame.Angles(0, 0, math.rad(-45)),
	Vertical = CFrame.Angles(0, 0, math.rad(90)),
}
-- these spin a random way round the line of the hit every time, so a string of them doesn't stack into one
local SPINS: { [Types.HitType]: true } = { Slash = true }

-- typed so the old solver takes them as keys of the shared sounds
local BREAK: Types.SharedFx = "Break"
local DELAY: Types.SharedFx = "Delay"
local LEVEL: Types.SwingAngle = "Horizontal"

local player = Players.LocalPlayer

-- every effect CombatFx carries, one function per result, the way the reference keeps one per hit effect (R16.3).
-- a hit's effects come from the attacking weapon's hit type, blocks and parries included
local CombatFx = {}

local function rootOf(char: Model?): BasePart?
	local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

-- at `at`, its front toward the attacker
local function facing(at: Vector3, from: BasePart, to: BasePart): CFrame
	local gap = from.Position - to.Position
	local flat = Vector3.new(gap.X, 0, gap.Z)
	local look = if flat.Magnitude > MIN_GAP then flat.Unit else to.CFrame.LookVector
	return CFrame.lookAt(at, at + look)
end

local function strike(attacker: Model?, target: Model?, id: string, slot: Types.HitFx)
	local from, to = rootOf(attacker), rootOf(target)
	local def = AttackDefs[id]
	if not from or not to or not def then
		return
	end
	local cf = if slot == "Parry"
		then facing(from.Position:Lerp(to.Position, 0.5), from, to)
		else facing(to.Position, from, to)
	if slot == "Block" then
		cf += cf.LookVector * GUARD_OUT
	end
	if SPINS[def.hitType] then
		cf *= CFrame.Angles(0, 0, math.random() * math.pi * 2)
	end
	Vfx.at(Vfx.template(def.hitType, slot), cf)
	Sfx.at(Sounds.Hits[def.hitType][slot], cf.Position)
end

local function broken(attacker: Model?, target: Model?)
	local from, to = rootOf(attacker), rootOf(target)
	if from and to then
		local cf = facing(to.Position, from, to)
		Vfx.at(Vfx.template("Shared", BREAK), cf)
		Sfx.at(Sounds.Shared[BREAK], cf.Position)
	end
end

-- where the server's knockback path met the surface, up along its normal
local function pin(slot: Types.SharedFx, point: Vector3?, normal: Vector3?)
	if point and normal then
		Vfx.at(Vfx.template("Shared", slot), Vfx.surface(point, normal, Vector3.yAxis))
		Sfx.at(Sounds.Shared[slot], point)
	end
end

-- the warning a delay gives, on the hand the attack swings with. the attacker's own client plays it the moment it
-- predicts the delay, everyone else when the server says. the hand is for the fist and two handed weapons, a weapon
-- held in one hand moves it up its blade later, see the effects plan
function CombatFx.delay(char: Model, id: string)
	local def = AttackDefs[id]
	if not def then
		return
	end
	for _, name in ARMS[def.hand] do
		local arm = char:FindFirstChild(name)
		if arm and arm:IsA("BasePart") then
			Vfx.on(Vfx.template("Shared", DELAY), arm, HAND)
			Sfx.at(Sounds.Shared[DELAY], arm.Position)
		end
	end
end

-- the arc an attack cuts as it comes through, riding on the root so it goes along with the lunge. played the same two
-- ways the delay is, and whether it lands or not
function CombatFx.swing(char: Model, id: string)
	local def = AttackDefs[id]
	local swing = if def then def.swing else nil
	local root = rootOf(char)
	if swing and root then
		local at = (swing.at or CFrame.identity) * ANGLES[swing.angle or LEVEL]
		Vfx.on(Vfx.template("Swing", swing.fx), root, at, swing.spin)
	end
end

-- a dodge has nothing to show
local PLAYS: { [Types.CombatFx]: Play } = {
	Hit = function(attacker, target, id)
		strike(attacker, target, id, "Hit")
	end,
	Knocked = function(attacker, target, id)
		strike(attacker, target, id, "HeavyHit")
	end,
	Blocked = function(attacker, target, id)
		strike(attacker, target, id, "Block")
	end,
	Parried = function(attacker, target, id)
		strike(attacker, target, id, "Parry")
	end,
	Broken = broken,
	WallSlam = function(_, _, _, point, normal)
		pin("WallSlam", point, normal)
	end,
	FloorSlam = function(_, _, _, point, normal)
		pin("FloorSlam", point, normal)
	end,
	Delay = function(attacker, _, id)
		if attacker and attacker ~= player.Character then
			CombatFx.delay(attacker, id)
		end
	end,
	Swing = function(attacker, _, id)
		if attacker and attacker ~= player.Character then
			CombatFx.swing(attacker, id)
		end
	end,
}

function CombatFx.play(
	attacker: Model?,
	target: Model?,
	id: string,
	result: Types.CombatFx,
	point: Vector3?,
	normal: Vector3?
)
	local play = PLAYS[result]
	if play then
		play(attacker, target, id, point, normal)
	end
end

return CombatFx
