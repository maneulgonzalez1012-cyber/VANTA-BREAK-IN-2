import re, sys, lupa

MODE = sys.argv[1] if len(sys.argv) > 1 else "ok"

# desugar Luau compound assignment
import pathlib
src = open(pathlib.Path(__file__).resolve().parent.parent.parent / 'loader.lua', encoding='utf-8').read()
lines = []
for line in src.split("\n"):
    m = re.match(r'^(\s*)([\w\.\[\]"\']+?)\s*(\+=|-=|\*=|/=)\s*(.+)$', line)
    if m and not line.lstrip().startswith('--'):
        ind, lhs, op, rhs = m.groups()
        line = f'{ind}{lhs} = {lhs} {op[0]} ({rhs})'
    lines.append(line)
# El banco no puede esperar los 12 s reales del tiempo límite: se baja a 3.
dsrc = "\n".join(lines).replace("local RUN_TIMEOUT = 12", "local RUN_TIMEOUT = 1")
assert "local RUN_TIMEOUT = 1" in dsrc, "no se pudo bajar RUN_TIMEOUT"

lua = lupa.LuaRuntime(unpack_returned_tuples=True)

MOCK = r'''
MODE = "%s"
TICK = 0
LOG = {}
HISTORY = {}
INST = {}
TWEEN = 0

local function say(...) table.insert(LOG, table.concat({...}, " ")) end

function mk(class, name)
    local t = {}
    t.ClassName = class
    t.Name = name or class
    t.Children = {}
    t.Parent = nil
    t.Text = ""
    t.TextTransparency = 1
    t.BackgroundTransparency = 1
    t.Size = {X = 0, Y = 0}
    t.Position = {X = 0, Y = 0}
    t.Destroyed = false
    function t:IsA(c) return t.ClassName == c end
    function t:GetChildren() return t.Children end
    function t:GetDescendants()
        local r = {}
        for _, c in ipairs(t.Children) do
            r[#r+1] = c
            for _, d in ipairs(c:GetDescendants()) do r[#r+1] = d end
        end
        return r
    end
    function t:FindFirstChild(n)
        for _, c in ipairs(t.Children) do if c.Name == n then return c end end
    end
    function t:WaitForChild(n) return t:FindFirstChild(n) end
    function t:Destroy() t.Destroyed = true end
    t.MouseButton1Click = { Connect = function(_, fn) t.click = fn end }
    INST[#INST+1] = t
    return t
end

UDim2 = {
    fromOffset = function(x, y) return {X = x, Y = y} end,
    fromScale  = function(x, y) return {X = x, Y = y} end,
    new        = function() return {X = 0, Y = 0} end,
}
Vector2 = { new = function(x, y) return {X = x, Y = y} end }
Color3  = { fromRGB = function(r, g, b) return {r = r} end }
Enum    = setmetatable({}, { __index = function() return setmetatable({}, { __index = function(_, k) return k end }) end })
TweenInfo = { new = function() return {} end }

TweenService = {
    Create = function(_, obj, info, props)
        TWEEN = TWEEN + 1
        for k, v in pairs(props or {}) do obj[k] = v end
        if obj.ClassName == "TextLabel" then
            HISTORY[#HISTORY+1] = obj.Name .. " = " .. tostring(obj.Text)
        end
        return { Play = function() end, Cancel = function() end, Completed = { Wait = function() end } }
    end,
}

CoreGui   = mk("CoreGui", "CoreGui")
PlayerGui = mk("PlayerGui", "PlayerGui")

Player = mk("Player", "Player")
Player.WaitForChild = function() return PlayerGui end

Players = mk("Players", "Players")
Players.LocalPlayer = Player

RS = mk("ReplicatedStorage", "ReplicatedStorage")
Events = mk("Folder", "Events")
Events.Parent = RS
RS.Children[#RS.Children+1] = Events

EXPECTED = {"GiveTool","Vending","Energy","HealTheNoobs","RainbowWhatStat","HitBadguy","IceSlip"}
local count = (MODE == "missing") and 3 or 7
for i = 1, count do
    local r = mk("RemoteEvent", EXPECTED[i])
    r.Parent = Events
    Events.Children[#Events.Children+1] = r
end

SVC = { Players = Players, ReplicatedStorage = RS, TweenService = TweenService, CoreGui = CoreGui }

game = { PlaceId = 13864667823 }
function game.GetService(_, n) return SVC[n] end
URLS_PEDIDAS = {}
-- El loader llama game:HttpGet(url), con dos puntos: el primer argumento
-- es `game`. Un mock con punto recibía la tabla como URL y todo pasaba
-- por accidente.
function game.HttpGet(_, url)
    table.insert(URLS_PEDIDAS, url)

    -- Caso real mientras el PR no está mergeado: main 404, branch 200.
    if MODE == "pr404" then
        if url:find("/main/") then
            error("HttpError: 404 Not Found (raw.githubusercontent.com)")
        end
        return string.rep("-- fuente falsa con la branch\n", 120)
    end

    if MODE == "neterr" then error("HttpError: 502 Bad Gateway") end
    if MODE == "empty" then return "" end
    if MODE == "syntax" then return "local x = = 1" end
    return string.rep("-- fuente falsa de VANTA\n", 120)
end

ENV = {}
function getgenv() return ENV end
function warn(...) say("WARN", table.concat({...}, " ")) end

CO = {}

-- os.clock del mock: avanza con cada espera. Si no, el tiempo límite de
-- la etapa 4 se compara contra un reloj congelado y nunca expira.
os = {clock = function() return TICK end}

task = {
    spawn = function(f)
        local co = coroutine.create(f)
        CO[#CO+1] = co
        return { cancel = function() end }
    end,
    -- os.clock del mock: avanza con cada espera. Si no, el tiempo límite
    -- de la etapa 4 se compara contra un reloj congelado y nunca expira.
    wait = function(t) TICK = TICK + (t or 0) coroutine.yield() end,
}

function loadstring(s)
    if MODE == "syntax" then return nil, "syntax error near '='" end
    if MODE == "runerr" then return function() error("boom dentro de VANTA.lua") end end
    if MODE == "nostate" then return function() end end

    -- Se queda en "Ejecutar": el chunk nunca vuelve. Es el caso real.
    if MODE == "hang" then
        return function() while true do coroutine.yield() end end
    end

    -- Tarda, pero termina. No debe reportarse como fallo.
    if MODE == "slow" then
        return function()
            for _ = 1, 5 do coroutine.yield() end
            ENV.VANTA_BI2 = {
                Verify = function()
                    return { ok = true, total = 8, healthy = 8, broken = 0,
                             found = #EXPECTED, missing = {} }
                end,
            }
        end
    end
    if MODE == "notmodules" then
        return function()
            ENV.VANTA_BI2 = {
                Verify = function()
                    return { ok = true, found = #EXPECTED, missing = {} }
                end,
            }
        end
    end
    return function()
        ENV.VANTA_BI2 = {
            Running = true,
            Verify = function()
                local n = #Events.Children
                local missing = {}
                for i = n + 1, #EXPECTED do missing[#missing+1] = EXPECTED[i] end
                local broken = (MODE == "brokenmodule") and 1 or 0
                return {
                    ok = (#missing == 0) and broken == 0,
                    total = 8,
                    healthy = 8 - broken,
                    broken = broken,
                    missing = missing,
                    found = #EXPECTED - #missing,
                    placeId = 13864667823,
                    connections = 7,
                }
            end,
        }
    end
end

Instance = { new = function(c) return mk(c, c) end }
''' % MODE

lua.execute(MOCK)
print("mock listo | instancias iniciales:", lua.eval("#INST"))

lua.execute(r'''
function drive(src, maxSteps)
    local f, e = load(src, "LOADER")
    if not f then return "COMPILE FAIL: " .. tostring(e) end

    local main = coroutine.create(f)

    for step = 1, maxSteps do
        local alive = false

        if coroutine.status(main) == "suspended" then
            alive = true
            local ok, err = coroutine.resume(main)
            if not ok then return "MAIN ERROR: " .. tostring(err) end
        end

        for i = 1, #CO do
            local c = CO[i]
            if coroutine.status(c) == "suspended" then
                alive = true
                local ok, err = coroutine.resume(c)
                if not ok then return "WORKER ERROR: " .. tostring(err) end
            end
        end

        if not alive then return "TERMINADO en " .. step .. " pasos" end
    end

    -- Si el ScreenGui ya se destruyó, el loader terminó: lo que sigue
    -- "vivo" es el hilo huérfano del script que se colgó, no el loader.
    local guiFinal
    for _, i in ipairs(INST) do
        if i.ClassName == "ScreenGui" then guiFinal = i end
    end

    if guiFinal and guiFinal.Destroyed then
        return "LOADER TERMINADO (hilo huérfano del script sigue vivo)"
    end

    local donde = "?"

    for _, i in ipairs(INST) do
        if i.ClassName == "TextLabel" and i.Text ~= ""
           and i.Text ~= "✔" and i.Text ~= "✖" and i.Text ~= "·"
           and i.Text ~= "VANTA" and i.Text ~= "BREAK IN 2" and i.Text ~= "clic para cerrar"
        then
            donde = i.Text
        end
    end

    return "SIGUE VIVO tras " .. maxSteps .. " pasos | detail: " .. tostring(donde)
end
''')

print("resultado:", lua.eval("drive")(dsrc, 500))
print("clases creadas:", lua.eval("#INST"), "| tweens:", lua.eval("TWEEN"))

lua.execute(r'''
-- Estado final del ScreenGui
local gui
for _, i in ipairs(INST) do if i.ClassName == "ScreenGui" then gui = i end end
print("ScreenGui:", gui and (gui.Destroyed and "destruido" or "vivo, padre="..tostring(gui.Parent and gui.Parent.Name)) or "NO CREADO")

-- Etapas y sus marcas
print("--- ETAPAS ---")
for _, i in ipairs(INST) do
    if i.ClassName == "TextLabel" and (i.Text == "✔" or i.Text == "✖" or i.Text == "·") then
        print("  marca: " .. i.Text)
    end
end

print("--- TEXTOS CON ETAPAS ---")
local wanted = {Conectar=1, Descargar=1, Compilar=1, Ejecutar=1, ["Verificar remotos"]=1}
for _, i in ipairs(INST) do
    if i.ClassName == "TextLabel" and wanted[i.Text] then
        print("  " .. i.Text)
    end
end

print("--- DETAIL ---")
for _, i in ipairs(INST) do
    if i.ClassName == "TextLabel" and i.Name == "TextLabel" and i.Text ~= "" and not wanted[i.Text] and i.Text ~= "✔" and i.Text ~= "✖" and i.Text ~= "·" then
        print("  [" .. i.Text .. "]")
    end
end

print("--- LOG ---")
for _, line in ipairs(LOG) do print("  " .. line) end
''')
