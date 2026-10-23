--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local MoveDefs = require(script.Parent.MoveDefs)
local Types = require(script.Parent.Types)

local SLOTS: { [string]: true } = {
	WallRunLeft = true,
	WallRunRight = true,
	WallLeapLeft = true,
	WallLeapRight = true,
	Roll = true,
	LedgeLeap2 = true,
	LedgeLeap3 = true,
	LedgeLeap4 = true,
	RampLeap = true,
	AirDash = true,
	DashCancelLeft = true,
	DashCancelRight = true,
}
for state in MoveDefs do
	SLOTS[state] = true
end

local Anims: { [Types.AnimName]: string } = {
	Idle = "rbxassetid://135449190200569",
	Walk = "rbxassetid://87539854939325",
	Run = "rbxassetid://97365671049008",
	Jump = "rbxassetid://91804113405885",
	Slide = "rbxassetid://131338188389559",
	SlideJump = "rbxassetid://87854361282454",
	CrouchIdle = "rbxassetid://118920925691918",
	CrouchWalk = "rbxassetid://126287311643867",
	WallRunLeft = "rbxassetid://117494238825220",
	WallRunRight = "rbxassetid://136658778996572",
	Fall = "rbxassetid://127049077162885",
	DoubleJump = "rbxassetid://139618742088489",
	WallCling = "rbxassetid://130191404882056",
	WallBoost = "rbxassetid://113668530383382",
	WallLeapLeft = "rbxassetid://78730538514260",
	WallLeapRight = "rbxassetid://101600913178855",
	Mantle = "rbxassetid://137171835971660",
	DashB = "rbxassetid://132820400906047",
	DashF = "rbxassetid://138725257049301",
	DashL = "rbxassetid://90778754431207",
	DashR = "rbxassetid://99540956567959",
	AirDash = "rbxassetid://133986443424200",
	DashCancelLeft = "rbxassetid://131903606548694",
	DashCancelRight = "rbxassetid://121599177700450",
	Roll = "rbxassetid://120431676333500",
	LedgeLeap = "rbxassetid://90219606237010",
	LedgeLeap2 = "rbxassetid://120588070311007",
	LedgeLeap3 = "rbxassetid://117907258676401",
	LedgeLeap4 = "rbxassetid://116062349274028",
	RampLeap = "rbxassetid://91426030301349",
}

-- the old solver doesn't check keys in the table above, so a typo would just never play
for name: string in Anims do
	assert(SLOTS[name], `no state or slot called {name}`)
end

return table.freeze(Anims)
