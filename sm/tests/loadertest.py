"""
VANTA | Strongman — banco del arranque.

Comprueba que el loader hace trabajo de verdad y que, cuando algo falla, se
ve en pantalla. Un loader que solo anima no pasa estas pruebas.

Escenarios
  ok          descarga, compila, ejecuta y verifica
  pr404       main da 404: debe caer a la rama
  neterr      sin red: deben verse los dos intentos fallidos
  empty       respuesta vacía: no debe dar por bueno
  syntax      el script no compila: error de sintaxis a la vista
  runerr      el script revienta al ejecutarse: se dice
  nostate     el script no deja estado: se dice por qué
  wrongplace  en otro PlaceId: avisa pero sigue
  noplayer    sin personaje: se para y lo dice

Uso: python3 sm/tests/loadertest.py [escenario]
"""
import os
import pathlib
import re
import sys

import lupa

ROOT = pathlib.Path(__file__).resolve().parent.parent
LOADER = ROOT.parent / "StrongmanLoader.lua"

MODE = sys.argv[1] if len(sys.argv) > 1 else "ok"


def desugar(source):
    pattern = re.compile(r"^(\s*)([\w\.\[\]\"']+?)\s*(\+=|-=|\*=|/=)\s*(.+)$")
    out = []

    for line in source.split("\n"):
        m = pattern.match(line)
        if m and not line.lstrip().startswith("--"):
            ind, lhs, op, rhs = m.groups()
            line = f"{ind}{lhs} = {lhs} {op[0]} ({rhs})"
        out.append(line)

    return "\n".join(out)


MOCK = r'''
MODE = "..."
TICK = 0
LOG = {}
INST = {}
CO = {}
CLICKED = nil

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
    function t:FindFirstChildOfClass(c)
        for _, ch in ipairs(t.Children) do if ch.ClassName == c then return ch end end
    end
    function t:FindFirstChildWhichIsA(c) return t:FindFirstChildOfClass(c) end
    function t:WaitForChild(n) return t:FindFirstChild(n) end
    function t:Destroy() t.Destroyed = true end
    t.MouseButton1Click = { Connect = function(_, fn) t.click = fn end }

    if class == "Frame" or class == "TextLabel" then
        t.IsA = function(self, c)
            return self.ClassName == c or c == "GuiObject"
        end
    end

    INST[#INST+1] = t
    return t
end

local function add(parent, child)
    child.Parent = parent
    table.insert(parent.Children, child)
    return child
end

Instance = {}

function Instance.new(class, parent)
    local t = mk(class)
    if parent then add(parent, t) end
    return t
end

UDim2 = {
    fromOffset = function(x, y) return {X = x, Y = y} end,
    new = function() return {X = 0, Y = 0} end,
}
UDim = {new = function() return 0 end}
Color3 = {fromRGB = function(r, g, b) return {r = r, g = g, b = b} end}

Enum = setmetatable({}, {__index = function()
    return setmetatable({}, {__index = function(_, k) return k end})
end})

-- El reloj avanza cuando alguien espera. Congelado, los plazos del loader
-- nunca expiran y los tests se quedarían a medias.
os = {clock = function()
    TICK = TICK + 0.01
    return TICK
end}

task = {
    spawn = function(f)
        local co = coroutine.create(f)
        CO[#CO+1] = co
        return {cancel = function() end}
    end,
    wait = function(t) TICK = TICK + (t or 0) coroutine.yield() end,
    delay = function(_, f) f() end,
    defer = function(f) f() end,
}

-- Servicios
local ReplicatedStorage = mk("ReplicatedStorage")
if MODE ~= "nostate" then
    add(ReplicatedStorage, mk("RemoteFunction", "StrongMan_UpgradeStrength"))
end

local PlayerGui = mk("PlayerGui")

local Character = mk("Model", "Tester")
add(Character, mk("Humanoid", "Humanoid"))

local LocalPlayer = mk("Player", "Tester")
LocalPlayer.Character = Character
add(LocalPlayer, PlayerGui)

local Players = mk("Players")
Players.LocalPlayer = LocalPlayer

if MODE == "noplayer" then
    LocalPlayer.Character = nil
end
add(Players, LocalPlayer)

local SVC = {
    Players = Players,
    ReplicatedStorage = ReplicatedStorage,
    TweenService = {Create = function() return {Play = function() end} end},
    CoreGui = mk("CoreGui"),
}

game = {
    PlaceId = (MODE == "wrongplace") and 123456 or 6766156863,
    GetService = function(_, n) return SVC[n] or mk(n) end,
    IsLoaded = function() return true end,
    Loaded = {Wait = function() end},
}

function game.HttpGet(_, url)
    if MODE == "neterr" then error("HttpError: 502 Bad Gateway") end
    if MODE == "empty" then return "" end
    if MODE == "syntax" then return string.rep("-- fuente falsa larga\n", 100) end
    if MODE == "pr404" and url:find("/main/") then
        error("HttpError: 404 Not Found (raw.githubusercontent.com)")
    end
    return string.rep("-- fuente falsa de VANTA\n", 100)
end

ENV = {}
function getgenv() return ENV end

function warn(...) say("WARN", table.concat({...}, " ")) end

function loadstring(text, name)
    if MODE == "syntax" then return nil, "syntax error near '='" end
    if MODE == "runerr" then return function() error("boom dentro del script") end end
    if MODE == "nostate" then return function() end end

    return function()
        ENV.VANTA_STRONGMAN = {
            Verify = function()
                return {ok = true, total = 9, healthy = 9, broken = 0}
            end,
        }
    end
end
'''

def mock_for(mode):
    return MOCK.replace('MODE = "..."', 'MODE = "' + mode + '"')


def drive(src, max_steps=400):
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(mock_for(MODE))
    lua.execute("LOADER_SRC = [==[\n" + src + "\n]==]")

    lua.execute("""
        function drive(maxSteps)
            local fn, err = load(LOADER_SRC, "loader")
            if not fn then return "COMPILE FAIL: " .. tostring(err) end

            local main = coroutine.create(fn)

            for step = 1, maxSteps do
                local alive = false

                if coroutine.status(main) == "suspended" then
                    alive = true
                    local ok, e = coroutine.resume(main)
                    if not ok then return "MAIN ERROR: " .. tostring(e) end
                end

                for i = 1, #CO do
                    local c = CO[i]
                    if coroutine.status(c) == "suspended" then
                        alive = true
                        local ok, e = coroutine.resume(c)
                        if not ok then return "WORKER ERROR: " .. tostring(e) end
                    end
                end

                if not alive then return "TERMINADO en " .. step .. " pasos" end
            end

            local gui
            for _, i in ipairs(INST) do
                if i.ClassName == "ScreenGui" then gui = i end
            end

            if gui and gui.Destroyed then
                return "LOADER TERMINADO (hilo huérfano sigue vivo)"
            end

            return "SIGUE VIVO tras " .. maxSteps .. " pasos"
        end
    """)

    result = lua.eval("drive")(max_steps)

    texts = []
    for inst in lua.eval("INST").values():
        if inst["ClassName"] == "TextLabel" and inst["Text"]:
            texts.append(inst["Text"])

    logs = []

    for key, line in (lua.eval("LOG") or {}).items():
        if isinstance(key, int):
            logs.append(str(line))

    return result, texts, logs


def main():
    source = desugar(LOADER.read_text(encoding="utf-8"))
    result, texts, logs = drive(source)

    failures = []
    joined = " | ".join(texts)
    log_line = " | ".join(logs)

    print(f"  resultado: {result}")
    print(f"  textos: {joined[:220]}")

    # El loader nunca debe quedarse colgado sin explicar.
    if "COLG" in result or "SIGUE VIVO" in result:
        failures.append(f"el loader no terminó: {result}")

    if MODE in ("ok", "pr404", "wrongplace"):
        if "listo" not in joined and "secciones" not in joined:
            failures.append("no llegó a 'listo' en el caso feliz")
        if "✖" in joined:
            failures.append("el caso feliz mostró un error")

    if MODE == "pr404":
        if "main" in log_line and "404" in log_line and "listo" not in joined:
            failures.append("no cayó a la rama cuando main dio 404")

    if MODE == "neterr":
        if "descargar" not in joined.lower():
            failures.append("no dijo que falló la descarga")
        if "✖" not in joined:
            failures.append("el fallo de red no se ve en pantalla")

    if MODE == "empty":
        if "✖" not in joined:
            failures.append("una respuesta vacía se dio por buena")

    if MODE == "syntax":
        if "sintaxis" not in joined.lower():
            failures.append("no nombró el error de sintaxis")

    if MODE == "runerr":
        if "falló" not in joined.lower() and "boom" not in joined:
            failures.append("no dijo que el script revienta")

    if MODE == "nostate":
        if "StrongMan_UpgradeStrength" not in joined:
            failures.append("no explicó qué falta cuando no deja estado")

    if MODE == "noplayer":
        full = (log_line + " " + joined).lower()
        if "mundo" not in full and "apareciste" not in full:
            failures.append("sin personaje no dijo nada")

    if MODE == "wrongplace":
        full = log_line + " " + joined
        if "PlaceId" not in full:
            failures.append("no avisó de que está en otro PlaceId")

    if failures and os.environ.get("SM_DEBUG"):
        print("  TEXTOS:", " | ".join(texts))
        print("  LOGS:", " | ".join(logs))

    print()
    if failures:
        print("FALLOS:")
        for f in failures:
            print("  ✖", f)
        return 1

    print("LOADER OK — 0 fallos")
    return 0


if __name__ == "__main__":
    sys.exit(main())
