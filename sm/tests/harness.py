
import pathlib
import re
import sys

import lupa

ROOT = pathlib.Path(__file__).resolve().parent.parent
BUNDLE = ROOT.parent / "StrongmanSimulator.lua"

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

    function inst:GetFullName()
        local names = {self.Name}
        local node = self.Parent

        while node do
            table.insert(names, 1, node.Name)
            node = node.Parent
        end

        return table.concat(names, ".")
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
        sig.count = function() return #list end
        return sig
    end

    function inst:UnequipTools() end
    function inst:ChangeState() end

    -- CFrame va por metamétodo, no como campo normal, para que el banco
    -- pueda reaccionar cuando una pieza se mueve (como hace el juego).
    inst._cframe = MAKE_CFRAME(MAKE_POSITION(0, 0, 0))

    local baseMeta = getmetatable(inst) or {}

    baseMeta.__index = function(self, key)
        if key == "CFrame" then return rawget(self, "_cframe") end

        -- En Roblox, Position es el CFrame.Position. Si fuera un campo aparte
        -- se quedaría congelado y cualquier medida de distancia mentiría.
        if key == "Position" then
            local cf = rawget(self, "_cframe")
            return cf and cf.Position
        end

        -- Los métodos viven en la propia tabla: no hay que taparlos.
        return rawget(self, key)
    end

    baseMeta.__newindex = function(self, key, value)
        if key == "Parent" then
            rawset(self, "Parent", value)

            if value then
                local list = rawget(value, "Children") or {}
                rawset(value, "Children", list)

                local already = false

                for _, child in ipairs(list) do
                    if child == self then already = true break end
                end

                if not already then
                    table.insert(list, self)
                end
            end

            return
        end

        if key == "CFrame" then
            rawset(self, "_cframe", value)

            if CF_FRAME_HOOK then
                CF_FRAME_HOOK(self, value)
            end

            return
        end

        rawset(self, key, value)
    end

    setmetatable(inst, baseMeta)
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

-- Un CFrame con Position de verdad. Si `.Position` devolviera una función,
-- comparar posiciones en el script fallaría por culpa del banco.
function MAKE_POSITION(x, y, z)
    local p = {X = x or 0, Y = y or 0, Z = z or 0}

    p.Magnitude = math.sqrt(p.X * p.X + p.Y * p.Y + p.Z * p.Z)

    setmetatable(p, {
        __sub = function(a, b)
            return MAKE_POSITION(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
        end,
    })

    return p
end

function MAKE_CFRAME(position)
    local cf = {Position = position}

    setmetatable(cf, {
        __mul = function(self, other)
            -- CFrame * CFrame desplaza; el banco solo necesita la posición.
            if other and other.Position then
                return MAKE_CFRAME(MAKE_POSITION(
                    self.Position.X + other.Position.X,
                    self.Position.Y + other.Position.Y,
                    self.Position.Z + other.Position.Z
                ))
            end

            return self
        end,
        __add = function(self, vector)
            if vector and vector.Y then
                return MAKE_CFRAME(MAKE_POSITION(
                    self.Position.X,
                    self.Position.Y + vector.Y,
                    self.Position.Z
                ))
            end

            return self
        end,
    })

    return cf
end

CFrame = {}
function CFrame.new(a, b, c)
    return MAKE_CFRAME(MAKE_POSITION(a or 0, b or 0, c or 0))
end
setmetatable(CFrame, {__mul = function() return CFrame.new(0, 0, 0) end})
Vector3 = {new = function(x,y,z) return {X=x or 0,Y=y or 0,Z=z or 0} end}
Color3 = {fromRGB = function(r,g,b) return {r=r,g=g,b=b} end}

Instance = {}
function Instance.new(cls, parent)
    local inst = class(cls, cls)
    if parent then
        inst.Parent = parent
        table.insert(parent.Children, inst)
    end
    return inst
end

local function addChild(parent, child)
    child.Parent = parent
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
localPlayer.UserId = 1

local humanoid = class("Humanoid", "Humanoid")
humanoid.Health = 42
humanoid.MaxHealth = 100
addChild(localPlayer.Character, humanoid)
addChild(localPlayer.Character, class("Part", "HumanoidRootPart"))
addChild(localPlayer, class("Backpack", "Backpack"))

players.LocalPlayer = localPlayer
players.PlayerAdded = players:Signal("PlayerAdded")
players.PlayerRemoving = players:Signal("PlayerRemoving")
function players:GetPlayers()
    local list = {localPlayer}
    for _, child in ipairs(self.Children) do
        if child.ClassName == "Player" then table.insert(list, child) end
    end
    return list
end

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

MKCLASS = class
Work = {}
Work.humanoid = function() return humanoid end
Work.stepped = function() return runSvc.Stepped end
Work.heartbeat = function() return runSvc.Heartbeat end
Work.fired = function() return FIRED end
Work.ClearFired = function() FIRED = {} end

-- ─── Strongman Simulator: mundo propio ──────────────────────────────────

-- Stats del jugador, como los expone el juego.
local stats = class("Folder", "leaderstats")
local strength = class("IntValue", "Strength")
strength.Value = 120
local energy = class("IntValue", "Energy")
energy.Value = 5000
addChild(stats, strength)
addChild(stats, energy)
addChild(localPlayer, stats)

-- Áreas: gimnasio con su WorkoutStation y una zona de arrastre con Goal.
local areas = class("Folder", "Areas")
addChild(service("Workspace"), areas)

local area1 = class("Folder", "Area1_Gym")
addChild(areas, area1)

local gym = class("Folder", "Gym")
addChild(area1, gym)

local equip = class("Folder", "TrainingEquipment")
addChild(gym, equip)

local station = class("Folder", "WorkoutStation")
addChild(equip, station)

local collider = class("Part", "Collider")
addChild(station, collider)

local prompt = class("ProximityPrompt", "Prompt")
prompt.HoldDuration = 0
addChild(station, prompt)

local retro = class("Folder", "Area14_Retro")
addChild(areas, retro)

local draggables = class("Folder", "DraggableItems")
addChild(retro, draggables)

local pyramid = class("MeshPart", "Pyramid")
addChild(draggables, pyramid)

local title = class("StringValue", "Title")
title.Value = "PYRAMID"
addChild(pyramid, title)

local interaction = class("BasePart", "InteractionPoint")
addChild(pyramid, interaction)

local goal = class("Part", "Goal")
goal.CFrame = CFrame.new(240, 35, 8090)
addChild(retro, goal)

local playerDrags = class("Folder", "PlayerDraggables")
addChild(service("Workspace"), playerDrags)

local myDrags = class("Folder", tostring(localPlayer.UserId or 1))
addChild(playerDrags, myDrags)
myDrags.DescendantAdded = myDrags:Signal("DescendantAdded")

-- El remoto de fuerza: RemoteFunction, cuelga de ReplicatedStorage.
local upgrade = class("RemoteFunction", "StrongMan_UpgradeStrength")

function upgrade:InvokeServer(multiplier)
    table.insert(FIRED, {name = self.Name, args = table.pack(multiplier)})

    if CLOSED then
        error("el servidor rechazó la llamada", 0)
    end

    local gain = 5
    if type(multiplier) == "number" then
        -- El servidor real acota; el banco imita ese tope.
        gain = 5 * math.min(multiplier, 100)
    end

    strength.Value = strength.Value + math.floor(gain)
    return strength.Value
end

addChild(rs, upgrade)

-- Contadores del banco
CLOSED = false

-- El juego premia con energía cuando una pieza cruza la línea. El banco lo
-- imita para poder comprobar que el script lo detecta.
CF_FRAME_HOOK = function(part, value)
    if part.Name ~= "Crate" then return end
    if not value or not value.Position then return end

    -- Paga cuando la pieza llega a la meta. Se busca el Goal en el mundo
    -- cada vez: capturarlo antes de que exista lo dejaría en nil.
    local goalPart = GOAL_PART

    if goalPart == nil then
        local areas = game:GetService("Workspace"):FindFirstChild("Areas")

        if areas then
            for _, area in ipairs(areas:GetChildren()) do
                local goal = area:FindFirstChild("Goal")

                if goal then goalPart = goal end
            end
        end
    end

    if goalPart and value.Position.X == goalPart.CFrame.Position.X then
        energy.Value = energy.Value + 250
    end
end
STRENGTH_VALUE = function() return strength.Value end
ENERGY_VALUE = function() return energy.Value end
STRENGTH_OBJ = strength
ENERGY_OBJ = energy
UPGRADE_REMOTE = upgrade
GYM_PROMPT = prompt
GOAL_PART = goal
PYRAMID_PART = pyramid
MY_DRAGS = myDrags

-- ─── Rayfield falso con contadores ──────────────────────────────────────
UI = {window = nil, tabs = {}, buttons = 0, toggles = {}}

local function makeWindow(config)
    UI.window = config and config.name or "?"
    WORK_LIVE = (WORK_LIVE or 0) + 1

    local win = {}

    function win:CreateTab(props)
        table.insert(UI.tabs, props.name)
        local tab = {Name = props.name}

        function tab:CreateButton(p)
            UI.buttons = UI.buttons + 1
            local b = {Name = p.name}
            function b:Fire()
                if p.callback then p.callback() end
            end
            return b
        end

        function tab:CreateToggle(p)
            local t = {Name = p.name}
            UI.toggles[p.name] = p
            function t:Fire(v)
                if p.callback then p.callback(v) end
            end
            function t:Set(v) if p.callback then p.callback(v) end end
            return t
        end

        function tab:CreateSlider(p)
            local s = {Name = p.name}
            function s:Set(v) if p.callback then p.callback(v) end end
            return s
        end

        function tab:CreateInput(p)
            local i = {Name = p.name}
            function i:Set(v) if p.callback then p.callback(v) end end
            return i
        end

        function tab:CreateDropdown(p)
            local d = {Name = p.name}
            function d:Set(v) if p.callback then p.callback(v) end end
            function d:Refresh() end
            return d
        end

        function tab:CreateSection() return {} end
        function tab:CreateText() return {} end

        return tab
    end

    function win:Notify() end
    function win:Unload()
    if not self.Unloaded then
        self.Unloaded = true
        WORK_LIVE = (WORK_LIVE or 1) - 1
    end
end

    return win
end

RAYFIELD_FAKE = {
    CreateWindow = function(self, config) return makeWindow(config) end,
}

function UI.FireToggle(name)
    local t = UI.toggles[name]
    if not t then return false end
    if t.callback then t.callback(not t.value) end
    return true
end
"""


def desugar(source):
    """El banco corre Lua, no Luau: se deshacen los operadores compuestos."""
    pattern = re.compile(r"^(\s*)([\w\.\[\]\"']+?)\s*(\+=|-=|\*=|/=)\s*(.+)$")
    out = []
    for line in source.split("\n"):
        m = pattern.match(line)
        if m and not line.lstrip().startswith("--"):
            ind, lhs, op, rhs = m.groups()
            line = f"{ind}{lhs} = {lhs} {op[0]} ({rhs})"
        out.append(line)
    return "\n".join(out)


def boot(script_name="StrongmanSimulator.lua"):
    lua = lupa.LuaRuntime(unpack_returned_tuples=True, register_eval=False)
    lua.execute(PRELUDE)

    source = desugar((ROOT.parent / script_name).read_text(encoding="utf-8"))
    lua.execute("BUNDLE_SRC = [====[\n" + source + "\n]====]")

    lua.execute("""
        loadstring = function(chunk, name)
            if chunk == "--RAYFIELD--" then
                return function() return RAYFIELD_FAKE end
            end
            return load(chunk, name)
        end
        game.HttpGet = function(_, url) return "--RAYFIELD--" end
    """)

    runner = lua.execute(
        "return function() "
        "  local fn, err = loadstring(BUNDLE_SRC, 'Strongman:bundle')"
        "  if not fn then return false, 'COMPILA: ' .. tostring(err) end"
        "  local ok, res = pcall(fn)"
        "  if not ok then return false, 'ARRANCA: ' .. tostring(res) end"
        "  return true, res "
        "end"
    )

    result = runner()
    result = result if isinstance(result, tuple) else (result,)
    ok = bool(result[0])
    detail = result[1] if len(result) > 1 else None

    return lua, ok, detail


def count(lua, what):
    return lua.eval(f"UI.{what}")
