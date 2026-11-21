"""
VANTA — banco de reentrada.

La pregunta: al ejecutar el script por SEGUNDA vez, ¿sigue funcionando?
En Roblox eso pasa todo el tiempo: se vuelve a pegar en la consola sin
reiniciar. Si la segunda vez empeora, el script está roto aunque el
primer arranque se vea bien.

Escenarios
  once        una sola ejecución (control)
  twice       dos ejecuciones seguidas: la segunda debe seguir viva
  thrice      tres seguidas, por si el daño se acumula
  stopstart   ejecutar, cerrar con Stop, volver a ejecutar
  stopstop    cerrar dos veces no debe explotar

Uso: python3 tools/tests/reentry.py [once|twice|thrice|stopstart|stopstop]
"""
import pathlib
import re
import sys

import lupa

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
BUNDLE = ROOT / "VANTA-BreakIn2.lua"


def desugar(source):
    pattern = re.compile(r"^(\s*)([\w\.\[\]\"']+?)\s*(\+=|-=|\*=)\s*(.+)$")
    out = []
    for line in source.split("\n"):
        m = pattern.match(line)
        if m and not line.lstrip().startswith("--"):
            ind, lhs, op, rhs = m.groups()
            line = f"{ind}{lhs} = {lhs} {op[0]} ({rhs})"
        out.append(line)
    return "\n".join(out)


def prelude(lua):
    """Mundo mínimo, con un Rayfield falso que cuenta cuántas veces se montó."""

    lua.execute(r"""
local function class(className, name)
    local inst = {}
    inst.ClassName = className
    inst.Name = name or className
    inst.Children = {}
    inst._signals = {}

    function inst:IsA(what)
        return self.ClassName == what or what == "Instance"
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
            function conn:DisconnectAll() self:Disconnect() end
            return conn
        end
        function sig:Wait() end
        function sig.Fire(_, ...)
            for _, fn in ipairs(list) do fn(...) end
        end
        sig.count = function() return #list end
        return sig
    end

    inst.Position = {Magnitude = 0, X = 0, Y = 0, Z = 0}
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
if not table.create then function table.create(n, v) local t = {} for i = 1, n do t[i] = v end return t end end

CFrame = {}
function CFrame.new(a, b, c)
    return {Position = {Magnitude = 0, X = a or 0, Y = b or 0, Z = c or 0}}
end
setmetatable(CFrame, {__mul = function() return CFrame.new(0,0,0) end})
Vector3 = {new = function(x,y,z) return {X=x or 0,Y=y or 0,Z=z or 0} end}
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

task = {
    wait = function(t) return t or 0 end,
    spawn = function(fn, ...) fn(...) end,
    delay = function(_, fn) fn() end,
    defer = function(fn, ...) fn(...) end,
}

Enum = setmetatable({}, {__index = function(_, k)
    return setmetatable({}, {__index = function(_, k2) return k2 end})
end})

GENV = {}
getgenv = function() return GENV end

local players = service("Players")
local localPlayer = class("Player", "Tester")
localPlayer.Character = class("Model", "Tester")
localPlayer.DisplayName = "Tester"

local humanoid = class("Humanoid", "Humanoid")
humanoid.Health = 42
addChild(localPlayer.Character, humanoid)
addChild(localPlayer.Character, class("Part", "HumanoidRootPart"))
addChild(localPlayer, class("Backpack", "Backpack"))

players.LocalPlayer = localPlayer
players.PlayerAdded = players:Signal("PlayerAdded")
players.PlayerRemoving = players:Signal("PlayerRemoving")
function players:GetPlayers() return {localPlayer} end

local rs = service("ReplicatedStorage")
local events = class("Folder", "Events")
addChild(rs, events)

for _, n in ipairs({"GiveTool","Vending","Energy","HealTheNoobs",
                    "RainbowWhatStat","HitBadguy","IceSlip"}) do
    local re = class("RemoteEvent", n)
    function re:FireServer() end
    addChild(events, re)
end

local runSvc = service("RunService")
runSvc.Heartbeat = runSvc:Signal("Heartbeat")
runSvc.Stepped = runSvc:Signal("Stepped")

local uis = service("UserInputService")
uis.JumpRequest = uis:Signal("JumpRequest")

service("Lighting")
service("Workspace")

-- ── Rayfield falso: cuenta montajes y ventanas vivas ──
MOUNTS = 0
LIVE_WINDOWS = 0

local function makeWindow(config)
    MOUNTS = MOUNTS + 1
    LIVE_WINDOWS = LIVE_WINDOWS + 1

    local win = {}
    win.Name = config and config.name or "?"
    win.Subtitle = config and config.subtitle or ""

    function win:CreateTab(props)
        local tab = {Name = props.name}
        function tab:CreateButton(p)
            local b = {Name = p.name}
            function b:Fire() if p.callback then p.callback() end end
            return b
        end
        function tab:CreateToggle(p)
            local t = {Name = p.name}
            function t:Fire(v) if p.callback then p.callback(v) end end
            return t
        end
        function tab:CreateSlider() return {} end
        function tab:CreateInput() return {} end
        function tab:CreateDropdown() return {} end
        function tab:CreateSection() return {} end
        function tab:CreateText() return {} end
        return tab
    end

    function win:Notify() end

    function win:Unload()
        if not self.Unloaded then
            self.Unloaded = true
            LIVE_WINDOWS = LIVE_WINDOWS - 1
        end
    end

    return win
end

RAYFIELD_FAKE = {
    CreateWindow = function(self, config) return makeWindow(config) end,
}

Work = {}
Work.humanoid = function() return humanoid end
Work.stepped = function() return runSvc.Stepped end
Work.heartbeat = function() return runSvc.Heartbeat end
Work.mounts = function() return MOUNTS end
Work.live = function() return LIVE_WINDOWS end
""")


def run_bundle(lua):
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
    return bool(res[0]), (res[1] if len(res) > 1 else None)


def main():
    scenario = sys.argv[1] if len(sys.argv) > 1 else "twice"

    lua = lupa.LuaRuntime(unpack_returned_tuples=True, register_eval=False)
    prelude(lua)

    source = desugar(BUNDLE.read_text(encoding="utf-8"))
    lua.execute("BUNDLE_SRC = [==[\n" + source + "\n]==]")

    lua.execute("""
        loadstring = function(chunk, chunkname)
            if chunk == "--RAYFIELD--" then return function() return RAYFIELD_FAKE end end
            return load(chunk, chunkname)
        end
        game.HttpGet = function(_, url) return "--RAYFIELD--" end
    """)

    failures = []

    rounds = {"once": 1, "twice": 2, "thrice": 3,
              "stopstart": 1, "stopstop": 1}[scenario]

    for i in range(1, rounds + 1):
        ok, result = run_bundle(lua)

        if not ok:
            failures.append(f"ejecución {i} falló: {result}")
            print(f"  ejecución {i}: ✖ {result}")
            break

        mounts = lua.eval("Work.mounts()")
        live = lua.eval("Work.live()")
        state = lua.eval("getgenv().VANTA_BI2")

        print(f"  ejecución {i}: montajes={mounts} ventanas_vivas={live} "
              f"VANTA_BI2={'sí' if state is not None else 'no'}")

        if state is not None:
            v = state["Verify"]()
            print(f"                 secciones {v['healthy']}/{v['total']}, "
                  f"conexiones {v['connections']}")

            if v["broken"] != 0:
                failures.append(f"ejecución {i}: {v['broken']} secciones rotas")

    # ── Cierre ──
    if scenario in ("stopstart", "stopstop", "twice", "thrice"):
        times = 2 if scenario == "stopstop" else 1

        state = lua.eval("getgenv().VANTA_BI2")

        for n in range(1, times + 1):
            if state is None:
                failures.append("no quedó estado para cerrar")
                break

            try:
                state["Stop"]()
            except Exception as exc:  # noqa: BLE001
                failures.append(f"Stop #{n} explotó: {exc}")
                break

            live = lua.eval("Work.live()")
            print(f"  Stop #{n}: ventanas vivas={live}")

            if live != 0:
                failures.append(f"Stop #{n} dejó {live} ventana(s) abierta(s)")

        if scenario == "stopstart":
            ok, result = run_bundle(lua)

            if not ok:
                failures.append(f"volver a ejecutar tras Stop falló: {result}")
            else:
                state = lua.eval("getgenv().VANTA_BI2")
                print(f"  tras Stop + reejecutar: VANTA_BI2="
                      f"{'sí' if state is not None else 'no'}, "
                      f"ventanas vivas={lua.eval('Work.live()')}")

                if state is None:
                    failures.append("tras Stop, la reejecución no dejó estado")
                else:
                    v = state["Verify"]()
                    if v["broken"] != 0:
                        failures.append(
                            f"tras Stop + reejecutar: {v['broken']} secciones rotas"
                        )

    # ── Lo que debe quedar al final: UNA ventana viva ──
    live = lua.eval("Work.live()")

    if scenario in ("once", "twice", "thrice") and live > 1:
        failures.append(f"quedaron {live} ventanas vivas; debería haber 1")

    # ── Nada debe haber quedado conectado tras cerrar ──
    if scenario in ("stopstop",):
        state = lua.eval("getgenv().VANTA_BI2")
        if state is not None:
            failures.append("tras Stop, getgenv().VANTA_BI2 sigue ocupado")

    print()
    if failures:
        print("FALLOS:")
        for f in failures:
            print("  ✖", f)
        sys.exit(1)

    print("REENTRADA OK — 0 fallos")


if __name__ == "__main__":
    main()
