#!/usr/bin/env bash
# VANTA | Strongman Simulator — verificación completa.
set -uo pipefail

cd "$(dirname "$0")" || exit 1

fail=0
line() { printf '%s\n' "────────────────────────────────────────────────────────"; }

line
echo "1. Sintaxis de los 15 módulos"
line
if python3 ../vanta/tests/luacheck.py $(find src -name '*.lua' | sort) >/tmp/sm_syntax.log 2>&1; then
    echo "   15 archivos compilan"
else
    echo "   FALLO"
    grep -v '^OK' /tmp/sm_syntax.log | head -10
    fail=1
fi

line
echo "2. Recompilar el script único"
line
python3 build.py || fail=1

line
echo "3. Sintaxis del script único"
line
if python3 ../vanta/tests/luacheck.py ../StrongmanSimulator.lua >/tmp/sm_bundle.log 2>&1; then
    echo "   OK"
else
    echo "   FALLO"
    grep -v '^OK' /tmp/sm_bundle.log | head -5
    fail=1
fi

line
echo "4. Escenarios del juego"
line
for scenario in ok strength grind pull rejected esp teleport stop twice; do
    printf '   %-10s ' "$scenario"
    log=$(mktemp)
    timeout 120 python3 tests/smoketest.py "$scenario" >"$log" 2>&1

    if grep -q 'STRONGMAN OK' "$log"; then
        echo "OK"
    else
        echo "FALLA"
        grep '✖' "$log" | sed 's/^/       /' | head -3
        fail=1
    fi

    rm -f "$log"
done

line
echo "5. Sintaxis del loader"
line
if python3 ../vanta/tests/luacheck.py ../StrongmanLoader.lua >/tmp/sm_loader.log 2>&1; then
    echo "   OK"
else
    echo "   FALLO"
    grep -v '^OK' /tmp/sm_loader.log | head -5
    fail=1
fi

line
echo "6. Arranque (9 escenarios)"
line
for mode in ok pr404 neterr empty syntax runerr nostate wrongplace noplayer; do
    printf '   %-12s ' "$mode"
    log=$(mktemp)
    timeout 120 python3 tests/loadertest.py "$mode" >"$log" 2>&1

    if grep -q 'LOADER OK' "$log"; then
        echo "OK"
    else
        echo "FALLA"
        grep '✖' "$log" | sed 's/^/       /' | head -3
        fail=1
    fi

    rm -f "$log"
done

line
if [ "$fail" -eq 0 ]; then
    echo "TODO OK"
else
    echo "HAY FALLOS"
fi
line

exit "$fail"
