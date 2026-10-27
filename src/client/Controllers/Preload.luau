--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Anims = require(ReplicatedStorage.Shared.Movement.Anims)
local AttackDefs = require(ReplicatedStorage.Shared.Combat.AttackDefs)
local Config = require(ReplicatedStorage.Shared.Config)
local Footsteps = require(ReplicatedStorage.Shared.Movement.Footsteps)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local Types = require(ReplicatedStorage.Shared.Types)
local WeaponDefs = require(ReplicatedStorage.Shared.Combat.WeaponDefs)

-- everything a fight plays, asked for the moment the client starts instead of the first time each is used. until an
-- animation arrives its track plays late and its Length reads 0, so a knockback or pin pose doesn't hold and a roll or
-- mantle runs at the wrong speed, and an effect's textures or a sound come out blank. it only moves these to the front
-- of the download queue, nothing waits on it. both clients need the other's animations too, so it's all of them
local Preload = {}

-- a content id only loads through an instance that holds it, a bare string is skipped
local function instances(ids: { [string]: true }, class: "Animation" | "Sound"): { Instance }
	local list: { Instance } = {}
	for id in ids do
		if class == "Animation" then
			local anim = Instance.new("Animation")
			anim.AnimationId = id
			table.insert(list, anim)
		else
			local sound = Instance.new("Sound")
			sound.SoundId = id
			table.insert(list, sound)
		end
	end
	return list
end

-- each id once, an empty one is a slot with nothing in it yet
local function add(set: { [string]: true }, id: string?)
	if id and id ~= "" then
		set[id] = true
	end
end

local function animationIds(): { [string]: true }
	local set: { [string]: true } = {}
	for _, id in Anims do
		add(set, id)
	end
	for _, def in AttackDefs do
		add(set, def.anim)
	end
	for _, weapon in WeaponDefs do
		for _, id in weapon.movement do
			add(set, id)
		end
		for _, list in weapon.reactions do
			for _, id in list do
				add(set, id)
			end
		end
		local grip = weapon.grip
		if grip then
			add(set, grip.anim)
			add(set, grip.victim)
		end
	end
	return set
end

local function soundIds(): { [string]: true }
	local set: { [string]: true } = {}
	for _, id in Sounds.Movement do
		add(set, id)
	end
	local function addSlot(ids: Types.SoundSlot)
		if type(ids) == "table" then
			for _, id in ids do
				add(set, id)
			end
		else
			add(set, ids)
		end
	end
	for _, slots in Sounds.Hits do
		for _, ids in slots do
			addSlot(ids)
		end
	end
	for _, ids in Sounds.Shared do
		addSlot(ids)
	end
	for _, ids in Sounds.Swings do
		addSlot(ids)
	end
	addSlot(Sounds.GenericSwing)
	addSlot(Sounds.BloodSpill)
	addSlot(Sounds.BloodLand)
	for _, id in Footsteps do
		add(set, id)
	end
	return set
end

task.spawn(function()
	-- the animations first, the code times poses by them. the effects folder brings every texture and mesh under it
	local list = instances(animationIds(), "Animation")
	table.insert(list, ReplicatedStorage:WaitForChild("Vfx"))
	for _, sound in instances(soundIds(), "Sound") do
		table.insert(list, sound)
	end

	local startedAt = os.clock()
	local failed = 0
	ContentProvider:PreloadAsync(list, function(id: string, status: Enum.AssetFetchStatus)
		if status ~= Enum.AssetFetchStatus.Success then
			failed += 1
			warn("couldn't preload", id, status.Name)
		end
	end)
	if Config.DEBUG then
		print(`preloaded in {math.round((os.clock() - startedAt) * 1000)} ms, {failed} failed`)
	end
end)

return Preload
