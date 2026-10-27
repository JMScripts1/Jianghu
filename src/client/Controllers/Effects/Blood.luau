--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local Sfx = require(script.Parent.Sfx)
local Vfx = require(script.Parent.Vfx)

type Drop = { part: BasePart, at: Vector3, velocity: Vector3, endsAt: number }

-- a drop flies out the far side of the body and up, AWAY and UP of each before SCATTER throws it off a little
local AWAY = 0.6
local UP = 1
local SCATTER = 0.5
-- a third either side of BLOOD_SPEED
local SPEED_SPREAD = 1 / 3
-- the trail fades out over about this, so a drop is kept that long after it stops
local TRAIL_FADE = 0.5
-- the pool sits this far off the surface so it never sinks into it
local SPLAT_LIFT = 0.1

-- blood from a hit: a burst at the body, then drops thrown out the far side that splat where they land, the way the
-- reference's Blood projectile and Demon Slayer's BloodFire both do it. the flight is worked out here, not by physics,
-- and only ever on the client
local Blood = {}

local drops: { Drop } = {}
local isWarned = false

-- the map only, a drop never lands on a character
local params = RaycastParams.new()
params.CollisionGroup = Config.PROBE_GROUP

local function spread(): number
	return math.random() * 2 - 1
end

-- somewhere inside the part, so the drops don't all leave from one point
local function inside(part: BasePart): Vector3
	local half = part.Size / 2
	return (part.CFrame * CFrame.new(spread() * half.X, spread() * half.Y, spread() * half.Z)).Position
end

-- moved along its flight, so it has to be a part
local function dropTemplate(): BasePart?
	local template = Vfx.template("Blood", "Drop")
	if template and template:IsA("BasePart") then
		return template
	elseif template and not isWarned then
		isWarned = true
		warn("vfx Blood/Drop has to be a Part, it's moved along the drop's flight")
	end
	return nil
end

-- the pool lies along the surface, turned a random way so no two look the same
local function land(hit: RaycastResult)
	local turn = Vector3.new(spread(), 0, spread())
	Vfx.at(Vfx.template("Blood", "Splat"), Vfx.surface(hit.Position + hit.Normal * SPLAT_LIFT, hit.Normal, turn))
	Sfx.at(Sounds.BloodLand, hit.Position)
end

-- count drops out of body, thrown away from `from`. past BLOOD_MAX_DROPS in the air the rest are skipped
function Blood.spill(body: BasePart, from: Vector3, count: number)
	Vfx.on(Vfx.template("Blood", "Hit"), body, CFrame.identity)
	Sfx.at(Sounds.BloodSpill, body.Position)
	local template = dropTemplate()
	if not template then
		return
	end

	local gap = body.Position - from
	local flat = Vector3.new(gap.X, 0, gap.Z)
	local away = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zero
	local endsAt = os.clock() + Config.BLOOD_LIFETIME
	for _ = 1, math.min(count, Config.BLOOD_MAX_DROPS - #drops) do
		local scatter = Vector3.new(spread(), spread(), spread()) * SCATTER
		local dir = (away * AWAY + Vector3.yAxis * UP + scatter).Unit
		local speed = Config.BLOOD_SPEED * (1 + spread() * SPEED_SPREAD)
		local at = inside(body)
		table.insert(drops, {
			part = Vfx.part(template, CFrame.new(at)),
			at = at,
			velocity = dir * speed,
			endsAt = endsAt,
		})
	end
end

-- a ray along each step's move, so a fast drop can't pass through a thin floor between frames
local function step(dt: number)
	local now = os.clock()
	for i = #drops, 1, -1 do
		local drop = drops[i]
		drop.velocity -= Vector3.new(0, Config.BLOOD_GRAVITY * dt, 0)
		local move = drop.velocity * dt
		local hit = workspace:Raycast(drop.at, move, params)
		if hit or now >= drop.endsAt then
			table.remove(drops, i)
			if hit then
				drop.part.Position = hit.Position
				land(hit)
			end
			task.delay(TRAIL_FADE, function()
				drop.part:Destroy()
			end)
			continue
		end
		drop.at += move
		drop.part.CFrame = CFrame.lookAt(drop.at, drop.at + drop.velocity)
	end
end

RunService.PreRender:Connect(step)

return Blood
