--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local Config = require(script.Parent.Config)
local Types = require(script.Parent.Types)

local Probes = {}

local params = RaycastParams.new()
params.CollisionGroup = "MoveProbe"

local UP = Vector3.yAxis

local function isWallFace(hit: RaycastResult): boolean
	return math.abs(hit.Normal.Y) <= Config.WALL_MAX_NORMAL_Y and hit.Instance.Anchored
end

local function isVaultable(part: BasePart): boolean
	if part:HasTag("Vaultable") then
		return true
	end
	local model = part:FindFirstAncestorOfClass("Model")
	return model ~= nil and model:HasTag("Vaultable")
end

-- a ray that starts inside a part never hits it, so a top above the window is rejected for free
local function findTop(at: Vector3, fromY: number, depth: number): Vector3?
	local hit = workspace:Raycast(Vector3.new(at.X, fromY, at.Z), -UP * depth, params)
	if hit and hit.Instance.Anchored and hit.Normal.Y >= Config.TOP_MIN_NORMAL_Y then
		return hit.Position
	end
	return nil
end

local function hasHeadroom(top: Vector3, look: Vector3): boolean
	return workspace:Raycast(top + UP * Config.ROOT_HEIGHT, look * Config.HEADROOM_REACH, params) == nil
end

-- slack is the server's extra reach, it sees every character slightly in the past
function Probes.wall(root: BasePart, speed: number, slack: number?): Types.WallHit?
	local cf = root.CFrame
	local reach = Config.WALL_REACH + (slack or 0)

	for _, dir in { cf.LookVector, cf.RightVector, -cf.RightVector } do
		local ray = dir * reach
		local hit = workspace:Raycast(cf.Position, ray, params)
		if not hit or not isWallFace(hit) or hit.Instance:HasTag("NoWall") then
			continue
		end

		-- centre plus one more height on the same part, so a ledge corner isn't a wall
		local spans = 0
		for _, offset in Config.WALL_SPAN_OFFSETS do
			local other = workspace:Raycast(cf.Position + UP * offset, ray, params)
			if other and other.Instance == hit.Instance then
				spans += 1
			end
		end
		if spans == 0 then
			continue
		end

		local normal = Vector3.new(hit.Normal.X, 0, hit.Normal.Z).Unit
		local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z).Unit
		if -look:Dot(normal) >= Config.FACING_SPLIT then
			return { kind = "Cling", normal = normal, part = hit.Instance }
		elseif speed < Config.WALLRUN_MIN_SPEED then
			return nil
		end

		local side: "Left" | "Right" = if cf.RightVector:Dot(-normal) > 0 then "Right" else "Left"
		return { kind = "Run", side = side, normal = normal, part = hit.Instance }
	end

	return nil
end

function Probes.ground(root: BasePart, slack: number?): RaycastResult?
	return workspace:Raycast(root.Position, -UP * (Config.GROUND_RAY + (slack or 0)), params)
end

-- the client also checks it's moving toward the hit, the server skips that
function Probes.vaultLow(root: BasePart, slack: number?): Types.VaultHit?
	local cf = root.CFrame
	local knee = cf.Position + UP * Config.KNEE_Y
	local hit = workspace:Raycast(knee, cf.LookVector * (Config.VAULT_REACH + (slack or 0)), params)
	if not hit or not isWallFace(hit) or not isVaultable(hit.Instance) then
		return nil
	end

	local floorY = cf.Position.Y - Config.ROOT_HEIGHT
	local top = findTop(
		hit.Position - hit.Normal * Config.VAULT_INSET,
		floorY + Config.VAULT_LOW_MAX_H,
		Config.VAULT_LOW_MAX_H - Config.VAULT_LOW_MIN_H
	)
	if not top or not hasHeadroom(top, cf.LookVector) then
		return nil
	end

	return { kind = "Low", part = hit.Instance, point = top, normal = hit.Normal }
end

-- slack also raises the lip window, a boosting character is further up than the server sees
function Probes.vaultMid(root: BasePart, slack: number?): Types.VaultHit?
	local give = slack or 0
	local cf = root.CFrame
	local head = cf.Position + UP * Config.HEAD_Y
	local reach = cf.LookVector * (Config.LEDGE_REACH + give)
	local hit = workspace:Raycast(head, reach, params)
	if not hit or not isWallFace(hit) or not isVaultable(hit.Instance) then
		return nil
	end

	local windowTop = head.Y + Config.LEDGE_MAX_UP + give
	if workspace:Raycast(Vector3.new(head.X, windowTop, head.Z), reach, params) then
		return nil
	end

	local top = findTop(
		hit.Position - hit.Normal * Config.LEDGE_DEPTH,
		windowTop,
		Config.LEDGE_MAX_UP - Config.LEDGE_MIN_UP + give
	)
	if not top or not hasHeadroom(top, cf.LookVector) then
		return nil
	end

	return { kind = "Mid", part = hit.Instance, point = top, normal = hit.Normal }
end

return Probes
