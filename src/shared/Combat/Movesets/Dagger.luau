--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local Types = require(script.Parent.Parent.Parent.Types)

-- the light anims are 43 frames at 60 fps and the stab lands about frame 25. the server starts the swing half a ping
-- late, so the box checks from a few frames before that through just after. the three add up to the whole anim
local LIGHT_WINDUP = 22 / 60
local LIGHT_ACTIVE = 4 / 60
local LIGHT_RECOVERY = 17 / 60
-- hits land a whole anim apart, so the stun has to outlast that for a string to connect
local LIGHT_STUN = 0.8

local Dagger: Types.Moveset = {
	light = {
		{
			anim = "rbxassetid://87060332838420",
			windup = LIGHT_WINDUP,
			active = LIGHT_ACTIVE,
			recovery = LIGHT_RECOVERY,
			stun = LIGHT_STUN,
		},
		{
			anim = "rbxassetid://131389170421490",
			windup = LIGHT_WINDUP,
			active = LIGHT_ACTIVE,
			recovery = LIGHT_RECOVERY,
			stun = LIGHT_STUN,
		},
		{
			anim = "rbxassetid://134208132284359",
			windup = LIGHT_WINDUP,
			active = LIGHT_ACTIVE,
			recovery = LIGHT_RECOVERY,
			stun = LIGHT_STUN,
		},
		{
			anim = "rbxassetid://85923627322840",
			windup = LIGHT_WINDUP,
			active = LIGHT_ACTIVE,
			recovery = LIGHT_RECOVERY,
			stun = LIGHT_STUN,
		},
		-- the finisher, it knocks back unless delayed
		{
			anim = "rbxassetid://95038775984402",
			windup = LIGHT_WINDUP,
			active = LIGHT_ACTIVE,
			recovery = LIGHT_RECOVERY,
			damage = 5,
			posture = 15,
			stun = 0.85,
			knockback = 50,
		},
	},
	-- 83 frames, two swings. the first windup ends on frame 27 and its stab lands about 35 to 37, then the second
	-- windup ends on 51 and its stab lands about 60. each is checked from a few frames before through just after, and
	-- the second picks up the moment the first ends, so the five add up to the whole anim. the first is a plain hit
	-- that holds the target for the second, which is the real crit
	heavy = {
		anim = "rbxassetid://70984112218280",
		windup = 32 / 60,
		delayAt = 22 / 60,
		active = 6 / 60,
		recovery = 0,
		damage = 6,
		posture = 15,
		stun = 0.55,
		lunge = 30,
		knockback = 0,
		canDodge = true,
		isGuardBreak = false,
		isHeavyStun = false,
		follow = {
			windup = 19 / 60,
			active = 4 / 60,
			recovery = 22 / 60,
			damage = 14,
			lunge = 40,
			knockback = 70,
		},
	},
	grip = {
		anim = "rbxassetid://102379717060858",
		victim = "rbxassetid://126464927360894",
		offset = CFrame.new(0, 0, 0) * CFrame.Angles(0, math.pi, 0),
		killAt = 105 / 60,
	},
	run = { anim = "" },
	air = { anim = "" },
	-- 39 frames, it lands about frame 21. it checks a few frames either side, the same way the lights do
	launch = {
		anim = "rbxassetid://80619691559159",
		windup = 18 / 60,
		active = 4 / 60,
		recovery = 17 / 60,
	},
	-- 35 frames, the windup ends on frame 19 and it lands about 24. a delay creeps on at DELAY_SPEED, about 4 frames
	-- over a full hold, so it starts that much early and a held slam sits at the top of its windup
	slam = {
		anim = "rbxassetid://139744136217190",
		windup = 22 / 60,
		delayAt = 15 / 60,
		active = 4 / 60,
		recovery = 9 / 60,
	},
	movement = {
		Idle = "rbxassetid://137203815389780",
		Walk = "rbxassetid://75792971332525",
	},
	reactions = {
		Parrying = "rbxassetid://111421663323177",
		Blocking = "rbxassetid://120953089487237",

		Parry = "rbxassetid://87080884226868",
		-- the fist's, its own two put the left arm through the body out of the dagger stance
		Deflected = "rbxassetid://129447946886861",
		BlockHit = "rbxassetid://95408241331260",
	},
}

return Dagger
