--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local MovementController = require(script.Parent.MovementController)

local InputController = {}

local lastTap = -math.huge

-- above the default controls, so Space never reaches the built in jump
local function bind(action: MovementController.Action, key: Enum.KeyCode)
	ContextActionService:BindActionAtPriority(action, function(_, inputState: Enum.UserInputState)
		if inputState == Enum.UserInputState.Begin then
			MovementController.action(action, true)
		elseif inputState == Enum.UserInputState.End then
			MovementController.action(action, false)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, key)
end

bind("Crouch", Config.KEYS.CROUCH)
bind("Jump", Config.KEYS.JUMP)
bind("Dash", Config.KEYS.DASH)

-- W goes through UserInputService unsunk, so it still walks
UserInputService.InputBegan:Connect(function(key, processed)
	if processed or key.KeyCode ~= Config.KEYS.SPRINT then
		return
	end
	local now = os.clock()
	if now - lastTap <= Config.DOUBLE_TAP then
		MovementController.action("Sprint", true)
	end
	lastTap = now
end)

UserInputService.InputEnded:Connect(function(key)
	if key.KeyCode == Config.KEYS.SPRINT then
		MovementController.action("Sprint", false)
	end
end)

return InputController
