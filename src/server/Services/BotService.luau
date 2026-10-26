--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatDefs = require(ReplicatedStorage.Shared.Combat.CombatDefs)
local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Brain = require(script.Parent.Parent.Bot.Brain)
local Motor = require(script.Parent.Parent.Bot.Motor)
local NpcAnimator = require(script.Parent.Parent.Combat.NpcAnimator)
local CharacterService = require(script.Parent.CharacterService)
local CombatService = require(script.Parent.CombatService)
local StateService = require(script.Parent.StateService)

local TAG = "Bot"
local DEFAULT_LEVEL: Types.BotLevel = "Normal"

-- sparring bots, tagged Bot in the place or spawned from the admin menu. they go through the same services players
-- do, so a bot can do nothing a player can't. what it decides is in Bot.Brain, how it moves in Bot.Motor. see the bot
-- outline
local BotService = {}

local bots: { [Model]: Brain.Mind } = {}
-- built once from a blank description the first time one is spawned, so the place needs no model for it
local template: Model? = nil

-- the menu's bots go in here, and the difficulty and weapon it last set sit on it so the menu can show them
local spawned = Instance.new("Folder")
spawned.Name = "Bots"
spawned:SetAttribute("Difficulty", DEFAULT_LEVEL)
spawned:SetAttribute("Weapon", CombatDefs.defaultWeapon)
spawned.Parent = workspace

-- the nearest living player in range, or failing that the nearest other bot, so two bots fight each other
local function target(model: Model, root: BasePart): Model?
	local best: Model? = nil
	local bestDist = Config.BOT_RANGE
	for _, plr in Players:GetPlayers() do
		local char = plr.Character
		local other = if char then StateService.liveRoot(char) else nil
		local dist = if other then (other.Position - root.Position).Magnitude else math.huge
		if other and dist < bestDist then
			best, bestDist = char, dist
		end
	end
	if best then
		return best
	end
	for other in bots do
		local otherRoot = if other ~= model then StateService.liveRoot(other) else nil
		local dist = if otherRoot then (otherRoot.Position - root.Position).Magnitude else math.huge
		if otherRoot and dist < bestDist then
			best, bestDist = other, dist
		end
	end
	return best
end

local function check(model: Model)
	local level = model:GetAttribute("Difficulty")
	if level ~= nil and not Brain.isLevel(level) then
		warn("no bot difficulty called", level, model:GetFullName())
	end
	local weapon = model:GetAttribute("Weapon")
	if weapon ~= nil and not CombatDefs.weapon(weapon) then
		warn("no weapon called", weapon, model:GetFullName())
	end
end

local function step(model: Model, mind: Brain.Mind, now: number)
	local st = StateService.get(model)
	local root = StateService.liveRoot(model)
	if not st or not root then
		return
	end
	-- the same attribute CombatService publishes the weapon on, so setting it in Studio asks for a swap. refused mid
	-- swing or stunned, so it's asked again every tick until it goes through
	local weapon: Types.WeaponId? = CombatDefs.weapon(model:GetAttribute("Weapon"))
	if weapon and weapon ~= st.combat.weapon then
		CombatService.equip(model, weapon)
	end
	Brain.step(model, mind, target(model, root), Brain.skill(model), now)
	Motor.step(mind.body, now)
end

local function add(inst: Instance)
	if not inst:IsA("Model") or not inst:IsDescendantOf(workspace) or bots[inst] then
		return
	end
	local hum = inst:FindFirstChildOfClass("Humanoid")
	local root = StateService.liveRoot(inst)
	if not hum or not root then
		warn("bot needs a living Humanoid and a HumanoidRootPart", inst:GetFullName())
		return
	end

	-- owned by the server, or a player standing next to it could take it over and fling it
	if root:CanSetNetworkOwnership() then
		root:SetNetworkOwner(nil)
	end

	-- a grip kills it, so it comes back fresh where it stood, from a copy taken before anything was added to it
	local fresh = inst:Clone()
	local home = inst.Parent
	hum.Died:Connect(function()
		task.delay(Config.BOT_RESPAWN, function()
			-- cleared from the menu while it lay dead
			if not inst:IsDescendantOf(workspace) then
				return
			end
			-- the difficulty and weapon it was switched to in Studio, not the ones it started with
			fresh:SetAttribute("Difficulty", inst:GetAttribute("Difficulty"))
			fresh:SetAttribute("Weapon", inst:GetAttribute("Weapon"))
			inst:Destroy()
			fresh.Parent = home
		end)
	end)

	-- setting up publishes the default weapon over the one it was placed with, so that one is asked for again after
	local placed = inst:GetAttribute("Weapon")
	CharacterService.add(inst)
	NpcAnimator.add(inst, hum, root)
	if placed ~= nil then
		inst:SetAttribute("Weapon", placed)
	end
	check(inst)
	inst:GetAttributeChangedSignal("Difficulty"):Connect(function()
		check(inst)
	end)
	inst:GetAttributeChangedSignal("Weapon"):Connect(function()
		check(inst)
	end)

	bots[inst] = Brain.new(Motor.new(inst, hum, root), workspace:GetServerTimeNow())
end

local function remove(inst: Instance)
	local mind = if inst:IsA("Model") then bots[inst] else nil
	if mind then
		bots[inst :: Model] = nil
		Motor.remove(mind.body)
		NpcAnimator.remove(inst :: Model)
		CharacterService.remove(inst :: Model)
	end
end

-- an R6 rig with nothing on it. the engine can fetch assets for it, so it's allowed to fail
local function rig(): Model?
	if template then
		return template
	end
	local ok, made = pcall(function()
		return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R6)
	end)
	if not ok or typeof(made) ~= "Instance" or not made:IsA("Model") then
		warn("couldn't build a bot rig", made)
		return nil
	end
	-- the engine puts its own Animate and Health scripts in, the bot has its own of both
	for _, part in made:GetDescendants() do
		if part:IsA("BaseScript") then
			part:Destroy()
		end
	end
	made.Name = "Bot"
	template = made
	return made
end

-- standing at the pose given, with the menu's difficulty and weapon. false once BOT_MAX are out
function BotService.spawn(at: CFrame): boolean
	if #spawned:GetChildren() >= Config.BOT_MAX then
		return false
	end
	local base = rig()
	if not base then
		return false
	end
	local bot = base:Clone()
	bot:SetAttribute("Difficulty", spawned:GetAttribute("Difficulty"))
	bot:SetAttribute("Weapon", spawned:GetAttribute("Weapon"))
	bot:PivotTo(at)
	bot:AddTag(TAG)
	bot.Parent = spawned
	return true
end

function BotService.clear()
	spawned:ClearAllChildren()
end

-- a remote's string back to a difficulty, nil when it names none
function BotService.level(value: unknown): Types.BotLevel?
	return if Brain.isLevel(value) then value :: Types.BotLevel else nil
end

-- every bot takes it, the placed ones too, and the menu's next ones spawn with it
function BotService.setDifficulty(level: Types.BotLevel)
	spawned:SetAttribute("Difficulty", level)
	for model in bots do
		model:SetAttribute("Difficulty", level)
	end
end

function BotService.setWeapon(weapon: Types.WeaponId)
	spawned:SetAttribute("Weapon", weapon)
	for model in bots do
		model:SetAttribute("Weapon", weapon)
	end
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(add)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(remove)
for _, inst in CollectionService:GetTagged(TAG) do
	add(inst)
end

task.spawn(function()
	while true do
		task.wait(Config.BOT_TICK)
		local now = workspace:GetServerTimeNow()
		for model, mind in bots do
			step(model, mind, now)
		end
	end
end)

return BotService
