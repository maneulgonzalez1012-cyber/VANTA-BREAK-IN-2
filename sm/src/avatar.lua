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
