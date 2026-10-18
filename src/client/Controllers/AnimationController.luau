--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Anims = require(ReplicatedStorage.Shared.Anims)
local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Context = require(script.Parent.Movement.Context)

local AnimationController = {}

local tracks: { [string]: AnimationTrack } = {}
local playing: AnimationTrack? = nil
local current = ""

-- once per character, an Animator has a track limit
function AnimationController.load(ctx: Context.Context)
	table.clear(tracks)
	playing = nil
	current = ""

	for name, id in Anims do
		if id == "" then
			continue
		end
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		tracks[name] = ctx.animator:LoadAnimation(anim)
	end

	ctx.trove:Add(function()
		table.clear(tracks)
		playing = nil
	end)
end

function AnimationController.state(state: Types.MoveState, side: ("Left" | "Right")?)
	local name = if state == "WallRun" then `WallRun{side}` else state
	if name == current then
		return
	end
	current = name

	if playing then
		playing:Stop(Config.ANIM_FADE)
	end
	playing = tracks[name]
	if playing then
		playing:Play(Config.ANIM_FADE)
		-- the vault's path is keyed to the animation, so the animation is stretched to the vault's length
		if name == "VaultMid" and playing.Length > 0 then
			playing:AdjustSpeed(playing.Length / Config.VAULT_MID_TIME)
		end
	end
end

-- plays over the state's track, a dash doesn't change the state
function AnimationController.dash(dir: Types.DashDir)
	local track = tracks[`Dash{dir}`]
	if track then
		track:Play(Config.ANIM_FADE)
	end
end

return AnimationController
