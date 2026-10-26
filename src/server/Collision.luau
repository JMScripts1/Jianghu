--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")

-- MoveProbe is the group the movement and hitbox raycasts use, so they only ever see the map
export type Group = "Players" | "Npcs" | "Ragdoll" | "MoveProbe"

-- every collision group and who passes through whom, in one place, like the reference's CollisionManager. any pair
-- not listed collides. players pass through each other, NPCs still block players and each other, and ragdoll limbs
-- land on the map and nothing else
local APART: { { Group } } = {
	{ "Players", "Players" },
	{ "MoveProbe", "Players" },
	{ "MoveProbe", "Npcs" },
	{ "Ragdoll", "Players" },
	{ "Ragdoll", "Npcs" },
	{ "Ragdoll", "Ragdoll" },
	{ "Ragdoll", "MoveProbe" },
}

local Collision = {}

function Collision.groupOf(char: Model): Group
	return if Players:GetPlayerFromCharacter(char) then "Players" else "Npcs"
end

-- every part it has now and every one it gets later, accessories and tools arrive after spawn
function Collision.add(char: Model)
	local group = Collision.groupOf(char)
	local function set(part: Instance)
		if part:IsA("BasePart") then
			part.CollisionGroup = group
		end
	end
	for _, part in char:GetDescendants() do
		set(part)
	end
	char.DescendantAdded:Connect(set)
end

-- the place file may already have some from the collision group editor
for _, pair in APART do
	for _, name in pair do
		if not PhysicsService:IsCollisionGroupRegistered(name) then
			PhysicsService:RegisterCollisionGroup(name)
		end
	end
	PhysicsService:CollisionGroupSetCollidable(pair[1], pair[2], false)
end

return Collision
