--[[
    VANTA | BREAK IN 2
    Loader

    Descarga VANTA.lua, ejecuta y cierra la pantalla de carga.
    Si la descarga falla, la pantalla se queda visible con el error en vez
    de desaparecer sin decir nada.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local SOURCE_URL =
    "https://raw.githubusercontent.com/maneulgonzalez1012-cyber/VANTA-BREAK-IN-2/main/VANTA.lua"

local Player = Players.LocalPlayer

-- El loader se ejecuta desde la branch, pero el HUD tiene que salir igual
-- en el cliente: CoreGui requiere permisos que no todos los executors dan.
local GuiParent = RunService:IsStudio() and Player:WaitForChild("PlayerGui") or nil

if not GuiParent then
    local ok, coreGui = pcall(function()
        return game:GetService("CoreGui")
    end)

    GuiParent = (ok and coreGui) or Player:WaitForChild("PlayerGui")
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "VANTA_Loader"
ScreenGui.IgnoreGuiInset = true
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder = 999
ScreenGui.Parent = GuiParent

local Frame = Instance.new("Frame")
Frame.Size = UDim2.new(1, 0, 1, 0)
Frame.BackgroundColor3 = Color3.fromRGB(12, 11, 10)
Frame.BorderSizePixel = 0
Frame.Parent = ScreenGui

local function Label(text, yOffset, height, size, color, font)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 0, height)
    label.Position = UDim2.new(0, 0, yOffset, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = color
    label.TextSize = size
    label.Font = font
    label.Parent = Frame

    return label
end

Label("VANTA", 0.42, 40, 32, Color3.fromRGB(242, 239, 233), Enum.Font.GothamBold)
Label("BREAK IN 2", 0.48, 24, 16, Color3.fromRGB(160, 155, 145), Enum.Font.Gotham)

local Status = Label(
    "Cargando...",
    0.58,
    20,
    14,
    Color3.fromRGB(180, 175, 165),
    Enum.Font.Gotham
)

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

local tween = TweenService:Create(
    Bar,
    TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
    {Size = UDim2.new(1, 0, 1, 0)}
)

tween:Play()
Status.Text = "Descargando script..."

local function FadeOut()
    local fadeInfo = TweenInfo.new(0.4)

    for _, child in ipairs(Frame:GetDescendants()) do
        if child:IsA("TextLabel") then
            TweenService:Create(child, fadeInfo, {TextTransparency = 1}):Play()
        elseif child:IsA("Frame") and child ~= Frame then
            TweenService:Create(child, fadeInfo, {BackgroundTransparency = 1}):Play()
        end
    end

    local fade = TweenService:Create(Frame, fadeInfo, {BackgroundTransparency = 1})
    fade:Play()
    fade.Completed:Wait()
    ScreenGui:Destroy()
end

local function Fail(message)
    Status.Text = "Error al cargar"
    Status.TextColor3 = Color3.fromRGB(235, 90, 90)
    warn("[VANTA Loader] " .. tostring(message))

    task.wait(3)
    FadeOut()
end

local okDownload, source = pcall(function()
    return game:HttpGet(SOURCE_URL)
end)

if not okDownload or type(source) ~= "string" or source == "" then
    Fail("No se pudo descargar VANTA.lua: " .. tostring(source))
    return
end

Status.Text = "Ejecutando..."

local okCompile, chunk = pcall(function()
    return loadstring(source, "VANTA")
end)

if not okCompile or not chunk then
    Fail("loadstring falló: " .. tostring(chunk))
    return
end

local okRun, runError = pcall(chunk)

if not okRun then
    Fail("VANTA.lua lanzó un error: " .. tostring(runError))
    return
end

Status.Text = "Listo"
task.wait(0.5)
FadeOut()
