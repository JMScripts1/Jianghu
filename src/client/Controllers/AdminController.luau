--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local WeaponDefs = require(ReplicatedStorage.Shared.Combat.WeaponDefs)

local GUTTER = 16
local PADDING = 8
local GAP = 4
local WIDTH = 120
local BUTTON_HEIGHT = 24
local BACKGROUND = Color3.fromRGB(18, 18, 18)
local BUTTON = Color3.fromRGB(40, 40, 40)
local HELD = Color3.fromRGB(225, 225, 225)
local TEXT = Color3.fromRGB(235, 235, 235)
local HELD_TEXT = Color3.fromRGB(18, 18, 18)
local MUTED = Color3.fromRGB(150, 150, 150)

local player = Players.LocalPlayer

local AdminController = {}

-- the server checks again, this only keeps the menu off everyone else's screen
if not (RunService:IsStudio() or table.find(Config.ADMINS, player.UserId)) then
	return AdminController
end

local buttons: { [Types.WeaponId]: TextButton } = {}
local conn: RBXScriptConnection? = nil

local function corner(parent: GuiObject)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 4)
	c.Parent = parent
end

local gui = Instance.new("ScreenGui")
gui.Name = "AdminUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 100

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(1, 1)
panel.Position = UDim2.new(1, -GUTTER, 1, -GUTTER)
panel.Size = UDim2.new()
panel.AutomaticSize = Enum.AutomaticSize.XY
panel.BackgroundColor3 = BACKGROUND
panel.BackgroundTransparency = 0.25
panel.BorderSizePixel = 0
corner(panel)
panel.Parent = gui

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, PADDING)
padding.PaddingBottom = UDim.new(0, PADDING)
padding.PaddingLeft = UDim.new(0, PADDING)
padding.PaddingRight = UDim.new(0, PADDING)
padding.Parent = panel

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, GAP)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.fromOffset(WIDTH, 16)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamMedium
title.TextSize = 12
title.TextColor3 = MUTED
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Weapon"
title.Parent = panel

-- sorted, so the order doesn't change between sessions
local ids: { Types.WeaponId } = {}
for weapon: Types.WeaponId in WeaponDefs do
	table.insert(ids, weapon)
end
table.sort(ids)

for i, weapon: Types.WeaponId in ids do
	local button = Instance.new("TextButton")
	button.LayoutOrder = i
	button.Size = UDim2.fromOffset(WIDTH, BUTTON_HEIGHT)
	button.BackgroundColor3 = BUTTON
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamMedium
	button.TextSize = 14
	button.TextColor3 = TEXT
	button.Text = weapon
	corner(button)
	button.Parent = panel
	button.Activated:Connect(function()
		Remotes.Equip:FireServer(weapon)
	end)
	buttons[weapon] = button
end

-- lit from the attribute the server sets, so a refused swap leaves the old one lit
local function show(char: Model)
	local held = char:GetAttribute("Weapon")
	for weapon, button in buttons do
		local isHeld = weapon == held
		button.BackgroundColor3 = if isHeld then HELD else BUTTON
		button.TextColor3 = if isHeld then HELD_TEXT else TEXT
	end
end

local function onCharacterAdded(char: Model)
	if conn then
		conn:Disconnect()
	end
	conn = char:GetAttributeChangedSignal("Weapon"):Connect(function()
		show(char)
	end)
	show(char)
end

UserInputService.InputBegan:Connect(function(input, isProcessed)
	if not isProcessed and input.KeyCode == Config.KEYS.ADMIN_MENU then
		gui.Enabled = not gui.Enabled
	end
end)
player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	onCharacterAdded(player.Character)
end

gui.Parent = player:WaitForChild("PlayerGui")

return AdminController
