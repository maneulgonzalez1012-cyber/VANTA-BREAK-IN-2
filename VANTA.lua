--[[
    VANTA | BREAK IN 2
    Executor + Rayfield Gen2

    Reescrito sobre los remotos verificados del juego.

    LUGARES (PlaceId)
    - 13864667823  historia
    - 14775231477  lobby privado
    - 13864661000  lobby

    REMOTOS CONFIRMADOS (ReplicatedStorage.Events)
    - GiveTool(nombre)                       dar herramienta
    - Vending(3, item, categoria, quien, 1)  vending / armas
    - Energy(delta, item)                    curar o dañar
    - HealTheNoobs()                         curar a todos los NPC
    - RainbowWhatStat("Strength"/"Speed")    entrenar
    - HitBadguy(modelo, daño, 4)             daño a NPC
    - RoadMissionEvent(1, part, 5)           romper árboles
    - OutsideFood(6, {item2=, placement=})   comida en la cocina
    - LarryEndingEvent(clave, true)          final secreto
    - IceSlip(Vector3)                       resbalón (bloqueado)
    - OnDoorHit(parte)                       golpear puerta
    - CatFed(item) / LouiseGive(2) / KeyEvent()

    NOTAS
    - FireServer no confirma que el servidor acepte la acción.
    - Lo que es solo local (movimiento, noclip, luz, ESP) se dice en la UI.
]]

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local Player = Players.LocalPlayer
local Env = getgenv()

-- Evitar varias instancias activas.
if Env.VANTA_BI2 and type(Env.VANTA_BI2.Stop) == "function" then
    pcall(Env.VANTA_BI2.Stop)
end

-- ============================================================
-- ESTADO
-- ============================================================

local State = {
    Running = true,
    Window = nil,

    SemiGod = false,
    AntiSlip = false,
    AutoHeal = false,
    AutoHealAmount = 25,
    AutoAttack = false,
    ESP = false,
    EnemyESP = false,

    SpeedEnabled = false,
    JumpEnabled = false,
    InfJump = false,
    Noclip = false,
    Fullbright = false,
    NoWind = false,
    NoMud = false,
    FreezeEnemies = false,

    Speed = 32,
    Jump = 75,

    AttackDamage = 65,
    AttackBurst = 4,
    AttackRadius = 150,
    AttackInterval = 0.5,
    HealInterval = 1.5,
    TrainAmount = 5,

    SelectedItem = "Golden Apple",
    SelectedPlayer = "",
    FoodPlacement = 1,

    Connections = {},
    ESPObjects = {},
    EnemyESPObjects = {},
    CollisionCache = {},
    HumanoidCache = setmetatable({}, {__mode = "k"}),

    Stats = {
        Kills = 0,
        Damage = 0,
        Heals = 0,
        Items = 0,
        Trains = 0,
        Dropped = 0,
    },

    Errors = 0,
    LastError = "Ninguno",
    MissingRemotes = {},
}

Env.VANTA_BI2 = State

local OriginalLighting = {
    Brightness = Lighting.Brightness,
    ClockTime = Lighting.ClockTime,
    FogEnd = Lighting.FogEnd,
    FogStart = Lighting.FogStart,
    GlobalShadows = Lighting.GlobalShadows,
    Ambient = Lighting.Ambient,
    OutdoorAmbient = Lighting.OutdoorAmbient,
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

local function IsAlive()
    local humanoid = GetHumanoid()

    return humanoid ~= nil and humanoid.Health > 0
end

-- Nombres de herramienta: el juego quita los espacios ("Golden Apple" -> "GoldenApple")
local function ToolName(item)
    return (tostring(item):gsub("%s", ""))
end

-- ============================================================
-- REMOTOS
-- ============================================================

local function GetEventsFolder()
    local folder = ReplicatedStorage:FindFirstChild("Events")

    if not folder then
        folder = ReplicatedStorage:FindFirstChild("RemoteEvents")
    end

    return folder
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

local function RememberMissing(label)
    State.MissingRemotes[label] = true
end

-- Los remotos son baratos pero no infinitos: un bucle de 60 paquetes por
-- segundo es la vía rápida al kick. Esto lo corta.
local RateLimit = {
    Window = 1,
    Max = 40,
    Count = 0,
    Started = os.clock(),
}

local function RateAllowed()
    local now = os.clock()

    if now - RateLimit.Started >= RateLimit.Window then
        RateLimit.Started = now
        RateLimit.Count = 0
    end

    if RateLimit.Count >= RateLimit.Max then
        State.Stats.Dropped += 1
        return false
    end

    RateLimit.Count += 1
    return true
end

local function Fire(folderName, remoteName, ...)
    local remote, err = FindRemote(folderName, remoteName)

    if not remote then
        RememberMissing(folderName .. "." .. remoteName)
        return false, err
    end

    if not RateAllowed() then
        return false, "límite de paquetes alcanzado"
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

-- Atajo para el folder real del juego.
local function Event(remoteName, ...)
    return Fire("Events", remoteName, ...)
end

-- ============================================================
-- RAYFIELD GEN2
-- ============================================================

local okLibrary, Rayfield = pcall(function()
    local source = game:HttpGet("https://sirius.menu/gen2")

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
        subtitle = "Remotos verificados",
        sidebarLayout = true,
        configuration = {
            autoSave = true,
            autoLoad = true,
            fileName = "VANTA_BreakIn2",
        },
    })
end)

if not okWindow or not Window then
    State.Running = false
    warn("[VANTA] No se pudo crear la ventana:", Window)
    return
end

State.Window = Window

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

local OriginalNamecall

if HookAvailable then
    local okHook, hookError = pcall(function()
        OriginalNamecall = hookmetamethod(
            game,
            "__namecall",
            newcclosure(function(self, ...)
                if State.Running and getnamecallmethod() == "FireServer" then
                    local args = table.pack(...)

                    -- Anti-slip: no se envía nada al remoto IceSlip.
                    if State.AntiSlip
                        and type(self) == "userdata"
                        and self.Name == "IceSlip"
                        and self:IsA("RemoteEvent")
                    then
                        return nil
                    end

                    -- Semi godmode: el daño viaja como número negativo en Energy.
                    if State.SemiGod
                        and type(self) == "userdata"
                        and self.Name == "Energy"
                        and self:IsA("RemoteEvent")
                    then
                        if type(args[1]) == "number" and args[1] < 0 then
                            args[1] = 0
                        end

                        return OriginalNamecall(
                            self,
                            table.unpack(args, 1, args.n)
                        )
                    end
                end

                return OriginalNamecall(self, ...)
            end)
        )
    end)

    if not okHook then
        HookAvailable = false
        OriginalNamecall = nil
        warn("[VANTA] Hook no disponible:", hookError)
    end
end

-- ============================================================
-- OBJETOS
-- ============================================================

local Weapons = {
    ["Crowbar 1"] = true,
    ["Crowbar 2"] = true,
    ["Crowbar 3"] = true,
    ["Bat"] = true,
    ["Pitchfork"] = true,
    ["Hammer"] = true,
    ["Wrench"] = true,
    ["Broom"] = true,
}

-- El vending usa el id interno, que no siempre coincide con el nombre visible.
local WeaponIDs = {
    ["Diamond Crowbar"] = "Crowbar3",
}

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
    "Diamond Crowbar",
    "Bat",
    "Pitchfork",
    "Hammer",
    "Wrench",
    "Broom",
}

local function GiveItem(item, silent)
    if type(item) ~= "string" or item == "" then
        return false
    end

    local ok, err

    if item == "Armor" then
        ok, err = Event("Vending", 3, "Armor2", "Armor", Player.Name, 1)

    elseif Weapons[item] or WeaponIDs[item] then
        ok, err = Event(
            "Vending",
            3,
            WeaponIDs[item] or ToolName(item),
            "Weapons",
            Player.Name,
            1
        )

    else
        -- Herramientas y comida: GiveTool con el nombre sin espacios.
        ok, err = Event("GiveTool", ToolName(item))
    end

    if ok then
        State.Stats.Items += 1
    elseif not silent then
        Notify("Objeto", err)
    end

    return ok
end

-- Variante silenciosa: los spammers usan esto para no inundar notificaciones.
local function GiveItemRaw(item)
    return GiveItem(item, true)
end

local function GiveList(list, delay)
    task.spawn(function()
        local sent = 0

        for _, item in ipairs(list) do
            if not State.Running then
                return
            end

            if GiveItemRaw(item) then
                sent += 1
            end

            task.wait(delay or 0.25)
        end

        Notify(
            "Objetos",
            tostring(sent) .. "/" .. tostring(#list)
                .. " solicitudes enviadas. Revisa el inventario."
        )
    end)
end

-- ============================================================
-- CURA
-- ============================================================

local function HasTool(toolName)
    local backpack = Player:FindFirstChildOfClass("Backpack")
    local character = GetCharacter()

    if backpack and backpack:FindFirstChild(toolName) then
        return true
    end

    if character and character:FindFirstChild(toolName) then
        return true
    end

    return false
end

local function HealSelf(silent, amount)
    amount = amount or State.AutoHealAmount

    if amount <= 0 then
        amount = 25
    end

    if not IsAlive() then
        return false
    end

    -- Solo pide pizza si no hay ninguna: pedirla en cada tick es lo que
    -- hace que el servidor te trate como spammer.
    local okItem, errItem = true, nil

    if not HasTool("Pizza") then
        okItem, errItem = Event("GiveTool", "Pizza")
        task.wait(0.1)
    end

    -- El servidor valida el ítem al procesar Energy.
    local okEnergy, errEnergy = Event("Energy", amount, "Pizza")

    if okEnergy then
        State.Stats.Heals += 1
    end

    if not silent then
        if not okItem then
            Notify("Curación", errItem)
        elseif not okEnergy then
            Notify("Curación", errEnergy)
        else
            Notify("Curación", "Solicitud de +" .. tostring(amount) .. " enviada.")
        end
    end

    return okItem and okEnergy
end

local function EquipTool(toolName)
    local character = GetCharacter()
    local backpack = Player:FindFirstChildOfClass("Backpack")

    if not character or not backpack then
        return nil
    end

    local tool = backpack:FindFirstChild(toolName)
        or character:FindFirstChild(toolName)

    if not tool then
        return nil
    end

    if tool.Parent ~= character then
        pcall(function()
            tool.Parent = character
        end)
    end

    return tool
end

local HealGuard = false

local function HealEveryone()
    if HealGuard then
        Notify("Curar a todos", "Ya hay una cura en curso.")
        return
    end

    HealGuard = true

    task.spawn(function()
        local ok = Safe("HealEveryone", function()
            local humanoid = GetHumanoid()

            if humanoid then
                humanoid:UnequipTools()
                task.wait(0.15)
            end

            if not GetCharacter() then
                Notify("Curar a todos", "No hay personaje.")
                return
            end

            if not GiveItemRaw("Golden Apple") then
                Notify("Curar a todos", "No se pudo pedir la manzana dorada.")
                return
            end

            local backpack = Player:FindFirstChildOfClass("Backpack")

            if not backpack then
                Notify("Curar a todos", "No se encontró la mochila.")
                return
            end

            local apple = backpack:FindFirstChild("GoldenApple")
                or backpack:WaitForChild("GoldenApple", 4)

            local character = GetCharacter()

            if not apple or not character then
                Notify(
                    "Curar a todos",
                    "La manzana dorada no llegó o falta el personaje."
                )
                return
            end

            pcall(function()
                apple.Parent = character
            end)

            task.wait(0.4)

            if Event("HealTheNoobs") then
                State.Stats.Heals += 1
                Notify("Curar a todos", "Solicitud enviada.")
            else
                Notify("Curar a todos", "HealTheNoobs no disponible.")
            end
        end)

        HealGuard = false

        if not ok then
            Notify("Curar a todos", "Error: " .. tostring(State.LastError))
        end
    end)
end

-- ============================================================
-- ENTRENAMIENTO
-- ============================================================

local function Train(stat, amount, silent)
    amount = math.clamp(tonumber(amount) or 5, 1, 100)

    task.spawn(function()
        local sent = 0

        for _ = 1, amount do
            if not State.Running then
                return
            end

            local ok, err = Event("RainbowWhatStat", stat)

            if not ok then
                if not silent then
                    Notify("Entrenamiento", err)
                end

                return
            end

            sent += 1
            State.Stats.Trains += 1
            task.wait(0.2)
        end

        if not silent then
            Notify(
                "Entrenamiento",
                stat .. ": " .. tostring(sent) .. " solicitudes enviadas."
            )
        end
    end)
end

-- ============================================================
-- COMBATE
-- ============================================================

local EnemyFolders = {"BadGuys", "BadGuysBoss", "BadGuysFront"}

local function GetEnemies()
    local enemies = {}
    local seen = {}

    local function Add(npc)
        if npc and not seen[npc] then
            seen[npc] = true
            table.insert(enemies, npc)
        end
    end

    for _, folderName in ipairs(EnemyFolders) do
        local folder = Workspace:FindFirstChild(folderName)

        if folder then
            for _, npc in ipairs(folder:GetChildren()) do
                Add(npc)
            end
        end
    end

    Add(Workspace:FindFirstChild("BadGuyPizza", true))
    Add(Workspace:FindFirstChild("BadGuyBrute", true))
    Add(Workspace:FindFirstChild("BadGuyBrute2", true))

    return enemies
end

local function GetEnemyRoot(npc)
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

local function IsEnemyAlive(npc)
    local humanoid = npc:FindFirstChildOfClass("Humanoid")

    if humanoid then
        return humanoid.Health > 0
    end

    return true
end

local function AttackEnemies(silent)
    local root = GetRoot()

    if not root then
        return 0
    end

    local remote, err = FindRemote("Events", "HitBadguy")

    if not remote then
        RememberMissing("Events.HitBadguy")

        if not silent then
            Notify("Combate", err)
        end

        return 0
    end

    local hit = 0
    local damage = State.AttackDamage
    local burst = math.clamp(State.AttackBurst, 1, 10)
    local enemies = GetEnemies()

    for _, npc in ipairs(enemies) do
        if not State.Running then
            break
        end

        local part = GetEnemyRoot(npc)

        if part and IsEnemyAlive(npc) then
            local distance = (part.Position - root.Position).Magnitude

            if distance <= State.AttackRadius then
                for _ = 1, burst do
                    local ok = pcall(function()
                        -- El remoto espera el modelo del NPC, no la parte.
                        remote:FireServer(npc, damage, 4)
                    end)

                    if ok then
                        hit += 1
                        State.Stats.Damage += damage
                    end
                end
            end
        end
    end

    if not silent then
        Notify(
            "Combate",
            tostring(hit) .. " golpes enviados a "
                .. tostring(#enemies) .. " NPC."
        )
    end

    return hit
end

local function KillAllEnemies(silent)
    local before = #GetEnemies()
    local hit = AttackEnemies(true)

    -- El servidor no confirma la muerte: se espera un instante y se cuenta
    -- lo que realmente desapareció del mapa.
    task.wait(0.2)

    local after = #GetEnemies()
    local killed = math.max(before - after, 0)

    State.Stats.Kills += killed

    if not silent then
        Notify(
            "Combate",
            tostring(hit) .. " golpes enviados | "
                .. tostring(killed) .. "/" .. tostring(before) .. " NPC caídos."
        )
    end

    return hit
end

-- Traer NPC al jugador: solo funciona si el modelo no está anclado en el servidor.
local function BringEnemies()
    local root = GetRoot()

    if not root then
        return 0
    end

    local moved = 0

    for _, npc in ipairs(GetEnemies()) do
        if npc:IsA("Model") and IsEnemyAlive(npc) then
            local npcRoot = npc:FindFirstChild("HumanoidRootPart")

            if npcRoot then
                local ok = pcall(function()
                    npcRoot.CFrame = root.CFrame * CFrame.new(0, 0, -4)
                end)

                if ok then
                    moved += 1
                end
            end
        end
    end

    if moved == 0 then
        Notify("Combate", "No hay NPC vivos para mover.")
    else
        Notify(
            "Combate",
            tostring(moved) .. " NPC movidos en el cliente. "
                .. "Si están anclados en el servidor, vuelven a su sitio."
        )
    end

    return moved
end

-- ============================================================
-- AMBIENTE: VIENTO / LODO / HIELO
-- ============================================================

-- Todo esto es local: toca partes del mapa que el cliente ve.

local function RemoveWind()
    local wave = Workspace:FindFirstChild("WavePart")

    if not wave then
        return false
    end

    local hail = Workspace:FindFirstChild("Hails")

    if hail then
        pcall(function()
            hail:Destroy()
        end)
    end

    pcall(function()
        wave.CanTouch = false
    end)

    return true
end

local function RemoveMud()
    local bog = Workspace:FindFirstChild("BogArea")

    if not bog then
        return 0
    end

    local cleared = 0

    for _, object in ipairs(bog:GetDescendants()) do
        if object.Name == "Mud" and object:IsA("BasePart") then
            pcall(function()
                object.CanTouch = false
            end)

            cleared += 1
        end
    end

    return cleared
end

local function PushEnemiesBack(direction, force)
    local root = GetRoot()

    if not root then
        return 0
    end

    local pushed = 0

    for _, npc in ipairs(GetEnemies()) do
        if npc:IsA("Model") and IsEnemyAlive(npc) then
            local npcRoot = npc:FindFirstChild("HumanoidRootPart")

            if npcRoot then
                pcall(function()
                    npcRoot.AssemblyLinearVelocity =
                        npcRoot.AssemblyLinearVelocity
                        + direction.Unit * force
                end)

                pushed += 1
            end
        end
    end

    return pushed
end

-- ============================================================
-- ÁRBOLES / BARRICADAS
-- ============================================================

local function BreakBarricades()
    local folder = Workspace:FindFirstChild("FallenTrees")

    if not folder then
        Notify("Barricadas", "No hay FallenTrees en este mapa.")
        return 0
    end

    local sent = 0

    for _, tree in ipairs(folder:GetChildren()) do
        local hitPart = tree:FindFirstChild("TreeHitPart")

        if hitPart then
            for _ = 1, 20 do
                if Event("RoadMissionEvent", 1, hitPart, 5) then
                    sent += 1
                else
                    break
                end
            end
        end
    end

    Notify("Barricadas", tostring(sent) .. " golpes enviados.")

    return sent
end

-- ============================================================
-- COMIDA DE COCINA
-- ============================================================

local function SpawnFood(item2, placement)
    placement = tonumber(placement) or State.FoodPlacement

    local ok, err = Event("OutsideFood", 6, {
        item2 = item2,
        placement = placement,
    })

    if not ok then
        Notify("Comida", err)
    end

    return ok
end

-- ============================================================
-- FINAL SECRETO
-- ============================================================

local SecretEndingKeys = {
    "HatCollected",
    "MaskCollected",
    "CrowbarCollected",
}

local function UnlockSecretEnding()
    local sent = 0

    for _, key in ipairs(SecretEndingKeys) do
        if Event("LarryEndingEvent", key, true) then
            sent += 1
        end
    end

    if sent > 0 then
        Notify("Final secreto", tostring(sent) .. "/3 eventos enviados.")
    end

    return sent
end

-- ============================================================
-- ESP
-- ============================================================

local VisualFolder = Instance.new("Folder")
VisualFolder.Name = "VANTA_BI2_ESP"
VisualFolder.Parent = Workspace

local function MakeHighlight(adornee, fill, outline, transparency)
    local highlight = Instance.new("Highlight")
    highlight.Name = "VANTA_Highlight"
    highlight.Adornee = adornee
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillColor = fill
    highlight.OutlineColor = outline
    highlight.FillTransparency = transparency or 0.75
    highlight.OutlineTransparency = 0
    highlight.Parent = VisualFolder

    return highlight
end

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
        or not target.Character
    then
        return
    end

    State.ESPObjects[target] = MakeHighlight(
        target.Character,
        Color3.fromRGB(100, 180, 255),
        Color3.fromRGB(220, 240, 255),
        0.8
    )
end

local function ClearEnemyESP()
    for npc, object in pairs(State.EnemyESPObjects) do
        if object then
            pcall(function()
                object:Destroy()
            end)
        end

        State.EnemyESPObjects[npc] = nil
    end
end

local function RefreshEnemyESP()
    if not State.EnemyESP then
        ClearEnemyESP()
        return
    end

    local alive = {}

    for _, npc in ipairs(GetEnemies()) do
        if IsEnemyAlive(npc) and npc:IsA("Model") then
            alive[npc] = true

            if not State.EnemyESPObjects[npc] then
                State.EnemyESPObjects[npc] = MakeHighlight(
                    npc,
                    Color3.fromRGB(255, 90, 90),
                    Color3.fromRGB(255, 200, 200),
                    0.7
                )
            end
        end
    end

    for npc, object in pairs(State.EnemyESPObjects) do
        if not alive[npc] or not npc.Parent then
            pcall(function()
                object:Destroy()
            end)

            State.EnemyESPObjects[npc] = nil
        end
    end
end

local function RefreshAllESP()
    for _, target in ipairs(Players:GetPlayers()) do
        RefreshESP(target)
    end

    RefreshEnemyESP()
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
-- MOVIMIENTO
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

    query = query:lower():gsub("^%s+", ""):gsub("%s+$", "")

    if query == "" then
        return nil
    end

    for _, target in ipairs(Players:GetPlayers()) do
        if target ~= Player
            and (
                target.Name:lower() == query
                or target.DisplayName:lower() == query
            )
        then
            return target
        end
    end

    for _, target in ipairs(Players:GetPlayers()) do
        if target ~= Player
            and (
                target.Name:lower():find(query, 1, true)
                or target.DisplayName:lower():find(query, 1, true)
            )
        then
            return target
        end
    end

    return nil
end

local function TeleportToPlayer()
    local root = GetRoot()

    if not root then
        Notify("Teleport", "No hay personaje.")
        return
    end

    if State.SelectedPlayer == "" then
        Notify("Teleport", "Escribe un nombre primero.")
        return
    end

    local target = FindPlayer(State.SelectedPlayer)

    local targetRoot = target
        and target.Character
        and target.Character:FindFirstChild("HumanoidRootPart")

    if not target or not targetRoot then
        Notify("Teleport", "Jugador o personaje no encontrado.")
        return
    end

    root.CFrame = targetRoot.CFrame * CFrame.new(3, 0, 0)
    Notify("Teleport", "Movido a " .. target.Name)
end

local PlaceCFrames = {
    {name = "Tienda", cframe = CFrame.new(-246.653229, 30.4500484, -847.319275, 0.999987781, -9.18427645e-08, -0.00494772941, 9.19905787e-08, 1, 2.96483353e-08, 0.00494772941, -3.01031164e-08, 0.999987781)},
    {name = "Cocina", cframe = CFrame.new(-249.753555, 30.4500484, -732.703125, -0.999205947, -1.97705017e-08, 0.0398429185, -2.00601384e-08, 1, -6.86967372e-09, -0.0398429185, -7.66347341e-09, -0.999205947)},
    {name = "Arena de pelea", cframe = CFrame.new(-255.521988, 62.7139359, -723.436035, -0.0542500541, 4.28905356e-09, -0.998527408, 1.07862625e-08, 1, 3.70936082e-09, 0.998527408, -1.05691456e-08, -0.0542500541)},
    {name = "Gimnasio", cframe = CFrame.new(-256.477448, 63.4500465, -840.825562, 0.999789953, 2.17116263e-08, 0.020495005, -2.15169358e-08, 1, -9.7199333e-09, -0.020495005, 9.27690191e-09, 0.999789953)},
    {name = "Habitación central", cframe = CFrame.new(-209.951859, 30.4590473, -789.723877, -0.0485812724, 6.74905039e-08, 0.998819232, 1.19352916e-09, 1, -6.75122394e-08, -0.998819232, -2.08771045e-09, -0.0485812724)},
    {name = "Pelea de jefe", cframe = CFrame.new(-1565.78772, -368.711945, -1040.66626, 0.0929690823, -1.97564436e-08, 0.995669007, -1.53269308e-08, 1, 2.1273511e-08, -0.995669007, -1.72383299e-08, 0.0929690823)},
    {name = "Pilar de Scary Mary", cframe = CFrame.new(-1501.49597, -325.156891, -1060.63367, -0.691015959, 7.43958628e-09, 0.722839475, -5.03345055e-09, 1, -1.51040194e-08, -0.722839475, -1.40754954e-08, -0.691015959)},
    {name = "Agente Bradley", cframe = CFrame.new(-281.792053, 95.4500275, -790.556946, -0.116918251, -7.95074726e-08, -0.993141532, -2.79918044e-09, 1, -7.97270019e-08, 0.993141532, -6.54155974e-09, -0.116918251)},
    {name = "Twando (perro)", cframe = CFrame.new(-257.56839, 29.4499969, -910.452637, -0.238445505, 7.71292363e-09, 0.971155882, 1.2913591e-10, 1, -7.91029819e-09, -0.971155882, -1.76076387e-09, -0.238445505)},
    {name = "Tío Pete", cframe = CFrame.new(-294.208923, 63.4182587, -737.712036, -0.998669028, -7.34403613e-08, -0.05157727, -7.2258743e-08, 1, -2.47743781e-08, 0.05157727, -2.1014495e-08, -0.998669028)},
    {name = "Palanca dorada", cframe = CFrame.new(-147.337204, 29.4477005, -929.365295, 0.756779075, 4.53537341e-09, -0.653670728, 5.82708326e-09, 1, 1.36845468e-08, 0.653670728, -1.4165173e-08, 0.756779075)},
    {name = "Máscara morada", cframe = CFrame.new(102.560722, 29.2477055, -976.389954, -0.951403797, 3.76210636e-08, -0.307946175, 1.89752569e-08, 1, 6.35433466e-08, 0.307946175, 5.46120233e-08, -0.951403797)},
    {name = "Golden Apple", cframe = CFrame.new(61.8781624, 29.4499969, -534.381165, -0.584439218, -1.05103076e-07, 0.811437488, -3.12853778e-08, 1, 1.06993674e-07, -0.811437488, 3.71451705e-08, -0.584439218)},
}

local function TeleportTo(placeName)
    local root = GetRoot()

    if not root then
        Notify("Teleport", "No hay personaje.")
        return
    end

    for _, place in ipairs(PlaceCFrames) do
        if place.name == placeName then
            root.CFrame = place.cframe
            Notify("Teleport", placeName)
            return
        end
    end
end

Connect(RunService.Stepped, function()
    if not State.Running then
        return
    end

    local humanoid = GetHumanoid()
    local character = GetCharacter()

    if humanoid then
        RememberHumanoid(humanoid)

        if State.SpeedEnabled and humanoid.WalkSpeed ~= State.Speed then
            humanoid.WalkSpeed = State.Speed
        end

        if State.JumpEnabled then
            if not humanoid.UseJumpPower then
                humanoid.UseJumpPower = true
            end

            if humanoid.JumpPower ~= State.Jump then
                humanoid.JumpPower = State.Jump
            end
        end
    end

    if State.Noclip and character then
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") then
                if State.CollisionCache[part] == nil then
                    State.CollisionCache[part] = part.CanCollide
                end

                if part.CanCollide then
                    part.CanCollide = false
                end
            end
        end
    end
end)

-- Salto infinito: una sola conexión, controlada por el flag.
Connect(UserInputService.JumpRequest, function()
    if State.Running and State.InfJump then
        local humanoid = GetHumanoid()

        if humanoid and humanoid.Health > 0 then
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end
end)

-- ============================================================
-- TABS
-- ============================================================

local TabMain = Window:CreateTab({name = "Inicio"})
local TabSurvival = Window:CreateTab({name = "Supervivencia"})
local TabItems = Window:CreateTab({name = "Objetos"})
local TabCombat = Window:CreateTab({name = "Combate"})
local TabWorld = Window:CreateTab({name = "Mundo"})
local TabMove = Window:CreateTab({name = "Movimiento"})
local TabVisuals = Window:CreateTab({name = "Visuales"})
local TabLobby = Window:CreateTab({name = "Lobby"})
local TabDiag = Window:CreateTab({name = "Diagnóstico"})

TabMain:CreateText({
    name = "VANTA | BREAK IN 2",
    text = "Remotos verificados sobre la historia y el lobby. "
        .. "Lo que es solo local (movimiento, noclip, luz, ESP) no toca el servidor.",
})

TabMain:CreateText({
    name = "Hooks",
    text = HookAvailable
        and "Disponibles: semi godmode y anti-slip activos."
        or "El executor no expone hookmetamethod. Semi godmode y anti-slip quedan apagados.",
})

local function DoQuickKit()
    local character = GetCharacter()
    local humanoid = GetHumanoid()

    if humanoid then
        humanoid:UnequipTools()
    end

    task.spawn(function()
        GiveItemRaw("Armor")
        task.wait(0.2)
        GiveItemRaw("Golden Apple")
        task.wait(0.2)
        GiveItemRaw("Med Kit")
        task.wait(0.2)
        GiveItemRaw("Crowbar 2")
        task.wait(0.2)

        -- Pizza de sobra: la usan la auto-curación y el heal.
        for _ = 1, 8 do
            GiveItemRaw("Gold Pizza")
            task.wait(0.05)
        end

        Train("Strength", 5, true)
        Train("Speed", 5, true)

        Notify("Kit rápido", "Armor, curas, palanca y entrenamiento enviados.")
    end)
end

TabMain:CreateButton({
    name = "Kit rápido (armor + curas + arma + entrenamiento)",
    callback = DoQuickKit,
})

TabMain:CreateButton({
    name = "Entrenar fuerza y velocidad ×5",
    callback = function()
        Train("Strength", 5)
        Train("Speed", 5)
    end,
})

TabMain:CreateButton({
    name = "Matar a todos los NPC cercanos",
    callback = function()
        KillAllEnemies(false)
    end,
})

TabMain:CreateButton({
    name = "Curar a todos (manzana dorada)",
    callback = HealEveryone,
})

-- SUPERVIVENCIA

TabSurvival:CreateSection({name = "Protección"})

TabSurvival:CreateToggle({
    name = "Semi godmode",
    description = HookAvailable
        and "Convierte el daño negativo de Energy en 0."
        or "Requiere hookmetamethod.",
    flag = "semiGod",
    value = false,
    callback = function(value)
        State.SemiGod = value and HookAvailable

        if value and not HookAvailable then
            Notify("Semi godmode", "Hooks no disponibles en este executor.")
        end
    end,
})

TabSurvival:CreateToggle({
    name = "Anti-slip",
    description = HookAvailable
        and "Bloquea el remoto IceSlip por completo."
        or "Requiere hookmetamethod.",
    flag = "antiSlip",
    value = false,
    callback = function(value)
        State.AntiSlip = value and HookAvailable

        if value and not HookAvailable then
            Notify("Anti-slip", "Hooks no disponibles en este executor.")
        end
    end,
})

TabSurvival:CreateSection({name = "Curación"})

TabSurvival:CreateButton({
    name = "Curarme ahora",
    callback = function()
        HealSelf(false)
    end,
})

TabSurvival:CreateSlider({
    name = "Cantidad por cura",
    range = {10, 150},
    increment = 5,
    value = 25,
    suffix = " HP",
    flag = "healAmount",
    callback = function(value)
        State.AutoHealAmount = value
    end,
})

TabSurvival:CreateToggle({
    name = "Auto-curación",
    description = "Manda pizza + Energy en bucle.",
    flag = "autoHeal",
    value = false,
    callback = function(value)
        State.AutoHeal = value
    end,
})

TabSurvival:CreateSlider({
    name = "Intervalo de auto-curación",
    range = {0.5, 10},
    increment = 0.5,
    value = 1.5,
    suffix = " s",
    flag = "healInterval",
    callback = function(value)
        State.HealInterval = value
    end,
})

TabSurvival:CreateButton({
    name = "Curar a todos (manzana dorada)",
    callback = HealEveryone,
})

TabSurvival:CreateSection({name = "Entrenamiento"})

TabSurvival:CreateSlider({
    name = "Repeticiones por stat",
    range = {1, 50},
    increment = 1,
    value = 5,
    flag = "trainAmount",
    callback = function(value)
        State.TrainAmount = value
    end,
})

TabSurvival:CreateButton({
    name = "Entrenar fuerza",
    callback = function()
        Train("Strength", State.TrainAmount)
    end,
})

TabSurvival:CreateButton({
    name = "Entrenar velocidad",
    callback = function()
        Train("Speed", State.TrainAmount)
    end,
})

TabSurvival:CreateButton({
    name = "Entrenar todo",
    callback = function()
        Train("Strength", State.TrainAmount)
        Train("Speed", State.TrainAmount)
    end,
})

-- OBJETOS

TabItems:CreateDropdown({
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

TabItems:CreateButton({
    name = "Dar objeto seleccionado",
    callback = function()
        if State.SelectedItem and GiveItem(State.SelectedItem) then
            Notify("Objetos", "Solicitado: " .. State.SelectedItem)
        end
    end,
})

TabItems:CreateButton({
    name = "Solicitar todos los objetos",
    callback = function()
        GiveList(Items, 0.2)
    end,
})

TabItems:CreateSection({name = "Acceso rápido"})

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
    "Louise",
}) do
    local currentItem = item

    TabItems:CreateButton({
        name = "Dar " .. currentItem,

        callback = function()
            if GiveItem(currentItem) then
                Notify("Objetos", "Solicitado: " .. currentItem)
            end
        end,
    })
end

TabItems:CreateSection({name = "Cocina"})

TabItems:CreateInput({
    name = "Slot de la mesa",
    placeholder = "1-4",
    value = "1",
    flag = "foodSlot",
    callback = function(value)
        State.FoodPlacement = tonumber(value) or 1
    end,
})

TabItems:CreateButton({
    name = "Spawnear caja de pizza",
    callback = function()
        if SpawnFood("Pizza") then
            Notify("Comida", "Caja de pizza solicitada.")
        end
    end,
})

TabItems:CreateButton({
    name = "Spawnear Bloxy Cola",
    callback = function()
        if SpawnFood("BloxyPack") then
            Notify("Comida", "Pack de Bloxy Cola solicitado.")
        end
    end,
})

-- COMBATE

TabCombat:CreateSlider({
    name = "Radio de ataque",
    range = {10, 300},
    increment = 10,
    value = 150,
    suffix = " studs",
    flag = "attackRadius",
    callback = function(value)
        State.AttackRadius = value
    end,
})

TabCombat:CreateSlider({
    name = "Daño por golpe",
    range = {5, 100},
    increment = 5,
    value = 65,
    flag = "attackDamage",
    callback = function(value)
        State.AttackDamage = value
    end,
})

TabCombat:CreateSlider({
    name = "Golpes por NPC",
    range = {1, 10},
    increment = 1,
    value = 4,
    suffix = "x",
    flag = "attackBurst",
    callback = function(value)
        State.AttackBurst = value
    end,
})

TabCombat:CreateSlider({
    name = "Intervalo de auto-ataque",
    range = {0.2, 5},
    increment = 0.1,
    value = 0.5,
    suffix = " s",
    flag = "attackInterval",
    callback = function(value)
        State.AttackInterval = value
    end,
})

TabCombat:CreateButton({
    name = "Atacar NPC cercanos una vez",
    callback = function()
        AttackEnemies(false)
    end,
})

TabCombat:CreateButton({
    name = "Matar a todos (barrido completo)",
    callback = function()
        KillAllEnemies(false)
    end,
})

TabCombat:CreateToggle({
    name = "Auto ataque NPC",
    flag = "autoAttack",
    value = false,
    callback = function(value)
        State.AutoAttack = value
    end,
})

TabCombat:CreateSection({name = "Utilidades"})

TabCombat:CreateButton({
    name = "Traer NPC al jugador (local)",
    callback = BringEnemies,
})

TabCombat:CreateToggle({
    name = "Congelar NPC",
    description = "Ancla los HumanoidRootPart en el cliente. Local.",
    flag = "freezeEnemies",
    value = false,
    callback = function(value)
        State.FreezeEnemies = value

        if not value then
            for _, npc in ipairs(GetEnemies()) do
                local npcRoot = npc:IsA("Model")
                    and npc:FindFirstChild("HumanoidRootPart")

                if npcRoot then
                    pcall(function()
                        npcRoot.Anchored = false
                    end)
                end
            end
        end
    end,
})

TabCombat:CreateButton({
    name = "Romper barricadas de árboles",
    callback = BreakBarricades,
})

-- MUNDO / TELEPORT

TabWorld:CreateText({
    name = "Teleports",
    text = "Coordenadas de la historia. En el lobby no hacen nada útil.",
})

for _, place in ipairs(PlaceCFrames) do
    local currentPlace = place.name

    TabWorld:CreateButton({
        name = currentPlace,
        callback = function()
            TeleportTo(currentPlace)
        end,
    })
end

TabWorld:CreateSection({name = "Ambiente (local)"})

TabWorld:CreateToggle({
    name = "Quitar viento y granizo",
    description = "Mata Hails y desactiva el toque de WavePart.",
    flag = "noWind",
    value = false,
    callback = function(value)
        State.NoWind = value

        if value then
            local ok = RemoveWind()

            if not ok then
                Notify("Ambiente", "No hay viento en este mapa todavía.")
            end
        end
    end,
})

TabWorld:CreateToggle({
    name = "Quitar lodo",
    description = "CanTouch = false en las partes Mud de BogArea.",
    flag = "noMud",
    value = false,
    callback = function(value)
        State.NoMud = value

        if value then
            local cleared = RemoveMud()

            if cleared == 0 then
                Notify("Ambiente", "No hay lodo en este mapa.")
            else
                Notify("Ambiente", tostring(cleared) .. " partes de lodo desactivadas.")
            end
        end
    end,
})

TabWorld:CreateButton({
    name = "Empujar NPC lejos",
    description = "Impulso local sobre los enemigos vivos.",
    callback = function()
        local root = GetRoot()

        if not root then
            return
        end

        local pushed = PushEnemiesBack(root.CFrame.LookVector, 200)

        Notify("Combate", tostring(pushed) .. " NPC empujados.")
    end,
})

TabWorld:CreateSection({name = "Progreso"})

TabWorld:CreateButton({
    name = "Abrir final secreto",
    description = "LarryEndingEvent con las tres claves.",
    callback = UnlockSecretEnding,
})

TabWorld:CreateButton({
    name = "Golpear puerta",
    description = "OnDoorHit apuntando al modelo cercano o a la puerta del mapa.",
    callback = function()
        local root = GetRoot()

        if not root then
            return
        end

        -- Sin acceso a la puerta exacta: se manda el modelo del mapa si existe.
        local door = Workspace:FindFirstChild("Door", true)
            or Workspace:FindFirstChild("Doorframe", true)

        if door then
            if TryFire("Events", "OnDoorHit", door) then
                Notify("Puerta", "OnDoorHit enviado.")
            end
        else
            Notify("Puerta", "No se encontró una puerta en el mapa.")
        end
    end,
})

-- MOVIMIENTO

TabMove:CreateSlider({
    name = "WalkSpeed",
    range = {16, 300},
    increment = 2,
    value = 32,
    flag = "speed",
    callback = function(value)
        State.Speed = value
    end,
})

TabMove:CreateToggle({
    name = "Activar velocidad",
    flag = "speedEnabled",
    value = false,
    callback = function(value)
        State.SpeedEnabled = value

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
    end,
})

TabMove:CreateSlider({
    name = "JumpPower",
    range = {50, 300},
    increment = 5,
    value = 75,
    flag = "jump",
    callback = function(value)
        State.Jump = value
    end,
})

TabMove:CreateToggle({
    name = "Activar salto",
    flag = "jumpEnabled",
    value = false,
    callback = function(value)
        State.JumpEnabled = value

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
    end,
})

TabMove:CreateToggle({
    name = "Salto infinito",
    description = "Local. Se puede saltar en el aire.",
    flag = "infJump",
    value = false,
    callback = function(value)
        State.InfJump = value
    end,
})

TabMove:CreateToggle({
    name = "Noclip",
    description = "Local. Atraviesa paredes.",
    flag = "noclip",
    value = false,
    callback = function(value)
        State.Noclip = value

        if not value then
            RestoreCollisions()
        end
    end,
})

TabMove:CreateInput({
    name = "Jugador para teleport",
    placeholder = "Nombre exacto o parcial",
    value = "",
    flag = "targetPlayer",
    callback = function(value)
        State.SelectedPlayer = tostring(value or "")
    end,
})

TabMove:CreateButton({
    name = "Teleport al jugador",
    callback = TeleportToPlayer,
})

-- VISUALES

TabVisuals:CreateToggle({
    name = "ESP jugadores",
    description = "Resalta a los otros jugadores.",
    flag = "playerESP",
    value = false,
    callback = function(value)
        State.ESP = value
        RefreshAllESP()
    end,
})

TabVisuals:CreateToggle({
    name = "ESP enemigos",
    description = "Resalta BadGuys, jefes y variantes.",
    flag = "enemyESP",
    value = false,
    callback = function(value)
        State.EnemyESP = value
        RefreshEnemyESP()
    end,
})

TabVisuals:CreateToggle({
    name = "Fullbright",
    description = "Local. Sube luz y quita sombras.",
    flag = "fullbright",
    value = false,
    callback = function(value)
        State.Fullbright = value

        if value then
            Lighting.Brightness = 3
            Lighting.ClockTime = 14
            Lighting.FogEnd = 100000
            Lighting.FogStart = 0
            Lighting.GlobalShadows = false
            Lighting.Ambient = Color3.fromRGB(150, 150, 150)
            Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 150)
        else
            RestoreLighting()
        end
    end,
})

-- LOBBY

TabLobby:CreateText({
    name = "Roles",
    text = "Solo funcionan en el lobby (14775231477 / 13864661000), "
        .. "antes de empezar la partida.",
})

TabLobby:CreateButton({
    name = "Solicitar Hacker",
    callback = function()
        if TryFire("RemoteEvents", "OutsideRole", "Phone", true, false) then
            Notify("Lobby", "Rol Hacker solicitado.")
        end
    end,
})

TabLobby:CreateButton({
    name = "Solicitar Nerd",
    callback = function()
        if TryFire("RemoteEvents", "OutsideRole", "Book", true, false) then
            Notify("Lobby", "Rol Nerd solicitado.")
        end
    end,
})

TabLobby:CreateButton({
    name = "Tocar objetos del lobby",
    description = "firetouchinterest sobre las partes con TouchInterest.",
    callback = function()
        local root = GetRoot()

        if not root then
            return
        end

        local touched = 0

        for _, object in ipairs(Workspace:GetChildren()) do
            if object.Name == "Part" and object:FindFirstChild("TouchInterest") then
                pcall(function()
                    firetouchinterest(object, root, 0)
                    task.wait()
                    firetouchinterest(object, root, 1)
                    touched += 1
                end)
            end
        end

        Notify("Lobby", tostring(touched) .. " partes tocadas.")
    end,
})

-- DIAGNÓSTICO

local RemoteChecks = {
    {"Events", "GiveTool"},
    {"Events", "Vending"},
    {"Events", "Energy"},
    {"Events", "HealTheNoobs"},
    {"Events", "RainbowWhatStat"},
    {"Events", "HitBadguy"},
    {"Events", "IceSlip"},
    {"Events", "RoadMissionEvent"},
    {"Events", "OutsideFood"},
    {"Events", "LarryEndingEvent"},
    {"Events", "OnDoorHit"},
    {"Events", "CatFed"},
    {"Events", "LouiseGive"},
    {"Events", "KeyEvent"},
    {"RemoteEvents", "OutsideRole"},
}

local function RunDiagnostics()
    local found = 0
    local report = {}

    print("========== VANTA DIAGNÓSTICO ==========")
    print("PlaceId:", game.PlaceId)
    local okInfo, info = pcall(function()
        return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId)
    end)

    print("Juego:", okInfo and info and info.Name or "desconocido")
    print("Hooks:", HookAvailable and "sí" or "no")

    for _, check in ipairs(RemoteChecks) do
        local remote = FindRemote(check[1], check[2])
        local label = check[1] .. "." .. check[2]

        if remote then
            found += 1
            print("[OK] " .. label)
            table.insert(report, "OK " .. label)
        else
            warn("[NO] " .. label)
        end
    end

    print("Errores:", State.Errors)
    print("Último error:", State.LastError)
    print("Paquetes descartados por límite:", State.Stats.Dropped)
    print("=======================================")

    Notify(
        "Diagnóstico",
        tostring(found) .. "/" .. tostring(#RemoteChecks)
            .. " remotos encontrados. Detalle en la consola."
    )

    return found
end

TabDiag:CreateText({
    name = "Estado",
    text = "Los remotos verificados son: GiveTool, Vending, Energy, HealTheNoobs, "
        .. "RainbowWhatStat, HitBadguy, RoadMissionEvent, OutsideFood, "
        .. "LarryEndingEvent, IceSlip, OnDoorHit.",
})

TabDiag:CreateButton({
    name = "Escanear remotos",
    callback = RunDiagnostics,
})

TabDiag:CreateButton({
    name = "Imprimir árbol de ReplicatedStorage",
    callback = function()
        local function dump(parent, depth)
            if depth > 3 then
                return
            end

            for _, child in ipairs(parent:GetChildren()) do
                print(string.rep("  ", depth) .. child.ClassName .. " : " .. child.Name)

                if child:IsA("Folder") or child:IsA("Model") then
                    dump(child, depth + 1)
                end
            end
        end

        print("===== ReplicatedStorage =====")
        dump(ReplicatedStorage, 0)

        local events = GetEventsFolder()

        if events then
            print("===== " .. events.Name .. " =====")

            for _, child in ipairs(events:GetChildren()) do
                print("  " .. child.ClassName .. " : " .. child.Name)
            end
        end

        Notify("Diagnóstico", "Árbol impreso en la consola (F9).")
    end,
})

TabDiag:CreateButton({
    name = "Estado del script",
    callback = function()
        local lines = {
            "PlaceId: " .. tostring(game.PlaceId),
            "Hooks: " .. (HookAvailable and "sí" or "no"),
            "Errores: " .. tostring(State.Errors),
            "Último error: " .. tostring(State.LastError),
            "Objetos pedidos: " .. tostring(State.Stats.Items),
            "Curas: " .. tostring(State.Stats.Heals),
            "Entrenos: " .. tostring(State.Stats.Trains),
            "Daño enviado: " .. tostring(State.Stats.Damage),
            "Paquetes descartados: " .. tostring(State.Stats.Dropped),
        }

        print("===== VANTA ESTADO =====")

        for _, line in ipairs(lines) do
            print(line)
        end

        Notify("Estado", lines[3] .. " | " .. lines[2])
    end,
})

TabDiag:CreateButton({
    name = "Detener y limpiar",
    description = "Restaura movimiento, colisiones, luz y cierra la ventana.",
    callback = function()
        if State.Stop then
            State.Stop()
        end
    end,
})

-- ============================================================
-- LOOPS
-- ============================================================

task.spawn(function()
    while State.Running do
        if State.AutoHeal then
            local humanoid = GetHumanoid()

            -- Curarse a tope es lo que rompe el juego: solo si falta vida.
            if humanoid and humanoid.Health > 0
                and humanoid.Health < humanoid.MaxHealth then

                Safe("AutoHeal", HealSelf, true)
            end
        end

        task.wait(math.max(State.HealInterval, 0.2))
    end
end)

task.spawn(function()
    while State.Running do
        if State.AutoAttack then
            Safe("AutoAttack", AttackEnemies, true)
        end

        task.wait(math.max(State.AttackInterval, 0.1))
    end
end)

task.spawn(function()
    while State.Running do
        if State.EnemyESP then
            Safe("EnemyESP", RefreshEnemyESP)
        end

        task.wait(1)
    end
end)

-- El mapa regenera Hails/WavePart: se reaplica el bloqueo mientras esté activo.
task.spawn(function()
    while State.Running do
        if State.NoWind then
            Safe("NoWind", RemoveWind)
        end

        if State.NoMud then
            Safe("NoMud", RemoveMud)
        end

        task.wait(1)
    end
end)

-- Congelar NPC: reancla cada tick corto mientras esté activo.
task.spawn(function()
    while State.Running do
        if State.FreezeEnemies then
            for _, npc in ipairs(GetEnemies()) do
                local npcRoot = npc:IsA("Model")
                    and npc:FindFirstChild("HumanoidRootPart")

                if npcRoot and not npcRoot.Anchored then
                    pcall(function()
                        npcRoot.Anchored = true
                    end)
                end
            end
        end

        task.wait(0.3)
    end
end)

-- Reaplica el estado del personaje cuando respawnea.
Connect(Player.CharacterAdded, function(character)
    task.wait(0.5)

    local humanoid = character:FindFirstChildOfClass("Humanoid")

    if humanoid then
        RememberHumanoid(humanoid)

        if State.SpeedEnabled then
            humanoid.WalkSpeed = State.Speed
        end

        if State.JumpEnabled then
            humanoid.UseJumpPower = true
            humanoid.JumpPower = State.Jump
        end

        if State.Fullbright then
            Lighting.Brightness = 3
            Lighting.ClockTime = 14
            Lighting.FogEnd = 100000
            Lighting.GlobalShadows = false
        end
    end

    if State.ESP then
        RefreshAllESP()
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
    State.EnemyESP = false

    for _, connection in ipairs(State.Connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end

    table.clear(State.Connections)

    RestoreCollisions()
    RestoreLighting()
    ClearEnemyESP()

    -- Soltar cualquier NPC anclado por el modo congelar.
    for _, npc in ipairs(GetEnemies()) do
        local npcRoot = npc:IsA("Model")
            and npc:FindFirstChild("HumanoidRootPart")

        if npcRoot then
            pcall(function()
                npcRoot.Anchored = false
            end)
        end
    end

    pcall(function()
        VisualFolder:Destroy()
    end)

    -- Restaurar el namecall original si enganchamos algo.
    if OriginalNamecall then
        pcall(function()
            hookmetamethod(game, "__namecall", OriginalNamecall)
        end)

        OriginalNamecall = nil
    end

    pcall(function()
        Window:Unload()
    end)

    if Env.VANTA_BI2 == State then
        Env.VANTA_BI2 = nil
    end

    print("[VANTA] Funciones detenidas y entorno restaurado.")
end

Notify(
    "VANTA cargado",
    "PlaceId " .. tostring(game.PlaceId)
        .. " | Hooks: " .. (HookAvailable and "sí" or "no")
)

Safe("Diagnóstico inicial", RunDiagnostics)

return State
