--[[
    VANTA | FEATURE — Diagnóstico
    La ventana al estado real: módulos vivos, remotos, firmas aprendidas.

    No adivina: pregunta al Bus, al registro y al módulo de remotos.
]]

local Remotes = require(script.Parent.Parent.core.remotes)
local PlayerLib = require(script.Parent.Parent.core.player)

local Diagnostics = {}

local expected = {
    "GiveTool",
    "Vending",
    "Energy",
    "HealTheNoobs",
    "RainbowWhatStat",
    "HitBadguy",
    "IceSlip",
}

Diagnostics.spec = {
    id = "diagnostics",
    name = "Diagnóstico",
    kind = "core",
    tab = "Diagnóstico",
    order = 90,
    description = "Estado de módulos, remotos y firmas",

    actions = {
        scan = function(state)
            local present, missing = 0, {}

            for _, name in ipairs(expected) do
                if Remotes.Exists("Events", name) then
                    present += 1
                else
                    table.insert(missing, name)
                end
            end

            local ok = #missing == 0

            if ok then
                return true, string.format(
                    "%d/%d remotos presentes",
                    present,
                    #expected
                )
            end

            return false, string.format(
                "faltan: %s",
                table.concat(missing, ", ")
            )
        end,

        modules = function(state)
            local registry = state.registry
            local bus = state.bus

            if not registry or not bus then
                return false, "registro no disponible"
            end

            local health = registry.Health()
            local snapshot = bus.Snapshot()

            print("===== VANTA MÓDULOS =====")

            for _, record in ipairs(registry.All()) do
                local status = "ok"

                if record.error then
                    status = "ERROR: " .. record.error
                elseif not record.loaded then
                    status = "no cargado"
                end

                print(string.format(
                    "  %-14s %-7s %s",
                    record.id,
                    record.kind,
                    status
                ))
            end

            if health.conflicts > 0 then
                print("  conflictos de acción: " .. health.conflicts)

                for _, conflict in ipairs(registry.Conflicts()) do
                    print(string.format(
                        "    %s lo declaran %s y %s",
                        conflict.key,
                        conflict.first,
                        conflict.second
                    ))
                end
            end

            print(string.format(
                "  sanos %d | roto %d | conexiones %d | errores %d",
                health.healthy,
                health.broken,
                snapshot.connections,
                snapshot.total
            ))

            return health.broken == 0, string.format(
                "%d/%d módulos sanos, %d conflictos",
                health.healthy,
                health.total,
                health.conflicts
            )
        end,

        signatures = function(state)
            local list = Remotes.Signatures()

            if #list == 0 then
                return true, "ninguna firma aprendida todavía"
            end

            print("===== FIRMAS APRENDIDAS =====")

            local parts = {}

            for _, entry in ipairs(list) do
                print(string.format("  %s = %s", entry.action, entry.label))
                table.insert(parts, entry.action)
            end

            return true, string.format(
                "%d firmas: %s",
                #list,
                table.concat(parts, ", ")
            )
        end,

        dump = function(state)
            local ReplicatedStorage = game:GetService("ReplicatedStorage")

            local function walk(parent, depth)
                if depth > 3 then
                    return
                end

                for _, child in ipairs(parent:GetChildren()) do
                    print(string.rep("  ", depth) .. child.ClassName .. " : " .. child.Name)

                    if child:IsA("Folder") or child:IsA("Model") then
                        walk(child, depth + 1)
                    end
                end
            end

            print("===== ReplicatedStorage =====")
            walk(ReplicatedStorage, 0)

            return true, "árbol impreso en la consola (F9)"
        end,

        probe = function(state)
            -- La sonda: prueba cada vía y reporta lo que el servidor acepta.
            local lines = {}

            local function add(text)
                table.insert(lines, text)
                print("[SONDA] " .. text)
            end

            add("== SONDA ==")
            add("PlaceId " .. tostring(game.PlaceId))

            local registry = state.registry
            local items = registry and registry.Get("items")

            if items then
                local before = PlayerLib.CountTools()
                registry.Run("items", "give", state.bus, "Pizza")
                local after = PlayerLib.CountTools()

                add(string.format(
                    "objeto Pizza: %s (mochila %d → %d)",
                    after > before and "aceptado" or "rechazado",
                    before,
                    after
                ))
            end

            local survival = registry and registry.Get("survival")

            if survival then
                local humanoid = PlayerLib.Humanoid()

                if humanoid then
                    local original = humanoid.Health
                    pcall(function()
                        humanoid.Health = math.max(original - 40, 10)
                    end)

                    local ok = registry.Run("survival", "heal", state.bus, 25)

                    add(string.format(
                        "cura: %s (vida %d → %d)",
                        ok and "aceptada" or "rechazada",
                        math.floor(humanoid.Health),
                        math.floor(PlayerLib.Health())
                    ))

                    pcall(function()
                        humanoid.Health = original
                    end)
                end
            end

            add("== FIN ==")

            return true, string.format("%d líneas en consola", #lines)
        end,
    },

    setup = function(ctx)
        -- El contexto ya trae registro y bus: no se depende de que el
        -- punto de entrada los inyecte después.
        ctx.state.registry = ctx.state.registry or ctx.registry
        ctx.state.bus = ctx.state.bus or ctx.bus
    end,
}

return Diagnostics
