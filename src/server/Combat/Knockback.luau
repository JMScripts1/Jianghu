--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

type Flight = {
	velocity: Vector3,
	-- where the server's own copy of the path had got to last step, starting where the root was when it was hit
	at: Vector3,
	stamp: number,
	endsAt: number,
	-- the server pushes an NPC itself, this is that mover so a wall can stop it
	mover: Instance?,
}

-- slower than this flat, a path has no way forward to look along for a wall
local MIN_FLAT = 1

-- the server follows its own copy of every knockback path instead of where a client says it is, and checks a little
-- ahead of it for a wall each step, the way the reference does (R10.2). a path going down looks for the floor too
local Knockback = {}

local flights: { [Model]: Flight } = {}

local params = RaycastParams.new()
params.CollisionGroup = Config.PROBE_GROUP

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

-- the flat part of the path, from last step's point through this one's and on past it, so a slow frame can't carry it
-- through a wall. only an anchored, near upright face counts, the same as a wall run's
local function wall(flight: Flight, at: Vector3): RaycastResult?
	local flat = Vector3.new(flight.velocity.X, 0, flight.velocity.Z)
	if flat.Magnitude < MIN_FLAT then
		return nil
	end
	local moved = at - flight.at
	local ray = Vector3.new(moved.X, 0, moved.Z) + flat.Unit * Config.WALL_SLAM_RANGE
	local hit = workspace:Raycast(flight.at, ray, params)
	return if hit and hit.Instance.Anchored and math.abs(hit.Normal.Y) <= Config.WALL_MAX_NORMAL_Y then hit else nil
end

-- a root's height above the floor under it, so the body reached the floor once the path is that close
local function floor(flight: Flight, at: Vector3): RaycastResult?
	if flight.velocity.Y >= 0 then
		return nil
	end
	local hit = workspace:Raycast(at, Vector3.new(0, -Config.ROOT_HEIGHT, 0), params)
	return if hit and hit.Normal.Y > Config.WALL_MAX_NORMAL_Y then hit else nil
end

function Knockback.step(
	now: number,
	onWall: (char: Model, hit: RaycastResult) -> (),
	onFloor: (char: Model, hit: RaycastResult) -> ()
)
	for char, flight in flights do
		local t = math.min(now, flight.endsAt) - flight.stamp
		local at = flight.at + flight.velocity * t
		local wallHit = wall(flight, at)
		local floorHit = if wallHit then nil else floor(flight, at)
		flight.at = at
		flight.stamp = math.min(now, flight.endsAt)

		if wallHit then
			Knockback.stop(char)
			onWall(char, wallHit)
		elseif floorHit then
			Knockback.stop(char)
			onFloor(char, floorHit)
		elseif now >= flight.endsAt then
			flights[char] = nil
		end
	end
end

return Knockback
