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

FILES["combat"] = [=[
--[[
    VANTA | Combate
    Daño a NPC por HitBadguy(objetivo, 64.8, 4), comprobando el Humanoid.

    Tres resultados que NO se mezclan:
    - el servidor confirmó (la vida del Humanoid bajó)
    - solo en tu pantalla (escribiste Health y el servidor no se enteró)
    - rechazado (nada la movió)

    El auto-ataque es una bandera de esta sección: apagarla corta su bucle
    y no toca el resto del script.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local Remotes = require("remotes")
local State = require("state")
local Sections = require("sections")

local Player = Players.LocalPlayer

local Combat = {}

local ENEMY_FOLDERS = {"BadGuys", "BadGuysBoss", "BadGuysFront"}

local config = {
    amount = 65,
    burst = 4,
    radius = 120,
    interval = 0.6,
    lastRun = 0,
}

-- ─── Enemigos ──────────────────────────────────────────────

local function root()
    local character = Player.Character

    return character and character:FindFirstChild("HumanoidRootPart")
end

local function enemies()
    local list = {}
    local seen = {}

    local function add(object)
        if object and not seen[object] then
            seen[object] = true
            table.insert(list, object)
        end
    end

    for _, folderName in ipairs(ENEMY_FOLDERS) do
        local folder = Workspace:FindFirstChild(folderName)

        if folder then
            for _, npc in ipairs(folder:GetChildren()) do
                add(npc)
            end
        end
    end

    add(Workspace:FindFirstChild("BadGuyPizza", true))
    add(Workspace:FindFirstChild("BadGuyBrute", true))

    return list
end

local function enemyHumanoid(npc)
    if not npc then
        return nil
    end

    if npc:IsA("Humanoid") then
        return npc
    end

    return npc:FindFirstChildOfClass("Humanoid")
end

local function enemyRoot(npc)
    if not npc then
        return nil
    end

    if npc:IsA("BasePart") then
        return npc
    end

    if npc:IsA("Model") then
        return npc.PrimaryPart or npc:FindFirstChild("HumanoidRootPart")
    end

    return nil
end

function Combat.Count()
    local alive = 0

    for _, npc in ipairs(enemies()) do
        local hum = enemyHumanoid(npc)

        if hum and hum.Health > 0 then
            alive += 1
        end
    end

    return alive
end

-- ─── Golpear ───────────────────────────────────────────────

local function hitOne(npc)
    local hum = enemyHumanoid(npc)

    if not hum or hum.Health <= 0 then
        return false, "sin vida", false
    end

    local myRoot = root()
    local npcRoot = enemyRoot(npc)

    if myRoot and npcRoot then
        local distance = (npcRoot.Position - myRoot.Position).Magnitude

        if distance > config.radius then
            return false, string.format("a %d de distancia", math.floor(distance)), false
        end
    end

    local before = hum.Health
    local model = npc:IsA("Model") and npc or npcRoot
    local hits = math.clamp(config.burst, 1, 10)

    for _ = 1, hits do
        local ok, reason = Remotes.Send("HitBadguy", model, config.amount)

        if not ok then
            return false, "HitBadguy no existe en este lugar: " .. tostring(reason), false
        end
    end

    local hurt = Remotes.Await(function()
        return hum.Health < before
    end, 0.6)

    if hurt then
        return true, string.format("%d → %d", math.floor(before), math.floor(hum.Health)), false
    end

    -- El remoto no movió la vida. Se cierra en el cliente, pero se marca
    -- como local: eso NO es un éxito del servidor.
    if hum.Health > 0 then
        pcall(function()
            hum.Health = 0
        end)

        if hum.Health < before then
            return true, string.format("%d → 0 solo en tu pantalla", math.floor(before)), true
        end
    end

    return false, "el remoto no bajó la vida", false
end

function Combat.HitAll()
    local targets = enemies()

    if #targets == 0 then
        return false, "no hay NPC en el mapa (¿estás en la historia?)"
    end

    local damaged, killed, localOnly, failed = 0, 0, 0, 0

    for _, npc in ipairs(targets) do
        local ok, _, isLocal = hitOne(npc)

        if ok then
            damaged += 1

            if isLocal then
                localOnly += 1
            else
                local hum = enemyHumanoid(npc)

                if hum and hum.Health <= 0 then
                    killed += 1
                end
            end
        else
            failed += 1
        end

        task.wait(0.05)
    end

    local detail = string.format("%d dañados, %d caídos", damaged, killed)

    if localOnly > 0 then
        detail = detail .. string.format(", %d solo en tu pantalla", localOnly)
    end

    if failed > 0 then
        detail = detail .. string.format(", %d sin efecto", failed)
    end

    -- Solo es éxito lo que el servidor confirmó.
    return (killed > 0 or (damaged > 0 and localOnly == 0)), detail
end

function Combat.HitNearest()
    local myRoot = root()

    if not myRoot then
        return false, "no hay personaje"
    end

    local nearest, bestDistance = nil, math.huge

    for _, npc in ipairs(enemies()) do
        local hum = enemyHumanoid(npc)
        local npcRoot = enemyRoot(npc)

        if hum and hum.Health > 0 and npcRoot then
            local distance = (npcRoot.Position - myRoot.Position).Magnitude

            if distance < bestDistance then
                nearest, bestDistance = npc, distance
            end
        end
    end

    if not nearest then
        return false, "no hay ningún NPC vivo cerca"
    end

    local ok, detail, isLocal = hitOne(nearest)

    if ok and isLocal then
        return false, detail
    end

    return ok, detail
end

-- ─── Configuración ─────────────────────────────────────────

function Combat.SetDamage(amount)
    config.amount = math.clamp(tonumber(amount) or 65, 1, 200)
    return true, "daño por golpe: " .. config.amount
end

function Combat.SetAuto(enabled)
    State.Set("combat.auto", enabled and true or false)
    return true, "auto-ataque " .. (enabled and "activo" or "apagado")
end

-- ─── Arranque ──────────────────────────────────────────────

function Combat.Setup()
    Sections.Connect("combat", RunService.Heartbeat, function()
        if not State.Get("combat.auto") then
            return
        end

        if os.clock() - config.lastRun < config.interval then
            return
        end

        config.lastRun = os.clock()

        task.spawn(Combat.HitAll)
    end)
end

return Combat
]=]
FILES["init"] = [=[
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
]=]
FILES["items"] = [=[
--[[
    VANTA | Objetos
    Dar, equipar y comprobar en la mochila.

    Dos caminos, porque el servidor los trata distinto:
    - Armadura: Vending(3, "Armor2", "Armor", nombre, 1)
    - Arma:     Vending(3, "Crowbar2", "Weapons", nombre, 1)
    - Todo lo demás: GiveTool(nombre sin espacios)

    Nunca dice "enviado": comprueba que el Tool esté de verdad.
]]

local Players = game:GetService("Players")

local Remotes = require("remotes")

local Player = Players.LocalPlayer

local Items = {}

-- ─── Catálogo ──────────────────────────────────────────────

Items.weapons = {
    "Crowbar 1", "Crowbar 2", "Crowbar 3",
    "Bat", "Pitchfork", "Hammer", "Wrench", "Broom",
}

Items.food = {
    "Pizza", "Gold Pizza", "Rainbow Pizza", "Rainbow Pizza Box",
    "Cookie", "Apple", "Golden Apple", "Chips", "Lollipop",
    "Bloxy Cola", "Expired Bloxy Cola", "Bottle", "Battery",
}

Items.utility = {
    "Med Kit", "Armor", "Key", "Gold Key", "Louise", "Book", "Phone", "Ladder",
}

Items.all = {}

for _, list in ipairs({Items.food, Items.weapons, Items.utility}) do
    for _, item in ipairs(list) do
        table.insert(Items.all, item)
    end
end

local weaponSet = {}

for _, item in ipairs(Items.weapons) do
    weaponSet[item] = true
end

-- ─── Mochila ───────────────────────────────────────────────

local function toolName(item)
    return (tostring(item):gsub("%s", ""))
end

local function findTool(item)
    local name = toolName(item)
    local bag = Player:FindFirstChildOfClass("Backpack")
    local character = Player.Character

    if bag then
        local tool = bag:FindFirstChild(name)

        if tool then
            return tool, "mochila"
        end
    end

    if character then
        local tool = character:FindFirstChild(name)

        if tool then
            return tool, "mano"
        end
    end

    return nil
end

function Items.Has(item)
    return findTool(item) ~= nil
end

function Items.Count()
    local bag = Player:FindFirstChildOfClass("Backpack")
    local total = 0

    if bag then
        for _, child in ipairs(bag:GetChildren()) do
            if child:IsA("Tool") then
                total += 1
            end
        end
    end

    return total
end

function Items.Equip(item)
    local tool = findTool(item)
    local character = Player.Character

    if not tool then
        return false, "no tienes " .. tostring(item)
    end

    if not character then
        return false, "no hay personaje"
    end

    if tool.Parent == character then
        return true, tostring(item) .. " ya estaba en la mano"
    end

    local ok = pcall(function()
        tool.Parent = character
    end)

    if ok then
        return true, tostring(item) .. " en la mano"
    end

    return false, "no se pudo mover " .. tostring(item)
end

-- ─── Dar ───────────────────────────────────────────────────

function Items.Give(item)
    if type(item) ~= "string" or item == "" then
        return false, "ítem inválido"
    end

    if findTool(item) then
        local equipped, reason = Items.Equip(item)
        return true, reason .. " (ya lo tenías)"
    end

    local sent, reason

    if item == "Armor" then
        sent, reason = Remotes.Send("VendingArmor")
    elseif weaponSet[item] then
        -- "Crowbar 3" es la palanca de diamante: el servidor espera
        -- "Crowbar3", sin espacio.
        sent, reason = Remotes.Send("VendingWeapon", item)
    else
        sent, reason = Remotes.Send("GiveTool", item)
    end

    if not sent then
        return false, "no se pudo enviar: " .. tostring(reason)
    end

    -- Await devuelve el PRIMER valor del predicado, que es el Tool, no una
    -- etiqueta. La ubicación se pregunta aparte: findTool ya la devuelve.
    local arrived = Remotes.Await(function()
        return findTool(item)
    end, 1.2)

    if arrived then
        Items.Equip(item)

        local _, location = findTool(item)

        return true, string.format(
            "%s en la %s",
            item,
            tostring(location or "mochila")
        )
    end

    -- Segunda vía: el vending acepta a veces lo que GiveTool rechaza.
    if not weaponSet[item] and item ~= "Armor" then
        Remotes.Send("VendingWeapon", toolName(item))

        if Remotes.Await(function()
            return findTool(item)
        end, 0.8) then
            Items.Equip(item)
            return true, item .. " llegó por el vending"
        end
    end

    return false, item .. " no llegó a la mochila (el servidor lo rechazó)"
end

-- ─── Lotes ─────────────────────────────────────────────────

function Items.GiveKit()
    local wanted = {"Armor", "Golden Apple", "Med Kit", "Crowbar 2"}
    local arrived = 0

    for _, item in ipairs(wanted) do
        if Items.Give(item) then
            arrived += 1
        end

        task.wait(0.15)
    end

    for _ = 1, 6 do
        Items.Give("Gold Pizza")
        task.wait(0.1)
    end

    return arrived > 0, string.format("%d/%d del kit en la mochila", arrived, #wanted)
end

function Items.GiveAll()
    local arrived, refused = 0, 0

    for _, item in ipairs(Items.all) do
        if Items.Give(item) then
            arrived += 1
        else
            refused += 1
        end

        task.wait(0.12)
    end

    return arrived > 0, string.format(
        "%d en la mochila, %d rechazados por el servidor",
        arrived,
        refused
    )
end

function Items.Setup()
    -- Sin bucles: nada que mantener encendido.
end

return Items
]=]
FILES["kit"] = [=[
--[[
    VANTA | Kit de interfaz
    Envoltorio único del menú (Rayfield Gen2).

    Por qué: si cada sección llamara al menú directo, una sección rota
    podría tumbar la ventana entera. Aquí toda creación de elemento pasa
    por pcall y devuelve un handle mudo si falla, así el resto sigue vivo.

    Un solo formato de reporte para todo el script:
        ✔ hecho de verdad
        ✖ no ocurrió, con el motivo

    Nada de "solicitud enviada".
]]

local Kit = {}

local window = nil
local tabs = {}

-- ─── Ventana y tabs ────────────────────────────────────────

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

-- ─── Elementos ─────────────────────────────────────────────

-- Handle inerte: la sección puede seguir llamando sin comprobar nada.
local function nullHandle()
    return {
        Set = function() end,
        Lock = function() end,
        Unlock = function() end,
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
        warn(string.format("[VANTA][UI] no se pudo crear %s: %s", label, tostring(handle)))
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

function Kit.Report(title, executed, detail)
    if executed then
        Kit.Notify(title, "✔ " .. tostring(detail))
    else
        Kit.Notify(title, "✖ " .. tostring(detail))
    end

    return executed
end

-- ─── Botón de acción ───────────────────────────────────────
-- La sección devuelve (ejecutado, motivo). Aquí solo se informa.

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

-- ─── Toggle de bandera ─────────────────────────────────────
-- El setter de la sección devuelve (ejecutado, motivo).

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

-- ─── Cierre ────────────────────────────────────────────────

function Kit.Unload()
    if window then
        pcall(function()
            window:Unload()
        end)
    end
end

return Kit
]=]
FILES["lobby"] = [=[
--[[
    VANTA | Lobby
    Roles Hacker y Nerd por OutsideRole.

    Dos fuentes documentan la firma:
    - NoobHubV1 usa OutsideRole("Phone") / OutsideRole("Book") solo.
    - RScriptz y BreakingBlitz usan OutsideRole(item, true, false).

    Se prueban las tres formas y gana la que entregue la herramienta. Esa
    es la prueba real: si tienes el Phone, eres Hacker.

    Solo funciona en el lobby (PlaceIds 14775231477 y 13864661000).
]]

local Players = game:GetService("Players")

local Remotes = require("remotes")

local Player = Players.LocalPlayer

local Lobby = {}

Lobby.places = {
    [14775231477] = "Lobby privado",
    [13864661000] = "Lobby",
    [13864667823] = "Historia",
}

Lobby.roles = {
    Hacker = {item = "Phone", tool = "Phone"},
    Nerd = {item = "Book", tool = "Book"},
}

local function hasTool(name)
    local bag = Player:FindFirstChildOfClass("Backpack")
    local character = Player.Character

    if bag and bag:FindFirstChild(name) then
        return true
    end

    return character ~= nil and character:FindFirstChild(name) ~= nil
end

function Lobby.WhereAmI()
    return Lobby.places[game.PlaceId] or ("PlaceId " .. tostring(game.PlaceId))
end

function Lobby.SetRole(roleName)
    local role = Lobby.roles[roleName]

    if not role then
        return false, "rol desconocido: " .. tostring(roleName)
    end

    if hasTool(role.tool) then
        return true, "ya tienes " .. roleName
    end

    -- Las tres formas documentadas, de la más completa a la más simple.
    local forms = {
        {label = "item, true, false", args = {role.item, true, false}},
        {label = "item, true", args = {role.item, true}},
        {label = "item", args = {role.item}},
    }

    for _, form in ipairs(forms) do
        local ok = Remotes.Fire("OutsideRole", table.unpack(form.args))

        if ok then
            local arrived = Remotes.Await(function()
                return hasTool(role.tool)
            end, 1.5)

            if arrived then
                Remotes.Learn("lobby." .. roleName, form.label)

                return true, string.format("rol %s activo (%s)", roleName, form.label)
            end
        end
    end

    -- Se comprueba el lugar para no culpar al script de estar fuera.
    if game.PlaceId == 13864667823 then
        return false, "estás en la historia: los roles solo funcionan en el lobby"
    end

    return false, string.format(
        "el lobby no entregó %s (¿gamepass o lobby equivocado?)",
        roleName
    )
end

function Lobby.Setup()
    -- Nada que mantener encendido.
end

return Lobby
]=]
FILES["movement"] = [=[
--[[
    VANTA | Movimiento
    Velocidad, salto alto, salto infinito y noclip. TODO local.

    El servidor no puede rechazar algo que no le pediste: las propiedades
    se escriben cada frame desde Stepped.

    Restauración garantizada: se guardan los valores originales y se
    devuelven al apagar la bandera o al cerrar el script. Sin esto, apagar
    con noclip activo te deja atravesando el mapa para siempre.
]]

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local State = require("state")
local Sections = require("sections")

local Player = Players.LocalPlayer

local Movement = {}

local config = {
    speed = 32,
    jump = 78,
    original = nil,
    collisions = {},
}

local function humanoid()
    local character = Player.Character

    return character and character:FindFirstChildOfClass("Humanoid")
end

-- ─── Ajustes ───────────────────────────────────────────────

function Movement.SetSpeed(value)
    config.speed = math.clamp(tonumber(value) or 32, 8, 500)

    if State.Get("movement.speed") then
        local hum = humanoid()

        if hum then
            hum.WalkSpeed = config.speed
        end
    end

    return true, "velocidad ajustada a " .. config.speed
end

function Movement.SetJump(value)
    config.jump = math.clamp(tonumber(value) or 78, 50, 500)

    if State.Get("movement.jump") then
        local hum = humanoid()

        if hum then
            hum.UseJumpPower = true
            hum.JumpPower = config.jump
        end
    end

    return true, "salto ajustado a " .. config.jump
end

-- ─── Banderas ──────────────────────────────────────────────

function Movement.SetSpeedOn(enabled)
    State.Set("movement.speed", enabled and true or false)

    local hum = humanoid()

    if hum and not enabled and config.original then
        hum.WalkSpeed = config.original.walkSpeed
    end

    return true, "velocidad " .. (enabled and "activa" or "apagada")
end

function Movement.SetJumpOn(enabled)
    State.Set("movement.jump", enabled and true or false)

    local hum = humanoid()

    if hum and not enabled and config.original then
        hum.JumpPower = config.original.jumpPower
        hum.UseJumpPower = config.original.useJumpPower
    end

    return true, "salto alto " .. (enabled and "activo" or "apagado")
end

function Movement.SetInfJump(enabled)
    State.Set("movement.infJump", enabled and true or false)
    return true, "salto infinito " .. (enabled and "activo" or "apagado")
end

function Movement.SetNoclip(enabled)
    State.Set("movement.noclip", enabled and true or false)

    if not enabled then
        Movement.RestoreCollisions()
    end

    return true, "noclip " .. (enabled and "activo" or "apagado")
end

-- ─── Restauración ──────────────────────────────────────────

function Movement.RestoreCollisions()
    for part, original in pairs(config.collisions) do
        if part and part.Parent then
            pcall(function()
                part.CanCollide = original
            end)
        end
    end

    table.clear(config.collisions)
end

function Movement.Restore()
    local hum = humanoid()

    if hum and config.original then
        pcall(function()
            hum.WalkSpeed = config.original.walkSpeed
            hum.JumpPower = config.original.jumpPower
            hum.UseJumpPower = config.original.useJumpPower
        end)
    end

    Movement.RestoreCollisions()
end

-- ─── Bucle ─────────────────────────────────────────────────

local function capture()
    if config.original then
        return
    end

    local hum = humanoid()

    if not hum then
        return
    end

    config.original = {
        walkSpeed = hum.WalkSpeed,
        jumpPower = hum.JumpPower,
        useJumpPower = hum.UseJumpPower,
    }
end

local function applyNoclip()
    local character = Player.Character

    if not character then
        return
    end

    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            if config.collisions[part] == nil then
                config.collisions[part] = part.CanCollide
            end

            if part.CanCollide then
                part.CanCollide = false
            end
        end
    end
end

function Movement.Setup()
    Sections.Connect("movement", RunService.Stepped, function()
        local hum = humanoid()

        if hum then
            capture()

            if State.Get("movement.speed") then
                if hum.WalkSpeed ~= config.speed then
                    hum.WalkSpeed = config.speed
                end
            elseif config.original and hum.WalkSpeed ~= config.original.walkSpeed then
                hum.WalkSpeed = config.original.walkSpeed
            end

            if State.Get("movement.jump") then
                if not hum.UseJumpPower then
                    hum.UseJumpPower = true
                end

                if hum.JumpPower ~= config.jump then
                    hum.JumpPower = config.jump
                end
            elseif config.original and hum.JumpPower ~= config.original.jumpPower then
                hum.JumpPower = config.original.jumpPower
                hum.UseJumpPower = config.original.useJumpPower
            end
        end

        if State.Get("movement.noclip") then
            applyNoclip()
        end
    end)

    Sections.Connect("movement", UserInputService.JumpRequest, function()
        if not State.Get("movement.infJump") then
            return
        end

        local hum = humanoid()

        if hum and hum.Health > 0 then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end)
end

return Movement
]=]
FILES["navigation"] = [=[
--[[
    VANTA | Navegación
    Teleports de la historia y a jugadores.

    Todo local: se escribe CFrame. Si el servidor tiene anti-teleport y te
    devuelve, se dice; no se finge que funcionó.
]]

local Players = game:GetService("Players")

local Remotes = require("remotes")

local Player = Players.LocalPlayer

local Navigation = {}

-- Coordenadas del mapa real.
Navigation.places = {
    {name = "Tienda", cframe = CFrame.new(-246.653229, 30.4500484, -847.319275)},
    {name = "Cocina", cframe = CFrame.new(-249.753555, 30.4500484, -732.703125)},
    {name = "Arena de pelea", cframe = CFrame.new(-255.521988, 62.7139359, -723.436035)},
    {name = "Gimnasio", cframe = CFrame.new(-256.477448, 63.4500465, -840.825562)},
    {name = "Habitación central", cframe = CFrame.new(-209.951859, 30.4590473, -789.723877)},
    {name = "Pelea de jefe", cframe = CFrame.new(-1565.78772, -368.711945, -1040.66626)},
    {name = "Pilar de Scary Mary", cframe = CFrame.new(-1501.49597, -325.156891, -1060.63367)},
    {name = "Agente Bradley", cframe = CFrame.new(-281.792053, 95.4500275, -790.556946)},
    {name = "Twando", cframe = CFrame.new(-257.56839, 29.4499969, -910.452637)},
    {name = "Tío Pete", cframe = CFrame.new(-294.208923, 63.4182587, -737.712036)},
    {name = "Palanca dorada", cframe = CFrame.new(-147.337204, 29.4477005, -929.365295)},
    {name = "Máscara morada", cframe = CFrame.new(102.560722, 29.2477055, -976.389954)},
    {name = "Golden Apple", cframe = CFrame.new(61.8781624, 29.4499969, -534.381165)},
}

local function root()
    local character = Player.Character

    return character and character:FindFirstChild("HumanoidRootPart")
end

local function placeByName(name)
    for _, place in ipairs(Navigation.places) do
        if place.name == name then
            return place
        end
    end

    return nil
end

-- ─── Teleports ─────────────────────────────────────────────

function Navigation.ToPlace(name)
    local myRoot = root()

    if not myRoot then
        return false, "no hay personaje"
    end

    local place = placeByName(name)

    if not place then
        return false, "lugar desconocido: " .. tostring(name)
    end

    -- Tres intentos: algunos mapas devuelven al personaje una vez.
    for _ = 1, 3 do
        myRoot.CFrame = place.cframe
        task.wait(0.1)
    end

    local arrived = Remotes.Await(function()
        return (myRoot.Position - place.cframe.Position).Magnitude < 15
    end, 0.6)

    if arrived then
        return true, "en " .. name
    end

    return false, "el servidor devolvió el personaje (anti-teleport)"
end

function Navigation.FindPlayer(query)
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
            and (target.Name:lower():find(wanted, 1, true)
                or target.DisplayName:lower():find(wanted, 1, true))
        then
            return target
        end
    end

    return nil
end

function Navigation.ToPlayer(query)
    local myRoot = root()

    if not myRoot then
        return false, "no hay personaje"
    end

    if type(query) ~= "string" or query == "" then
        return false, "escribe un nombre primero"
    end

    local target = Navigation.FindPlayer(query)

    if not target then
        return false, "no encontré a " .. query
    end

    local targetRoot = target.Character
        and target.Character:FindFirstChild("HumanoidRootPart")

    if not targetRoot then
        return false, target.Name .. " no tiene personaje"
    end

    local destination = targetRoot.CFrame * CFrame.new(3, 0, 0)

    for _ = 1, 3 do
        myRoot.CFrame = destination
        task.wait(0.1)
    end

    local arrived = Remotes.Await(function()
        return (myRoot.Position - destination.Position).Magnitude < 15
    end, 0.6)

    if arrived then
        return true, "junto a " .. target.Name
    end

    return false, "el servidor devolvió el personaje"
end

function Navigation.Setup()
    -- Sin bucles: nada que mantener encendido.
end

return Navigation
]=]
FILES["remotes"] = [=[
--[[
    VANTA | Remotos
    La única puerta al servidor.

    Dos carpetas
    El juego expone los mismos remotos en dos sitios según el lugar:
    ReplicatedStorage.Events (historia) y ReplicatedStorage.RemoteEvents
    (lobby y algunas sesiones). Un script que solo mira "Events" falla en
    silencio en el lobby; uno que solo mira "RemoteEvents" falla en la
    historia. Aquí se prueban las dos.

    Firmas verificadas
    Cada remoto tiene su forma de argumentos sacada de scripts públicos
    que funcionan. El módulo no inventa argumentos: pide la forma por
    nombre y la recibe.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Remotes = {}

local FOLDERS = {"Events", "RemoteEvents"}

-- ─── Firmas verificadas ────────────────────────────────────
-- Fuentes: NoobHubV1/Break In 2 Story.lua, RScriptz/BreakIn2.lua,
-- Vcsk/BreakingBlitz.lua, carlwashere/BreakIn2.lua.

Remotes.SIGNATURES = {
    -- Objeto por nombre sin espacios.
    GiveTool = function(item)
        return {tostring(item):gsub("%s", "")}
    end,

    -- Armadura: (3, "Armor2", "Armor", nombre, 1)
    VendingArmor = function()
        return {3, "Armor2", "Armor", tostring(Players.LocalPlayer), 1}
    end,

    -- Arma: (3, "Crowbar2", "Weapons", nombre, 1)
    VendingWeapon = function(weaponId)
        return {3, tostring(weaponId):gsub("%s", ""), "Weapons", Players.LocalPlayer.Name, 1}
    end,

    -- Cura: cantidad positiva. Con negativa el servidor te daña.
    Energy = function(amount, item)
        return {amount, item or "Pizza"}
    end,

    -- Daño: (objetivo, 64.8, 4). El 4 es el índice del golpe.
    HitBadguy = function(target, damage)
        return {target, damage or 64.8, 4}
    end,

    -- Entrenamiento: "Speed" o "Strength".
    RainbowWhatStat = function(stat)
        return {stat}
    end,

    HealTheNoobs = function()
        return {}
    end,

    -- Rol del lobby: "Phone" = Hacker, "Book" = Nerd.
    OutsideRole = function(item, once)
        return {item, once ~= false, false}
    end,

    -- Objeto de tienda con posición: (6, {item2=, placement=})
    OutsideFood = function(item, placement)
        return {6, {item2 = item, placement = placement or 1}}
    end,

    -- Árbol caído de la misión.
    RoadMissionEvent = function(part)
        return {1, part, 5}
    end,

    LarryEndingEvent = function(key)
        return {key, true}
    end,

    KeyEvent = function()
        return {}
    end,

    CurePlayer = function(target)
        local player = target or Players.LocalPlayer
        return {player, player}
    end,

    CatFed = function(name)
        return {tostring(name)}
    end,

    LouiseGive = function(amount)
        return {amount or 2}
    end,

    IceSlip = function()
        return {Vector3.new(0, 0, 0)}
    end,
}

-- ─── Resolución ────────────────────────────────────────────

local cache = {}
local folderCache = {}

local function getFolder(name)
    local cached = folderCache[name]

    if cached and cached.Parent then
        return cached
    end

    local found = ReplicatedStorage:FindFirstChild(name)

    if found then
        folderCache[name] = found
        return found
    end

    return nil
end

-- Busca el remoto en las dos carpetas. Devuelve el objeto y dónde estaba.
function Remotes.Resolve(remoteName)
    local cached = cache[remoteName]

    if cached and cached.Parent then
        return cached
    end

    for _, folderName in ipairs(FOLDERS) do
        local container = getFolder(folderName)

        if container then
            local remote = container:FindFirstChild(remoteName)

            if remote and remote:IsA("RemoteEvent") then
                cache[remoteName] = remote
                return remote, folderName
            end
        end
    end

    return nil, nil
end

function Remotes.Exists(remoteName)
    return Remotes.Resolve(remoteName) ~= nil
end

function Remotes.Inventory()
    local names = {
        "GiveTool", "Vending", "Energy", "HealTheNoobs", "RainbowWhatStat",
        "HitBadguy", "IceSlip", "OutsideRole", "OutsideFood", "RoadMissionEvent",
        "LarryEndingEvent", "KeyEvent", "CurePlayer", "CatFed", "LouiseGive",
        "HitReplicate", "PagesReplicate", "OnDoorHit",
    }

    local found = {}

    for _, name in ipairs(names) do
        local remote, where = Remotes.Resolve(name)

        if remote then
            found[name] = where or "?"
        end
    end

    return found
end

-- ─── Presupuesto ───────────────────────────────────────────

local budget = {window = 1, max = 60, count = 0, started = 0}
local stats = {sent = 0, dropped = 0, failed = 0}

local function allowed()
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

function Remotes.Fire(remoteName, ...)
    local remote = Remotes.Resolve(remoteName)

    if not remote then
        stats.failed += 1
        return false, "no existe el remoto " .. tostring(remoteName)
    end

    if not allowed() then
        return false, "límite de 60 remotos/s alcanzado"
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

-- Dispara usando una firma con nombre.
function Remotes.Send(signatureName, ...)
    local builder = Remotes.SIGNATURES[signatureName]

    if not builder then
        return false, "firma desconocida: " .. tostring(signatureName)
    end

    -- El nombre del remoto es la firma sin sufijo (VendingArmor -> Vending).
    local remoteName = signatureName:gsub("Armor$", ""):gsub("Weapon$", "")

    local ok, args = pcall(builder, ...)

    if not ok then
        return false, "argumentos inválidos: " .. tostring(args)
    end

    return Remotes.Fire(remoteName, table.unpack(args, 1, #args))
end

-- ─── Espera de efecto ──────────────────────────────────────

function Remotes.Await(predicate, timeout)
    timeout = timeout or 1.5

    local started = os.clock()
    local spins = 0

    repeat
        local ok, value = pcall(predicate)

        if ok and value then
            return true, value
        end

        spins += 1
        task.wait(0.05)
    until os.clock() - started >= timeout or spins >= 60

    return false
end

-- ─── Firmas aprendidas ─────────────────────────────────────
-- La variante que el servidor aceptó se guarda para la próxima sesión.

local learned = {}

local function store()
    if type(getgenv) ~= "function" then
        return nil
    end

    local env = getgenv()
    env.VANTA_BI2_LEARNED = env.VANTA_BI2_LEARNED or {}
    return env.VANTA_BI2_LEARNED
end

function Remotes.Learned(action)
    local saved = store()
    return (saved and saved[action]) or learned[action]
end

function Remotes.Learn(action, label)
    learned[action] = label

    local saved = store()

    if saved then
        saved[action] = label
    end
end

-- ─── Estado ────────────────────────────────────────────────

function Remotes.Stats()
    return {sent = stats.sent, dropped = stats.dropped, failed = stats.failed}
end

function Remotes.ClearCache()
    table.clear(cache)
    table.clear(folderCache)
end

return Remotes
]=]
FILES["sections"] = [=[
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
]=]
FILES["state"] = [=[
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
]=]
FILES["survival"] = [=[
--[[
    VANTA | Supervivencia
    Curar, curar a todos, semi godmode, anti-slip y auto-curación.

    Todo vive en este archivo: sus banderas, su bucle, su hook. Apagar
    "Curarme solo" no toca nada de las otras secciones.

    Firmas verificadas
    - Energy(25, "Pizza") cura. Con número negativo el servidor DAÑA.
    - HealTheNoobs() cura al equipo, pero exige la manzana equipada.
    - IceSlip se corta en el hook: el servidor deja de resbalarte.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Remotes = require("remotes")
local State = require("state")
local Sections = require("sections")

local Player = Players.LocalPlayer

local Survival = {}

-- ─── Lecturas ──────────────────────────────────────────────

local function humanoid()
    local character = Player.Character

    return character and character:FindFirstChildOfClass("Humanoid")
end

local function toolName(item)
    return (tostring(item):gsub("%s", ""))
end

local function hasTool(item)
    local name = toolName(item)
    local bag = Player:FindFirstChildOfClass("Backpack")
    local character = Player.Character

    if bag and bag:FindFirstChild(name) then
        return true
    end

    return character ~= nil and character:FindFirstChild(name) ~= nil
end

local function equip(item)
    local name = toolName(item)
    local bag = Player:FindFirstChildOfClass("Backpack")
    local character = Player.Character

    if not character then
        return false
    end

    local tool = (bag and bag:FindFirstChild(name)) or character:FindFirstChild(name)

    if not tool then
        return false
    end

    if tool.Parent == character then
        return true
    end

    return (pcall(function()
        tool.Parent = character
    end))
end

-- ─── Cura ──────────────────────────────────────────────────

-- Escalera: primero lo barato, después lo que cura más.
local LADDER = {
    {item = "Pizza", amount = 25},
    {item = "Gold Pizza", amount = 50},
    {item = "Rainbow Pizza", amount = 75},
}

function Survival.Heal()
    local hum = humanoid()

    if not hum or hum.Health <= 0 then
        return false, "no hay personaje vivo"
    end

    local before = hum.Health

    if before >= hum.MaxHealth then
        return true, string.format("ya estabas a %d de vida", math.floor(before))
    end

    for _, step in ipairs(LADDER) do
        if not hasTool(step.item) then
            Remotes.Send("GiveTool", step.item)

            Remotes.Await(function()
                return hasTool(step.item)
            end, 0.8)
        end

        local base = hum.Health

        if Remotes.Send("Energy", step.amount, step.item) then
            local cured = Remotes.Await(function()
                local now = humanoid()
                return now ~= nil and now.Health > base + 0.5
            end, 1.2)

            if cured then
                local now = humanoid()

                return true, string.format(
                    "+%d de vida con %s (%d → %d)",
                    math.floor(now.Health - before),
                    step.item,
                    math.floor(before),
                    math.floor(now.Health)
                )
            end
        end
    end

    return false, "Energy no movió la vida con Pizza, Gold Pizza ni Rainbow Pizza"
end

-- ─── Curar a todos ─────────────────────────────────────────

function Survival.HealEveryone()
    local hum = humanoid()

    if not hum or hum.Health <= 0 then
        return false, "no hay personaje vivo"
    end

    -- La manzana tiene que estar EN LA MANO: guardada, el servidor ignora
    -- HealTheNoobs y no avisa.
    pcall(function()
        hum:UnequipTools()
    end)

    task.wait(0.15)

    if not hasTool("Golden Apple") then
        Remotes.Send("GiveTool", "Golden Apple")

        if not Remotes.Await(function()
            return hasTool("Golden Apple")
        end, 2.0) then
            return false, "la manzana dorada no llegó a la mochila"
        end
    end

    if not equip("Golden Apple") then
        return false, "no se pudo equipar la manzana dorada"
    end

    task.wait(0.25)

    if not Remotes.Send("HealTheNoobs") then
        return false, "HealTheNoobs no existe en este lugar"
    end

    return true, "manzana equipada y HealTheNoobs disparado"
end

-- ─── Semi godmode y anti-slip ──────────────────────────────

-- El hook se instala UNA vez y consulta sus banderas en cada llamada.
-- Apagar la bandera no deja un hook huérfano ni obliga a reinstalar.
local hook = {
    installed = false,
    original = nil,
    semiGod = false,
    antiSlip = false,
}

local function canHook()
    return type(hookmetamethod) == "function"
        and type(getnamecallmethod) == "function"
        and type(newcclosure) == "function"
end

local function installHook()
    if hook.installed then
        return true
    end

    if not canHook() then
        return false
    end

    -- Cuidado: aquí NUNCA se corta el paso por una bandera general. Un
    -- `if not running then return end` en este punto se traga TODOS los
    -- remotos del juego, incluidos los del motor. Solo se toca lo propio.
    hook.original = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        if getnamecallmethod() == "FireServer"
            and typeof(self) == "Instance"
            and self:IsA("RemoteEvent")
        then
            if hook.antiSlip and self.Name == "IceSlip" then
                return nil
            end

            if hook.semiGod and self.Name == "Energy" then
                local args = table.pack(...)

                if typeof(args[1]) == "number" and args[1] < 0 then
                    args[1] = 0
                    return hook.original(self, table.unpack(args, 1, args.n))
                end
            end
        end

        return hook.original(self, ...)
    end))

    hook.installed = true
    return true
end

function Survival.SetSemiGod(enabled)
    if not enabled then
        hook.semiGod = false
        return true, "semi godmode apagado"
    end

    if not installHook() then
        return false, "tu ejecutor no expone hookmetamethod"
    end

    hook.semiGod = true
    return true, "semi godmode activo: el daño de Energy se anula"
end

function Survival.SetAntiSlip(enabled)
    if not enabled then
        hook.antiSlip = false
        return true, "anti-slip apagado"
    end

    if not installHook() then
        return false, "tu ejecutor no expone hookmetamethod"
    end

    hook.antiSlip = true
    return true, "anti-slip activo: IceSlip se bloquea"
end

-- ─── Auto-curación ─────────────────────────────────────────

function Survival.SetAutoHeal(enabled)
    State.Set("survival.autoHeal", enabled and true or false)
    return true, "auto-curación " .. (enabled and "activa" or "apagada")
end

-- ─── Arranque ──────────────────────────────────────────────

function Survival.Setup()
    local lastHeal = 0

    Sections.Connect("survival", RunService.Heartbeat, function()
        local hum = humanoid()

        if not hum or hum.Health <= 0 then
            return
        end

        -- Las banderas del hook se leen aquí: apagar la de la UI lo apaga
        -- en el siguiente frame, sin reinstalar nada. Se combina con lo que
        -- fijó SetSemiGod/SetAntiSlip por si el hook se instaló sin UI.
        hook.antiSlip = State.Get("survival.antiSlip", false) or hook.antiSlipHeld
        hook.semiGod = State.Get("survival.semiGod", false) or hook.semiGodHeld

        if not State.Get("survival.autoHeal") then
            return
        end

        local threshold = State.Get("survival.threshold", 60)

        if hum.Health >= threshold then
            return
        end

        -- Como mucho una cura por segundo: pedir Energy en cada frame
        -- sería flood.
        if os.clock() - lastHeal < 1 then
            return
        end

        lastHeal = os.clock()

        task.spawn(Survival.Heal)
    end)
end

return Survival
]=]
FILES["trainer"] = [=[
--[[
    VANTA | Entrenamiento
    Fuerza y velocidad por RainbowWhatStat.

    Los valores que el servidor acepta son "Speed" y "Strength" — tal cual,
    con mayúscula. Confirmado en cuatro scripts públicos independientes.

    Verificación: si el cliente expone el stat, se lee antes y después. Si
    no lo expone, se dice que se envió sin poder medir. No se inventa un
    "subió".
]]

local Players = game:GetService("Players")

local Remotes = require("remotes")
local State = require("state")

local Player = Players.LocalPlayer

local Trainer = {}

local statSource = {}

-- ─── Lectura del stat ──────────────────────────────────────

local function lookup(statName)
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

    return nil, nil
end

function Trainer.ReadStat(statName)
    local cached = statSource[statName]

    if cached and cached.Parent then
        if cached:IsA("TextLabel") then
            local number = cached.Text:match("(%d+%.?%d*)")

            if number then
                return tonumber(number)
            end
        else
            return cached.Value
        end
    end

    local value, source = lookup(statName)

    if value and source then
        statSource[statName] = source
        return value
    end

    return nil
end

function Trainer.ForgetStats()
    table.clear(statSource)
end

-- ─── Entrenar ──────────────────────────────────────────────

local VALID = {Speed = "Speed", Strength = "Strength"}

function Trainer.Train(stat)
    local canonical = VALID[stat]

    if not canonical then
        -- Acepta minúsculas sin obligar al usuario a saber la capitalización.
        for name in pairs(VALID) do
            if name:lower() == tostring(stat):lower() then
                canonical = name
            end
        end
    end

    if not canonical then
        return false, "stat inválido: " .. tostring(stat) .. " (usa Speed o Strength)"
    end

    local before = Trainer.ReadStat(canonical)
    local reps = State.Get("trainer.reps", 10)
    local sent = 0

    for _ = 1, reps do
        if not Remotes.Send("RainbowWhatStat", canonical) then
            return false, "RainbowWhatStat no existe en este lugar"
        end

        sent += 1
        task.wait(0.25)
    end

    if not before then
        return true, string.format(
            "%s: %d envíos (tu cliente no muestra el stat, no puedo medirlo)",
            canonical,
            sent
        )
    end

    local after = Trainer.ReadStat(canonical)

    if after and after > before then
        return true, string.format(
            "%s %d → %d (+%d) en %d envíos",
            canonical,
            math.floor(before),
            math.floor(after),
            math.floor(after - before),
            sent
        )
    end

    return false, string.format(
        "%s no subió tras %d envíos (el servidor lo ignora o el stat no es legible)",
        canonical,
        sent
    )
end

function Trainer.SetReps(value)
    local reps = math.clamp(tonumber(value) or 10, 1, 100)
    State.Set("trainer.reps", reps)
    return true, reps .. " envíos por clic"
end

function Trainer.Setup()
    State.Set("trainer.reps", State.Get("trainer.reps", 10))
end

return Trainer
]=]
FILES["visuals"] = [=[
--[[
    VANTA | Visuales
    ESP de jugadores y fullbright. Todo local, todo restaurable.

    Los highlights viven en una carpeta propia. Apagar el ESP borra SOLO
    esa carpeta: no toca nada de otras secciones. Al cerrar, la luz vuelve
    a como estaba.
]]

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local State = require("state")
local Sections = require("sections")

local Player = Players.LocalPlayer

local Visuals = {}

local folder = nil
local highlights = {}
local originalLight = nil

local ESP_COLOR = Color3.fromRGB(120, 190, 255)
local ESP_OUTLINE = Color3.fromRGB(235, 245, 255)

-- ─── Luz ───────────────────────────────────────────────────

local function captureLight()
    if originalLight then
        return
    end

    -- Nombres exactos de propiedad. Derivarlos del nombre corto daba
    -- propiedades mal escritas y la restauración no hacía nada.
    originalLight = {
        {property = "Brightness", value = Lighting.Brightness},
        {property = "ClockTime", value = Lighting.ClockTime},
        {property = "FogEnd", value = Lighting.FogEnd},
        {property = "GlobalShadows", value = Lighting.GlobalShadows},
    }
end

function Visuals.RestoreLight()
    if not originalLight then
        return
    end

    for _, entry in ipairs(originalLight) do
        pcall(function()
            Lighting[entry.property] = entry.value
        end)
    end
end

function Visuals.SetFullbright(enabled)
    State.Set("visuals.fullbright", enabled and true or false)

    if not enabled then
        Visuals.RestoreLight()
    end

    return true, "fullbright " .. (enabled and "activo" or "apagado")
end

-- ─── ESP ───────────────────────────────────────────────────

local function ensureFolder()
    if folder and folder.Parent then
        return folder
    end

    folder = Instance.new("Folder")
    folder.Name = "VANTA_ESP"
    folder.Parent = Workspace

    return folder
end

local function removeHighlight(target)
    local highlight = highlights[target]

    if highlight then
        pcall(function()
            highlight:Destroy()
        end)

        highlights[target] = nil
    end
end

local function addHighlight(target)
    removeHighlight(target)

    if target == Player or not target.Character then
        return
    end

    local highlight = Instance.new("Highlight")
    highlight.Name = "VANTA_HL"
    highlight.Adornee = target.Character
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillColor = ESP_COLOR
    highlight.OutlineColor = ESP_OUTLINE
    highlight.FillTransparency = 0.75
    highlight.OutlineTransparency = 0
    highlight.Parent = ensureFolder()

    highlights[target] = highlight
end

function Visuals.ClearESP()
    for target in pairs(highlights) do
        removeHighlight(target)
    end

    if folder and folder.Parent then
        pcall(function()
            folder:Destroy()
        end)
    end

    folder = nil
end

function Visuals.SetESP(enabled)
    State.Set("visuals.esp", enabled and true or false)

    if not enabled then
        Visuals.ClearESP()
        return true, "ESP apagado"
    end

    local count = 0

    for _, target in ipairs(Players:GetPlayers()) do
        if target ~= Player then
            addHighlight(target)
            count += 1
        end
    end

    return true, string.format("ESP activo en %d jugadores", count)
end

-- ─── Arranque ──────────────────────────────────────────────

function Visuals.Setup()
    Sections.Connect("visuals", Players.PlayerAdded, function(target)
        Sections.Connect("visuals", target.CharacterAdded, function()
            if State.Get("visuals.esp") then
                addHighlight(target)
            end
        end)
    end)

    Sections.Connect("visuals", Players.PlayerRemoving, function(target)
        removeHighlight(target)
    end)

    Sections.Connect("visuals", RunService.Stepped, function()
        if not State.Get("visuals.fullbright") then
            return
        end

        captureLight()

        if Lighting.Brightness ~= 3 then
            Lighting.Brightness = 3
        end

        if Lighting.ClockTime ~= 14 then
            Lighting.ClockTime = 14
        end

        if Lighting.FogEnd < 100000 then
            Lighting.FogEnd = 100000
        end

        if Lighting.GlobalShadows then
            Lighting.GlobalShadows = false
        end
    end)
end

-- Cierre: lo llama el núcleo antes de desconectar.
function Visuals.Shutdown()
    Visuals.ClearESP()
    Visuals.RestoreLight()
end

return Visuals
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
