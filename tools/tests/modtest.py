"""
VANTA — banco de pruebas de aislamiento.

Monta un Roblox falso, carga los 9 módulos por separado y mide:
  1. Todos cargan.
  2. Un módulo que explota al cargar NO rompe a los demás.
  3. Dos módulos no pueden declarar la misma acción sin que se vea.
  4. Descargar un módulo solo mata SUS conexiones.
  5. Una acción que lanza devuelve ok=false, no propaga.
  6. Cerrar todo deja 0 conexiones y 0 restos.

Uso: python3 /tmp/modtest.py [ok|broken|conflict]
"""
import re
import sys
import pathlib

import lupa

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent / "src"

lua = lupa.LuaRuntime(unpack_returned_tuples=True, register_eval=False)

PRELUDE = r"""
-- ───────── Roblox falso ─────────
local function class(className, name)
    local inst = {}
    inst.ClassName = className
    inst.Name = name or className
    inst.Children = {}
    inst.Props = {}
    inst._conns = {}
    inst._signals = {}

    function inst:IsA(what)
        return self.ClassName == what
            or (what == "Instance")
            or (what == "BasePart" and self.ClassName == "Part")
            or (what == "BasePart" and self.ClassName == "MeshPart")
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
                table.insert(out, c)
                walk(c)
            end
        end
        walk(self)
        return out
    end

    function inst:Destroy()
        self.Parent = nil
        self.Destroyed = true
    end

    function inst:GetPropertyChangedSignal()
        return inst:Signal("propChanged")
    end

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
        return sig
    end

    inst.Changed = inst:Signal("Changed")
    inst.ChildAdded = inst:Signal("ChildAdded")
    inst.ChildRemoved = inst:Signal("ChildRemoved")
    inst.AncestryChanged = inst:Signal("Ancestry")

    inst.Position = setmetatable({Magnitude = 0, X = 0, Y = 0, Z = 0}, MT_POS)
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
    inst.Backing = {children = {}}

    function inst:UnequipTools() end
    function inst:ChangeState() end

    return inst
end

MT_POS = {
    __sub = function(a, b) return {Magnitude = 0, X = 0, Y = 0, Z = 0} end,
    __add = function(a, b) return {Magnitude = 0, X = 0, Y = 0, Z = 0} end,
}

CFrame = {}
function CFrame.new(a, b, c)
    if type(a) == "number" and b == nil then
        return {Position = {Magnitude = 0, X = a, Y = a, Z = a}, _cf = true}
    end
    return {Position = {Magnitude = 0, X = a or 0, Y = b or 0, Z = c or 0}, _cf = true}
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

-- Services
local services = {}
local function service(name)
    if not services[name] then
        services[name] = class("Service", name)
    end
    return services[name]
end

game = {
    PlaceId = 13864667823,
    GetService = function(self, name) return service(name) end,
    IsA = function() return false end,
}

-- Luau tiene table.clear / table.find; Lua 5.5 no.
function math.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

if not table.clear then
    function table.clear(t) for k in pairs(t) do t[k] = nil end end
end
if not table.find then
    function table.find(t, v)
        for i, x in ipairs(t) do if x == v then return i end end
        return nil
    end
end
if not table.create then
    function table.create(n, v)
        local t = {}
        for i = 1, (n or 0) do t[i] = v end
        return t
    end
end

task = {
    wait = function(t) return t or 0 end,
    spawn = function(fn, ...) fn(...) end,
    delay = function(_, fn) fn() end,
    defer = function(fn, ...) fn(...) end,
}

Enum = setmetatable({}, {
    __index = function(_, k) return setmetatable({}, {
        __index = function(_, k2) return k2 end
    }) end
})

-- Jugador
local players = service("Players")
local localPlayer = class("Player", "Tester")
localPlayer.Character = class("Model", "Tester")
localPlayer.DisplayName = "Tester"

local humanoid = class("Humanoid", "Humanoid")
humanoid.Health = 42
humanoid.MaxHealth = 100
addChild(localPlayer.Character, humanoid)

local root = class("Part", "HumanoidRootPart")
root.Position = {Magnitude = 0, X = 0, Y = 0, Z = 0}
addChild(localPlayer.Character, root)

local backpack = class("Backpack", "Backpack")
addChild(localPlayer, backpack)

players.LocalPlayer = localPlayer
players.PlayerAdded = players:Signal("PlayerAdded")
players.PlayerRemoving = players:Signal("PlayerRemoving")
function players:GetPlayers() return {localPlayer} end

-- RemoteEvents
local rs = service("ReplicatedStorage")
local events = class("Folder", "Events")
addChild(rs, events)

local names = {"GiveTool","Vending","Energy","HealTheNoobs",
               "RainbowWhatStat","HitBadguy","IceSlip"}
local fired = {}

for _, n in ipairs(names) do
    local re = class("RemoteEvent", n)
    function re:FireServer(...)
        local args = table.pack(...)
        table.insert(fired, {name = self.Name, args = args})

        -- Servidor falso: responde a lo que sabe responder.
        if REJECT_SERVER then return end
        if self.Name == "GiveTool" then
            local tool = class("Tool", args[1])
            addChild(backpack, tool)
        elseif self.Name == "Energy" then
            humanoid.Health = math.min(humanoid.Health + (tonumber(args[1]) or 0), humanoid.MaxHealth)
        elseif self.Name == "HitBadguy" and not MUTE_COMBAT then
            local target = args[1]
            if target and target._humanoid then
                target._humanoid.Health = 0
            end
        end
    end
    addChild(events, re)
end

Work = {}
function Work.fired() return fired end
function Work.humanoid() return humanoid end
function Work.backpack() return backpack end
function Work.localPlayer() return localPlayer end
function Work.service(n) return service(n) end

-- RunService
local runSvc = service("RunService")
runSvc.Heartbeat = runSvc:Signal("Heartbeat")
runSvc.Stepped = runSvc:Signal("Stepped")

local uis = service("UserInputService")
uis.JumpRequest = uis:Signal("JumpRequest")

-- NPCs de prueba
local badGuys = class("Folder", "BadGuys")
addChild(service("Workspace"), badGuys)

function SpawnNPC(health)
    local npc = class("Model", "BadGuy")
    local h = class("Humanoid", "Humanoid")
    h.Health = health or 100
    h.MaxHealth = 100
    addChild(npc, h)
    local p = class("Part", "HumanoidRootPart")
    addChild(npc, p)
    npc._humanoid = h
    npc.PrimaryPart = p
    addChild(badGuys, npc)
    return npc
end

function Work.SpawnNPC(h) return SpawnNPC(h) end

local lighting = service("Lighting")
local workspace = service("Workspace")

-- Dependencias que los módulos usan
hookmetamethod = nil
getnamecallmethod = nil
newcclosure = nil

REJECT_SERVER = REJECT_SERVER or false
MUTE_COMBAT = MUTE_COMBAT or false

-- ───────── require() por ruta ─────────
local sources = {}
function Provide(name, src) sources[name] = src end

local cache = {}
function VanillaRequire(name)
    if cache[name] then return cache[name] end
    local src = sources[name]
    if not src then error("módulo no provisto: " .. name) end
    local fn = assert(load(src, name))
    local result = fn()
    cache[name] = result
    return result
end

function VanillaClearCache() cache = {} end

-- El módulo llama require("lib.items") pero dentro de la prueba las
-- fuentes están en `sources`. Se engancha require al cargador falso.
local realRequire = require
require = function(name)
    if sources[name] then return VanillaRequire(name) end
    return realRequire(name)
end

Work.SpawnNPCFn = function(h) return SpawnNPC(h) end

return {
    Work = Work,
    SpawnNPC = Work.SpawnNPCFn,
    fired = fired,
    class = class,
    addChild = addChild,
    service = service,
    players = players,
    humanoid = humanoid,
    backpack = backpack,
    events = events,
}
"""


DESUGAR = re.compile(r'^(\s*)([\w\.\[\]"\']+?)\s*(\+=|-=|\*=|/=)\s*(.+)$')


def desugar(src):
    """Luau permite `x += 1`; Lua 5.5 no. Se reescribe para la prueba."""
    out = []
    for line in src.split("\n"):
        m = DESUGAR.match(line)
        if m and not line.lstrip().startswith("--"):
            ind, lhs, op, rhs = m.groups()
            line = f"{ind}{lhs} = {lhs} {op[0]} ({rhs})"
        out.append(line)
    return "\n".join(out)


def load_modules(scenario="ok"):
    """Carga cada .lua y reescribe require(script.Parent...) a rutas."""
    lua.execute(f"REJECT_SERVER = {'true' if scenario == 'reject' else 'false'}")
    lua.execute(f"MUTE_COMBAT = {'true' if scenario == 'mutecombat' else 'false'}")
    work = lua.execute(PRELUDE)
    provide = lua.globals().Provide

    for path in sorted(ROOT.rglob("*.lua")):
        rel = path.relative_to(ROOT).with_suffix("")
        name = ".".join(rel.parts)
        if name.endswith(".init"):
            name = name[: -len(".init")]
        src = desugar(path.read_text(encoding="utf-8"))
        # require(script.Parent.Parent.core.player) -> require("core.player")
        src = re.sub(
            r"require\(script\.Parent\.Parent\.([\w\.]+)\)",
            r'require("\1")',
            src,
        )
        src = re.sub(
            r"require\(script\:WaitForChild\(\"(\w+)\"\)\:WaitForChild\(\"(\w+)\"\)\)",
            r'require("\1.\2")',
            src,
        )
        provide(name, src)

    return work


def mod(work, name):
    return lua.globals().VanillaRequire(name)


def unpack2(res):
    """Registry.Run / Load devuelven (ejecutado, motivo, ...)."""
    if isinstance(res, tuple):
        return (bool(res[0]), res[1] if len(res) > 1 else None)
    return (bool(res), None)


def main():
    scenario = sys.argv[1] if len(sys.argv) > 1 else "ok"
    work = load_modules(scenario)

    Bus = mod(work, "core.bus")
    Registry = mod(work, "core.registry")
    Remotes = mod(work, "core.remotes")
    PlayerLib = mod(work, "core.player")

    order = [
        "survival", "trainer", "items", "combat",
        "navigation", "movement", "visuals", "lobby", "diagnostics",
    ]

    failures = []

    # ── 1. Declarar ──
    specs = {}
    for name in order:
        module = mod(work, "features." + name)
        spec = module["spec"]
        specs[name] = spec

        if scenario == "broken" and name == "combat":
            spec["setup"] = lua.eval("function(ctx) error('explosión deliberada') end")

        ok, _ = unpack2(Registry.Declare(spec))
        if not ok:
            failures.append(f"declarar {name} falló")

    # ── 2. Cargar ──
    load_results = {}
    for name in order:
        load_results[name] = unpack2(Registry.Load(name, Bus))

    if scenario == "broken":
        ok, err = load_results["combat"]
        if ok:
            failures.append("combat debía fallar al cargar y no falló")
        else:
            print(f"  combat roto como se esperaba: {err}")
        healthy = [n for n in order if load_results[n][0]]
        print(f"  módulos sanos con combat roto: {len(healthy)}/{len(order)}")
        if len(healthy) != len(order) - 1:
            failures.append(f"se cayeron más módulos de los esperados: {healthy}")
    else:
        for name in order:
            ok, err = load_results[name]
            if not ok:
                failures.append(f"cargar {name}: {err}")

    # ── 3. Conflicto de acciones ──
    if scenario == "conflict":
        thief = lua.table_from({
            "id": "thief",
            "name": "Ladrón",
            "kind": "remote",
            "tab": "X",
            "actions": lua.table_from({"heal": lambda state, amount: (True, "robado")}),
        })
        Registry.Declare(thief)
        conflicts = list(Registry.Conflicts().values())
        print(f"  conflictos detectados: {len(conflicts)}")
        if len(conflicts) != 1:
            failures.append("el conflicto de acción no se detectó")
        else:
            print(f"  -> {conflicts[0]['key']}: {conflicts[0]['first']} vs {conflicts[0]['second']}")

    # ── 4. Aislamiento de conexiones ──
    runSvc = work.service("RunService")
    before = len(list(runSvc.Stepped._list.values()))

    Registry.Unload("movement", Bus)
    after_move = len(list(runSvc.Stepped._list.values()))
    after_visuals = len(list(runSvc.Stepped._list.values()))

    print(f"  conexiones Stepped: antes {before} | tras descargar movement {after_move}")

    if after_move != before - 1:
        failures.append(
            f"descargar movement debía cerrar 1 conexión Stepped ({before} -> {after_move})"
        )

    # visuals sigue vivo tras descargar movement
    if not Registry.Get("visuals")["loaded"]:
        failures.append("visuals murió al descargar movement")

    # ── 5. Acción que lanza no propaga ──
    bad = lua.table_from({
        "id": "bad",
        "name": "Malo",
        "kind": "remote",
        "tab": "X",
        "actions": lua.table_from({
            "boom": lua.eval("function(state, x) error('acción explosiva') end")
        }),
    })
    Registry.Declare(bad)
    Registry.Load("bad", Bus)

    ok, result = unpack2(Registry.Run("bad", "boom", Bus, 1))
    print(f"  acción que lanza -> ok={ok} motivo={result}")
    if ok:
        failures.append("una acción que lanza devolvió ok=true")
    if not str(result).find("explosiva"):
        failures.append("el motivo del fallo no se conservó")
    if Bus.ErrorCount("bad:boom") < 1:
        failures.append("el Bus no registró el error de la acción")

    # ── 6. Acción normal ejecuta y verifica ──
    ok, result = unpack2(Registry.Run("survival", "heal", Bus, 25))
    print(f"  survival.heal -> ok={ok} | {result}")

    if scenario in ("ok", "conflict") and not str(result).startswith("+"):
        failures.append(f"el motivo de heal no es legible: {result!r}")

    if scenario in ("ok", "conflict"):
        if not ok:
            failures.append(f"heal con servidor falso debía funcionar: {result}")
        health = work["humanoid"].Health
        if health <= 42:
            failures.append(f"la vida no subió: {health}")

    ok, result = unpack2(Registry.Run("items", "give", Bus, "Golden Apple"))
    print(f"  items.give -> ok={ok} | {result}")

    if scenario == "reject":
        # Nada debe reportarse como ejecutado si el servidor no respondió.
        if ok:
            failures.append(f"give reportó éxito con el servidor mudo: {result!r}")
        if "no llegó" not in str(result):
            failures.append(f"el motivo no dice que no llegó: {result!r}")

        heal_ok, heal_detail = unpack2(Registry.Run("survival", "heal", Bus, 25))
        if heal_ok:
            failures.append(f"heal reportó éxito con el servidor mudo: {heal_detail!r}")
        if "no movió la vida" not in str(heal_detail):
            failures.append(f"el motivo de heal no es honesto: {heal_detail!r}")

        # La vida no debe haber cambiado
        if work["humanoid"].Health != 42:
            failures.append(f"la vida cambió sin servidor: {work['humanoid'].Health}")

        # Y el cliente NO debe haber fingido quitar vida a un NPC
        hit_ok, hit_detail = unpack2(Registry.Run("combat", "hitAll", Bus))
        print(f"  combat.hitAll (servidor mudo) -> ok={hit_ok} | {hit_detail}")
    elif scenario != "broken" and "Golden Apple" not in str(result):
        failures.append(f"el motivo de give no nombra el objeto: {result!r}")

    # Instrumentación temporal del callback para ver si se ejecuta
    lua.execute("""
        local mv = VanillaRequire("features.movement")
        local oldSetup = mv.spec.setup
    """)

    # ── 6a. Restauración al descargar movement ──
    if scenario in ("ok", "conflict"):
        # El paso 4 descargó movement: se recarga para probar la restauración.
        Registry.Load("movement", Bus)
        Registry.Run("movement", "setSpeed", Bus, True)
        Registry.Run("movement", "setNoclip", Bus, True)

        # `Stepped:Fire()` debe lanzarse desde Lua: invocado desde Python
        # no llega a los callbacks del mock.
        lua.execute('Work.service("RunService").Stepped:Fire()')

        # Se lee siempre a través de Lua: lupa devuelve una tabla nueva por
        # llamada y una copia vieja del Humanoid muestra valores obsoletos.
        speed_during = lua.eval("Work.humanoid().WalkSpeed")
        collide_during = lua.eval("""
            (function()
                for _, c in ipairs(Work.localPlayer().Character.Children) do
                    if c.Name == "HumanoidRootPart" then return c.CanCollide end
                end
                return true
            end)()
        """)

        print(f"  durante: WalkSpeed={speed_during} CanCollide={collide_during}")

        if speed_during != 32:
            failures.append(f"la velocidad no se aplicó: {speed_during}")
        if collide_during:
            failures.append("el noclip no quitó la colisión")

        # Descargar el módulo debe devolver TODO, no solo desconectar.
        Registry.Unload("movement", Bus)
        lua.execute('Work.service("RunService").Stepped:Fire()')

        speed_after = lua.eval("Work.humanoid().WalkSpeed")
        collide_after = lua.eval("""
            (function()
                for _, c in ipairs(Work.localPlayer().Character.Children) do
                    if c.Name == "HumanoidRootPart" then return c.CanCollide end
                end
                return true
            end)()
        """)

        print(f"  tras descargar: WalkSpeed={speed_after} CanCollide={collide_after}")

        if speed_after != 16:
            failures.append(f"la velocidad no se restauró: {speed_after}")
        if not collide_after:
            failures.append("la colisión no se restauró (te quedas atravesando el mapa)")

        # Un módulo descargado ya no puede tocar nada.
        Registry.Run("movement", "setSpeed", Bus, True)
        lua.execute('Work.service("RunService").Stepped:Fire()')

        if lua.eval("Work.humanoid().WalkSpeed") != 16:
            failures.append("un módulo descargado siguió aplicando velocidad")

    # ── 6b. Combate con NPCs presentes ──
    npc = work.SpawnNPC(100)
    hit_ok, hit_detail = unpack2(Registry.Run("combat", "hitAll", Bus))
    alive = npc._humanoid.Health > 0
    print(f"  combat.hitAll -> ok={hit_ok} | {hit_detail} | vida NPC {npc._humanoid.Health}")

    if scenario == "mutecombat":
        # El servidor no hace nada; el cliente sí puede escribir Health=0.
        # Eso NO puede reportarse como ejecutado.
        if hit_ok:
            failures.append(
                f"combat reportó éxito con el servidor mudo: {hit_detail!r}"
            )
        if "solo" not in str(hit_detail) and "no bajó" not in str(hit_detail):
            failures.append(f"el motivo no distingue local de servidor: {hit_detail!r}")
    elif scenario == "broken":
        # combat está roto a propósito: ni se intenta.
        if npc._humanoid.Health != 100:
            failures.append("un módulo roto movió la vida del NPC")
    elif scenario == "reject":
        # Con todos los remotos mudos, el cliente sí puede matar localmente,
        # pero entonces NO debe reportarse como ejecutado.
        if hit_ok:
            failures.append(f"combat reportó éxito con el servidor mudo: {hit_detail!r}")
        if "solo" not in str(hit_detail) and "no bajó" not in str(hit_detail):
            failures.append(f"el motivo no distingue local de servidor: {hit_detail!r}")
    else:
        if not hit_ok:
            failures.append(f"combat debía dañar al NPC: {hit_detail!r}")
        if alive:
            failures.append("el NPC sigue vivo tras el ataque")

    # ── 7. Cierre total ──
    for name in reversed(list(order)):
        Registry.Unload(name, Bus)
    Bus.DisconnectAll()

    snap = Bus.Snapshot()
    print(f"  tras cerrar: conexiones {snap['connections']} | errores {snap['total']}")
    if snap["connections"] != 0:
        failures.append(f"quedaron {snap['connections']} conexiones abiertas")

    print()
    if failures:
        print("FALLOS:")
        for f in failures:
            print("  ✖", f)
        sys.exit(1)

    print("AISLAMIENTO OK — 0 fallos")


if __name__ == "__main__":
    main()
