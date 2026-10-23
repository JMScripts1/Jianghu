--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local Types = require(script.Parent.Types)

-- an empty id is a slot with no sound yet, it plays nothing
local Sounds: { [Types.SoundName]: string } = {
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

return table.freeze(Sounds)
