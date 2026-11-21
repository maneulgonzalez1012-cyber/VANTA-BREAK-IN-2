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
