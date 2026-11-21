--[[
    VANTA | Navegación
    Teleports de la historia y a jugadores.

    Todo local: se escribe CFrame. Si el servidor tiene anti-teleport y te
    devuelve, se dice; no se finge que funcionó.
]]

local Players = game:GetService("Players")

local Remotes = require("remotes")

local Player = Players.LocalPlayer

local Navigation = {}

-- Coordenadas del mapa real.
Navigation.places = {
    {name = "Tienda", cframe = CFrame.new(-246.653229, 30.4500484, -847.319275)},
    {name = "Cocina", cframe = CFrame.new(-249.753555, 30.4500484, -732.703125)},
    {name = "Arena de pelea", cframe = CFrame.new(-255.521988, 62.7139359, -723.436035)},
    {name = "Gimnasio", cframe = CFrame.new(-256.477448, 63.4500465, -840.825562)},
    {name = "Habitación central", cframe = CFrame.new(-209.951859, 30.4590473, -789.723877)},
    {name = "Pelea de jefe", cframe = CFrame.new(-1565.78772, -368.711945, -1040.66626)},
    {name = "Pilar de Scary Mary", cframe = CFrame.new(-1501.49597, -325.156891, -1060.63367)},
    {name = "Agente Bradley", cframe = CFrame.new(-281.792053, 95.4500275, -790.556946)},
    {name = "Twando", cframe = CFrame.new(-257.56839, 29.4499969, -910.452637)},
    {name = "Tío Pete", cframe = CFrame.new(-294.208923, 63.4182587, -737.712036)},
    {name = "Palanca dorada", cframe = CFrame.new(-147.337204, 29.4477005, -929.365295)},
    {name = "Máscara morada", cframe = CFrame.new(102.560722, 29.2477055, -976.389954)},
    {name = "Golden Apple", cframe = CFrame.new(61.8781624, 29.4499969, -534.381165)},
}

local function root()
    local character = Player.Character

    return character and character:FindFirstChild("HumanoidRootPart")
end

local function placeByName(name)
    for _, place in ipairs(Navigation.places) do
        if place.name == name then
            return place
        end
    end

    return nil
end

-- ─── Teleports ─────────────────────────────────────────────

function Navigation.ToPlace(name)
    local myRoot = root()

    if not myRoot then
        return false, "no hay personaje"
    end

    local place = placeByName(name)

    if not place then
        return false, "lugar desconocido: " .. tostring(name)
    end

    -- Tres intentos: algunos mapas devuelven al personaje una vez.
    for _ = 1, 3 do
        myRoot.CFrame = place.cframe
        task.wait(0.1)
    end

    local arrived = Remotes.Await(function()
        return (myRoot.Position - place.cframe.Position).Magnitude < 15
    end, 0.6)

    if arrived then
        return true, "en " .. name
    end

    return false, "el servidor devolvió el personaje (anti-teleport)"
end

function Navigation.FindPlayer(query)
    if type(query) ~= "string" then
        return nil
    end

    local wanted = query:lower():match("^%s*(.-)%s*$")

    if wanted == "" then
        return nil
    end

    for _, target in ipairs(Players:GetPlayers()) do
        if target ~= Player
            and (target.Name:lower() == wanted or target.DisplayName:lower() == wanted)
        then
            return target
        end
    end

    for _, target in ipairs(Players:GetPlayers()) do
        if target ~= Player
            and (target.Name:lower():find(wanted, 1, true)
                or target.DisplayName:lower():find(wanted, 1, true))
        then
            return target
        end
    end

    return nil
end

function Navigation.ToPlayer(query)
    local myRoot = root()

    if not myRoot then
        return false, "no hay personaje"
    end

    if type(query) ~= "string" or query == "" then
        return false, "escribe un nombre primero"
    end

    local target = Navigation.FindPlayer(query)

    if not target then
        return false, "no encontré a " .. query
    end

    local targetRoot = target.Character
        and target.Character:FindFirstChild("HumanoidRootPart")

    if not targetRoot then
        return false, target.Name .. " no tiene personaje"
    end

    local destination = targetRoot.CFrame * CFrame.new(3, 0, 0)

    for _ = 1, 3 do
        myRoot.CFrame = destination
        task.wait(0.1)
    end

    local arrived = Remotes.Await(function()
        return (myRoot.Position - destination.Position).Magnitude < 15
    end, 0.6)

    if arrived then
        return true, "junto a " .. target.Name
    end

    return false, "el servidor devolvió el personaje"
end

function Navigation.Setup()
    -- Sin bucles: nada que mantener encendido.
end

return Navigation
