--[[
    VANTA | FEATURE — Entrenamiento
    RainbowWhatStat con lectura de stat para verificar.

    Si el cliente no expone el stat, la acción se informa sin afirmar
    que subió. No hay éxito inventado.
]]

local PlayerLib = require(script.Parent.Parent.core.player)
local Remotes = require(script.Parent.Parent.core.remotes)

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
