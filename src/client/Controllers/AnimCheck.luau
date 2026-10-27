--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AttackDefs = require(ReplicatedStorage.Shared.Combat.AttackDefs)
local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)

local FPS = 60
-- a frame either side, the editor snaps to them
local SLACK = 1 / FPS
local HIT = "Hit"
local DELAY = "Delay"

local AnimCheck = {}

if not Config.DEBUG then
	return AnimCheck
end

-- a named keyframe or an animation event, either marks the moment
local function times(seq: KeyframeSequence, name: string): { number }
	local found = {}
	for _, kf in seq:GetKeyframes() do
		if not kf:IsA("Keyframe") then
			continue
		end
		local isMarked = kf.Name == name
		for _, marker in kf:GetMarkers() do
			isMarked = isMarked or marker.Name == name
		end
		if isMarked then
			table.insert(found, kf.Time)
		end
	end
	table.sort(found)
	return found
end

local function frame(swingTime: number, def: Types.AttackDef): number
	return math.round(swingTime * def.speed * FPS)
end

-- the last keyframe is where the animation ends
local function length(seq: KeyframeSequence): number
	local last = 0
	for _, kf in seq:GetKeyframes() do
		if kf:IsA("Keyframe") then
			last = math.max(last, kf.Time)
		end
	end
	return last
end

-- a chain that ends a frame or more off its animation leaves it cut short or standing still. checked with or without
-- Hit keyframes, and it says the length to type
local function checkLength(id: Types.AttackId, seq: KeyframeSequence)
	local def = AttackDefs[id]
	local ends = 0
	local strike: Types.AttackId? = id
	while strike do
		local s = AttackDefs[strike]
		ends += s.windup + s.active + s.recovery
		strike = s.follow
	end
	local total = length(seq)
	local frames = math.round(total * FPS)
	if math.abs(ends * def.speed - total) > SLACK then
		warn(`{id} ends on frame {frame(ends, def)}, its animation is {frames} frames. set length = {frames}`)
	end
end

-- the nth Hit belongs to the nth strike of the chain. a hit only has to land inside its strike's active window, the
-- box opens a few frames early on purpose. a miss says the contact frame to type, a follow counts from the start of
-- the same animation too
local function check(id: Types.AttackId, seq: KeyframeSequence)
	local def = AttackDefs[id]
	local delay = times(seq, DELAY)[1]
	local delayAt = def.delayAt
	if delay and delayAt and math.abs(delay / def.speed - delayAt) > SLACK then
		local at = math.round(delay * FPS)
		warn(`{id} has its Delay on frame {at}, its delayAt is frame {frame(delayAt, def)}. set delayAt = {at} / 60`)
	end

	local hits = times(seq, HIT)
	local at = 0
	local strike: Types.AttackId? = id
	for _, hit in hits do
		if not strike then
			warn(`{id} has more Hit keyframes than strikes`)
			break
		end
		local s = AttackDefs[strike]
		local from, to = at + s.windup, at + s.windup + s.active
		local hitAt = hit / s.speed
		if hitAt < from - SLACK or hitAt > to + SLACK then
			local opens, closes, contact = frame(from, s), frame(to, s), math.round(hit * FPS)
			warn(
				`{strike} hits on frame {contact}, its box is open frames {opens} to {closes}. set contact = {contact}`
			)
		end
		at = to + s.recovery
		strike = s.follow
	end
end

-- every chain starts at an attack nothing follows, the follows are reached through it
local isFollow: { [Types.AttackId]: true } = {}
for _, def in AttackDefs do
	if def.follow then
		isFollow[def.follow] = true
	end
end

task.spawn(function()
	local seqs: { [string]: KeyframeSequence } = {}
	local unmarked = 0
	for id: Types.AttackId, def in AttackDefs do
		if isFollow[id] then
			continue
		elseif def.anim == "" then
			warn("no animation for", id)
			continue
		end

		local seq = seqs[def.anim]
		if not seq then
			local ok, result =
				pcall(KeyframeSequenceProvider.GetKeyframeSequenceAsync, KeyframeSequenceProvider, def.anim)
			if not ok then
				warn("couldn't load", def.anim, "for", id, result)
				continue
			end
			seq = result
			seqs[def.anim] = result
		end

		checkLength(id, seq)
		if #times(seq, HIT) == 0 then
			unmarked += 1
		else
			check(id, seq)
		end
	end
	if unmarked > 0 then
		warn(unmarked, "attacks have no Hit keyframe, so their timing isn't checked")
	end
end)

return AnimCheck
