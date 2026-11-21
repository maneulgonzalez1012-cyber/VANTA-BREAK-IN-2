--[[
    VANTA | Jugadores
    ESP, teleport a jugador y copiar su posición.

    El ESP se dibuja con Highlight, que es del cliente: aparece de verdad o no
    aparece, y se comprueba que el objeto esté colgando del jugador. Al apagar
    se destruye todo, sin restos.

    El teleport mueve el HumanoidRootPart y comprueba la distancia 0.6 s
    después: un teleport que el servidor revierte no es un teleport.
]]

local Players = {}

local State = require("state")
local Sections = require("sections")

local PlayersService = game:GetService("Players")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "SM_ESP"
local highlights = {}

-- ─── Utilidades ────────────────────────────────────────────

local function folder()
    local player = PlayersService.LocalPlayer

    if not player then
        return nil
    end

    local existing = player:FindFirstChild(FOLDER_NAME)

    if existing then
        return existing
    end

    local created = Instance.new("Folder")
    created.Name = FOLDER_NAME
    created.Parent = player

    return created
end

local function characterOf(player)
    return player and player.Character
end

local function rootOf(player)
    local char = characterOf(player)

    if not char then
        return nil
    end

    return char:FindFirstChild("HumanoidRootPart")
end

local function distance(a, b)
    local ok, result = pcall(function()
        return (a.Position - b.Position).Magnitude
    end)

    if ok and type(result) == "number" then
        return result
    end

    return nil
end

-- ─── ESP ───────────────────────────────────────────────────

local function drawFor(player)
    local char = characterOf(player)

    if not char or highlights[player] then
        return false
    end

    local ok, highlight = pcall(function()
        local h = Instance.new("Highlight")
        h.Name = "SM_Highlight"
        h.Adornee = char
        h.FillColor = Color3.fromRGB(0, 170, 255)
        h.OutlineColor = Color3.fromRGB(255, 255, 255)
        h.FillTransparency = 0.5
        h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        h.Parent = folder()
        return h
    end)

    if not ok or not highlight then
        return false
    end

    highlights[player] = highlight

    -- Comprobación real: el Highlight existe y cuelga de tu carpeta.
    return highlight.Parent ~= nil and highlight.Adornee == char
end

local function clearOne(player)
    local highlight = highlights[player]

    if not highlight then
        return false
    end

    pcall(function()
        highlight:Destroy()
    end)

    highlights[player] = nil

    return true
end

function Players.RefreshESP()
    local me = PlayersService.LocalPlayer
    local drawn = 0

    for _, player in ipairs(PlayersService:GetPlayers()) do
        if player ~= me and State.Get("players.esp", false) then
            if drawFor(player) then
                drawn += 1
            end
        end
    end

    return drawn
end

function Players.SetESP(enabled)
    State.Set("players.esp", enabled and true or false)

    if not enabled then
        local removed = 0

        for player in pairs(highlights) do
            if clearOne(player) then
                removed += 1
            end
        end

        local holder = folder()

        if holder then
            pcall(function()
                holder:Destroy()
            end)
        end

        return true, string.format("ESP apagado (%d resaltados quitados)", removed)
    end

    local drawn = Players.RefreshESP()

    if drawn == 0 then
        return false, "no hay otros jugadores a la vista para resaltar"
    end

    return true, string.format("%d jugador(es) resaltados", drawn)
end

-- ─── Teleport ──────────────────────────────────────────────

function Players.ToPlayer(name)
    local me = PlayersService.LocalPlayer
    local target = nil

    if not name or name == "" then
        return false, "escribe el nombre del jugador"
    end

    for _, player in ipairs(PlayersService:GetPlayers()) do
        if player ~= me then
            local display = string.lower(player.DisplayName or "")
            local user = string.lower(player.Name or "")
            local wanted = string.lower(name)

            if display == wanted or user == wanted
                or string.find(user, wanted, 1, true)
            then
                target = player
                break
            end
        end
    end

    if not target then
        return false, "no encontré a " .. tostring(name) .. " en esta partida"
    end

    local myRoot = rootOf(me)
    local theirRoot = rootOf(target)

    if not myRoot then
        return false, "tu personaje no está listo"
    end

    if not theirRoot then
        return false, target.Name .. " acaba de aparecer, prueba otra vez"
    end

    local before = distance(myRoot, theirRoot)

    local ok = pcall(function()
        myRoot.CFrame = theirRoot.CFrame * CFrame.new(0, 0, 3)
    end)

    if not ok then
        return false, "el ejecutor bloqueó el cambio de CFrame"
    end

    -- Se comprueba que sigues ahí y no te devolvieron.
    task.wait(0.6)

    local after = distance(myRoot, theirRoot)

    if after == nil then
        return false, "no se pudo medir la distancia después"
    end

    if after > 12 then
        return false, string.format(
            "el servidor te devolvió (quedaste a %.0f studs)",
            after
        )
    end

    return true, string.format(
        "llegaste con %s (de %.0f a %.0f studs)",
        target.Name,
        before or 0,
        after
    )
end

-- ─── Arranque ──────────────────────────────────────────────

function Players.Setup()
    Sections.Connect("players", PlayersService.PlayerAdded, function()
        if State.Get("players.esp", false) then
            task.delay(1, Players.RefreshESP)
        end
    end)

    Sections.Connect("players", PlayersService.PlayerRemoving, function(player)
        clearOne(player)
    end)

    -- Si el personaje reaparece, el Highlight anterior apunta a un modelo
    -- muerto: se vuelve a dibujar.
    Sections.Connect("players", RunService.Heartbeat, function()
        if not State.Get("players.esp", false) then
            return
        end

        local me = PlayersService.LocalPlayer

        for player, highlight in pairs(highlights) do
            local char = characterOf(player)

            if not char or not highlight.Parent or highlight.Adornee ~= char then
                clearOne(player)

                if player ~= me then
                    drawFor(player)
                end
            end
        end
    end)
end

return Players
