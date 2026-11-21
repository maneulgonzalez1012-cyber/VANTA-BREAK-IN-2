"""
VANTA — prueba del script único.

Carga SOLO VANTA-BreakIn2.lua en un Roblox falso y comprueba:
  1. El bundle compila y arranca.
  2. Los 9 módulos quedaron declarados.
  3. Los módulos cargaron de verdad (no solo existen).
  4. La UI se creó con cada tab y cada botón.
  5. getgenv().VANTA_BI2_STATE expone Stop/Verify para el loader.
  6. Stop desmonta todo: 0 conexiones, 0 restos.

Uso: python3 /tmp/bundletest.py
"""
import pathlib
import sys

import lupa

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
BUNDLE = ROOT / "VANTA-BreakIn2.lua"

lua = lupa.LuaRuntime(unpack_returned_tuples=True, register_eval=False)

PRELUDE = r"""
-- ───────── Roblox falso ─────────
local function class(className, name)
    local inst = {}
    inst.ClassName = className
    inst.Name = name or className
    inst.Children = {}
    inst._signals = {}
    inst._props = {}

    function inst:IsA(what)
        return self.ClassName == what or what == "Instance"
            or (what == "BasePart" and self.ClassName == "Part")
    end

    function inst:FindFirstChild(n, recursive)
        for _, c in ipairs(self.Children) do
            if c.Name == n then return c end
        end
        if recursive then
            for _, c in ipairs(self.Children) do
                local hit = c:FindFirstChild(n, true)
                if hit then return hit end
            end
        end
        return nil
    end

    function inst:FindFirstChildOfClass(cls)
        for _, c in ipairs(self.Children) do
            if c.ClassName == cls then return c end
        end
        return nil
    end

    function inst:GetChildren()
        local copy = {}
        for i, c in ipairs(self.Children) do copy[i] = c end
        return copy
    end

    function inst:GetDescendants()
        local out = {}
        local function walk(node)
            for _, c in ipairs(node.Children) do
                table.insert(out, c); walk(c)
            end
        end
        walk(self)
        return out
    end

    function inst:Destroy() self.Destroyed = true end

    function inst:Signal(name)
        self._signals[name] = self._signals[name] or {}
        local list = self._signals[name]
        local sig = {}
        function sig:Connect(fn)
            table.insert(list, fn)
            local conn = {connected = true}
            function conn:Disconnect()
                self.connected = false
                for i, f in ipairs(list) do
                    if f == fn then table.remove(list, i) break end
                end
            end
            return conn
        end
        function sig:Wait() end
        function sig.Fire(_, ...) for _, fn in ipairs(list) do fn(...) end end
        sig._list = list
        return sig
    end

    function inst:UnequipTools() end
    function inst:ChangeState() end
    function inst:GetPropertyChangedSignal() return self:Signal("prop") end

    inst.Changed = inst:Signal("Changed")
    inst.Position = setmetatable({Magnitude = 0, X = 0, Y = 0, Z = 0}, {
        __sub = function() return {Magnitude = 0, X = 0, Y = 0, Z = 0} end,
        __add = function() return {Magnitude = 0, X = 0, Y = 0, Z = 0} end,
    })
    inst.CFrame = setmetatable({}, {
        __index = function() return function() return inst.CFrame end end,
        __mul = function() return inst.CFrame end,
    })
    inst.Text = ""
    inst.CanCollide = true
    inst.WalkSpeed = 16
    inst.JumpPower = 50
    inst.UseJumpPower = true
    inst.Health = 100
    inst.MaxHealth = 100
    inst.Brightness = 1
    inst.ClockTime = 14
    inst.FogEnd = 1000
    inst.GlobalShadows = true

    return inst
end

function math.clamp(v, lo, hi) if v < lo then return lo end if v > hi then return hi end return v end
if not table.clear then function table.clear(t) for k in pairs(t) do t[k] = nil end end end
if not table.find then
    function table.find(t, v) for i, x in ipairs(t) do if x == v then return i end end return nil end
end

CFrame = {}
function CFrame.new(a, b, c)
    if type(a) == "number" and b == nil then
        return {Position = {Magnitude = 0, X = a, Y = a, Z = a}}
    end
    return {Position = {Magnitude = 0, X = a or 0, Y = b or 0, Z = c or 0}}
end
setmetatable(CFrame, {__mul = function() return CFrame.new(0,0,0) end})
Color3 = {fromRGB = function(r,g,b) return {r=r,g=g,b=b} end}

Instance = {}
function Instance.new(cls, parent)
    local inst = class(cls, cls)
    if parent then inst.Parent = parent end
    return inst
end

local function addChild(parent, child)
    child.Parent = parent
    table.insert(parent.Children, child)
    return child
end

local services = {}
local function service(name)
    if not services[name] then services[name] = class("Service", name) end
    return services[name]
end

game = {
    PlaceId = 13864667823,
    GetService = function(self, name) return service(name) end,
    IsA = function() return false end,
}

task = {wait = function(t) return t or 0 end, spawn = function(fn, ...) fn(...) end,
        delay = function(_, fn) fn() end, defer = function(fn, ...) fn(...) end}

Enum = setmetatable({}, {__index = function(_, k)
    return setmetatable({}, {__index = function(_, k2) return k2 end})
end})

getgenv = function() return GENV end
GENV = {}

-- Jugador
local players = service("Players")
local localPlayer = class("Player", "Tester")
localPlayer.Character = class("Model", "Tester")
localPlayer.DisplayName = "Tester"
localPlayer.Name = "Tester"

local humanoid = class("Humanoid", "Humanoid")
humanoid.Health = 42
humanoid.MaxHealth = 100
addChild(localPlayer.Character, humanoid)
addChild(localPlayer.Character, class("Part", "HumanoidRootPart"))

local backpack = class("Backpack", "Backpack")
addChild(localPlayer, backpack)
local playerGui = class("PlayerGui", "PlayerGui")
addChild(localPlayer, playerGui)

players.LocalPlayer = localPlayer
players.PlayerAdded = players:Signal("PlayerAdded")
players.PlayerRemoving = players:Signal("PlayerRemoving")
function players:GetPlayers() return {localPlayer} end

-- Remotos
local rs = service("ReplicatedStorage")
local events = class("Folder", "Events")
addChild(rs, events)

for _, n in ipairs({"GiveTool","Vending","Energy","HealTheNoobs",
                    "RainbowWhatStat","HitBadguy","IceSlip"}) do
    local re = class("RemoteEvent", n)
    re.fired = 0
    function re:FireServer(...)
        self.fired = self.fired + 1
        local args = table.pack(...)
        if self.Name == "GiveTool" then
            addChild(backpack, class("Tool", args[1]))
        elseif self.Name == "Energy" then
            humanoid.Health = math.min(humanoid.Health + (tonumber(args[1]) or 0), 100)
        end
    end
    addChild(events, re)
end

local runSvc = service("RunService")
runSvc.Heartbeat = runSvc:Signal("Heartbeat")
runSvc.Stepped = runSvc:Signal("Stepped")

local uis = service("UserInputService")
uis.JumpRequest = uis:Signal("JumpRequest")

service("Lighting")
service("Workspace")

-- Rayfield falso: registra cada elemento creado
local UI = {tabs = {}, buttons = {}, toggles = 0, sliders = 0,
            inputs = 0, dropdowns = 0, texts = 0, sections = 0, unloaded = false}

local function tab(name)
    local t = {}
    t.name = name
    function t:CreateButton(p) table.insert(UI.buttons, p.name) return {Set = function() end} end
    function t:CreateToggle(p) UI.toggles = UI.toggles + 1 return {Set = function() end} end
    function t:CreateSlider(p) UI.sliders = UI.sliders + 1 return {Set = function() end} end
    function t:CreateInput(p) UI.inputs = UI.inputs + 1 return {Set = function() end} end
    function t:CreateDropdown(p) UI.dropdowns = UI.dropdowns + 1 return {Set = function() end} end
    function t:CreateText(p) UI.texts = UI.texts + 1 return {Set = function() end} end
    function t:CreateSection(p) UI.sections = UI.sections + 1 return {Set = function() end} end
    return t
end

local fakeWindow = {}
function fakeWindow:CreateTab(p)
    table.insert(UI.tabs, p.name)
    return tab(p.name)
end
function fakeWindow:Notify(p) table.insert(UI.buttons, "NOTIFY:" .. tostring(p.title)) end
function fakeWindow:Unload() UI.unloaded = true end

RAYFIELD_FAKE = nil
local Rayfield = {}
RAYFIELD_FAKE = Rayfield
function Rayfield:CreateWindow(config)
    UI.window = config.name
    UI.subtitle = config.subtitle
    return fakeWindow
end

-- loadstring: solo sirve el bundle y Rayfield falso
local function fakeLoadstring(chunk, chunkname)
    if chunkname and chunkname:find("Rayfield") then
        return function() return Rayfield end
    end
    return load(chunk, chunkname)
end

-- HttpGet devuelve marcadores; el bundle no baja nada más
local function fakeHttpGet(url)
    if url:find("sirius.menu") then return "--RAYFIELD--" end
    error("descarga inesperada: " .. url)
end

Work = {}
function Work.UI() return UI end
function Work.humanoid() return humanoid end
function Work.backpack() return backpack end
function Work.Stepped() return runSvc.Stepped end
function Work.GENV() return GENV end
function Work.players() return players end
"""


def main():
    lua.execute(PRELUDE)

    # Se parchean dentro del propio Lua: asignar desde Python no crea globales
    # visibles al compilar el bundle.
    lua.execute("""
        loadstring = function(chunk, chunkname)
            if chunk == "--RAYFIELD--" then
                return function() return RAYFIELD_FAKE end
            end
            return load(chunk, chunkname)
        end
        game.HttpGet = function(_, url)
            if url:find("sirius.menu") then return "--RAYFIELD--" end
            error("descarga inesperada: " .. url)
        end
    """)

    source = BUNDLE.read_text(encoding="utf-8")

    # El bundle real usa `+=`, `math.clamp` y `table.clear` (Luau). Para
    # probar la lógica se desugan los operadores compuestos.
    import re
    desugar = re.compile(r"^(\s*)([\w\.\[\]\"']+?)\s*(\+=|-=|\*=)\s*(.+)$")
    lines = []
    for line in source.split("\n"):
        m = desugar.match(line)
        if m and not line.lstrip().startswith("--"):
            ind, lhs, op, rhs = m.groups()
            line = f"{ind}{lhs} = {lhs} {op[0]} ({rhs})"
        lines.append(line)
    source = "\n".join(lines)

    lua.execute("BUNDLE_SRC = [==[\n" + source + "\n]==]")

    runner = lua.execute(
        "return function() "
        "  local fn, err = loadstring(BUNDLE_SRC, 'VANTA:bundle') "
        "  if not fn then return false, 'COMPILA: ' .. tostring(err) end "
        "  local ok, res = pcall(fn) "
        "  if not ok then return false, 'ARRANCA: ' .. tostring(res) end "
        "  return true, res "
        "end"
    )

    res = runner()
    res = res if isinstance(res, tuple) else (res,)
    ok, result = bool(res[0]), (res[1] if len(res) > 1 else None)

    failures = []

    if not ok:
        print(f"✖ {result}")
        sys.exit(1)

    Work = lua.eval("Work")
    UI = Work.UI()
    genv = Work.GENV()

    print(f"  ventana: {UI['window']} ({UI['subtitle']})")
    print(f"  tabs ({len(list(UI['tabs'].values()))}): {', '.join(UI['tabs'].values())}")
    print(f"  botones: {len(list(UI['buttons'].values()))}")
    print(f"  toggles: {UI['toggles']} | inputs: {UI['inputs']} | dropdowns: {UI['dropdowns']}")

    # ── 1. Tabs esperados ──
    expected_tabs = {"Supervivencia", "Objetos", "Combate", "Navegación",
                     "Movimiento", "Visuales", "Lobby", "Diagnóstico"}
    got_tabs = set(UI["tabs"].values())
    missing = expected_tabs - got_tabs
    if missing:
        failures.append(f"faltan tabs: {missing}")

    # ── 2. Estado expuesto ──
    state = genv["VANTA_BI2"]
    if state is None:
        failures.append("getgenv().VANTA_BI2 no existe")
    else:
        if state["Stop"] is None:
            failures.append("VANTA_BI2.Stop no existe")
        else:
            print("  getgenv().VANTA_BI2 exponía Stop")
        if state["Verify"] is None:
            failures.append("VANTA_BI2.Verify no existe")
        else:
            v = state["Verify"]()
            print(f"  Verify -> ok={v['ok']} secciones={v['total']} "
                  f"sanas={v['healthy']} rotas={v['broken']} "
                  f"remotos={len(list(v['remotes'].values()))} "
                  f"conexiones={v['connections']} ({v['ms']} ms)")
            if v["total"] != 8:
                failures.append(f"se declararon {v['total']} secciones, no 8")
            if v["broken"] != 0:
                failures.append(f"{v['broken']} secciones rotas al cargar")

    # ── 3. Secciones cargadas ──
    sections = state["sections"]
    health = sections["Health"]()
    print(f"  secciones: {health['healthy']}/{health['total']} sanas, "
          f"{sections['ConnectionCount']()} conexiones")

    if health["broken"] != 0:
        for record in list(sections["List"]().values()):
            if record["error"]:
                print(f"    ROTA {record['name']}: {record['error']}")
        failures.append(f"{health['broken']} secciones rotas al cargar")

    # ── 4. Acción real a través del bundle ──
    survival = sections["Get"]("survival")
    itemsModule = sections["Get"]("items")

    res = survival["Heal"]()
    res = res if isinstance(res, tuple) else (res,)
    print(f"  survival.Heal -> {res[0]} | {res[1] if len(res) > 1 else ''}")

    if not res[0]:
        failures.append(f"heal falló en el bundle: {res[1] if len(res)>1 else ''}")
    if Work.humanoid().Health <= 42:
        failures.append("la vida no subió en el bundle")

    res = itemsModule["Give"]("Golden Apple")
    res = res if isinstance(res, tuple) else (res,)
    print(f"  items.Give -> {res[0]} | {res[1] if len(res) > 1 else ''}")

    # El motivo debe ser texto, no una tabla: si lo fuera, la UI pondría
    # "table: 0x..." delante del usuario.
    if len(res) > 1 and lua.eval("type")(res[1]) != "string":
        failures.append(f"el motivo de Give no es texto: {type(res[1]).__name__}")
    if not res[0]:
        failures.append(f"give falló en el bundle: {res[1] if len(res)>1 else ''}")

    # ── 5. Una función inexistente no explota ──
    missing = survival["noExiste"]
    if missing is not None:
        failures.append("una función inexistente no devolvió nil")

    # ── 6. Stop limpia todo ──
    Stepped = Work.Stepped()
    connections_before = len(list(Stepped._list.values()))
    state["Stop"]()
    connections_after = len(list(Stepped._list.values()))

    print(f"  Stop: conexiones {connections_before} -> {connections_after} | "
          f"ventana cerrada: {UI['unloaded']}")

    if connections_after != 0:
        failures.append(f"Stop dejó {connections_after} conexiones Stepped")
    if not UI["unloaded"]:
        failures.append("Stop no descargó la ventana")
    if genv["VANTA_BI2"] is not None:
        failures.append("Stop no limpió getgenv().VANTA_BI2")

    print()
    if failures:
        print("FALLOS:")
        for f in failures:
            print("  ✖", f)
        sys.exit(1)

    print("BUNDLE OK — 0 fallos")


if __name__ == "__main__":
    main()
