--[[
    VANTA | BREAK IN 2
    Executor + Rayfield Gen2

    FUNCIONES
    - Semi godmode y anti-slip
    - Curación y auto-curación
    - Curar a todos
    - Objetos y armas conocidos
    - Entrenamiento de velocidad y fuerza
    - Ataque a NPC y auto-ataque
    - ESP de jugadores
    - WalkSpeed, JumpPower y noclip
    - Teleport a jugador
    - Fullbright
    - Roles del lobby
    - Diagnóstico de remotos
    - Limpieza al cerrar

    NOTAS
    - Los remotos pueden haber cambiado.
    - FireServer no confirma que el servidor acepte la acción.
    - El semi godmode solo cubre ciertos eventos enviados por cliente.
    - Las modificaciones de movimiento y visuales son locales.
]]

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local Player = Players.LocalPlayer
local Env = getgenv()

-- Evitar varias instancias activas.
if Env.VANTA_BI2 and type(Env.VANTA_BI2.Stop) == "function" then
    pcall(Env.VANTA_BI2.Stop)
end

local State = {
    Running = true,

    SemiGod = false,
    AntiSlip = false,
    AutoHeal = false,
    AutoAttack = false,
    ESP = false,

    SpeedEnabled = false,
    JumpEnabled = false,
    Noclip = false,
    Fullbright = false,

    Speed = 32,
    Jump = 75,

    AttackDamage = 65,
    AttackRadius = 150,
    AttackInterval = 0.5,
    HealInterval = 1.5,

    SelectedItem = "Golden Apple",
    SelectedPlayer = "",

    Connections = {},
    ESPObjects = {},
    CollisionCache = {},
    HumanoidCache = setmetatable({}, {__mode = "k"}),

    Errors = 0,
    LastError = "Ninguno",
}

Env.VANTA_BI2 = State

local OriginalLighting = {
    Brightness = Lighting.Brightness,
    ClockTime = Lighting.ClockTime,
    FogEnd = Lighting.FogEnd,
    GlobalShadows = Lighting.GlobalShadows,
}

-- ============================================================
-- HELPERS
-- ============================================================

local function Safe(name, callback, ...)
    local args = table.pack(...)

    local ok, result = xpcall(function()
        return callback(table.unpack(args, 1, args.n))
    end, function(err)
        return tostring(err) .. "\n" .. debug.traceback()
    end)

    if not ok then
        State.Errors += 1
        State.LastError = name .. ": " .. tostring(result)
        warn("[VANTA][" .. name .. "] " .. tostring(result))
    end

    return ok, result
end

local function Connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(State.Connections, connection)
    return connection
end

local function GetCharacter()
    return Player.Character
end

local function GetHumanoid()
    local character = GetCharacter()

    return character and character:FindFirstChildOfClass("Humanoid")
end

local function GetRoot()
    local character = GetCharacter()

    return character and character:FindFirstChild("HumanoidRootPart")
end

local function FindRemote(folderName, remoteName)
    local folder = ReplicatedStorage:FindFirstChild(folderName)

    if not folder then
        return nil, "No existe ReplicatedStorage." .. folderName
    end

    local remote = folder:FindFirstChild(remoteName)

    if not remote or not remote:IsA("RemoteEvent") then
        return nil, "No existe " .. folderName .. "." .. remoteName
    end

    return remote
end

local function Fire(folderName, remoteName, ...)
    local remote, err = FindRemote(folderName, remoteName)

    if not remote then
        return false, err
    end

    local args = table.pack(...)

    local ok, result = pcall(function()
        remote:FireServer(table.unpack(args, 1, args.n))
    end)

    if not ok then
        return false, tostring(result)
    end

    -- Solo confirma que se intentó enviar la solicitud.
    return true
end

-- ============================================================
-- RAYFIELD GEN2
-- ============================================================

local okLibrary, Rayfield = pcall(function()
    local source = game:HttpGet(
        "https://sirius.menu/gen2"
    )

    return loadstring(source)()
end)

if not okLibrary or not Rayfield then
    State.Running = false
    warn("[VANTA] No se pudo cargar Rayfield Gen2:", Rayfield)
    return
end

local okWindow, Window = pcall(function()
    return Rayfield:CreateWindow({
        name = "VANTA | BREAK IN 2",
        subtitle = "Advanced Hub",
        sidebarLayout = true,
    })
end)

if not okWindow or not Window then
    State.Running = false
    warn("[VANTA] No se pudo crear la ventana:", Window)
    return
end

local function Notify(title, content)
    print("[VANTA] " .. tostring(title) .. ": " .. tostring(content))

    pcall(function()
        Window:Notify({
            title = tostring(title),
            content = tostring(content),
            duration = 4,
        })
    end)
end

local function TryFire(folderName, remoteName, ...)
    local ok, err = Fire(folderName, remoteName, ...)

    if not ok then
        Notify("Remoto no disponible", err)
    end

    return ok
end

-- ============================================================
-- HOOK: SEMI GODMODE / ANTI SLIP
-- ============================================================

local HookAvailable =
    type(hookmetamethod) == "function"
    and type(getnamecallmethod) == "function"
    and type(newcclosure) == "function"

if HookAvailable then
    local previous

    local okHook, hookError = pcall(function()
        previous = hookmetamethod(
            game,
            "__namecall",
            newcclosure(function(self, ...)
                if State.Running
                    and getnamecallmethod() == "FireServer" then

                    local events = ReplicatedStorage:FindFirstChild("Events")

                    if events and self.Parent == events then
                        if State.AntiSlip and self.Name == "IceSlip" then
                            return nil
                        end

                        if State.SemiGod and self.Name == "Energy" then
                            local args = table.pack(...)

                            if type(args[1]) == "number" and args[1] < 0 then
                                args[1] = 0
                            end

                            return previous(
                                self,
                                table.unpack(args, 1, args.n)
                            )
                        end
                    end
                end

                return previous(self, ...)
            end)
        )
    end)

    if not okHook then
        HookAvailable = false
        warn("[VANTA] Hook no disponible:", hookError)
    end
end

-- ============================================================
-- ITEMS
-- ============================================================

local Items = {
    "Golden Apple",
    "Gold Pizza",
    "Rainbow Pizza",
    "Rainbow Pizza Box",
    "Pizza",
    "Cookie",
    "Apple",
    "Chips",
    "Lollipop",
    "Bloxy Cola",
    "Expired Bloxy Cola",
    "Bottle",
    "Battery",
    "Med Kit",
    "Armor",
    "Key",
    "Gold Key",
    "Louise",
    "Book",
    "Phone",
    "Ladder",
    "Crowbar 1",
    "Crowbar 2",
    "Bat",
    "Pitchfork",
    "Hammer",
    "Wrench",
    "Broom",
}

local Weapons = {
    ["Crowbar 1"] = true,
    ["Crowbar 2"] = true,
    ["Bat"] = true,
    ["Pitchfork"] = true,
    ["Hammer"] = true,
    ["Wrench"] = true,
    ["Broom"] = true,
}

local function GiveItem(item, silent)
    if type(item) ~= "string" or item == "" then
        return false
    end

    local ok, err

    if item == "Armor" then
        ok, err = Fire(
            "Events",
            "Vending",
            3,
            "Armor2",
            "Armor",
            Player.Name,
            1
        )

    elseif Weapons[item] then
        ok, err = Fire(
            "Events",
            "Vending",
            3,
            item:gsub(" ", ""),
            "Weapons",
            Player.Name,
            1
        )

    else
        ok, err = Fire(
            "Events",
            "GiveTool",
            item:gsub(" ", "")
        )
    end

    if not ok and not silent then
        Notify("Objeto", err)
    end

    return ok
end

local function GiveList(list)
    task.spawn(function()
        local sent = 0

        for _, item in ipairs(list) do
            if not State.Running then
                return
            end

            if GiveItem(item, true) then
                sent += 1
            end

            task.wait(0.25)
        end

        Notify(
            "Objetos",
            tostring(sent) .. " solicitudes enviadas. Revisa el inventario."
        )
    end)
end

-- ============================================================
-- HEAL / TRAINING
-- ============================================================

local function HealSelf(silent)
    local okItem, errItem = Fire("Events", "GiveTool", "Pizza")
    local okEnergy, errEnergy = Fire("Events", "Energy", 25, "Pizza")

    if not silent then
        if not okItem then
            Notify("Curación", errItem)
        elseif not okEnergy then
            Notify("Curación", errEnergy)
        else
            Notify("Curación", "Solicitud enviada.")
        end
    end

    return okItem and okEnergy
end

local function HealEveryone()
    task.spawn(function()
        local humanoid = GetHumanoid()

        if humanoid then
            humanoid:UnequipTools()
        end

        if not GiveItem("Golden Apple", false) then
            return
        end

        local backpack = Player:FindFirstChildOfClass("Backpack")

        if not backpack then
            Notify("Curar a todos", "No se encontró la mochila.")
            return
        end

        local apple = backpack:FindFirstChild("GoldenApple")
            or backpack:WaitForChild("GoldenApple", 3)

        local character = GetCharacter()

        if not apple or not character then
            Notify(
                "Curar a todos",
                "No llegó la manzana dorada o falta el personaje."
            )
            return
        end

        apple.Parent = character
        task.wait(0.3)

        if TryFire("Events", "HealTheNoobs") then
            Notify("Curar a todos", "Solicitud enviada.")
        end
    end)
end

local function Train(stat, amount)
    task.spawn(function()
        for _ = 1, amount do
            if not State.Running then
                return
            end

            local ok, err = Fire("Events", "RainbowWhatStat", stat)

            if not ok then
                Notify("Entrenamiento", err)
                return
            end

            task.wait(0.2)
        end

        Notify("Entrenamiento", stat .. ": solicitudes enviadas.")
    end)
end

-- ============================================================
-- COMBAT
-- ============================================================

local function GetNPCPart(npc)
    if not npc then
        return nil
    end

    if npc:IsA("BasePart") then
        return npc
    end

    if npc:IsA("Model") then
        return npc.PrimaryPart
            or npc:FindFirstChild("HumanoidRootPart")
            or npc:FindFirstChildWhichIsA("BasePart", true)
    end

    return nil
end

local function GetEnemies()
    local enemies = {}
    local seen = {}

    local function Add(npc)
        if npc and not seen[npc] then
            seen[npc] = true
            table.insert(enemies, npc)
        end
    end

    for _, folderName in ipairs({
        "BadGuys",
        "BadGuysBoss",
        "BadGuysFront",
    }) do
        local folder = Workspace:FindFirstChild(folderName)

        if folder then
            for _, npc in ipairs(folder:GetChildren()) do
                Add(npc)
            end
        end
    end

    Add(Workspace:FindFirstChild("BadGuyPizza", true))
    Add(Workspace:FindFirstChild("BadGuyBrute", true))

    return enemies
end

local function AttackEnemies(silent)
    local root = GetRoot()

    if not root then
        return
    end

    local remote, err = FindRemote("Events", "HitBadguy")

    if not remote then
        if not silent then
            Notify("Combate", err)
        end

        return
    end

    local count = 0

    for _, npc in ipairs(GetEnemies()) do
        if not State.Running then
            break
        end

        local part = GetNPCPart(npc)

        if part then
            local distance = (part.Position - root.Position).Magnitude

            if distance <= State.AttackRadius then
                local ok = pcall(function()
                    remote:FireServer(npc, State.AttackDamage, 4)
                end)

                if ok then
                    count += 1
                end
            end
        end
    end

    if not silent then
        Notify(
            "Combate",
            "Solicitudes enviadas a " .. tostring(count) .. " NPC."
        )
    end
end

-- ============================================================
-- ESP
-- ============================================================

local VisualFolder = Instance.new("Folder")
VisualFolder.Name = "VANTA_BI2_ESP"
VisualFolder.Parent = Workspace

local function RemoveESP(target)
    local object = State.ESPObjects[target]

    if object then
        object:Destroy()
        State.ESPObjects[target] = nil
    end
end

local function RefreshESP(target)
    RemoveESP(target)

    if not State.Running
        or not State.ESP
        or target == Player
        or not target.Character then

        return
    end

    local highlight = Instance.new("Highlight")
    highlight.Name = "VANTA_Highlight"
    highlight.Adornee = target.Character
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillColor = Color3.fromRGB(100, 180, 255)
    highlight.OutlineColor = Color3.fromRGB(220, 240, 255)
    highlight.FillTransparency = 0.8
    highlight.OutlineTransparency = 0
    highlight.Parent = VisualFolder

    State.ESPObjects[target] = highlight
end

local function RefreshAllESP()
    for _, target in ipairs(Players:GetPlayers()) do
        RefreshESP(target)
    end
end

local function TrackPlayer(target)
    if target == Player then
        return
    end

    Connect(target.CharacterAdded, function()
        if State.Running then
            RefreshESP(target)
        end
    end)

    Connect(target.CharacterRemoving, function()
        RemoveESP(target)
    end)

    if State.ESP then
        RefreshESP(target)
    end
end

for _, target in ipairs(Players:GetPlayers()) do
    TrackPlayer(target)
end

Connect(Players.PlayerAdded, TrackPlayer)
Connect(Players.PlayerRemoving, RemoveESP)

-- ============================================================
-- MOVEMENT / TELEPORT
-- ============================================================

local function RememberHumanoid(humanoid)
    if humanoid and not State.HumanoidCache[humanoid] then
        State.HumanoidCache[humanoid] = {
            WalkSpeed = humanoid.WalkSpeed,
            JumpPower = humanoid.JumpPower,
            UseJumpPower = humanoid.UseJumpPower,
        }
    end
end

local function RestoreCollisions()
    for part, original in pairs(State.CollisionCache) do
        if part and part.Parent then
            pcall(function()
                part.CanCollide = original
            end)
        end
    end

    table.clear(State.CollisionCache)
end

local function RestoreLighting()
    for property, value in pairs(OriginalLighting) do
        pcall(function()
            Lighting[property] = value
        end)
    end
end

local function FindPlayer(query)
    if type(query) ~= "string" or query == "" then
        return nil
    end

    query = query:lower()

    for _, target in ipairs(Players:GetPlayers()) do
        if target ~= Player
            and (
                target.Name:lower() == query
                or target.DisplayName:lower() == query
            ) then

            return target
        end
    end

    for _, target in ipairs(Players:GetPlayers()) do
        if target ~= Player
            and (
                target.Name:lower():find(query, 1, true)
                or target.DisplayName:lower():find(query, 1, true)
            ) then

            return target
        end
    end

    return nil
end

local function TeleportToPlayer()
    local target = FindPlayer(State.SelectedPlayer)
    local root = GetRoot()

    local targetRoot = target
        and target.Character
        and target.Character:FindFirstChild("HumanoidRootPart")

    if not target or not root or not targetRoot then
        Notify("Teleport", "Jugador o personaje no encontrado.")
        return
    end

    root.CFrame = targetRoot.CFrame * CFrame.new(3, 0, 0)
    Notify("Teleport", "Movido a " .. target.Name)
end

Connect(RunService.Stepped, function()
    if not State.Running then
        return
    end

    local humanoid = GetHumanoid()
    local character = GetCharacter()

    if humanoid then
        RememberHumanoid(humanoid)

        if State.SpeedEnabled then
            humanoid.WalkSpeed = State.Speed
        end

        if State.JumpEnabled then
            humanoid.UseJumpPower = true
            humanoid.JumpPower = State.Jump
        end
    end

    if State.Noclip and character then
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") then
                if State.CollisionCache[part] == nil then
                    State.CollisionCache[part] = part.CanCollide
                end

                part.CanCollide = false
            end
        end
    end
end)

-- ============================================================
-- TABS
-- ============================================================

local Main = Window:CreateTab({name = "Inicio"})
local Survival = Window:CreateTab({name = "Supervivencia"})
local Inventory = Window:CreateTab({name = "Objetos"})
local Combat = Window:CreateTab({name = "Combate"})
local Movement = Window:CreateTab({name = "Movimiento"})
local Visuals = Window:CreateTab({name = "Visuales"})
local Lobby = Window:CreateTab({name = "Lobby"})
local Settings = Window:CreateTab({name = "Diagnóstico"})

Main:CreateText({
    name = "VANTA | BREAK IN 2",
    text = "Remotos históricos. El servidor puede rechazarlos o haberlos cambiado.",
})

Main:CreateText({
    name = "Compatibilidad de hooks",
    text = HookAvailable
        and "Hooks disponibles para semi godmode y anti-slip."
        or "El executor no expone los hooks necesarios.",
})

Main:CreateButton({
    name = "Kit rápido",

    callback = function()
        GiveList({
            "Armor",
            "Golden Apple",
            "Gold Pizza",
            "Med Kit",
            "Crowbar 2",
        })
    end,
})

Main:CreateButton({
    name = "Entrenar fuerza y velocidad ×5",

    callback = function()
        Train("Strength", 5)
        Train("Speed", 5)
    end,
})

-- SUPERVIVENCIA

Survival:CreateSection({name = "Protección"})

Survival:CreateToggle({
    name = "Semi godmode",
    description = "Bloquea ciertos valores negativos enviados por Energy.",
    flag = "semiGod",
    value = false,

    callback = function(value)
        State.SemiGod = value and HookAvailable

        if value and not HookAvailable then
            Notify("Semi godmode", "Hooks no disponibles.")
        end
    end,
})

Survival:CreateToggle({
    name = "Anti-slip",
    flag = "antiSlip",
    value = false,

    callback = function(value)
        State.AntiSlip = value and HookAvailable

        if value and not HookAvailable then
            Notify("Anti-slip", "Hooks no disponibles.")
        end
    end,
})

Survival:CreateSection({name = "Curación"})

Survival:CreateButton({
    name = "Curarme ahora",

    callback = function()
        HealSelf(false)
    end,
})

Survival:CreateToggle({
    name = "Auto-curación",
    flag = "autoHeal",
    value = false,

    callback = function(value)
        State.AutoHeal = value
    end,
})

Survival:CreateSlider({
    name = "Intervalo de curación",
    range = {1, 10},
    increment = 0.5,
    value = 1.5,
    suffix = " s",

    callback = function(value)
        State.HealInterval = value
    end,
})

Survival:CreateButton({
    name = "Curar a todos",
    callback = HealEveryone,
})

Survival:CreateSection({name = "Estadísticas"})

Survival:CreateButton({
    name = "Entrenar fuerza ×5",

    callback = function()
        Train("Strength", 5)
    end,
})

Survival:CreateButton({
    name = "Entrenar velocidad ×5",

    callback = function()
        Train("Speed", 5)
    end,
})

-- OBJETOS

Inventory:CreateDropdown({
    name = "Seleccionar objeto",
    options = Items,
    value = "Golden Apple",
    flag = "item",

    callback = function(value)
        if type(value) == "table" then
            State.SelectedItem = value[1]
        else
            State.SelectedItem = value
        end
    end,
})

Inventory:CreateButton({
    name = "Dar objeto seleccionado",

    callback = function()
        if State.SelectedItem and GiveItem(State.SelectedItem) then
            Notify("Objetos", "Solicitado: " .. State.SelectedItem)
        end
    end,
})

Inventory:CreateButton({
    name = "Solicitar todos los objetos",

    callback = function()
        GiveList(Items)
    end,
})

Inventory:CreateSection({name = "Acceso rápido"})

for _, item in ipairs({
    "Golden Apple",
    "Gold Pizza",
    "Rainbow Pizza",
    "Med Kit",
    "Armor",
    "Crowbar 2",
    "Bat",
    "Key",
    "Gold Key",
}) do
    local currentItem = item

    Inventory:CreateButton({
        name = "Dar " .. currentItem,

        callback = function()
            if GiveItem(currentItem) then
                Notify("Objetos", "Solicitado: " .. currentItem)
            end
        end,
    })
end

-- COMBATE

Combat:CreateSlider({
    name = "Radio de ataque",
    range = {10, 300},
    increment = 10,
    value = 150,
    suffix = " studs",

    callback = function(value)
        State.AttackRadius = value
    end,
})

Combat:CreateSlider({
    name = "Daño solicitado",
    range = {5, 100},
    increment = 5,
    value = 65,

    callback = function(value)
        State.AttackDamage = value
    end,
})

Combat:CreateSlider({
    name = "Intervalo de ataque",
    range = {0.5, 5},
    increment = 0.5,
    value = 0.5,
    suffix = " s",

    callback = function(value)
        State.AttackInterval = value
    end,
})

Combat:CreateButton({
    name = "Atacar NPC cercanos una vez",

    callback = function()
        AttackEnemies(false)
    end,
})

Combat:CreateToggle({
    name = "Auto ataque NPC",
    flag = "autoAttack",
    value = false,

    callback = function(value)
        State.AutoAttack = value
    end,
})

-- MOVIMIENTO

Movement:CreateSlider({
    name = "WalkSpeed",
    range = {16, 100},
    increment = 1,
    value = 32,

    callback = function(value)
        State.Speed = value
    end,
})

Movement:CreateToggle({
    name = "Activar velocidad",
    flag = "speed",
    value = false,

    callback = function(value)
        local humanoid = GetHumanoid()

        if humanoid then
            RememberHumanoid(humanoid)

            if not value then
                local original = State.HumanoidCache[humanoid]

                if original then
                    humanoid.WalkSpeed = original.WalkSpeed
                end
            end
        end

        State.SpeedEnabled = value
    end,
})

Movement:CreateSlider({
    name = "JumpPower",
    range = {50, 150},
    increment = 5,
    value = 75,

    callback = function(value)
        State.Jump = value
    end,
})

Movement:CreateToggle({
    name = "Activar salto",
    flag = "jump",
    value = false,

    callback = function(value)
        local humanoid = GetHumanoid()

        if humanoid then
            RememberHumanoid(humanoid)

            if not value then
                local original = State.HumanoidCache[humanoid]

                if original then
                    humanoid.JumpPower = original.JumpPower
                    humanoid.UseJumpPower = original.UseJumpPower
                end
            end
        end

        State.JumpEnabled = value
    end,
})

Movement:CreateToggle({
    name = "Noclip",
    flag = "noclip",
    value = false,

    callback = function(value)
        State.Noclip = value

        if not value then
            RestoreCollisions()
        end
    end,
})

Movement:CreateInput({
    name = "Jugador para teleport",
    placeholder = "Nombre exacto o parcial",
    value = "",

    callback = function(value)
        State.SelectedPlayer = tostring(value or "")
    end,
})

Movement:CreateButton({
    name = "Teleport al jugador",
    callback = TeleportToPlayer,
})

-- VISUALES

Visuals:CreateToggle({
    name = "ESP jugadores",
    flag = "playerESP",
    value = false,

    callback = function(value)
        State.ESP = value
        RefreshAllESP()
    end,
})

Visuals:CreateToggle({
    name = "Fullbright",
    flag = "fullbright",
    value = false,

    callback = function(value)
        State.Fullbright = value

        if value then
            Lighting.Brightness = 3
            Lighting.ClockTime = 14
            Lighting.FogEnd = 100000
            Lighting.GlobalShadows = false
        else
            RestoreLighting()
        end
    end,
})

-- LOBBY

Lobby:CreateText({
    name = "Roles de lobby",
    text = "Solicitudes históricas; pueden estar parcheadas.",
})

Lobby:CreateButton({
    name = "Solicitar Hacker",

    callback = function()
        if TryFire(
            "RemoteEvents",
            "OutsideRole",
            "Phone",
            true,
            false
        ) then
            Notify("Lobby", "Solicitud de Hacker enviada.")
        end
    end,
})

Lobby:CreateButton({
    name = "Solicitar Nerd",

    callback = function()
        if TryFire(
            "RemoteEvents",
            "OutsideRole",
            "Book",
            true,
            false
        ) then
            Notify("Lobby", "Solicitud de Nerd enviada.")
        end
    end,
})

-- DIAGNÓSTICO

Settings:CreateButton({
    name = "Diagnóstico de remotos",

    callback = function()
        local checks = {
            {"Events", "GiveTool"},
            {"Events", "Vending"},
            {"Events", "Energy"},
            {"Events", "HealTheNoobs"},
            {"Events", "RainbowWhatStat"},
            {"Events", "HitBadguy"},
            {"Events", "IceSlip"},
            {"RemoteEvents", "OutsideRole"},
        }

        local found = 0

        print("========== VANTA DIAGNÓSTICO ==========")
        print("PlaceId:", game.PlaceId)

        for _, check in ipairs(checks) do
            local remote = FindRemote(check[1], check[2])
            local name = check[1] .. "." .. check[2]

            if remote then
                found += 1
                print("[OK] " .. name)
            else
                warn("[NO] " .. name)
            end
        end

        print("Errores:", State.Errors)
        print("Último error:", State.LastError)
        print("=======================================")

        Notify(
            "Diagnóstico",
            tostring(found) .. "/" .. tostring(#checks)
                .. " remotos encontrados. Revisa la consola."
        )
    end,
})

-- ============================================================
-- LOOPS
-- ============================================================

task.spawn(function()
    while State.Running do
        if State.AutoHeal then
            Safe("AutoHeal", HealSelf, true)
        end

        task.wait(State.HealInterval)
    end
end)

task.spawn(function()
    while State.Running do
        if State.AutoAttack then
            Safe("AutoAttack", AttackEnemies, true)
        end

        task.wait(State.AttackInterval)
    end
end)

-- ============================================================
-- CLEANUP
-- ============================================================

State.Stop = function()
    if not State.Running then
        return
    end

    local humanoid = GetHumanoid()
    local original = humanoid and State.HumanoidCache[humanoid]

    if humanoid and original then
        if State.SpeedEnabled then
            humanoid.WalkSpeed = original.WalkSpeed
        end

        if State.JumpEnabled then
            humanoid.JumpPower = original.JumpPower
            humanoid.UseJumpPower = original.UseJumpPower
        end
    end

    State.Running = false
    State.SemiGod = false
    State.AntiSlip = false
    State.AutoHeal = false
    State.AutoAttack = false
    State.ESP = false

    for _, connection in ipairs(State.Connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end

    table.clear(State.Connections)

    RestoreCollisions()
    RestoreLighting()

    pcall(function()
        VisualFolder:Destroy()
    end)

    pcall(function()
        Window:Unload()
    end)

    if Env.VANTA_BI2 == State then
        Env.VANTA_BI2 = nil
    end

    print("[VANTA] Funciones detenidas.")
end

Settings:CreateButton({
    name = "Cerrar y detener funciones",
    description = "Restaura movimiento, colisiones y luz locales.",

    callback = function()
        State.Stop()
    end,
})

Notify(
    "VANTA cargado",
    "PlaceId: " .. tostring(game.PlaceId)
        .. " | Hooks: " .. (HookAvailable and "sí" or "no")
)