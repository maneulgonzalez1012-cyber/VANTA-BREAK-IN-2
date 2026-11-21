--[[
    VANTA | CORE — Registro
    El corazón del aislamiento.

    Cada módulo se declara aquí con su nombre, su tipo y sus acciones.
    El registro garantiza:

    - Un módulo que falla al cargar NO impide que los demás carguen.
    - Dos módulos no pueden registrar la misma clave de acción.
    - Cada módulo tiene su propio espacio de banderas y conexiones.
    - Descargar un módulo solo limpia lo suyo.

    Tipos
    - "local"    solo toca propiedades del cliente
    - "remote"   habla con el servidor (pasa por core/remotes)
    - "core"     infraestructura, no tiene UI
]]

local Registry = {}

local modules = {}
local order = {}
local actionOwner = {}
local conflicts = {}

-- ─── Declaración ───────────────────────────────────────────

function Registry.Declare(spec)
    if type(spec) ~= "table" or type(spec.id) ~= "string" or spec.id == "" then
        return false, "módulo sin id"
    end

    if modules[spec.id] then
        return false, "módulo duplicado: " .. spec.id
    end

    local record = {
        id = spec.id,
        name = spec.name or spec.id,
        kind = spec.kind or "remote",
        tab = spec.tab or "Módulos",
        order = spec.order or (#order + 1),
        description = spec.description or "",

        setup = spec.setup,
        actions = {},
        state = {},
        loaded = false,
        error = nil,
    }

    -- Las acciones viven en el registro, no en el módulo: así dos módulos
    -- con el mismo nombre de acción no se pisan en silencio.
    for key, action in pairs(spec.actions or {}) do
        if actionOwner[key] then
            table.insert(conflicts, {
                key = key,
                first = actionOwner[key],
                second = spec.id,
            })
        else
            actionOwner[key] = spec.id
            record.actions[key] = action
        end
    end

    modules[spec.id] = record
    table.insert(order, spec.id)

    return true, record
end

-- ─── Carga / descarga ──────────────────────────────────────

function Registry.Load(moduleId, bus)
    local record = modules[moduleId]

    if not record then
        return false, "módulo no declarado: " .. tostring(moduleId)
    end

    if record.loaded then
        return true
    end

    if type(record.setup) ~= "function" then
        record.loaded = true
        return true
    end

    -- Un módulo que falla queda marcado, pero el resto sigue vivo.
    local ok, err = pcall(record.setup, {
        id = record.id,
        state = record.state,
        bus = bus,
        registry = Registry,
    })

    if not ok then
        record.error = tostring(err)
        record.loaded = false

        if bus then
            bus.Record(record.id, err)
        end

        return false, record.error
    end

    record.loaded = true
    record.error = nil

    return true
end

function Registry.Unload(moduleId, bus)
    local record = modules[moduleId]

    if not record then
        return false
    end

    -- Primero se cortan las conexiones: si el bucle del módulo sigue vivo,
    -- vuelve a aplicar velocidad o noclip en el mismo frame y deshace la
    -- restauración. Después se restaura, y por último se borra el estado.
    if bus then
        bus.DisconnectModule(moduleId)
    end

    -- El teardown puede vivir en la spec o en el estado del módulo.
    if type(record.teardown) == "function" then
        pcall(record.teardown)
    end

    if type(record.state.teardown) == "function" then
        pcall(record.state.teardown)
    end

    record.loaded = false
    table.clear(record.state)

    return true
end

-- ─── Acciones ──────────────────────────────────────────────

-- Ejecuta una acción con nombre. Siempre va por el Bus: si el módulo
-- explota, el error queda registrado con su nombre y no sube.
function Registry.Run(moduleId, actionKey, bus, ...)
    local args = table.pack(...)
    local record = modules[moduleId]

    if not record then
        return false, "módulo desconocido"
    end

    if not record.loaded then
        return false, "módulo no cargado"
    end

    local action = record.actions[actionKey]

    if not action then
        return false, "acción desconocida: " .. tostring(actionKey)
    end

    -- El estado del módulo va SIEMPRE delante: la acción nunca lee estado
    -- global ni el de otro módulo. Cada uno ve solo el suyo.
    local results = table.pack(pcall(
        action,
        record.state,
        table.unpack(args, 1, args.n)
    ))

    -- pcall devuelve ok + todos los retornos de la acción. Sin table.pack
    -- se pierde todo menos el primero, y la UI acaba mostrando "true".
    if not results[1] then
        local err = results[2]

        if bus then
            bus.Record(moduleId .. ":" .. actionKey, err)
        end

        return false, tostring(err)
    end

    -- Se devuelve tal cual lo que respondió la acción: (ejecutado, motivo, ...).
    -- Añadir aquí un `true` delante obliga a la UI a leer el mensaje en la
    -- tercera posición y acaba mostrando "true" en pantalla.
    return table.unpack(results, 2, results.n)
end

-- ─── Consulta ──────────────────────────────────────────────

function Registry.Get(moduleId)
    return modules[moduleId]
end

function Registry.All()
    local list = {}

    for _, moduleId in ipairs(order) do
        table.insert(list, modules[moduleId])
    end

    table.sort(list, function(a, b)
        return a.order < b.order
    end)

    return list
end

function Registry.ByKind(kind)
    local list = {}

    for _, record in ipairs(Registry.All()) do
        if record.kind == kind then
            table.insert(list, record)
        end
    end

    return list
end

function Registry.Conflicts()
    return conflicts
end

function Registry.Health()
    local healthy, broken = 0, 0

    for _, record in ipairs(Registry.All()) do
        if record.error then
            broken += 1
        else
            healthy += 1
        end
    end

    return {
        total = #order,
        healthy = healthy,
        broken = broken,
        conflicts = #conflicts,
    }
end

return Registry
