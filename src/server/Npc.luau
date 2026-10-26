--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatDefs = require(ReplicatedStorage.Shared.Combat.CombatDefs)
local Types = require(ReplicatedStorage.Shared.Types)
local NpcAnimator = require(script.Parent.Combat.NpcAnimator)
local CharacterService = require(script.Parent.Services.CharacterService)
local CombatService = require(script.Parent.Services.CombatService)
local StateService = require(script.Parent.Services.StateService)

-- the Weapon attribute is the one CombatService publishes on, so setting it in Studio asks for a swap
local WEAPON = "Weapon"

export type Parts = { model: Model, hum: Humanoid, root: BasePart }

-- every rig the server runs, dummies and bots alike, comes in the same way: owned by the server, set up like a
-- player's character, and back fresh where it stood after a grip kills it. what each kind does is its own service's
local Npc = {}

local function checkWeapon(model: Model)
	local weapon = model:GetAttribute(WEAPON)
	if weapon ~= nil and not CombatDefs.weapon(weapon) then
		warn("no weapon called", weapon, model:GetFullName())
	end
end

-- nil for anything that can't be one. kind names it in the warning, and keep lists the attributes a respawn takes
-- from the one that died, the weapon always among them, so what was switched in Studio outlives it
function Npc.add(inst: Instance, kind: string, respawn: number, keep: { string }): Parts?
	if not inst:IsA("Model") or not inst:IsDescendantOf(workspace) then
		return nil
	end
	local hum = inst:FindFirstChildOfClass("Humanoid")
	local root = StateService.liveRoot(inst)
	if not hum or not root then
		warn(kind, "needs a living Humanoid and a HumanoidRootPart", inst:GetFullName())
		return nil
	end

	-- owned by the server, or a player standing next to it could take it over and fling it
	if root:CanSetNetworkOwnership() then
		root:SetNetworkOwner(nil)
	end

	-- the copy is taken before anything is added to it
	local fresh = inst:Clone()
	local home = inst.Parent
	hum.Died:Connect(function()
		task.delay(respawn, function()
			-- cleared away while it lay dead
			if not inst:IsDescendantOf(workspace) then
				return
			end
			fresh:SetAttribute(WEAPON, inst:GetAttribute(WEAPON))
			for _, name in keep do
				fresh:SetAttribute(name, inst:GetAttribute(name))
			end
			inst:Destroy()
			fresh.Parent = home
		end)
	end)

	-- setting up publishes the default weapon over the one it was placed with, so that one is asked for again after
	local placed = inst:GetAttribute(WEAPON)
	CharacterService.add(inst)
	NpcAnimator.add(inst, hum, root)
	if placed ~= nil then
		inst:SetAttribute(WEAPON, placed)
	end
	checkWeapon(inst)
	inst:GetAttributeChangedSignal(WEAPON):Connect(function()
		checkWeapon(inst)
	end)
	return { model = inst, hum = hum, root = root }
end

function Npc.remove(model: Model)
	NpcAnimator.remove(model)
	CharacterService.remove(model)
end

-- a swap is refused mid swing or stunned, so it's asked for again every tick until it goes through
function Npc.equip(model: Model, st: StateService.CharState)
	local weapon: Types.WeaponId? = CombatDefs.weapon(model:GetAttribute(WEAPON))
	if weapon and weapon ~= st.combat.weapon then
		CombatService.equip(model, weapon)
	end
end

return Npc
