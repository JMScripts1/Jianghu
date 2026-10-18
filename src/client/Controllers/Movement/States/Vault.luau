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
		local out = Vector3.new(hit.normal.X, 0, hit.normal.Z).Unit
		local edge = hit.point + out * Config.LEDGE_DEPTH
		points = { start, edge + out * Config.LEDGE_PLANT_OUT + Vector3.yAxis * Config.LEDGE_PLANT_UP, over }
		-- square to the ledge, not wherever the cling left us looking
		forward = -out
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
	local start, mid, finish = points[1], points[2], points[3]
	if ctx.state == "VaultLow" then
		align.Position = if t < 0.5 then start:Lerp(mid, t * 2) else mid:Lerp(finish, t * 2 - 1)
	else
		-- the VaultMid animation plants its hands on the lip halfway through, so the curve passes there at the midpoint
		local bend = mid * 2 - (start + finish) / 2
		local u = 1 - t
		align.Position = start * (u * u) + bend * (2 * t * u) + finish * (t * t)
	end
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
