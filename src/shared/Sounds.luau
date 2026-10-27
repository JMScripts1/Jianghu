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
local Hits: { [Types.HitType]: { [Types.HitFx]: Types.SoundSlot } } = {
	Blunt = {
		Hit = "",
		HeavyHit = "",
		Block = "",
	},
	Slash = {
		Hit = "",
		HeavyHit = "",
		Block = "",
	},
}

-- the whoosh of every swing as it comes through, hit or miss, by the attacking weapon's hit type. an empty one plays
-- GenericSwing
local Swings: { [Types.HitType]: Types.SoundSlot } = {
	Blunt = { "", "", "" },
	Slash = "",
}

-- the same for every weapon. Delay is the charge a held swing makes
local Shared: { [Types.SharedFx]: Types.SoundSlot } = {
	Parry = { "rbxassetid://74187740395150", "rbxassetid://130145352629864", "rbxassetid://95707278240429" },
	Break = "",
	WallSlam = "rbxassetid://126221270237387",
	FloorSlam = "rbxassetid://113950757735761",
	Delay = "",
}

for _, sounds in Hits do
	table.freeze(sounds)
end

return table.freeze({
	Movement = table.freeze(Movement),
	Hits = table.freeze(Hits),
	Shared = table.freeze(Shared),
	Swings = table.freeze(Swings),
	-- any hit type's swing with none of its own
	GenericSwing = "" :: Types.SoundSlot,
	-- once at the body when a hit bleeds, the same for every weapon
	BloodSpill = {
		"",
		"",
		"",
	} :: Types.SoundSlot,
	-- where each drop lands, several a hit, so a quiet one
	BloodLand = "" :: Types.SoundSlot,
})
