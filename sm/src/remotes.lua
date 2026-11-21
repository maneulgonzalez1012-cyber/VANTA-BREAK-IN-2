--[[
    VANTA | Remotos
    La única puerta al servidor.

    En Strongman Simulator no hay una carpeta de remotos como en otros juegos:
    el remoto de fuerza cuelga de ReplicatedStorage directamente y los demás
    (gimnasio, arrastre) van por ProximityPrompt del mapa. Aquí se busca todo
    por nombre, se recuerda lo que se encontró y se dice qué falta.

    Todo lo verificado está en STRONGMAN.md. Lo que no se pudo verificar no
    se inventa: se busca por candidatos y, si no aparece, se informa.
]]

local Remotes = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local resolved = {}
local missing = {}

-- Nombres candidatos, de más probable a menos.
local CANDIDATES = {
    strength = {
        "StrongMan_UpgradeStrength",
        "UpgradeStrength",
        "Upgrade_Strength",
        "StrengthUpgrade",
    },

    -- No verificado en este juego. Se busca; si no está, se dice.
    codes = {
        "RedeemCode",
        "RedeemCodes",
        "CodeEvent",
        "Codes",
        "Redeem",
    },
}

-- ─── Búsqueda ──────────────────────────────────────────────

local function findByPath(name)
    local direct = ReplicatedStorage:FindFirstChild(name)

    if direct then
        return direct
    end

    -- Carpetas típicas, por si algún remoto va dentro.
    for _, folderName in ipairs({"Remotes", "Events", "RemoteEvents", "Game"}) do
        local folder = ReplicatedStorage:FindFirstChild(folderName)

        if folder then
            local hit = folder:FindFirstChild(name)

            if hit then
                return hit
            end
        end
    end

    return nil
end

function Remotes.Resolve(key)
    if resolved[key] then
        local instance = resolved[key]

        if instance.Parent then
            return instance
        end

        resolved[key] = nil
    end

    for _, name in ipairs(CANDIDATES[key] or {}) do
        local instance = findByPath(name)

        if instance then
            resolved[key] = instance
            missing[key] = nil
            return instance
        end
    end

    missing[key] = string.format(
        "no se encontró ninguno de: %s",
        table.concat(CANDIDATES[key] or {}, ", ")
    )

    return nil
end

function Remotes.Get(key)
    return resolved[key] or Remotes.Resolve(key)
end

-- ─── Fuerza ────────────────────────────────────────────────

-- El único remoto confirmado: RemoteFunction, se invoca con un multiplicador.
-- Devuelve (ok, motivo). El éxito NO se decide aquí: se mide fuera, viendo si
-- la fuerza subió.
function Remotes.UpgradeStrength(multiplier)
    local remote = Remotes.Resolve("strength")

    if not remote then
        return false, "no está StrongMan_UpgradeStrength (¿estás en el juego?)"
    end

    local ok, result = pcall(function()
        if multiplier == nil then
            return remote:InvokeServer()
        end

        return remote:InvokeServer(multiplier)
    end)

    if not ok then
        return false, "el servidor rechazó la llamada: " .. tostring(result)
    end

    return true, result
end

-- ─── Códigos ───────────────────────────────────────────────

function Remotes.RedeemCode(code)
    local remote = Remotes.Resolve("codes")

    if not remote then
        return false, missing.codes or "no se encontró el remoto de códigos"
    end

    local ok, result = pcall(function()
        return remote:InvokeServer(code)
    end)

    if not ok then
        return false, "el servidor rechazó el código: " .. tostring(result)
    end

    return true, result
end

-- ─── Diagnóstico ───────────────────────────────────────────

function Remotes.Inventory()
    local list = {}

    for key, instance in pairs(resolved) do
        if instance.Parent then
            list[key] = instance:GetFullName()
        end
    end

    return list
end

function Remotes.Missing()
    return missing
end

function Remotes.Player()
    return Players.LocalPlayer
end

function Remotes.Humanoid()
    local player = Players.LocalPlayer

    if not player then
        return nil
    end

    local character = player.Character

    if not character then
        return nil
    end

    return character:FindFirstChildOfClass("Humanoid")
end

return Remotes
