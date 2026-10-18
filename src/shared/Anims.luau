--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local MoveDefs = require(script.Parent.MoveDefs)
local Types = require(script.Parent.Types)

-- "rbxassetid://..." made on an R6 rig and owned by the experience's owner, empty slots are skipped
-- priority is set in the animation editor, grouped below by the one each needs
local Anims: { [Types.AnimName]: string } = {
	-- Idle
	Idle = "rbxassetid://99836695944502",
	Fall = "rbxassetid://87938113594336",
	CrouchIdle = "rbxassetid://120819572969910",
	-- Movement
	Walk = "rbxassetid://84144179682608",
	Run = "rbxassetid://79577852813740",
	CrouchWalk = "rbxassetid://119276757875300",

	-- Action
	Slide = "rbxassetid://102374643545160",
	VaultLow = "rbxassetid://127756718825111",
	VaultMid = "rbxassetid://79521848275184",
	Jump = "rbxassetid://79956262533713",
	DoubleJump = "rbxassetid://105830003406496",
	SlideJump = "rbxassetid://135295565014032",
	WallRunLeft = "rbxassetid://116628350222963",
	WallRunRight = "rbxassetid://104913629506430",
	WallLeapLeft = "rbxassetid://103898545115791",
	WallLeapRight = "rbxassetid://105572157004127",
	WallCling = "rbxassetid://78068464202635",
	WallBoost = "rbxassetid://136022644832167",
	DashF = "rbxassetid://94356223480257",
	DashB = "rbxassetid://134294238611266",
	DashL = "rbxassetid://77340216112314",
	DashR = "rbxassetid://122209274211606",

	-- Action2, one shots over the Slide loop and whatever the slide ends in
	SlideIntro = "rbxassetid://116003744485924",
	SlideExit = "rbxassetid://88690341011809",
}

-- the old solver doesn't check the keys above, so a typo would just never play
local slots: { [string]: true } = {
	SlideIntro = true,
	SlideExit = true,
	WallRunLeft = true,
	WallRunRight = true,
	WallLeapLeft = true,
	WallLeapRight = true,
	DashF = true,
	DashB = true,
	DashL = true,
	DashR = true,
}
for state: string in MoveDefs do
	if state ~= "WallRun" and state ~= "WallLeap" then
		slots[state] = true
	end
end
for name: string in Anims do
	assert(slots[name], `no animation slot called {name}`)
end

return table.freeze(Anims)
