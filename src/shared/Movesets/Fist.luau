--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local Types = require(script.Parent.Parent.Types)

-- the light anims are 44 frames at 60 fps and the punch lands on frame 28. the server starts the swing half a ping
-- late, so the box checks from a few frames before that through just after. the three add up to the whole anim
local LIGHT_WINDUP = 25 / 60
local LIGHT_ACTIVE = 4 / 60
local LIGHT_RECOVERY = 15 / 60
-- hits land a whole anim apart, so the stun has to outlast that for a string to connect
local LIGHT_STUN = 0.8

local Fist: Types.Moveset = {
	light = {
		{
			anim = "rbxassetid://105683870168935",
			windup = LIGHT_WINDUP,
			active = LIGHT_ACTIVE,
			recovery = LIGHT_RECOVERY,
			stun = LIGHT_STUN,
		},
		{
			anim = "rbxassetid://132199108178634",
			windup = LIGHT_WINDUP,
			active = LIGHT_ACTIVE,
			recovery = LIGHT_RECOVERY,
			stun = LIGHT_STUN,
		},
		{
			anim = "rbxassetid://85679270615646",
			windup = LIGHT_WINDUP,
			active = LIGHT_ACTIVE,
			recovery = LIGHT_RECOVERY,
			stun = LIGHT_STUN,
		},
		{
			anim = "rbxassetid://83303322568088",
			windup = LIGHT_WINDUP,
			active = LIGHT_ACTIVE,
			recovery = LIGHT_RECOVERY,
			stun = LIGHT_STUN,
		},
		-- the finisher, it knocks back unless delayed
		{
			anim = "rbxassetid://78930044990625",
			windup = LIGHT_WINDUP,
			active = LIGHT_ACTIVE,
			recovery = LIGHT_RECOVERY,
			damage = 5,
			posture = 15,
			stun = 0.85,
			knockback = 50,
		},
	},
	-- 60 frames, the windup ends on frame 23 and the punch lands about 38. it checks the same way the lights do, from a
	-- few frames before through just after, and the three add up to the whole anim.
	-- lunge pushes forward at that many studs a second for LUNGE_TIME, starting at the hit
	heavy = {
		anim = "rbxassetid://108120316811300",
		windup = 35 / 60,
		delayAt = 0.3,
		active = 4 / 60,
		recovery = 21 / 60,
		lunge = 40,
		knockback = 70,
	},
	run = { anim = "" },
	air = { anim = "" },
	reactions = {
		Parrying = "",
		Blocking = "",
	},
}

return Fist
