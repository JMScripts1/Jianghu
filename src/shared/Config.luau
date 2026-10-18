--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.

return table.freeze({
	DEBUG = true,

	WALK_SPEED = 14,
	CROUCH_SPEED = 7,
	RUN_SPEED = 22,
	MOMENTUM_MAX = 44,

	RUN_BUILD = 1.5,
	-- MoveDirection against the flat look, at or above this counts as running straight
	RUN_STRAIGHT = 0.95,
	MOMENTUM_GROUND_DECAY = 30,
	MOMENTUM_AIR_DECAY = 1.5,
	LAND_GRACE = 0.15,
	AIR_TURN_RATE = 120,
	SLOPE_MIN_Y = 0.97,
	SLOPE_GAIN = 12,
	REPEAT_FALLOFF = 0.7,
	REPEAT_RESET = 2,
	TIER_2_SPEED = 30,
	TIER_3_SPEED = 38,
	TIER_HYSTERESIS = 2,

	JUMP_POWER = 50,
	DOUBLE_JUMP_POWER = 45,
	MAX_AIR_JUMPS = 1,
	COYOTE = 0.15,

	SLIDE_MIN_SPEED = 18,
	SLIDE_BOOST = 1.1,
	SLIDE_DECAY = 8,
	SLIDE_END_SPEED = 10,
	SLIDE_COOLDOWN = 0.6,
	SLIDE_JUMP_GAIN = 4,
	-- degrees per second the slide turns toward the camera
	SLIDE_TURN_RATE = 90,

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
	LEAP_OUT = 28,
	LEAP_UP = 40,
	LEAP_TIME = 0.35,
	LEAP_GAIN = 6,
	BOOST_UP = 55,
	BOOST_TIME = 0.4,

	VAULT_REACH = 2.5,
	VAULT_LOW_MIN_H = 2,
	VAULT_LOW_MAX_H = 4.5,
	VAULT_LOW_TIME = 0.5,
	VAULT_BOOST = 1.1,
	VAULT_COOLDOWN = 0.4,
	LEDGE_REACH = 2.5,
	-- lip window, measured up from head height
	LEDGE_MIN_UP = 1,
	LEDGE_MAX_UP = 5,
	LEDGE_DEPTH = 1.5,
	-- the VaultMid animation's length, it plants its hands at the halfway point
	VAULT_MID_TIME = 0.4,
	-- where the root sits when the hands land, above the lip and out from the wall face
	LEDGE_PLANT_UP = 0.5,
	LEDGE_PLANT_OUT = 0.5,
	-- how far past the obstacle's face the VaultLow top ray drops
	VAULT_INSET = 0.5,
	TOP_MIN_NORMAL_Y = 0.8,
	HEADROOM_REACH = 3,
	-- MoveDirection against the obstacle's face, at or above this counts as moving into it
	VAULT_TOWARD = 0.5,
	MOVER_RESPONSIVENESS = 200,
	ANIM_FADE = 0.1,
	-- run animation speed through a running jump, back to 1 on landing
	RUN_JUMP_ANIM_SPEED = 0.3,

	DASH_SPEED = 55,
	DASH_TIME = 0.2,
	-- the back dash is a slow backstep, then a burst when its animation hits the Boost marker
	BACK_DASH_SPEED = 20,
	BACK_DASH_DRIFT = 0.8,
	BACK_DASH_BOOST = 3,
	-- the backstep stops here if the marker hasn't fired, so the marker has to come before it
	BACK_DASH_TIME = 0.5,
	BACK_DASH_BOOST_TIME = 0.2,
	BACK_DASH_ANIM_TIME = 1,
	DODGE_TIME = 0.15,
	DASH_COOLDOWN = 1.2,
	DASH_BURST = 3,
	DASH_REFILL = 1,

	KEYS = table.freeze({
		SPRINT = Enum.KeyCode.W,
		CROUCH = Enum.KeyCode.LeftControl,
		JUMP = Enum.KeyCode.Space,
		DASH = Enum.KeyCode.Q,
	}),
	-- most seconds between the two taps of the sprint key
	DOUBLE_TAP = 0.25,

	-- offsets from the HumanoidRootPart centre, same for every R6 character
	ROOT_HEIGHT = 3,
	HEAD_Y = 1.5,
	KNEE_Y = -2,
	GROUND_RAY = 4,

	MOVE_BURST = 10,
	MOVE_REFILL = 8,
	SPEED_SAMPLE_INTERVAL = 0.25,
	SPEED_TOLERANCE = 1.25,
	SPEED_LAG_STUDS = 4,
	SPEED_BUCKET_MAX = 6,
	SPEED_BUCKET_DRAIN = 1.5,
	SPAWN_EXEMPT = 1.5,
	-- server side give, it sees every character slightly in the past
	PROBE_SLACK = 3,
	-- the server's probes also reach as far as the character moves in this many seconds
	PROBE_LAG = 0.15,
	PROBE_SLACK_MAX = 12,
	COOLDOWN_SLACK = 0.1,
	-- how long after the server last saw ground a Jump still counts, COYOTE plus a sample gap and ping
	GROUND_GRACE = 0.5,

	STAMINA_MAX = 100,
	STAMINA_REGEN = 15,
})
