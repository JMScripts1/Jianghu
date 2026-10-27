--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local DEBUG_TIME = 0.2

local Hitbox = {}

local roots: { [Model]: BasePart } = {}

-- only ever sees roots, one part per character
local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Include

-- the map only, players and NPCs are all in a group MoveProbe passes through
local sight = RaycastParams.new()
sight.CollisionGroup = Config.PROBE_GROUP

-- a root can't be taken out of the filter on its own, so the whole list is set again
local function refresh()
	local list: { Instance } = {}
	for _, root in roots do
		table.insert(list, root)
	end
	overlap.FilterDescendantsInstances = list
end

local function draw(cf: CFrame, size: Vector3)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 0.7
	part.Color = Color3.fromRGB(255, 0, 0)
	part.CFrame = cf
	part.Size = size
	part.Parent = workspace
	task.delay(DEBUG_TIME, function()
		part:Destroy()
	end)
end

function Hitbox.add(char: Model)
	local root = char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		roots[char] = root
		refresh()
	end
end

function Hitbox.remove(char: Model)
	if roots[char] then
		roots[char] = nil
		refresh()
	end
end

-- every character whose root is in the box in front of `from` with nothing from the map in between. a swing that
-- lunges covers the ground its lunge does, so the box reaches on past where the root is by as far as lunge carries it
-- in LUNGE_TIME. the lunge starts at the hit and the server sees the attacker's own push a replication late, so the
-- root is always still where the lunge started. a wall in the way is still caught by the sight ray
function Hitbox.query(from: BasePart, box: Vector3, lunge: number): { Model }
	local slack = Config.HIT_SLACK * 2
	local size = box + Vector3.new(slack, slack, slack + lunge * Config.LUNGE_TIME)
	-- forward is -Z, so the back face sits BOX_BACK behind the root
	local cf = from.CFrame * CFrame.new(0, 0, Config.BOX_BACK - size.Z / 2)
	if Config.DEBUG then
		draw(cf, size)
	end

	local found: { Model } = {}
	for _, part in workspace:GetPartBoundsInBox(cf, size, overlap) do
		local char = part.Parent
		if part == from or not char or not char:IsA("Model") then
			continue
		end
		if workspace:Raycast(from.Position, part.Position - from.Position, sight) then
			continue
		end
		table.insert(found, char)
	end
	return found
end

-- whether a swing from `from` with this box would catch target, the same query the swing itself runs
function Hitbox.reaches(from: BasePart, box: Vector3, lunge: number, target: Model): boolean
	return table.find(Hitbox.query(from, box, lunge), target) ~= nil
end

return Hitbox
