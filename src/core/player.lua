--[[
    VANTA | CORE — Jugador
    Lecturas del mundo, sin E/S. Todo lo que consultan los módulos pasa aquí:
    personaje, vida, mochila, enemigos, jugadores, stats.

    Por qué un módulo aparte: si el juego renombra una carpeta, se arregla
    en un sitio.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Player = Players.LocalPlayer

local PlayerLib = {}

local statSource = {}

local enemyFolders = {"BadGuys", "BadGuysBoss", "BadGuysFront"}

-- ─── Personaje ─────────────────────────────────────────────

function PlayerLib.Character()
    return Player.Character
end

function PlayerLib.Humanoid()
    local character = Player.Character

    return character and character:FindFirstChildOfClass("Humanoid")
end

function PlayerLib.Root()
    local character = Player.Character

    return character and character:FindFirstChild("HumanoidRootPart")
end

function PlayerLib.Backpack()
    return Player:FindFirstChildOfClass("Backpack")
end

function PlayerLib.Alive()
    local humanoid = PlayerLib.Humanoid()

    return humanoid ~= nil and humanoid.Health > 0
end

function PlayerLib.Health()
    local humanoid = PlayerLib.Humanoid()

    return humanoid and humanoid.Health or 0
end

function PlayerLib.MaxHealth()
    local humanoid = PlayerLib.Humanoid()

    return humanoid and humanoid.MaxHealth or 100
end

-- ─── Herramientas ──────────────────────────────────────────

function PlayerLib.ToolName(item)
    return (tostring(item):gsub("%s", ""))
end

function PlayerLib.FindTool(item)
    local name = PlayerLib.ToolName(item)
    local backpack = PlayerLib.Backpack()
    local character = Player.Character

    if backpack then
        local tool = backpack:FindFirstChild(name)

        if tool then
            return tool, "mochila"
        end
    end

    if character then
        local tool = character:FindFirstChild(name)

        if tool then
            return tool, "equipada"
        end
    end

    return nil
end

function PlayerLib.CountTools()
    local backpack = PlayerLib.Backpack()
    local count = 0

    if backpack then
        for _, child in ipairs(backpack:GetChildren()) do
            if child:IsA("Tool") then
                count += 1
            end
        end
    end

    return count
end

function PlayerLib.Equip(item)
    local tool = PlayerLib.FindTool(item)
    local character = Player.Character

    if not tool or not character then
        return false
    end

    if tool.Parent == character then
        return true
    end

    local ok = pcall(function()
        tool.Parent = character
    end)

    return ok
end

-- ─── Enemigos ──────────────────────────────────────────────

function PlayerLib.Enemies()
    local list = {}
    local seen = {}

    local function Add(npc)
        if npc and not seen[npc] then
            seen[npc] = true
            table.insert(list, npc)
        end
    end

    for _, folderName in ipairs(enemyFolders) do
        local folder = Workspace:FindFirstChild(folderName)

        if folder then
            for _, npc in ipairs(folder:GetChildren()) do
                Add(npc)
            end
        end
    end

    Add(Workspace:FindFirstChild("BadGuyPizza", true))
    Add(Workspace:FindFirstChild("BadGuyBrute", true))

    return list
end

function PlayerLib.EnemyHumanoid(npc)
    if not npc then
        return nil
    end

    if npc:IsA("Humanoid") then
        return npc
    end

    return npc:FindFirstChildOfClass("Humanoid")
end

function PlayerLib.EnemyRoot(npc)
    if not npc then
        return nil
    end

    if npc:IsA("BasePart") then
        return npc
    end

    if npc:IsA("Model") then
        return npc.PrimaryPart
            or npc:FindFirstChild("HumanoidRootPart")
    end

    return nil
end

function PlayerLib.EnemyAlive(npc)
    local humanoid = PlayerLib.EnemyHumanoid(npc)

    return humanoid ~= nil and humanoid.Health > 0
end

-- ─── Jugadores ─────────────────────────────────────────────

function PlayerLib.Find(query)
    if type(query) ~= "string" then
        return nil
    end

    local wanted = query:lower():match("^%s*(.-)%s*$")

    if wanted == "" then
        return nil
    end

    for _, target in ipairs(Players:GetPlayers()) do
        if target ~= Player
            and (target.Name:lower() == wanted or target.DisplayName:lower() == wanted)
        then
            return target
        end
    end

    for _, target in ipairs(Players:GetPlayers()) do
        if target ~= Player
            and (
                target.Name:lower():find(wanted, 1, true)
                or target.DisplayName:lower():find(wanted, 1, true)
            )
        then
            return target
        end
    end

    return nil
end

-- ─── Stats (fuerza / velocidad) ────────────────────────────
-- El juego no los expone de forma estable. Se memoriza la primera
-- fuente que da un número, para no recorrer el árbol en cada lectura.

local function Lookup(statName)
    local wanted = statName:lower()
    local playerGui = Player:FindFirstChildOfClass("PlayerGui")

    if playerGui then
        local assets = playerGui:FindFirstChild("Assets")

        if assets then
            for _, object in ipairs(assets:GetDescendants()) do
                if object:IsA("TextLabel") then
                    local text = object.Text:lower()

                    if text:find(wanted, 1, true) then
                        local number = text:match("(%d+%.?%d*)")

                        if number then
                            return tonumber(number), object
                        end
                    end
                end
            end
        end
    end

    for _, object in ipairs(Player:GetDescendants()) do
        if (object:IsA("NumberValue") or object:IsA("IntValue"))
            and object.Name:lower():find(wanted, 1, true)
        then
            return object.Value, object
        end
    end

    if playerGui then
        for _, object in ipairs(playerGui:GetDescendants()) do
            if object:IsA("TextLabel") and object.Text ~= "" then
                local text = object.Text:lower()

                if text:find(wanted, 1, true) then
                    local number = text:match("(%d+%.?%d*)")

                    if number then
                        return tonumber(number), object
                    end
                end
            end
        end
    end

    return nil, nil
end

function PlayerLib.ReadStat(statName)
    local cached = statSource[statName]

    if cached and cached.Parent then
        local value

        if cached:IsA("TextLabel") then
            local number = cached.Text:match("(%d+%.?%d*)")
            value = number and tonumber(number)
        else
            value = cached.Value
        end

        if value then
            return value
        end
    end

    local value, source = Lookup(statName)

    if value and source then
        statSource[statName] = source

        return value
    end

    statSource[statName] = nil

    return nil
end

function PlayerLib.ForgetStats()
    table.clear(statSource)
end

return PlayerLib
