--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

-- each round trip moves the estimate this share of the way, so one spike doesn't swing it
local SMOOTHING = 0.25

local Ping = {}

-- timed here and not from GetNetworkPing, which leaves out frame time and Studio's simulated lag
local rtts: { [Player]: number } = {}
-- one ping out per player at a time, so an answer nobody asked for does nothing. that's the rate limit
local sentAt: { [Player]: number } = {}
-- the first ping waits in the queue until the client's scripts load, so its time says nothing and is thrown away
local isTimed: { [Player]: true } = {}

-- how far behind the server this character's screen is: the round trip plus the replication delay before a swing
-- shows. a parry and a hit on it are judged that far back. capped, so a client faking a slow connection gains no more
-- than PARRY_REWIND. NPCs live on the server and see everything as it happens
function Ping.rewind(char: Model): number
	local plr = Players:GetPlayerFromCharacter(char)
	if not plr then
		return 0
	end
	return math.min(Config.PARRY_REWIND, (rtts[plr] or 0) + Config.VIEW_DELAY)
end

local function onPing(plr: Player)
	local at = sentAt[plr]
	if not at then
		return
	end
	sentAt[plr] = nil
	if not isTimed[plr] then
		isTimed[plr] = true
		return
	end
	local sample = os.clock() - at
	local rtt = rtts[plr]
	rtts[plr] = if rtt then rtt + (sample - rtt) * SMOOTHING else sample
end

Remotes.Ping.OnServerEvent:Connect(onPing)
Players.PlayerRemoving:Connect(function(plr)
	rtts[plr] = nil
	sentAt[plr] = nil
	isTimed[plr] = nil
end)

task.spawn(function()
	while true do
		for _, plr in Players:GetPlayers() do
			if not sentAt[plr] then
				sentAt[plr] = os.clock()
				Remotes.Ping:FireClient(plr)
			end
		end
		task.wait(Config.PING_INTERVAL)
	end
end)

return Ping
