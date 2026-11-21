--[[
    VANTA | STRONGMAN SIMULATOR
    Un archivo, trece módulos. Cada pestaña toca solo su módulo.

    REGLA
    Ninguna acción se queda en "solicitud enviada". Cada una:
        1. dispara
        2. comprueba en el cliente que pasó DE VERDAD
        3. si no pasó, reintenta por otra vía
        4. dice qué ocurrió, no qué se intentó

    Lo que es local (velocidad, salto, noclip, luz, ESP, teleport) no se pide:
    se escribe.
]]

local State = {}

local flags = {}
local watchers = {}

function State.Get(key, default)
    local value = flags[key]

    if value == nil then
        return default
    end

    return value
end

function State.Set(key, value)
    if flags[key] == value then
        return false
    end

    flags[key] = value

    for _, callback in ipairs(watchers[key] or {}) do
        local ok, err = pcall(callback, value)

        if not ok then
            warn(string.format("[SM] estado %s: %s", key, tostring(err)))
        end
    end

    return true
end

function State.Toggle(key)
    local value = not State.Get(key, false)
    State.Set(key, value)
    return value
end

function State.Reset()
    local keys = {}

    for key in pairs(flags) do
        table.insert(keys, key)
    end

    for _, key in ipairs(keys) do
        State.Set(key, false)
    end

    return #keys
end

return State
