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
