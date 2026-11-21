--[[
    VANTA | STRONGMAN SIMULATOR
    Punto de entrada. Un archivo, trece módulos.

    Arranque inmediato
    La ventana se monta en cuanto el menú responde. Las secciones se cargan
    después, cada una en su propio hilo, así ninguna retrasa a las demás ni
    las tumba.

    Convivencia
    1. Cada sección tiene su pestaña. Tocar una no repinta otra.
    2. Cada bandera vive en state.lua con el prefijo de su sección.
    3. Una sección que falla al cargar queda marcada; las otras siguen.
    4. Ejecutar el script dos veces apaga la copia anterior antes de montar.
    5. Cerrar restaura todo: velocidad, salto, colisiones, tamaño y ventana.
]]

local Sections = require("sections")
local State = require("state")
local Remotes = require("remotes")
local Kit = require("kit")

local training = require("training")
local dragging = require("dragging")
local movement = require("movement")
local world = require("world")
local players = require("players")
local codes = require("codes")
local pets = require("pets")
local avatar = require("avatar")
local diagnostics = require("diagnostics")

Sections.Declare("training", training)
Sections.Declare("dragging", dragging)
Sections.Declare("movement", movement)
Sections.Declare("world", world)
Sections.Declare("players", players)
Sections.Declare("codes", codes)
Sections.Declare("pets", pets)
Sections.Declare("avatar", avatar)
Sections.Declare("diagnostics", diagnostics)

-- ─── Un solo VANTA a la vez ────────────────────────────────
-- Si ya hay una copia viva (volviste a pegar el script sin reiniciar), se
-- apaga esa antes de montar la nueva. Si no, quedan dos ventanas y dos
-- Heartbeats peleándose por el mismo personaje.

local previous = getgenv and getgenv().VANTA_STRONGMAN

if type(previous) == "table" and type(previous.Stop) == "function" then
    pcall(previous.Stop)
    print("[SM] había una copia anterior: apagada antes de arrancar esta.")
end

-- ─── Menú ──────────────────────────────────────────────────

local okLibrary, Rayfield = pcall(function()
    return loadstring(game:HttpGet("https://sirius.menu/gen2"))()
end)

if not okLibrary or not Rayfield then
    warn("[SM] no se pudo cargar el menú: " .. tostring(Rayfield))
    return nil
end

local window, windowError = Kit.Mount(Rayfield, {
    name = "VANTA | STRONGMAN SIMULATOR",
    subtitle = "un módulo por pestaña",
    sidebarLayout = true,
    configuration = {
        autoSave = true,
        autoLoad = true,
        fileName = "VANTA_Strongman",
    },
})

if not window then
    warn("[SM] no se pudo crear la ventana: " .. tostring(windowError))
    return nil
end

-- ─── Carga de secciones ────────────────────────────────────

for _, record in ipairs(Sections.List()) do
    task.spawn(function()
        Sections.Load(record.name)
    end)
end

-- ─── Entrenamiento (fuerza) ────────────────────────────────

local tab = Kit.Tab("Entrenamiento")

if tab then
    Kit.Action(tab, "Subir fuerza", "Invoca StrongMan_UpgradeStrength y mide", function()
        return training.Upgrade()
    end)

    Kit.Action(tab, "Entrenar x10", "Diez subidas seguidas, con la fuerza medida", function()
        return training.Grind(10)
    end)

    Kit.Action(tab, "Entrenar x50", "Cincuenta subidas, con la fuerza medida", function()
        return training.Grind(50)
    end)

    local multiplierSlider = Kit.Slider(tab, {
        name = "Multiplicador",
        description = "Cuánto se le pide al remoto en cada llamada",
        min = 1,
        max = 500,
        default = 10,
        callback = function(value)
            training.SetMultiplier(value)
        end,
    })

    if multiplierSlider and multiplierSlider.Set then
        pcall(function()
            multiplierSlider:Set(10)
        end)
    end

    Kit.Flag(tab, "Entrenar solo", "Sube la fuerza cada segundo", "auto",
        training.SetAuto)
end

-- ─── Arrastre (energía) ────────────────────────────────────

tab = Kit.Tab("Arrastre")

if tab then
    Kit.Action(tab, "Arrastrar a la meta", "Mueve tus piezas al Goal y mide la energía", function()
        return dragging.Pull()
    end)

    Kit.Action(tab, "Sujetar el Pyrámide", "Activa su ProximityPrompt, comprobando que se sujeta", function()
        return dragging.Grab("PYRAMID")
    end)

    Kit.Action(tab, "Qué área es esta", "Dice en qué área estás y si tiene meta", function()
        local area, why = dragging.Area()

        if not area then
            return false, why
        end

        local goal = area:FindFirstChild("Goal")

        return true, string.format(
            "%s (meta: %s)",
            area.Name,
            goal and "sí" or "no"
        )
    end)

    Kit.Flag(tab, "Arrastrar solo", "Lleva tus piezas a la meta cada medio segundo", "auto",
        dragging.SetAuto)

    Kit.Dropdown(tab, {
        name = "Área",
        description = "Dónde arrastrar cuando hay varias abiertas",
        options = {
            "Area1_Gym", "Area9_Space", "Area14_Retro", "Area18_Apartment",
        },
        callback = function(value)
            dragging.SetArea(value)
        end,
    })
end

-- ─── Movimiento ────────────────────────────────────────────

tab = Kit.Tab("Movimiento")

if tab then
    Kit.Slider(tab, {
        name = "Velocidad",
        description = "studs por segundo",
        min = 16,
        max = 300,
        default = 64,
        callback = function(value)
            if State.Get("movement.speedOn", false) then
                movement.SetSpeed(value)
            else
                State.Set("movement.speed", value)
            end
        end,
    })

    Kit.Flag(tab, "Velocidad activa", "Aplica la velocidad del control de arriba", "speedOn",
        movement.SetSpeedOn)

    Kit.Slider(tab, {
        name = "Salto",
        description = "altura del salto",
        min = 50,
        max = 500,
        default = 100,
        callback = function(value)
            movement.SetJump(value)
        end,
    })

    Kit.Flag(tab, "Noclip", "Atraviesa el mapa", "noclip", movement.SetNoclip)
    Kit.Flag(tab, "Salto infinito", "Salta en el aire", "infJump", movement.SetInfJump)
    Kit.Flag(tab, "Flotar", "Te deja quieto en el aire (PlatformStand)", "float", movement.SetFloat)

    Kit.Action(tab, "Restaurar movimiento", "Devuelve velocidad, salto y colisiones", function()
        return movement.Restore()
    end)
end

-- ─── Mundo ─────────────────────────────────────────────────

tab = Kit.Tab("Mundo")

if tab then
    Kit.Action(tab, "Quitar puertas", "Destruye las salidas (Exit/Copy) de todas las áreas", function()
        return world.BreakExits()
    end)

    Kit.Flag(tab, "Sin peso extra", "Quita ExtraWeight de tus arrastres, también los nuevos", "noWeight",
        world.SetNoWeight)

    Kit.Action(tab, "¿Estoy anclado?", "Dice si el servidor te tiene sujeto ahora mismo", function()
        if world.IsAnchored() then
            return true, "sí: el servidor te tiene anclado (estás arrastrando o entrenando)"
        end

        return true, "no: te puedes mover"
    end)
end

-- ─── Jugadores ─────────────────────────────────────────────

tab = Kit.Tab("Jugadores")

if tab then
    Kit.Flag(tab, "ESP", "Resalta a los demás jugadores", "esp", players.SetESP)

    Kit.Input(tab, {
        name = "Nombre del jugador",
        description = "Para el teleport",
        placeholder = "Nombre o DisplayName",
        callback = function(value)
            State.Set("players.target", value)
        end,
    })

    Kit.Action(tab, "Teleport al jugador", "Mueve tu personaje y comprueba que sigues ahí", function()
        return players.ToPlayer(State.Get("players.target", ""))
    end)
end

-- ─── Códigos ───────────────────────────────────────────────

tab = Kit.Tab("Códigos")

if tab then
    Kit.Action(tab, "Canjear todos", "Prueba los códigos públicos y mide la energía", function()
        return codes.RedeemAll()
    end)

    Kit.Input(tab, {
        name = "Un código",
        description = "Se comprueba si la energía cambió",
        placeholder = "strongman",
        callback = function(value)
            State.Set("codes.one", value)
        end,
    })

    Kit.Action(tab, "Canjear ese", "Manda el código de arriba y comprueba", function()
        local code = State.Get("codes.one", "")

        if code == "" then
            return false, "escribe un código primero"
        end

        local ok, expired, detail = codes.Redeem(code)
        return ok or expired, detail
    end)
end

-- ─── Mascotas ──────────────────────────────────────────────

tab = Kit.Tab("Mascotas")

if tab then
    Kit.Action(tab, "Ver mis mascotas", "Busca tu inventario y lo lista", function()
        return pets.List()
    end)

    Kit.Action(tab, "Ver el catálogo", "Las mascotas del juego y su bonus", function()
        return true, table.concat(pets.Catalog(), ", ")
    end)

    Kit.Text(tab, {
        name = "Equipar desde la UI del juego",
        description = "El remoto de equipar no está verificado; el script no lo inventa",
    })
end

-- ─── Personaje ─────────────────────────────────────────────

tab = Kit.Tab("Personaje")

if tab then
    Kit.Slider(tab, {
        name = "Tamaño",
        description = "porcentaje del original (cosmético, no da fuerza)",
        min = 50,
        max = 300,
        default = 100,
        callback = function(value)
            avatar.SetSizePercent(value)
        end,
    })

    Kit.Flag(tab, "Anti-AFK", "El juego deja de expulsarte por inactividad", "antiafk",
        avatar.SetAntiAFK)

    Kit.Action(tab, "Tamaño original", "Devuelve el personaje a su escala", function()
        return avatar.ResetSize()
    end)

    Kit.Action(tab, "Subir en el aire", "Te sube 20 studs para mirar desde arriba", function()
        return avatar.Float(20)
    end)
end

-- ─── Diagnóstico ───────────────────────────────────────────

tab = Kit.Tab("Diagnóstico")

if tab then
    Kit.Action(tab, "Ver el estado", "Remotos, stats, secciones y huecos", function()
        return diagnostics.Print()
    end)

    Kit.Action(tab, "Probar la fuerza", "Una subida y te dice si de verdad subió", function()
        return training.Upgrade()
    end)

    Kit.Action(tab, "Cerrar todo", "Restaura y descarga el script", function()
        task.defer(function()
            local state = getgenv and getgenv().VANTA_STRONGMAN

            if state and type(state.Stop) == "function" then
                state.Stop()
            end
        end)

        return true, "cerrando"
    end)
end

-- ─── Cierre ────────────────────────────────────────────────

local started = os.clock()
local alive = true

local function stop()
    if not alive then
        return
    end

    alive = false

    -- Desconectar primero: si el bucle sigue vivo, vuelve a aplicar noclip o
    -- velocidad en el mismo frame.
    local closed = Sections.DisconnectAll()

    pcall(movement.Restore)
    pcall(avatar.Restore)
    pcall(players.SetESP, false)

    State.Reset()
    Kit.Unload()

    if getgenv then
        getgenv().VANTA_STRONGMAN = nil
    end

    print(string.format(
        "[SM] cerrado: %d conexiones cortadas, todo restaurado.",
        closed
    ))
end

getgenv().VANTA_STRONGMAN = {
    Stop = stop,
    sections = Sections,
    state = State,
    remotes = Remotes,
    modules = {
        training = training,
        dragging = dragging,
        movement = movement,
        world = world,
        players = players,
        codes = codes,
        pets = pets,
        avatar = avatar,
        diagnostics = diagnostics,
    },

    Verify = function()
        local health = Sections.Health()

        return {
            ok = health.broken == 0,
            total = health.total,
            healthy = health.healthy,
            broken = health.broken,
            placeId = game.PlaceId,
            ms = math.floor((os.clock() - started) * 1000),
            connections = Sections.ConnectionCount(),
            remotes = Remotes.Inventory(),
        }
    end,
}

-- Un solo aviso si algo no arrancó.
task.delay(0.3, function()
    local health = Sections.Health()

    if health.broken > 0 then
        Kit.Notify("Secciones rotas", string.format(
            "%d de %d no arrancaron. Mira Diagnóstico.",
            health.broken,
            health.total
        ))
    end
end)

return getgenv().VANTA_STRONGMAN
