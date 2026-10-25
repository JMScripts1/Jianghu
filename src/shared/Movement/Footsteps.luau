--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local PLASTIC = "rbxassetid://7326203155"
local GRASS = "rbxassetid://507863105"
local METAL = "rbxassetid://6876957898"
local WOOD = "rbxassetid://507863457"
local CONCRETE = "rbxassetid://5761648082"
local FABRIC = "rbxassetid://6240702531"
local SAND = "rbxassetid://265653329"
local GLASS = "rbxassetid://9117949159"

-- the floor's material picks the sound, see EffectController for anything not listed
local Footsteps: { [Enum.Material]: string } = {
	[Enum.Material.SmoothPlastic] = PLASTIC,
	[Enum.Material.ForceField] = PLASTIC,
	[Enum.Material.Foil] = PLASTIC,
	[Enum.Material.Plastic] = PLASTIC,

	[Enum.Material.WoodPlanks] = WOOD,
	[Enum.Material.Wood] = WOOD,

	[Enum.Material.Ground] = FABRIC,
	[Enum.Material.Fabric] = FABRIC,

	[Enum.Material.DiamondPlate] = METAL,
	[Enum.Material.CorrodedMetal] = METAL,
	[Enum.Material.Metal] = METAL,

	[Enum.Material.LeafyGrass] = GRASS,
	[Enum.Material.Grass] = GRASS,
	[Enum.Material.Mud] = GRASS,
	[Enum.Material.Snow] = GRASS,
	[Enum.Material.Glacier] = GRASS,

	[Enum.Material.Pavement] = CONCRETE,
	[Enum.Material.Limestone] = CONCRETE,
	[Enum.Material.Salt] = CONCRETE,
	[Enum.Material.Asphalt] = CONCRETE,
	[Enum.Material.Neon] = CONCRETE,
	[Enum.Material.CrackedLava] = CONCRETE,
	[Enum.Material.Basalt] = CONCRETE,
	[Enum.Material.Sandstone] = CONCRETE,
	[Enum.Material.Rock] = CONCRETE,
	[Enum.Material.Cobblestone] = CONCRETE,
	[Enum.Material.Pebble] = CONCRETE,
	[Enum.Material.Brick] = CONCRETE,
	[Enum.Material.Granite] = CONCRETE,
	[Enum.Material.Marble] = CONCRETE,
	[Enum.Material.Ice] = CONCRETE,
	[Enum.Material.Slate] = CONCRETE,
	[Enum.Material.Concrete] = CONCRETE,

	[Enum.Material.Sand] = SAND,
	[Enum.Material.Glass] = GLASS,
}

return table.freeze(Footsteps)
