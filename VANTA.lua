--[[
    VANTA | BREAK IN 2
    Executor + Rayfield Gen2

    REGLA ÚNICA
    Ningún remoto se manda y se reza. Cada acción hace:
        1. dispara
        2. verifica en el cliente que pasó DE VERDAD
        3. si no pasó, reintenta por otra vía o lo fuerza localmente
        4. informa qué ocurrió, no qué se intentó

    Lo que es local (movimiento, noclip, luz, ESP, daño visual) no se pide:
    se escribe en la propiedad cada frame. El servidor no lo puede rechazar.

    Lo que es remoto (objetos, cura, entrenamiento, golpes) se verifica contra
    el estado real del cliente: mochila, vida, stat, Humanoid del NPC.

    PlaceIds
    - 13864667823  historia
    - 14775231477  lobby privado
    - 13864661000  lobby
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
local Clock = os.clock

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
    HealAmount = 25,
    AutoAttack = false,
    ESP = false,

    SpeedEnabled = false,
    JumpEnabled = false,
    InfJump = false,
    Noclip = false,
    Fullbright = false,

    Speed = 32,
    Jump = 75,
    OriginalSpeed = 16,
    OriginalJump = 50,
    OriginalUseJumpPower = true,

    AttackDamage = 65,
    AttackBurst = 4,
    AttackRadius = 150,
    AttackInterval = 0.5,
    HealInterval = 1.5,
    TrainAmount = 5,

    SelectedItem = "Golden Apple",
    SelectedPlayer = "",

    Connections = {},
    ESPObjects = {},
    CollisionCache = {},
    HumanoidCache = setmetatable({}, {__mode = "k"}),
    RemoteCache = {},

    Stats = {
        Executed = 0,
        Failed = 0,
        Retries = 0,
        Dropped = 0,
    },

    -- Lo que el script aprende del servidor real durante la sesión.
    -- Vive en getgenv para que sobreviva a recargas sin re-aprender.
    Learned = Env.VANTA_BI2_LEARNED or {},

    Errors = 0,
    LastError = "Ninguno",
}

Env.VANTA_BI2_LEARNED = State.Learned

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

local function GetBackpack()
    return Player:FindFirstChildOfClass("Backpack")
end

local function ToolName(item)
    return (tostring(item):gsub("%s", ""))
end

local function Alive()
    local humanoid = GetHumanoid()

    return humanoid ~= nil and humanoid.Health > 0
end

-- Espera a que una condición se cumpla. Es la pieza que convierte
-- "envié una petición" en "esto ocurrió".
local function Await(label, predicate, timeout, interval)
    timeout = timeout or 1.5
    interval = math.max(interval or 0.05, 0.02)

    local started = Clock()
    local spins = 0
    local maxSpins = 200

    repeat
        local ok, value = pcall(predicate)

        if ok and value then
            return true, value
        end

        spins += 1
        task.wait(interval)
    until Clock() - started >= timeout or spins >= maxSpins

    return false
end

-- ============================================================
-- RAYFIELD GEN2
-- ============================================================

local okLibrary, Rayfield = pcall(function()
    return loadstring(game:HttpGet("https://sirius.menu/gen2"))()
end)

if not okLibrary or not Rayfield then
    State.Running = false
    warn("[VANTA] No se pudo cargar Rayfield Gen2:", Rayfield)
    return
end

local okWindow, Window = pcall(function()
    return Rayfield:CreateWindow({
        name = "VANTA | BREAK IN 2",
        subtitle = "Ejecuta · verifica · informa",
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

-- Informe uniforme: nunca dice "enviado", dice qué ocurrió.
local function Report(title, executed, detail)
    if executed then
        State.Stats.Executed += 1
        Notify(title, "✔ " .. tostring(detail))
    else
        State.Stats.Failed += 1
        Notify(title, "✖ " .. tostring(detail))
    end

    return executed
end

-- ============================================================
-- HOOK: SEMI GODMODE / ANTI-SLIP
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

                    if State.AntiSlip
                        and type(self) == "userdata"
                        and self:IsA("RemoteEvent")
                        and self.Name == "IceSlip"
                    then
                        State.Stats.Dropped += 1
                        return nil
                    end

                    if State.SemiGod
                        and type(self) == "userdata"
                        and self:IsA("RemoteEvent")
                        and self.Name == "Energy"
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
-- CAPA DE REMOTOS
-- ============================================================

-- Presupuesto de paquetes: los reintentos de verificación no pueden
-- convertirse en un flood que te saque de la partida.
local Budget = {
    Window = 1,
    Max = 60,
    Count = 0,
    Started = Clock(),
}

local function BudgetAllows()
    local now = Clock()

    if now - Budget.Started >= Budget.Window then
        Budget.Started = now
        Budget.Count = 0
    end

    if Budget.Count >= Budget.Max then
        State.Stats.Dropped += 1
        return false
    end

    Budget.Count += 1
    return true
end

local function ResolveRemote(folderName, remoteName)
    local key = folderName .. "." .. remoteName
    local cached = State.RemoteCache[key]

    if cached and cached.Parent then
        return cached
    end

    local folder = ReplicatedStorage:FindFirstChild(folderName)

    if not folder then
        return nil, "falta ReplicatedStorage." .. folderName
    end

    local remote = folder:FindFirstChild(remoteName)

    if not remote or not remote:IsA("RemoteEvent") then
        return nil, "falta " .. key
    end

    State.RemoteCache[key] = remote

    return remote
end

-- Dispara una vez. Devuelve ok, motivo.
local function Emit(folderName, remoteName, ...)
    local remote, reason = ResolveRemote(folderName, remoteName)

    if not remote then
        return false, reason
    end

    if not BudgetAllows() then
        return false, "presupuesto de paquetes agotado"
    end

    local args = table.pack(...)

    local ok, err = pcall(function()
        remote:FireServer(table.unpack(args, 1, args.n))
    end)

    if not ok then
        return false, tostring(err)
    end

    return true
end

local function Evt(remoteName, ...)
    return Emit("Events", remoteName, ...)
end

-- ============================================================
-- FIRMAS APRENDIDAS
-- ============================================================
-- El servidor decide. Cuando una variante de argumentos funciona, se anota
-- con la clave de la acción. La siguiente sesión empieza por la que ganó.

local function SignatureKey(action)
    return "sig:" .. action
end

local function GetSignature(action)
    return State.Learned[SignatureKey(action)]
end

local function SetSignature(action, shape)
    local key = SignatureKey(action)

    if State.Learned[key] ~= shape then
        State.Learned[key] = shape
        print("[VANTA] firma aprendida " .. action .. " -> " .. tostring(shape))
    end
end

-- Ejecuta una lista de variantes y devuelve la primera que cumpla `verify`.
-- Mide antes/después para no creerse la primera respuesta.
local function TryVariants(action, variants, verify, timeout)
    local learned = GetSignature(action)
    local ordered = {}

    if learned then
        for _, variant in ipairs(variants) do
            if variant.label == learned then
                table.insert(ordered, variant)
            end
        end
    end

    for _, variant in ipairs(variants) do
        if variant.label ~= learned then
            table.insert(ordered, variant)
        end
    end

    for index, variant in ipairs(ordered) do
        local okFire, reason = variant.fire()

        if not okFire and variant.fatal then
            return false, reason
        end

        if Await(action, verify, timeout or 1.0) then
            SetSignature(action, variant.label)
            return true, variant.detail or variant.label, index
        end

        if index < #ordered then
            State.Stats.Retries += 1
        end
    end

    return false, nil
end

-- ============================================================
-- DETECTORES
-- ============================================================

local function FindToolIn(item)
    local name = ToolName(item)
    local backpack = GetBackpack()
    local character = GetCharacter()

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

local function CountTools()
    local count = 0
    local backpack = GetBackpack()

    if backpack then
        for _, child in ipairs(backpack:GetChildren()) do
            if child:IsA("Tool") then
                count += 1
            end
        end
    end

    return count
end

local function ReadHealth()
    local humanoid = GetHumanoid()

    return humanoid and humanoid.Health or 0
end

local function ReadMaxHealth()
    local humanoid = GetHumanoid()

    return humanoid and humanoid.MaxHealth or 100
end

-- Busca un stat legible en el cliente. El juego lo expone de formas
-- distintas según la versión, así que se prueban todas y se memoriza
-- la primera que funciona: recorrer el árbol entero en cada tick es caro.

local StatSource = {}

local function LookupStat(statName)
    local wanted = statName:lower()

    -- 1. La ruta que usan los scripts del juego para el HUD.
    local playerGui = Player:FindFirstChildOfClass("PlayerGui")

    if playerGui then
        local note = playerGui:FindFirstChild("Assets")

        if note then
            for _, object in ipairs(note:GetDescendants()) do
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

    -- 2. Valores numéricos colgados del jugador.
    for _, object in ipairs(Player:GetDescendants()) do
        if (object:IsA("NumberValue") or object:IsA("IntValue"))
            and object.Name:lower():find(wanted, 1, true)
        then
            return object.Value, object
        end
    end

    -- 3. Cualquier texto del HUD que mencione el stat.
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

local function ReadStat(statName)
    local cached = StatSource[statName]

    -- La fuente se comprueba antes de usarse: si el HUD se reconstruyó,
    -- se vuelve a buscar una vez y se actualiza la memoria.
    if cached and cached.Parent then
        local value

        if cached:IsA("TextLabel") then
            local number = cached.Text:match("(%d+%.?%d*)")
            value = number and tonumber(number)
        else
            value = cached.Value
        end

        if value then
            return value, cached:GetFullName()
        end
    end

    local value, source = LookupStat(statName)

    if value and source then
        StatSource[statName] = source
        return value, source:GetFullName()
    end

    StatSource[statName] = nil

    return nil
end

-- Permitir que la sonda invalide la memoria si el juego cambió el HUD.
local function ForgetStatSources()
    table.clear(StatSource)
end

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

local function GetEnemyHumanoid(npc)
    if not npc then
        return nil
    end

    if npc:IsA("Humanoid") then
        return npc
    end

    return npc:FindFirstChildOfClass("Humanoid")
end

local function IsEnemyAlive(npc)
    local humanoid = GetEnemyHumanoid(npc)

    if humanoid then
        return humanoid.Health > 0
    end

    return true
end

local function FindPlayer(query)
    if type(query) ~= "string" then
        return nil
    end

    query = query:lower():match("^%s*(.-)%s*$")

    if query == "" then
        return nil
    end

    for _, target in ipairs(Players:GetPlayers()) do
        if target ~= Player
            and (target.Name:lower() == query or target.DisplayName:lower() == query)
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

-- ============================================================
-- EJECUTORES VERIFICADOS
-- ============================================================
-- Cada uno devuelve: ejecutado (bool), detalle (string).
-- Ninguno devuelve "enviado". Devuelven lo que ocurrió.

-- Nombre visible -> nombre de herramienta que espera el vending.
-- "Crowbar 1" produce Crowbar1; el dorado es Crowbar3.
local Weapons = {
    ["Crowbar 1"] = "Crowbar1",
    ["Crowbar 2"] = "Crowbar2",
    ["Diamond Crowbar"] = "Crowbar3",
    ["Bat"] = "Bat",
    ["Pitchfork"] = "Pitchfork",
    ["Hammer"] = "Hammer",
    ["Wrench"] = "Wrench",
    ["Broom"] = "Broom",
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

-- OBJETOS ----------------------------------------------------
-- Vía 1: GiveTool(nombre). Vía 2: Vending(...) para armas y armadura.
-- Se verifica leyendo la mochila. Si la vía 1 no deja el ítem, se usa la 2.

local function ExecGiveItem(item)
    if type(item) ~= "string" or item == "" then
        return false, "ítem inválido"
    end

    -- Si ya lo tienes, no se pide: se ejecuta sacándolo al personaje.
    local existing = FindToolIn(item)

    if existing then
        local character = GetCharacter()

        if character and existing.Parent ~= character then
            pcall(function()
                existing.Parent = character
            end)
        end

        return true, item .. " ya estaba; equipado"
    end

    local name = ToolName(item)
    local variants = {
        {
            label = "GiveTool(sin espacios)",
            fire = function()
                return Evt("GiveTool", name)
            end,
        },
        {
            label = "GiveTool(con espacios)",
            fire = function()
                return Evt("GiveTool", item)
            end,
        },
    }

    -- El vending es la vía real de armas y armadura.
    if item == "Armor" then
        table.insert(variants, 1, {
            label = "Vending(Armor2)",
            fire = function()
                return Evt("Vending", 3, "Armor2", "Armor", Player.Name, 1)
            end,
        })
    elseif Weapons[item] then
        table.insert(variants, 1, {
            label = "Vending(" .. Weapons[item] .. ")",
            fire = function()
                return Evt("Vending", 3, Weapons[item], "Weapons", Player.Name, 1)
            end,
        })
    end

    local ok, label = TryVariants(item, variants, function()
        return FindToolIn(item) ~= nil
    end, 1.0)

    if ok then
        -- Equipar es parte de "dar el objeto", no un extra.
        local tool = FindToolIn(item)
        local character = GetCharacter()

        if tool and character and tool.Parent ~= character then
            pcall(function()
                tool.Parent = character
            end)
        end

        return true, string.format("%s en mochila (%s)", item, tostring(label))
    end

    return false, item .. " no llegó por ninguna de " .. #variants .. " vías"
end

-- CURA -------------------------------------------------------
-- La vida es la prueba. Si Energy no mueve la barra, se sube de ítem.

-- El remoto Energy puede venir con firma (delta, ítem) o (delta, bool, bool)
-- según la versión. Se prueban las dos y gana la que mueva la barra.
local HealLadder = {
    {item = "Pizza", amount = 25},
    {item = "Gold Pizza", amount = 50},
    {item = "Rainbow Pizza", amount = 75},
}

local function ExecHeal(amount)
    if not Alive() then
        return false, "sin personaje vivo"
    end

    amount = tonumber(amount) or 25

    local before = ReadHealth()
    local maxHealth = ReadMaxHealth()

    if before >= maxHealth then
        return true, "ya estaba a " .. math.floor(before) .. " HP"
    end

    for _, step in ipairs(HealLadder) do
        local healFor = math.max(amount, step.amount)

        -- Solo pide el ítem si no lo tiene: pedirlo cada tick es lo que
        -- hace que el servidor te trate como flood.
        if not FindToolIn(step.item) then
            Evt("GiveTool", ToolName(step.item))
            Await(step.item, function()
                return FindToolIn(step.item) ~= nil
            end, 0.8)
        end

        local base = ReadHealth()

        local ok, label = TryVariants("heal", {
            {
                label = "Energy(delta, ítem)",
                detail = step.item,
                fire = function()
                    return Evt("Energy", healFor, step.item)
                end,
            },
            {
                label = "Energy(delta, bool, bool)",
                detail = step.item .. " (forma antigua)",
                fire = function()
                    return Evt("Energy", healFor, false, false)
                end,
            },
        }, function()
            return ReadHealth() > base + 0.5
        end, 1.2)

        if ok then
            return true, string.format(
                "+%d HP con %s (%d → %d)",
                math.floor(ReadHealth() - before),
                tostring(label),
                math.floor(before),
                math.floor(ReadHealth())
            )
        end
    end

    return false, "Energy no movió la vida con ningún ítem ni firma"
end

-- CURAR A TODOS ----------------------------------------------
-- Manzana dorada + HealTheNoobs. Se verifica con la vida de los NPC
-- aliados si el juego los expone; si no, se verifica que la manzana
-- se haya equipado, que es la precondición real del remoto.

local function ExecHealEveryone()
    if not Alive() then
        return false, "sin personaje vivo"
    end

    local humanoid = GetHumanoid()

    if humanoid then
        pcall(function()
            humanoid:UnequipTools()
        end)

        task.wait(0.15)
    end

    local backpack = GetBackpack()

    if not backpack then
        return false, "sin mochila"
    end

    local apple = backpack:FindFirstChild("GoldenApple")

    if not apple then
        Evt("GiveTool", "GoldenApple")

        local got = Await("apple", function()
            local bag = GetBackpack()

            return bag and bag:FindFirstChild("GoldenApple") ~= nil
        end, 2.0)

        if not got then
            return false, "la manzana dorada no llegó"
        end

        backpack = GetBackpack()
        apple = backpack and backpack:FindFirstChild("GoldenApple")
    end

    if not apple then
        return false, "la manzana no está en la mochila"
    end

    local character = GetCharacter()
    local equipped = false

    if character then
        pcall(function()
            apple.Parent = character
        end)

        -- Parent es la prueba directa; FindFirstChild puede tardar un frame
        -- en reflejar el cambio, así que se acepta cualquiera de las dos.
        equipped = Await("equip", function()
            return apple.Parent == character
                or character:FindFirstChild("GoldenApple") ~= nil
        end, 1.0)
    end

    if not equipped then
        return false, "no se pudo equipar la manzana"
    end

    task.wait(0.25)

    if not Evt("HealTheNoobs") then
        return false, "HealTheNoobs no existe en este lugar"
    end

    -- Verificación real si el juego expone NPC aliados.
    local healed = Await("allies", function()
        for _, name in ipairs({"Noobs", "Allies", "Survivors", "Players"}) do
            local folder = Workspace:FindFirstChild(name)

            if folder then
                for _, npc in ipairs(folder:GetChildren()) do
                    local npcHumanoid = GetEnemyHumanoid(npc)

                    if npcHumanoid and npcHumanoid.Health < npcHumanoid.MaxHealth then
                        return false
                    end
                end

                return true
            end
        end

        return nil
    end, 1.5)

    if healed then
        return true, "grupo curado (verificado en aliados)"
    end

    return true, "manzana equipada y HealTheNoobs disparado"
end

-- ENTRENAMIENTO ----------------------------------------------
-- Se verifica contra el stat si el cliente lo expone. Si no lo expone,
-- se reintenta hasta agotar el presupuesto y se informa sin adornos.

local function ExecTrain(stat, reps)
    reps = math.clamp(tonumber(reps) or 5, 1, 100)

    local before = ReadStat(stat)
    local done = 0

    for _ = 1, reps do
        if not State.Running then
            break
        end

        if not Evt("RainbowWhatStat", stat) then
            return false, "RainbowWhatStat no existe en este lugar"
        end

        done += 1
        task.wait(before and 0.25 or 0.2)
    end

    if not before then
        return true, string.format(
            "%s: %d copias (sin stat legible para verificar)",
            stat,
            done
        )
    end

    local after = ReadStat(stat)

    if after and after > before then
        return true, string.format(
            "%s %d → %d (+%d) en %d envíos",
            stat,
            math.floor(before),
            math.floor(after),
            math.floor(after - before),
            done
        )
    end

    -- El nombre del stat puede ir en otro formato. Se prueban variantes
    -- con la forma exacta que documenta el juego antes de rendirse.
    local variants = {
        {label = stat, arg = stat},
        {label = stat:lower(), arg = stat:lower()},
        {label = stat:upper(), arg = stat:upper()},
    }


    for _, variant in ipairs(variants) do
        if variant.arg ~= stat then
            State.Stats.Retries += 1
            local base = ReadStat(stat)

            Evt("RainbowWhatStat", variant.arg)
            task.wait(0.4)

            local now = ReadStat(stat)

            if now and base and now > base then
                SetSignature("train", variant.label)
                return true, string.format(
                    "%s subió con variante %s (%d → %d)",
                    stat,
                    variant.label,
                    math.floor(base),
                    math.floor(now)
                )
            end
        end
    end

    return false, string.format(
        "%s no subió (%d copias) — el servidor lo ignora o el stat no es legible",
        stat,
        done
    )
end

-- COMBATE ----------------------------------------------------
-- Tres formas de argumento. Se prueban hasta que el Humanoid baje.

local function ExecAttackOne(npc, damage, burst)
    local humanoid = GetEnemyHumanoid(npc)

    if not humanoid or humanoid.Health <= 0 then
        return false, "sin vida", false
    end

    local root = GetRoot()

    if root then
        local part = GetEnemyRoot(npc)

        if part and (part.Position - root.Position).Magnitude > State.AttackRadius then
            return false, "fuera de radio", false
        end
    end

    local before = humanoid.Health
    local part = GetEnemyRoot(npc)
    local hits = math.clamp(burst, 1, 10)

    local function volley(...)
        local args = table.pack(...)

        for _ = 1, hits do
            Evt("HitBadguy", table.unpack(args, 1, args.n))
        end
    end

    local variants = {
        {
            label = "HitBadguy(modelo, daño, 4)",
            fire = function()
                volley(npc, damage, 4)
                return true
            end,
        },
    }

    -- Algunas versiones quieren la parte raíz; otras ignoran el tercer arg.
    if part then
        table.insert(variants, {
            label = "HitBadguy(parte, daño, 4)",
            fire = function()
                volley(part, damage, 4)
                return true
            end,
        })
    end

    table.insert(variants, {
        label = "HitBadguy(modelo, daño)",
        fire = function()
            volley(npc, damage)
            return true
        end,
    })

    local ok, label = TryVariants("hit", variants, function()
        return humanoid.Health < before
    end, 0.5)

    if ok then
        return true, string.format(
            "%d → %d (%s)",
            math.floor(before),
            math.floor(humanoid.Health),
            tostring(label)
        ), false
    end

    -- Última vía: si el Humanoid está replicado en el cliente, se escribe.
    -- Se marca como local para que el contador de caídos no te mienta.
    if humanoid.Health > 0 then
        pcall(function()
            humanoid.Health = 0
        end)

        if humanoid.Health < before then
            return true, string.format("%d → 0 (local)", math.floor(before)), true
        end
    end

    return false, "el remoto no bajó la vida y el cliente no la aceptó", false
end

local function ExecAttackAll(damage, burst, silent)
    local total = 0
    local killed = 0
    local local_only = 0
    local failed = 0

    for _, npc in ipairs(GetEnemies()) do
        if not State.Running then
            break
        end

        if IsEnemyAlive(npc) then
            local ok, _, isLocal = ExecAttackOne(npc, damage, burst)

            if ok then
                total += 1

                if isLocal then
                    local_only += 1
                elseif not IsEnemyAlive(npc) then
                    killed += 1
                end
            else
                failed += 1
            end
        end
    end

    local detail = string.format("%d dañados, %d caídos", total, killed)

    if local_only > 0 then
        detail = detail .. string.format(", %d solo en cliente", local_only)
    end

    if failed > 0 then
        detail = detail .. string.format(", %d sin efecto", failed)
    end

    -- Solo cuenta como ejecutado lo que el servidor confirmó con vida bajada.
    local verified = killed > 0 or (total > 0 and local_only == 0)

    if not silent then
        Report("Combate", verified, detail)
    end

    return verified, detail
end

-- ============================================================
-- PROPIEDADES LOCALES: EJECUTAR, NO PEDIR
-- ============================================================
-- RunService.Stepped reescribe cada frame. Sin remoto, sin rechazo.

local function CaptureOriginals(humanoid)
    if not humanoid then
        return
    end

    if State.HumanoidCache[humanoid] then
        return
    end

    State.HumanoidCache[humanoid] = true
    State.OriginalSpeed = humanoid.WalkSpeed
    State.OriginalJump = humanoid.JumpPower
    State.OriginalUseJumpPower = humanoid.UseJumpPower
end

local function ApplyLocalState()
    local humanoid = GetHumanoid()
    local character = GetCharacter()

    if humanoid then
        CaptureOriginals(humanoid)

        if State.SpeedEnabled then
            if humanoid.WalkSpeed ~= State.Speed then
                humanoid.WalkSpeed = State.Speed
            end
        elseif humanoid.WalkSpeed ~= State.OriginalSpeed then
            humanoid.WalkSpeed = State.OriginalSpeed
        end

        if State.JumpEnabled then
            if not humanoid.UseJumpPower then
                humanoid.UseJumpPower = true
            end

            if humanoid.JumpPower ~= State.Jump then
                humanoid.JumpPower = State.Jump
            end
        elseif humanoid.JumpPower ~= State.OriginalJump then
            humanoid.JumpPower = State.OriginalJump
            humanoid.UseJumpPower = State.OriginalUseJumpPower
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

        if humanoid then
            pcall(function()
                humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, true)
            end)
        end
    elseif not State.Noclip then
        for part, original in pairs(State.CollisionCache) do
            if part and part.Parent and part.CanCollide ~= original then
                pcall(function()
                    part.CanCollide = original
                end)
            end
        end
    end

    if State.Fullbright then
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
    end
end

Connect(RunService.Stepped, function()
    if State.Running then
        ApplyLocalState()
    end
end)

-- Salto infinito: una sola conexión, siempre activa, controlada por el flag.
Connect(UserInputService.JumpRequest, function()
    if not State.Running or not State.InfJump then
        return
    end

    local humanoid = GetHumanoid()

    if humanoid and humanoid.Health > 0 then
        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end)

-- ============================================================
-- ESP
-- ============================================================

local VisualFolder = Instance.new("Folder")
VisualFolder.Name = "VANTA_BI2"
VisualFolder.Parent = Workspace

local function RemoveESP(target)
    local object = State.ESPObjects[target]

    if object then
        pcall(function()
            object:Destroy()
        end)

        State.ESPObjects[target] = nil
    end
end

local function ApplyESP(target)
    RemoveESP(target)

    if not State.Running or not State.ESP or target == Player then
        return
    end

    if not target.Character then
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
    highlight.Parent = VisualFolder

    State.ESPObjects[target] = highlight
end

local function RefreshESP()
    for _, target in ipairs(Players:GetPlayers()) do
        ApplyESP(target)
    end
end

local function TrackPlayer(target)
    if target == Player then
        return
    end

    Connect(target.CharacterAdded, function()
        if State.Running and State.ESP then
            ApplyESP(target)
        end
    end)

    Connect(target.CharacterRemoving, function()
        RemoveESP(target)
    end)

    if State.ESP then
        ApplyESP(target)
    end
end

for _, target in ipairs(Players:GetPlayers()) do
    TrackPlayer(target)
end

Connect(Players.PlayerAdded, TrackPlayer)
Connect(Players.PlayerRemoving, RemoveESP)

-- ============================================================
-- TELEPORT
-- ============================================================

local function ExecTeleportToPlayer()
    local root = GetRoot()

    if not root then
        return false, "sin personaje"
    end

    if State.SelectedPlayer == "" then
        return false, "escribe un nombre primero"
    end

    local target = FindPlayer(State.SelectedPlayer)

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

    -- Verificación: el root tiene que estar donde lo pusimos.
    local ok = Await("tp", function()
        return (root.Position - destination.Position).Magnitude < 12
    end, 0.6)

    if ok then
        return true, "junto a " .. target.Name
    end

    return false, "el servidor devolvió el personaje (anti-teleport)"
end

-- ============================================================
-- LOBBY
-- ============================================================

local RoleTools = {
    Hacker = {arg = "Phone", tool = "Phone"},
    Nerd = {arg = "Book", tool = "Book"},
}

local function ExecLobbyRole(roleName)
    local role = RoleTools[roleName]

    if not role then
        return false, "rol desconocido"
    end

    -- Verificación directa: si ya tienes la herramienta del rol, ya lo eres.
    if FindToolIn(role.tool) then
        return true, "ya tienes " .. roleName
    end

    local ok, label = TryVariants("role", {
        {
            label = "OutsideRole(ítem, true, false)",
            fire = function()
                return Emit("RemoteEvents", "OutsideRole", role.arg, true, false)
            end,
        },
        {
            label = "OutsideRole(ítem)",
            fire = function()
                return Emit("RemoteEvents", "OutsideRole", role.arg)
            end,
        },
    }, function()
        return FindToolIn(role.tool) ~= nil
    end, 1.5)

    if ok then
        return true, "rol " .. roleName .. " activo (" .. tostring(label) .. ")"
    end

    return false, "el lobby no entregó " .. roleName
        .. " (¿gamepass o lobby equivocado?)"
end

-- ============================================================
-- UI
-- ============================================================

local TabMain = Window:CreateTab({name = "Inicio"})
local TabSurvival = Window:CreateTab({name = "Supervivencia"})
local TabItems = Window:CreateTab({name = "Objetos"})
local TabCombat = Window:CreateTab({name = "Combate"})
local TabMove = Window:CreateTab({name = "Movimiento"})
local TabVisuals = Window:CreateTab({name = "Visuales"})
local TabLobby = Window:CreateTab({name = "Lobby"})
local TabDiag = Window:CreateTab({name = "Diagnóstico"})

-- Los botones nunca bloquean la UI: cada ejecución corre en su hilo
-- y notifica el resultado real cuando termina.
local function Async(title, executor)
    return function()
        task.spawn(function()
            Safe(title, function()
                local ok, detail = executor()
                Report(title, ok, detail)
            end)
        end)
    end
end

TabMain:CreateText({
    name = "VANTA | BREAK IN 2",
    text = "Cada acción dispara, verifica y reintenta por otra vía. "
        .. "Si no ocurre, lo dice.",
})

TabMain:CreateText({
    name = "Hooks",
    text = HookAvailable
        and "Disponibles: semi godmode y anti-slip activos."
        or "Este executor no expone hookmetamethod: semi godmode y anti-slip quedan fuera.",
})

TabMain:CreateButton({
    name = "Kit completo (verificado)",
    callback = Async("Kit", function()
        local done = 0
        local total = 0

        for _, item in ipairs({"Armor", "Golden Apple", "Med Kit", "Crowbar 2"}) do
            total += 1

            if ExecGiveItem(item) then
                done += 1
            end
        end

        for _ = 1, 6 do
            ExecGiveItem("Gold Pizza")
        end

        return done > 0, string.format(
            "%d/%d objetos del kit en la mochila",
            done,
            total
        )
    end),
})

TabMain:CreateButton({
    name = "Entrenar fuerza y velocidad",
    callback = Async("Entrenamiento", function()
        local okA, detailA = ExecTrain("Strength", State.TrainAmount)
        local okB, detailB = ExecTrain("Speed", State.TrainAmount)

        return okA or okB, tostring(detailA) .. " | " .. tostring(detailB)
    end),
})

-- SUPERVIVENCIA

TabSurvival:CreateSection({name = "Protección"})

TabSurvival:CreateToggle({
    name = "Semi godmode",
    description = HookAvailable
        and "Anula el daño negativo de Energy antes de que salga."
        or "Requiere hookmetamethod.",
    flag = "semiGod",
    value = false,
    callback = function(value)
        State.SemiGod = value and HookAvailable

        if value and not HookAvailable then
            Notify("Semi godmode", "✖ este executor no tiene hooks")
        end
    end,
})

TabSurvival:CreateToggle({
    name = "Anti-slip",
    description = HookAvailable
        and "Corta el remoto IceSlip completo."
        or "Requiere hookmetamethod.",
    flag = "antiSlip",
    value = false,
    callback = function(value)
        State.AntiSlip = value and HookAvailable

        if value and not HookAvailable then
            Notify("Anti-slip", "✖ este executor no tiene hooks")
        end
    end,
})

TabSurvival:CreateSection({name = "Curación"})

TabSurvival:CreateButton({
    name = "Curarme ahora",
    callback = Async("Curación", function()
        return ExecHeal(State.HealAmount)
    end),
})

TabSurvival:CreateSlider({
    name = "Curación por uso",
    range = {10, 150},
    increment = 5,
    value = 25,
    suffix = " HP",
    flag = "healAmount",
    callback = function(value)
        State.HealAmount = value
    end,
})

TabSurvival:CreateToggle({
    name = "Auto-curación",
    description = "Solo actúa si estás herido. Verifica cada cura.",
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
    name = "Curar a todos",
    callback = Async("Curar a todos", ExecHealEveryone),
})

TabSurvival:CreateSection({name = "Entrenamiento"})

TabSurvival:CreateSlider({
    name = "Repeticiones",
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
    callback = Async("Fuerza", function()
        return ExecTrain("Strength", State.TrainAmount)
    end),
})

TabSurvival:CreateButton({
    name = "Entrenar velocidad",
    callback = Async("Velocidad", function()
        return ExecTrain("Speed", State.TrainAmount)
    end),
})

-- OBJETOS

TabItems:CreateDropdown({
    name = "Objeto",
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
    name = "Dar y equipar seleccionado",
    callback = Async("Objeto", function()
        return ExecGiveItem(State.SelectedItem)
    end),
})

TabItems:CreateButton({
    name = "Dar todos los objetos",
    callback = Async("Objetos", function()
        local done, failed = 0, 0

        for _, item in ipairs(Items) do
            if not State.Running then
                break
            end

            local ok = ExecGiveItem(item)

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
    end),
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
}) do
    local current = item

    TabItems:CreateButton({
        name = current,
        callback = Async(current, function()
            return ExecGiveItem(current)
        end),
    })
end

-- COMBATE

TabCombat:CreateSlider({
    name = "Radio",
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
    name = "Daño",
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
    name = "Atacar NPC cercanos",
    callback = Async("Combate", function()
        return ExecAttackAll(
            State.AttackDamage,
            State.AttackBurst,
            true
        )
    end),
})

TabCombat:CreateToggle({
    name = "Auto ataque",
    flag = "autoAttack",
    value = false,
    callback = function(value)
        State.AutoAttack = value
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
    name = "Velocidad",
    description = "Se reescribe cada frame. El servidor no lo puede rechazar.",
    flag = "speedEnabled",
    value = false,
    callback = function(value)
        State.SpeedEnabled = value

        if not value and State.OriginalSpeed then
            local humanoid = GetHumanoid()

            if humanoid then
                humanoid.WalkSpeed = State.OriginalSpeed
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
    name = "Salto",
    flag = "jumpEnabled",
    value = false,
    callback = function(value)
        State.JumpEnabled = value

        if not value then
            local humanoid = GetHumanoid()

            if humanoid then
                humanoid.JumpPower = State.OriginalJump
                humanoid.UseJumpPower = State.OriginalUseJumpPower
            end
        end
    end,
})

TabMove:CreateToggle({
    name = "Salto infinito",
    flag = "infJump",
    value = false,
    callback = function(value)
        State.InfJump = value
    end,
})

TabMove:CreateToggle({
    name = "Noclip",
    description = "Colisiones a false cada frame y restauración al apagar.",
    flag = "noclip",
    value = false,
    callback = function(value)
        State.Noclip = value
    end,
})

TabMove:CreateInput({
    name = "Jugador",
    placeholder = "Nombre exacto o parcial",
    value = "",
    flag = "targetPlayer",
    callback = function(value)
        State.SelectedPlayer = tostring(value or "")
    end,
})

TabMove:CreateButton({
    name = "Teleport al jugador",
    callback = Async("Teleport", ExecTeleportToPlayer),
})

-- VISUALES

TabVisuals:CreateToggle({
    name = "ESP jugadores",
    flag = "playerESP",
    value = false,
    callback = function(value)
        State.ESP = value
        RefreshESP()
    end,
})

TabVisuals:CreateToggle({
    name = "Fullbright",
    flag = "fullbright",
    value = false,
    callback = function(value)
        State.Fullbright = value

        if not value then
            for property, original in pairs(OriginalLighting) do
                pcall(function()
                    Lighting[property] = original
                end)
            end
        end
    end,
})

-- LOBBY

TabLobby:CreateText({
    name = "Roles",
    text = "Solo en el lobby (14775231477 / 13864661000), antes de empezar.",
})

TabLobby:CreateButton({
    name = "Rol Hacker",
    callback = Async("Hacker", function()
        return ExecLobbyRole("Hacker")
    end),
})

TabLobby:CreateButton({
    name = "Rol Nerd",
    callback = Async("Nerd", function()
        return ExecLobbyRole("Nerd")
    end),
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
    {"RemoteEvents", "OutsideRole"},
}

TabDiag:CreateText({
    name = "Cómo leer esto",
    text = "✔ = ocurrió y se verificó. ✖ = no ocurrió y por qué. "
        .. "Los contadores son de acciones, no de paquetes.",
})

TabDiag:CreateButton({
    name = "Comprobar remotos",
    callback = function()
        local found = 0

        print("========== VANTA REMOTOS ==========")
        print("PlaceId:", game.PlaceId)

        for _, check in ipairs(RemoteChecks) do
            local remote = ResolveRemote(check[1], check[2])

            if remote then
                found += 1
                print("[OK] " .. check[1] .. "." .. check[2])
            else
                warn("[FALTA] " .. check[1] .. "." .. check[2])
            end
        end

        print("===================================")

        Notify(
            "Remotos",
            found == #RemoteChecks
                and "✔ los " .. found .. " están presentes"
                or "✖ faltan " .. (#RemoteChecks - found) .. " de " .. #RemoteChecks
        )
    end,
})

TabDiag:CreateButton({
    name = "Sondear firmas (descubre la forma real)",
    description = "Prueba cada variante de argumentos, mide el efecto y "
        .. "guarda la que el servidor acepta.",
    callback = function()
        task.spawn(function()
            Safe("Sonda", function()
                local lines = {}
                local function add(text)
                    table.insert(lines, text)
                    print("[SONDA] " .. text)
                end

                add("== SONDA ==")
                add("PlaceId " .. tostring(game.PlaceId))

                -- 1. Objetos: se prueba un objeto barato y se ve qué vía lo trae.
                local probeItem = "Pizza"
                local bagBefore = CountTools()
                local gotItem = ExecGiveItem(probeItem)
                local bagAfter = CountTools()

                add(string.format(
                    "objeto %s: %s (mochila %d → %d)",
                    probeItem,
                    gotItem and "aceptado" or "rechazado",
                    bagBefore,
                    bagAfter
                ))

                -- 2. Cura: se fuerza daño local antes, para tener margen real.
                local humanoid = GetHumanoid()

                if humanoid then
                    local original = humanoid.Health
                    local hurtTo = math.max(original - 40, 10)

                    pcall(function()
                        humanoid.Health = hurtTo
                    end)

                    local healed = ExecHeal(25)
                    add("cura: " .. (healed and "aceptada" or "rechazada")
                        .. string.format(" (vida %d → %d)", math.floor(hurtTo), math.floor(ReadHealth())))

                    pcall(function()
                        humanoid.Health = original
                    end)
                end

                -- 3. Entrenamiento: una copia por variante de nombre.
                ForgetStatSources()

                for _, stat in ipairs({"Strength", "Speed"}) do
                    local base = ReadStat(stat)

                    if base then
                        Evt("RainbowWhatStat", stat)
                        task.wait(0.5)
                        local now = ReadStat(stat)

                        add(string.format(
                            "entrenar %s: %s (%s → %s)",
                            stat,
                            (now and base and now > base) and "sube" or "no sube",
                            tostring(base),
                            tostring(now)
                        ))
                    else
                        add("entrenar " .. stat .. ": sin lectura local")
                    end
                end

                -- 4. Combate: una variante por forma sobre el primer NPC vivo.
                local target = GetEnemies()[1]

                if target then
                    local npcHumanoid = GetEnemyHumanoid(target)

                    if npcHumanoid then
                        local startHealth = npcHumanoid.Health
                        local ok, _, isLocal = ExecAttackOne(target, 5, 1)

                        -- Si el único camino que funcionó fue escribir la vida
                        -- en el cliente, no es el servidor aceptando: se dice.
                        local verdict = "rechazado"

                        if ok and not isLocal then
                            verdict = "aceptado por el servidor"
                        elseif ok and isLocal then
                            verdict = "solo local (el servidor no lo aceptó)"
                        end

                        add(string.format(
                            "golpe: %s (vida NPC %d → %d)",
                            verdict,
                            math.floor(startHealth),
                            math.floor(npcHumanoid.Health)
                        ))
                    end
                else
                    add("golpe: no hay NPC en el mapa para probar")
                end

                -- 5. Foto de firmas aprendidas.
                local learned = {}

                for key, value in pairs(State.Learned) do
                    table.insert(learned, key .. " = " .. tostring(value))
                end

                local readable = {}

                for _, stat in ipairs({"Strength", "Speed"}) do
                    if ReadStat(stat) then
                        table.insert(readable, stat)
                    end
                end

                add(string.format(
                    "stats legibles: %s",
                    #readable > 0 and table.concat(readable, ", ") or "ninguno"
                ))

                if #learned > 0 then
                    table.sort(learned)
                    add("firmas: " .. table.concat(learned, " ; "))
                else
                    add("firmas: ninguna todavía")
                end

                add("== FIN ==")

                Notify(
                    "Sonda",
                    string.format(
                        "%d líneas en consola | %d firmas aprendidas",
                        #lines,
                        #learned
                    )
                )
            end)
        end)
    end,
})

TabDiag:CreateButton({
    name = "Volcar ReplicatedStorage",
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
        Notify("Volcado", "✔ árbol impreso en la consola (F9)")
    end,
})

TabDiag:CreateButton({
    name = "Estado del script",
    callback = function()
        local lines = {
            "PlaceId: " .. tostring(game.PlaceId),
            "Hooks: " .. (HookAvailable and "sí" or "no"),
            "Ejecutadas: " .. State.Stats.Executed,
            "Fallidas: " .. State.Stats.Failed,
            "Reintentos: " .. State.Stats.Retries,
            "Paquetes descartados: " .. State.Stats.Dropped,
            "Errores: " .. State.Errors,
            "Último error: " .. State.LastError,
        }

        local learnedCount = 0

        for _ in pairs(State.Learned) do
            learnedCount += 1
        end

        table.insert(lines, "Firmas aprendidas: " .. learnedCount)

        print("===== VANTA ESTADO =====")

        for _, line in ipairs(lines) do
            print(line)
        end

        Notify(
            "Estado",
            string.format(
                "✔ %d | ✖ %d | reintentos %d",
                State.Stats.Executed,
                State.Stats.Failed,
                State.Stats.Retries
            )
        )
    end,
})

TabDiag:CreateButton({
    name = "Detener y restaurar",
    description = "Devuelve movimiento, colisiones, luz y el hook original.",
    callback = function()
        if State.Stop then
            State.Stop()
        end
    end,
})

-- ============================================================
-- LOOPS
-- ============================================================

-- Auto-curación: solo si estás herido, y verifica que la vida suba.
task.spawn(function()
    while State.Running do
        if State.AutoHeal then
            local humanoid = GetHumanoid()

            if humanoid and humanoid.Health > 0
                and humanoid.Health < humanoid.MaxHealth then

                Safe("AutoHeal", ExecHeal, State.HealAmount)
            end
        end

        task.wait(math.max(State.HealInterval, 0.5))
    end
end)

-- Auto-ataque: sin notificación por tick para no inundar la UI.
task.spawn(function()
    while State.Running do
        if State.AutoAttack then
            Safe("AutoAttack", ExecAttackAll, State.AttackDamage, State.AttackBurst, true)
        end

        task.wait(math.max(State.AttackInterval, 0.2))
    end
end)

-- Al respawnear se recapturan los valores originales y se reaplica lo activo.
Connect(Player.CharacterAdded, function(character)
    task.wait(0.5)

    local humanoid = character:FindFirstChildOfClass("Humanoid")

    if humanoid then
        State.HumanoidCache[humanoid] = nil
        CaptureOriginals(humanoid)
        ApplyLocalState()
    end

    if State.ESP then
        RefreshESP()
    end
end)

-- ============================================================
-- CLEANUP
-- ============================================================

State.Stop = function()
    if not State.Running then
        return
    end

    State.Running = false

    -- 1. Devolver propiedades locales al valor real del juego.
    local humanoid = GetHumanoid()

    if humanoid then
        pcall(function()
            humanoid.WalkSpeed = State.OriginalSpeed
            humanoid.JumpPower = State.OriginalJump
            humanoid.UseJumpPower = State.OriginalUseJumpPower
        end)
    end

    for part, original in pairs(State.CollisionCache) do
        if part and part.Parent then
            pcall(function()
                part.CanCollide = original
            end)
        end
    end

    table.clear(State.CollisionCache)

    for property, value in pairs(OriginalLighting) do
        pcall(function()
            Lighting[property] = value
        end)
    end

    -- 2. Espacios y ESP.
    for target in pairs(State.ESPObjects) do
        RemoveESP(target)
    end

    pcall(function()
        VisualFolder:Destroy()
    end)

    -- 3. Conexiones.
    for _, connection in ipairs(State.Connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end

    table.clear(State.Connections)

    -- 4. Hook original de vuelta.
    if OriginalNamecall then
        pcall(function()
            hookmetamethod(game, "__namecall", OriginalNamecall)
        end)

        OriginalNamecall = nil
    end

    table.clear(State.RemoteCache)

    -- 5. UI.
    pcall(function()
        Window:Unload()
    end)

    if Env.VANTA_BI2 == State then
        Env.VANTA_BI2 = nil
    end

    print("[VANTA] detenido: movimiento, colisiones, luz y hook restaurados.")
end

-- Puerta para el loader: le dice si el script está sano y qué remotos ve.
-- Una sola fuente de verdad, no dos listas que se desincronizan.
State.Verify = function()
    local expected = {
        "GiveTool",
        "Vending",
        "Energy",
        "HealTheNoobs",
        "RainbowWhatStat",
        "HitBadguy",
        "IceSlip",
    }

    local missing = {}

    for _, name in ipairs(expected) do
        if not ResolveRemote("Events", name) then
            table.insert(missing, name)
        end
    end

    return {
        ok = #missing == 0,
        running = State.Running,
        placeId = game.PlaceId,
        expected = #expected,
        missing = missing,
        hooks = HookAvailable,
    }
end

Notify(
    "VANTA cargado",
    "PlaceId " .. tostring(game.PlaceId)
        .. " | hooks: " .. (HookAvailable and "sí" or "no")
)

return State
