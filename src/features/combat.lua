--[[
    VANTA | FEATURE — Combate
    Golpear NPC con escalera de variantes y medición por Humanoid.

    Distingue tres resultados, y no los mezcla:
    - servidor confirmó (la vida bajó por el remoto)
    - solo local (el cliente aceptó la escritura, el servidor no)
    - rechazado (nada movió la vida)
]]

local PlayerLib = require(script.Parent.Parent.core.player)
local Remotes = require(script.Parent.Parent.core.remotes)

local Combat = {}

local function hitOne(state, npc, damage, burst)
    local humanoid = PlayerLib.EnemyHumanoid(npc)

    if not humanoid or humanoid.Health <= 0 then
        return false, "sin vida", false
    end

    local root = PlayerLib.Root()

    if root then
        local part = PlayerLib.EnemyRoot(npc)

        if part and (part.Position - root.Position).Magnitude > state.radius then
            return false, "fuera de radio", false
        end
    end

    local before = humanoid.Health
    local part = PlayerLib.EnemyRoot(npc)
    local hits = math.clamp(burst or state.burst, 1, 10)

    local function volley(...)
        local args = table.pack(...)

        for _ = 1, hits do
            Remotes.Event("HitBadguy", table.unpack(args, 1, args.n))
        end
    end

    local variants = {
        {
            label = "HitBadguy(modelo, daño, 4)",
            fire = function()
                volley(npc, damage, 4)
                return true
            end,
        },
    }

    if part then
        table.insert(variants, {
            label = "HitBadguy(parte, daño, 4)",
            fire = function()
                volley(part, damage, 4)
                return true
            end,
        })
    end

    table.insert(variants, {
        label = "HitBadguy(modelo, daño)",
        fire = function()
            volley(npc, damage)
            return true
        end,
    })

    local ok, label = Remotes.TryVariants("hit", variants, function()
        return humanoid.Health < before
    end, 0.5)

    if ok then
        return true, string.format(
            "%d → %d (%s)",
            math.floor(before),
            math.floor(humanoid.Health),
            tostring(label)
        ), false
    end

    -- Último recurso: escribir en el cliente. Se marca como local.
    if humanoid.Health > 0 then
        pcall(function()
            humanoid.Health = 0
        end)

        if humanoid.Health < before then
            return true, string.format("%d → 0 (local)", math.floor(before)), true
        end
    end

    return false, "el remoto no bajó la vida y el cliente no la aceptó", false
end

local function hitAll(state, silent)
    local total, killed, localOnly, failed = 0, 0, 0, 0

    local targets = PlayerLib.Enemies()

    if #targets == 0 then
        return false, "no hay NPC en el mapa (¿place correcto?)", 0, 0
    end

    for _, npc in ipairs(targets) do
        if not state.running then
            break
        end

        if PlayerLib.EnemyAlive(npc) then
            local ok, _, isLocal = hitOne(state, npc, state.damage, state.burst)

            if ok then
                total += 1

                if isLocal then
                    localOnly += 1
                elseif not PlayerLib.EnemyAlive(npc) then
                    killed += 1
                end
            else
                failed += 1
            end
        end
    end

    local detail = string.format("%d dañados, %d caídos", total, killed)

    if localOnly > 0 then
        detail = detail .. string.format(", %d solo en cliente", localOnly)
    end

    if failed > 0 then
        detail = detail .. string.format(", %d sin efecto", failed)
    end

    if total == 0 and failed == 0 then
        detail = "había NPC pero ninguno estaba vivo o en radio"
    end

    -- Solo cuenta como ejecutado lo que el servidor confirmó.
    local verified = killed > 0 or (total > 0 and localOnly == 0)

    return verified, detail, total, killed
end

Combat.spec = {
    id = "combat",
    name = "Combate",
    kind = "remote",
    tab = "Combate",
    order = 40,
    description = "Daño a NPC con verificación por Humanoid",

    actions = {
        hitAll = function(state)
            return hitAll(state, false)
        end,

        hitOne = function(state)
            local target = PlayerLib.Enemies()[1]

            if not target then
                return false, "no hay NPC en el mapa"
            end

            local ok, detail, isLocal = hitOne(state, target, state.damage, state.burst)

            if ok and isLocal then
                return false, detail .. " — solo en tu pantalla"
            end

            return ok, detail
        end,

        setAuto = function(state, value)
            state.auto = value and true or false

            return true, "auto-ataque " .. (state.auto and "activo" or "apagado")
        end,
    },

    setup = function(ctx)
        local state = ctx.state

        state.damage = 65
        state.burst = 4
        state.radius = 150
        state.interval = 0.5
        state.auto = false
        state.running = true

        -- El bucle vive aquí y usa el Bus: si el módulo se descarga,
        -- la conexión muere con él.
        ctx.bus.Connect("combat", game:GetService("RunService").Heartbeat, function()
            if not state.auto then
                return
            end

            -- Heartbeat corre cada frame: se limita a pedazos.
            if os.clock() - (state.lastTick or 0) < state.interval then
                return
            end

            state.lastTick = os.clock()
            hitAll(state, true)
        end)
    end,
}

return Combat
