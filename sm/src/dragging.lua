--[[
    VANTA | Arrastre
    Energía: el otro recurso real del juego.

    El juego da energía por arrastrar objetos pesados pasando la línea. La
    forma de automatizarlo está verificada en tres scripts públicos:

        1. hay un ProximityPrompt en el objeto (InteractionPoint)
        2. se mantiene pulsado: InputHoldBegin / InputHoldEnd
        3. las piezas que arrastras viven en Workspace.PlayerDraggables[UserId]
        4. la meta es Areas[área].Goal

    El script no teletransporta las piezas al azar: primero las mueve a la
    meta y comprueba que la energía subió. Si no subió, lo dice.
]]

local Dragging = {}

local State = require("state")
local Sections = require("sections")
local Stats = require("stats")
local Remotes = require("remotes")

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

-- ─── Localizar ─────────────────────────────────────────────

local function character()
    local player = Remotes.Player()
    return player and player.Character
end

local function root()
    local char = character()

    if not char then
        return nil
    end

    return char:FindFirstChild("HumanoidRootPart")
end

-- Las piezas que llevas ahora mismo.
function Dragging.MyPieces()
    local player = Remotes.Player()
    local folder = Workspace:FindFirstChild("PlayerDraggables")

    if not player or not folder then
        return nil, "no existe Workspace.PlayerDraggables"
    end

    local mine = folder:FindFirstChild(tostring(player.UserId))

    if not mine then
        return nil, "todavía no arrastras nada (no hay carpeta tuya)"
    end

    return mine
end

-- El área donde estás: la que tiene DraggableItems y Goal.
function Dragging.Area()
    local areas = Workspace:FindFirstChild("Areas")

    if not areas then
        return nil, "no existe Workspace.Areas"
    end

    local chosen = State.Get("dragging.area")

    if chosen and areas:FindFirstChild(chosen) then
        return areas[chosen]
    end

    -- Sin elegir: la primera que tenga meta y objetos.
    for _, area in ipairs(areas:GetChildren()) do
        if area:FindFirstChild("Goal") and area:FindFirstChild("DraggableItems") then
            return area
        end
    end

    return nil, "ninguna área tiene Goal y DraggableItems"
end

function Dragging.SetArea(name)
    State.Set("dragging.area", name)
    return true, "área: " .. tostring(name)
end

-- ─── Arrastrar ─────────────────────────────────────────────

local function finishPieces(pieces, goal)
    local moved = 0

    for _, piece in ipairs(pieces:GetChildren()) do
        if piece:IsA("BasePart") then
            local ok = pcall(function()
                piece.Anchored = true
                piece.CFrame = goal.CFrame
                piece.Anchored = false
            end)

            if ok then
                moved += 1
            end
        end
    end

    return moved
end

function Dragging.Pull()
    local pieces, why = Dragging.MyPieces()

    if not pieces then
        return false, why
    end

    local area, areaWhy = Dragging.Area()

    if not area then
        return false, areaWhy
    end

    local goal = area:FindFirstChild("Goal")

    if not goal then
        return false, area.Name .. " no tiene Goal"
    end

    local count = #pieces:GetChildren()

    if count == 0 then
        return false, "la carpeta de arrastre está vacía: sujeta algo primero"
    end

    local grew, before, after, detail = Stats.Changed("energy", function()
        local moved = finishPieces(pieces, goal)

        if moved == 0 then
            return false, "no se pudo mover ninguna pieza"
        end

        return true
    end)

    if grew then
        return true, detail
    end

    return false, string.format(
        "moví %d pieza(s) a %s pero la energía no subió (%s → %s)",
        count,
        area.Name,
        tostring(before),
        tostring(after)
    )
end

-- ─── Sujetar el objeto de un área ──────────────────────────
-- Verificado: InteractionPoint tiene un ProximityPrompt, y se activa
-- manteniéndolo pulsado.

function Dragging.Grab(title)
    local area, why = Dragging.Area()

    if not area then
        return false, why
    end

    local items = area:FindFirstChild("DraggableItems")

    if not items then
        return false, area.Name .. " no tiene DraggableItems"
    end

    local target = nil

    for _, item in ipairs(items:GetChildren()) do
        if not title then
            target = item
            break
        end

        local titleValue = item:FindFirstChild("Title")

        if titleValue and string.lower(tostring(titleValue.Value)) == string.lower(title) then
            target = item
            break
        end
    end

    if not target then
        return false, string.format("no hay objeto %s en %s", tostring(title or "—"), area.Name)
    end

    local point = target:FindFirstChild("InteractionPoint") or target

    local prompt = point:FindFirstChildOfClass("ProximityPrompt")
        or target:FindFirstChildOfClass("ProximityPrompt")

    if not prompt then
        return false, target.Name .. " no tiene ProximityPrompt"
    end

    local before = Stats.Read("energy")

    local ok = pcall(function()
        point:InputHoldBegin()
        task.wait(0.1)
        point:InputHoldEnd()
    end)

    if not ok then
        -- Segunda vía: el ejecutor puede tener fireproximityprompt.
        if type(fireproximityprompt) == "function" then
            pcall(fireproximityprompt, prompt)
        else
            return false, "no se pudo activar el ProximityPrompt"
        end
    end

    -- Lo que de verdad dice si funcionó: si la carpeta de arrastre ya no
    -- está vacía.
    local deadline = os.clock() + 2

    repeat
        task.wait(0.1)
        local pieces = Dragging.MyPieces()

        if pieces and #pieces:GetChildren() > 0 then
            return true, string.format("%s sujeto (%d piezas)", target.Name, #pieces:GetChildren())
        end
    until os.clock() >= deadline

    local after = Stats.Read("energy")

    if before and after and after > before then
        return true, string.format("energía +%.0f con %s", after - before, target.Name)
    end

    return false, string.format(
        "activé el prompt de %s pero no se sujetó nada: el servidor no lo aceptó",
        target.Name
    )
end

-- ─── Automático ────────────────────────────────────────────

function Dragging.SetAuto(enabled)
    State.Set("dragging.auto", enabled and true or false)
    return true, "arrastre automático " .. (enabled and "encendido" or "apagado")
end

function Dragging.Setup()
    local last = 0

    Sections.Connect("dragging", RunService.Heartbeat, function()
        if not State.Get("dragging.auto", false) then
            return
        end

        if os.clock() - last < 0.5 then
            return
        end

        last = os.clock()

        local pieces = Dragging.MyPieces()
        local area = Dragging.Area()

        if not pieces or not area then
            return
        end

        local goal = area:FindFirstChild("Goal")

        if goal and #pieces:GetChildren() > 0 then
            finishPieces(pieces, goal)
        end
    end)
end

return Dragging
