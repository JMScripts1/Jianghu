--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local Types = require(script.Parent.Parent.Parent.Types)

-- the light anims are 44 frames at 60 fps and the punch lands on frame 28. the server starts the swing half a ping
-- late, so the box checks from a few frames before that through just after. the three add up to the whole anim
local LIGHT_WINDUP = 25 / 60
local LIGHT_ACTIVE = 4 / 60
local LIGHT_RECOVERY = 15 / 60
-- hits land a whole anim apart, so the stun has to outlast that for a string to connect
local LIGHT_STUN = 0.8

local Fist: Types.Moveset = {
	hitType = "Blunt",
	light = {
		{
			anim = "rbxassetid://105683870168935",
			swing = {
				fx = "BluntThrust",
				at = CFrame.new(-0.122, 0.304, -0.73, 0.955, -0.298, 0, 0.298, 0.955, 0, 0, 0, 1),
			},
			windup = LIGHT_WINDUP,
			active = LIGHT_ACTIVE,
			recovery = LIGHT_RECOVERY,
			stun = LIGHT_STUN,
		},
		{
			anim = "rbxassetid://132199108178634",
			swing = {
				fx = "BluntSwipeL",
				at = CFrame.new(-0.122, 0.304, -0.73, -0.977, -0.214, 0, 0.214, -0.977, 0, 0, 0, 1),
			},
			windup = LIGHT_WINDUP,
			active = LIGHT_ACTIVE,
			recovery = LIGHT_RECOVERY,
			stun = LIGHT_STUN,
		},
		{
			anim = "rbxassetid://85679270615646",
			swing = {
				fx = "BluntSwipeR",
				at = CFrame.new(-0.122, 0.304, -0.73)
					* CFrame.fromOrientation(math.rad(-3.841), math.rad(165.489), math.rad(-149.512)),
			},
			windup = LIGHT_WINDUP,
			active = LIGHT_ACTIVE,
			recovery = LIGHT_RECOVERY,
			stun = LIGHT_STUN,
		},
		{
			anim = "rbxassetid://83303322568088",
			swing = {
				fx = "BluntThrust",
				at = CFrame.new(-0.122, 0.304, -0.73, -0.977, -0.214, 0, 0.214, -0.977, 0, 0, 0, 1),
			},
			windup = LIGHT_WINDUP,
			active = LIGHT_ACTIVE,
			recovery = LIGHT_RECOVERY,
			stun = LIGHT_STUN,
		},
		-- the finisher, it knocks back unless delayed
		{
			anim = "rbxassetid://78930044990625",
			swing = {
				fx = "BluntThrust",
				at = CFrame.new(0.007, 0.525, -1, 0.541, -0.841, 0, 0.841, 0.541, 0, 0, 0, 1),
			},
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
		swing = { fx = "BluntThrust", at = CFrame.new(0.138, 0.418, -3.544) },
		windup = 35 / 60,
		delayAt = 0.3,
		active = 4 / 60,
		recovery = 21 / 60,
		lunge = 40,
		knockback = 70,
		damage = 20,
	},
	-- the victim lies in the generic GripPose in front, facing the gripper. the kill lands killAt seconds in
	grip = {
		anim = "rbxassetid://94398703522966",
		offset = CFrame.new(0, 0, -3) * CFrame.Angles(0, math.pi, 0),
		killAt = 130 / 60,
	},
	run = { anim = "" },
	air = { anim = "" },
	-- 39 frames, it lands about frame 21. it checks a few frames either side, the same way the lights do
	launch = {
		anim = "rbxassetid://80619691559159",
		swing = { fx = "BluntSwipeR", at = CFrame.new(-0.152, 0.361, -1, -0.416, -0.909, 0, 0.909, -0.416, 0, 0, 0, 1) },
		windup = 18 / 60,
		active = 4 / 60,
		recovery = 17 / 60,
	},
	-- 35 frames, the windup ends on frame 19 and it lands about 24. a delay creeps on at DELAY_SPEED, about 4 frames
	-- over a full hold, so it starts that much early and a held slam sits at the top of its windup
	slam = {
		anim = "rbxassetid://139744136217190",
		swing = { fx = "BluntSwipeL", at = CFrame.new(0, 0, -1.195, 0.157, -0.988, 0, 0.988, 0.157, 0, 0, 0, 1) },
		windup = 22 / 60,
		delayAt = 15 / 60,
		active = 4 / 60,
		recovery = 9 / 60,
	},
	reactions = {
		Parrying = "rbxassetid://111421663323177",
		Blocking = "rbxassetid://120953089487237",
		Parry = "rbxassetid://87080884226868",
		Deflected = "rbxassetid://129447946886861",
		BlockHit = "rbxassetid://136221159215388",
	},
}

return Fist
