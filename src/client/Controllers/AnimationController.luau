--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Anims = require(ReplicatedStorage.Shared.Anims)
local Config = require(ReplicatedStorage.Shared.Config)
local MoveDefs = require(ReplicatedStorage.Shared.MoveDefs)
local Types = require(ReplicatedStorage.Shared.Types)
local Context = require(script.Parent.Movement.Context)

-- these states last until landing but their animations are one shots, so the fall loop takes over when one runs out
local THEN_FALL: { [string]: true } = { Jump = true, DoubleJump = true, SlideJump = true }

local AnimationController = {}

local tracks: { [string]: AnimationTrack } = {}
local playing: AnimationTrack? = nil
-- a one shot over the state's track, stopped by the next state change
local overlay: AnimationTrack? = nil
local current = ""

-- once per character, an Animator has a track limit
function AnimationController.load(ctx: Context.Context)
	table.clear(tracks)
	playing = nil
	overlay = nil
	current = ""

	for name, id in Anims do
		if id == "" then
			continue
		end
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local track = ctx.animator:LoadAnimation(anim)
		tracks[name] = track

		if THEN_FALL[name] then
			-- state() moves current on before stopping the old track, so a state change never gets in here
			ctx.trove:Connect(track.Stopped, function()
				if current == name and playing == track then
					playing = tracks.Fall
					if playing then
						playing:Play(Config.ANIM_FADE)
					end
				end
			end)
		end
	end

	ctx.trove:Add(function()
		table.clear(tracks)
		playing = nil
		overlay = nil
	end)
end

function AnimationController.state(state: Types.MoveState, side: ("Left" | "Right")?)
	local name = if state == "WallRun" or state == "WallLeap" then `{state}{side}` else state
	if name == current then
		return
	end
	local from = current
	current = name

	if overlay then
		overlay:Stop(Config.ANIM_FADE)
		overlay = nil
	end

	-- a running jump keeps the run going slowed down instead of cutting to the jump, landing in Run speeds it back up
	if playing and playing == tracks.Run and (name == "Jump" or name == "Run") then
		playing:AdjustSpeed(if name == "Jump" then Config.RUN_JUMP_ANIM_SPEED else 1)
		return
	end

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

	-- the slide's intro and exit aren't states, they play over the loop and whatever grounded state comes after it
	if name == "Slide" then
		overlay = tracks.SlideIntro
	elseif from == "Slide" and MoveDefs[state].group == "Grounded" then
		overlay = tracks.SlideExit
	end
	if overlay then
		overlay:Play(Config.ANIM_FADE)
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
