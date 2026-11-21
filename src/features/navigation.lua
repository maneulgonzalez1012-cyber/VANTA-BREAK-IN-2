--[[
    VANTA | FEATURE — Navegación
    Teleports de la historia y teleport a jugador.

    Verifica que el personaje siga en el destino: si el servidor lo devuelve,
    se dice en vez de fingir que funcionó.
]]

local PlayerLib = require(script.Parent.Parent.core.player)
local Remotes = require(script.Parent.Parent.core.remotes)
local Places = require(script.Parent.Parent.lib.places)

local Navigation = {}

Navigation.spec = {
    id = "navigation",
    name = "Navegación",
    kind = "local",
    tab = "Navegación",
    order = 45,
    description = "Teleports de la historia y a jugadores",

    actions = {
        toPlace = function(state, placeName)
            local root = PlayerLib.Root()

            if not root then
                return false, "sin personaje"
            end

            local place = Places.byName(placeName)

            if not place then
                return false, "lugar desconocido: " .. tostring(placeName)
            end

            for _ = 1, 3 do
                root.CFrame = place.cframe
                task.wait(0.1)
            end

            local ok = Remotes.Await(function()
                return (root.Position - place.cframe.Position).Magnitude < 12
            end, 0.6)

            if ok then
                return true, placeName
            end

            return false, "el servidor devolvió el personaje (anti-teleport)"
        end,

        toPlayer = function(state)
            local root = PlayerLib.Root()

            if not root then
                return false, "sin personaje"
            end

            if (state.target or "") == "" then
                return false, "escribe un nombre primero"
            end

            local target = PlayerLib.Find(state.target)

            if not target then
                return false, "jugador no encontrado"
            end

            local targetRoot = target.Character
                and target.Character:FindFirstChild("HumanoidRootPart")

            if not targetRoot then
                return false, target.Name .. " no tiene personaje"
            end

            local destination = targetRoot.CFrame * CFrame.new(3, 0, 0)

            for _ = 1, 3 do
                root.CFrame = destination
                task.wait(0.1)
            end

            local ok = Remotes.Await(function()
                return (root.Position - destination.Position).Magnitude < 12
            end, 0.6)

            if ok then
                return true, "junto a " .. target.Name
            end

            return false, "el servidor devolvió el personaje (anti-teleport)"
        end,
    },

    setup = function(ctx)
        ctx.state.target = ""
        ctx.state.places = Places.names()
    end,
}

return Navigation
