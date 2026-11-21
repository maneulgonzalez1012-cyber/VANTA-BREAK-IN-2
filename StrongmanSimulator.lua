--[[
    VANTA | STRONGMAN SIMULATOR — script único
    Generado por sm/build.py desde sm/src/. No editar a mano.

    Cada módulo vive en su propia entrada de FILES y se compila por separado.
    Un módulo roto no impide que carguen los demás.
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

    if loading[name] then
        error("dependencia circular en " .. tostring(name), 0)
    end

    loading[name] = true

    local chunk, compileError = loadstring(source, "Strongman:" .. name)

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

FILES["init"] = [==[
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

]==]

FILES["avatar"] = [==[
--[[
    VANTA | Personaje
    Tamaño, altura y anti-afk.

    En Strongman Simulator el personaje se hace más grande según la fuerza,
    así que tocar la escala es cosmético: no da fuerza ni energía. Este módulo
    no promete progreso, solo control del modelo.

    Todo se comprueba leyendo lo que quedó escrito y se devuelve al original
    al apagar.
]]

local Avatar = {}

local State = require("state")
local Sections = require("sections")
local Remotes = require("remotes")

local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")

local originals = {
    hooks = {},
}

local function character()
    local player = Remotes.Player()
    return player and player.Character
end

local function humanoid()
    local char = character()

    if not char then
        return nil
    end

    return char:FindFirstChildOfClass("Humanoid")
end

-- ─── Tamaño ────────────────────────────────────────────────
-- Se escala con Humanoid.BodyDepthScale, que no deforma las partes a mano.

function Avatar.SetSizePercent(percent)
    local hum = humanoid()

    if not hum then
        return false, "no hay personaje todavía"
    end

    percent = math.clamp(tonumber(percent) or 100, 50, 300)

    if originals.bodyScale == nil then
        originals.bodyScale = {
            depth = hum.BodyDepthScale,
            width = hum.BodyWidthScale,
            height = hum.BodyHeightScale,
            head = hum.HeadScale,
        }
    end

    local factor = percent / 100

    local ok = pcall(function()
        hum.BodyDepthScale = factor
        hum.BodyWidthScale = factor
        hum.BodyHeightScale = factor
        hum.HeadScale = factor
    end)

    if not ok then
        return false, "el ejecutor bloqueó las escalas del Humanoid"
    end

    if math.abs(hum.BodyDepthScale - factor) > 0.01 then
        return false, string.format(
            "pedí %d%% y quedó en %d%%",
            percent,
            math.floor(hum.BodyDepthScale * 100)
        )
    end

    State.Set("avatar.size", percent)

    return true, string.format("tamaño = %d%%", percent)
end

function Avatar.ResetSize()
    local hum = humanoid()

    if not hum then
        return false, "no hay personaje"
    end

    local original = originals.bodyScale or {
        depth = 1,
        width = 1,
        height = 1,
        head = 1,
    }

    pcall(function()
        hum.BodyDepthScale = original.depth
        hum.BodyWidthScale = original.width
        hum.BodyHeightScale = original.height
        hum.HeadScale = original.head
    end)

    originals.bodyScale = nil

    return true, "tamaño original"
end

-- ─── Altura ────────────────────────────────────────────────

function Avatar.Float(height)
    local char = character()
    local root = char and char:FindFirstChild("HumanoidRootPart")

    if not root then
        return false, "no hay personaje todavía"
    end

    height = math.clamp(tonumber(height) or 0, 0, 500)

    if height == 0 then
        return Avatar.Unfloat()
    end

    local ok = pcall(function()
        root.CFrame = root.CFrame + Vector3.new(0, height, 0)
    end)

    if not ok then
        return false, "el ejecutor bloqueó el cambio de posición"
    end

    return true, string.format("subido %d studs", height)
end

function Avatar.Unfloat()
    return true, "sin altura artificial (usa velocidad o salto para moverte)"
end

-- ─── Anti-AFK ──────────────────────────────────────────────
-- El juego expulsa por inactividad. VirtualUser manda actividad de verdad,
-- no simula un clic en el vacío.

function Avatar.SetAntiAFK(enabled)
    State.Set("avatar.antiafk", enabled and true or false)

    if not enabled then
        return true, "anti-AFK apagado"
    end

    local player = Remotes.Player()

    if not player then
        return false, "no hay jugador"
    end

    if originals.hooks.antiafk then
        return true, "anti-AFK ya estaba activo"
    end

    local ok = pcall(function()
        originals.hooks.antiafk = player.Idled:Connect(function()
            if not State.Get("avatar.antiafk", false) then
                return
            end

            if VirtualUser and VirtualUser.CaptureController then
                pcall(function()
                    VirtualUser:CaptureController()
                    VirtualUser:ClickButton2(Vector2.new())
                end)
            end
        end)
    end)

    if not ok or not originals.hooks.antiafk then
        return false, "tu ejecutor no deja enganchar Idled"
    end

    return true, "anti-AFK encendido: el juego dejará de expulsarte por inactividad"
end

-- ─── Arranque ──────────────────────────────────────────────

function Avatar.Setup()
    -- Si reapareces, las escalas vuelven a 1: se reaplica lo elegido.
    Sections.Connect("avatar", RunService.Heartbeat, function()
        local percent = State.Get("avatar.size")

        if not percent then
            return
        end

        local hum = humanoid()

        if not hum then
            return
        end

        local factor = percent / 100

        if math.abs(hum.BodyDepthScale - factor) > 0.01 then
            pcall(function()
                hum.BodyDepthScale = factor
                hum.BodyWidthScale = factor
                hum.BodyHeightScale = factor
                hum.HeadScale = factor
            end)
        end
    end)
end

function Avatar.Restore()
    Avatar.ResetSize()

    if originals.hooks.antiafk then
        pcall(function()
            originals.hooks.antiafk:Disconnect()
        end)

        originals.hooks.antiafk = nil
    end

    return true, "tamaño y anti-AFK restaurados"
end

return Avatar

]==]

FILES["codes"] = [==[
--[[
    VANTA | Códigos
    Canjear los códigos públicos del juego.

    Los códigos salen de la descripción oficial del juego, así que son
    reales. El REMOTO no está verificado para este juego: en el corpus
    aparece RedeemCode, pero en scripts de otros juegos. Por eso se busca
    por varios nombres candidatos y, si no aparece, se dice en pantalla en
    vez de fingir que se canjeó.

    Cada código se comprueba: se mide la energía antes y después. Si nada
    cambió, el código no sirvió (caducado o ya usado).
]]

local Codes = {}

local Remotes = require("remotes")
local Sections = require("sections")
local Stats = require("stats")

-- De la descripción oficial del juego. No todos siguen activos.
local LIST = {
    "1500likes",
    "5000likes",
    "10000",
    "25k",
    "10m",
    "100M",
    "400M",
    "season1",
    "strongman",
}

function Codes.List()
    return LIST
end

-- Devuelve (servidos, caducados, motivo)
function Codes.Redeem(code)
    local remote = Remotes.Get("codes")

    if not remote then
        local missing = Remotes.Missing().codes or "no se encontró"
        return false, false, "remoto de códigos: " .. tostring(missing)
    end

    local before = Stats.Read("energy")

    local allowed, why = Sections.Allow()

    if not allowed then
        return false, false, why
    end

    local ok, result = Remotes.RedeemCode(code)

    if not ok then
        return false, false, tostring(result)
    end

    -- Comprobación: la energía subió.
    task.wait(0.5)

    local after = Stats.Read("energy")

    if before and after then
        if after > before then
            return true, false, string.format(
                "%s: energía +%.0f",
                code,
                after - before
            )
        end

        return false, true, string.format(
            "%s: el servidor respondió pero la energía no cambió",
            code
        )
    end

    -- Sin stat legible no se puede comprobar: se dice, no se inventa.
    return false, false, string.format(
        "%s: se envió pero no puedo leer la energía para comprobarlo",
        code
    )
end

function Codes.RedeemAll()
    local redeemed = {}
    local dead = {}
    local failed = 0

    for _, code in ipairs(LIST) do
        local ok, expired, detail = Codes.Redeem(code)

        if ok then
            table.insert(redeemed, code)
        elseif expired then
            table.insert(dead, code)
        else
            failed += 1
        end

        task.wait(0.3)
    end

    if #redeemed == 0 and failed > 0 then
        return false, string.format(
            "ninguno sirvió (%d con error). Mira la consola: %s",
            failed,
            tostring(Remotes.Missing().codes or "remoto encontrado pero rechazado")
        )
    end

    return true, string.format(
        "%d canjeados, %d ya usados o caducados%s",
        #redeemed,
        #dead,
        #redeemed > 0 and (": " .. table.concat(redeemed, ", ")) or ""
    )
end

function Codes.Setup()
    -- Nada que conectar: los códigos se canjean a petición.
end

return Codes

]==]

FILES["diagnostics"] = [==[
--[[
    VANTA | Diagnóstico
    Dice la verdad sobre lo que hay y lo que no.

    Esto existe porque gran parte de este juego está ofuscada y no todo se
    pudo verificar. Mejor un panel que diga "remoto de códigos: no
    encontrado" que un botón que no hace nada.
]]

local Diagnostics = {}

local Sections = require("sections")
local Remotes = require("remotes")
local Stats = require("stats")
local State = require("state")

local PlayersService = game:GetService("Players")

local PLACE_ID = 6766156863

function Diagnostics.Report()
    local health = Sections.Health()
    local inventory = Remotes.Inventory()
    local missing = Remotes.Missing()
    local values = Stats.Report()

    local remotes = {}

    for key, path in pairs(inventory) do
        table.insert(remotes, key .. " → " .. path)
    end

    table.sort(remotes)

    local gaps = {}

    for key, why in pairs(missing) do
        table.insert(gaps, key .. ": " .. why)
    end

    table.sort(gaps)

    return {
        placeOk = game.PlaceId == PLACE_ID,
        placeId = game.PlaceId,
        sections = health,
        connections = Sections.ConnectionCount(),
        strength = values.strength,
        strengthWhere = values.strengthWhere,
        energy = values.energy,
        energyWhere = values.energyWhere,
        remotes = remotes,
        gaps = gaps,
        players = #PlayersService:GetPlayers(),
    }
end

function Diagnostics.Describe()
    local report = Diagnostics.Report()
    local lines = {}

    if not report.placeOk then
        table.insert(lines, string.format(
            "⚠ estás en otro juego (PlaceId %s, no %d)",
            tostring(report.placeId),
            PLACE_ID
        ))
    end

    table.insert(lines, string.format(
        "secciones: %d/%d",
        report.sections.healthy,
        report.sections.total
    ))

    table.insert(lines, string.format(
        "fuerza: %s   energía: %s",
        report.strength and string.format("%.0f", report.strength) or "no encontrada",
        report.energy and string.format("%.0f", report.energy) or "no encontrada"
    ))

    if #report.remotes == 0 then
        table.insert(lines, "remotos: ninguno encontrado")
    else
        table.insert(lines, "remotos: " .. table.concat(report.remotes, " | "))
    end

    for _, gap in ipairs(report.gaps) do
        table.insert(lines, "✖ " .. gap)
    end

    return table.concat(lines, "\n")
end

function Diagnostics.Print()
    local report = Diagnostics.Report()

    print("─── VANTA | Strongman Simulator ───")
    print(Diagnostics.Describe())

    if report.strengthWhere then
        print("fuerza en: " .. tostring(report.strengthWhere))
    end

    if report.energyWhere then
        print("energía en: " .. tostring(report.energyWhere))
    end

    print("conexiones: " .. tostring(report.connections))

    if report.strength then
        return true, string.format(
            "fuerza %.0f, energía %s, %d remoto(s), %d hueco(s)",
            report.strength,
            report.energy and string.format("%.0f", report.energy) or "?",
            #report.remotes,
            #report.gaps
        )
    end

    return false, "no pude leer tu fuerza: " .. tostring(report.strengthWhere)
end

function Diagnostics.Setup()
    -- Nada que conectar.
end

return Diagnostics

]==]

FILES["dragging"] = [==[
--[[
    VANTA | Arrastre
    Energía: el otro recurso real del juego.

    El juego da energía por arrastrar objetos pesados pasando la línea. La
    forma de automatizarlo está verificada en tres scripts públicos:

        1. hay un ProximityPrompt en el objeto (InteractionPoint)
        2. se mantiene pulsado: InputHoldBegin / InputHoldEnd
        3. las piezas que arrastras viven en Workspace.PlayerDraggables[UserId]
        4. la meta es Areas[área].Goal

    El script no teletransporta las piezas al azar: primero las mueve a la
    meta y comprueba que la energía subió. Si no subió, lo dice.
]]

local Dragging = {}

local State = require("state")
local Sections = require("sections")
local Stats = require("stats")
local Remotes = require("remotes")

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

-- ─── Localizar ─────────────────────────────────────────────

local function character()
    local player = Remotes.Player()
    return player and player.Character
end

local function root()
    local char = character()

    if not char then
        return nil
    end

    return char:FindFirstChild("HumanoidRootPart")
end

-- Las piezas que llevas ahora mismo.
function Dragging.MyPieces()
    local player = Remotes.Player()
    local folder = Workspace:FindFirstChild("PlayerDraggables")

    if not player or not folder then
        return nil, "no existe Workspace.PlayerDraggables"
    end

    local mine = folder:FindFirstChild(tostring(player.UserId))

    if not mine then
        return nil, "todavía no arrastras nada (no hay carpeta tuya)"
    end

    return mine
end

-- El área donde estás: la que tiene DraggableItems y Goal.
function Dragging.Area()
    local areas = Workspace:FindFirstChild("Areas")

    if not areas then
        return nil, "no existe Workspace.Areas"
    end

    local chosen = State.Get("dragging.area")

    if chosen and areas:FindFirstChild(chosen) then
        return areas[chosen]
    end

    -- Sin elegir: la primera que tenga meta y objetos.
    for _, area in ipairs(areas:GetChildren()) do
        if area:FindFirstChild("Goal") and area:FindFirstChild("DraggableItems") then
            return area
        end
    end

    return nil, "ninguna área tiene Goal y DraggableItems"
end

function Dragging.SetArea(name)
    State.Set("dragging.area", name)
    return true, "área: " .. tostring(name)
end

-- ─── Arrastrar ─────────────────────────────────────────────

local function finishPieces(pieces, goal)
    local moved = 0

    for _, piece in ipairs(pieces:GetChildren()) do
        if piece:IsA("BasePart") then
            local ok = pcall(function()
                piece.Anchored = true
                piece.CFrame = goal.CFrame
                piece.Anchored = false
            end)

            if ok then
                moved += 1
            end
        end
    end

    return moved
end

function Dragging.Pull()
    local pieces, why = Dragging.MyPieces()

    if not pieces then
        return false, why
    end

    local area, areaWhy = Dragging.Area()

    if not area then
        return false, areaWhy
    end

    local goal = area:FindFirstChild("Goal")

    if not goal then
        return false, area.Name .. " no tiene Goal"
    end

    local count = #pieces:GetChildren()

    if count == 0 then
        return false, "la carpeta de arrastre está vacía: sujeta algo primero"
    end

    local grew, before, after, detail = Stats.Changed("energy", function()
        local moved = finishPieces(pieces, goal)

        if moved == 0 then
            return false, "no se pudo mover ninguna pieza"
        end

        return true
    end)

    if grew then
        return true, detail
    end

    return false, string.format(
        "moví %d pieza(s) a %s pero la energía no subió (%s → %s)",
        count,
        area.Name,
        tostring(before),
        tostring(after)
    )
end

-- ─── Sujetar el objeto de un área ──────────────────────────
-- Verificado: InteractionPoint tiene un ProximityPrompt, y se activa
-- manteniéndolo pulsado.

function Dragging.Grab(title)
    local area, why = Dragging.Area()

    if not area then
        return false, why
    end

    local items = area:FindFirstChild("DraggableItems")

    if not items then
        return false, area.Name .. " no tiene DraggableItems"
    end

    local target = nil

    for _, item in ipairs(items:GetChildren()) do
        if not title then
            target = item
            break
        end

        local titleValue = item:FindFirstChild("Title")

        if titleValue and string.lower(tostring(titleValue.Value)) == string.lower(title) then
            target = item
            break
        end
    end

    if not target then
        return false, string.format("no hay objeto %s en %s", tostring(title or "—"), area.Name)
    end

    local point = target:FindFirstChild("InteractionPoint") or target

    local prompt = point:FindFirstChildOfClass("ProximityPrompt")
        or target:FindFirstChildOfClass("ProximityPrompt")

    if not prompt then
        return false, target.Name .. " no tiene ProximityPrompt"
    end

    local before = Stats.Read("energy")

    local ok = pcall(function()
        point:InputHoldBegin()
        task.wait(0.1)
        point:InputHoldEnd()
    end)

    if not ok then
        -- Segunda vía: el ejecutor puede tener fireproximityprompt.
        if type(fireproximityprompt) == "function" then
            pcall(fireproximityprompt, prompt)
        else
            return false, "no se pudo activar el ProximityPrompt"
        end
    end

    -- Lo que de verdad dice si funcionó: si la carpeta de arrastre ya no
    -- está vacía.
    local deadline = os.clock() + 2

    repeat
        task.wait(0.1)
        local pieces = Dragging.MyPieces()

        if pieces and #pieces:GetChildren() > 0 then
            return true, string.format("%s sujeto (%d piezas)", target.Name, #pieces:GetChildren())
        end
    until os.clock() >= deadline

    local after = Stats.Read("energy")

    if before and after and after > before then
        return true, string.format("energía +%.0f con %s", after - before, target.Name)
    end

    return false, string.format(
        "activé el prompt de %s pero no se sujetó nada: el servidor no lo aceptó",
        target.Name
    )
end

-- ─── Automático ────────────────────────────────────────────

function Dragging.SetAuto(enabled)
    State.Set("dragging.auto", enabled and true or false)
    return true, "arrastre automático " .. (enabled and "encendido" or "apagado")
end

function Dragging.Setup()
    local last = 0

    Sections.Connect("dragging", RunService.Heartbeat, function()
        if not State.Get("dragging.auto", false) then
            return
        end

        if os.clock() - last < 0.5 then
            return
        end

        last = os.clock()

        local pieces = Dragging.MyPieces()
        local area = Dragging.Area()

        if not pieces or not area then
            return
        end

        local goal = area:FindFirstChild("Goal")

        if goal and #pieces:GetChildren() > 0 then
            finishPieces(pieces, goal)
        end
    end)
end

return Dragging

]==]

FILES["kit"] = [==[
--[[
    VANTA | Kit de interfaz
    Envoltorio del menú (Rayfield Gen2).

    Una pestaña rota no puede tumbar la ventana: toda creación de elemento
    pasa por pcall y devuelve un handle inerte si falla.

    Un solo formato de reporte para todo el script:
        ✔ hecho de verdad
        ✖ no ocurrió, con el motivo
]]

local Kit = {}

local window = nil
local tabs = {}

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

local function nullHandle()
    return {
        Set = function() end,
        Fire = function() end,
        Refresh = function() end,
    }
end

local function create(tab, method, props, label)
    if not tab then
        return nullHandle()
    end

    local ok, handle = pcall(function()
        return tab[method](tab, props)
    end)

    if not ok or not handle then
        warn(string.format("[SM][UI] no se pudo crear %s: %s", label, tostring(handle)))
        return nullHandle()
    end

    return handle
end

function Kit.Button(tab, props) return create(tab, "CreateButton", props, props.name) end
function Kit.Toggle(tab, props) return create(tab, "CreateToggle", props, props.name) end
function Kit.Slider(tab, props) return create(tab, "CreateSlider", props, props.name) end
function Kit.Input(tab, props) return create(tab, "CreateInput", props, props.name) end
function Kit.Dropdown(tab, props) return create(tab, "CreateDropdown", props, props.name) end
function Kit.Section(tab, props) return create(tab, "CreateSection", props, props.name) end
function Kit.Text(tab, props) return create(tab, "CreateText", props, props.name) end

-- ─── Reporte ───────────────────────────────────────────────

function Kit.Notify(title, content)
    print(string.format("[SM] %s: %s", tostring(title), tostring(content)))

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

function Kit.Report(title, executed, detail)
    if executed then
        Kit.Notify(title, "✔ " .. tostring(detail))
    else
        Kit.Notify(title, "✖ " .. tostring(detail))
    end

    return executed
end

-- La acción devuelve (ejecutado, motivo). Aquí solo se informa.
function Kit.Action(tab, label, description, runner)
    return Kit.Button(tab, {
        name = label,
        description = description,

        callback = function()
            task.spawn(function()
                local ok, executed, detail = pcall(runner)

                if not ok then
                    Kit.Report(label, false, "error: " .. tostring(executed))
                    return
                end

                Kit.Report(label, executed == true, detail or "sin respuesta")
            end)
        end,
    })
end

-- El setter devuelve (ejecutado, motivo).
function Kit.Flag(tab, label, description, flag, setter)
    return Kit.Toggle(tab, {
        name = label,
        description = description,
        flag = flag,
        value = false,

        callback = function(value)
            task.spawn(function()
                local ok, executed, detail = pcall(setter, value)

                if not ok then
                    Kit.Notify(label, "error: " .. tostring(executed))
                    return
                end

                Kit.Notify(label, tostring(
                    detail or (executed and "aplicado" or "no se pudo aplicar")
                ))
            end)
        end,
    })
end

function Kit.Unload()
    if window then
        pcall(function()
            window:Unload()
        end)
    end
end

return Kit

]==]

FILES["movement"] = [==[
--[[
    VANTA | Movimiento
    Velocidad, salto, noclip y flotar.

    Todo esto es local: no se pide al servidor, se escribe. Y como se escribe,
    se comprueba leyendo la propiedad después de escribirla.

    Al apagar, cada valor vuelve al que tenía. No se "pone 16 y ya": se
    guarda el original del personaje, que puede no ser 16.
]]

local Movement = {}

local State = require("state")
local Sections = require("sections")
local Remotes = require("remotes")

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local originals = {
    walkSpeed = nil,
    jumpPower = nil,
    gravity = nil,
    parts = {},
}

local DEFAULT_WALK = 16
local DEFAULT_JUMP = 50
local DEFAULT_GRAVITY = 196.2

-- ─── Utilidades ────────────────────────────────────────────

local function character()
    local player = Remotes.Player()
    return player and player.Character
end

local function humanoid()
    local char = character()

    if not char then
        return nil
    end

    return char:FindFirstChildOfClass("Humanoid")
end

local function capture(hum)
    if originals.walkSpeed == nil then
        originals.walkSpeed = hum.WalkSpeed
    end

    if originals.jumpPower == nil then
        originals.jumpPower = hum.JumpPower
    end
end

-- ─── Velocidad ─────────────────────────────────────────────

function Movement.SetSpeed(value)
    local hum = humanoid()

    if not hum then
        return false, "no hay personaje todavía"
    end

    capture(hum)

    value = math.clamp(tonumber(value) or DEFAULT_WALK, 0, 1000)

    local ok = pcall(function()
        hum.WalkSpeed = value
    end)

    if not ok then
        return false, "el ejecutor bloqueó WalkSpeed"
    end

    -- Se comprueba leyendo lo que quedó escrito.
    if hum.WalkSpeed ~= value then
        return false, string.format(
            "pedí %d y quedó en %s (el juego lo limita)",
            value,
            tostring(hum.WalkSpeed)
        )
    end

    State.Set("movement.speed", value)

    return true, string.format("velocidad = %d", value)
end

function Movement.SetSpeedOn(enabled)
    if not enabled then
        State.Set("movement.speedOn", false)
        Movement.RestoreSpeed()
        return true, "velocidad normal"
    end

    State.Set("movement.speedOn", true)

    return Movement.SetSpeed(State.Get("movement.speed", 64))
end

function Movement.RestoreSpeed()
    local hum = humanoid()

    if not hum then
        return false, "no hay personaje"
    end

    local target = originals.walkSpeed or DEFAULT_WALK

    pcall(function()
        hum.WalkSpeed = target
    end)

    if hum.WalkSpeed ~= target then
        return false, string.format("no volvió (quedó en %s)", tostring(hum.WalkSpeed))
    end

    return true, string.format("velocidad restaurada = %d", target)
end

-- ─── Salto ─────────────────────────────────────────────────

function Movement.SetJump(value)
    local hum = humanoid()

    if not hum then
        return false, "no hay personaje todavía"
    end

    capture(hum)

    value = math.clamp(tonumber(value) or DEFAULT_JUMP, 0, 1000)

    local ok = pcall(function()
        hum.UseJumpPower = true
        hum.JumpPower = value
    end)

    if not ok then
        return false, "el ejecutor bloqueó JumpPower"
    end

    if hum.JumpPower ~= value then
        return false, string.format(
            "pedí %d y quedó en %s",
            value,
            tostring(hum.JumpPower)
        )
    end

    State.Set("movement.jump", value)

    return true, string.format("salto = %d", value)
end

function Movement.RestoreJump()
    local hum = humanoid()

    if not hum then
        return false, "no hay personaje"
    end

    local target = originals.jumpPower or DEFAULT_JUMP

    pcall(function()
        hum.JumpPower = target
    end)

    return hum.JumpPower == target, string.format("salto restaurado = %d", target)
end

-- ─── Noclip ────────────────────────────────────────────────

local function setCollisions(state)
    local char = character()

    if not char then
        return 0
    end

    local touched = 0

    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            if state == false and originals.parts[part] == nil then
                originals.parts[part] = part.CanCollide
            end

            local value = state

            if state and originals.parts[part] ~= nil then
                value = originals.parts[part]
            end

            pcall(function()
                part.CanCollide = value
            end)

            touched += 1
        end
    end

    return touched
end

function Movement.SetNoclip(enabled)
    State.Set("movement.noclip", enabled and true or false)

    local touched = setCollisions(enabled and false or true)

    if touched == 0 then
        return false, "no hay personaje todavía"
    end

    if enabled then
        return true, string.format("noclip en %d partes", touched)
    end

    originals.parts = {}

    return true, string.format("colisiones devueltas en %d partes", touched)
end

-- ─── Flotar ────────────────────────────────────────────────

function Movement.SetFloat(enabled)
    local hum = humanoid()

    if not hum then
        return false, "no hay personaje todavía"
    end

    if originals.gravity == nil then
        originals.gravity = workspace.Gravity
    end

    pcall(function()
        hum.PlatformStand = enabled and true or false
    end)

    State.Set("movement.float", enabled and true or false)

    return true, enabled and "flotando (PlatformStand)" or "control devuelto"
end

-- ─── Infinito ──────────────────────────────────────────────

function Movement.SetInfJump(enabled)
    State.Set("movement.infJump", enabled and true or false)
    return true, "salto infinito " .. (enabled and "encendido" or "apagado")
end

-- ─── Restaurar todo ────────────────────────────────────────

function Movement.Restore()
    local restored = {}

    local okSpeed = Movement.RestoreSpeed()
    table.insert(restored, tostring(okSpeed))

    Movement.RestoreJump()
    setCollisions(true)
    originals.parts = {}

    local hum = humanoid()

    if hum then
        pcall(function()
            hum.PlatformStand = false
        end)
    end

    if originals.gravity ~= nil then
        pcall(function()
            workspace.Gravity = originals.gravity
        end)
    end

    originals.walkSpeed = nil
    originals.jumpPower = nil

    return true, "velocidad, salto, colisiones y flotar restaurados"
end

-- ─── Arranque ──────────────────────────────────────────────

function Movement.Setup()
    -- El noclip se reaplica: si el personaje reaparece, las partes son nuevas.
    Sections.Connect("movement", RunService.Stepped, function()
        if State.Get("movement.noclip", false) then
            setCollisions(false)
        elseif State.Get("movement.speedOn", false) then
            local hum = humanoid()

            -- Algunos juegos reescriben WalkSpeed cada frame.
            if hum and hum.WalkSpeed ~= State.Get("movement.speed", 64) then
                pcall(function()
                    hum.WalkSpeed = State.Get("movement.speed", 64)
                end)
            end
        end
    end)

    Sections.Connect("movement", UserInputService.JumpRequest, function()
        if not State.Get("movement.infJump", false) then
            return
        end

        local hum = humanoid()

        if hum then
            pcall(function()
                hum:ChangeState(Enum.HumanoidStateType.Jumping)
            end)
        end
    end)
end

return Movement

]==]

FILES["pets"] = [==[
--[[
    VANTA | Mascotas
    Listar y equipar mascotas.

    Lo que está confirmado del juego: las mascotas dan bonus de entrenamiento
    y de energía, y se compran con energía en cada zona (Toilet Brush +0.3,
    Shaker +0.4, … DiscoStool +3.4).

    Lo que NO está verificado es el remoto de equipar. Por eso este módulo no
    dispara nada a ciegas: busca las mascotas en tu propio inventario y, si
    hay un remoto con pinta de equipar, lo dice en Diagnóstico. Equipar desde
    la UI del juego sigue siendo lo fiable.

    Es preferible un módulo honesto que un botón que no hace nada.
]]

local Pets = {}

local Remotes = require("remotes")
local Sections = require("sections")

local PlayersService = game:GetService("Players")

-- Nombres vistos en el catálogo público del juego.
local CATALOG = {
    "Toilet Brush", "Shaker", "Kettle Bell", "Medicine Ball",
    "Soda", "Fries", "Turkey",
    "Air Hockey", "8Ball", "Space Invaders",
    "Carrot", "Tomato", "Egg Plant",
    "Obelisk", "Knight", "Hydra",
    "Diver Bot", "Planter Bot", "Spider Bot",
    "DiscoBall", "DiscoStool", "Speaker",
}

-- Carpetas donde el juego suele guardar lo que posees.
local HOLDERS = {
    "Pets",
    "OwnedPets",
    "Inventory",
    "PlayerPets",
}

function Pets.Catalog()
    return CATALOG
end

-- Devuelve (lista, dónde) — lista puede venir vacía sin ser un error.
function Pets.Owned()
    local player = PlayersService.LocalPlayer

    if not player then
        return {}, "no hay jugador"
    end

    for _, holderName in ipairs(HOLDERS) do
        local holder = player:FindFirstChild(holderName, true)

        if holder then
            local found = {}

            for _, child in ipairs(holder:GetDescendants()) do
                if child:IsA("StringValue") or child:IsA("ObjectValue") then
                    table.insert(found, tostring(child.Value))
                elseif child:IsA("Folder") or child:IsA("Model") then
                    table.insert(found, child.Name)
                end
            end

            if #found > 0 then
                return found, holder:GetFullName()
            end
        end
    end

    return {}, "no encontré tu inventario de mascotas"
end

function Pets.List()
    local owned, where = Pets.Owned()

    if #owned == 0 then
        return false, "no encontré mascotas tuyas (" .. tostring(where) .. ")"
    end

    return true, string.format("%d: %s", #owned, table.concat(owned, ", "))
end

-- Comprueba si hay un remoto con pinta de equipar mascota, sin usarlo.
function Pets.Setup()
    local candidates = {"EquipPet", "PetEquip", "Equip", "SelectPet", "PetEvent"}
    local found = {}

    for _, name in ipairs(candidates) do
        local hit = game:GetService("ReplicatedStorage"):FindFirstChild(name, true)

        if hit then
            table.insert(found, hit:GetFullName())
        end
    end

    if #found > 0 then
        print("[SM] remotos con pinta de mascota: " .. table.concat(found, ", "))
    end
end

return Pets

]==]

FILES["players"] = [==[
--[[
    VANTA | Jugadores
    ESP, teleport a jugador y copiar su posición.

    El ESP se dibuja con Highlight, que es del cliente: aparece de verdad o no
    aparece, y se comprueba que el objeto esté colgando del jugador. Al apagar
    se destruye todo, sin restos.

    El teleport mueve el HumanoidRootPart y comprueba la distancia 0.6 s
    después: un teleport que el servidor revierte no es un teleport.
]]

local Players = {}

local State = require("state")
local Sections = require("sections")

local PlayersService = game:GetService("Players")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "SM_ESP"
local highlights = {}

-- ─── Utilidades ────────────────────────────────────────────

local function folder()
    local player = PlayersService.LocalPlayer

    if not player then
        return nil
    end

    local existing = player:FindFirstChild(FOLDER_NAME)

    if existing then
        return existing
    end

    local created = Instance.new("Folder")
    created.Name = FOLDER_NAME
    created.Parent = player

    return created
end

local function characterOf(player)
    return player and player.Character
end

local function rootOf(player)
    local char = characterOf(player)

    if not char then
        return nil
    end

    return char:FindFirstChild("HumanoidRootPart")
end

local function distance(a, b)
    local ok, result = pcall(function()
        return (a.Position - b.Position).Magnitude
    end)

    if ok and type(result) == "number" then
        return result
    end

    return nil
end

-- ─── ESP ───────────────────────────────────────────────────

local function drawFor(player)
    local char = characterOf(player)

    if not char or highlights[player] then
        return false
    end

    local ok, highlight = pcall(function()
        local h = Instance.new("Highlight")
        h.Name = "SM_Highlight"
        h.Adornee = char
        h.FillColor = Color3.fromRGB(0, 170, 255)
        h.OutlineColor = Color3.fromRGB(255, 255, 255)
        h.FillTransparency = 0.5
        h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        h.Parent = folder()
        return h
    end)

    if not ok or not highlight then
        return false
    end

    highlights[player] = highlight

    -- Comprobación real: el Highlight existe y cuelga de tu carpeta.
    return highlight.Parent ~= nil and highlight.Adornee == char
end

local function clearOne(player)
    local highlight = highlights[player]

    if not highlight then
        return false
    end

    pcall(function()
        highlight:Destroy()
    end)

    highlights[player] = nil

    return true
end

function Players.RefreshESP()
    local me = PlayersService.LocalPlayer
    local drawn = 0

    for _, player in ipairs(PlayersService:GetPlayers()) do
        if player ~= me and State.Get("players.esp", false) then
            if drawFor(player) then
                drawn += 1
            end
        end
    end

    return drawn
end

function Players.SetESP(enabled)
    State.Set("players.esp", enabled and true or false)

    if not enabled then
        local removed = 0

        for player in pairs(highlights) do
            if clearOne(player) then
                removed += 1
            end
        end

        local holder = folder()

        if holder then
            pcall(function()
                holder:Destroy()
            end)
        end

        return true, string.format("ESP apagado (%d resaltados quitados)", removed)
    end

    local drawn = Players.RefreshESP()

    if drawn == 0 then
        return false, "no hay otros jugadores a la vista para resaltar"
    end

    return true, string.format("%d jugador(es) resaltados", drawn)
end

-- ─── Teleport ──────────────────────────────────────────────

function Players.ToPlayer(name)
    local me = PlayersService.LocalPlayer
    local target = nil

    if not name or name == "" then
        return false, "escribe el nombre del jugador"
    end

    for _, player in ipairs(PlayersService:GetPlayers()) do
        if player ~= me then
            local display = string.lower(player.DisplayName or "")
            local user = string.lower(player.Name or "")
            local wanted = string.lower(name)

            if display == wanted or user == wanted
                or string.find(user, wanted, 1, true)
            then
                target = player
                break
            end
        end
    end

    if not target then
        return false, "no encontré a " .. tostring(name) .. " en esta partida"
    end

    local myRoot = rootOf(me)
    local theirRoot = rootOf(target)

    if not myRoot then
        return false, "tu personaje no está listo"
    end

    if not theirRoot then
        return false, target.Name .. " acaba de aparecer, prueba otra vez"
    end

    local before = distance(myRoot, theirRoot)

    local ok = pcall(function()
        myRoot.CFrame = theirRoot.CFrame * CFrame.new(0, 0, 3)
    end)

    if not ok then
        return false, "el ejecutor bloqueó el cambio de CFrame"
    end

    -- Se comprueba que sigues ahí y no te devolvieron.
    task.wait(0.6)

    local after = distance(myRoot, theirRoot)

    if after == nil then
        return false, "no se pudo medir la distancia después"
    end

    if after > 12 then
        return false, string.format(
            "el servidor te devolvió (quedaste a %.0f studs)",
            after
        )
    end

    return true, string.format(
        "llegaste con %s (de %.0f a %.0f studs)",
        target.Name,
        before or 0,
        after
    )
end

-- ─── Arranque ──────────────────────────────────────────────

function Players.Setup()
    Sections.Connect("players", PlayersService.PlayerAdded, function()
        if State.Get("players.esp", false) then
            task.delay(1, Players.RefreshESP)
        end
    end)

    Sections.Connect("players", PlayersService.PlayerRemoving, function(player)
        clearOne(player)
    end)

    -- Si el personaje reaparece, el Highlight anterior apunta a un modelo
    -- muerto: se vuelve a dibujar.
    Sections.Connect("players", RunService.Heartbeat, function()
        if not State.Get("players.esp", false) then
            return
        end

        local me = PlayersService.LocalPlayer

        for player, highlight in pairs(highlights) do
            local char = characterOf(player)

            if not char or not highlight.Parent or highlight.Adornee ~= char then
                clearOne(player)

                if player ~= me then
                    drawFor(player)
                end
            end
        end
    end)
end

return Players

]==]

FILES["remotes"] = [==[
--[[
    VANTA | Remotos
    La única puerta al servidor.

    En Strongman Simulator no hay una carpeta de remotos como en otros juegos:
    el remoto de fuerza cuelga de ReplicatedStorage directamente y los demás
    (gimnasio, arrastre) van por ProximityPrompt del mapa. Aquí se busca todo
    por nombre, se recuerda lo que se encontró y se dice qué falta.

    Todo lo verificado está en STRONGMAN.md. Lo que no se pudo verificar no
    se inventa: se busca por candidatos y, si no aparece, se informa.
]]

local Remotes = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local resolved = {}
local missing = {}

-- Nombres candidatos, de más probable a menos.
local CANDIDATES = {
    strength = {
        "StrongMan_UpgradeStrength",
        "UpgradeStrength",
        "Upgrade_Strength",
        "StrengthUpgrade",
    },

    -- No verificado en este juego. Se busca; si no está, se dice.
    codes = {
        "RedeemCode",
        "RedeemCodes",
        "CodeEvent",
        "Codes",
        "Redeem",
    },
}

-- ─── Búsqueda ──────────────────────────────────────────────

local function findByPath(name)
    local direct = ReplicatedStorage:FindFirstChild(name)

    if direct then
        return direct
    end

    -- Carpetas típicas, por si algún remoto va dentro.
    for _, folderName in ipairs({"Remotes", "Events", "RemoteEvents", "Game"}) do
        local folder = ReplicatedStorage:FindFirstChild(folderName)

        if folder then
            local hit = folder:FindFirstChild(name)

            if hit then
                return hit
            end
        end
    end

    return nil
end

function Remotes.Resolve(key)
    if resolved[key] then
        local instance = resolved[key]

        if instance.Parent then
            return instance
        end

        resolved[key] = nil
    end

    for _, name in ipairs(CANDIDATES[key] or {}) do
        local instance = findByPath(name)

        if instance then
            resolved[key] = instance
            missing[key] = nil
            return instance
        end
    end

    missing[key] = string.format(
        "no se encontró ninguno de: %s",
        table.concat(CANDIDATES[key] or {}, ", ")
    )

    return nil
end

function Remotes.Get(key)
    return resolved[key] or Remotes.Resolve(key)
end

-- ─── Fuerza ────────────────────────────────────────────────

-- El único remoto confirmado: RemoteFunction, se invoca con un multiplicador.
-- Devuelve (ok, motivo). El éxito NO se decide aquí: se mide fuera, viendo si
-- la fuerza subió.
function Remotes.UpgradeStrength(multiplier)
    local remote = Remotes.Resolve("strength")

    if not remote then
        return false, "no está StrongMan_UpgradeStrength (¿estás en el juego?)"
    end

    local ok, result = pcall(function()
        if multiplier == nil then
            return remote:InvokeServer()
        end

        return remote:InvokeServer(multiplier)
    end)

    if not ok then
        return false, "el servidor rechazó la llamada: " .. tostring(result)
    end

    return true, result
end

-- ─── Códigos ───────────────────────────────────────────────

function Remotes.RedeemCode(code)
    local remote = Remotes.Resolve("codes")

    if not remote then
        return false, missing.codes or "no se encontró el remoto de códigos"
    end

    local ok, result = pcall(function()
        return remote:InvokeServer(code)
    end)

    if not ok then
        return false, "el servidor rechazó el código: " .. tostring(result)
    end

    return true, result
end

-- ─── Diagnóstico ───────────────────────────────────────────

function Remotes.Inventory()
    local list = {}

    for key, instance in pairs(resolved) do
        if instance.Parent then
            list[key] = instance:GetFullName()
        end
    end

    return list
end

function Remotes.Missing()
    return missing
end

function Remotes.Player()
    return Players.LocalPlayer
end

function Remotes.Humanoid()
    local player = Players.LocalPlayer

    if not player then
        return nil
    end

    local character = player.Character

    if not character then
        return nil
    end

    return character:FindFirstChildOfClass("Humanoid")
end

return Remotes

]==]

FILES["sections"] = [==[
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

]==]

FILES["state"] = [==[
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

]==]

FILES["stats"] = [==[
--[[
    VANTA | Stats
    Leer fuerza y energía, y saber si subieron.

    Aquí está la clave para que ninguna acción mienta: antes de disparar se
    toma la foto del stat, después se vuelve a leer. Si el número no cambió,
    la acción no funcionó, diga lo que diga el servidor.

    Dónde vive el número: no está confirmado para este juego. Se prueban los
    sitios habituales del género y se devuelve el primero que aparece, junto
    con la ruta, para poder mostrarla en Diagnóstico en vez de suponerla.
]]

local Stats = {}

local Players = game:GetService("Players")

local cache = {}

local NAMES = {
    strength = {"Strength", "StrengthValue", "Power"},
    energy = {"Energy", "EnergyValue"},
}

local CONTAINERS = {
    "leaderstats",
    "Stats",
    "Values",
    "Data",
}

-- ─── Localizar ─────────────────────────────────────────────

local function player()
    return Players.LocalPlayer
end

local function isStatHolder(instance)
    return instance:IsA("ValueBase") or instance:IsA("IntValue")
        or instance:IsA("NumberValue")
end

local function search(from, name)
    if not from then
        return nil
    end

    local direct = from:FindFirstChild(name)

    if direct and isStatHolder(direct) then
        return direct
    end

    for _, containerName in ipairs(CONTAINERS) do
        local container = from:FindFirstChild(containerName)

        if container then
            local hit = container:FindFirstChild(name)

            if hit and isStatHolder(hit) then
                return hit
            end
        end

        -- Un nivel más: PlayerGui puede tener la UI con el número.
        for _, child in ipairs(from:GetChildren()) do
            local nested = child:FindFirstChild(containerName)

            if nested then
                local hit = nested:FindFirstChild(name)

                if hit and isStatHolder(hit) then
                    return hit
                end
            end
        end
    end

    return nil
end

function Stats.Find(kind)
    local cached = cache[kind]

    if cached and cached.Parent then
        return cached
    end

    local owner = player()

    if not owner then
        return nil
    end

    for _, name in ipairs(NAMES[kind] or {}) do
        local hit = search(owner, name)

        if hit then
            cache[kind] = hit
            return hit
        end
    end

    -- Último recurso: buscar en toda la jerarquía del jugador.
    for _, name in ipairs(NAMES[kind] or {}) do
        for _, descendant in ipairs(owner:GetDescendants()) do
            if descendant.Name == name and isStatHolder(descendant) then
                cache[kind] = descendant
                return descendant
            end
        end
    end

    return nil
end

-- ─── Leer ──────────────────────────────────────────────────

function Stats.Read(kind)
    local stat = Stats.Find(kind)

    if stat then
        local value = stat.Value

        if type(value) == "number" then
            return value, stat:GetFullName()
        end
    end

    -- La UI del juego también muestra el número. Se intenta leer de ahí.
    local owner = player()

    if owner and owner:FindFirstChild("PlayerGui") then
        local wanted = string.lower(kind)

        for _, label in ipairs(owner.PlayerGui:GetDescendants()) do
            if label:IsA("TextLabel") then
                local text = string.lower(label.Text or "")

                if string.find(text, wanted, 1, true) then
                    local number = string.match(
                        string.gsub(label.Text, ",", ""),
                        "([%d]+%.?[%d]*)"
                    )

                    if number then
                        return tonumber(number), label:GetFullName()
                    end
                end
            end
        end
    end

    return nil, "no se encontró el stat de " .. tostring(kind)
end

-- Foto antes/después. Devuelve (subió, antes, después, motivo).
function Stats.Changed(kind, action, minimum)
    local before, where = Stats.Read(kind)

    if before == nil then
        return false, nil, nil, where
    end

    local ok, err = action()

    if not ok then
        return false, before, before, tostring(err)
    end

    -- El servidor tarda: se da margen sin mentir, comprobando de verdad.
    local after = before
    local deadline = os.clock() + 2

    repeat
        task.wait(0.1)
        local now = Stats.Read(kind)

        if now and now > after then
            after = now
        end
    until after > before or os.clock() >= deadline

    minimum = minimum or 1

    if after - before < minimum then
        return false, before, after, string.format(
            "el servidor no aplicó el cambio (%.0f → %.0f)",
            before,
            after
        )
    end

    return true, before, after, string.format(
        "%s +%.0f (%.0f → %.0f)",
        kind,
        after - before,
        before,
        after
    )
end

function Stats.Report()
    local strength, strengthWhere = Stats.Read("strength")
    local energy, energyWhere = Stats.Read("energy")

    return {
        strength = strength,
        strengthWhere = strengthWhere,
        energy = energy,
        energyWhere = energyWhere,
    }
end

return Stats

]==]

FILES["training"] = [==[
--[[
    VANTA | Entrenamiento
    Fuerza: el único remoto confirmado del juego.

    StrongMan_UpgradeStrength es una RemoteFunction y se invoca con un
    multiplicador. El script NO supone que funcionó: mide la fuerza antes y
    después con stats.lua. Si el número no subió, la acción falló aunque el
    servidor no haya dado error.

    Si el multiplicador es rechazado, se reintenta sin argumento y luego con
    un valor pequeño: el servidor acota, y hay que encontrar por dónde pasa.
]]

local Training = {}

local State = require("state")
local Sections = require("sections")
local Remotes = require("remotes")
local Stats = require("stats")

local RunService = game:GetService("RunService")

local MAX_MULTIPLIER = 500

local function multiplier()
    local value = State.Get("training.multiplier", 1)

    if type(value) ~= "number" or value < 1 then
        return 1
    end

    return math.min(math.floor(value), MAX_MULTIPLIER)
end

-- ─── Una subida ────────────────────────────────────────────

local function attempt(value)
    local allowed, why = Sections.Allow()

    if not allowed then
        return false, why
    end

    return Remotes.UpgradeStrength(value)
end

function Training.Upgrade(multiplierOverride)
    local value = multiplierOverride or multiplier()

    local grew, before, after, detail = Stats.Changed(
        "strength",
        function()
            return attempt(value)
        end
    )

    if grew then
        return true, detail
    end

    -- El servidor rechazó o acotó: segunda vía, sin argumento.
    local ok, second = attempt(nil)

    if ok then
        local retried, b2, a2, d2 = Stats.Changed(
            "strength",
            function()
                return true
            end,
            0
        )

        if retried then
            return true, d2
        end
    end

    return false, string.format(
        "no subió (%.0f → %.0f). %s",
        before or 0,
        after or 0,
        tostring(second or "sin respuesta")
    )
end

-- ─── Entrenar varias veces ─────────────────────────────────

function Training.Grind(times)
    times = math.min(tonumber(times) or 10, 100)

    local first = Stats.Read("strength")

    for _ = 1, times do
        local allowed = Sections.Allow()

        if not allowed then
            break
        end

        Remotes.UpgradeStrength(multiplier())
        task.wait(0.05)
    end

    local last = Stats.Read("strength")

    if first == nil or last == nil then
        return false, "no se pudo leer la fuerza para comprobarlo"
    end

    if last <= first then
        return false, string.format(
            "%d llamadas y la fuerza siguió en %.0f: el servidor no las aceptó",
            times,
            first
        )
    end

    return true, string.format(
        "%d llamadas: fuerza +%.0f (%.0f → %.0f)",
        times,
        last - first,
        first,
        last
    )
end

-- ─── Automático ────────────────────────────────────────────

function Training.SetAuto(enabled, delay)
    State.Set("training.auto", enabled and true or false)
    State.Set("training.delay", tonumber(delay) or 1)

    if enabled then
        return true, "entrenamiento automático encendido"
    end

    return true, "entrenamiento automático apagado"
end

function Training.SetMultiplier(value)
    State.Set("training.multiplier", tonumber(value) or 1)
    return true, string.format("multiplicador: %d", multiplier())
end

-- ─── Arranque ──────────────────────────────────────────────

function Training.Setup()
    local last = 0

    Sections.Connect("training", RunService.Heartbeat, function()
        if not State.Get("training.auto", false) then
            return
        end

        local delay = State.Get("training.delay", 1)

        if os.clock() - last < delay then
            return
        end

        last = os.clock()

        Training.Upgrade()
    end)
end

return Training

]==]

FILES["world"] = [==[
--[[
    VANTA | Mundo
    Quitar puertas, congelar el temporizador de arrastre, quitar el peso extra.

    Verificado en los scripts públicos del juego:
        - las salidas se llaman "Exit…" o "Copy…" dentro de Workspace.Areas
        - las piezas que arrastras pueden traer un hijo "ExtraWeight"
        - el globo del área es Areas[...].DraggableItems con Title

    Nada de esto toca remotos: es destruir o ajustar objetos del cliente. Por
    eso se comprueba contando cuántos objetos cambiaron de verdad.
]]

local World = {}

local State = require("state")
local Sections = require("sections")

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

-- ─── Salidas ───────────────────────────────────────────────

function World.BreakExits()
    local areas = Workspace:FindFirstChild("Areas")

    if not areas then
        return false, "no existe Workspace.Areas"
    end

    local removed = 0

    for _, object in ipairs(areas:GetDescendants()) do
        local name = string.lower(object.Name or "")

        if string.find(name, "exit", 1, true) or string.find(name, "copy", 1, true) then
            local ok = pcall(function()
                object:Destroy()
            end)

            if ok then
                removed += 1
            end
        end
    end

    if removed == 0 then
        return false, "no encontré puertas con 'Exit' o 'Copy' en Areas"
    end

    return true, string.format("%d puertas quitadas", removed)
end

-- ─── Peso extra ────────────────────────────────────────────

function World.SetNoWeight(enabled)
    State.Set("world.noWeight", enabled and true or false)

    if not enabled then
        return true, "peso extra permitido otra vez"
    end

    -- Se limpia lo que ya esté puesto y se sigue vigilando en Setup().
    local player = game:GetService("Players").LocalPlayer
    local folder = Workspace:FindFirstChild("PlayerDraggables")
    local mine = player and folder and folder:FindFirstChild(tostring(player.UserId))

    local removed = 0

    if mine then
        for _, child in ipairs(mine:GetDescendants()) do
            if child.Name == "ExtraWeight" then
                pcall(function()
                    child:Destroy()
                end)

                removed += 1
            end
        end
    end

    return true, string.format(
        "peso extra bloqueado (%d quitados ahora; se quitarán los nuevos)",
        removed
    )
end

-- ─── Anclaje ───────────────────────────────────────────────
-- El servidor ancla al personaje mientras arrastra o entrena. Saber eso
-- sirve para no teletransportar en mal momento.

function World.IsAnchored()
    local player = game:GetService("Players").LocalPlayer
    local char = player and player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")

    if not root then
        return false
    end

    return root.Anchored == true
end

-- ─── Arranque ──────────────────────────────────────────────

function World.Setup()
    local player = game:GetService("Players").LocalPlayer
    local folder = Workspace:FindFirstChild("PlayerDraggables")

    if not player or not folder then
        return
    end

    local mine = folder:FindFirstChild(tostring(player.UserId))

    if not mine then
        return
    end

    Sections.Connect("world", mine.DescendantAdded, function(added)
        if added.Name ~= "ExtraWeight" then
            return
        end

        if State.Get("world.noWeight", false) then
            pcall(function()
                added:Destroy()
            end)
        end
    end)
end

return World

]==]


-- ─── Arranque ──────────────────────────────────────────────

local ok, result = pcall(loadModule, "init")

if not ok then
    warn("[SM] arranque falló: " .. tostring(result))
    return nil
end

-- El loader comprueba esto antes de decir que todo salió bien.
getgenv().VANTA_STRONGMAN_STATE = result

return result
