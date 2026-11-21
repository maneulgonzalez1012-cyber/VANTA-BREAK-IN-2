--[[
    VANTA | FEATURE — Supervivencia
    Curación verificada, semi godmode y anti-slip.

    Aislamiento
    - No sabe que existe otro módulo.
    - Su único estado vive en `ctx.state`.
    - Sus conexiones van por `ctx.bus`.
    - Todas sus acciones devuelven ok + motivo, nunca lanzan.
]]

local Items = require(script.Parent.Parent.lib.items)
local PlayerLib = require(script.Parent.Parent.core.player)
local Remotes = require(script.Parent.Parent.core.remotes)

local HealLadder = {
    {item = "Pizza", amount = 25},
    {item = "Gold Pizza", amount = 50},
    {item = "Rainbow Pizza", amount = 75},
}

local Survival = {}

Survival.spec = {
    id = "survival",
    name = "Supervivencia",
    kind = "remote",
    tab = "Supervivencia",
    order = 20,
    description = "Cura verificada, semi godmode y anti-slip",

    actions = {
        heal = function(state, amount)
            amount = tonumber(amount) or 25

            if not PlayerLib.Alive() then
                return false, "sin personaje vivo"
            end

            local before = PlayerLib.Health()

            if before >= PlayerLib.MaxHealth() then
                return true, "ya estaba a " .. math.floor(before) .. " HP"
            end

            for _, step in ipairs(HealLadder) do
                local healFor = math.max(amount, step.amount)

                -- No se pide ítem si ya lo hay: pedirlo cada tick es flood.
                if not PlayerLib.FindTool(step.item) then
                    Remotes.Event("GiveTool", Items.toolName(step.item))
                    Remotes.Await(function()
                        return PlayerLib.FindTool(step.item) ~= nil
                    end, 0.8)
                end

                local base = PlayerLib.Health()

                local ok, label = Remotes.TryVariants("heal", {
                    {
                        label = "Energy(delta, ítem)",
                        fire = function()
                            return Remotes.Event("Energy", healFor, step.item)
                        end,
                    },
                    {
                        label = "Energy(delta, bool, bool)",
                        fire = function()
                            return Remotes.Event("Energy", healFor, false, false)
                        end,
                    },
                }, function()
                    return PlayerLib.Health() > base + 0.5
                end, 1.2)

                if ok then
                    return true, string.format(
                        "+%d HP con %s (%d → %d)",
                        math.floor(PlayerLib.Health() - before),
                        tostring(label),
                        math.floor(before),
                        math.floor(PlayerLib.Health())
                    )
                end
            end

            return false, "Energy no movió la vida con ningún ítem ni firma"
        end,

        healEveryone = function()
            if not PlayerLib.Alive() then
                return false, "sin personaje vivo"
            end

            local humanoid = PlayerLib.Humanoid()

            if humanoid then
                pcall(function()
                    humanoid:UnequipTools()
                end)
                task.wait(0.15)
            end

            local backpack = PlayerLib.Backpack()

            if not backpack then
                return false, "sin mochila"
            end

            if not backpack:FindFirstChild("GoldenApple") then
                Remotes.Event("GiveTool", "GoldenApple")

                if not Remotes.Await(function()
                    local bag = PlayerLib.Backpack()
                    return bag and bag:FindFirstChild("GoldenApple") ~= nil
                end, 2.0) then
                    return false, "la manzana dorada no llegó"
                end
            end

            if not PlayerLib.Equip("Golden Apple") then
                return false, "no se pudo equipar la manzana"
            end

            task.wait(0.25)

            if not Remotes.Event("HealTheNoobs") then
                return false, "HealTheNoobs no existe en este lugar"
            end

            return true, "manzana equipada y HealTheNoobs disparado"
        end,

        setSemiGod = function(state, value)
            if not state.hooks then
                return false, "este executor no expone hookmetamethod"
            end

            state.semiGod = value and true or false

            return true, "semi godmode " .. (state.semiGod and "activo" or "apagado")
        end,

        setAntiSlip = function(state, value)
            if not state.hooks then
                return false, "este executor no expone hookmetamethod"
            end

            state.antiSlip = value and true or false

            return true, "anti-slip " .. (state.antiSlip and "activo" or "apagado")
        end,
    },

    setup = function(ctx)
        local state = ctx.state

        state.hooks = type(hookmetamethod) == "function"
            and type(getnamecallmethod) == "function"
            and type(newcclosure) == "function"

        state.semiGod = false
        state.antiSlip = false

        -- El hook es del módulo: si se descarga, el Bus lo desconecta.
        if not state.hooks then
            return
        end

        local original = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
            -- Nunca se corta el paso por estado: un `if not running then return end`
            -- aquí se traga TODOS los remotos del juego, incluidos los del
            -- propio motor. Solo se interviene cuando hay algo que hacer.
            if getnamecallmethod() == "FireServer"
                and type(self) == "userdata"
                and self:IsA("RemoteEvent")
            then
                local args = table.pack(...)

                if ctx.state.antiSlip and self.Name == "IceSlip" then
                    return nil
                end

                if ctx.state.semiGod and self.Name == "Energy"
                    and type(args[1]) == "number" and args[1] < 0
                then
                    args[1] = 0
                end

                return original(self, table.unpack(args, 1, args.n))
            end

            return original(self, ...)
        end))

        ctx.state.restoreHook = original
    end,
}

return Survival
