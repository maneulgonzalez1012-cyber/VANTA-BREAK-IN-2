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
