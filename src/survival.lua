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
