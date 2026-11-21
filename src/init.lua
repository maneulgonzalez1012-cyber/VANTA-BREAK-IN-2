--[[
    VANTA | BREAK IN 2
    Punto de entrada. Un archivo, ocho módulos.

    Arranque inmediato
    La ventana se monta en cuanto el menú responde. Las secciones se
    suscriben después, cada una en su propio hilo, así ninguna puede
    retrasar a las demás ni tumbarlas.

    Convivencia
    1. Cada sección tiene su tab. Tocar una no repinta otra.
    2. Cada bandera vive en state.lua con el prefijo de su sección.
    3. Una sección que falla al cargar queda marcada; las otras siguen.
    4. Cerrar restaura TODO: velocidad, colisiones, luz y ventana.
]]

local Sections = require("sections")
local State = require("state")
local Remotes = require("remotes")
local Kit = require("kit")

-- ─── Secciones ─────────────────────────────────────────────

local survival = require("survival")
local trainer = require("trainer")
local items = require("items")
local combat = require("combat")
local navigation = require("navigation")
local movement = require("movement")
local visuals = require("visuals")
local lobby = require("lobby")

Sections.Declare("survival", survival)
Sections.Declare("trainer", trainer)
Sections.Declare("items", items)
Sections.Declare("combat", combat)
Sections.Declare("navigation", navigation)
Sections.Declare("movement", movement)
Sections.Declare("visuals", visuals)
Sections.Declare("lobby", lobby)

-- ─── Menú ──────────────────────────────────────────────────

local okLibrary, Rayfield = pcall(function()
    return loadstring(game:HttpGet("https://sirius.menu/gen2"))()
end)

if not okLibrary or not Rayfield then
    warn("[VANTA] no se pudo cargar el menú: " .. tostring(Rayfield))
    return nil
end

local window, windowError = Kit.Mount(Rayfield, {
    name = "VANTA | BREAK IN 2",
    subtitle = "un módulo por zona",
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

-- ─── Carga de secciones ────────────────────────────────────
-- Cada una en su hilo: una lenta no frena a las demás.

for _, record in ipairs(Sections.List()) do
    task.spawn(function()
        Sections.Load(record.name)
    end)
end

-- ─── Supervivencia ─────────────────────────────────────────

local tab = Kit.Tab("Supervivencia")

if tab then
    Kit.Action(tab, "Curarme ahora", "Comprueba que la vida suba", function()
        return survival.Heal()
    end)

    Kit.Flag(tab, "Curarme solo", "Cura cuando bajas del umbral", "autoHeal",
        survival.SetAutoHeal)

    Kit.Action(tab, "Curar a todos", "Manzana equipada + HealTheNoobs", function()
        return survival.HealEveryone()
    end)

    Kit.Flag(tab, "Semi godmode", "El daño de Energy no te toca", "semiGod",
        survival.SetSemiGod)

    Kit.Flag(tab, "Anti-slip", "IceSlip deja de resbalarte", "antiSlip",
        survival.SetAntiSlip)

    Kit.Section(tab, {name = "Entrenamiento"})

    Kit.Action(tab, "Entrenar fuerza", "RainbowWhatStat(Strength)", function()
        return trainer.Train("Strength")
    end)

    Kit.Action(tab, "Entrenar velocidad", "RainbowWhatStat(Speed)", function()
        return trainer.Train("Speed")
    end)

    Kit.Slider(tab, {
        name = "Envíos por clic",
        range = {1, 50},
        increment = 1,
        value = 10,
        flag = "trainerReps",

        callback = function(value)
            trainer.SetReps(value)
        end,
    })
end

-- ─── Objetos ───────────────────────────────────────────────

tab = Kit.Tab("Objetos")

if tab then
    local selected = "Golden Apple"

    Kit.Dropdown(tab, {
        name = "Objeto",
        options = items.all,
        value = selected,
        flag = "itemElegido",

        callback = function(value)
            selected = type(value) == "table" and value[1] or value
        end,
    })

    Kit.Action(tab, "Dar y equipar", "Comprueba la mochila", function()
        return items.Give(selected)
    end)

    Kit.Action(tab, "Kit rápido", "Armadura, curas y arma", function()
        return items.GiveKit()
    end)

    Kit.Action(tab, "Dar todos", "Todo el catálogo, uno a uno", function()
        return items.GiveAll()
    end)

    Kit.Action(tab, "Equipar el elegido", "Solo si ya lo tienes", function()
        return items.Equip(selected)
    end)
end

-- ─── Combate ───────────────────────────────────────────────

tab = Kit.Tab("Combate")

if tab then
    Kit.Action(tab, "Atacar NPC cercanos", "Comprueba la vida del Humanoid", function()
        return combat.HitAll()
    end)

    Kit.Action(tab, "Atacar el más cercano", "Un solo objetivo", function()
        return combat.HitNearest()
    end)

    Kit.Flag(tab, "Auto ataque", "Golpea cada 0.6 s", "autoAttack",
        combat.SetAuto)

    Kit.Slider(tab, {
        name = "Daño por golpe",
        range = {1, 200},
        increment = 1,
        value = 65,
        suffix = " HP",
        flag = "combatDamage",

        callback = function(value)
            combat.SetDamage(value)
        end,
    })
end

-- ─── Movimiento ────────────────────────────────────────────

tab = Kit.Tab("Movimiento")

if tab then
    Kit.Flag(tab, "Velocidad", "Escrita cada frame, no se pide", "speedOn",
        movement.SetSpeedOn)

    Kit.Slider(tab, {
        name = "Velocidad",
        range = {16, 200},
        increment = 1,
        value = 32,
        flag = "speedValue",

        callback = function(value)
            movement.SetSpeed(value)
        end,
    })

    Kit.Flag(tab, "Salto alto", "JumpPower alto", "jumpOn",
        movement.SetJumpOn)

    Kit.Slider(tab, {
        name = "Salto",
        range = {50, 300},
        increment = 1,
        value = 78,
        flag = "jumpValue",

        callback = function(value)
            movement.SetJump(value)
        end,
    })

    Kit.Flag(tab, "Salto infinito", "Se re-salta en el aire", "infJump",
        movement.SetInfJump)

    Kit.Flag(tab, "Noclip", "Restaura colisiones al apagar", "noclip",
        movement.SetNoclip)
end

-- ─── Navegación ────────────────────────────────────────────

tab = Kit.Tab("Navegación")

if tab then
    Kit.Section(tab, {name = "Historia"})

    for _, place in ipairs(navigation.places) do
        Kit.Action(tab, place.name, "Teleport", function()
            return navigation.ToPlace(place.name)
        end)
    end

    Kit.Section(tab, {name = "Jugadores"})

    local target = ""

    Kit.Input(tab, {
        name = "Nombre",
        placeholder = "exacto o parcial",
        value = "",
        flag = "targetPlayer",

        callback = function(value)
            target = tostring(value or "")
        end,
    })

    Kit.Action(tab, "Ir al jugador", "Comprueba el destino", function()
        return navigation.ToPlayer(target)
    end)
end

-- ─── Visuales ──────────────────────────────────────────────

tab = Kit.Tab("Visuales")

if tab then
    Kit.Flag(tab, "ESP jugadores", "Highlight por jugador", "esp",
        visuals.SetESP)

    Kit.Flag(tab, "Fullbright", "Restaura la luz al apagar", "fullbright",
        visuals.SetFullbright)
end

-- ─── Lobby ─────────────────────────────────────────────────

tab = Kit.Tab("Lobby")

if tab then
    Kit.Text(tab, {
        name = "Dónde estás",
        text = "Estás en: " .. lobby.WhereAmI()
            .. ". Los roles solo funcionan en el lobby.",
    })

    Kit.Action(tab, "Rol Hacker", "Entrega el Phone", function()
        return lobby.SetRole("Hacker")
    end)

    Kit.Action(tab, "Rol Nerd", "Entrega el Book", function()
        return lobby.SetRole("Nerd")
    end)
end

-- ─── Diagnóstico ───────────────────────────────────────────

tab = Kit.Tab("Diagnóstico")

if tab then
    Kit.Action(tab, "Estado de secciones", "Aislamiento y errores", function()
        local health = Sections.Health()

        print("===== VANTA SECCIONES =====")

        for _, record in ipairs(Sections.List()) do
            print(string.format(
                "  %-12s %s",
                record.name,
                record.error and ("ROTA: " .. record.error) or "ok"
            ))
        end

        print(string.format(
            "  %d/%d sanas | %d conexiones",
            health.healthy,
            health.total,
            Sections.ConnectionCount()
        ))

        return health.broken == 0, string.format(
            "%d/%d secciones sanas, %d conexiones",
            health.healthy,
            health.total,
            Sections.ConnectionCount()
        )
    end)

    Kit.Action(tab, "Comprobar remotos", "Los siete de la historia", function()
        local inventory = Remotes.Inventory()
        local found, missing = 0, {}

        for _, name in ipairs({"GiveTool", "Vending", "Energy", "HealTheNoobs",
                               "RainbowWhatStat", "HitBadguy", "IceSlip"}) do
            if inventory[name] then
                found += 1
            else
                table.insert(missing, name)
            end
        end

        if #missing == 0 then
            return true, string.format("%d/7 remotos encontrados", found)
        end

        return false, string.format(
            "%d/7: faltan %s",
            found,
            table.concat(missing, ", ")
        )
    end)

    Kit.Action(tab, "Volcar remotos", "Lista completa a la consola (F9)", function()
        local inventory = Remotes.Inventory()
        local count = 0

        print("===== REMOTOS DISPONIBLES =====")

        for name, where in pairs(inventory) do
            print(string.format("  %-18s en %s", name, where))
            count += 1
        end

        if count == 0 then
            return false, "no se encontró ningún remoto (¿estás en Break In 2?)"
        end

        return true, string.format("%d remotos, mira la consola con F9", count)
    end)

    Kit.Action(tab, "Probar cura", "Dispara Energy y mide", function()
        return survival.Heal()
    end)

    Kit.Action(tab, "Cerrar todo", "Restaura y descarga el script", function()
        task.defer(function()
            local state = getgenv and getgenv().VANTA_BI2

            if state and type(state.Stop) == "function" then
                state.Stop()
            end
        end)

        return true, "cerrando"
    end)
end

-- ─── Arranque ──────────────────────────────────────────────

local started = os.clock()
local alive = true

-- ─── Cierre ────────────────────────────────────────────────

local function stop()
    if not alive then
        return
    end

    alive = false

    -- Restaurar ANTES de desconectar no sirve: si el bucle sigue vivo,
    -- vuelve a aplicar velocidad o noclip en el mismo frame. Se desconecta
    -- primero y se restaura después.
    local closed = Sections.DisconnectAll()

    pcall(movement.Restore)
    pcall(visuals.Shutdown)
    pcall(survival.SetSemiGod, false)
    pcall(survival.SetAntiSlip, false)

    State.Reset()
    Kit.Unload()

    if getgenv then
        getgenv().VANTA_BI2 = nil
    end

    print(string.format(
        "[VANTA] cerrado: %d conexiones cortadas, todo restaurado.",
        closed
    ))
end

getgenv().VANTA_BI2 = {
    Stop = stop,
    sections = Sections,
    state = State,
    remotes = Remotes,

    Verify = function()
        local health = Sections.Health()

        return {
            ok = health.broken == 0,
            total = health.total,
            healthy = health.healthy,
            broken = health.broken,
            placeId = game.PlaceId,
            ms = math.floor((os.clock() - started) * 1000),
            remotes = Remotes.Inventory(),
            connections = Sections.ConnectionCount(),
        }
    end,
}

-- Un solo aviso si algo no arrancó.
task.delay(0.3, function()
    local health = Sections.Health()

    if health.broken > 0 then
        Kit.Notify("Secciones rotas", string.format(
            "%d de %d no arrancaron. Mira Diagnóstico → Estado de secciones.",
            health.broken,
            health.total
        ))
    end
end)

return getgenv().VANTA_BI2
