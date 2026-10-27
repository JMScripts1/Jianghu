--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)

-- the folders in assets/Vfx.rbxm, a hit type's own and the ones everyone shares. Swing's are named by the attacks
export type Group = Types.HitType | "Movement" | "Shared" | "Swing" | "Blood"

-- picked in Studio and saved over assets/Vfx.rbxm, see the effects plan. an empty slot plays nothing
local templates = ReplicatedStorage:WaitForChild("Vfx")

-- a one shot is cleaned up this long after its last particle should have gone
local LINGER = 0.5

-- an effect is a Part holding attachments and emitters, or a bare Attachment holding emitters, nearly all switched
-- off. EmitCount bursts once, EmitDuration switches the emitter on at its Rate for that long, and both wait EmitDelay
-- first. one function plays any of them, and only on the client, the server never builds an effect. what plays where
-- is MoveFx's and CombatFx's
local Vfx = {}

local folder = Instance.new("Folder")
folder.Name = "Effects"
folder.Parent = workspace

local warned: { [string]: true } = {}

local function number(inst: Instance, name: string): number
	local value = inst:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

local function fire(emitter: ParticleEmitter, count: number, duration: number)
	-- cleaned up already
	if not emitter.Parent then
		return
	end
	if count > 0 then
		emitter:Emit(count)
	end
	if duration > 0 then
		emitter.Enabled = true
		task.delay(duration, function()
			emitter.Enabled = false
		end)
	end
end

-- emitting before the clone is in the world does nothing, so this runs after it's parented. returns how long until
-- the last particle is gone
local function emit(holder: Instance): number
	local last = 0
	for _, inst in holder:GetDescendants() do
		if not inst:IsA("ParticleEmitter") then
			continue
		end
		local delay = number(inst, "EmitDelay")
		local count = number(inst, "EmitCount")
		local duration = number(inst, "EmitDuration")
		last = math.max(last, delay + duration + inst.Lifetime.Max)
		if delay > 0 then
			task.delay(delay, fire, inst, count, duration)
		else
			fire(inst, count, duration)
		end
	end
	return last
end

-- a clone set around cf the way the template sat around its holder part. the holder only carries the emitters so
-- it's hidden, and no part of an effect is ever hit, stood on or queried
local function place(template: BasePart, cf: CFrame, isAnchored: boolean): BasePart
	local holder = template:Clone()
	local origin = holder.CFrame
	local offsets: { [BasePart]: CFrame } = { [holder] = CFrame.identity }
	for _, inst in holder:GetDescendants() do
		if inst:IsA("BasePart") then
			offsets[inst] = origin:ToObjectSpace(inst.CFrame)
		end
	end
	for part, offset in offsets do
		part.CFrame = cf * offset
		part.Anchored = isAnchored
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Massless = true
	end
	holder.Transparency = 1
	return holder
end

-- the holder rides on the part through a Weld, so a loop's offset can move, and the rest ride on the holder
local function weld(holder: BasePart, part: BasePart, offset: CFrame)
	local joint = Instance.new("Weld")
	joint.Part0 = part
	joint.Part1 = holder
	joint.C0 = offset
	joint.Parent = holder
	for _, inst in holder:GetDescendants() do
		if inst:IsA("BasePart") then
			local rest = Instance.new("WeldConstraint")
			rest.Part0 = holder
			rest.Part1 = inst
			rest.Parent = inst
		end
	end
end

-- a clone riding on `on` at offset, or left in the world at offset with no part, and where it goes. not parented yet.
-- an attachment sits in its parent's space, and Terrain sits at the origin, so one alone in the world goes there
local function make(template: Instance, on: BasePart?, offset: CFrame): (Instance, Instance)
	if template:IsA("BasePart") then
		local holder = place(template, if on then on.CFrame * offset else offset, on == nil)
		if on then
			weld(holder, on, offset)
		end
		return holder, folder
	end
	-- the only other kind Vfx.template hands out
	local made = template:Clone() :: Attachment
	made.CFrame = offset
	return made, on or workspace.Terrain
end

-- turns every flat particle round in its own plane, which no CFrame can, see Types.SwingFx
local function spin(holder: Instance, degrees: number)
	for _, inst in holder:GetDescendants() do
		if inst:IsA("ParticleEmitter") then
			local rotation = inst.Rotation
			inst.Rotation = NumberRange.new(rotation.Min + degrees, rotation.Max + degrees)
		end
	end
end

local function play(template: Instance?, on: BasePart?, offset: CFrame, degrees: number?)
	if not template then
		return
	end
	local made, parent = make(template, on, offset)
	if degrees then
		spin(made, degrees)
	end
	made.Parent = parent
	task.delay(emit(made) + LINGER, function()
		made:Destroy()
	end)
end

local function setLoop(holder: Instance, isOn: boolean)
	for _, inst in holder:GetDescendants() do
		if inst:IsA("ParticleEmitter") then
			inst.Enabled = isOn
		end
	end
end

-- up along the surface's normal, its front turned toward look as near as it can
function Vfx.surface(point: Vector3, normal: Vector3, look: Vector3): CFrame
	local right = look:Cross(normal)
	if right.Magnitude < 1e-3 then
		right = normal:Cross(if math.abs(normal.Y) < 0.9 then Vector3.yAxis else Vector3.zAxis)
	end
	return CFrame.fromMatrix(point, right.Unit, normal.Unit)
end

-- a slot holds a Part or an Attachment, or a Folder of them as variants, one picked at random each time
function Vfx.template(group: Group, name: string): Instance?
	local list = templates:FindFirstChild(group)
	local found = if list then list:FindFirstChild(name) else nil
	if found and found:IsA("Folder") then
		local variants = found:GetChildren()
		found = if #variants > 0 then variants[math.random(#variants)] else nil
	end
	if not found or found:IsA("BasePart") or found:IsA("Attachment") then
		return found
	end
	local path = `{group}/{name}`
	if not warned[path] then
		warned[path] = true
		warn("vfx", path, "has to be a Part, an Attachment or a Folder of them, not a", found.ClassName)
	end
	return nil
end

-- a copy of a part template set at cf, anchored and never hit, for the caller to move and destroy itself. nothing in
-- it is emitted, a trail draws on its own as it moves
function Vfx.part(template: BasePart, cf: CFrame): BasePart
	local holder = place(template, cf, true)
	holder.Parent = folder
	return holder
end

-- a one shot left where it happened
function Vfx.at(template: Instance?, cf: CFrame)
	play(template, nil, cf)
end

-- a one shot that rides along on a part, offset from it, its particles spun that many degrees in their own plane
function Vfx.on(template: Instance?, part: BasePart, offset: CFrame, degrees: number?)
	play(template, part, offset, degrees)
end

-- a loop kept on the part under name, made from the template the first time and only ever switched on and off at the
-- Rate set in Studio. the offset is set again each time, a wall run's wall can be on either side. an attachment's
-- offset is its own CFrame, a part's is its weld's
local function loopOf(template: Instance?, part: BasePart, name: string, offset: CFrame): Instance?
	local made = part:FindFirstChild(name)
	if made or not template then
		return made
	end
	local new = make(template, part, offset)
	new.Name = name
	new.Parent = part
	return new
end

function Vfx.loop(template: Instance?, part: BasePart, name: string, offset: CFrame)
	local holder = loopOf(template, part, name, offset)
	if not holder then
		return
	end
	if holder:IsA("Attachment") then
		holder.CFrame = offset
	else
		local joint = holder:FindFirstChildOfClass("Weld")
		if joint then
			joint.C0 = offset
		end
	end
	setLoop(holder, true)
end

function Vfx.stopLoop(part: BasePart, name: string)
	local holder = part:FindFirstChild(name)
	if holder then
		setLoop(holder, false)
	end
end

return Vfx
