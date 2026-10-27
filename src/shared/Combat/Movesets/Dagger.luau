--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local Types = require(script.Parent.Parent.Parent.Types)

-- the light anims are 43 frames and the stab lands about frame 25
local LIGHT_CONTACT = 25
local LIGHT_LENGTH = 43
-- hits land a whole anim apart, so the stun has to outlast that for a string to connect
local LIGHT_STUN = 0.8
-- width, height, depth in studs, before HIT_SLACK. a slash sweeps wide and short, a stab is narrow and reaches
local SLASH = Vector3.new(6, 5, 4.5)
local STAB = Vector3.new(3.5, 5, 5.5)

local Dagger: Types.Moveset = {
	hitType = "Slash",
	light = {
		{
			anim = "rbxassetid://87060332838420",
			swing = { fx = "SlashL", spin = 100, angle = "Horizontal" },
			box = SLASH,
			contact = LIGHT_CONTACT,
			length = LIGHT_LENGTH,
			stun = LIGHT_STUN,
		},
		{
			anim = "rbxassetid://131389170421490",
			swing = { fx = "SlashR", spin = 100, angle = "Horizontal" },
			box = SLASH,
			contact = LIGHT_CONTACT,
			length = LIGHT_LENGTH,
			stun = LIGHT_STUN,
			hand = "Right",
		},
		{
			anim = "rbxassetid://134208132284359",
			swing = { fx = "SlashThrust", angle = "Horizontal" },
			box = STAB,
			contact = LIGHT_CONTACT,
			length = LIGHT_LENGTH,
			stun = LIGHT_STUN,
		},
		{
			anim = "rbxassetid://85923627322840",
			swing = {
				fx = "SlashR",
				at = CFrame.new(-0.309, 0.674, -0.635, -0.299, -0.95, 0.086, 0.954, -0.297, 0.027, 0, 0.091, 0.996),
			},
			box = SLASH,
			contact = LIGHT_CONTACT,
			length = LIGHT_LENGTH,
			stun = LIGHT_STUN,
			hand = "Right",
		},
		-- the finisher, it knocks back unless delayed
		{
			anim = "rbxassetid://95038775984402",
			contact = LIGHT_CONTACT,
			length = LIGHT_LENGTH,
			damage = 5,
			posture = 15,
			stun = 0.85,
			knockback = 50,
			swing = { fx = "SlashL", angle = "DiagonalRight" },
			box = SLASH,
		},
	},
	-- 83 frames, two slashes, left then right. the first lands about 35 to 37, so its box stays open 6 frames, and the
	-- second lands about 60, picking up the moment the first's box closes. the first is a plain hit that holds the
	-- target for the second, which is the real crit
	heavy = {
		anim = "rbxassetid://70984112218280",
		swing = { fx = "SlashL", angle = "Horizontal", spin = 100 },
		box = SLASH,
		contact = 35,
		delayAt = 22 / 60,
		active = 6 / 60,
		damage = 6,
		posture = 15,
		stun = 0.55,
		lunge = 30,
		knockback = 0,
		canDodge = true,
		isGuardBreak = false,
		isHeavyStun = false,
		follow = {
			-- a follow takes its kind's box and no swing effect, not its first strike's
			swing = { fx = "SlashR", angle = "Horizontal", spin = 100 },
			box = SLASH,
			contact = 60,
			length = 83,
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
	-- 39 frames, it lands about frame 21
	launch = {
		anim = "rbxassetid://80619691559159",
		swing = { fx = "BluntSwipeR", at = CFrame.new(-0.152, 0.361, -1, -0.416, -0.909, 0, 0.909, -0.416, 0, 0, 0, 1) },
		box = Vector3.new(4, 7, 4.5),
		contact = 21,
		length = 39,
	},
	-- 35 frames, the windup ends on frame 19 and it lands about 24. a delay creeps on at DELAY_SPEED, about 4 frames
	-- over a full hold, so it starts that much early and a held slam sits at the top of its windup
	slam = {
		anim = "rbxassetid://139744136217190",
		swing = { fx = "BluntSwipeL", at = CFrame.new(0, 0, -1.195, 0.157, -0.988, 0, 0.988, 0.157, 0, 0, 0, 1) },
		box = Vector3.new(5, 9, 5),
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
