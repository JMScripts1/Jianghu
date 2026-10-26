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
local WIDTH = 150
local BUTTON_HEIGHT = 24
local LABEL_HEIGHT = 16
local BACKGROUND = Color3.fromRGB(18, 18, 18)
local BUTTON = Color3.fromRGB(40, 40, 40)
local HELD = Color3.fromRGB(225, 225, 225)
local TEXT = Color3.fromRGB(235, 235, 235)
local HELD_TEXT = Color3.fromRGB(18, 18, 18)
local MUTED = Color3.fromRGB(150, 150, 150)

local LEVELS: { Types.BotLevel } = { "Easy", "Normal", "Hard" }

local player = Players.LocalPlayer

local AdminController = {}

-- the server checks again, this only keeps the menu off everyone else's screen
if not (RunService:IsStudio() or table.find(Config.ADMINS, player.UserId)) then
	return AdminController
end

-- each set is lit from an attribute the server sets, so a refused change leaves the old one lit
local weaponButtons: { [string]: TextButton } = {}
local levelButtons: { [string]: TextButton } = {}
local botWeaponButtons: { [string]: TextButton } = {}
local conn: RBXScriptConnection? = nil
local order = 0

local function nextOrder(): number
	order += 1
	return order
end

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

local function label(text: string)
	local title = Instance.new("TextLabel")
	title.LayoutOrder = nextOrder()
	title.Size = UDim2.fromOffset(WIDTH, LABEL_HEIGHT)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamMedium
	title.TextSize = 12
	title.TextColor3 = MUTED
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = text
	title.Parent = panel
end

local function button(parent: GuiObject, text: string, width: number, onPress: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.LayoutOrder = nextOrder()
	b.Size = UDim2.fromOffset(width, BUTTON_HEIGHT)
	b.BackgroundColor3 = BUTTON
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 14
	b.TextColor3 = TEXT
	b.Text = text
	corner(b)
	b.Parent = parent
	b.Activated:Connect(onPress)
	return b
end

-- buttons side by side, sharing the panel's width
local function row(texts: { string }, onPress: (string) -> ()): { [string]: TextButton }
	local frame = Instance.new("Frame")
	frame.LayoutOrder = nextOrder()
	frame.Size = UDim2.fromOffset(WIDTH, BUTTON_HEIGHT)
	frame.BackgroundTransparency = 1
	frame.Parent = panel

	local across = Instance.new("UIListLayout")
	across.FillDirection = Enum.FillDirection.Horizontal
	across.Padding = UDim.new(0, GAP)
	across.SortOrder = Enum.SortOrder.LayoutOrder
	across.Parent = frame

	local width = (WIDTH - GAP * (#texts - 1)) / #texts
	local made: { [string]: TextButton } = {}
	for _, text in texts do
		made[text] = button(frame, text, width, function()
			onPress(text)
		end)
	end
	return made
end

local function light(buttons: { [string]: TextButton }, value: unknown)
	for name, b in buttons do
		local isOn = name == value
		b.BackgroundColor3 = if isOn then HELD else BUTTON
		b.TextColor3 = if isOn then HELD_TEXT else TEXT
	end
end

local levels: { string } = {}
for _, level in LEVELS do
	table.insert(levels, level)
end

-- sorted, so the order doesn't change between sessions
local weapons: { string } = {}
for weapon: Types.WeaponId in WeaponDefs do
	table.insert(weapons, weapon)
end
table.sort(weapons)

label("Weapon")
for _, weapon in weapons do
	weaponButtons[weapon] = button(panel, weapon, WIDTH, function()
		Remotes.Equip:FireServer(weapon)
	end)
end

-- every bot fights at the difficulty and with the weapon picked here, and new ones spawn with them
label("Bots")
levelButtons = row(levels, function(level)
	Remotes.Bot:FireServer("Difficulty", level)
end)
botWeaponButtons = row(weapons, function(weapon)
	Remotes.Bot:FireServer("Weapon", weapon)
end)
row({ "Spawn", "Clear" }, function(action)
	Remotes.Bot:FireServer(action)
end)

local function onCharacterAdded(char: Model)
	if conn then
		conn:Disconnect()
	end
	conn = char:GetAttributeChangedSignal("Weapon"):Connect(function()
		light(weaponButtons, char:GetAttribute("Weapon"))
	end)
	light(weaponButtons, char:GetAttribute("Weapon"))
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

-- the server keeps the bot settings on the folder its menu bots go in, see BotService
task.spawn(function()
	local bots = workspace:WaitForChild("Bots")
	local function show()
		light(levelButtons, bots:GetAttribute("Difficulty"))
		light(botWeaponButtons, bots:GetAttribute("Weapon"))
	end
	bots:GetAttributeChangedSignal("Difficulty"):Connect(show)
	bots:GetAttributeChangedSignal("Weapon"):Connect(show)
	show()
end)

gui.Parent = player:WaitForChild("PlayerGui")

return AdminController
