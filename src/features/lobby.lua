--[[
    VANTA | FEATURE — Lobby
    Roles por OutsideRole. Solo tiene efecto en el lobby.

    La prueba del rol es la herramienta del gamepass: si llega, eres el rol.
]]

local PlayerLib = require(script.Parent.Parent.core.player)
local Remotes = require(script.Parent.Parent.core.remotes)

local Lobby = {}

local roles = {
    Hacker = {arg = "Phone", tool = "Phone"},
    Nerd = {arg = "Book", tool = "Book"},
}

Lobby.spec = {
    id = "lobby",
    name = "Lobby",
    kind = "remote",
    tab = "Lobby",
    order = 70,
    description = "Roles Hacker y Nerd",

    actions = {
        role = function(state, roleName)
            local role = roles[roleName]

            if not role then
                return false, "rol desconocido: " .. tostring(roleName)
            end

            -- Si ya tienes la herramienta del rol, ya lo eres.
            if PlayerLib.FindTool(role.tool) then
                return true, "ya tienes " .. roleName
            end

            local ok, label = Remotes.TryVariants("role:" .. roleName, {
                {
                    label = "OutsideRole(ítem, true, false)",
                    fire = function()
                        return Remotes.Fire(
                            "RemoteEvents", "OutsideRole",
                            role.arg, true, false
                        )
                    end,
                },
                {
                    label = "OutsideRole(ítem)",
                    fire = function()
                        return Remotes.Fire("RemoteEvents", "OutsideRole", role.arg)
                    end,
                },
            }, function()
                return PlayerLib.FindTool(role.tool) ~= nil
            end, 1.5)

            if ok then
                return true, "rol " .. roleName .. " activo (" .. tostring(label) .. ")"
            end

            return false, "el lobby no entregó " .. roleName
                .. " (¿gamepass o lobby equivocado?)"
        end,
    },

    setup = function(ctx)
        ctx.state.roles = roles
    end,
}

return Lobby
