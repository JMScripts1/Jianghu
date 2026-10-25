--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local WeaponDefs = require(ReplicatedStorage.Shared.Combat.WeaponDefs)

-- made in Studio, Rojo only syncs scripts
local models = ServerStorage:FindFirstChild("Weapons")

local WeaponModels = {}

-- the model each character has in its hand
local held: { [Model]: Model } = {}

-- the model brings the Motor6D it was posed with on a rig's right arm, Part1 on its handle and C0 and C1 as it sat
-- there. every R6 arm is the same size, so only Part0 changes, and the joint stays in the model so it goes with it
function WeaponModels.hold(char: Model, weapon: Types.WeaponId)
	local old = held[char]
	if old then
		old:Destroy()
		held[char] = nil
	end
	local name = WeaponDefs[weapon].model
	if not name then
		return
	end

	local source = if models then models:FindFirstChild(name) else nil
	local model = if source and source:IsA("Model") then source:Clone() else nil
	local joint = if model then model:FindFirstChildWhichIsA("Motor6D", true) else nil
	local handle = if joint then joint.Part1 else nil
	local arm = char:FindFirstChild("Right Arm")
	if
		not model
		or not joint
		or not handle
		or not handle:IsDescendantOf(model)
		or not arm
		or not arm:IsA("BasePart")
	then
		warn("no model with a Motor6D on its handle in ServerStorage.Weapons for", weapon)
		return
	end

	for _, inst in model:GetDescendants() do
		-- free models hide backdoors, and a script in a character runs
		if inst:IsA("LuaSourceContainer") then
			inst:Destroy()
		elseif inst:IsA("BasePart") then
			-- never weighs the character down, and only roots are ever hit
			inst.Anchored = false
			inst.Massless = true
			inst.CanCollide = false
			inst.CanQuery = false
			inst.CanTouch = false
		end
	end
	joint.Part0 = arm
	model.Parent = char
	held[char] = model
end

-- the model itself goes with the character
function WeaponModels.remove(char: Model)
	held[char] = nil
end

return WeaponModels
