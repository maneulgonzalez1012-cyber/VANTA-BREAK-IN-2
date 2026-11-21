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
