--[[
    VANTA | BREAK IN 2 — script único
    Generado por tools/build.py desde src/. No editar a mano.

    Cada módulo vive en su propia entrada de FILES y se compila por
    separado. Un módulo roto no impide que carguen los demás.
]]

local FILES = {}

local cache = {}
local loading = {}

local function loadModule(name)
    if cache[name] then
        return cache[name]
    end

    local source = FILES[name]

    if not source then
        error("módulo no empaquetado: " .. tostring(name), 0)
    end

    -- Ciclo: dos módulos que se piden entre sí. Se avisa, no se cuelga.
    if loading[name] then
        error("dependencia circular en " .. tostring(name), 0)
    end

    loading[name] = true

    local chunk, compileError = loadstring(source, "VANTA:" .. name)

    if not chunk then
        loading[name] = nil
        error(string.format("módulo %s no compila: %s", name, tostring(compileError)), 0)
    end

    local ok, result = pcall(chunk)

    loading[name] = nil

    if not ok then
        error(string.format("módulo %s falló al cargar: %s", name, tostring(result)), 0)
    end

    cache[name] = result

    return result
end

-- El require de los módulos resuelve contra FILES, no contra el juego.
local vanillaRequire = require

require = function(target)
    if type(target) == "string" and FILES[target] then
        return loadModule(target)
    end

    return vanillaRequire(target)
end

FILES["core.bus"] = [=[
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
]=]
FILES["core.player"] = [=[
--[[
    VANTA | CORE — Jugador
    Lecturas del mundo, sin E/S. Todo lo que consultan los módulos pasa aquí:
    personaje, vida, mochila, enemigos, jugadores, stats.

    Por qué un módulo aparte: si el juego renombra una carpeta, se arregla
    en un sitio.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Player = Players.LocalPlayer

local PlayerLib = {}

local statSource = {}

local enemyFolders = {"BadGuys", "BadGuysBoss", "BadGuysFront"}

-- ─── Personaje ─────────────────────────────────────────────

function PlayerLib.Character()
    return Player.Character
end

function PlayerLib.Humanoid()
    local character = Player.Character

    return character and character:FindFirstChildOfClass("Humanoid")
end

function PlayerLib.Root()
    local character = Player.Character

    return character and character:FindFirstChild("HumanoidRootPart")
end

function PlayerLib.Backpack()
    return Player:FindFirstChildOfClass("Backpack")
end

function PlayerLib.Alive()
    local humanoid = PlayerLib.Humanoid()

    return humanoid ~= nil and humanoid.Health > 0
end

function PlayerLib.Health()
    local humanoid = PlayerLib.Humanoid()

    return humanoid and humanoid.Health or 0
end

function PlayerLib.MaxHealth()
    local humanoid = PlayerLib.Humanoid()

    return humanoid and humanoid.MaxHealth or 100
end

-- ─── Herramientas ──────────────────────────────────────────

function PlayerLib.ToolName(item)
    return (tostring(item):gsub("%s", ""))
end

function PlayerLib.FindTool(item)
    local name = PlayerLib.ToolName(item)
    local backpack = PlayerLib.Backpack()
    local character = Player.Character

    if backpack then
        local tool = backpack:FindFirstChild(name)

        if tool then
            return tool, "mochila"
        end
    end

    if character then
        local tool = character:FindFirstChild(name)

        if tool then
            return tool, "equipada"
        end
    end

    return nil
end

function PlayerLib.CountTools()
    local backpack = PlayerLib.Backpack()
    local count = 0

    if backpack then
        for _, child in ipairs(backpack:GetChildren()) do
            if child:IsA("Tool") then
                count += 1
            end
        end
    end

    return count
end

function PlayerLib.Equip(item)
    local tool = PlayerLib.FindTool(item)
    local character = Player.Character

    if not tool or not character then
        return false
    end

    if tool.Parent == character then
        return true
    end

    local ok = pcall(function()
        tool.Parent = character
    end)

    return ok
end

-- ─── Enemigos ──────────────────────────────────────────────

function PlayerLib.Enemies()
    local list = {}
    local seen = {}

    local function Add(npc)
        if npc and not seen[npc] then
            seen[npc] = true
            table.insert(list, npc)
        end
    end

    for _, folderName in ipairs(enemyFolders) do
        local folder = Workspace:FindFirstChild(folderName)

        if folder then
            for _, npc in ipairs(folder:GetChildren()) do
                Add(npc)
            end
        end
    end

    Add(Workspace:FindFirstChild("BadGuyPizza", true))
    Add(Workspace:FindFirstChild("BadGuyBrute", true))

    return list
end

function PlayerLib.EnemyHumanoid(npc)
    if not npc then
        return nil
    end

    if npc:IsA("Humanoid") then
        return npc
    end

    return npc:FindFirstChildOfClass("Humanoid")
end

function PlayerLib.EnemyRoot(npc)
    if not npc then
        return nil
    end

    if npc:IsA("BasePart") then
        return npc
    end

    if npc:IsA("Model") then
        return npc.PrimaryPart
            or npc:FindFirstChild("HumanoidRootPart")
    end

    return nil
end

function PlayerLib.EnemyAlive(npc)
    local humanoid = PlayerLib.EnemyHumanoid(npc)

    return humanoid ~= nil and humanoid.Health > 0
end

-- ─── Jugadores ─────────────────────────────────────────────

function PlayerLib.Find(query)
    if type(query) ~= "string" then
        return nil
    end

    local wanted = query:lower():match("^%s*(.-)%s*$")

    if wanted == "" then
        return nil
    end

    for _, target in ipairs(Players:GetPlayers()) do
        if target ~= Player
            and (target.Name:lower() == wanted or target.DisplayName:lower() == wanted)
        then
            return target
        end
    end

    for _, target in ipairs(Players:GetPlayers()) do
        if target ~= Player
            and (
                target.Name:lower():find(wanted, 1, true)
                or target.DisplayName:lower():find(wanted, 1, true)
            )
        then
            return target
        end
    end

    return nil
end

-- ─── Stats (fuerza / velocidad) ────────────────────────────
-- El juego no los expone de forma estable. Se memoriza la primera
-- fuente que da un número, para no recorrer el árbol en cada lectura.

local function Lookup(statName)
    local wanted = statName:lower()
    local playerGui = Player:FindFirstChildOfClass("PlayerGui")

    if playerGui then
        local assets = playerGui:FindFirstChild("Assets")

        if assets then
            for _, object in ipairs(assets:GetDescendants()) do
                if object:IsA("TextLabel") then
                    local text = object.Text:lower()

                    if text:find(wanted, 1, true) then
                        local number = text:match("(%d+%.?%d*)")

                        if number then
                            return tonumber(number), object
                        end
                    end
                end
            end
        end
    end

    for _, object in ipairs(Player:GetDescendants()) do
        if (object:IsA("NumberValue") or object:IsA("IntValue"))
            and object.Name:lower():find(wanted, 1, true)
        then
            return object.Value, object
        end
    end

    if playerGui then
        for _, object in ipairs(playerGui:GetDescendants()) do
            if object:IsA("TextLabel") and object.Text ~= "" then
                local text = object.Text:lower()

                if text:find(wanted, 1, true) then
                    local number = text:match("(%d+%.?%d*)")

                    if number then
                        return tonumber(number), object
                    end
                end
            end
        end
    end

    return nil, nil
end

function PlayerLib.ReadStat(statName)
    local cached = statSource[statName]

    if cached and cached.Parent then
        local value

        if cached:IsA("TextLabel") then
            local number = cached.Text:match("(%d+%.?%d*)")
            value = number and tonumber(number)
        else
            value = cached.Value
        end

        if value then
            return value
        end
    end

    local value, source = Lookup(statName)

    if value and source then
        statSource[statName] = source

        return value
    end

    statSource[statName] = nil

    return nil
end

function PlayerLib.ForgetStats()
    table.clear(statSource)
end

return PlayerLib
]=]
FILES["core.registry"] = [=[
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
]=]
FILES["core.remotes"] = [=[
--[[
    VANTA | CORE — Remotos
    Única puerta al servidor. Ningún módulo llama FireServer directo.

    Responsabilidades
    1. Resolver remotos con caché y verificar que sigan vivos.
    2. Presupuesto de paquetes: nadie puede inundar el servidor.
    3. Firmas aprendidas: si una forma de argumentos ganó, se recuerda.
    4. Devolver siempre ok/motivo, nunca lanzar.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

local cache = {}
local budget = {
    window = 1,
    max = 60,
    count = 0,
    started = os.clock(),
}

local stats = {
    sent = 0,
    dropped = 0,
    failed = 0,
}

local learned = {}

-- ─── Resolución ────────────────────────────────────────────

function Remotes.Resolve(folderName, remoteName)
    local key = folderName .. "." .. remoteName
    local cached = cache[key]

    if cached and cached.Parent then
        return cached
    end

    local folder = ReplicatedStorage:FindFirstChild(folderName)

    if not folder then
        return nil, "falta ReplicatedStorage." .. folderName
    end

    local remote = folder:FindFirstChild(remoteName)

    if not remote or not remote:IsA("RemoteEvent") then
        return nil, "falta " .. key
    end

    cache[key] = remote

    return remote
end

function Remotes.Exists(folderName, remoteName)
    return Remotes.Resolve(folderName, remoteName) ~= nil
end

-- ─── Presupuesto ───────────────────────────────────────────

local function BudgetAllows()
    local now = os.clock()

    if now - budget.started >= budget.window then
        budget.started = now
        budget.count = 0
    end

    if budget.count >= budget.max then
        stats.dropped += 1
        return false
    end

    budget.count += 1

    return true
end

-- ─── Disparo ───────────────────────────────────────────────

function Remotes.Fire(folderName, remoteName, ...)
    local remote, reason = Remotes.Resolve(folderName, remoteName)

    if not remote then
        stats.failed += 1
        return false, reason
    end

    if not BudgetAllows() then
        return false, "presupuesto de paquetes agotado"
    end

    local args = table.pack(...)

    local ok, err = pcall(function()
        remote:FireServer(table.unpack(args, 1, args.n))
    end)

    if not ok then
        stats.failed += 1
        return false, tostring(err)
    end

    stats.sent += 1

    return true
end

function Remotes.Event(remoteName, ...)
    return Remotes.Fire("Events", remoteName, ...)
end

-- ─── Firmas aprendidas ─────────────────────────────────────

function Remotes.GetSignature(action)
    return learned[action]
end

function Remotes.SetSignature(action, label)
    if learned[action] ~= label then
        learned[action] = label
        print(string.format("[VANTA] firma %s -> %s", action, tostring(label)))
    end
end

function Remotes.Signatures()
    local list = {}

    for action, label in pairs(learned) do
        table.insert(list, {action = action, label = label})
    end

    table.sort(list, function(a, b)
        return a.action < b.action
    end)

    return list
end

-- ─── Espera de efecto ──────────────────────────────────────

-- Ninguna acción se cree la primera respuesta: se mide.
function Remotes.Await(predicate, timeout, interval)
    timeout = timeout or 1.5
    interval = math.max(interval or 0.05, 0.02)

    local started = os.clock()
    local spins = 0

    repeat
        local ok, value = pcall(predicate)

        if ok and value then
            return true, value
        end

        spins += 1
        task.wait(interval)
    until os.clock() - started >= timeout or spins >= 200

    return false
end

-- ─── Variantes ─────────────────────────────────────────────

-- Prueba cada variante hasta que una produzca efecto medible.
-- La ganadora queda aprendida para la próxima sesión.
function Remotes.TryVariants(action, variants, verify, timeout)
    local winner = learned[action]
    local ordered = {}

    if winner then
        for _, variant in ipairs(variants) do
            if variant.label == winner then
                table.insert(ordered, variant)
            end
        end
    end

    for _, variant in ipairs(variants) do
        if variant.label ~= winner then
            table.insert(ordered, variant)
        end
    end

    for _, variant in ipairs(ordered) do
        local fired, reason = variant.fire()

        if not fired and variant.fatal then
            return false, reason, 0
        end

        if Remotes.Await(verify, timeout or 1.0) then
            Remotes.SetSignature(action, variant.label)

            return true, variant.label, 1
        end
    end

    return false, nil, #ordered
end

-- ─── Estado ────────────────────────────────────────────────

function Remotes.Stats()
    return {
        sent = stats.sent,
        dropped = stats.dropped,
        failed = stats.failed,
        cached = (function()
            local n = 0

            for _ in pairs(cache) do
                n += 1
            end

            return n
        end)(),
    }
end

function Remotes.ClearCache()
    table.clear(cache)
end

return Remotes
]=]
FILES["features.combat"] = [=[
--[[
    VANTA | FEATURE — Combate
    Golpear NPC con escalera de variantes y medición por Humanoid.

    Distingue tres resultados, y no los mezcla:
    - servidor confirmó (la vida bajó por el remoto)
    - solo local (el cliente aceptó la escritura, el servidor no)
    - rechazado (nada movió la vida)
]]

local PlayerLib = require("core.player")
local Remotes = require("core.remotes")

local Combat = {}

local function hitOne(state, npc, damage, burst)
    local humanoid = PlayerLib.EnemyHumanoid(npc)

    if not humanoid or humanoid.Health <= 0 then
        return false, "sin vida", false
    end

    local root = PlayerLib.Root()

    if root then
        local part = PlayerLib.EnemyRoot(npc)

        if part and (part.Position - root.Position).Magnitude > state.radius then
            return false, "fuera de radio", false
        end
    end

    local before = humanoid.Health
    local part = PlayerLib.EnemyRoot(npc)
    local hits = math.clamp(burst or state.burst, 1, 10)

    local function volley(...)
        local args = table.pack(...)

        for _ = 1, hits do
            Remotes.Event("HitBadguy", table.unpack(args, 1, args.n))
        end
    end

    local variants = {
        {
            label = "HitBadguy(modelo, daño, 4)",
            fire = function()
                volley(npc, damage, 4)
                return true
            end,
        },
    }

    if part then
        table.insert(variants, {
            label = "HitBadguy(parte, daño, 4)",
            fire = function()
                volley(part, damage, 4)
                return true
            end,
        })
    end

    table.insert(variants, {
        label = "HitBadguy(modelo, daño)",
        fire = function()
            volley(npc, damage)
            return true
        end,
    })

    local ok, label = Remotes.TryVariants("hit", variants, function()
        return humanoid.Health < before
    end, 0.5)

    if ok then
        return true, string.format(
            "%d → %d (%s)",
            math.floor(before),
            math.floor(humanoid.Health),
            tostring(label)
        ), false
    end

    -- Último recurso: escribir en el cliente. Se marca como local.
    if humanoid.Health > 0 then
        pcall(function()
            humanoid.Health = 0
        end)

        if humanoid.Health < before then
            return true, string.format("%d → 0 (local)", math.floor(before)), true
        end
    end

    return false, "el remoto no bajó la vida y el cliente no la aceptó", false
end

local function hitAll(state, silent)
    local total, killed, localOnly, failed = 0, 0, 0, 0

    local targets = PlayerLib.Enemies()

    if #targets == 0 then
        return false, "no hay NPC en el mapa (¿place correcto?)", 0, 0
    end

    for _, npc in ipairs(targets) do
        if not state.running then
            break
        end

        if PlayerLib.EnemyAlive(npc) then
            local ok, _, isLocal = hitOne(state, npc, state.damage, state.burst)

            if ok then
                total += 1

                if isLocal then
                    localOnly += 1
                elseif not PlayerLib.EnemyAlive(npc) then
                    killed += 1
                end
            else
                failed += 1
            end
        end
    end

    local detail = string.format("%d dañados, %d caídos", total, killed)

    if localOnly > 0 then
        detail = detail .. string.format(", %d solo en cliente", localOnly)
    end

    if failed > 0 then
        detail = detail .. string.format(", %d sin efecto", failed)
    end

    if total == 0 and failed == 0 then
        detail = "había NPC pero ninguno estaba vivo o en radio"
    end

    -- Solo cuenta como ejecutado lo que el servidor confirmó.
    local verified = killed > 0 or (total > 0 and localOnly == 0)

    return verified, detail, total, killed
end

Combat.spec = {
    id = "combat",
    name = "Combate",
    kind = "remote",
    tab = "Combate",
    order = 40,
    description = "Daño a NPC con verificación por Humanoid",

    actions = {
        hitAll = function(state)
            return hitAll(state, false)
        end,

        hitOne = function(state)
            local target = PlayerLib.Enemies()[1]

            if not target then
                return false, "no hay NPC en el mapa"
            end

            local ok, detail, isLocal = hitOne(state, target, state.damage, state.burst)

            if ok and isLocal then
                return false, detail .. " — solo en tu pantalla"
            end

            return ok, detail
        end,

        setAuto = function(state, value)
            state.auto = value and true or false

            return true, "auto-ataque " .. (state.auto and "activo" or "apagado")
        end,
    },

    setup = function(ctx)
        local state = ctx.state

        state.damage = 65
        state.burst = 4
        state.radius = 150
        state.interval = 0.5
        state.auto = false
        state.running = true

        -- El bucle vive aquí y usa el Bus: si el módulo se descarga,
        -- la conexión muere con él.
        ctx.bus.Connect("combat", game:GetService("RunService").Heartbeat, function()
            if not state.auto then
                return
            end

            -- Heartbeat corre cada frame: se limita a pedazos.
            if os.clock() - (state.lastTick or 0) < state.interval then
                return
            end

            state.lastTick = os.clock()
            hitAll(state, true)
        end)
    end,
}

return Combat
]=]
FILES["features.diagnostics"] = [=[
--[[
    VANTA | FEATURE — Diagnóstico
    La ventana al estado real: módulos vivos, remotos, firmas aprendidas.

    No adivina: pregunta al Bus, al registro y al módulo de remotos.
]]

local Remotes = require("core.remotes")
local PlayerLib = require("core.player")

local Diagnostics = {}

local expected = {
    "GiveTool",
    "Vending",
    "Energy",
    "HealTheNoobs",
    "RainbowWhatStat",
    "HitBadguy",
    "IceSlip",
}

Diagnostics.spec = {
    id = "diagnostics",
    name = "Diagnóstico",
    kind = "core",
    tab = "Diagnóstico",
    order = 90,
    description = "Estado de módulos, remotos y firmas",

    actions = {
        scan = function(state)
            local present, missing = 0, {}

            for _, name in ipairs(expected) do
                if Remotes.Exists("Events", name) then
                    present += 1
                else
                    table.insert(missing, name)
                end
            end

            local ok = #missing == 0

            if ok then
                return true, string.format(
                    "%d/%d remotos presentes",
                    present,
                    #expected
                )
            end

            return false, string.format(
                "faltan: %s",
                table.concat(missing, ", ")
            )
        end,

        modules = function(state)
            local registry = state.registry
            local bus = state.bus

            if not registry or not bus then
                return false, "registro no disponible"
            end

            local health = registry.Health()
            local snapshot = bus.Snapshot()

            print("===== VANTA MÓDULOS =====")

            for _, record in ipairs(registry.All()) do
                local status = "ok"

                if record.error then
                    status = "ERROR: " .. record.error
                elseif not record.loaded then
                    status = "no cargado"
                end

                print(string.format(
                    "  %-14s %-7s %s",
                    record.id,
                    record.kind,
                    status
                ))
            end

            if health.conflicts > 0 then
                print("  conflictos de acción: " .. health.conflicts)

                for _, conflict in ipairs(registry.Conflicts()) do
                    print(string.format(
                        "    %s lo declaran %s y %s",
                        conflict.key,
                        conflict.first,
                        conflict.second
                    ))
                end
            end

            print(string.format(
                "  sanos %d | roto %d | conexiones %d | errores %d",
                health.healthy,
                health.broken,
                snapshot.connections,
                snapshot.total
            ))

            return health.broken == 0, string.format(
                "%d/%d módulos sanos, %d conflictos",
                health.healthy,
                health.total,
                health.conflicts
            )
        end,

        signatures = function(state)
            local list = Remotes.Signatures()

            if #list == 0 then
                return true, "ninguna firma aprendida todavía"
            end

            print("===== FIRMAS APRENDIDAS =====")

            local parts = {}

            for _, entry in ipairs(list) do
                print(string.format("  %s = %s", entry.action, entry.label))
                table.insert(parts, entry.action)
            end

            return true, string.format(
                "%d firmas: %s",
                #list,
                table.concat(parts, ", ")
            )
        end,

        dump = function(state)
            local ReplicatedStorage = game:GetService("ReplicatedStorage")

            local function walk(parent, depth)
                if depth > 3 then
                    return
                end

                for _, child in ipairs(parent:GetChildren()) do
                    print(string.rep("  ", depth) .. child.ClassName .. " : " .. child.Name)

                    if child:IsA("Folder") or child:IsA("Model") then
                        walk(child, depth + 1)
                    end
                end
            end

            print("===== ReplicatedStorage =====")
            walk(ReplicatedStorage, 0)

            return true, "árbol impreso en la consola (F9)"
        end,

        probe = function(state)
            -- La sonda: prueba cada vía y reporta lo que el servidor acepta.
            local lines = {}

            local function add(text)
                table.insert(lines, text)
                print("[SONDA] " .. text)
            end

            add("== SONDA ==")
            add("PlaceId " .. tostring(game.PlaceId))

            local registry = state.registry
            local items = registry and registry.Get("items")

            if items then
                local before = PlayerLib.CountTools()
                registry.Run("items", "give", state.bus, "Pizza")
                local after = PlayerLib.CountTools()

                add(string.format(
                    "objeto Pizza: %s (mochila %d → %d)",
                    after > before and "aceptado" or "rechazado",
                    before,
                    after
                ))
            end

            local survival = registry and registry.Get("survival")

            if survival then
                local humanoid = PlayerLib.Humanoid()

                if humanoid then
                    local original = humanoid.Health
                    pcall(function()
                        humanoid.Health = math.max(original - 40, 10)
                    end)

                    local ok = registry.Run("survival", "heal", state.bus, 25)

                    add(string.format(
                        "cura: %s (vida %d → %d)",
                        ok and "aceptada" or "rechazada",
                        math.floor(humanoid.Health),
                        math.floor(PlayerLib.Health())
                    ))

                    pcall(function()
                        humanoid.Health = original
                    end)
                end
            end

            add("== FIN ==")

            return true, string.format("%d líneas en consola", #lines)
        end,
    },

    setup = function(ctx)
        -- El contexto ya trae registro y bus: no se depende de que el
        -- punto de entrada los inyecte después.
        ctx.state.registry = ctx.state.registry or ctx.registry
        ctx.state.bus = ctx.state.bus or ctx.bus
    end,
}

return Diagnostics
]=]
FILES["features.items"] = [=[
--[[
    VANTA | FEATURE — Objetos
    Dar, equipar y verificar contra la mochila real.

    No confía en "enviado": comprueba que el ítem esté.
    Si no está, prueba la siguiente vía.
]]

local Items = require("lib.items")
local PlayerLib = require("core.player")
local Remotes = require("core.remotes")

local Players = game:GetService("Players")
local LocalName = Players.LocalPlayer.Name

local Feature = {}

local function give(state, item)
    if type(item) ~= "string" or item == "" then
        return false, "ítem inválido"
    end

    -- Ya lo tienes: se equipa, no se pide.
    if PlayerLib.FindTool(item) then
        PlayerLib.Equip(item)
        return true, item .. " ya estaba; equipado"
    end

    local variants = {}
    local toolName = Items.toolName(item)

    -- Armas y armadura van por el vending primero.
    if Items.isArmor(item) then
        table.insert(variants, {
            label = "Vending(Armor2)",
            fire = function()
                return Remotes.Event(
                    "Vending", 3, Items.armorId, "Armor", LocalName, 1
                )
            end,
        })
    elseif Items.isWeapon(item) then
        local weaponId = Items.weaponId(item)

        table.insert(variants, {
            label = "Vending(" .. weaponId .. ")",
            fire = function()
                return Remotes.Event(
                    "Vending", 3, weaponId, "Weapons", LocalName, 1
                )
            end,
        })
    end

    table.insert(variants, {
        label = "GiveTool(sin espacios)",
        fire = function()
            return Remotes.Event("GiveTool", toolName)
        end,
    })

    table.insert(variants, {
        label = "GiveTool(con espacios)",
        fire = function()
            return Remotes.Event("GiveTool", item)
        end,
    })

    local ok, label = Remotes.TryVariants(item, variants, function()
        return PlayerLib.FindTool(item) ~= nil
    end, 1.0)

    if ok then
        PlayerLib.Equip(item)

        return true, string.format(
            "%s en mochila (%s)",
            item,
            tostring(label or "primera vía")
        )
    end

    return false, string.format(
        "%s no llegó por ninguna de %d vías",
        item,
        #variants
    )
end

Feature.spec = {
    id = "items",
    name = "Objetos",
    kind = "remote",
    tab = "Objetos",
    order = 30,
    description = "Dar, equipar y verificar contra la mochila",

    actions = {
        give = function(state, item)
            return give(state, item)
        end,

        giveAll = function(state)
            local done, failed = 0, 0

            for _, item in ipairs(Items.all) do
                if not state.running then
                    break
                end

                local ok = give(state, item)

                if ok then
                    done += 1
                else
                    failed += 1
                end

                task.wait(0.15)
            end

            return done > 0, string.format(
                "%d en mochila, %d rechazados",
                done,
                failed
            )
        end,

        quickKit = function(state)
            local wanted = {"Armor", "Golden Apple", "Med Kit", "Crowbar 2"}
            local done = 0

            for _, item in ipairs(wanted) do
                if give(state, item) then
                    done += 1
                end
            end

            for _ = 1, 6 do
                give(state, "Gold Pizza")
            end

            return done > 0, string.format(
                "%d/%d objetos del kit en la mochila",
                done,
                #wanted
            )
        end,

        selected = function(state)
            return give(state, state.selected or "Golden Apple")
        end,
    },

    setup = function(ctx)
        ctx.state.selected = "Golden Apple"
    end,
}

return Feature
]=]
FILES["features.lobby"] = [=[
--[[
    VANTA | FEATURE — Lobby
    Roles por OutsideRole. Solo tiene efecto en el lobby.

    La prueba del rol es la herramienta del gamepass: si llega, eres el rol.
]]

local PlayerLib = require("core.player")
local Remotes = require("core.remotes")

local Lobby = {}

local roles = {
    Hacker = {arg = "Phone", tool = "Phone"},
    Nerd = {arg = "Book", tool = "Book"},
}

Lobby.spec = {
    id = "lobby",
    name = "Lobby",
    kind = "remote",
    tab = "Lobby",
    order = 70,
    description = "Roles Hacker y Nerd",

    actions = {
        role = function(state, roleName)
            local role = roles[roleName]

            if not role then
                return false, "rol desconocido: " .. tostring(roleName)
            end

            -- Si ya tienes la herramienta del rol, ya lo eres.
            if PlayerLib.FindTool(role.tool) then
                return true, "ya tienes " .. roleName
            end

            local ok, label = Remotes.TryVariants("role:" .. roleName, {
                {
                    label = "OutsideRole(ítem, true, false)",
                    fire = function()
                        return Remotes.Fire(
                            "RemoteEvents", "OutsideRole",
                            role.arg, true, false
                        )
                    end,
                },
                {
                    label = "OutsideRole(ítem)",
                    fire = function()
                        return Remotes.Fire("RemoteEvents", "OutsideRole", role.arg)
                    end,
                },
            }, function()
                return PlayerLib.FindTool(role.tool) ~= nil
            end, 1.5)

            if ok then
                return true, "rol " .. roleName .. " activo (" .. tostring(label) .. ")"
            end

            return false, "el lobby no entregó " .. roleName
                .. " (¿gamepass o lobby equivocado?)"
        end,
    },

    setup = function(ctx)
        ctx.state.roles = roles
    end,
}

return Lobby
]=]
FILES["features.movement"] = [=[
--[[
    VANTA | FEATURE — Movimiento
    Todo local. No manda ni un remoto.

    Por qué así: WalkSpeed, JumpPower, noclip y salto infinito se escriben
    en la propiedad cada frame desde Stepped. El servidor no puede
    rechazar algo que no le pediste.

    Restauración garantizada: guarda los valores originales y los devuelve
    al descargar el módulo.
]]

local PlayerLib = require("core.player")

local Movement = {}

Movement.spec = {
    id = "movement",
    name = "Movimiento",
    kind = "local",
    tab = "Movimiento",
    order = 50,
    description = "Velocidad, salto y noclip — todo local",

    actions = {
        setSpeed = function(state, enabled)
            state.speedEnabled = enabled and true or false

            return true, "velocidad " .. (state.speedEnabled and "activa" or "apagada")
        end,

        setJump = function(state, enabled)
            state.jumpEnabled = enabled and true or false

            return true, "salto " .. (state.jumpEnabled and "activo" or "apagado")
        end,

        setInfJump = function(state, enabled)
            state.infJump = enabled and true or false

            return true, "salto infinito " .. (state.infJump and "activo" or "apagado")
        end,

        setNoclip = function(state, enabled)
            state.noclip = enabled and true or false

            if not state.noclip then
                Movement.restoreCollisions(state)
            end

            return true, "noclip " .. (state.noclip and "activo" or "apagado")
        end,
    },

    setup = function(ctx)
        local state = ctx.state
        local RunService = game:GetService("RunService")
        local UserInputService = game:GetService("UserInputService")

        state.speed = 32
        state.jump = 75
        state.speedEnabled = false
        state.jumpEnabled = false
        state.infJump = false
        state.noclip = false

        state.originals = nil
        state.collisions = {}

        -- Sin esto, al descargar el módulo el Bus borra `state.originals`
        -- y el personaje se queda sin colisión y con la velocidad cambiada
        -- para siempre. El teardown devuelve todo antes de que se borre.
        state.teardown = function()
            local humanoid = PlayerLib.Humanoid()

            if humanoid and state.originals then
                pcall(function()
                    humanoid.WalkSpeed = state.originals.walkSpeed
                    humanoid.JumpPower = state.originals.jumpPower
                    humanoid.UseJumpPower = state.originals.useJumpPower
                end)
            end

            for part, original in pairs(state.collisions or {}) do
                if part and part.Parent then
                    pcall(function()
                        part.CanCollide = original
                    end)
                end
            end

            state.collisions = {}
        end

        local function capture()
            local humanoid = PlayerLib.Humanoid()

            if not humanoid or state.originals then
                return
            end

            state.originals = {
                walkSpeed = humanoid.WalkSpeed,
                jumpPower = humanoid.JumpPower,
                useJumpPower = humanoid.UseJumpPower,
            }
        end

        ctx.bus.Connect("movement", RunService.Stepped, function()
            local humanoid = PlayerLib.Humanoid()
            local character = PlayerLib.Character()

            if humanoid then
                capture()

                if state.speedEnabled then
                    if humanoid.WalkSpeed ~= state.speed then
                        humanoid.WalkSpeed = state.speed
                    end
                elseif state.originals and humanoid.WalkSpeed ~= state.originals.walkSpeed then
                    humanoid.WalkSpeed = state.originals.walkSpeed
                end

                if state.jumpEnabled then
                    if not humanoid.UseJumpPower then
                        humanoid.UseJumpPower = true
                    end

                    if humanoid.JumpPower ~= state.jump then
                        humanoid.JumpPower = state.jump
                    end
                elseif state.originals and humanoid.JumpPower ~= state.originals.jumpPower then
                    humanoid.JumpPower = state.originals.jumpPower
                    humanoid.UseJumpPower = state.originals.useJumpPower
                end
            end

            if state.noclip and character then
                for _, part in ipairs(character:GetDescendants()) do
                    if part:IsA("BasePart") then
                        if state.collisions[part] == nil then
                            state.collisions[part] = part.CanCollide
                        end

                        if part.CanCollide then
                            part.CanCollide = false
                        end
                    end
                end
            end
        end)

        ctx.bus.Connect("movement", UserInputService.JumpRequest, function()
            if not state.infJump then
                return
            end

            local humanoid = PlayerLib.Humanoid()

            if humanoid and humanoid.Health > 0 then
                humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end)
    end,
}

function Movement.restoreCollisions(state)
    for part, original in pairs(state.collisions or {}) do
        if part and part.Parent then
            pcall(function()
                part.CanCollide = original
            end)
        end
    end

    table.clear(state.collisions or {})
end

return Movement
]=]
FILES["features.navigation"] = [=[
--[[
    VANTA | FEATURE — Navegación
    Teleports de la historia y teleport a jugador.

    Verifica que el personaje siga en el destino: si el servidor lo devuelve,
    se dice en vez de fingir que funcionó.
]]

local PlayerLib = require("core.player")
local Remotes = require("core.remotes")
local Places = require("lib.places")

local Navigation = {}

Navigation.spec = {
    id = "navigation",
    name = "Navegación",
    kind = "local",
    tab = "Navegación",
    order = 45,
    description = "Teleports de la historia y a jugadores",

    actions = {
        toPlace = function(state, placeName)
            local root = PlayerLib.Root()

            if not root then
                return false, "sin personaje"
            end

            local place = Places.byName(placeName)

            if not place then
                return false, "lugar desconocido: " .. tostring(placeName)
            end

            for _ = 1, 3 do
                root.CFrame = place.cframe
                task.wait(0.1)
            end

            local ok = Remotes.Await(function()
                return (root.Position - place.cframe.Position).Magnitude < 12
            end, 0.6)

            if ok then
                return true, placeName
            end

            return false, "el servidor devolvió el personaje (anti-teleport)"
        end,

        toPlayer = function(state)
            local root = PlayerLib.Root()

            if not root then
                return false, "sin personaje"
            end

            if (state.target or "") == "" then
                return false, "escribe un nombre primero"
            end

            local target = PlayerLib.Find(state.target)

            if not target then
                return false, "jugador no encontrado"
            end

            local targetRoot = target.Character
                and target.Character:FindFirstChild("HumanoidRootPart")

            if not targetRoot then
                return false, target.Name .. " no tiene personaje"
            end

            local destination = targetRoot.CFrame * CFrame.new(3, 0, 0)

            for _ = 1, 3 do
                root.CFrame = destination
                task.wait(0.1)
            end

            local ok = Remotes.Await(function()
                return (root.Position - destination.Position).Magnitude < 12
            end, 0.6)

            if ok then
                return true, "junto a " .. target.Name
            end

            return false, "el servidor devolvió el personaje (anti-teleport)"
        end,
    },

    setup = function(ctx)
        ctx.state.target = ""
        ctx.state.places = Places.names()
    end,
}

return Navigation
]=]
FILES["features.survival"] = [=[
--[[
    VANTA | FEATURE — Supervivencia
    Curación verificada, semi godmode y anti-slip.

    Aislamiento
    - No sabe que existe otro módulo.
    - Su único estado vive en `ctx.state`.
    - Sus conexiones van por `ctx.bus`.
    - Todas sus acciones devuelven ok + motivo, nunca lanzan.
]]

local Items = require("lib.items")
local PlayerLib = require("core.player")
local Remotes = require("core.remotes")

local HealLadder = {
    {item = "Pizza", amount = 25},
    {item = "Gold Pizza", amount = 50},
    {item = "Rainbow Pizza", amount = 75},
}

local Survival = {}

Survival.spec = {
    id = "survival",
    name = "Supervivencia",
    kind = "remote",
    tab = "Supervivencia",
    order = 20,
    description = "Cura verificada, semi godmode y anti-slip",

    actions = {
        heal = function(state, amount)
            amount = tonumber(amount) or 25

            if not PlayerLib.Alive() then
                return false, "sin personaje vivo"
            end

            local before = PlayerLib.Health()

            if before >= PlayerLib.MaxHealth() then
                return true, "ya estaba a " .. math.floor(before) .. " HP"
            end

            for _, step in ipairs(HealLadder) do
                local healFor = math.max(amount, step.amount)

                -- No se pide ítem si ya lo hay: pedirlo cada tick es flood.
                if not PlayerLib.FindTool(step.item) then
                    Remotes.Event("GiveTool", Items.toolName(step.item))
                    Remotes.Await(function()
                        return PlayerLib.FindTool(step.item) ~= nil
                    end, 0.8)
                end

                local base = PlayerLib.Health()

                local ok, label = Remotes.TryVariants("heal", {
                    {
                        label = "Energy(delta, ítem)",
                        fire = function()
                            return Remotes.Event("Energy", healFor, step.item)
                        end,
                    },
                    {
                        label = "Energy(delta, bool, bool)",
                        fire = function()
                            return Remotes.Event("Energy", healFor, false, false)
                        end,
                    },
                }, function()
                    return PlayerLib.Health() > base + 0.5
                end, 1.2)

                if ok then
                    return true, string.format(
                        "+%d HP con %s (%d → %d)",
                        math.floor(PlayerLib.Health() - before),
                        tostring(label),
                        math.floor(before),
                        math.floor(PlayerLib.Health())
                    )
                end
            end

            return false, "Energy no movió la vida con ningún ítem ni firma"
        end,

        healEveryone = function()
            if not PlayerLib.Alive() then
                return false, "sin personaje vivo"
            end

            local humanoid = PlayerLib.Humanoid()

            if humanoid then
                pcall(function()
                    humanoid:UnequipTools()
                end)
                task.wait(0.15)
            end

            local backpack = PlayerLib.Backpack()

            if not backpack then
                return false, "sin mochila"
            end

            if not backpack:FindFirstChild("GoldenApple") then
                Remotes.Event("GiveTool", "GoldenApple")

                if not Remotes.Await(function()
                    local bag = PlayerLib.Backpack()
                    return bag and bag:FindFirstChild("GoldenApple") ~= nil
                end, 2.0) then
                    return false, "la manzana dorada no llegó"
                end
            end

            if not PlayerLib.Equip("Golden Apple") then
                return false, "no se pudo equipar la manzana"
            end

            task.wait(0.25)

            if not Remotes.Event("HealTheNoobs") then
                return false, "HealTheNoobs no existe en este lugar"
            end

            return true, "manzana equipada y HealTheNoobs disparado"
        end,

        setSemiGod = function(state, value)
            if not state.hooks then
                return false, "este executor no expone hookmetamethod"
            end

            state.semiGod = value and true or false

            return true, "semi godmode " .. (state.semiGod and "activo" or "apagado")
        end,

        setAntiSlip = function(state, value)
            if not state.hooks then
                return false, "este executor no expone hookmetamethod"
            end

            state.antiSlip = value and true or false

            return true, "anti-slip " .. (state.antiSlip and "activo" or "apagado")
        end,
    },

    setup = function(ctx)
        local state = ctx.state

        state.hooks = type(hookmetamethod) == "function"
            and type(getnamecallmethod) == "function"
            and type(newcclosure) == "function"

        state.semiGod = false
        state.antiSlip = false

        -- El hook es del módulo: si se descarga, el Bus lo desconecta.
        if not state.hooks then
            return
        end

        local original = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
            -- Nunca se corta el paso por estado: un `if not running then return end`
            -- aquí se traga TODOS los remotos del juego, incluidos los del
            -- propio motor. Solo se interviene cuando hay algo que hacer.
            if getnamecallmethod() == "FireServer"
                and type(self) == "userdata"
                and self:IsA("RemoteEvent")
            then
                local args = table.pack(...)

                if ctx.state.antiSlip and self.Name == "IceSlip" then
                    return nil
                end

                if ctx.state.semiGod and self.Name == "Energy"
                    and type(args[1]) == "number" and args[1] < 0
                then
                    args[1] = 0
                end

                return original(self, table.unpack(args, 1, args.n))
            end

            return original(self, ...)
        end))

        ctx.state.restoreHook = original
    end,
}

return Survival
]=]
FILES["features.trainer"] = [=[
--[[
    VANTA | FEATURE — Entrenamiento
    RainbowWhatStat con lectura de stat para verificar.

    Si el cliente no expone el stat, la acción se informa sin afirmar
    que subió. No hay éxito inventado.
]]

local PlayerLib = require("core.player")
local Remotes = require("core.remotes")

local Trainer = {}

Trainer.spec = {
    id = "trainer",
    name = "Entrenamiento",
    kind = "remote",
    tab = "Supervivencia",
    order = 25,
    description = "Fuerza y velocidad con lectura de stat",

    actions = {
        train = function(state, stat, reps)
            reps = math.clamp(tonumber(reps) or 5, 1, 100)

            local before = PlayerLib.ReadStat(stat)
            local sent = 0

            for _ = 1, reps do
                if not state.running then
                    break
                end

                if not Remotes.Event("RainbowWhatStat", stat) then
                    return false, "RainbowWhatStat no existe en este lugar"
                end

                sent += 1
                task.wait(before and 0.25 or 0.2)
            end

            if not before then
                return true, string.format(
                    "%s: %d envíos (sin stat legible para verificar)",
                    stat,
                    sent
                )
            end

            local after = PlayerLib.ReadStat(stat)

            if after and after > before then
                return true, string.format(
                    "%s %d → %d (+%d) en %d envíos",
                    stat,
                    math.floor(before),
                    math.floor(after),
                    math.floor(after - before),
                    sent
                )
            end

            -- Probar variantes del nombre antes de rendirse.
            for _, variant in ipairs({stat:lower(), stat:upper()}) do
                local base = PlayerLib.ReadStat(stat)

                Remotes.Event("RainbowWhatStat", variant)
                task.wait(0.4)

                local now = PlayerLib.ReadStat(stat)

                if now and base and now > base then
                    Remotes.SetSignature("train", variant)

                    return true, string.format(
                        "%s subió con variante %s (%d → %d)",
                        stat,
                        variant,
                        math.floor(base),
                        math.floor(now)
                    )
                end
            end

            return false, string.format(
                "%s no subió (%d envíos) — el servidor lo ignora o el stat no es legible",
                stat,
                sent
            )
        end,
    },

    setup = function(ctx)
        ctx.state.running = true
        ctx.state.reps = 5

        -- Si el HUD se reconstruyó, se olvida la fuente memorizada.
        ctx.state.resetStats = function()
            PlayerLib.ForgetStats()
        end
    end,
}

return Trainer
]=]
FILES["features.visuals"] = [=[
--[[
    VANTA | FEATURE — Visuales
    ESP de jugadores y fullbright. Todo local.

    Los highlights viven en una carpeta propia del módulo. Al descargarlo
    se destruye solo esa carpeta: no toca nada de otro módulo.
]]

local PlayerLib = require("core.player")

local Visuals = {}

Visuals.spec = {
    id = "visuals",
    name = "Visuales",
    kind = "local",
    tab = "Visuales",
    order = 60,
    description = "ESP de jugadores y fullbright",

    actions = {
        setESP = function(state, enabled)
            state.esp = enabled and true or false

            if state.refresh then
                state.refresh()
            end

            return true, "ESP " .. (state.esp and "activo" or "apagado")
        end,

        setFullbright = function(state, enabled)
            state.fullbright = enabled and true or false

            if not state.fullbright and state.restoreLighting then
                state.restoreLighting()
            end

            return true, "fullbright " .. (state.fullbright and "activo" or "apagado")
        end,
    },

    setup = function(ctx)
        local state = ctx.state
        local Players = game:GetService("Players")
        local Lighting = game:GetService("Lighting")
        local Workspace = game:GetService("Workspace")
        local RunService = game:GetService("RunService")
        local Player = Players.LocalPlayer

        state.esp = false
        state.fullbright = false
        state.objects = {}

        local folder = Instance.new("Folder")
        folder.Name = "VANTA_Visuals"
        folder.Parent = Workspace

        state.folder = folder

        -- Nombres exactos de propiedad: derivarlos del nombre corto daba
        -- historiales mal escritos y la restauración no hacía nada.
        state.original = {
            {property = "Brightness", value = Lighting.Brightness},
            {property = "ClockTime", value = Lighting.ClockTime},
            {property = "FogEnd", value = Lighting.FogEnd},
            {property = "GlobalShadows", value = Lighting.GlobalShadows},
        }

        function state.restoreLighting()
            for _, entry in ipairs(state.original) do
                pcall(function()
                    Lighting[entry.property] = entry.value
                end)
            end
        end

        local function remove(target)
            local object = state.objects[target]

            if object then
                pcall(function()
                    object:Destroy()
                end)

                state.objects[target] = nil
            end
        end

        local function apply(target)
            remove(target)

            if not state.esp or target == Player or not target.Character then
                return
            end

            local highlight = Instance.new("Highlight")
            highlight.Name = "VANTA_HL"
            highlight.Adornee = target.Character
            highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            highlight.FillColor = Color3.fromRGB(100, 180, 255)
            highlight.OutlineColor = Color3.fromRGB(220, 240, 255)
            highlight.FillTransparency = 0.8
            highlight.OutlineTransparency = 0
            highlight.Parent = folder

            state.objects[target] = highlight
        end

        function state.refresh()
            for _, target in ipairs(Players:GetPlayers()) do
                if target ~= Player then
                    apply(target)
                end
            end
        end

        Players.PlayerAdded:Connect(function(target)
            ctx.bus.Connect("visuals", target.CharacterAdded, function()
                if state.esp then
                    apply(target)
                end
            end)
        end)

        Players.PlayerRemoving:Connect(function(target)
            remove(target)
        end)

        ctx.bus.Connect("visuals", RunService.Stepped, function()
            if not state.fullbright then
                return
            end

            if Lighting.Brightness ~= 3 then
                Lighting.Brightness = 3
            end

            if Lighting.ClockTime ~= 14 then
                Lighting.ClockTime = 14
            end

            if Lighting.FogEnd ~= 100000 then
                Lighting.FogEnd = 100000
            end

            if Lighting.GlobalShadows then
                Lighting.GlobalShadows = false
            end
        end)

        -- Teardown propio: si el módulo se descarga, no deja basura.
        ctx.state.teardown = function()
            for target in pairs(state.objects) do
                remove(target)
            end

            pcall(function()
                folder:Destroy()
            end)
        end
    end,
}

return Visuals
]=]
FILES["init"] = [=[
--[[
    VANTA | NÚCLEO
    Punto de entrada único. Carga cada módulo por separado.

    Reglas de convivencia
    1. Un módulo que falla al cargar no detiene a los demás.
    2. Ningún módulo conoce a otro: se hablan por el Bus.
    3. Cada módulo tiene su tab, sus conexiones y su estado.
    4. Descargar un módulo solo limpia lo suyo.

    Orden de arranque
    Bus -> Remotos -> Registro -> UI -> módulos -> menú
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Env = getgenv()

-- ─── Evitar doble instancia ────────────────────────────────

if Env.VANTA_BI2 and type(Env.VANTA_BI2.Stop) == "function" then
    pcall(Env.VANTA_BI2.Stop)
end

-- ─── Núcleo ────────────────────────────────────────────────

local Bus = require("core.bus")
local Remotes = require("core.remotes")
local Registry = require("core.registry")
local PlayerLib = require("core.player")
local Kit = require("ui.kit")

-- ─── Módulos ───────────────────────────────────────────────

local moduleOrder = {
    "survival",
    "trainer",
    "items",
    "combat",
    "navigation",
    "movement",
    "visuals",
    "lobby",
    "diagnostics",
}

local loaded = {}

for _, moduleName in ipairs(moduleOrder) do
    -- Cada módulo se pide por nombre. Si uno no compila o no existe,
    -- el error queda anotado con SU nombre y el bucle sigue.
    local ok, module = pcall(require, "features." .. moduleName)

    if ok and type(module) == "table" and module.spec then
        local declared, reason = Registry.Declare(module.spec)

        if declared then
            loaded[moduleName] = module
        else
            Bus.Record(moduleName, "no se pudo declarar: " .. tostring(reason))
        end
    else
        Bus.Record(moduleName, "no se pudo cargar: " .. tostring(module))
    end
end

-- ─── UI ────────────────────────────────────────────────────

local okLibrary, Rayfield = pcall(function()
    return loadstring(game:HttpGet("https://sirius.menu/gen2"))()
end)

if not okLibrary or not Rayfield then
    warn("[VANTA] no se pudo cargar Rayfield Gen2: " .. tostring(Rayfield))
    return nil
end

local window, windowError = Kit.Mount(Rayfield, {
    name = "VANTA | BREAK IN 2",
    subtitle = "módulos aislados",
    sidebarLayout = true,
    configuration = {
        autoSave = true,
        autoLoad = true,
        fileName = "VANTA_BreakIn2",
    },
})

if not window then
    warn("[VANTA] no se pudo crear la ventana: " .. tostring(windowError))
    return nil
end

-- ─── Carga de módulos ──────────────────────────────────────

local context = {
    bus = Bus,
    registry = Registry,
    players = PlayerLib,
    remotes = Remotes,
}

local status = {
    running = true,
    start = os.clock(),
}

-- Cada módulo arranca en su propio hilo y con su propio pcall:
-- uno lento no bloquea al resto, uno roto no tumba a nadie.
for _, record in ipairs(Registry.All()) do
    local module = loaded[record.id]

    if module then
        task.spawn(function()
            local ok, err = Registry.Load(record.id, Bus)

            if not ok then
                Kit.Notify(
                    "Módulo roto",
                    string.format("%s: %s", record.id, tostring(err))
                )
            end
        end)
    end
end

-- ─── Menú ──────────────────────────────────────────────────
-- Cada módulo escribe solo en su tab. Dos módulos no comparten tab
-- salvo que lo declaren, y en ese caso van en secciones separadas.

local tabsUsed = {}

for _, record in ipairs(Registry.All()) do
    local tab = Kit.Tab(record.tab)

    if tab then
        tabsUsed[record.tab] = (tabsUsed[record.tab] or 0) + 1

        -- Si el tab ya lo usa otro módulo, se separa con su propia sección.
        if record.id ~= "items" and record.id ~= "combat" then
            Kit.Section(tab, {name = record.name})
        end

        Kit.Text(tab, {
            name = record.name,
            text = record.description,
        })
    end
end

-- ─── Acciones por tab ──────────────────────────────────────

-- Toggle con reporte: el módulo decide, la UI solo informa.
local function actionToggle(tab, moduleId, actionKey, label, description, flag)
    return Kit.Toggle(tab, {
        name = label,
        description = description,
        flag = flag,
        value = false,

        callback = Bus.Safe(moduleId, function(value)
            local executed, detail = Registry.Run(moduleId, actionKey, Bus, value)

            Kit.Notify(label, tostring(detail or
                ((executed == true) and "aplicado" or "no se pudo aplicar")))
        end),
    })
end

local function actionButton(tab, moduleId, actionKey, label, description, ...)
    local preset = table.pack(...)

    return Kit.Button(tab, {
        name = label,
        description = description,

        callback = function()
            task.spawn(function()
                -- Las acciones responden (ejecutado, motivo, ...).
                local executed, detail = Registry.Run(moduleId, actionKey, Bus,
                    table.unpack(preset, 1, preset.n))

                Kit.Report(label, executed == true, tostring(detail or "sin respuesta"))
            end)
        end,
    })
end

-- Supervivencia
local survivalTab = Kit.Tab("Supervivencia")

if survivalTab then
    actionButton(survivalTab, "survival", "heal", "Curarme ahora", "Verifica que la vida suba")

    actionToggle(survivalTab, "survival", "setSemiGod", "Semi godmode",
        "El servidor no puede bajarte la vida", "semiGod")

    actionToggle(survivalTab, "survival", "setAntiSlip", "Anti-slip",
        "Ignora IceSlip", "antiSlip")

    actionButton(survivalTab, "survival", "healEveryone", "Curar a todos", "Manzana dorada + HealTheNoobs")

    actionButton(survivalTab, "trainer", "train", "Entrenar fuerza", "Strength", "Strength", 5)
    actionButton(survivalTab, "trainer", "train", "Entrenar velocidad", "Speed", "Speed", 5)
end

-- Objetos
local itemsTab = Kit.Tab("Objetos")

if itemsTab then
    local Items = require("lib.items")

    Kit.Dropdown(itemsTab, {
        name = "Objeto",
        options = Items.all,
        value = "Golden Apple",
        flag = "item",

        callback = Bus.Safe("items", function(value)
            local record = Registry.Get("items")

            if record then
                record.state.selected = type(value) == "table" and value[1] or value
            end
        end),
    })

    actionButton(itemsTab, "items", "selected", "Dar y equipar", "Verifica la mochila")
    actionButton(itemsTab, "items", "quickKit", "Kit rápido", "Armor, curas, arma")
    actionButton(itemsTab, "items", "giveAll", "Dar todos", "29 objetos, uno por uno")
end

-- Combate
local combatTab = Kit.Tab("Combate")

if combatTab then
    actionButton(combatTab, "combat", "hitAll", "Atacar NPC cercanos", "Verifica por Humanoid")
    actionButton(combatTab, "combat", "hitOne", "Atacar el primero", "Un solo objetivo")

    actionToggle(combatTab, "combat", "setAuto", "Auto ataque",
        "Golpea NPC dentro del radio", "autoAttack")
end

-- Navegación
local navTab = Kit.Tab("Navegación")

if navTab then
    local Places = require("lib.places")

    for _, place in ipairs(Places.list) do
        actionButton(navTab, "navigation", "toPlace", place.name, "Teleport", place.name)
    end

    Kit.Input(navTab, {
        name = "Jugador",
        placeholder = "Nombre exacto o parcial",
        value = "",
        flag = "targetPlayer",

        callback = Bus.Safe("navigation", function(value)
            local record = Registry.Get("navigation")

            if record then
                record.state.target = tostring(value or "")
            end
        end),
    })

    actionButton(navTab, "navigation", "toPlayer", "Teleport al jugador", "Verifica el destino")
end

-- Movimiento
local moveTab = Kit.Tab("Movimiento")

if moveTab then
    actionToggle(moveTab, "movement", "setSpeed", "Velocidad", "Local, cada frame", "speedOn")
    actionToggle(moveTab, "movement", "setJump", "Salto alto", "Local, cada frame", "jumpOn")
    actionToggle(moveTab, "movement", "setInfJump", "Salto infinito", "Se re-salta en el aire", "infJump")
    actionToggle(moveTab, "movement", "setNoclip", "Noclip", "Sin colisión, restaura al apagar", "noclip")
end

-- Visuales
local visualTab = Kit.Tab("Visuales")

if visualTab then
    actionToggle(visualTab, "visuals", "setESP", "ESP jugadores", "Highlight por jugador", "esp")
    actionToggle(visualTab, "visuals", "setFullbright", "Fullbright", "Restaura la luz al apagar", "fullbright")
end

-- Lobby
local lobbyTab = Kit.Tab("Lobby")

if lobbyTab then
    actionButton(lobbyTab, "lobby", "role", "Rol Hacker", "Solo en el lobby", "Hacker")
    actionButton(lobbyTab, "lobby", "role", "Rol Nerd", "Solo en el lobby", "Nerd")
end

-- Diagnóstico
local diagTab = Kit.Tab("Diagnóstico")

if diagTab then
    local diagRecord = Registry.Get("diagnostics")

    if diagRecord then
        diagRecord.state.registry = Registry
        diagRecord.state.bus = Bus
    end

    actionButton(diagTab, "diagnostics", "modules", "Estado de módulos", "Aislamiento y errores")
    actionButton(diagTab, "diagnostics", "scan", "Comprobar remotos", "Los 7 del juego")
    actionButton(diagTab, "diagnostics", "signatures", "Firmas aprendidas", "Lo que el servidor aceptó")
    actionButton(diagTab, "diagnostics", "probe", "Sondear", "Prueba todo y reporta")
    actionButton(diagTab, "diagnostics", "dump", "Volcar ReplicatedStorage", "Árbol completo")
end

-- ─── Cierre global ─────────────────────────────────────────

local function stop()
    if not status.running then
        return
    end

    status.running = false

    -- Descargar en orden inverso: lo último en montarse es lo primero en irse.
    local all = Registry.All()

    for index = #all, 1, -1 do
        local record = all[index]

        pcall(function()
            -- Registry.Unload llama el teardown del módulo (spec o estado)
            -- y desconecta solo las conexiones de ese módulo.
            Registry.Unload(record.id, Bus)
        end)
    end

    Bus.DisconnectAll()

    pcall(function()
        window:Unload()
    end)

    if Env.VANTA_BI2 == status then
        Env.VANTA_BI2 = nil
    end

    print("[VANTA] detenido: módulos descargados, conexiones cerradas.")
end

status.Stop = stop
status.Verify = function()
    local health = Registry.Health()
    local missing = {}

    for _, name in ipairs({"GiveTool", "Vending", "Energy", "HealTheNoobs",
                           "RainbowWhatStat", "HitBadguy", "IceSlip"}) do
        if not Remotes.Exists("Events", name) then
            table.insert(missing, name)
        end
    end

    return {
        ok = #missing == 0 and health.broken == 0,
        running = status.running,
        placeId = game.PlaceId,
        expected = 7,
        missing = missing,
        hooks = Registry.Get("survival") and Registry.Get("survival").state.hooks or false,
        modules = health,
    }
end
status.modules = Registry
status.bus = Bus

Env.VANTA_BI2 = status

-- ─── Diagnóstico al arrancar ───────────────────────────────

task.delay(0.5, function()
    local health = Registry.Health()

    if health.broken > 0 then
        Kit.Notify(
            "Módulos",
            string.format(
                "%d/%d sanos. Revisa Diagnóstico → Estado de módulos.",
                health.healthy,
                health.total
            )
        )
    end
end)

Kit.Notify(
    "VANTA cargado",
    string.format(
        "%d módulos | PlaceId %s",
        #Registry.All(),
        tostring(game.PlaceId)
    )
)

return status
]=]
FILES["lib.items"] = [=[
--[[
    VANTA | LIB — Catálogo de objetos
    Fuente única. Los módulos no escriben nombres de objeto por su cuenta.
]]

local Items = {}

-- Nombre visible -> nombre interno que espera el servidor.
Items.weapons = {
    ["Crowbar 1"] = "Crowbar1",
    ["Crowbar 2"] = "Crowbar2",
    ["Diamond Crowbar"] = "Crowbar3",
    ["Bat"] = "Bat",
    ["Pitchfork"] = "Pitchfork",
    ["Hammer"] = "Hammer",
    ["Wrench"] = "Wrench",
    ["Broom"] = "Broom",
}

-- Armadura va por otra rama del vending.
Items.armor = "Armor"
Items.armorId = "Armor2"

Items.all = {
    "Golden Apple",
    "Gold Pizza",
    "Rainbow Pizza",
    "Rainbow Pizza Box",
    "Pizza",
    "Cookie",
    "Apple",
    "Chips",
    "Lollipop",
    "Bloxy Cola",
    "Expired Bloxy Cola",
    "Bottle",
    "Battery",
    "Med Kit",
    "Armor",
    "Key",
    "Gold Key",
    "Louise",
    "Book",
    "Phone",
    "Ladder",
    "Crowbar 1",
    "Crowbar 2",
    "Diamond Crowbar",
    "Bat",
    "Pitchfork",
    "Hammer",
    "Wrench",
    "Broom",
}

function Items.toolName(item)
    return (tostring(item):gsub("%s", ""))
end

function Items.isWeapon(item)
    return Items.weapons[item] ~= nil
end

function Items.weaponId(item)
    return Items.weapons[item]
end

function Items.isArmor(item)
    return item == Items.armor
end

return Items
]=]
FILES["lib.places"] = [=[
--[[
    VANTA | LIB — Lugares
    Coordenadas de la historia. Un módulo solo, un sitio.
]]

local Places = {}

Places.ids = {
    story = 13864667823,
    lobbyPrivate = 14775231477,
    lobby = 13864661000,
}

Places.list = {
    {name = "Tienda", cframe = CFrame.new(-246.653229, 30.4500484, -847.319275, 0.999987781, -9.18427645e-08, -0.00494772941, 9.19905787e-08, 1, 2.96483353e-08, 0.00494772941, -3.01031164e-08, 0.999987781)},
    {name = "Cocina", cframe = CFrame.new(-249.753555, 30.4500484, -732.703125, -0.999205947, -1.97705017e-08, 0.0398429185, -2.00601384e-08, 1, -6.86967372e-09, -0.0398429185, -7.66347341e-09, -0.999205947)},
    {name = "Arena de pelea", cframe = CFrame.new(-255.521988, 62.7139359, -723.436035, -0.0542500541, 4.28905356e-09, -0.998527408, 1.07862625e-08, 1, 3.70936082e-09, 0.998527408, -1.05691456e-08, -0.0542500541)},
    {name = "Gimnasio", cframe = CFrame.new(-256.477448, 63.4500465, -840.825562, 0.999789953, 2.17116263e-08, 0.020495005, -2.15169358e-08, 1, -9.7199333e-09, -0.020495005, 9.27690191e-09, 0.999789953)},
    {name = "Habitación central", cframe = CFrame.new(-209.951859, 30.4590473, -789.723877, -0.0485812724, 6.74905039e-08, 0.998819232, 1.19352916e-09, 1, -6.75122394e-08, -0.998819232, -2.08771045e-09, -0.0485812724)},
    {name = "Pelea de jefe", cframe = CFrame.new(-1565.78772, -368.711945, -1040.66626, 0.0929690823, -1.97564436e-08, 0.995669007, -1.53269308e-08, 1, 2.1273511e-08, -0.995669007, -1.72383299e-08, 0.0929690823)},
    {name = "Pilar de Scary Mary", cframe = CFrame.new(-1501.49597, -325.156891, -1060.63367, -0.691015959, 7.43958628e-09, 0.722839475, -5.03345055e-09, 1, -1.51040194e-08, -0.722839475, -1.40754954e-08, -0.691015959)},
    {name = "Agente Bradley", cframe = CFrame.new(-281.792053, 95.4500275, -790.556946, -0.116918251, -7.95074726e-08, -0.993141532, -2.79918044e-09, 1, -7.97270019e-08, 0.993141532, -6.54155974e-09, -0.116918251)},
    {name = "Twando (perro)", cframe = CFrame.new(-257.56839, 29.4499969, -910.452637, -0.238445505, 7.71292363e-09, 0.971155882, 1.2913591e-10, 1, -7.91029819e-09, -0.971155882, -1.76076387e-09, -0.238445505)},
    {name = "Tío Pete", cframe = CFrame.new(-294.208923, 63.4182587, -737.712036, -0.998669028, -7.34403613e-08, -0.05157727, -7.2258743e-08, 1, -2.47743781e-08, 0.05157727, -2.1014495e-08, -0.998669028)},
    {name = "Palanca dorada", cframe = CFrame.new(-147.337204, 29.4477005, -929.365295, 0.756779075, 4.53537341e-09, -0.653670728, 5.82708326e-09, 1, 1.36845468e-08, 0.653670728, -1.4165173e-08, 0.756779075)},
    {name = "Máscara morada", cframe = CFrame.new(102.560722, 29.2477055, -976.389954, -0.951403797, 3.76210636e-08, -0.307946175, 1.89752569e-08, 1, 6.35433466e-08, 0.307946175, 5.46120233e-08, -0.951403797)},
    {name = "Golden Apple", cframe = CFrame.new(61.8781624, 29.4499969, -534.381165, -0.584439218, -1.05103076e-07, 0.811437488, -3.12853778e-08, 1, 1.06993674e-07, -0.811437488, 3.71451705e-08, -0.584439218)},
}

function Places.byName(name)
    for _, place in ipairs(Places.list) do
        if place.name == name then
            return place
        end
    end

    return nil
end

function Places.names()
    local list = {}

    for _, place in ipairs(Places.list) do
        table.insert(list, place.name)
    end

    return list
end

return Places
]=]
FILES["ui.kit"] = [=[
--[[
    VANTA | UI — Kit
    Envoltorio único de Rayfield.

    Por qué: si cada módulo llamara a Rayfield directo, un módulo roto
    podría tumbar la ventana. Aquí toda creación de elemento pasa por pcall
    y devuelve un handle mudo si falla, así el módulo sigue vivo.

    Además normaliza el reporte: ✔ hecho de verdad, ✖ no ocurrió.
]]

local Kit = {}

local window = nil
local tabs = {}
local notifications = 0

function Kit.Mount(rayfield, config)
    local ok, result = pcall(function()
        return rayfield:CreateWindow(config)
    end)

    if not ok or not result then
        return nil, tostring(result)
    end

    window = result

    return window
end

function Kit.Window()
    return window
end

function Kit.Tab(name)
    if tabs[name] then
        return tabs[name]
    end

    if not window then
        return nil
    end

    local ok, tab = pcall(function()
        return window:CreateTab({name = name})
    end)

    if not ok or not tab then
        return nil
    end

    tabs[name] = tab

    return tab
end

-- Handle inerte: el módulo puede seguir llamando sin comprobar nada.
local function NullHandle()
    local handle = {}

    handle.Set = function() end
    handle.Lock = function() end
    handle.Unlock = function() end

    return handle
end

local function Create(tab, method, props, label)
    if not tab then
        return NullHandle()
    end

    local ok, handle = pcall(function()
        return tab[method](tab, props)
    end)

    if not ok or not handle then
        warn(string.format("[VANTA][UI] no se pudo crear %s: %s", label, tostring(handle)))
        return NullHandle()
    end

    return handle
end

function Kit.Button(tab, props)
    return Create(tab, "CreateButton", props, props.name)
end

function Kit.Toggle(tab, props)
    return Create(tab, "CreateToggle", props, props.name)
end

function Kit.Slider(tab, props)
    return Create(tab, "CreateSlider", props, props.name)
end

function Kit.Input(tab, props)
    return Create(tab, "CreateInput", props, props.name)
end

function Kit.Dropdown(tab, props)
    return Create(tab, "CreateDropdown", props, props.name)
end

function Kit.Section(tab, props)
    return Create(tab, "CreateSection", props, props.name)
end

function Kit.Text(tab, props)
    return Create(tab, "CreateText", props, props.name)
end

-- ─── Reporte ───────────────────────────────────────────────

function Kit.Notify(title, content)
    notifications += 1

    print(string.format("[VANTA] %s: %s", tostring(title), tostring(content)))

    if not window then
        return
    end

    pcall(function()
        window:Notify({
            title = tostring(title),
            content = tostring(content),
            duration = 4,
        })
    end)
end

-- El único formato de respuesta que usa la UI.
function Kit.Report(title, executed, detail)
    if executed then
        Kit.Notify(title, "✔ " .. tostring(detail))
    else
        Kit.Notify(title, "✖ " .. tostring(detail))
    end

    return executed
end

function Kit.Count()
    return notifications
end

return Kit
]=]

-- ─── Arranque ──────────────────────────────────────────────

local ok, result = pcall(loadModule, "init")

if not ok then
    warn("[VANTA] arranque falló: " .. tostring(result))
    return nil
end

-- El loader comprueba esto antes de decir que todo salió bien.
getgenv().VANTA_BI2_STATE = result

return result
