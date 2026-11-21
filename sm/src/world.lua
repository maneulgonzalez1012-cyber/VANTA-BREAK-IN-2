--[[
    VANTA | Mundo
    Quitar puertas, congelar el temporizador de arrastre, quitar el peso extra.

    Verificado en los scripts públicos del juego:
        - las salidas se llaman "Exit…" o "Copy…" dentro de Workspace.Areas
        - las piezas que arrastras pueden traer un hijo "ExtraWeight"
        - el globo del área es Areas[...].DraggableItems con Title

    Nada de esto toca remotos: es destruir o ajustar objetos del cliente. Por
    eso se comprueba contando cuántos objetos cambiaron de verdad.
]]

local World = {}

local State = require("state")
local Sections = require("sections")

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

-- ─── Salidas ───────────────────────────────────────────────

function World.BreakExits()
    local areas = Workspace:FindFirstChild("Areas")

    if not areas then
        return false, "no existe Workspace.Areas"
    end

    local removed = 0

    for _, object in ipairs(areas:GetDescendants()) do
        local name = string.lower(object.Name or "")

        if string.find(name, "exit", 1, true) or string.find(name, "copy", 1, true) then
            local ok = pcall(function()
                object:Destroy()
            end)

            if ok then
                removed += 1
            end
        end
    end

    if removed == 0 then
        return false, "no encontré puertas con 'Exit' o 'Copy' en Areas"
    end

    return true, string.format("%d puertas quitadas", removed)
end

-- ─── Peso extra ────────────────────────────────────────────

function World.SetNoWeight(enabled)
    State.Set("world.noWeight", enabled and true or false)

    if not enabled then
        return true, "peso extra permitido otra vez"
    end

    -- Se limpia lo que ya esté puesto y se sigue vigilando en Setup().
    local player = game:GetService("Players").LocalPlayer
    local folder = Workspace:FindFirstChild("PlayerDraggables")
    local mine = player and folder and folder:FindFirstChild(tostring(player.UserId))

    local removed = 0

    if mine then
        for _, child in ipairs(mine:GetDescendants()) do
            if child.Name == "ExtraWeight" then
                pcall(function()
                    child:Destroy()
                end)

                removed += 1
            end
        end
    end

    return true, string.format(
        "peso extra bloqueado (%d quitados ahora; se quitarán los nuevos)",
        removed
    )
end

-- ─── Anclaje ───────────────────────────────────────────────
-- El servidor ancla al personaje mientras arrastra o entrena. Saber eso
-- sirve para no teletransportar en mal momento.

function World.IsAnchored()
    local player = game:GetService("Players").LocalPlayer
    local char = player and player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")

    if not root then
        return false
    end

    return root.Anchored == true
end

-- ─── Arranque ──────────────────────────────────────────────

function World.Setup()
    local player = game:GetService("Players").LocalPlayer
    local folder = Workspace:FindFirstChild("PlayerDraggables")

    if not player or not folder then
        return
    end

    local mine = folder:FindFirstChild(tostring(player.UserId))

    if not mine then
        return
    end

    Sections.Connect("world", mine.DescendantAdded, function(added)
        if added.Name ~= "ExtraWeight" then
            return
        end

        if State.Get("world.noWeight", false) then
            pcall(function()
                added:Destroy()
            end)
        end
    end)
end

return World
