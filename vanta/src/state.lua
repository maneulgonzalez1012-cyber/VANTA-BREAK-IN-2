--[[
    VANTA | Estado
    Las banderas de todas las secciones, en un solo sitio.

    Cada llave lleva el prefijo de su sección: "survival.autoHeal",
    "combat.auto", "movement.noclip". Así una sección no puede pisar la
    bandera de otra por accidente, y guardar o restaurar la configuración
    es recorrer una tabla.
]]

local State = {}

local flags = {}
local watchers = {}

-- ─── Banderas ──────────────────────────────────────────────

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

    local list = watchers[key]

    if list then
        for _, callback in ipairs(list) do
            local ok, err = pcall(callback, value)

            if not ok then
                warn(string.format("[VANTA] state %s: %s", key, tostring(err)))
            end
        end
    end

    return true
end

function State.Toggle(key)
    local value = not State.Get(key, false)
    State.Set(key, value)
    return value
end

function State.OnChange(key, callback)
    watchers[key] = watchers[key] or {}
    table.insert(watchers[key], callback)
end

-- ─── Persistencia ──────────────────────────────────────────
-- Solo valores simples: nada de objetos ni funciones en la nube.

function State.Export()
    local copy = {}

    for key, value in pairs(flags) do
        local kind = type(value)

        if kind == "boolean" or kind == "number" or kind == "string" then
            copy[key] = value
        end
    end

    return copy
end

function State.Import(values)
    if type(values) ~= "table" then
        return 0
    end

    local restored = 0

    for key, value in pairs(values) do
        local kind = type(value)

        if kind == "boolean" or kind == "number" or kind == "string" then
            State.Set(key, value)
            restored += 1
        end
    end

    return restored
end

-- ─── Apagar todo ───────────────────────────────────────────

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

function State.Snapshot()
    local list = {}

    for key, value in pairs(flags) do
        table.insert(list, {key = key, value = value})
    end

    table.sort(list, function(a, b)
        return a.key < b.key
    end)

    return list
end

return State
