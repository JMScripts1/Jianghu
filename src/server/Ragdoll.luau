--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Probes = require(ReplicatedStorage.Shared.Probes)

type Joint = {
	motor: string,
	limb: string,
	-- where the socket sits on the torso and on the limb
	torso: CFrame,
	at: CFrame,
	-- degrees the limb can swing off its rest
	limit: number,
}

type Rig = { motors: { Motor6D }, sockets: { BallSocketConstraint }, colliders: { BasePart } }

local GROUP = "Ragdoll"
local CHAR_GROUP = "Characters"
local PROBE_GROUP = "MoveProbe"
-- a little under the limb, so it never catches on the torso it hangs from
local COLLIDER_SCALE = 0.6
local HIP = 40
local SHOULDER = 110

-- the four limbs swing free, the neck and the root stay rigid. sockets and limits are the reference's tested R6 ones
local JOINTS: { Joint } = {
	{
		motor = "Left Hip",
		limb = "Left Leg",
		torso = CFrame.new(-0.5, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
		at = CFrame.new(0, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
		limit = HIP,
	},
	{
		motor = "Right Hip",
		limb = "Right Leg",
		torso = CFrame.new(0.5, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
		at = CFrame.new(0, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
		limit = HIP,
	},
	{
		motor = "Left Shoulder",
		limb = "Left Arm",
		torso = CFrame.new(-1.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
		at = CFrame.new(0, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
		limit = SHOULDER,
	},
	{
		motor = "Right Shoulder",
		limb = "Right Arm",
		torso = CFrame.new(1.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
		at = CFrame.new(0, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
		limit = SHOULDER,
	},
}

local Ragdoll = {}

local rigs: { [Model]: Rig } = {}

-- back on its feet where it lay, facing the way it faced or, flat on its back or front, the way its head pointed
local function stand(char: Model, root: BasePart)
	local cf = root.CFrame
	local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	local facing = if look.Magnitude > 0.5 then look.Unit else Vector3.new(cf.UpVector.X, 0, cf.UpVector.Z).Unit
	local floor = Probes.ground(root, Config.ROOT_HEIGHT * 2)
	local at = if floor then Vector3.new(cf.X, floor.Position.Y + Config.ROOT_HEIGHT, cf.Z) else cf.Position
	char:PivotTo(CFrame.lookAt(at, at + facing))
end

-- the sockets and colliders are made once on spawn and sit switched off until the character goes down
function Ragdoll.add(char: Model)
	local torso = char:FindFirstChild("Torso") :: BasePart
	local rig: Rig = { motors = {}, sockets = {}, colliders = {} }
	for _, joint in JOINTS do
		local limb = char:FindFirstChild(joint.limb) :: BasePart
		table.insert(rig.motors, torso:FindFirstChild(joint.motor) :: Motor6D)

		local a0 = Instance.new("Attachment")
		a0.CFrame = joint.torso
		a0.Parent = torso
		local a1 = Instance.new("Attachment")
		a1.CFrame = joint.at
		a1.Parent = limb

		local socket = Instance.new("BallSocketConstraint")
		socket.Attachment0 = a0
		socket.Attachment1 = a1
		socket.LimitsEnabled = true
		socket.UpperAngle = joint.limit
		socket.Enabled = false
		socket.Parent = torso
		table.insert(rig.sockets, socket)

		-- the Humanoid keeps R6 limbs from colliding, so each gets a stand in that does
		local collider = Instance.new("Part")
		collider.Name = "RagdollCollider"
		collider.Size = limb.Size * COLLIDER_SCALE
		collider.Transparency = 1
		collider.Massless = true
		collider.CanCollide = false
		collider.CanQuery = false
		collider.CanTouch = false
		collider.CastShadow = false
		local weld = Instance.new("Weld")
		weld.Part0 = limb
		weld.Part1 = collider
		weld.Parent = collider
		collider.Parent = limb
		table.insert(rig.colliders, collider)
	end
	rigs[char] = rig
end

function Ragdoll.remove(char: Model)
	rigs[char] = nil
end

-- a player's own client owns its physics, so it changes its own Humanoid state from CombatState, see
-- CombatController. the server does that itself for NPCs
function Ragdoll.set(char: Model, isOn: boolean)
	local rig = rigs[char]
	local root = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not rig or not root or not root:IsA("BasePart") or not hum then
		return
	end

	for _, motor in rig.motors do
		motor.Enabled = not isOn
	end
	for _, socket in rig.sockets do
		socket.Enabled = isOn
	end
	for _, collider in rig.colliders do
		collider.CanCollide = isOn
		collider.CollisionGroup = if isOn then GROUP else CHAR_GROUP
	end
	if not isOn then
		stand(char, root)
	end

	if Players:GetPlayerFromCharacter(char) then
		return
	end
	hum.AutoRotate = not isOn
	hum:ChangeState(if isOn then Enum.HumanoidStateType.Physics else Enum.HumanoidStateType.Running)
	if isOn then
		root:ApplyAngularImpulse(root.CFrame.RightVector * Config.RAGDOLL_TIP)
	end
end

-- the limbs land on the map, but never on their own torso, each other or other characters
for _, name in { GROUP, CHAR_GROUP, PROBE_GROUP } do
	if not PhysicsService:IsCollisionGroupRegistered(name) then
		PhysicsService:RegisterCollisionGroup(name)
	end
end
for _, other in { GROUP, CHAR_GROUP, PROBE_GROUP } do
	PhysicsService:CollisionGroupSetCollidable(GROUP, other, false)
end

return Ragdoll
