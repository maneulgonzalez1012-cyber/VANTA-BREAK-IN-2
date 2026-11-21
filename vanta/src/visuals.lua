--[[
    VANTA | Visuales
    ESP de jugadores y fullbright. Todo local, todo restaurable.

    Los highlights viven en una carpeta propia. Apagar el ESP borra SOLO
    esa carpeta: no toca nada de otras secciones. Al cerrar, la luz vuelve
    a como estaba.
]]

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local State = require("state")
local Sections = require("sections")

local Player = Players.LocalPlayer

local Visuals = {}

local folder = nil
local highlights = {}
local originalLight = nil

local ESP_COLOR = Color3.fromRGB(120, 190, 255)
local ESP_OUTLINE = Color3.fromRGB(235, 245, 255)

-- ─── Luz ───────────────────────────────────────────────────

local function captureLight()
    if originalLight then
        return
    end

    -- Nombres exactos de propiedad. Derivarlos del nombre corto daba
    -- propiedades mal escritas y la restauración no hacía nada.
    originalLight = {
        {property = "Brightness", value = Lighting.Brightness},
        {property = "ClockTime", value = Lighting.ClockTime},
        {property = "FogEnd", value = Lighting.FogEnd},
        {property = "GlobalShadows", value = Lighting.GlobalShadows},
    }
end

function Visuals.RestoreLight()
    if not originalLight then
        return
    end

    for _, entry in ipairs(originalLight) do
        pcall(function()
            Lighting[entry.property] = entry.value
        end)
    end
end

function Visuals.SetFullbright(enabled)
    State.Set("visuals.fullbright", enabled and true or false)

    if not enabled then
        Visuals.RestoreLight()
    end

    return true, "fullbright " .. (enabled and "activo" or "apagado")
end

-- ─── ESP ───────────────────────────────────────────────────

local function ensureFolder()
    if folder and folder.Parent then
        return folder
    end

    folder = Instance.new("Folder")
    folder.Name = "VANTA_ESP"
    folder.Parent = Workspace

    return folder
end

local function removeHighlight(target)
    local highlight = highlights[target]

    if highlight then
        pcall(function()
            highlight:Destroy()
        end)

        highlights[target] = nil
    end
end

local function addHighlight(target)
    removeHighlight(target)

    if target == Player or not target.Character then
        return
    end

    local highlight = Instance.new("Highlight")
    highlight.Name = "VANTA_HL"
    highlight.Adornee = target.Character
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillColor = ESP_COLOR
    highlight.OutlineColor = ESP_OUTLINE
    highlight.FillTransparency = 0.75
    highlight.OutlineTransparency = 0
    highlight.Parent = ensureFolder()

    highlights[target] = highlight
end

function Visuals.ClearESP()
    for target in pairs(highlights) do
        removeHighlight(target)
    end

    if folder and folder.Parent then
        pcall(function()
            folder:Destroy()
        end)
    end

    folder = nil
end

function Visuals.SetESP(enabled)
    State.Set("visuals.esp", enabled and true or false)

    if not enabled then
        Visuals.ClearESP()
        return true, "ESP apagado"
    end

    local count = 0

    for _, target in ipairs(Players:GetPlayers()) do
        if target ~= Player then
            addHighlight(target)
            count += 1
        end
    end

    return true, string.format("ESP activo en %d jugadores", count)
end

-- ─── Arranque ──────────────────────────────────────────────

function Visuals.Setup()
    Sections.Connect("visuals", Players.PlayerAdded, function(target)
        Sections.Connect("visuals", target.CharacterAdded, function()
            if State.Get("visuals.esp") then
                addHighlight(target)
            end
        end)
    end)

    Sections.Connect("visuals", Players.PlayerRemoving, function(target)
        removeHighlight(target)
    end)

    Sections.Connect("visuals", RunService.Stepped, function()
        if not State.Get("visuals.fullbright") then
            return
        end

        captureLight()

        if Lighting.Brightness ~= 3 then
            Lighting.Brightness = 3
        end

        if Lighting.ClockTime ~= 14 then
            Lighting.ClockTime = 14
        end

        if Lighting.FogEnd < 100000 then
            Lighting.FogEnd = 100000
        end

        if Lighting.GlobalShadows then
            Lighting.GlobalShadows = false
        end
    end)
end

-- Cierre: lo llama el núcleo antes de desconectar.
function Visuals.Shutdown()
    Visuals.ClearESP()
    Visuals.RestoreLight()
end

return Visuals
