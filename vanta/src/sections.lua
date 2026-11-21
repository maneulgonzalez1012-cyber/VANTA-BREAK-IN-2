--[[
    VANTA | Secciones
    Carga cada módulo por separado y los mantiene aislados.

    Contrato de un módulo
    - Devuelve una tabla con Setup() (opcional) y sus funciones públicas.
    - Sus banderas viven en state.lua con el prefijo de su nombre.
    - Todas sus acciones devuelven (ejecutado, motivo).

    Aislamiento
    pcall por sección. Una que revienta al cargar queda marcada como rota y
    las demás siguen vivas. Eso es lo que impide que tocar una zona del
    menú rompa el resto del script.
]]

local Sections = {}

local records = {}
local order = {}
local connections = {}

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
        warn(string.format("[VANTA] sección %s rota: %s", name, tostring(err)))
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
            warn(string.format("[VANTA] %s: %s", name, tostring(err)))
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
