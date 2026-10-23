--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)

export type Action = "Sprint" | "Crouch" | "Jump" | "Dash" | "DashCancel" | "Light" | "Heavy" | "Block"

local SPRINT: Action = "Sprint"
local CROUCH: Action = "Crouch"
local DASH_CANCEL: Action = "DashCancel"

-- above the default controls and sunk, so Space never jumps the humanoid
local PRIORITY = Enum.ContextActionPriority.High.Value

-- Light is the mouse button, the rest are keys
local BINDS: { [Action]: Enum.KeyCode | Enum.UserInputType } = {
	Crouch = Config.KEYS.CROUCH,
	Jump = Config.KEYS.JUMP,
	Dash = Config.KEYS.DASH,
	Light = Config.KEYS.LIGHT,
	Heavy = Config.KEYS.HEAVY,
	Block = Config.KEYS.BLOCK,
}

-- first held key wins, so W and D together is a forward dash
local DASH_KEYS: { { key: Enum.KeyCode, state: Types.MoveState } } = {
	{ key = Enum.KeyCode.W, state = "DashF" },
	{ key = Enum.KeyCode.A, state = "DashL" },
	{ key = Enum.KeyCode.S, state = "DashB" },
	{ key = Enum.KeyCode.D, state = "DashR" },
}

local InputController = {}

local held: { [Action]: boolean } = {}
local pressed: { [Action]: boolean } = {}
local lastTap = 0

function InputController.isDown(action: Action): boolean
	return held[action] == true
end

function InputController.take(action: Action): boolean
	local was = pressed[action] == true
	pressed[action] = nil
	return was
end

-- a press nothing took this step is dropped, not kept for later
function InputController.flush()
	table.clear(pressed)
end

function InputController.dash(): Types.MoveState
	for _, bind in DASH_KEYS do
		if UserInputService:IsKeyDown(bind.key) then
			return bind.state
		end
	end
	return "DashB"
end

-- crouch is a toggle, and standing up to jump or sprint turns it off
for action: Action, key in BINDS do
	ContextActionService:BindActionAtPriority(`Move{action}`, function(_, inputState: Enum.UserInputState)
		if inputState == Enum.UserInputState.Begin then
			held[action] = if action == CROUCH then not held[CROUCH] else true
			pressed[action] = true
			if action == "Jump" then
				held[CROUCH] = nil
			end
		elseif action ~= CROUCH then
			held[action] = nil
		end
		return Enum.ContextActionResult.Sink
	end, false, PRIORITY, key)
end

-- the sprint key also walks and right mouse also turns the camera, so both are watched without sinking them
UserInputService.InputBegan:Connect(function(input: InputObject, isProcessed: boolean)
	if isProcessed then
		return
	elseif input.UserInputType == Config.KEYS.DASH_CANCEL then
		pressed[DASH_CANCEL] = true
		return
	elseif input.KeyCode ~= Config.KEYS.SPRINT then
		return
	end
	local now = os.clock()
	if now - lastTap <= Config.DOUBLE_TAP then
		held[SPRINT] = true
		held[CROUCH] = nil
	end
	lastTap = now
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.KeyCode == Config.KEYS.SPRINT then
		held[SPRINT] = nil
	end
end)

-- a key let go while the window is unfocused never sends an End
UserInputService.WindowFocusReleased:Connect(function()
	table.clear(held)
end)

return InputController
