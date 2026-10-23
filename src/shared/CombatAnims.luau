--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local Types = require(script.Parent.Types)

-- the loops play from a character's CombatState, the one shots when a hit it took part in resolves. a player's own
-- client plays them and the server plays an NPC's, everyone else sees them through replication.
-- every weapon plays these unless its moveset has its own. an empty id plays nothing
local CombatAnims: { [Types.Reaction]: Types.ReactionAnims } = {
	Parrying = "rbxassetid://111421663323177",
	Blocking = "rbxassetid://120953089487237",
	Stunned = "rbxassetid://136120702508483",
	PostureBroken = "rbxassetid://136120702508483",
	-- a downed character is a ragdoll, see Ragdoll. its pose waits for grips
	Downed = "",
	-- authored at Action2, a priority above the loops and swings, so they take over instead of blending in
	Parry = "",
	Deflected = "",
	BlockHit = "",
	-- every hit that doesn't knock back, taking turns
	Hurt = { "rbxassetid://137510119167669", "rbxassetid://119836976069798" },
	-- played by whoever a hit knocks back, the finisher and the heavy
	Knockback = "rbxassetid://73363607130187",
}

return table.freeze(CombatAnims)
