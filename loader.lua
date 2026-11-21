--[[
    VANTA | BREAK IN 2
    Loader
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")

local Player = Players.LocalPlayer

-- Simple loading GUI
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "VANTA_Loader"
ScreenGui.IgnoreGuiInset = true
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = CoreGui

local Frame = Instance.new("Frame")
Frame.Size = UDim2.new(1, 0, 1, 0)
Frame.BackgroundColor3 = Color3.fromRGB(12, 11, 10)
Frame.BorderSizePixel = 0
Frame.Parent = ScreenGui

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 40)
Title.Position = UDim2.new(0, 0, 0.42, 0)
Title.BackgroundTransparency = 1
Title.Text = "VANTA"
Title.TextColor3 = Color3.fromRGB(242, 239, 233)
Title.TextSize = 32
Title.Font = Enum.Font.GothamBold
Title.Parent = Frame

local Subtitle = Instance.new("TextLabel")
Subtitle.Size = UDim2.new(1, 0, 0, 24)
Subtitle.Position = UDim2.new(0, 0, 0.48, 0)
Subtitle.BackgroundTransparency = 1
Subtitle.Text = "BREAK IN 2"
Subtitle.TextColor3 = Color3.fromRGB(160, 155, 145)
Subtitle.TextSize = 16
Subtitle.Font = Enum.Font.Gotham
Subtitle.Parent = Frame

local Status = Instance.new("TextLabel")
Status.Size = UDim2.new(1, 0, 0, 20)
Status.Position = UDim2.new(0, 0, 0.58, 0)
Status.BackgroundTransparency = 1
Status.Text = "Cargando..."
Status.TextColor3 = Color3.fromRGB(180, 175, 165)
Status.TextSize = 14
Status.Font = Enum.Font.Gotham
Status.Parent = Frame

local BarBg = Instance.new("Frame")
BarBg.Size = UDim2.new(0, 220, 0, 4)
BarBg.Position = UDim2.new(0.5, -110, 0.63, 0)
BarBg.BackgroundColor3 = Color3.fromRGB(40, 38, 35)
BarBg.BorderSizePixel = 0
BarBg.Parent = Frame

local Bar = Instance.new("Frame")
Bar.Size = UDim2.new(0, 0, 1, 0)
Bar.BackgroundColor3 = Color3.fromRGB(242, 239, 233)
Bar.BorderSizePixel = 0
Bar.Parent = BarBg

-- Animate bar
local tween = TweenService:Create(Bar, TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
    Size = UDim2.new(1, 0, 1, 0)
})
tween:Play()

Status.Text = "Descargando script..."

local success, err = pcall(function()
    local source = game:HttpGet("https://raw.githubusercontent.com/maneulgonzalez1012-cyber/VANTA-BREAK-IN-2/main/VANTA.lua")
    loadstring(source)()
end)

if success then
    Status.Text = "Listo"
    task.wait(0.6)
else
    Status.Text = "Error al cargar"
    warn("[VANTA Loader]", err)
    task.wait(2)
end

-- Fade out
local fade = TweenService:Create(Frame, TweenInfo.new(0.4), {
    BackgroundTransparency = 1
})

for _, child in ipairs(Frame:GetDescendants()) do
    if child:IsA("TextLabel") then
        TweenService:Create(child, TweenInfo.new(0.4), {TextTransparency = 1}):Play()
    elseif child:IsA("Frame") and child ~= Frame then
        TweenService:Create(child, TweenInfo.new(0.4), {BackgroundTransparency = 1}):Play()
    end
end

fade:Play()
fade.Completed:Wait()
ScreenGui:Destroy()
