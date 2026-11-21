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
