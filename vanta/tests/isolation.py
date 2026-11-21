"""
VANTA — banco de aislamiento.

La pregunta que responde: al activar una zona, ¿toca otra?
Se mide, no se supone.

Escenarios
  ok        todo carga, ninguna sección rota
  broken    una sección explota al cargar y las demás siguen
  toggle    encender una bandera no cambia las banderas de otra sección
  restore   apagar velocidad y noclip devuelve el personaje a la normalidad
  teardown  cerrar corta TODAS las conexiones y no deja restos

Uso: python3 tools/tests/isolation.py [ok|broken|toggle|restore|teardown]
"""
import pathlib
import re
import sys

import lupa

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src"

lua = lupa.LuaRuntime(unpack_returned_tuples=True, register_eval=False)

PRELUDE = r"""
local function class(className, name)
    local inst = {}
    inst.ClassName = className
    inst.Name = name or className
    inst.Children = {}
    inst._signals = {}

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
        function sig.Fire(_, ...)
            for _, fn in ipairs(list) do fn(...) end
        end
        sig._list = list
        sig.count = function() return #list end
        return sig
    end

    function inst:UnequipTools() end
    function inst:ChangeState() end

    inst.Position = setmetatable({Magnitude = 0, X = 0, Y = 0, Z = 0}, {
        __sub = function() return {Magnitude = 50, X = 0, Y = 0, Z = 0} end,
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

CFrame = {}
function CFrame.new(a, b, c)
    if type(a) == "number" and b == nil then
        return {Position = {Magnitude = 0, X = a, Y = a, Z = a}}
    end
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

-- Hook falso: guarda el envoltorio y deja invocarlo como el real.
HOOK = {installed = 0}
STATE_HOOK = HOOK
function hookmetamethod(obj, name, fn)
    HOOK.installed = HOOK.installed + 1
    HOOK.fn = fn
    -- El original de verdad: llamar al método directo, sin pasar por el
    -- envoltorio (si no, `original` se vuelve a llamar a sí mismo).
    return function(self, ...) return self.FireServer(self, ...) end
end
function getnamecallmethod() return HOOK.method or "FireServer" end
function newcclosure(fn) return fn end
-- El typeof de Luau devuelve "Instance" para instancias, no "table".
typeof = function(v)
    if type(v) == "table" and v.ClassName then return "Instance" end
    return type(v)
end

local players = service("Players")
local localPlayer = class("Player", "Tester")
localPlayer.Character = class("Model", "Tester")
localPlayer.DisplayName = "Tester"

local humanoid = class("Humanoid", "Humanoid")
humanoid.Health = 42
humanoid.MaxHealth = 100
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
EVENTS_FOLDER = events

FIRED = {}

for _, n in ipairs({"GiveTool","Vending","Energy","HealTheNoobs",
                    "RainbowWhatStat","HitBadguy","IceSlip"}) do
    local re = class("RemoteEvent", n)
    function re:FireServer(...)
        table.insert(FIRED, {name = self.Name, args = table.pack(...)})
        if self.Name == "GiveTool" then
            addChild(localPlayer.Backpack, class("Tool", (table.pack(...))[1]))
        elseif self.Name == "Energy" then
            humanoid.Health = math.min(humanoid.Health + ((table.pack(...))[1] or 0), 100)
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

Work = {}
Work.humanoid = function() return humanoid end
Work.stepped = function() return runSvc.Stepped end
Work.heartbeat = function() return runSvc.Heartbeat end
Work.fired = function() return FIRED end
Work.ClearFired = function() FIRED = {} end
"""


def load_modules():
    """Cada módulo se ofrece a un require propio, como en el bundle."""
    lua.execute(PRELUDE)

    lua.execute("""
        local sources = {}
        function Provide(name, text) sources[name] = text end
        local cache = {}
        function Load(name)
            if cache[name] then return cache[name] end
            local fn = assert(load(sources[name], name))
            local result = fn()
            cache[name] = result
            return result
        end
        VANILLA = require
        require = function(target)
            if type(target) == "string" and sources[target] then
                return Load(target)
            end
            return VANILLA(target)
        end
    """)

    for path in sorted(SRC.glob("*.lua")):
        name = path.stem
        source = path.read_text(encoding="utf-8")

        # El harness corre Lua, no Luau: se desugara lo compuesto.
        out = []
        for line in source.split("\n"):
            m = re.match(r'^(\s*)([\w\.\[\]"\']+?)\s*(\+=|-=|\*=)\s*(.+)$', line)
            if m and not line.lstrip().startswith("--"):
                ind, lhs, op, rhs = m.groups()
                line = f"{ind}{lhs} = {lhs} {op[0]} ({rhs})"
            out.append(line)

        lua.globals().Provide(name, "\n".join(out))


def main():
    scenario = sys.argv[1] if len(sys.argv) > 1 else "ok"

    load_modules()

    Sections = lua.eval('Load("sections")')
    State = lua.eval('Load("state")')

    order = ["survival", "trainer", "items", "combat",
             "navigation", "movement", "visuals", "lobby"]

    for name in order:
        module = lua.eval(f'Load("{name}")')
        Sections.Declare(name, module)

    # En el escenario "broken" una sección revienta al cargar.
    if scenario == "broken":
        lua.eval('Load("combat")')["Setup"] = lua.eval(
            'function() error("explosión deliberada") end'
        )

    for name in order:
        Sections.Load(name)

    health = Sections.Health()
    failures = []

    print(f"  secciones: {health['healthy']}/{health['total']} sanas, "
          f"{health['broken']} rotas, {Sections.ConnectionCount()} conexiones")

    if scenario == "broken":
        if health["broken"] != 1:
            failures.append(f"esperaba 1 rota, hay {health['broken']}")
        others = [r for r in list(Sections.List().values()) if not r["error"]]
        if len(others) != 7:
            failures.append(f"se cayeron más secciones de las esperadas: {len(others)}")
    else:
        if health["broken"] != 0:
            for record in list(Sections.List().values()):
                if record["error"]:
                    print(f"    ROTA {record['name']}: {record['error']}")
            failures.append(f"{health['broken']} secciones rotas")

    # ── toggle: una bandera no cambia las de otra sección ──
    if scenario == "toggle":
        before = {s["key"]: s["value"] for s in list(State.Snapshot().values())}

        survival = Sections.Get("survival")
        survival.SetAutoHeal(True)
        survival.SetSemiGod(True)

        after = {s["key"]: s["value"] for s in list(State.Snapshot().values())}

        # Solo deben cambiar llaves de survival.
        touched = [k for k in after if after.get(k) != before.get(k)]
        bad = [k for k in touched if not k.startswith("survival.")]

        print(f"  llaves que cambiaron al tocar supervivencia: {touched}")

        if bad:
            failures.append(f"supervivencia tocó banderas ajenas: {bad}")

        if not after.get("survival.autoHeal"):
            failures.append("la bandera de supervivencia no se encendió")

        # Y al revés: combate no toca supervivencia.
        combat = Sections.Get("combat")
        combat.SetAuto(True)

        final = {s["key"]: s["value"] for s in list(State.Snapshot().values())}
        leaked = [k for k in final
                  if k.startswith("combat.") and not final[k]]
        if leaked:
            failures.append(f"combate no encendió sus banderas: {leaked}")

        if not final.get("survival.autoHeal"):
            failures.append("combate apagó la bandera de supervivencia")

    # ── restore: noclip y velocidad vuelven a su sitio ──
    if scenario == "restore":
        movement = Sections.Get("movement")

        movement.SetSpeed(64)
        movement.SetSpeedOn(True)
        movement.SetNoclip(True)

        lua.execute('Work.stepped().Fire()')

        speed_during = lua.eval("Work.humanoid().WalkSpeed")
        collide_during = lua.eval(
            '(function() for _,c in ipairs(GENV.__character.Children) do '
            'if c.Name=="HumanoidRootPart" then return c.CanCollide end end '
            'return true end)()'
        ) if lua.eval("GENV.__character") else None

        # Character directo desde Lua
        lua.execute('GENV.__character = game:GetService("Players").LocalPlayer.Character')

        collide_during = lua.eval(
            '(function() for _,c in ipairs(GENV.__character.Children) do '
            'if c.Name=="HumanoidRootPart" then return c.CanCollide end end '
            'return true end)()'
        )

        print(f"  durante: WalkSpeed={speed_during} CanCollide={collide_during}")

        if speed_during != 64:
            failures.append(f"la velocidad no se aplicó: {speed_during}")
        if collide_during:
            failures.append("el noclip no quitó la colisión")

        movement.SetSpeedOn(False)
        movement.SetNoclip(False)

        lua.execute('Work.stepped().Fire()')

        speed_after = lua.eval("Work.humanoid().WalkSpeed")
        collide_after = lua.eval(
            '(function() for _,c in ipairs(GENV.__character.Children) do '
            'if c.Name=="HumanoidRootPart" then return c.CanCollide end end '
            'return true end)()'
        )

        print(f"  al apagar: WalkSpeed={speed_after} CanCollide={collide_after}")

        if speed_after != 16:
            failures.append(f"la velocidad no volvió: {speed_after}")
        if not collide_after:
            failures.append("la colisión no volvió (quedas atravesando el mapa)")

    # ── hook: el interruptor tiene que sobrevivir al frame ──
    if scenario == "hook":
        survival = Sections.Get("survival")

        ok, detail = survival.SetSemiGod(True)
        print(f"  SetSemiGod -> {ok} | {detail}")

        if not ok:
            failures.append(f"el hook no se instaló: {detail}")

        # El Heartbeat corre justo después. Si el hook se apaga aquí,
        # el interruptor no dura ni un frame.
        lua.execute('Work.heartbeat().Fire()')

        # El hook ya no guarda copia: la bandera vive en state.
        still = State.Get("survival.semiGod", False)

        print(f"  tras un frame: semiGod={still}")

        if not still:
            failures.append("la bandera no sobrevivió al frame")

        # Y la prueba de verdad: el daño no debe pasar.
        damage = lua.execute("""
            local energy = EVENTS_FOLDER.Children[3]
            HOOK.method = "FireServer"
            Work.humanoid().Health = 100
            HOOK.fn(energy, -25, "Pizza")
            return Work.humanoid().Health
        """)

        print(f"  vida tras Energy(-25): {damage}")

        if damage != 100:
            failures.append(f"el semi godmode no bloqueó el daño: vida {damage}")

        # Apagado: el daño vuelve a entrar.
        survival.SetSemiGod(False)
        lua.execute('Work.heartbeat().Fire()')

        damage = lua.execute("""
            local energy = EVENTS_FOLDER.Children[3]
            HOOK.method = "FireServer"
            Work.humanoid().Health = 100
            HOOK.fn(energy, -25, "Pizza")
            return Work.humanoid().Health
        """)

        print(f"  vida tras apagar: {damage}")

        if damage >= 100:
            failures.append("al apagar el semi god el daño sigue bloqueado")

    # ── teardown: cerrar corta todo ──
    if scenario == "teardown":
        before = Sections.ConnectionCount()
        closed = Sections.DisconnectAll()

        lua.execute('Work.stepped().Fire()')
        lua.execute('Work.heartbeat().Fire()')

        after = Sections.ConnectionCount()

        print(f"  conexiones: {before} antes, {closed} cortadas, {after} quedan")

        if after != 0:
            failures.append(f"quedaron {after} conexiones abiertas")

        # Tras cerrar, tocar una bandera no debe mover nada.
        State.Set("movement.speed", True)
        lua.execute('Work.stepped().Fire()')

        if lua.eval("Work.humanoid().WalkSpeed") != 16:
            failures.append("un módulo descargado siguió aplicando cambios")

    print()
    if failures:
        print("FALLOS:")
        for f in failures:
            print("  ✖", f)
        sys.exit(1)

    print("AISLAMIENTO OK — 0 fallos")


if __name__ == "__main__":
    main()
