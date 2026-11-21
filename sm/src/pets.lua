--[[
    VANTA | Mascotas
    Listar y equipar mascotas.

    Lo que está confirmado del juego: las mascotas dan bonus de entrenamiento
    y de energía, y se compran con energía en cada zona (Toilet Brush +0.3,
    Shaker +0.4, … DiscoStool +3.4).

    Lo que NO está verificado es el remoto de equipar. Por eso este módulo no
    dispara nada a ciegas: busca las mascotas en tu propio inventario y, si
    hay un remoto con pinta de equipar, lo dice en Diagnóstico. Equipar desde
    la UI del juego sigue siendo lo fiable.

    Es preferible un módulo honesto que un botón que no hace nada.
]]

local Pets = {}

local Remotes = require("remotes")
local Sections = require("sections")

local PlayersService = game:GetService("Players")

-- Nombres vistos en el catálogo público del juego.
local CATALOG = {
    "Toilet Brush", "Shaker", "Kettle Bell", "Medicine Ball",
    "Soda", "Fries", "Turkey",
    "Air Hockey", "8Ball", "Space Invaders",
    "Carrot", "Tomato", "Egg Plant",
    "Obelisk", "Knight", "Hydra",
    "Diver Bot", "Planter Bot", "Spider Bot",
    "DiscoBall", "DiscoStool", "Speaker",
}

-- Carpetas donde el juego suele guardar lo que posees.
local HOLDERS = {
    "Pets",
    "OwnedPets",
    "Inventory",
    "PlayerPets",
}

function Pets.Catalog()
    return CATALOG
end

-- Devuelve (lista, dónde) — lista puede venir vacía sin ser un error.
function Pets.Owned()
    local player = PlayersService.LocalPlayer

    if not player then
        return {}, "no hay jugador"
    end

    for _, holderName in ipairs(HOLDERS) do
        local holder = player:FindFirstChild(holderName, true)

        if holder then
            local found = {}

            for _, child in ipairs(holder:GetDescendants()) do
                if child:IsA("StringValue") or child:IsA("ObjectValue") then
                    table.insert(found, tostring(child.Value))
                elseif child:IsA("Folder") or child:IsA("Model") then
                    table.insert(found, child.Name)
                end
            end

            if #found > 0 then
                return found, holder:GetFullName()
            end
        end
    end

    return {}, "no encontré tu inventario de mascotas"
end

function Pets.List()
    local owned, where = Pets.Owned()

    if #owned == 0 then
        return false, "no encontré mascotas tuyas (" .. tostring(where) .. ")"
    end

    return true, string.format("%d: %s", #owned, table.concat(owned, ", "))
end

-- Comprueba si hay un remoto con pinta de equipar mascota, sin usarlo.
function Pets.Setup()
    local candidates = {"EquipPet", "PetEquip", "Equip", "SelectPet", "PetEvent"}
    local found = {}

    for _, name in ipairs(candidates) do
        local hit = game:GetService("ReplicatedStorage"):FindFirstChild(name, true)

        if hit then
            table.insert(found, hit:GetFullName())
        end
    end

    if #found > 0 then
        print("[SM] remotos con pinta de mascota: " .. table.concat(found, ", "))
    end
end

return Pets
