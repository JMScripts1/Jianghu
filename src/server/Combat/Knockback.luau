--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

type Flight = {
	velocity: Vector3,
	-- where the server's own copy of the path had got to last step, at the root's height when it was hit
	at: Vector3,
	stamp: number,
	endsAt: number,
	-- the server pushes an NPC itself, this is that mover so a wall can stop it
	mover: Instance?,
}

-- the server follows its own copy of every knockback path instead of where a client says it is, and checks a little
-- ahead of it for a wall each step, the way the reference does (R10.2)
local Knockback = {}

local flights: { [Model]: Flight } = {}

local params = RaycastParams.new()
params.CollisionGroup = "MoveProbe"

function Knockback.start(char: Model, root: BasePart, velocity: Vector3, now: number, mover: Instance?)
	Knockback.stop(char)
	flights[char] = {
		velocity = velocity,
		at = root.Position,
		stamp = now,
		endsAt = now + Config.KNOCKBACK_TIME,
		mover = mover,
	}
end

function Knockback.stop(char: Model)
	local flight = flights[char]
	if flight and flight.mover then
		flight.mover:Destroy()
	end
	flights[char] = nil
end

-- the ray runs from last step's point to this one's and on past it, so a slow frame can't carry the path through a
-- wall. only an anchored, near upright face counts, the same as a wall run's
function Knockback.step(now: number, onWall: (char: Model, hit: RaycastResult) -> ())
	for char, flight in flights do
		local t = math.min(now, flight.endsAt) - flight.stamp
		local at = flight.at + flight.velocity * t
		local ray = at - flight.at + flight.velocity.Unit * Config.WALL_SLAM_RANGE
		local hit = workspace:Raycast(flight.at, ray, params)
		flight.at = at
		flight.stamp = math.min(now, flight.endsAt)

		if hit and hit.Instance.Anchored and math.abs(hit.Normal.Y) <= Config.WALL_MAX_NORMAL_Y then
			Knockback.stop(char)
			onWall(char, hit)
		elseif now >= flight.endsAt then
			flights[char] = nil
		end
	end
end

return Knockback
