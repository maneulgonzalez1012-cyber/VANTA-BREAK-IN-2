--[[
    VANTA | FEATURE — Visuales
    ESP de jugadores y fullbright. Todo local.

    Los highlights viven en una carpeta propia del módulo. Al descargarlo
    se destruye solo esa carpeta: no toca nada de otro módulo.
]]

local PlayerLib = require(script.Parent.Parent.core.player)

local Visuals = {}

Visuals.spec = {
    id = "visuals",
    name = "Visuales",
    kind = "local",
    tab = "Visuales",
    order = 60,
    description = "ESP de jugadores y fullbright",

    actions = {
        setESP = function(state, enabled)
            state.esp = enabled and true or false

            if state.refresh then
                state.refresh()
            end

            return true, "ESP " .. (state.esp and "activo" or "apagado")
        end,

        setFullbright = function(state, enabled)
            state.fullbright = enabled and true or false

            if not state.fullbright and state.restoreLighting then
                state.restoreLighting()
            end

            return true, "fullbright " .. (state.fullbright and "activo" or "apagado")
        end,
    },

    setup = function(ctx)
        local state = ctx.state
        local Players = game:GetService("Players")
        local Lighting = game:GetService("Lighting")
        local Workspace = game:GetService("Workspace")
        local RunService = game:GetService("RunService")
        local Player = Players.LocalPlayer

        state.esp = false
        state.fullbright = false
        state.objects = {}

        local folder = Instance.new("Folder")
        folder.Name = "VANTA_Visuals"
        folder.Parent = Workspace

        state.folder = folder

        -- Nombres exactos de propiedad: derivarlos del nombre corto daba
        -- historiales mal escritos y la restauración no hacía nada.
        state.original = {
            {property = "Brightness", value = Lighting.Brightness},
            {property = "ClockTime", value = Lighting.ClockTime},
            {property = "FogEnd", value = Lighting.FogEnd},
            {property = "GlobalShadows", value = Lighting.GlobalShadows},
        }

        function state.restoreLighting()
            for _, entry in ipairs(state.original) do
                pcall(function()
                    Lighting[entry.property] = entry.value
                end)
            end
        end

        local function remove(target)
            local object = state.objects[target]

            if object then
                pcall(function()
                    object:Destroy()
                end)

                state.objects[target] = nil
            end
        end

        local function apply(target)
            remove(target)

            if not state.esp or target == Player or not target.Character then
                return
            end

            local highlight = Instance.new("Highlight")
            highlight.Name = "VANTA_HL"
            highlight.Adornee = target.Character
            highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            highlight.FillColor = Color3.fromRGB(100, 180, 255)
            highlight.OutlineColor = Color3.fromRGB(220, 240, 255)
            highlight.FillTransparency = 0.8
            highlight.OutlineTransparency = 0
            highlight.Parent = folder

            state.objects[target] = highlight
        end

        function state.refresh()
            for _, target in ipairs(Players:GetPlayers()) do
                if target ~= Player then
                    apply(target)
                end
            end
        end

        Players.PlayerAdded:Connect(function(target)
            ctx.bus.Connect("visuals", target.CharacterAdded, function()
                if state.esp then
                    apply(target)
                end
            end)
        end)

        Players.PlayerRemoving:Connect(function(target)
            remove(target)
        end)

        ctx.bus.Connect("visuals", RunService.Stepped, function()
            if not state.fullbright then
                return
            end

            if Lighting.Brightness ~= 3 then
                Lighting.Brightness = 3
            end

            if Lighting.ClockTime ~= 14 then
                Lighting.ClockTime = 14
            end

            if Lighting.FogEnd ~= 100000 then
                Lighting.FogEnd = 100000
            end

            if Lighting.GlobalShadows then
                Lighting.GlobalShadows = false
            end
        end)

        -- Teardown propio: si el módulo se descarga, no deja basura.
        ctx.state.teardown = function()
            for target in pairs(state.objects) do
                remove(target)
            end

            pcall(function()
                folder:Destroy()
            end)
        end
    end,
}

return Visuals
