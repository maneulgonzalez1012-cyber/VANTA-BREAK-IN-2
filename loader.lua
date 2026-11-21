--[[
    VANTA | BREAK IN 2
    Loader

    La barra no es una animación: es el estado real del trabajo.
    Cada etapa escribe su progreso y el hilo de dibujo lo lee. Si la
    descarga se cuelga, la barra se queda quieta donde está — porque eso
    es lo que está pasando.

    Etapas
    1. Conectar
    2. Descargar VANTA.lua
    3. Compilar
    4. Ejecutar
    5. Verificar remotos

    Si una etapa falla: se marca en rojo, el error se queda en pantalla y
    la barra no desaparece sola. Un clic cierra.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

-- ─────────────────────────────────────────────────────────────
-- CONFIGURACIÓN
-- ─────────────────────────────────────────────────────────────

local SOURCE_URL =
    "https://raw.githubusercontent.com/maneulgonzalez1012-cyber/VANTA-BREAK-IN-2/main/VANTA.lua"

-- Para probar una branch sin merge, cambia la línea de arriba por:
-- .../VANTA-BREAK-IN-2/<branch>/VANTA.lua

local PALETTE = {
    background = Color3.fromRGB(12, 11, 10),
    text = Color3.fromRGB(242, 239, 233),
    muted = Color3.fromRGB(126, 122, 114),
    dim = Color3.fromRGB(58, 55, 50),
    line = Color3.fromRGB(38, 36, 33),
    ok = Color3.fromRGB(150, 205, 160),
    error = Color3.fromRGB(226, 106, 96),
    warn = Color3.fromRGB(218, 178, 108),
}

local STAGES = {
    {name = "Conectar",          weight = 0.06},
    {name = "Descargar",         weight = 0.42},
    {name = "Compilar",          weight = 0.16},
    {name = "Ejecutar",          weight = 0.26},
    {name = "Verificar remotos", weight = 0.10},
}

-- ─────────────────────────────────────────────────────────────
-- ESTADO COMPARTIDO CON EL HILO DE TRABAJO
-- ─────────────────────────────────────────────────────────────

local Prog = {
    value = 0,
    stage = 1,
    detail = "",
    failed = nil,
    partial = nil,
    finished = false,
}

local function SetStage(index, detail)
    Prog.stage = index
    Prog.detail = detail or ""

    local base = 0

    for i = 1, index - 1 do
        base += STAGES[i].weight
    end

    Prog.value = math.min(base, 1)
end

local function SetProgress(fraction)
    local base = 0

    for i = 1, Prog.stage - 1 do
        base += STAGES[i].weight
    end

    Prog.value = math.min(base + STAGES[Prog.stage].weight * fraction, 1)
end

-- ─────────────────────────────────────────────────────────────
-- GUI
-- ─────────────────────────────────────────────────────────────

local Player = Players.LocalPlayer

local function PickParent()
    local ok, coreGui = pcall(function()
        return game:GetService("CoreGui")
    end)

    if ok and coreGui then
        return coreGui
    end

    return Player:WaitForChild("PlayerGui")
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "VANTA_Loader"
ScreenGui.IgnoreGuiInset = true
ScreenGui.ResetOnSpawn = false
ScreenGui.DisplayOrder = 2147483647
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = PickParent()

local Backdrop = Instance.new("Frame")
Backdrop.Size = UDim2.fromScale(1, 1)
Backdrop.BackgroundColor3 = PALETTE.background
Backdrop.BackgroundTransparency = 1
Backdrop.BorderSizePixel = 0
Backdrop.Parent = ScreenGui

-- Columna centrada: nada toca los bordes, todo respira.
local Column = Instance.new("Frame")
Column.AnchorPoint = Vector2.new(0.5, 0.5)
Column.Position = UDim2.fromScale(0.5, 0.5)
Column.Size = UDim2.fromOffset(360, 168)
Column.BackgroundTransparency = 1
Column.Parent = Backdrop

local Wordmark = Instance.new("TextLabel")
Wordmark.Size = UDim2.new(1, 0, 0, 40)
Wordmark.BackgroundTransparency = 1
Wordmark.Text = "VANTA"
Wordmark.TextColor3 = PALETTE.text
Wordmark.TextSize = 34
Wordmark.Font = Enum.Font.GothamBold
Wordmark.TextXAlignment = Enum.TextXAlignment.Left
Wordmark.TextTransparency = 1
Wordmark.Parent = Column

local Subtitle = Instance.new("TextLabel")
Subtitle.Position = UDim2.fromOffset(2, 38)
Subtitle.Size = UDim2.new(1, 0, 0, 18)
Subtitle.BackgroundTransparency = 1
Subtitle.Text = "BREAK IN 2"
Subtitle.TextColor3 = PALETTE.muted
Subtitle.TextSize = 12
Subtitle.Font = Enum.Font.Gotham
Subtitle.TextXAlignment = Enum.TextXAlignment.Left
Subtitle.TextTransparency = 1
Subtitle.Parent = Column

local Rule = Instance.new("Frame")
Rule.Position = UDim2.fromOffset(0, 74)
Rule.Size = UDim2.new(1, 0, 0, 1)
Rule.BackgroundColor3 = PALETTE.line
Rule.BorderSizePixel = 0
Rule.BackgroundTransparency = 1
Rule.Parent = Column

-- Lista de etapas: cada una pasa de · a ✔ cuando ocurre de verdad.
local StageRows = {}

for index, stage in ipairs(STAGES) do
    local row = Instance.new("Frame")
    row.Position = UDim2.fromOffset(0, 86 + (index - 1) * 17)
    row.Size = UDim2.new(1, 0, 0, 15)
    row.BackgroundTransparency = 1
    row.Parent = Column

    local marker = Instance.new("TextLabel")
    marker.Size = UDim2.fromOffset(16, 15)
    marker.BackgroundTransparency = 1
    marker.Text = "·"
    marker.TextColor3 = PALETTE.dim
    marker.TextSize = 12
    marker.Font = Enum.Font.GothamBold
    marker.TextXAlignment = Enum.TextXAlignment.Left
    marker.TextTransparency = 1
    marker.Parent = row

    local label = Instance.new("TextLabel")
    label.Position = UDim2.fromOffset(18, 0)
    label.Size = UDim2.new(1, -18, 0, 15)
    label.BackgroundTransparency = 1
    label.Text = stage.name
    label.TextColor3 = PALETTE.dim
    label.TextSize = 12
    label.Font = Enum.Font.Gotham
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextTransparency = 1
    label.Parent = row

    StageRows[index] = {marker = marker, label = label}
end

-- Barra: 2 px, sin adornos.
local Track = Instance.new("Frame")
Track.Position = UDim2.fromOffset(0, 86 + #STAGES * 17 + 10)
Track.Size = UDim2.new(1, 0, 0, 2)
Track.BackgroundColor3 = PALETTE.line
Track.BorderSizePixel = 0
Track.BackgroundTransparency = 1
Track.Parent = Column

local Fill = Instance.new("Frame")
Fill.Size = UDim2.new(0, 0, 1, 0)
Fill.BackgroundColor3 = PALETTE.text
Fill.BorderSizePixel = 0
Fill.BackgroundTransparency = 1
Fill.Parent = Track

local Detail = Instance.new("TextLabel")
Detail.Position = UDim2.fromOffset(0, 86 + #STAGES * 17 + 18)
Detail.Size = UDim2.new(1, 0, 0, 14)
Detail.BackgroundTransparency = 1
Detail.Text = ""
Detail.TextColor3 = PALETTE.muted
Detail.TextSize = 11
Detail.Font = Enum.Font.Code
Detail.TextXAlignment = Enum.TextXAlignment.Left
Detail.TextTransparency = 1
Detail.Parent = Column

local Hint = Instance.new("TextLabel")
Hint.AnchorPoint = Vector2.new(1, 1)
Hint.Position = UDim2.new(1, -28, 1, -22)
Hint.Size = UDim2.fromOffset(240, 14)
Hint.BackgroundTransparency = 1
Hint.Text = ""
Hint.TextColor3 = PALETTE.muted
Hint.TextSize = 11
Hint.Font = Enum.Font.Code
Hint.TextXAlignment = Enum.TextXAlignment.Right
Hint.TextTransparency = 1
Hint.Parent = Backdrop

-- ─────────────────────────────────────────────────────────────
-- APARICIÓN
-- ─────────────────────────────────────────────────────────────

local FADE_IN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function FadeIn()
    TweenService:Create(Backdrop, FADE_IN, {BackgroundTransparency = 0}):Play()

    for _, object in ipairs(Column:GetDescendants()) do
        if object:IsA("TextLabel") then
            TweenService:Create(object, FADE_IN, {TextTransparency = 0}):Play()
        elseif object:IsA("Frame") then
            TweenService:Create(object, FADE_IN, {BackgroundTransparency = 0}):Play()
        end
    end
end

local function FadeOutAndClose()
    local info = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    for _, object in ipairs(Backdrop:GetDescendants()) do
        if object:IsA("TextLabel") then
            TweenService:Create(object, info, {TextTransparency = 1}):Play()
        elseif object:IsA("Frame") then
            TweenService:Create(object, info, {BackgroundTransparency = 1}):Play()
        end
    end

    local done = TweenService:Create(Backdrop, info, {BackgroundTransparency = 1})
    done:Play()
    done.Completed:Wait()
    ScreenGui:Destroy()
end

FadeIn()

-- ─────────────────────────────────────────────────────────────
-- DIBUJO
-- ─────────────────────────────────────────────────────────────

local barTween

local function Render()
    local target = UDim2.new(Prog.value, 0, 1, 0)

    if barTween then
        barTween:Cancel()
    end

    barTween = TweenService:Create(
        Fill,
        TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {Size = target}
    )

    barTween:Play()

    for index, row in ipairs(StageRows) do
        if Prog.failed and index == Prog.stage then
            row.marker.Text = "✖"
            row.marker.TextColor3 = PALETTE.error
            row.label.TextColor3 = PALETTE.error
        elseif Prog.partial and index == Prog.stage then
            row.marker.Text = "!"
            row.marker.TextColor3 = PALETTE.warn
            row.label.TextColor3 = PALETTE.warn
        elseif index < Prog.stage
            or (Prog.finished and not Prog.failed and index == Prog.stage)
        then
            row.marker.Text = "✔"
            row.marker.TextColor3 = PALETTE.ok
            row.label.TextColor3 = PALETTE.muted
        elseif index == Prog.stage then
            row.marker.Text = "·"
            row.marker.TextColor3 = PALETTE.text
            row.label.TextColor3 = PALETTE.text
        else
            row.marker.Text = "·"
            row.marker.TextColor3 = PALETTE.dim
            row.label.TextColor3 = PALETTE.dim
        end
    end

    Detail.Text = Prog.detail

    if Prog.failed then
        Fill.BackgroundColor3 = PALETTE.error
        Hint.Text = "clic para cerrar"
    end
end

-- ─────────────────────────────────────────────────────────────
-- TRABAJO
-- ─────────────────────────────────────────────────────────────

local function Fail(stageIndex, message)
    Prog.stage = stageIndex
    Prog.failed = tostring(message)
    Prog.detail = tostring(message)
    Prog.finished = true
    warn("[VANTA Loader] " .. tostring(message))
end

local function Worker()
    -- 1. Conectar
    SetStage(1, "resolviendo VANTA.lua")
    task.wait(0.15)

    -- 2. Descargar (dos intentos: la red falla más de lo que parece)
    SetStage(2, "0 KB")

    local source

    for attempt = 1, 2 do
        local ok, result = pcall(function()
            return game:HttpGet(SOURCE_URL)
        end)

        if ok and type(result) == "string" and #result > 0 then
            source = result
            SetProgress(1)
            Prog.detail = string.format("%d KB", math.floor(#source / 1024))
            break
        end

        local reason

        if not ok then
            reason = tostring(result)
        elseif type(result) ~= "string" then
            reason = "respuesta no es texto (" .. type(result) .. ")"
        else
            reason = "respuesta vacía"
        end

        if attempt == 1 then
            Prog.detail = "reintentando: " .. reason
            task.wait(0.6)
        else
            Fail(2, "no se pudo descargar: " .. reason)
            return
        end
    end

    if not source then
        return
    end

    -- 3. Compilar
    SetStage(3, "loadstring")

    -- loadstring devuelve dos valores (función, error). pcall solo
    -- captura el primero, así que el mensaje se guarda desde dentro.
    local compileError
    local chunk

    local okCompile = pcall(function()
        chunk, compileError = loadstring(source, "VANTA")
    end)

    if not okCompile then
        Fail(3, "loadstring lanzó: " .. tostring(chunk))
        return
    end

    if type(chunk) ~= "function" then
        Fail(3, "error de sintaxis: " .. tostring(compileError or "desconocido"))
        return
    end

    SetProgress(1)

    -- 4. Ejecutar
    SetStage(4, "montando interfaz")

    local okRun, runError = pcall(chunk)

    if not okRun then
        Fail(4, "VANTA.lua falló: " .. tostring(runError))
        return
    end

    SetProgress(1)

    -- 5. Verificar: el script deja su estado en getgenv. Si no está, no cargó.
    SetStage(5, "comprobando")

    local state = getgenv and getgenv().VANTA_BI2

    if not state then
        Fail(5, "el script corrió pero no dejó estado (¿return temprano?)")
        return
    end

    if state.Running == false then
        Fail(5, "el script se detuvo al arrancar")
        return
    end

    -- La verificación la hace el propio script, no una copia de su lista.
    local report

    if type(state.Verify) == "function" then
        local okVerify, result = pcall(state.Verify)

        if okVerify then
            report = result
        end
    end

    -- Si el script no expone Verify (versión vieja), se cuenta a mano.
    if not report then
        local events = game:GetService("ReplicatedStorage"):FindFirstChild("Events")
        local expected = {"GiveTool", "Vending", "Energy", "HealTheNoobs",
                          "RainbowWhatStat", "HitBadguy", "IceSlip"}
        local missing = {}

        for _, name in ipairs(expected) do
            if not (events and events:FindFirstChild(name)) then
                table.insert(missing, name)
            end
        end

        report = {
            ok = #missing == 0,
            expected = #expected,
            missing = missing,
            hooks = false,
        }
    end

    local found = report.expected - #report.missing

    SetProgress(1)
    Prog.detail = string.format(
        "%d/%d remotos | hooks %s",
        found,
        report.expected,
        report.hooks and "sí" or "no"
    )

    Prog.finished = true

    -- El script cargó, pero si faltan remotos no es un ✔ limpio:
    -- se marca la etapa en ámbar y se dice por qué.
    if not report.ok then
        Prog.partial = string.format(
            "faltan %s (PlaceId %s)",
            table.concat(report.missing, ", "),
            tostring(game.PlaceId)
        )

        warn("[VANTA Loader] " .. Prog.partial)
    end
end

task.spawn(function()
    local ok, err = pcall(Worker)

    if not ok then
        Fail(Prog.stage, tostring(err))
    end
end)

-- Hilo de dibujo: corre aparte, así la barra sigue viva aunque la descarga
-- bloquee su hilo.
while not Prog.finished do
    Render()
    task.wait(0.05)
end

Render()

-- ─────────────────────────────────────────────────────────────
-- CIERRE
-- ─────────────────────────────────────────────────────────────

if Prog.failed then
    -- El error se queda. Un clic cierra.
    local closed = false

    local button = Instance.new("TextButton")
    button.Size = UDim2.fromScale(1, 1)
    button.BackgroundTransparency = 1
    button.Text = ""
    button.Parent = Backdrop

    button.MouseButton1Click:Connect(function()
        if closed then
            return
        end

        closed = true
        FadeOutAndClose()
    end)

    task.wait(20)

    if not closed then
        FadeOutAndClose()
    end
else
    task.wait(0.35)
    FadeOutAndClose()
end
