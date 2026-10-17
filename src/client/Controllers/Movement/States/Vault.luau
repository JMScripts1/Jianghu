--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Context = require(script.Parent.Parent.Context)

local Vault = {}

-- start, over the lip, then the landing spot
local points: { Vector3 } = {}
local mover: AlignPosition? = nil
-- also in the character's trove, so dying mid vault still cleans them
local made: { Instance } = {}

function Vault.enter(ctx: Context.Context)
	local hit = ctx.vaultHit :: Types.VaultHit
	local root = ctx.root
	local look = root.CFrame.LookVector
	local forward = Vector3.new(look.X, 0, look.Z).Unit
	local start = root.Position
	local over = hit.point + Vector3.yAxis * Config.ROOT_HEIGHT

	-- a death mid vault skips exit, the trove already destroyed whatever is left in here
	table.clear(made)

	if ctx.state == "VaultLow" then
		ctx.momentum += Context.gain(ctx, "VaultLow", ctx.momentum * (Config.VAULT_BOOST - 1))
		points = { start, over, over + forward * Config.HEADROOM_REACH }
	else
		ctx.momentum = Config.WALK_SPEED
		points = { start, Vector3.new(start.X, over.Y, start.Z), over }
	end

	for _, part in ctx.char:GetChildren() do
		if part:IsA("BasePart") then
			local ignore = ctx.trove:Add(Instance.new("NoCollisionConstraint"))
			ignore.Part0 = part
			ignore.Part1 = hit.part
			ignore.Parent = part
			table.insert(made, ignore)
		end
	end

	local align = ctx.trove:Add(Instance.new("AlignPosition"))
	align.Mode = Enum.PositionAlignmentMode.OneAttachment
	align.Attachment0 = ctx.attachment
	align.MaxForce = math.huge
	align.Responsiveness = Config.MOVER_RESPONSIVENESS
	align.Position = start
	align.Parent = root
	table.insert(made, align)

	mover = align
	ctx.hum.PlatformStand = true
	Context.face(ctx, forward)
end

function Vault.update(ctx: Context.Context, _: number): Types.MoveState?
	local duration = if ctx.state == "VaultLow" then Config.VAULT_LOW_TIME else Config.VAULT_MID_TIME
	local t = (os.clock() - ctx.since) / duration
	if t >= 1 then
		return if ctx.state == "VaultLow" and ctx.input.sprint then "Run" else "Walk"
	end

	local align = mover :: AlignPosition
	align.Position = if t < 0.5 then points[1]:Lerp(points[2], t * 2) else points[2]:Lerp(points[3], t * 2 - 1)
	return nil
end

function Vault.exit(ctx: Context.Context)
	for _, inst in made do
		ctx.trove:Remove(inst)
	end
	table.clear(made)
	mover = nil
	ctx.hum.PlatformStand = false
	Context.release(ctx)
end

return Vault
