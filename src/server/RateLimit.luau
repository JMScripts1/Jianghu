--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

type Action = "Move" | "Dash"
type Bucket = { tokens: number, stamp: number }

local LIMITS: { [Action]: { burst: number, refill: number } } = {
	Move = { burst = Config.MOVE_BURST, refill = Config.MOVE_REFILL },
	Dash = { burst = Config.DASH_BURST, refill = Config.DASH_REFILL },
}

local RateLimit = {}

local buckets: { [Player]: { [Action]: Bucket } } = {}

-- a player with no entry has left, so a late remote from them is refused
function RateLimit.check(plr: Player, action: Action): boolean
	local mine = buckets[plr]
	if not mine then
		return false
	end

	local limit = LIMITS[action]
	local now = os.clock()
	local bucket = mine[action]
	if bucket then
		bucket.tokens = math.min(limit.burst, bucket.tokens + (now - bucket.stamp) * limit.refill)
		bucket.stamp = now
	else
		bucket = { tokens = limit.burst, stamp = now }
		mine[action] = bucket
	end

	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

local function onPlayer(plr: Player)
	buckets[plr] = {}
end

Players.PlayerAdded:Connect(onPlayer)
for _, plr in Players:GetPlayers() do
	onPlayer(plr)
end

Players.PlayerRemoving:Connect(function(plr)
	buckets[plr] = nil
end)

return RateLimit
