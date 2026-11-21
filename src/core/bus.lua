--[[
    VANTA | CORE — Bus
    Aislamiento de errores entre módulos.

    Regla: un módulo que falla no puede tumbar a otro. Cada llamada a un
    módulo va por `Bus.Guard`, que captura el error, lo cuenta y lo guarda
    con nombre. El Bus nunca propaga una excepción al llamador.

    También es el punto único de conexiones: todo lo que un módulo conecte
    se registra a su nombre, así `Bus.DisconnectModule` limpia solo lo suyo.
]]

local Bus = {}

local connections = {}
local errors = {}
local counters = {}
local listeners = {}

-- ─── Conexiones aisladas por módulo ─────────────────────────

function Bus.Connect(moduleName, signal, callback)
    local connection = signal:Connect(function(...)
        local ok, err = pcall(callback, ...)

        if not ok then
            Bus.Record(moduleName, err)
        end
    end)

    connections[moduleName] = connections[moduleName] or {}
    table.insert(connections[moduleName], connection)

    return connection
end

function Bus.DisconnectModule(moduleName)
    local list = connections[moduleName]

    if not list then
        return 0
    end

    local closed = 0

    for _, connection in ipairs(list) do
        local ok = pcall(function()
            connection:Disconnect()
        end)

        if ok then
            closed += 1
        end
    end

    connections[moduleName] = nil

    return closed
end

function Bus.DisconnectAll()
    local total = 0

    for moduleName in pairs(connections) do
        total += Bus.DisconnectModule(moduleName)
    end

    return total
end

-- ─── Registro de errores ───────────────────────────────────

function Bus.Record(moduleName, err)
    local message = tostring(err)

    errors[moduleName] = {
        message = message,
        at = os.clock(),
    }

    counters[moduleName] = (counters[moduleName] or 0) + 1

    warn(string.format("[VANTA][%s] %s", tostring(moduleName), message))
end

function Bus.Errors()
    return errors
end

function Bus.ErrorCount(moduleName)
    return counters[moduleName] or 0
end

function Bus.TotalErrors()
    local total = 0

    for _, count in pairs(counters) do
        total += count
    end

    return total
end

-- ─── Llamadas protegidas ───────────────────────────────────

-- Toda entrada de un módulo pasa por aquí. Nunca lanza.
function Bus.Guard(moduleName, fn, ...)
    local args = table.pack(...)

    local ok, results = pcall(function()
        return fn(table.unpack(args, 1, args.n))
    end)

    if not ok then
        Bus.Record(moduleName, results)
        return false, results
    end

    return true, results
end

-- Para callbacks de UI: envuelve y nunca deja escapar el error.
function Bus.Safe(moduleName, fn)
    return function(...)
        local args = table.pack(...)

        local ok, err = pcall(function()
            return fn(table.unpack(args, 1, args.n))
        end)

        if not ok then
            Bus.Record(moduleName, err)
        end

        return ok
    end
end

-- ─── Eventos internos entre módulos ────────────────────────
-- Un módulo no llama a otro directamente: publica. Así ninguno
-- depende de que el otro exista.

function Bus.On(eventName, moduleName, callback)
    listeners[eventName] = listeners[eventName] or {}

    table.insert(listeners[eventName], {
        module = moduleName,
        fn = Bus.Safe(moduleName, callback),
    })
end

function Bus.Emit(eventName, ...)
    local list = listeners[eventName]

    if not list then
        return 0
    end

    local delivered = 0

    for _, listener in ipairs(list) do
        listener.fn(...)
        delivered += 1
    end

    return delivered
end

-- ─── Estado ────────────────────────────────────────────────

function Bus.Snapshot()
    local modules = {}

    for moduleName, count in pairs(counters) do
        table.insert(modules, {
            name = moduleName,
            errors = count,
            last = errors[moduleName] and errors[moduleName].message,
        })
    end

    table.sort(modules, function(a, b)
        return a.name < b.name
    end)

    return {
        modules = modules,
        total = Bus.TotalErrors(),
        connections = (function()
            local n = 0

            for _, list in pairs(connections) do
                n += #list
            end

            return n
        end)(),
    }
end

return Bus
