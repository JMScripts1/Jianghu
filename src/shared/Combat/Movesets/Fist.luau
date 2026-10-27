--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local Types = require(script.Parent.Parent.Parent.Types)

-- the light anims are 44 frames and the punch lands on frame 28
local LIGHT_CONTACT = 28
local LIGHT_LENGTH = 44
-- hits land a whole anim apart, so the stun has to outlast that for a string to connect
local LIGHT_STUN = 0.8
-- width, height, depth in studs, before HIT_SLACK. a jab reaches further, a hook swings wider and shorter
local JAB = Vector3.new(4, 5, 5.5)
local HOOK = Vector3.new(6, 5, 5)

local Fist: Types.Moveset = {
	hitType = "Blunt",
	
	light = {
		{
			anim = "rbxassetid://105683870168935",
			swing = {
				fx = "BluntThrust",
				at = CFrame.new(-0.122, 0.304, -0.73, 0.955, -0.298, 0, 0.298, 0.955, 0, 0, 0, 1),
			},
			box = JAB,
			contact = LIGHT_CONTACT,
			length = LIGHT_LENGTH,
			stun = LIGHT_STUN,
		},
		{
			anim = "rbxassetid://132199108178634",
			swing = {
				fx = "BluntSwipeL",
				at = CFrame.new(-0.122, 0.304, -0.73, -0.977, -0.214, 0, 0.214, -0.977, 0, 0, 0, 1),
			},
			box = HOOK,
			contact = LIGHT_CONTACT,
			length = LIGHT_LENGTH,
			stun = LIGHT_STUN,
		},
		{
			anim = "rbxassetid://85679270615646",
			swing = {
				fx = "BluntSwipeR",
				at = CFrame.new(-0.122, 0.304, -0.73)
					* CFrame.fromOrientation(math.rad(-3.841), math.rad(165.489), math.rad(-149.512)),
			},
			box = HOOK,
			contact = LIGHT_CONTACT,
			length = LIGHT_LENGTH,
			stun = LIGHT_STUN,
		},
		{
			anim = "rbxassetid://83303322568088",
			swing = {
				fx = "BluntThrust",
				at = CFrame.new(-0.122, 0.304, -0.73, -0.977, -0.214, 0, 0.214, -0.977, 0, 0, 0, 1),
			},
			box = JAB,
			contact = LIGHT_CONTACT,
			length = LIGHT_LENGTH,
			stun = LIGHT_STUN,
		},
		-- the finisher, it knocks back unless delayed
		{
			anim = "rbxassetid://78930044990625",
			swing = {
				fx = "BluntThrust",
				at = CFrame.new(0.007, 0.525, -1, 0.541, -0.841, 0, 0.841, 0.541, 0, 0, 0, 1),
			},
			box = JAB,
			contact = LIGHT_CONTACT,
			length = LIGHT_LENGTH,
			damage = 5,
			posture = 15,
			stun = 0.85,
			knockback = 50,
		},
	},
	-- 60 frames, the windup ends on frame 23 and the punch lands about 38
	-- lunge pushes forward at that many studs a second for LUNGE_TIME, starting at the hit
	heavy = {
		anim = "rbxassetid://108120316811300",
		swing = { fx = "BluntThrust", at = CFrame.new(0.138, 0.418, -3.544) },
		box = Vector3.new(5, 5, 6.5),
		contact = 38,
		length = 60,
		delayAt = 0.3,
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
	-- 39 frames, it lands about frame 21
	launch = {
		anim = "rbxassetid://80619691559159",
		swing = { fx = "BluntSwipeR", at = CFrame.new(-0.152, 0.361, -1, -0.416, -0.909, 0, 0.909, -0.416, 0, 0, 0, 1) },
		box = Vector3.new(4, 7, 5),
		contact = 21,
		length = 39,
	},
	-- 35 frames, the windup ends on frame 19 and it lands about 24. a delay creeps on at DELAY_SPEED, about 4 frames
	-- over a full hold, so it starts that much early and a held slam sits at the top of its windup
	slam = {
		anim = "rbxassetid://139744136217190",
		swing = { fx = "BluntSwipeL", at = CFrame.new(0, 0, -1.195, 0.157, -0.988, 0, 0.988, 0.157, 0, 0, 0, 1) },
		box = Vector3.new(5, 9, 5.5),
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
