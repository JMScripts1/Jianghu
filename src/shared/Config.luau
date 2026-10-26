--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.

return table.freeze({
	DEBUG = true,

	WALK_SPEED = 14,
	CROUCH_SPEED = 7,
	RUN_SPEED = 22,
	-- a run holds the momentum it started with for RUN_HOLD, then drops back to RUN_SPEED at RUN_DECAY a second
	RUN_HOLD = 2.5,
	RUN_DECAY = 4,
	-- at or under this share of health a run is HURT_SPEED_PENALTY slower
	HURT_THRESHOLD = 0.3,
	HURT_SPEED_PENALTY = 4,
	MOMENTUM_MAX = 40,
	-- the same move again within REPEAT_RESET of its last use gains REPEAT_FALLOFF times what that one did
	REPEAT_FALLOFF = 0.7,
	REPEAT_RESET = 2,
	MOMENTUM_GROUND_DECAY = 30,
	MOMENTUM_AIR_DECAY = 1.5,
	LAND_GRACE = 0.15,
	AIR_TURN_RATE = 120,

	JUMP_POWER = 50,
	DOUBLE_JUMP_POWER = 80,
	MAX_AIR_JUMPS = 1,
	COYOTE = 0.15,
	-- a drop of at least this below where the ground was left lands in a roll
	ROLL_HEIGHT = 10,
	ROLL_SPEED = 20,
	-- the roll animation is 26 frames at 60 fps, stretched to this
	ROLL_TIME = 26 / 60,

	SLIDE_MIN_SPEED = 18,
	SLIDE_BOOST = 1.1,
	SLIDE_DECAY = 12,
	-- a second on a straight drop, scaled by Probes.slope. it outruns SLIDE_DECAY from about 12 degrees
	SLOPE_GAIN = 60,
	SLIDE_END_SPEED = 10,
	SLIDE_COOLDOWN = 1.2,
	-- degrees per second the slide turns toward the camera
	SLIDE_TURN_RATE = 90,
	SLIDE_JUMP_GAIN = 4,
	-- the slide jump launches at momentum times this plus SLIDE_JUMP_LIFT up, held for SLIDE_JUMP_LAUNCH_TIME
	SLIDE_JUMP_LAUNCH = 1.5,
	SLIDE_JUMP_LIFT = 18,
	SLIDE_JUMP_LAUNCH_TIME = 0.25,
	-- a slide jump that clears a drop of LEDGE_LEAP_DROP within LEDGE_LEAP_WINDOW of takeoff turns into a ledge leap
	LEDGE_LEAP_WINDOW = 0.2,
	LEDGE_LEAP_DROP = 8,
	-- a slide jump on a floor dropping at least this steeply along the slide is a ramp leap, 0.34 is about 20 degrees
	RAMP_SLOPE = 0.34,
	LEDGE_LEAP_GAIN = 8,
	LEDGE_LEAP_LAUNCH = 2,
	LEDGE_LEAP_LIFT = 30,
	LEDGE_LEAP_LAUNCH_TIME = 0.25,
	-- the leap lasts as long as its animation, this is the most the server allows and the length until it loads
	LEDGE_LEAP_TIME = 1,

	WALL_REACH = 2.5,
	WALL_SPAN_OFFSETS = table.freeze({ 1.5, -1.5 }),
	WALL_MAX_NORMAL_Y = 0.2,
	FACING_SPLIT = 0.7,
	WALL_REGRAB = 0.4,
	WALLRUN_MIN_SPEED = 16,
	WALLRUN_MAX_TIME = 2.5,
	WALLRUN_FALL_SPEED = 3,
	WALLRUN_DECAY = 2,
	CLING_MAX_TIME = 3,
	CLING_SLIDE_SPEED = 2,
	CLING_GAIN = 2,
	LEAP_OUT = 60,
	LEAP_UP = 80,
	LEAP_TIME = 0.35,
	LEAP_GAIN = 6,
	BOOST_UP = 100,
	BOOST_TIME = 0.6,
	BOOST_IN = 10,

	MANTLE_COOLDOWN = 0.4,
	LEDGE_REACH = 2.5,
	-- Mantle lip window from the root centre, just above the feet to 5 over the head
	LEDGE_LOW = -2.5,
	LEDGE_HIGH = 6.5,
	LEDGE_DEPTH = 1.5,
	-- the Mantle animation's length, it plants its hands at the halfway point
	MANTLE_TIME = 0.4,
	-- where the root sits when the hands land, above the lip and out from the wall face
	LEDGE_PLANT_UP = 0.5,
	LEDGE_PLANT_OUT = 0.5,
	TOP_MIN_NORMAL_Y = 0.8,

	DASH_SPEED = 55,
	DASH_TIME = 0.25,
	DASH_TAIL = 0.15,
	DASH_AIR_HOLD = 0.1,
	-- the back dash is a slow backstep, then a burst when its animation hits the Boost marker
	BACK_DASH_SPEED = 20,
	BACK_DASH_DRIFT = 0.8,
	BACK_DASH_BOOST = 3,
	-- the backstep stops here if the marker hasn't fired, so the marker has to come before it
	BACK_DASH_TIME = 0.5,
	BACK_DASH_BOOST_TIME = 0.2,
	-- the DashB animation's Boost marker is on frame 35 at 60 fps. the backstep up to it plays in BACK_DASH_WINDUP,
	-- the rest at the rate that would stretch the whole animation to BACK_DASH_ANIM_TIME
	BACK_DASH_MARKER = 35 / 60,
	BACK_DASH_WINDUP = 0.3,
	BACK_DASH_ANIM_TIME = 1,
	-- a forward dash in the air bursts at AIR_DASH_SPEED, then carries momentum plus AIR_DASH_GAIN, at least AIR_DASH_EXIT
	AIR_DASH_SPEED = 70,
	AIR_DASH_GAIN = 4,
	AIR_DASH_EXIT = 28,
	-- upward speed held through DASH_AIR_HOLD instead of zero, so the air dash rises a little
	AIR_DASH_LIFT = 30,
	-- the iframes, from the start of any dash
	DODGE_TIME = 0.25,
	DASH_COOLDOWN = 1.2,

	LEAN_WALK = 9,
	LEAN_SPRINT = 11,
	LEAN_TIME = 0.08,
	-- the camera widens from FOV_BASE at walking speed to FOV_MAX at MOMENTUM_MAX and past, easing over FOV_TIME
	FOV_BASE = 70,
	FOV_MAX = 85,
	FOV_TIME = 0.15,
	-- a downhill slide widens it by up to FOV_SLOPE more, scaled by Probes.slope, easing over FOV_SLOPE_TIME
	FOV_SLOPE = 20,
	FOV_SLOPE_TIME = 0.8,
	-- seconds between footsteps, matched to the animations, which play at the same speed whatever the momentum
	WALK_STEP_TIME = 0.5,
	RUN_STEP_TIME = 0.3,
	CROUCH_STEP_TIME = 0.5,
	-- footsteps fade out to nothing by this distance
	FOOTSTEP_RANGE = 80,
	ANIM_FADE = 0.1,
	-- attacks and guard poses sit far apart, and a longer blend swings the arm through the body between them
	COMBAT_FADE = 0.03,
	-- run animation speed through a running jump, back to 1 on landing
	RUN_JUMP_ANIM_SPEED = 0.3,
	-- the run plays the sprint from ENTER momentum until it falls back under EXIT, two lines so it never flickers
	-- on one, and blends over the longer fade so it reads as picking up speed
	SPRINT_ANIM_ENTER = 32,
	SPRINT_ANIM_EXIT = 28,
	SPRINT_ANIM_FADE = 0.25,

	KEYS = table.freeze({
		SPRINT = Enum.KeyCode.W,
		CROUCH = Enum.KeyCode.LeftControl,
		JUMP = Enum.KeyCode.Space,
		DASH = Enum.KeyCode.Q,
		DASH_CANCEL = Enum.UserInputType.MouseButton2,
		LIGHT = Enum.UserInputType.MouseButton1,
		HEAVY = Enum.KeyCode.R,
		BLOCK = Enum.KeyCode.F,
		GRIP = Enum.KeyCode.B,
		ADMIN_MENU = Enum.KeyCode.F2,
	}),
	-- most seconds between the two taps of the sprint key
	DOUBLE_TAP = 0.3,

	-- offsets from the HumanoidRootPart centre, same for every R6 character
	ROOT_HEIGHT = 3,
	KNEE_Y = -2,
	GROUND_RAY = 4,
	STAND_RAY = 2.5,

	MOVE_BURST = 10,
	MOVE_REFILL = 8,
	SPEED_SAMPLE_INTERVAL = 0.25,
	SPEED_TOLERANCE = 1.25,
	SPEED_LAG_STUDS = 4,
	SPEED_BUCKET_MAX = 6,
	SPEED_BUCKET_DRAIN = 1.5,
	SPAWN_EXEMPT = 1.5,
	-- server side give, so jitter and the server's slightly old view never deny a real player
	COOLDOWN_TOLERANCE = 0.15,
	LAND_SLACK = 3,
	PROBE_SLACK = 3,
	PROBE_LAG = 0.25,

	STAMINA_MAX = 100,
	STAMINA_REGEN = 15,

	PARRY_WINDOW = 0.25,
	PARRY_COOLDOWN = 1.4,
	PARRY_POSTURE = 20,
	PARRIED_STUN = 0.4,
	-- a parried attacker is pushed back at this for LUNGE_TIME, about 3 studs
	PARRY_RECOIL = 30,
	-- a parry and a hit on a player are judged as far back as its screen is behind: its round trip plus VIEW_DELAY,
	-- the replication before a swing shows, never more than PARRY_REWIND. see Ping
	PARRY_REWIND = 0.2,
	VIEW_DELAY = 0.05,
	PING_INTERVAL = 2,
	-- the target's flat look dotted with the way to the attacker. under 0 because the server sees a turn late
	GUARD_FACING = -0.15,

	POSTURE_MAX = 100,
	POSTURE_REGEN = 15,
	POSTURE_REGEN_DELAY = 2,
	-- the length of the PostureBroken animation, 180 frames
	POSTURE_BREAK_TIME = 3,
	-- the first hit during a break ends it, always knocks back at this speed and does this times its damage
	BREAK_KNOCKBACK = 70,
	BREAK_HIT_DAMAGE = 1.5,
	-- a knockback that meets a wall within WALL_SLAM_RANGE of its path pins the body WALL_SLAM_OFFSET off it for
	-- WALL_STUN, and takes WALL_POSTURE and WALL_DAMAGE. another before WALL_IMMUNITY only stops there, so a
	-- wall can't pin someone for good
	WALL_SLAM_RANGE = 1.5,
	WALL_SLAM_OFFSET = 0.5,
	WALL_STUN = 1.5,
	WALL_POSTURE = 25,
	WALL_DAMAGE = 5,
	WALL_IMMUNITY = 4,

	ATTACK_WALK_SPEED = 8,
	COMBO_RESET = 0.4,
	-- no light for this long after a string's last hit ends, so it can't be mashed straight back into the first
	STRING_ENDLAG = 0.4,
	-- the uppercut throws both fighters LAUNCH_RISE up over LAUNCH_TIME, and a juggle holds them there for JUGGLE_HOLD
	-- after each hit
	LAUNCH_COOLDOWN = 4,
	LAUNCH_RISE = 15,
	LAUNCH_TIME = 0.25,
	JUGGLE_HOLD = 1.5,
	-- the nth hit in a row on a juggled body stuns for JUGGLE_DECAY / n of its stun, capped at all of it
	JUGGLE_DECAY = 1.5,
	-- a juggle holds height with an AlignPosition this strong on the up axis only, like the reference's BodyPosition, so
	-- a lunge into the target can't ride the body up over it. it closes at no more than the rise's speed
	JUGGLE_FORCE = 1e6,
	JUGGLE_RESPONSIVENESS = 50,
	-- every dash inside a juggle goes this share of its usual speed, far enough to get behind the target
	JUGGLE_DASH_SCALE = 0.6,
	-- degrees under flat the slam drives its target down at. landing pins it for SLAM_STUN, and a delayed slam does up
	-- to SLAM_DELAY_DAMAGE more of its damage, all of it at DELAY_FULL of hold
	SLAM_ANGLE = 60,
	SLAM_STUN = 2.5,
	SLAM_DELAY_DAMAGE = 0.5,
	HEAVY_COOLDOWN = 3,
	-- a light pressed this close to the end of a swing is sent when it ends
	INPUT_BUFFER = 0.2,
	ACTIVE_STEP = 1 / 30,
	LUNGE_TIME = 0.1,

	-- held through its delayAt, a windup runs at DELAY_SPEED for up to DELAY_MAX
	DELAY_SPEED = 0.1,
	DELAY_MAX = 0.6,
	-- held this long gets all of DELAY_STUN
	DELAY_FULL = 0.25,
	DELAY_COOLDOWN = 1.2,
	DELAY_STUN = 0.15,
	DELAY_POSTURE = 2,
	DELAY_EXHAUST = 4,
	DELAY_LUNGE = 40,
	DELAY_WALK_SPEED = 5,

	RUN_ATTACK_COOLDOWN = 2.5,
	-- the lunge is momentum times this. the damage bonus scales from RUN_SPEED to MOMENTUM_MAX of measured speed
	RUN_ATTACK_LUNGE = 1.5,
	RUN_ATTACK_BONUS = 0.5,

	-- the box grows this much on every side, the server sees everyone slightly in the past
	HIT_SLACK = 1,
	-- the box's back face sits this far behind the root
	BOX_BACK = 1,
	MAX_TARGETS = 4,

	BLOCK_WALK_SPEED = 8,
	STUN_WALK_SPEED = 4,
	KNOCKBACK_TIME = 0.4,

	HEALTH_REGEN = 2,
	REGEN_INTERVAL = 1,
	-- no health regen until this long after hitting or being hit
	COMBAT_TAG = 20,
	DOWNED_TIME = 15,
	-- share of max health a downed character gets back up with
	DOWNED_HEALTH = 0.2,
	-- the angular impulse that tips a ragdoll over backwards, a body balanced on its feet would stay standing
	RAGDOLL_TIP = 90,
	-- studs from the gripper's root to the downed root it picks up
	GRIP_RANGE = 5,

	-- every press has a release that counts too, a dropped Unblock would leave the block held
	COMBAT_BURST = 16,
	COMBAT_REFILL = 12,
	COMBAT_TOLERANCE = 0.15,
	FX_RANGE = 200,
	DUMMY_INTERVAL = 1.5,
	-- a dummy killed by a grip comes back fresh after this
	DUMMY_RESPAWN = 3,
	-- a dummy only turns to and swings at a player this close
	DUMMY_RANGE = 30,

	-- user ids that get the admin menu on a live server, everyone gets it in Studio
	ADMINS = table.freeze({ 10837572668 }),
	EQUIP_BURST = 4,
	EQUIP_REFILL = 2,
})
