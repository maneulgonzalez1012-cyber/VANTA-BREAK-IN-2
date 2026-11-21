--[[
    VANTA | Objetos
    Dar, equipar y comprobar en la mochila.

    Dos caminos, porque el servidor los trata distinto:
    - Armadura: Vending(3, "Armor2", "Armor", nombre, 1)
    - Arma:     Vending(3, "Crowbar2", "Weapons", nombre, 1)
    - Todo lo demás: GiveTool(nombre sin espacios)

    Nunca dice "enviado": comprueba que el Tool esté de verdad.
]]

local Players = game:GetService("Players")

local Remotes = require("remotes")

local Player = Players.LocalPlayer

local Items = {}

-- ─── Catálogo ──────────────────────────────────────────────

Items.weapons = {
    "Crowbar 1", "Crowbar 2", "Crowbar 3",
    "Bat", "Pitchfork", "Hammer", "Wrench", "Broom",
}

Items.food = {
    "Pizza", "Gold Pizza", "Rainbow Pizza", "Rainbow Pizza Box",
    "Cookie", "Apple", "Golden Apple", "Chips", "Lollipop",
    "Bloxy Cola", "Expired Bloxy Cola", "Bottle", "Battery",
}

Items.utility = {
    "Med Kit", "Armor", "Key", "Gold Key", "Louise", "Book", "Phone", "Ladder",
}

Items.all = {}

for _, list in ipairs({Items.food, Items.weapons, Items.utility}) do
    for _, item in ipairs(list) do
        table.insert(Items.all, item)
    end
end

local weaponSet = {}

for _, item in ipairs(Items.weapons) do
    weaponSet[item] = true
end

-- ─── Mochila ───────────────────────────────────────────────

local function toolName(item)
    return (tostring(item):gsub("%s", ""))
end

local function findTool(item)
    local name = toolName(item)
    local bag = Player:FindFirstChildOfClass("Backpack")
    local character = Player.Character

    if bag then
        local tool = bag:FindFirstChild(name)

        if tool then
            return tool, "mochila"
        end
    end

    if character then
        local tool = character:FindFirstChild(name)

        if tool then
            return tool, "mano"
        end
    end

    return nil
end

function Items.Has(item)
    return findTool(item) ~= nil
end

function Items.Count()
    local bag = Player:FindFirstChildOfClass("Backpack")
    local total = 0

    if bag then
        for _, child in ipairs(bag:GetChildren()) do
            if child:IsA("Tool") then
                total += 1
            end
        end
    end

    return total
end

function Items.Equip(item)
    local tool = findTool(item)
    local character = Player.Character

    if not tool then
        return false, "no tienes " .. tostring(item)
    end

    if not character then
        return false, "no hay personaje"
    end

    if tool.Parent == character then
        return true, tostring(item) .. " ya estaba en la mano"
    end

    local ok = pcall(function()
        tool.Parent = character
    end)

    if ok then
        return true, tostring(item) .. " en la mano"
    end

    return false, "no se pudo mover " .. tostring(item)
end

-- ─── Dar ───────────────────────────────────────────────────

function Items.Give(item)
    if type(item) ~= "string" or item == "" then
        return false, "ítem inválido"
    end

    if findTool(item) then
        local equipped, reason = Items.Equip(item)
        return true, reason .. " (ya lo tenías)"
    end

    local sent, reason

    if item == "Armor" then
        sent, reason = Remotes.Send("VendingArmor")
    elseif weaponSet[item] then
        -- "Crowbar 3" es la palanca de diamante: el servidor espera
        -- "Crowbar3", sin espacio.
        sent, reason = Remotes.Send("VendingWeapon", item)
    else
        sent, reason = Remotes.Send("GiveTool", item)
    end

    if not sent then
        return false, "no se pudo enviar: " .. tostring(reason)
    end

    -- Await devuelve el PRIMER valor del predicado, que es el Tool, no una
    -- etiqueta. La ubicación se pregunta aparte: findTool ya la devuelve.
    local arrived = Remotes.Await(function()
        return findTool(item)
    end, 1.2)

    if arrived then
        Items.Equip(item)

        local _, location = findTool(item)

        return true, string.format(
            "%s en la %s",
            item,
            tostring(location or "mochila")
        )
    end

    -- Segunda vía: el vending acepta a veces lo que GiveTool rechaza.
    if not weaponSet[item] and item ~= "Armor" then
        Remotes.Send("VendingWeapon", toolName(item))

        if Remotes.Await(function()
            return findTool(item)
        end, 0.8) then
            Items.Equip(item)
            return true, item .. " llegó por el vending"
        end
    end

    return false, item .. " no llegó a la mochila (el servidor lo rechazó)"
end

-- ─── Lotes ─────────────────────────────────────────────────

function Items.GiveKit()
    local wanted = {"Armor", "Golden Apple", "Med Kit", "Crowbar 2"}
    local arrived = 0

    for _, item in ipairs(wanted) do
        if Items.Give(item) then
            arrived += 1
        end

        task.wait(0.15)
    end

    for _ = 1, 6 do
        Items.Give("Gold Pizza")
        task.wait(0.1)
    end

    return arrived > 0, string.format("%d/%d del kit en la mochila", arrived, #wanted)
end

function Items.GiveAll()
    local arrived, refused = 0, 0

    for _, item in ipairs(Items.all) do
        if Items.Give(item) then
            arrived += 1
        else
            refused += 1
        end

        task.wait(0.12)
    end

    return arrived > 0, string.format(
        "%d en la mochila, %d rechazados por el servidor",
        arrived,
        refused
    )
end

function Items.Setup()
    -- Sin bucles: nada que mantener encendido.
end

return Items
