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
