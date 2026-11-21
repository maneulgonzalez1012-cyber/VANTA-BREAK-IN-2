--[[
    VANTA | FEATURE — Objetos
    Dar, equipar y verificar contra la mochila real.

    No confía en "enviado": comprueba que el ítem esté.
    Si no está, prueba la siguiente vía.
]]

local Items = require(script.Parent.Parent.lib.items)
local PlayerLib = require(script.Parent.Parent.core.player)
local Remotes = require(script.Parent.Parent.core.remotes)

local Players = game:GetService("Players")
local LocalName = Players.LocalPlayer.Name

local Feature = {}

local function give(state, item)
    if type(item) ~= "string" or item == "" then
        return false, "ítem inválido"
    end

    -- Ya lo tienes: se equipa, no se pide.
    if PlayerLib.FindTool(item) then
        PlayerLib.Equip(item)
        return true, item .. " ya estaba; equipado"
    end

    local variants = {}
    local toolName = Items.toolName(item)

    -- Armas y armadura van por el vending primero.
    if Items.isArmor(item) then
        table.insert(variants, {
            label = "Vending(Armor2)",
            fire = function()
                return Remotes.Event(
                    "Vending", 3, Items.armorId, "Armor", LocalName, 1
                )
            end,
        })
    elseif Items.isWeapon(item) then
        local weaponId = Items.weaponId(item)

        table.insert(variants, {
            label = "Vending(" .. weaponId .. ")",
            fire = function()
                return Remotes.Event(
                    "Vending", 3, weaponId, "Weapons", LocalName, 1
                )
            end,
        })
    end

    table.insert(variants, {
        label = "GiveTool(sin espacios)",
        fire = function()
            return Remotes.Event("GiveTool", toolName)
        end,
    })

    table.insert(variants, {
        label = "GiveTool(con espacios)",
        fire = function()
            return Remotes.Event("GiveTool", item)
        end,
    })

    local ok, label = Remotes.TryVariants(item, variants, function()
        return PlayerLib.FindTool(item) ~= nil
    end, 1.0)

    if ok then
        PlayerLib.Equip(item)

        return true, string.format(
            "%s en mochila (%s)",
            item,
            tostring(label or "primera vía")
        )
    end

    return false, string.format(
        "%s no llegó por ninguna de %d vías",
        item,
        #variants
    )
end

Feature.spec = {
    id = "items",
    name = "Objetos",
    kind = "remote",
    tab = "Objetos",
    order = 30,
    description = "Dar, equipar y verificar contra la mochila",

    actions = {
        give = function(state, item)
            return give(state, item)
        end,

        giveAll = function(state)
            local done, failed = 0, 0

            for _, item in ipairs(Items.all) do
                if not state.running then
                    break
                end

                local ok = give(state, item)

                if ok then
                    done += 1
                else
                    failed += 1
                end

                task.wait(0.15)
            end

            return done > 0, string.format(
                "%d en mochila, %d rechazados",
                done,
                failed
            )
        end,

        quickKit = function(state)
            local wanted = {"Armor", "Golden Apple", "Med Kit", "Crowbar 2"}
            local done = 0

            for _, item in ipairs(wanted) do
                if give(state, item) then
                    done += 1
                end
            end

            for _ = 1, 6 do
                give(state, "Gold Pizza")
            end

            return done > 0, string.format(
                "%d/%d objetos del kit en la mochila",
                done,
                #wanted
            )
        end,

        selected = function(state)
            return give(state, state.selected or "Golden Apple")
        end,
    },

    setup = function(ctx)
        ctx.state.selected = "Golden Apple"
    end,
}

return Feature
