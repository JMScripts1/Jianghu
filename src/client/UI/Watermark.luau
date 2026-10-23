--!strict
-- Jianghu by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local Players = game:GetService("Players")

local WATERMARK_TEXT = "RUHA"
local COLS, ROWS = 9, 7
local CELL_W, CELL_H = 1 / COLS, 1 / ROWS

local player = Players.LocalPlayer

local Watermark = {}

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DevWatermarkUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 1000

local banner = Instance.new("TextLabel")
banner.Name = "WarningBanner"
banner.Size = UDim2.new(1, 0, 0, 40)
banner.Position = UDim2.new(0, 0, 0, 0)
banner.BackgroundTransparency = 1
banner.Text = "ASPECTS OF THIS GAME ARE STILL IN DEVELOPMENT, AND MAY NOT BE REPRESENTATIVE OF THE FINAL PRODUCT."
banner.TextColor3 = Color3.fromRGB(255, 255, 255)
banner.TextTransparency = 0.15
banner.Font = Enum.Font.GothamBold
banner.TextSize = 20
banner.TextXAlignment = Enum.TextXAlignment.Center
banner.ZIndex = 10
banner.Parent = screenGui

local watermarkHolder = Instance.new("Frame")
watermarkHolder.Name = "WatermarkHolder"
watermarkHolder.Size = UDim2.fromScale(1, 1)
watermarkHolder.BackgroundTransparency = 1
watermarkHolder.ZIndex = 1
watermarkHolder.Parent = screenGui

for row = 0, ROWS - 1 do
	for col = 0, COLS - 1 do
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(CELL_W, CELL_H)
		label.Position = UDim2.fromScale(col * CELL_W, row * CELL_H)
		label.Text = WATERMARK_TEXT
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.TextTransparency = 0.95
		label.Font = Enum.Font.GothamBold
		label.TextSize = 16
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextYAlignment = Enum.TextYAlignment.Center
		label.Rotation = -20
		label.ZIndex = 1
		label.Parent = watermarkHolder
	end
end

screenGui.Parent = player:WaitForChild("PlayerGui")

return Watermark
