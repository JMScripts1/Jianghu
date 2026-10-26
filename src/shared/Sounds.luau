--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local Types = require(script.Parent.Types)

-- an empty id is a slot with no sound yet, it plays nothing
local Movement: { [Types.SoundName]: string } = {
	Jump = "",
	DoubleJump = "rbxassetid://113971697134227",
	SlideJump = "",
	LedgeLeap = "rbxassetid://689786169",
	Dash = "rbxassetid://101472633081729",
	Land = "",
	Slide = "rbxassetid://101177667565550",
	WallRun = "rbxassetid://18782450319",
	WallLeap = "rbxassetid://120666632097409",
	WallCling = "",
	WallBoost = "",
	Mantle = "",
}

-- from the attacking weapon's hit type, the same split as the effects in assets/Vfx.rbxm
local Hits: { [Types.HitType]: { [Types.HitFx]: string } } = {
	Blunt = {
		Hit = "",
		HeavyHit = "",
		Block = "",
		Parry = "",
	},
	Slash = {
		Hit = "",
		HeavyHit = "",
		Block = "",
		Parry = "",
	},
}

-- Delay is the charge a held swing makes
local Shared: { [Types.SharedFx]: string } = {
	Break = "",
	WallSlam = "",
	FloorSlam = "",
	Delay = "",
}

for _, sounds in Hits do
	table.freeze(sounds)
end

return table.freeze({
	Movement = table.freeze(Movement),
	Hits = table.freeze(Hits),
	Shared = table.freeze(Shared),
})
