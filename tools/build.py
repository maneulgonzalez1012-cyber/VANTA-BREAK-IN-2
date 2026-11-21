#!/usr/bin/env python3
"""
VANTA — empaquetador.

Convierte src/ (17 archivos, un módulo por archivo) en UN solo script
ejecutable. El resultado no es una copia mezclada: es un cargador de
módulos que los mantiene separados en memoria.

Cómo lo hace
1. Cada archivo se guarda en una tabla `FILES` con su ruta.
2. Se instala un `require` propio que solo sirve esos archivos.
3. `script.Parent...` se reescribe a `require("core.player")`, que es
   exactamente lo que hacen los archivos en disco.
4. Nada de concatenar cuerpos: un error en un módulo no puede cortar
   el archivo de otro, porque cada uno se compila aparte al cargarse.

Uso:
    python3 tools/build.py            # escribe VANTA-BreakIn2.lua
    python3 tools/build.py --check    # solo verifica
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
OUT = ROOT / "VANTA-BreakIn2.lua"

BOOTSTRAP = r'''--[[
    VANTA | BREAK IN 2 — script único
    Generado por tools/build.py desde src/. No editar a mano.

    Cada módulo vive en su propia entrada de FILES y se compila por
    separado. Un módulo roto no impide que carguen los demás.
]]

local FILES = {}

local cache = {}
local loading = {}

local function loadModule(name)
    if cache[name] then
        return cache[name]
    end

    local source = FILES[name]

    if not source then
        error("módulo no empaquetado: " .. tostring(name), 0)
    end

    -- Ciclo: dos módulos que se piden entre sí. Se avisa, no se cuelga.
    if loading[name] then
        error("dependencia circular en " .. tostring(name), 0)
    end

    loading[name] = true

    local chunk, compileError = loadstring(source, "VANTA:" .. name)

    if not chunk then
        loading[name] = nil
        error(string.format("módulo %s no compila: %s", name, tostring(compileError)), 0)
    end

    local ok, result = pcall(chunk)

    loading[name] = nil

    if not ok then
        error(string.format("módulo %s falló al cargar: %s", name, tostring(result)), 0)
    end

    cache[name] = result

    return result
end

-- El require de los módulos resuelve contra FILES, no contra el juego.
local vanillaRequire = require

require = function(target)
    if type(target) == "string" and FILES[target] then
        return loadModule(target)
    end

    return vanillaRequire(target)
end

'''

FOOTER = r'''
-- ─── Arranque ──────────────────────────────────────────────

local ok, result = pcall(loadModule, "init")

if not ok then
    warn("[VANTA] arranque falló: " .. tostring(result))
    return nil
end

-- El loader comprueba esto antes de decir que todo salió bien.
getgenv().VANTA_BI2_STATE = result

return result
'''

REWRITES = [
    # require(script.Parent.Parent.core.player) -> require("core.player")
    (re.compile(r"require\(\s*script\.Parent\.Parent\.([\w\.]+)\s*\)"), r'require("\1")'),
    (re.compile(r"require\(\s*script\.Parent\.([\w\.]+)\s*\)"), r'require("\1")'),
    # require(script:WaitForChild("core"):WaitForChild("bus"))
    (
        re.compile(r'require\(\s*script:WaitForChild\("(\w+)"\):WaitForChild\("(\w+)"\)\s*\)'),
        r'require("\1.\2")',
    ),
    # script:WaitForChild("features")
    (re.compile(r'script:WaitForChild\("(\w+)"\)'), r'require("\1")'),
]

# El punto de entrada pide init; dentro de init el script es el nodo raíz.
INIT_EXTRAS = [
    (re.compile(r'local features = require\("features"\)'),
     'local features = require("features")'),
]


def module_name(path: pathlib.Path) -> str:
    """src/init.lua -> "init"; src/core/bus.lua -> "core.bus"."""
    rel = path.relative_to(SRC).with_suffix("")
    parts = list(rel.parts)

    # Un `init.lua` representa a su carpeta. En la raíz la carpeta es el
    # propio bundle, así que se queda como "init": si se dejara vacío,
    # el arranque pediría un módulo sin nombre y no lo encontraría.
    if parts[-1] == "init" and len(parts) > 1:
        parts = parts[:-1]

    return ".".join(parts)


def collect():
    files = {}
    for path in sorted(SRC.rglob("*.lua")):
        files[module_name(path)] = path
    return files


def transform(source: str) -> str:
    for pattern, replacement in REWRITES:
        source = pattern.sub(replacement, source)
    return source


def lua_string(text: str) -> str:
    """Lua long bracket string: no escapa nada."""
    level = 0
    while ("]" + "=" * level + "]") in text:
        level += 1
    open_b = "[" + "=" * level + "["
    close_b = "]" + "=" * level + "]"
    return open_b + "\n" + text.rstrip("\n") + "\n" + close_b


def main():
    check_only = "--check" in sys.argv

    files = collect()

    if not files:
        print("no hay archivos en src/")
        return 1

    parts = [BOOTSTRAP]
    total_bytes = 0

    for name, path in files.items():
        source = transform(path.read_text(encoding="utf-8"))
        total_bytes += len(source)
        # Asignación directa: es código, no una llamada. Cualquier
        # reescritura de `require` no puede tocarla.
        parts.append(f'FILES["{name}"] = {lua_string(source)}\n')

    parts.append(FOOTER)
    bundle = "".join(parts)

    if check_only:
        print(f"{len(files)} módulos, {total_bytes} bytes de código")
        for name in files:
            print("  ", name)
        return 0

    OUT.write_text(bundle, encoding="utf-8")

    print(f"{OUT.name}: {len(bundle)} bytes")
    print(f"  módulos empaquetados: {len(files)}")
    print(f"  código fuente: {total_bytes} bytes")
    print(f"  sobrecarga del cargador: {len(bundle) - total_bytes} bytes")

    return 0


if __name__ == "__main__":
    sys.exit(main())
