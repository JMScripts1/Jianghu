--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local StateService = require(script.Parent.Parent.Services.StateService)

type Hold = {
	-- the attachment the mover hangs off, destroying it takes both
	attach: Attachment,
	mover: AlignPosition,
	untilAt: number,
}

-- holds fighters in the air through a juggle with an AlignPosition on the up axis, the way the reference's
-- AerialManager holds them with a BodyPosition (R10.1). the server can't move a player's character, so that client
-- holds its own, told with Juggle. the server holds an NPC itself
local Juggle = {}

local holds: { [Model]: Hold } = {}

local function drop(char: Model)
	local hold = holds[char]
	if hold then
		hold.attach:Destroy()
		holds[char] = nil
	end
end

-- a rise moves the hold that far up, and the mover carries the body there at the rise's speed. a hold with none
-- keeps the height it's at, and every hit renews it
function Juggle.hold(
	char: Model,
	st: StateService.CharState,
	root: BasePart,
	now: number,
	rise: number,
	duration: number
)
	-- a fresh juggle counts its hits from none
	if now >= st.combat.juggleUntil then
		st.combat.juggleHits = 0
	end
	st.combat.juggleUntil = now + duration
	local plr = Players:GetPlayerFromCharacter(char)
	if plr then
		Remotes.Juggle:FireClient(plr, rise, duration)
		return
	end
	if root.Anchored then
		return
	end

	local hold = holds[char]
	if not hold then
		local attach = Instance.new("Attachment")
		attach.Parent = root
		local mover = Instance.new("AlignPosition")
		mover.Mode = Enum.PositionAlignmentMode.OneAttachment
		mover.Attachment0 = attach
		mover.ForceLimitMode = Enum.ForceLimitMode.PerAxis
		mover.MaxAxesForce = Vector3.new(0, Config.JUGGLE_FORCE, 0)
		mover.MaxVelocity = Config.LAUNCH_RISE / Config.LAUNCH_TIME
		mover.Responsiveness = Config.JUGGLE_RESPONSIVENESS
		mover.Position = root.Position
		mover.Parent = attach
		hold = { attach = attach, mover = mover, untilAt = 0 }
		holds[char] = hold
	end
	hold.untilAt = now + duration
	if rise > 0 then
		hold.mover.Position = root.Position + Vector3.new(0, rise, 0)
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			-- a standing Humanoid holds itself to the floor
			hum:ChangeState(Enum.HumanoidStateType.Freefall)
		end
	end
end

function Juggle.release(char: Model, st: StateService.CharState)
	if st.combat.juggleUntil == 0 then
		return
	end
	st.combat.juggleUntil = 0
	st.combat.juggleHits = 0
	drop(char)
	local plr = Players:GetPlayerFromCharacter(char)
	if plr then
		Remotes.Juggle:FireClient(plr, 0, 0)
	end
end

function Juggle.remove(char: Model)
	drop(char)
end

function Juggle.step(now: number)
	for char, hold in holds do
		if now >= hold.untilAt or not hold.attach.Parent then
			drop(char)
		end
	end
end

return Juggle
