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
