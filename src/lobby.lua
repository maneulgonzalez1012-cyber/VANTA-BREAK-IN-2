--[[
    VANTA | Lobby
    Roles Hacker y Nerd por OutsideRole.

    Dos fuentes documentan la firma:
    - NoobHubV1 usa OutsideRole("Phone") / OutsideRole("Book") solo.
    - RScriptz y BreakingBlitz usan OutsideRole(item, true, false).

    Se prueban las tres formas y gana la que entregue la herramienta. Esa
    es la prueba real: si tienes el Phone, eres Hacker.

    Solo funciona en el lobby (PlaceIds 14775231477 y 13864661000).
]]

local Players = game:GetService("Players")

local Remotes = require("remotes")

local Player = Players.LocalPlayer

local Lobby = {}

Lobby.places = {
    [14775231477] = "Lobby privado",
    [13864661000] = "Lobby",
    [13864667823] = "Historia",
}

Lobby.roles = {
    Hacker = {item = "Phone", tool = "Phone"},
    Nerd = {item = "Book", tool = "Book"},
}

local function hasTool(name)
    local bag = Player:FindFirstChildOfClass("Backpack")
    local character = Player.Character

    if bag and bag:FindFirstChild(name) then
        return true
    end

    return character ~= nil and character:FindFirstChild(name) ~= nil
end

function Lobby.WhereAmI()
    return Lobby.places[game.PlaceId] or ("PlaceId " .. tostring(game.PlaceId))
end

function Lobby.SetRole(roleName)
    local role = Lobby.roles[roleName]

    if not role then
        return false, "rol desconocido: " .. tostring(roleName)
    end

    if hasTool(role.tool) then
        return true, "ya tienes " .. roleName
    end

    -- Las tres formas documentadas, de la más completa a la más simple.
    local forms = {
        {label = "item, true, false", args = {role.item, true, false}},
        {label = "item, true", args = {role.item, true}},
        {label = "item", args = {role.item}},
    }

    for _, form in ipairs(forms) do
        local ok = Remotes.Fire("OutsideRole", table.unpack(form.args))

        if ok then
            local arrived = Remotes.Await(function()
                return hasTool(role.tool)
            end, 1.5)

            if arrived then
                Remotes.Learn("lobby." .. roleName, form.label)

                return true, string.format("rol %s activo (%s)", roleName, form.label)
            end
        end
    end

    -- Se comprueba el lugar para no culpar al script de estar fuera.
    if game.PlaceId == 13864667823 then
        return false, "estás en la historia: los roles solo funcionan en el lobby"
    end

    return false, string.format(
        "el lobby no entregó %s (¿gamepass o lobby equivocado?)",
        roleName
    )
end

function Lobby.Setup()
    -- Nada que mantener encendido.
end

return Lobby
