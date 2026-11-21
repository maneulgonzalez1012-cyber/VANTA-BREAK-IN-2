--[[
    VANTA | Stats
    Leer fuerza y energía, y saber si subieron.

    Aquí está la clave para que ninguna acción mienta: antes de disparar se
    toma la foto del stat, después se vuelve a leer. Si el número no cambió,
    la acción no funcionó, diga lo que diga el servidor.

    Dónde vive el número: no está confirmado para este juego. Se prueban los
    sitios habituales del género y se devuelve el primero que aparece, junto
    con la ruta, para poder mostrarla en Diagnóstico en vez de suponerla.
]]

local Stats = {}

local Players = game:GetService("Players")

local cache = {}

local NAMES = {
    strength = {"Strength", "StrengthValue", "Power"},
    energy = {"Energy", "EnergyValue"},
}

local CONTAINERS = {
    "leaderstats",
    "Stats",
    "Values",
    "Data",
}

-- ─── Localizar ─────────────────────────────────────────────

local function player()
    return Players.LocalPlayer
end

local function isStatHolder(instance)
    return instance:IsA("ValueBase") or instance:IsA("IntValue")
        or instance:IsA("NumberValue")
end

local function search(from, name)
    if not from then
        return nil
    end

    local direct = from:FindFirstChild(name)

    if direct and isStatHolder(direct) then
        return direct
    end

    for _, containerName in ipairs(CONTAINERS) do
        local container = from:FindFirstChild(containerName)

        if container then
            local hit = container:FindFirstChild(name)

            if hit and isStatHolder(hit) then
                return hit
            end
        end

        -- Un nivel más: PlayerGui puede tener la UI con el número.
        for _, child in ipairs(from:GetChildren()) do
            local nested = child:FindFirstChild(containerName)

            if nested then
                local hit = nested:FindFirstChild(name)

                if hit and isStatHolder(hit) then
                    return hit
                end
            end
        end
    end

    return nil
end

function Stats.Find(kind)
    local cached = cache[kind]

    if cached and cached.Parent then
        return cached
    end

    local owner = player()

    if not owner then
        return nil
    end

    for _, name in ipairs(NAMES[kind] or {}) do
        local hit = search(owner, name)

        if hit then
            cache[kind] = hit
            return hit
        end
    end

    -- Último recurso: buscar en toda la jerarquía del jugador.
    for _, name in ipairs(NAMES[kind] or {}) do
        for _, descendant in ipairs(owner:GetDescendants()) do
            if descendant.Name == name and isStatHolder(descendant) then
                cache[kind] = descendant
                return descendant
            end
        end
    end

    return nil
end

-- ─── Leer ──────────────────────────────────────────────────

function Stats.Read(kind)
    local stat = Stats.Find(kind)

    if stat then
        local value = stat.Value

        if type(value) == "number" then
            return value, stat:GetFullName()
        end
    end

    -- La UI del juego también muestra el número. Se intenta leer de ahí.
    local owner = player()

    if owner and owner:FindFirstChild("PlayerGui") then
        local wanted = string.lower(kind)

        for _, label in ipairs(owner.PlayerGui:GetDescendants()) do
            if label:IsA("TextLabel") then
                local text = string.lower(label.Text or "")

                if string.find(text, wanted, 1, true) then
                    local number = string.match(
                        string.gsub(label.Text, ",", ""),
                        "([%d]+%.?[%d]*)"
                    )

                    if number then
                        return tonumber(number), label:GetFullName()
                    end
                end
            end
        end
    end

    return nil, "no se encontró el stat de " .. tostring(kind)
end

-- Foto antes/después. Devuelve (subió, antes, después, motivo).
function Stats.Changed(kind, action, minimum)
    local before, where = Stats.Read(kind)

    if before == nil then
        return false, nil, nil, where
    end

    local ok, err = action()

    if not ok then
        return false, before, before, tostring(err)
    end

    -- El servidor tarda: se da margen sin mentir, comprobando de verdad.
    local after = before
    local deadline = os.clock() + 2

    repeat
        task.wait(0.1)
        local now = Stats.Read(kind)

        if now and now > after then
            after = now
        end
    until after > before or os.clock() >= deadline

    minimum = minimum or 1

    if after - before < minimum then
        return false, before, after, string.format(
            "el servidor no aplicó el cambio (%.0f → %.0f)",
            before,
            after
        )
    end

    return true, before, after, string.format(
        "%s +%.0f (%.0f → %.0f)",
        kind,
        after - before,
        before,
        after
    )
end

function Stats.Report()
    local strength, strengthWhere = Stats.Read("strength")
    local energy, energyWhere = Stats.Read("energy")

    return {
        strength = strength,
        strengthWhere = strengthWhere,
        energy = energy,
        energyWhere = energyWhere,
    }
end

return Stats
