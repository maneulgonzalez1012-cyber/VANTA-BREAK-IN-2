--[[
    VANTA | Secciones
    Carga cada módulo por separado y los mantiene aislados.

    Aislamiento
    pcall por sección: una que revienta al cargar queda marcada como rota y
    las demás siguen vivas. Cada sección registra sus conexiones a su nombre,
    así cerrarla corta solo lo suyo y no hay bucles huérfanos.

    También aquí está la restricción de llamadas por segundo, que comparten
    todos los módulos: el servidor de Strongman Simulator rechaza ráfagas.
]]

local Sections = {}

local records = {}
local order = {}
local connections = {}

local budget = {
    limit = 20,
    used = 0,
    window = 0,
}

-- ─── Registro ──────────────────────────────────────────────

function Sections.Declare(name, module)
    if type(name) ~= "string" or type(module) ~= "table" then
        return false, "sección inválida: " .. tostring(name)
    end

    if records[name] then
        return false, "sección duplicada: " .. name
    end

    records[name] = {
        name = name,
        module = module,
        loaded = false,
        error = nil,
    }

    table.insert(order, name)

    return true
end

function Sections.Load(name)
    local record = records[name]

    if not record then
        return false, "sección desconocida: " .. tostring(name)
    end

    if record.loaded then
        return true
    end

    if type(record.module.Setup) ~= "function" then
        record.loaded = true
        return true
    end

    local ok, err = pcall(record.module.Setup)

    if not ok then
        record.error = tostring(err)
        warn(string.format("[SM] sección %s rota: %s", name, tostring(err)))
        return false, record.error
    end

    record.loaded = true
    return true
end

function Sections.LoadAll()
    local okCount, failCount = 0, 0

    for _, name in ipairs(order) do
        if Sections.Load(name) then
            okCount += 1
        else
            failCount += 1
        end
    end

    return okCount, failCount
end

-- ─── Conexiones por sección ────────────────────────────────

function Sections.Connect(name, signal, callback)
    local connection = signal:Connect(function(...)
        local ok, err = pcall(callback, ...)

        if not ok then
            warn(string.format("[SM] %s: %s", name, tostring(err)))
        end
    end)

    connections[name] = connections[name] or {}
    table.insert(connections[name], connection)

    return connection
end

function Sections.Disconnect(name)
    local list = connections[name]

    if not list then
        return 0
    end

    local closed = 0

    for _, connection in ipairs(list) do
        pcall(function()
            connection:Disconnect()
        end)

        closed += 1
    end

    connections[name] = nil

    return closed
end

function Sections.DisconnectAll()
    local total = 0

    for name in pairs(connections) do
        total += Sections.Disconnect(name)
    end

    return total
end

function Sections.ConnectionCount()
    local total = 0

    for _, list in pairs(connections) do
        total += #list
    end

    return total
end

-- ─── Presupuesto de llamadas ───────────────────────────────
-- 20 por segundo para todo el script. Pasarse no acelera nada: el servidor
-- rechaza y la acción se queda a medias.

function Sections.Allow()
    local now = os.clock()

    if now - budget.window >= 1 then
        budget.window = now
        budget.used = 0
    end

    if budget.used >= budget.limit then
        return false, string.format("límite de %d llamadas por segundo", budget.limit)
    end

    budget.used += 1
    return true
end

-- ─── Consulta ──────────────────────────────────────────────

function Sections.Get(name)
    local record = records[name]
    return record and record.module
end

function Sections.List()
    local list = {}

    for _, name in ipairs(order) do
        local record = records[name]

        table.insert(list, {
            name = name,
            loaded = record.loaded,
            error = record.error,
        })
    end

    return list
end

function Sections.Health()
    local healthy = 0

    for _, name in ipairs(order) do
        if not records[name].error then
            healthy += 1
        end
    end

    return {
        total = #order,
        healthy = healthy,
        broken = #order - healthy,
    }
end

return Sections
