--[[
    VANTA | FEATURE — Movimiento
    Todo local. No manda ni un remoto.

    Por qué así: WalkSpeed, JumpPower, noclip y salto infinito se escriben
    en la propiedad cada frame desde Stepped. El servidor no puede
    rechazar algo que no le pediste.

    Restauración garantizada: guarda los valores originales y los devuelve
    al descargar el módulo.
]]

local PlayerLib = require(script.Parent.Parent.core.player)

local Movement = {}

Movement.spec = {
    id = "movement",
    name = "Movimiento",
    kind = "local",
    tab = "Movimiento",
    order = 50,
    description = "Velocidad, salto y noclip — todo local",

    actions = {
        setSpeed = function(state, enabled)
            state.speedEnabled = enabled and true or false

            return true, "velocidad " .. (state.speedEnabled and "activa" or "apagada")
        end,

        setJump = function(state, enabled)
            state.jumpEnabled = enabled and true or false

            return true, "salto " .. (state.jumpEnabled and "activo" or "apagado")
        end,

        setInfJump = function(state, enabled)
            state.infJump = enabled and true or false

            return true, "salto infinito " .. (state.infJump and "activo" or "apagado")
        end,

        setNoclip = function(state, enabled)
            state.noclip = enabled and true or false

            if not state.noclip then
                Movement.restoreCollisions(state)
            end

            return true, "noclip " .. (state.noclip and "activo" or "apagado")
        end,
    },

    setup = function(ctx)
        local state = ctx.state
        local RunService = game:GetService("RunService")
        local UserInputService = game:GetService("UserInputService")

        state.speed = 32
        state.jump = 75
        state.speedEnabled = false
        state.jumpEnabled = false
        state.infJump = false
        state.noclip = false

        state.originals = nil
        state.collisions = {}

        -- Sin esto, al descargar el módulo el Bus borra `state.originals`
        -- y el personaje se queda sin colisión y con la velocidad cambiada
        -- para siempre. El teardown devuelve todo antes de que se borre.
        state.teardown = function()
            local humanoid = PlayerLib.Humanoid()

            if humanoid and state.originals then
                pcall(function()
                    humanoid.WalkSpeed = state.originals.walkSpeed
                    humanoid.JumpPower = state.originals.jumpPower
                    humanoid.UseJumpPower = state.originals.useJumpPower
                end)
            end

            for part, original in pairs(state.collisions or {}) do
                if part and part.Parent then
                    pcall(function()
                        part.CanCollide = original
                    end)
                end
            end

            state.collisions = {}
        end

        local function capture()
            local humanoid = PlayerLib.Humanoid()

            if not humanoid or state.originals then
                return
            end

            state.originals = {
                walkSpeed = humanoid.WalkSpeed,
                jumpPower = humanoid.JumpPower,
                useJumpPower = humanoid.UseJumpPower,
            }
        end

        ctx.bus.Connect("movement", RunService.Stepped, function()
            local humanoid = PlayerLib.Humanoid()
            local character = PlayerLib.Character()

            if humanoid then
                capture()

                if state.speedEnabled then
                    if humanoid.WalkSpeed ~= state.speed then
                        humanoid.WalkSpeed = state.speed
                    end
                elseif state.originals and humanoid.WalkSpeed ~= state.originals.walkSpeed then
                    humanoid.WalkSpeed = state.originals.walkSpeed
                end

                if state.jumpEnabled then
                    if not humanoid.UseJumpPower then
                        humanoid.UseJumpPower = true
                    end

                    if humanoid.JumpPower ~= state.jump then
                        humanoid.JumpPower = state.jump
                    end
                elseif state.originals and humanoid.JumpPower ~= state.originals.jumpPower then
                    humanoid.JumpPower = state.originals.jumpPower
                    humanoid.UseJumpPower = state.originals.useJumpPower
                end
            end

            if state.noclip and character then
                for _, part in ipairs(character:GetDescendants()) do
                    if part:IsA("BasePart") then
                        if state.collisions[part] == nil then
                            state.collisions[part] = part.CanCollide
                        end

                        if part.CanCollide then
                            part.CanCollide = false
                        end
                    end
                end
            end
        end)

        ctx.bus.Connect("movement", UserInputService.JumpRequest, function()
            if not state.infJump then
                return
            end

            local humanoid = PlayerLib.Humanoid()

            if humanoid and humanoid.Health > 0 then
                humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end)
    end,
}

function Movement.restoreCollisions(state)
    for part, original in pairs(state.collisions or {}) do
        if part and part.Parent then
            pcall(function()
                part.CanCollide = original
            end)
        end
    end

    table.clear(state.collisions or {})
end

return Movement
