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
