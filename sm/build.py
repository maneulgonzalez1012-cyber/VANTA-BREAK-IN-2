#!/usr/bin/env python3
"""
VANTA | Strongman Simulator — empaquetador.

Convierte sm/src/ (15 módulos, uno por archivo) en UN solo script
ejecutable. No concatena cuerpos: guarda cada módulo en su propia entrada de
`FILES` y lo compila aparte al cargarse, con un `require` propio.

Por qué así
    - un error de sintaxis en un módulo no impide que arranquen los otros
    - un `return` en un módulo no termina el script
    - dos módulos pueden usar el mismo nombre local sin chocar

Uso:
    python3 build.py           # escribe StrongmanSimulator.lua
    python3 build.py --check   # solo verifica
"""
import os
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent
SRC = ROOT / "src"
OUT = ROOT.parent / "StrongmanSimulator.lua"

BOOTSTRAP = r'''--[[
    VANTA | STRONGMAN SIMULATOR — script único
    Generado por sm/build.py desde sm/src/. No editar a mano.

    Cada módulo vive en su propia entrada de FILES y se compila por separado.
    Un módulo roto no impide que carguen los demás.
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

    if loading[name] then
        error("dependencia circular en " .. tostring(name), 0)
    end

    loading[name] = true

    local chunk, compileError = loadstring(source, "Strongman:" .. name)

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
    warn("[SM] arranque falló: " .. tostring(result))
    return nil
end

-- El loader comprueba esto antes de decir que todo salió bien.
getgenv().VANTA_STRONGMAN_STATE = result

return result
'''


def module_name(path: pathlib.Path) -> str:
    return path.relative_to(SRC).with_suffix("").as_posix().replace("/", ".")


def main() -> int:
    check_only = "--check" in sys.argv

    files = sorted(SRC.rglob("*.lua"), key=lambda p: (p.name != "init.lua", str(p)))

    if not files:
        print(f"no hay módulos en {SRC}", file=sys.stderr)
        return 1

    names = {}

    for path in files:
        name = module_name(path)

        if name in names:
            print(f"nombre duplicado: {name}", file=sys.stderr)
            return 1

        names[name] = path

    # init debe existir y ser único.
    if "init" not in names:
        print("falta init.lua", file=sys.stderr)
        return 1

    parts = [BOOTSTRAP]
    total = 0

    for name, path in names.items():
        source = path.read_text(encoding="utf-8")

        # Un módulo que cierre el bloque `[==[` rompería el empaquetado.
        if "]==]" in source:
            print(f"{path}: contiene ]==] y no se puede empaquetar", file=sys.stderr)
            return 1

        total += len(source)
        parts.append(f'FILES["{name}"] = [==[\n{source}\n]==]\n\n')

    parts.append(FOOTER)
    bundle = "".join(parts)

    if check_only:
        print(f"{len(names)} módulos, {total} bytes de código")
        return 0

    # Escritura atómica: un lector nunca ve el archivo a medias.
    temp = OUT.with_name(f"{OUT.name}.{os.getpid()}.tmp")

    with open(temp, "w", encoding="utf-8") as handle:
        handle.write(bundle)
        handle.flush()
        os.fsync(handle.fileno())

    os.replace(temp, OUT)

    print(f"{OUT.name}: {len(bundle)} bytes")
    print(f"  módulos empaquetados: {len(names)}")
    print(f"  código fuente: {total} bytes")
    print(f"  sobrecarga del cargador: {len(bundle) - total} bytes")

    return 0


if __name__ == "__main__":
    sys.exit(main())
